import 'dart:io';
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:isar_community/isar.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/config/env.dart';
import '../device/home_widgets.dart';
import '../device/notifications.dart';
import '../local/isar/comment_local.dart';
import '../local/isar/date_idea_local.dart';
import '../local/isar/note_local.dart';
import '../local/isar/post_local.dart';
import '../local/isar/special_date_local.dart';
import '../local/isar/status_local.dart';
import '../local/isar_service.dart';
import '../local/user_cache.dart';
import '../remote/api_client.dart';
import '../remote/endpoints.dart';
import '../remote/token_storage.dart';
import 'status_photo_cache.dart';
import 'sync_prefs.dart';

class SyncWorker {
  static const taskId = 'alma.sync.batch';
  static const taskName = 'alma-sync-batch';
}

/// WorkManager entrypoint — runs in its own isolate, so no shared state with UI.
@pragma('vm:entry-point')
void syncCallbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    if (task != SyncWorker.taskName) return true;
    try {
      await _runSync();
      return true;
    } catch (_) {
      return false; // WorkManager will retry per its backoff
    }
  });
}

Future<void> _runSync() async {
  // Background isolates don't get the plugin registrant for free; without this
  // secure storage, notifications and the widget bridge are all unavailable.
  DartPluginRegistrant.ensureInitialized();

  final conn = await Connectivity().checkConnectivity();
  if (conn.contains(ConnectivityResult.none)) return;

  final token = await TokenStorage.read();
  if (token == null) return;

  final dio = Dio(
    BaseOptions(
      baseUrl: Env.apiBaseUrl,
      headers: {'Authorization': 'Bearer $token'},
      sendTimeout: const Duration(minutes: 2),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  // "Sync only on Wi-Fi" is about not burning mobile data on photo and video
  // *uploads*. It must not gate the few KB of JSON below: doing that meant no
  // partner notifications at all on mobile data, since the preference is on
  // by default.
  final wifiOnly = await SyncPrefs.wifiOnly();
  final onWifi =
      conn.contains(ConnectivityResult.wifi) ||
      conn.contains(ConnectivityResult.ethernet);

  if (!wifiOnly || onWifi) {
    final isar = await IsarService.openForIsolate();

    // Recover uploads that were interrupted mid-flight last time.
    await _reviveStalled(isar);

    await _pushEverything(isar, dio);
  }

  // With the app closed there is no WebSocket, so this tick is what surfaces
  // the partner's activity and keeps the home-screen widget current. Always
  // runs, on any connection.
  await _notifyPartnerActivity(dio);
}

/// Push every kind of pending row, in order, isolating each step.
///
/// One shared pipeline for the background isolate and the foreground call so
/// the two lists can't drift. Each step is wrapped: a step that throws (a
/// timeout on the notes batch, say) used to abort everything queued behind it
/// — posts, comments, special dates and citas all silently waited for the next
/// tick because one request failed.
Future<void> _pushEverything(Isar isar, Dio dio) async {
  final myId = (await UserCache.read())?.me.id;
  await _step(() => _syncNotes(isar, dio));
  await _step(() => _syncNoteMutations(isar, dio, myId));
  await _step(() => _syncStatus(isar, dio));
  await _step(() => _syncPosts(isar, dio));
  await _step(() => _syncPostMutations(isar, dio));
  await _step(() => _syncComments(isar, dio));
  await _step(() => _syncSpecialDates(isar, dio));
  await _step(() => _syncDateIdeas(isar, dio));
}

/// Run one step of the pipeline, keeping its failure to itself. Anything that
/// didn't go up stays flagged in Isar and is retried on the next tick.
Future<void> _step(Future<void> Function() body) async {
  try {
    await body();
  } catch (_) {
    // Best effort by design — see [_pushEverything].
  }
}

/// Poll for partner activity and raise a notification for anything new.
///
/// Markers hold the timestamp of the last item we already announced; the very
/// first run only records them, so installing the app never fires a burst of
/// notifications about old content.
Future<void> _notifyPartnerActivity(Dio dio) async {
  final session = await UserCache.read();
  final myId = session?.me.id;
  if (myId == null) return;
  final partnerName = session?.partner?.prettyName;

  // Status ("siente").
  try {
    final res = await dio.get(Endpoints.status);
    final partner = _newestFrom(res.data['statuses'], myId, 'updated_at');
    final text = partner?['text']?.toString().trim() ?? '';
    final stamp = partner?['updated_at']?.toString() ?? '';
    final photoUrl = partner?['image_url']?.toString();
    if ((text.isNotEmpty || (photoUrl ?? '').isNotEmpty) && stamp.isNotEmpty) {
      if (await _isNewSince('status', stamp)) {
        await Notifications.partnerStatus(
          partnerName,
          text.isEmpty ? 'Te compartió una instantánea' : text,
        );
      }
      // Pass the snapshot along: pushing without it used to blank the photo
      // out of the widget on every background tick.
      await HomeWidgets.pushStatus(
        author: partnerName,
        text: text,
        photoPath: await cacheStatusPhotoWith(dio, photoUrl),
        at: DateTime.tryParse(stamp)?.toLocal(),
      );
    }
  } catch (_) {
    /* offline or server down — try again next tick */
  }

  // Diary entries.
  try {
    final res = await dio.get(Endpoints.notes);
    final note = _newestFrom(res.data['notes'], myId, 'created_at');
    final stamp = note?['created_at']?.toString() ?? '';
    if (stamp.isNotEmpty && await _isNewSince('note', stamp)) {
      await Notifications.partnerNote(
        partnerName,
        note?['body']?.toString() ?? '',
      );
    }
  } catch (_) {
    /* ignore */
  }

  // Feed posts.
  try {
    final res = await dio.get(Endpoints.posts);
    final post = _newestFrom(res.data['posts'], myId, 'created_at');
    final stamp = post?['created_at']?.toString() ?? '';
    if (stamp.isNotEmpty && await _isNewSince('post', stamp)) {
      await Notifications.partnerPost(
        partnerName,
        post?['title']?.toString() ?? '',
      );
    }
  } catch (_) {
    /* ignore */
  }
}

/// Newest entry in [raw] not authored by [myId], by the [field] timestamp.
Map<String, dynamic>? _newestFrom(dynamic raw, String myId, String field) {
  if (raw is! List) return null;
  Map<String, dynamic>? best;
  DateTime? bestAt;
  for (final item in raw) {
    if (item is! Map) continue;
    final j = Map<String, dynamic>.from(item);
    if (j['author_id']?.toString() == myId) continue;
    final at = DateTime.tryParse(j[field]?.toString() ?? '');
    if (at == null) continue;
    if (bestAt == null || at.isAfter(bestAt)) {
      best = j;
      bestAt = at;
    }
  }
  return best;
}

/// True when [stamp] is newer than what we last announced for [kind]. Always
/// records the stamp; returns false on the first ever call (baseline only).
Future<bool> _isNewSince(String kind, String stamp) async {
  final seen = await SyncPrefs.marker(kind);
  if (seen == stamp) return false;
  await SyncPrefs.setMarker(kind, stamp);
  return seen != null;
}

/// Foreground push of everything pending. Called from the UI right after the
/// user creates content and on app resume, so uploads reach the partner in
/// seconds instead of waiting for the 15-minute background tick. Reuses the
/// app's already-open Isar and the authenticated [ApiClient].
Future<void> runForegroundSync() async {
  if (await TokenStorage.read() == null) return;
  final Isar isar;
  try {
    isar = IsarService.instance.db;
  } catch (_) {
    return; // Isar not open yet — nothing to do.
  }
  final dio = ApiClient.instance.dio;
  try {
    // While the user is actively here, give stuck *and* previously-failed
    // uploads a fresh chance.
    await _reviveStalled(isar, includeFailed: true);
    await _pushEverything(isar, dio);
  } catch (_) {
    // Best-effort; the periodic worker retries later.
  }
}

/// Reset uploads left mid-flight (`syncing`) — and optionally ones that hit the
/// retry cap (`failed`) — back to `pending` so they get picked up again instead
/// of getting stuck forever.
Future<void> _reviveStalled(Isar isar, {bool includeFailed = false}) async {
  final stalled = <PostLocal>[
    ...await isar.postLocals.filter().syncStatusEqualTo('syncing').findAll(),
    if (includeFailed)
      ...await isar.postLocals.filter().syncStatusEqualTo('failed').findAll(),
  ];
  if (stalled.isEmpty) return;
  await isar.writeTxn(() async {
    for (final p in stalled) {
      p.syncStatus = 'pending';
      await isar.postLocals.put(p);
    }
  });
}

Future<void> _syncComments(Isar isar, Dio dio) async {
  final pending = await isar.commentLocals
      .filter()
      .syncStatusEqualTo('pending')
      .limit(Env.syncBatchSize)
      .findAll();
  for (final c in pending) {
    try {
      // Route by target: a diary comment posted to the feed route was stored
      // against a post id, never broadcast and never read back — while the
      // client happily marked it synced.
      final res = await dio.post(
        Endpoints.commentsFor(c.targetType, c.postId),
        data: {'body': c.text},
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        await isar.writeTxn(() async {
          c
            ..remoteId =
                (res.data['comment']?['id'] ?? res.data['comment']?['_id'])
                    ?.toString()
            ..syncStatus = 'synced';
          await isar.commentLocals.put(c);
        });
      }
    } catch (_) {
      // Stays pending for the next tick.
    }
  }
}

Future<void> _syncNotes(Isar isar, Dio dio) async {
  final pending = await isar.noteLocals
      .filter()
      .syncStatusEqualTo('pending')
      .limit(Env.syncBatchSize)
      .findAll();
  if (pending.isEmpty) return;

  // Upload each note's photos/video first (once — the remote URLs are saved on
  // the row so a retry never re-uploads), then send the note with all its rich
  // fields. Previously only the text body was synced, so photos/video/location/
  // mood were silently dropped.
  final payload = <Map<String, dynamic>>[];
  for (final n in pending) {
    if (n.remoteImageUrls.isEmpty && n.imagePaths.isNotEmpty) {
      final urls = <String>[];
      for (final path in n.imagePaths) {
        final url = await _uploadFile(dio, path);
        if (url != null) urls.add(url);
      }
      if (urls.isNotEmpty) {
        await isar.writeTxn(() async {
          n.remoteImageUrls = urls;
          await isar.noteLocals.put(n);
        });
      }
    }
    if (n.remoteVideoUrls.isEmpty && n.videoPaths.isNotEmpty) {
      final urls = <String>[];
      for (final path in n.videoPaths) {
        final url = await _uploadFile(dio, path);
        if (url != null) urls.add(url);
      }
      if (urls.isNotEmpty) {
        await isar.writeTxn(() async {
          n.remoteVideoUrls = urls;
          await isar.noteLocals.put(n);
        });
      }
    }
    // Legacy single-video entries created before multi-video support.
    if (n.remoteVideoUrl == null && n.videoPath != null) {
      final url = await _uploadFile(dio, n.videoPath!);
      if (url != null) {
        await isar.writeTxn(() async {
          n.remoteVideoUrl = url;
          await isar.noteLocals.put(n);
        });
      }
    }
    if (n.remoteAudioUrl == null && n.audioPath != null) {
      final url = await _uploadFile(dio, n.audioPath!);
      if (url != null) {
        await isar.writeTxn(() async {
          n.remoteAudioUrl = url;
          await isar.noteLocals.put(n);
        });
      }
    }

    payload.add({
      'client_id': n.isarId.toString(),
      'body': n.body,
      'author_id': n.authorId,
      // Always ship UTC ("Z" suffix) — a zone-less local timestamp fails the
      // server's ISO8601 parse and silently falls back to "now", which is how
      // entries/dates ended up on the wrong day.
      'created_at': n.createdAt.toUtc().toIso8601String(),
      'mood': n.mood,
      'link': n.link,
      'private': n.isPrivate,
      'image_urls': n.remoteImageUrls,
      'video_urls': n.remoteVideoUrls,
      'video_url': n.remoteVideoUrl,
      'audio_url': n.remoteAudioUrl,
      'latitude': n.latitude,
      'longitude': n.longitude,
      'place_label': n.placeLabel,
      'reaction_emoji': n.reactionEmoji,
      'reaction_author_id': n.reactionAuthorId,
    });
  }

  final res = await dio.post(Endpoints.syncBatch, data: {'notes': payload});
  if (res.statusCode == 200) {
    final acks = (res.data['notes'] as List).cast<Map<String, dynamic>>();
    await isar.writeTxn(() async {
      for (final ack in acks) {
        if (ack['error'] != null) continue;
        final n = await isar.noteLocals.get(int.parse(ack['client_id']));
        if (n == null) continue;
        n.remoteId = ack['id']?.toString();
        // Only flip pending→synced; an edit/delete made mid-flight keeps its
        // flag (and, now that remoteId is set, gets pushed on the next pass).
        if (n.syncStatus == 'pending') n.syncStatus = 'synced';
        await isar.noteLocals.put(n);
      }
    });
  }
}

/// Push text edits (PUT) and deletions (DELETE) of diary entries. Deletions
/// are tombstones: the local row only disappears once the server confirms.
///
/// The payload carries the reaction as well as the text. They are two
/// different things with two different owners — the body belongs to whoever
/// wrote the entry, the reaction to whoever left it — and the server scopes
/// each half accordingly, so a partner reacting to an entry they can't edit
/// still gets their reaction stored. Sending both in one PUT keeps the client
/// from having to know which half it is allowed to change: [myId] is passed
/// only so we don't waste a request re-sending text we never touched.
Future<void> _syncNoteMutations(Isar isar, Dio dio, String? myId) async {
  final edited = await isar.noteLocals
      .filter()
      .syncStatusEqualTo('edited')
      .findAll();
  for (final n in edited) {
    final rid = n.remoteId;
    if (rid == null) continue;
    final mine = myId == null || n.authorId == myId;
    try {
      final res = await dio.put(
        Endpoints.note(rid),
        data: {
          if (mine) 'body': n.body,
          if (mine) 'mood': n.mood,
          if (mine) 'link': n.link,
          'reaction_emoji': n.reactionEmoji,
          'reaction_author_id': n.reactionAuthorId,
        },
      );
      if (res.statusCode == 200) {
        await isar.writeTxn(() async {
          n.syncStatus = 'synced';
          await isar.noteLocals.put(n);
        });
      }
    } catch (_) {
      // Retry next tick.
    }
  }

  final deleted = await isar.noteLocals
      .filter()
      .syncStatusEqualTo('deleted')
      .findAll();
  for (final n in deleted) {
    if (await _remoteDeleteOk(dio, n.remoteId, Endpoints.note)) {
      await isar.writeTxn(() async {
        await isar.noteLocals.delete(n.isarId);
      });
    }
  }
}

/// Same as [_syncNoteMutations], for feed posts (title/description/tags).
Future<void> _syncPostMutations(Isar isar, Dio dio) async {
  final edited = await isar.postLocals
      .filter()
      .syncStatusEqualTo('edited')
      .findAll();
  for (final p in edited) {
    final rid = p.remoteId;
    if (rid == null) continue;
    try {
      final res = await dio.put(
        Endpoints.post(rid),
        data: {'title': p.title, 'description': p.description, 'tags': p.tags},
      );
      if (res.statusCode == 200) {
        await isar.writeTxn(() async {
          p.syncStatus = 'synced';
          await isar.postLocals.put(p);
        });
      }
    } catch (_) {
      // Retry next tick.
    }
  }

  final deleted = await isar.postLocals
      .filter()
      .syncStatusEqualTo('deleted')
      .findAll();
  for (final p in deleted) {
    if (await _remoteDeleteOk(dio, p.remoteId, Endpoints.post)) {
      await isar.writeTxn(() async {
        await isar.postLocals.delete(p.isarId);
      });
    }
  }
}

/// DELETE `pathFor(remoteId)`; true when the doc is gone (deleted now, never
/// synced, or already absent). False on network trouble → retry next tick.
Future<bool> _remoteDeleteOk(
  Dio dio,
  String? remoteId,
  String Function(String) pathFor,
) async {
  if (remoteId == null) return true;
  try {
    await dio.delete(pathFor(remoteId));
    return true;
  } on DioException catch (e) {
    return e.response?.statusCode == 404;
  } catch (_) {
    return false;
  }
}

/// Upload one local file (photo/video) as multipart; returns its remote URL,
/// or null on failure (the caller keeps the row pending for the next tick).
Future<String?> _uploadFile(Dio dio, String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  try {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path),
    });
    final res = await dio.post(Endpoints.mediaUpload, data: form);
    if (res.statusCode == 200) return res.data['url'] as String?;
  } catch (_) {
    /* leave pending */
  }
  return null;
}

/// Push "citas": new ideas, edits (including marking one as lived, which is
/// what carries its photos up), and deletions.
Future<void> _syncDateIdeas(Isar isar, Dio dio) async {
  Future<Map<String, dynamic>> body(DateIdeaLocal d) async {
    // Photos ride along on the row once uploaded, so a retry never re-uploads.
    if (d.remoteImageUrls.isEmpty && d.imagePaths.isNotEmpty) {
      final urls = <String>[];
      for (final path in d.imagePaths) {
        final url = await _uploadFile(dio, path);
        if (url != null) urls.add(url);
      }
      if (urls.isNotEmpty) {
        await isar.writeTxn(() async {
          d.remoteImageUrls = urls;
          await isar.dateIdeaLocals.put(d);
        });
      }
    }

    return {
      'client_id': d.isarId.toString(),
      'title': d.title,
      'description': d.description,
      'planned_at': d.plannedAt?.toUtc().toIso8601String(),
      'done': d.done,
      'done_at': d.doneAt?.toUtc().toIso8601String(),
      'done_note': d.doneNote,
      'image_urls': d.remoteImageUrls,
      'latitude': d.latitude,
      'longitude': d.longitude,
      'place_label': d.placeLabel,
      'created_at': d.createdAt.toUtc().toIso8601String(),
    };
  }

  final pending = await isar.dateIdeaLocals
      .filter()
      .syncStatusEqualTo('pending')
      .findAll();
  for (final d in pending) {
    try {
      final res = await dio.post(Endpoints.dateIdeas, data: await body(d));
      if (res.statusCode == 200 || res.statusCode == 201) {
        final doc = res.data['date_idea'] as Map?;
        await isar.writeTxn(() async {
          d.remoteId = (doc?['_id'] ?? doc?['id'])?.toString();
          if (d.syncStatus == 'pending') d.syncStatus = 'synced';
          await isar.dateIdeaLocals.put(d);
        });
      }
    } catch (_) {
      // Retry next tick.
    }
  }

  final edited = await isar.dateIdeaLocals
      .filter()
      .syncStatusEqualTo('edited')
      .findAll();
  for (final d in edited) {
    final rid = d.remoteId;
    if (rid == null) continue;
    try {
      final res = await dio.put(Endpoints.dateIdea(rid), data: await body(d));
      if (res.statusCode == 200) {
        await isar.writeTxn(() async {
          d.syncStatus = 'synced';
          await isar.dateIdeaLocals.put(d);
        });
      }
    } catch (_) {
      // Retry next tick.
    }
  }

  final deleted = await isar.dateIdeaLocals
      .filter()
      .syncStatusEqualTo('deleted')
      .findAll();
  for (final d in deleted) {
    if (await _remoteDeleteOk(dio, d.remoteId, Endpoints.dateIdea)) {
      await isar.writeTxn(() async {
        await isar.dateIdeaLocals.delete(d.isarId);
      });
    }
  }
}

Future<void> _syncSpecialDates(Isar isar, Dio dio) async {
  final pending = await isar.specialDateLocals
      .filter()
      .syncStatusEqualTo('pending')
      .findAll();
  for (final s in pending) {
    try {
      final res = await dio.post(
        Endpoints.specialDates,
        data: {
          // Idempotency key — a retry after a lost ack updates, not duplicates.
          'client_id': s.isarId.toString(),
          'title': s.title,
          'emoji': s.emoji,
          'recurring': s.recurring,
          'date': s.date.toUtc().toIso8601String(),
        },
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        final doc = res.data['special_date'] as Map?;
        await isar.writeTxn(() async {
          s.remoteId = (doc?['_id'] ?? doc?['id'])?.toString();
          s.syncStatus = 'synced';
          await isar.specialDateLocals.put(s);
        });
      }
    } catch (_) {
      // Stays pending for the next tick.
    }
  }

  // Tombstones: locally-deleted rows whose server copy must go too. Only once
  // the remote DELETE is confirmed (or the doc is already gone) do we drop the
  // local row — otherwise hydration would resurrect it.
  final deleted = await isar.specialDateLocals
      .filter()
      .syncStatusEqualTo('deleted')
      .findAll();
  for (final s in deleted) {
    if (await _remoteDeleteOk(dio, s.remoteId, Endpoints.specialDate)) {
      await isar.writeTxn(() async {
        await isar.specialDateLocals.delete(s.isarId);
      });
    }
  }
}

Future<void> _syncStatus(Isar isar, Dio dio) async {
  final pending = await isar.statusLocals
      .filter()
      .syncStatusEqualTo('pending')
      .findAll();
  for (final s in pending) {
    // Upload the snapshot once; the URL is kept so a retry never re-uploads.
    if (s.remoteImageUrl == null && s.imagePath != null) {
      final url = await _uploadFile(dio, s.imagePath!);
      if (url != null) {
        await isar.writeTxn(() async {
          s.remoteImageUrl = url;
          await isar.statusLocals.put(s);
        });
      }
    }

    final res = await dio.put(
      Endpoints.status,
      data: {
        'text': s.text,
        'image_url': s.remoteImageUrl,
        'updated_at': s.updatedAt.toUtc().toIso8601String(),
      },
    );
    if (res.statusCode == 200) {
      await isar.writeTxn(() async {
        s.syncStatus = 'synced';
        await isar.statusLocals.put(s);
      });
    }
  }
}

Future<void> _syncPosts(Isar isar, Dio dio) async {
  final pending = await isar.postLocals
      .filter()
      .syncStatusEqualTo('pending')
      .limit(Env.syncBatchSize)
      .findAll();

  for (final p in pending) {
    await isar.writeTxn(() async {
      p.syncStatus = 'syncing';
      await isar.postLocals.put(p);
    });

    try {
      // 1) Upload the media once, persisting the URLs as soon as they come
      //    back. Keeping them in a local variable until the post was created
      //    meant every failed or interrupted attempt re-uploaded the whole set
      //    under fresh names, leaking a full duplicate onto the server.
      if (p.remoteMediaUrls.isEmpty && p.localMediaPaths.isNotEmpty) {
        final uploaded = <String>[];
        for (final path in p.localMediaPaths) {
          final url = await _uploadFile(dio, path);
          if (url != null) uploaded.add(url);
        }
        if (uploaded.isNotEmpty) {
          await isar.writeTxn(() async {
            p.remoteMediaUrls = uploaded;
            await isar.postLocals.put(p);
          });
        }
      }
      final remoteUrls = p.remoteMediaUrls;

      // 2) Create the post referencing the remote URLs.
      final res = await dio.post(
        Endpoints.posts,
        data: {
          'client_id': p.isarId.toString(),
          'title': p.title,
          'description': p.description,
          'tags': p.tags,
          'media_urls': remoteUrls,
          'private': p.isPrivate,
          'latitude': p.latitude,
          'longitude': p.longitude,
          'place_label': p.placeLabel,
          'created_at': p.createdAt.toUtc().toIso8601String(),
        },
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        await isar.writeTxn(() async {
          p.remoteId = res.data['id'];
          p.syncStatus = 'synced';
          p.lastError = null;
          await isar.postLocals.put(p);
        });
      } else {
        await _markFailed(isar, p, 'HTTP ${res.statusCode}');
      }
    } catch (e) {
      await _markFailed(isar, p, e.toString());
    }
  }
}

Future<void> _markFailed(Isar isar, PostLocal p, String err) async {
  await isar.writeTxn(() async {
    p.retryCount += 1;
    // Give up after too many attempts so we don't retry a doomed upload
    // forever (and so the UI can surface a real "failed" state).
    p.syncStatus = p.retryCount >= Env.syncMaxRetries ? 'failed' : 'pending';
    p.lastError = err;
    await isar.postLocals.put(p);
  });
}
