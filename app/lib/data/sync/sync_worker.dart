import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:isar_community/isar.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/config/env.dart';
import '../local/isar/comment_local.dart';
import '../local/isar/note_local.dart';
import '../local/isar/post_local.dart';
import '../local/isar/special_date_local.dart';
import '../local/isar/status_local.dart';
import '../local/isar_service.dart';
import '../remote/api_client.dart';
import '../remote/endpoints.dart';
import '../remote/token_storage.dart';
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
  final conn = await Connectivity().checkConnectivity();
  if (conn.contains(ConnectivityResult.none)) return;

  // Respect "Wi-Fi only" preference per spec §2: at the user's option, skip
  // mobile data uploads.
  final wifiOnly = await SyncPrefs.wifiOnly();
  final onWifi =
      conn.contains(ConnectivityResult.wifi) ||
      conn.contains(ConnectivityResult.ethernet);
  if (wifiOnly && !onWifi) return;

  final token = await TokenStorage.read();
  if (token == null) return;

  final isar = await IsarService.openForIsolate();
  final dio = Dio(
    BaseOptions(
      baseUrl: Env.apiBaseUrl,
      headers: {'Authorization': 'Bearer $token'},
      sendTimeout: const Duration(minutes: 2),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  // Recover uploads that were interrupted mid-flight last time.
  await _reviveStalled(isar);

  await _syncNotes(isar, dio);
  await _syncStatus(isar, dio);
  await _syncPosts(isar, dio);
  await _syncComments(isar, dio);
  await _syncSpecialDates(isar, dio);
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
    await _syncNotes(isar, dio);
    await _syncStatus(isar, dio);
    await _syncPosts(isar, dio);
    await _syncComments(isar, dio);
    await _syncSpecialDates(isar, dio);
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
      final res = await dio.post(
        Endpoints.postComments(c.postId),
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
    if (n.remoteVideoUrl == null && n.videoPath != null) {
      final url = await _uploadFile(dio, n.videoPath!);
      if (url != null) {
        await isar.writeTxn(() async {
          n.remoteVideoUrl = url;
          await isar.noteLocals.put(n);
        });
      }
    }

    payload.add({
      'client_id': n.isarId.toString(),
      'body': n.body,
      'author_id': n.authorId,
      'created_at': n.createdAt.toIso8601String(),
      'mood': n.mood,
      'link': n.link,
      'image_urls': n.remoteImageUrls,
      'video_url': n.remoteVideoUrl,
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
        n.syncStatus = 'synced';
        await isar.noteLocals.put(n);
      }
    });
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
          'title': s.title,
          'emoji': s.emoji,
          'recurring': s.recurring,
          'date': s.date.toIso8601String(),
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
}

Future<void> _syncStatus(Isar isar, Dio dio) async {
  final pending = await isar.statusLocals
      .filter()
      .syncStatusEqualTo('pending')
      .findAll();
  for (final s in pending) {
    final res = await dio.put(
      Endpoints.status,
      data: {'text': s.text, 'updated_at': s.updatedAt.toIso8601String()},
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
      // 1) Upload each media file (multipart), collect remote URLs.
      final remoteUrls = <String>[];
      for (final path in p.localMediaPaths) {
        final file = File(path);
        if (!await file.exists()) continue;
        final form = FormData.fromMap({
          'file': await MultipartFile.fromFile(file.path),
        });
        final mediaRes = await dio.post(Endpoints.mediaUpload, data: form);
        if (mediaRes.statusCode == 200) {
          remoteUrls.add(mediaRes.data['url']);
        }
      }

      // 2) Create the post referencing the remote URLs.
      final res = await dio.post(
        Endpoints.posts,
        data: {
          'client_id': p.isarId.toString(),
          'title': p.title,
          'description': p.description,
          'tags': p.tags,
          'media_urls': remoteUrls,
          'created_at': p.createdAt.toIso8601String(),
        },
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        await isar.writeTxn(() async {
          p.remoteId = res.data['id'];
          p.remoteMediaUrls = remoteUrls;
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
