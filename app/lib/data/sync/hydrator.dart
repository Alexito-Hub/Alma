import 'dart:async';

import 'package:dio/dio.dart';
import 'package:isar_community/isar.dart';

import '../device/home_widgets.dart';
import '../device/notifications.dart';
import '../local/isar/date_idea_local.dart';
import '../local/isar/note_local.dart';
import '../local/isar/post_local.dart';
import '../local/isar/special_date_local.dart';
import '../local/isar/status_local.dart';
import '../local/isar_service.dart';
import '../remote/api_client.dart';
import '../remote/endpoints.dart';
import '../remote/ws_client.dart';
import '../repositories/comment_repository.dart';
import 'status_photo_cache.dart';
import 'sync_prefs.dart';

/// Pulls the couple's data down from the server into Isar so the offline
/// caches reflect what the partner has been doing. Idempotent: a row already
/// present locally (by `remoteId`) is updated in place, never duplicated.
class Hydrator {
  Hydrator._();
  static final Hydrator instance = Hydrator._();

  final _dio = ApiClient.instance.dio;
  Isar get _isar => IsarService.instance.db;

  /// The signed-in user's id. Lets us (a) ignore our own events echoed back on
  /// the couple channel and (b) attach pulled docs to the pending local row
  /// that created them (via client_id) instead of duplicating it.
  String? _selfId;

  /// Partner's display name, used to title the notifications and the widget.
  String? _partnerName;

  set partnerName(String? name) {
    if (name != null && name.isNotEmpty) _partnerName = name;
  }

  /// Full initial sync. Safe to call repeatedly.
  Future<void> hydrateAll({
    required String? coupleId,
    String? selfUserId,
    String? partnerName,
  }) async {
    if (selfUserId != null) _selfId = selfUserId;
    this.partnerName = partnerName;
    if (coupleId == null) return;
    await Future.wait([
      _guard(_pullNotes),
      _guard(_pullPosts),
      _guard(_pullStatus),
      _guard(_pullSpecialDates),
      _guard(_pullDateIdeas),
    ]);
  }

  /// Run one pull, keeping its failure to itself.
  ///
  /// Every caller fires hydration and forgets it, so anything escaping here
  /// lands as an unhandled async error rather than as a stale tab. The pulls
  /// catch `DioException` themselves; this covers the rest.
  Future<void> _guard(Future<void> Function() pull) async {
    try {
      await pull();
    } catch (_) {
      // The next hydrate — app resume, or the periodic tick — tries again.
    }
  }

  String? _subscribedCoupleId;
  StreamSubscription? _wsSub;

  /// Subscribe to the couple channel so live new_post/new_note from the
  /// partner are persisted as soon as they happen. `onPartnerUpdated` is
  /// invoked when the partner changes profile data (avatar, email).
  /// Sole owner of the `couple:<id>` channel — Phoenix rejects a second join
  /// on the same topic from one socket, so every couple event (posts, notes,
  /// special dates *and* status) is dispatched from here.
  Future<void> subscribeToLiveUpdates(
    String coupleId, {
    String? selfUserId,
    String? partnerName,
    void Function(Map<String, dynamic>)? onPartnerUpdated,
  }) async {
    if (selfUserId != null) _selfId = selfUserId;
    this.partnerName = partnerName;
    // phoenix_socket asserts that a channel only joins once; reuse the
    // existing subscription if we're already on the right couple.
    if (_subscribedCoupleId == coupleId && _wsSub != null) return;
    await _wsSub?.cancel();
    _wsSub = null;

    try {
      final socket = await WsClient.instance.connect();
      final ch = socket.addChannel(topic: 'couple:$coupleId');
      _wsSub = ch.messages.listen((msg) async {
        final ev = msg.event.value;
        final payload = msg.payload;
        if (payload == null) return;
        final p = Map<String, dynamic>.from(payload);
        // The server echoes our own broadcasts back to us. Our rows are
        // managed by the sync-ack path; upserting the echo here would race
        // the ack (no remoteId yet) and insert a duplicate.
        final fromSelf =
            _selfId != null && p['author_id']?.toString() == _selfId;
        switch (ev) {
          case 'new_post':
            if (!fromSelf) {
              await _upsertPost(p);
              await Notifications.partnerPost(
                _partnerName,
                p['title']?.toString() ?? '',
              );
              await _markSeen('post', p['created_at']);
            }
            break;
          case 'post_updated':
            if (!fromSelf) await _upsertPost(p);
            break;
          case 'new_note':
            if (!fromSelf) {
              await _upsertNote(p);
              await Notifications.partnerNote(
                _partnerName,
                p['body']?.toString() ?? '',
              );
              await _markSeen('note', p['created_at']);
            }
            break;
          case 'note_updated':
            if (!fromSelf) await _upsertNote(p);
            break;
          case 'status_updated':
            if (!fromSelf) await _onPartnerStatus(p);
            break;
          case 'new_special_date':
            if (!fromSelf) await _upsertSpecialDate(p);
            break;
          case 'note_deleted':
            await _deleteNoteByRemoteId((p['id'] ?? p['_id'])?.toString());
            break;
          case 'post_deleted':
            await _deletePostByRemoteId((p['id'] ?? p['_id'])?.toString());
            break;
          case 'new_comment':
            await _upsertComment(p);
            break;
          case 'new_date_idea':
          case 'date_idea_updated':
            if (!fromSelf) await _upsertDateIdea(p);
            break;
          case 'date_idea_deleted':
            await _deleteDateIdeaByRemoteId((p['id'] ?? p['_id'])?.toString());
            break;
          case 'special_date_deleted':
            await _deleteSpecialDateByRemoteId(
              (p['id'] ?? p['_id'])?.toString(),
            );
            break;
          case 'partner_updated':
            onPartnerUpdated?.call(p);
            break;
        }
      });
      await ch.join().future;
      _subscribedCoupleId = coupleId;
    } catch (_) {
      // WS unavailable — periodic hydrateAll() still works as fallback.
    }
  }

  // ─── pulls ────────────────────────────────────────────────────────────────

  Future<void> _pullNotes() async {
    try {
      final res = await _dio.get(Endpoints.notes);
      final list = (res.data['notes'] as List? ?? const []);
      final serverIds = _idsOf(list);
      // One transaction for the whole page instead of one per row.
      await _isar.writeTxn(() async {
        for (final raw in list) {
          await _upsertNoteInTxn(Map<String, dynamic>.from(raw as Map));
        }
        // Drop already-synced rows the server no longer has (deleted remotely)
        // so a deletion propagates instead of leaving a phantom entry. Rows
        // still pending upload (no remoteId) are kept.
        final all = await _isar.noteLocals.where().findAll();
        final stale = all
            .where((n) => n.remoteId != null && !serverIds.contains(n.remoteId))
            .map((n) => n.isarId)
            .toList();
        if (stale.isNotEmpty) await _isar.noteLocals.deleteAll(stale);
      });
    } on DioException {
      // offline / no couple yet — ignore
    }
  }

  Future<void> _pullPosts() async {
    try {
      final res = await _dio.get(Endpoints.posts);
      final list = (res.data['posts'] as List? ?? const []);
      final serverIds = _idsOf(list);
      await _isar.writeTxn(() async {
        for (final raw in list) {
          await _upsertPostInTxn(Map<String, dynamic>.from(raw as Map));
        }
        // Drop already-synced rows the server no longer has (deleted remotely)
        // so a deletion propagates instead of leaving a broken/phantom post.
        final all = await _isar.postLocals.where().findAll();
        final stale = all
            .where((p) => p.remoteId != null && !serverIds.contains(p.remoteId))
            .map((p) => p.isarId)
            .toList();
        if (stale.isNotEmpty) await _isar.postLocals.deleteAll(stale);
      });
    } on DioException {
      /* ignore */
    }
  }

  /// Collects the server-side ids (`_id`/`id`) from a raw JSON list.
  Set<String> _idsOf(List<dynamic> list) {
    final ids = <String>{};
    for (final raw in list) {
      final id = ((raw as Map)['_id'] ?? raw['id'])?.toString();
      if (id != null) ids.add(id);
    }
    return ids;
  }

  Future<void> _pullStatus() async {
    try {
      final res = await _dio.get(Endpoints.status);
      final list =
          res.data['statuses'] as List? ??
          (res.data['status'] == null ? const [] : [res.data['status']]);
      if (list.isEmpty) return;

      // Snapshots are downloaded *before* the transaction — network calls
      // can't run inside a writeTxn, and skipping this step used to leave the
      // previous photo attached to a freshly updated status.
      final photos = <String, String?>{};
      for (final raw in list) {
        final j = Map<String, dynamic>.from(raw as Map);
        final author = j['author_id']?.toString();
        final url = j['image_url']?.toString();
        if (author != null && url != null && url.isNotEmpty) {
          photos[author] = await _cachePhoto(url);
        }
      }

      await _isar.writeTxn(() async {
        for (final raw in list) {
          final j = Map<String, dynamic>.from(raw as Map);
          await _upsertStatusInTxn(
            j,
            localPhoto: photos[j['author_id']?.toString()],
          );
        }
      });
    } on DioException {
      /* ignore */
    }
  }

  // ─── upserts ──────────────────────────────────────────────────────────────
  // The public entrypoints own a transaction and are used for single live
  // updates from the WebSocket; the *InTxn variants carry the logic and run
  // inside a caller-owned transaction so pulls can batch many rows at once.

  Future<void> _upsertNote(Map<String, dynamic> j) =>
      _isar.writeTxn(() => _upsertNoteInTxn(j));

  Future<void> _upsertNoteInTxn(Map<String, dynamic> j) async {
    final remoteId = (j['_id'] ?? j['id'])?.toString();
    if (remoteId == null) return;
    var existing = await _isar.noteLocals
        .filter()
        .remoteIdEqualTo(remoteId)
        .findFirst();
    // A doc I authored may already exist locally as the pending row that
    // produced it (lost ack / pull racing the ack). Its client_id is that
    // row's isar id — attach to it instead of inserting a duplicate.
    existing ??= await _mineByClientId(j, _isar.noteLocals.get);
    // Local mutations win until pushed: don't resurrect a tombstone or
    // clobber an unsent edit with the server's stale copy.
    if (existing != null &&
        (existing.syncStatus == 'deleted' || existing.syncStatus == 'edited')) {
      return;
    }
    final row = existing ?? NoteLocal();
    row
      ..remoteId = remoteId
      ..body = j['body']?.toString() ?? ''
      ..authorId = j['author_id']?.toString() ?? ''
      ..createdAt = _date(j['created_at']) ?? DateTime.now()
      ..isPrivate = j['private'] == true
      ..mood = j['mood']?.toString()
      ..link = j['link']?.toString()
      ..remoteImageUrls = (j['image_urls'] as List? ?? const [])
          .map((u) => u.toString())
          .toList()
      ..remoteVideoUrls = (j['video_urls'] as List? ?? const [])
          .map((u) => u.toString())
          .toList()
      ..remoteVideoUrl = j['video_url']?.toString()
      ..remoteAudioUrl = j['audio_url']?.toString()
      ..latitude = _toDouble(j['latitude'])
      ..longitude = _toDouble(j['longitude'])
      ..placeLabel = j['place_label']?.toString()
      ..reactionEmoji = j['reaction_emoji']?.toString()
      ..reactionAuthorId = j['reaction_author_id']?.toString()
      ..syncStatus = 'synced';
    await _isar.noteLocals.put(row);
  }

  Future<void> _upsertPost(Map<String, dynamic> j) =>
      _isar.writeTxn(() => _upsertPostInTxn(j));

  Future<void> _upsertPostInTxn(Map<String, dynamic> j) async {
    final remoteId = (j['_id'] ?? j['id'])?.toString();
    if (remoteId == null) return;
    var existing = await _isar.postLocals
        .filter()
        .remoteIdEqualTo(remoteId)
        .findFirst();
    existing ??= await _mineByClientId(j, _isar.postLocals.get);
    // Local mutations win until pushed (see note upsert).
    if (existing != null &&
        (existing.syncStatus == 'deleted' || existing.syncStatus == 'edited')) {
      return;
    }
    final row = existing ?? PostLocal();
    row
      ..remoteId = remoteId
      ..title = j['title']?.toString() ?? ''
      ..description = j['description']?.toString() ?? ''
      ..authorId = j['author_id']?.toString() ?? ''
      ..tags = (j['tags'] as List? ?? const [])
          .map((t) => t.toString())
          .toList()
      ..isPrivate = j['private'] == true
      ..latitude = _toDouble(j['latitude'])
      ..longitude = _toDouble(j['longitude'])
      ..placeLabel = j['place_label']?.toString()
      ..localMediaPaths = const []
      ..remoteMediaUrls = (j['media_urls'] as List? ?? const [])
          .map((u) => u.toString())
          .toList()
      ..createdAt = _date(j['created_at']) ?? DateTime.now()
      ..syncStatus = 'synced';
    await _isar.postLocals.put(row);
  }

  /// Partner published a new "siente": cache it, notify, refresh the widget.
  Future<void> _onPartnerStatus(Map<String, dynamic> j) async {
    // Pull the snapshot down first so both Isar and the widget can point at a
    // local file — the home-screen widget can't fetch a URL itself.
    final photo = await _cachePhoto(j['image_url']?.toString());
    await _isar.writeTxn(() => _upsertStatusInTxn(j, localPhoto: photo));

    final text = j['text']?.toString() ?? '';
    if (text.trim().isEmpty && photo == null) return;
    await Notifications.partnerStatus(
      _partnerName,
      text.trim().isEmpty ? 'Te compartió una instantánea' : text,
    );
    await HomeWidgets.pushStatus(
      author: _partnerName,
      text: text,
      photoPath: photo,
      at: _date(j['updated_at']),
    );
    await _markSeen('status', j['updated_at']);
  }

  /// Record that we already told the user about this item, so the background
  /// tick doesn't announce the same thing again minutes later.
  Future<void> _markSeen(String kind, dynamic stamp) async {
    final value = stamp?.toString();
    if (value == null || value.isEmpty) return;
    await SyncPrefs.setMarker(kind, value);
  }

  /// Public entry point for callers that need a local copy of a status photo
  /// (the home-screen widget can only read files, not URLs).
  Future<String?> cacheStatusPhoto(String? url) => _cachePhoto(url);

  Future<String?> _cachePhoto(String? url) => cacheStatusPhotoWith(_dio, url);

  Future<void> _upsertStatusInTxn(
    Map<String, dynamic> j, {
    String? localPhoto,
  }) async {
    final authorId = j['author_id']?.toString();
    if (authorId == null) return;
    final existing = await _isar.statusLocals
        .filter()
        .authorIdEqualTo(authorId)
        .findFirst();
    // Our own row can hold a snapshot that hasn't uploaded yet — don't let a
    // pull overwrite it with the server's older copy.
    if (existing != null &&
        authorId == _selfId &&
        existing.syncStatus == 'pending') {
      return;
    }
    final remoteImage = j['image_url']?.toString();
    final row = existing ?? StatusLocal();
    row
      ..authorId = authorId
      ..text = j['text']?.toString() ?? ''
      ..remoteImageUrl = (remoteImage == null || remoteImage.isEmpty)
          ? null
          : remoteImage
      // Strictly derived from the current remote photo: keeping the old local
      // path when a download fails is what made a new status show the
      // previous image. Null just falls back to loading from the URL.
      ..imagePath = (remoteImage == null || remoteImage.isEmpty)
          ? null
          : localPhoto
      ..updatedAt = _date(j['updated_at']) ?? DateTime.now()
      ..syncStatus = 'synced';
    await _isar.statusLocals.put(row);
  }

  Future<void> _pullSpecialDates() async {
    try {
      final res = await _dio.get(Endpoints.specialDates);
      final list = (res.data['special_dates'] as List? ?? const []);
      final serverIds = _idsOf(list);
      await _isar.writeTxn(() async {
        for (final raw in list) {
          await _upsertSpecialDateInTxn(Map<String, dynamic>.from(raw as Map));
        }
        final all = await _isar.specialDateLocals.where().findAll();
        final stale = all
            .where((s) => s.remoteId != null && !serverIds.contains(s.remoteId))
            .map((s) => s.isarId)
            .toList();
        if (stale.isNotEmpty) await _isar.specialDateLocals.deleteAll(stale);
      });
    } on DioException {
      /* ignore */
    }
  }

  /// A comment on a diary entry, arriving live on the couple channel.
  Future<void> _upsertComment(Map<String, dynamic> j) async {
    await CommentRepository().upsertFromRemote(j);
  }

  Future<void> _pullDateIdeas() async {
    try {
      final res = await _dio.get(Endpoints.dateIdeas);
      final list = (res.data['date_ideas'] as List? ?? const []);
      final serverIds = _idsOf(list);
      await _isar.writeTxn(() async {
        for (final raw in list) {
          await _upsertDateIdeaInTxn(Map<String, dynamic>.from(raw as Map));
        }
        final all = await _isar.dateIdeaLocals.where().findAll();
        final stale = all
            .where((d) => d.remoteId != null && !serverIds.contains(d.remoteId))
            .map((d) => d.isarId)
            .toList();
        if (stale.isNotEmpty) await _isar.dateIdeaLocals.deleteAll(stale);
      });
    } on DioException {
      /* ignore */
    }
  }

  Future<void> _upsertDateIdea(Map<String, dynamic> j) =>
      _isar.writeTxn(() => _upsertDateIdeaInTxn(j));

  Future<void> _upsertDateIdeaInTxn(Map<String, dynamic> j) async {
    final remoteId = (j['_id'] ?? j['id'])?.toString();
    if (remoteId == null) return;
    var existing = await _isar.dateIdeaLocals
        .filter()
        .remoteIdEqualTo(remoteId)
        .findFirst();
    existing ??= await _mineByClientId(j, _isar.dateIdeaLocals.get);
    // Local changes win until pushed.
    if (existing != null &&
        (existing.syncStatus == 'deleted' || existing.syncStatus == 'edited')) {
      return;
    }
    final row = existing ?? DateIdeaLocal();
    row
      ..remoteId = remoteId
      ..title = j['title']?.toString() ?? ''
      ..description = j['description']?.toString() ?? ''
      ..proposedBy = j['author_id']?.toString() ?? ''
      ..plannedAt = _date(j['planned_at'])
      ..done = j['done'] == true
      ..doneAt = _date(j['done_at'])
      ..doneNote = j['done_note']?.toString()
      ..remoteImageUrls = (j['image_urls'] as List? ?? const [])
          .map((u) => u.toString())
          .toList()
      ..latitude = _toDouble(j['latitude'])
      ..longitude = _toDouble(j['longitude'])
      ..placeLabel = j['place_label']?.toString()
      ..createdAt = _date(j['created_at']) ?? DateTime.now()
      ..syncStatus = 'synced';
    await _isar.dateIdeaLocals.put(row);
  }

  Future<void> _deleteDateIdeaByRemoteId(String? remoteId) async {
    if (remoteId == null) return;
    await _isar.writeTxn(() async {
      final row = await _isar.dateIdeaLocals
          .filter()
          .remoteIdEqualTo(remoteId)
          .findFirst();
      if (row != null) await _isar.dateIdeaLocals.delete(row.isarId);
    });
  }

  Future<void> _upsertSpecialDate(Map<String, dynamic> j) =>
      _isar.writeTxn(() => _upsertSpecialDateInTxn(j));

  /// Resolves the local row a self-authored server doc originated from, via
  /// its client_id (the originating device's isar id). Only rows that never
  /// got a remoteId qualify — anything else is someone else's data.
  Future<T?> _mineByClientId<T>(
    Map<String, dynamic> j,
    Future<T?> Function(int) getById,
  ) async {
    if (_selfId == null || j['author_id']?.toString() != _selfId) return null;
    final cid = int.tryParse(j['client_id']?.toString() ?? '');
    if (cid == null) return null;
    final mine = await getById(cid);
    if (mine == null) return null;
    final dyn = mine as dynamic;
    return dyn.remoteId == null ? mine : null;
  }

  Future<void> _deleteSpecialDateByRemoteId(String? remoteId) async {
    if (remoteId == null) return;
    await _isar.writeTxn(() async {
      final row = await _isar.specialDateLocals
          .filter()
          .remoteIdEqualTo(remoteId)
          .findFirst();
      if (row != null) await _isar.specialDateLocals.delete(row.isarId);
    });
  }

  Future<void> _deleteNoteByRemoteId(String? remoteId) async {
    if (remoteId == null) return;
    await _isar.writeTxn(() async {
      final row = await _isar.noteLocals
          .filter()
          .remoteIdEqualTo(remoteId)
          .findFirst();
      if (row != null) await _isar.noteLocals.delete(row.isarId);
    });
  }

  Future<void> _deletePostByRemoteId(String? remoteId) async {
    if (remoteId == null) return;
    await _isar.writeTxn(() async {
      final row = await _isar.postLocals
          .filter()
          .remoteIdEqualTo(remoteId)
          .findFirst();
      if (row != null) await _isar.postLocals.delete(row.isarId);
    });
  }

  Future<void> _upsertSpecialDateInTxn(Map<String, dynamic> j) async {
    final remoteId = (j['_id'] ?? j['id'])?.toString();
    if (remoteId == null) return;
    var existing = await _isar.specialDateLocals
        .filter()
        .remoteIdEqualTo(remoteId)
        .findFirst();
    existing ??= await _mineByClientId(j, _isar.specialDateLocals.get);
    // Tombstone: locally deleted, remote DELETE still in flight — don't
    // resurrect it from a pull.
    if (existing != null && existing.syncStatus == 'deleted') return;
    final row = existing ?? SpecialDateLocal();
    row
      ..remoteId = remoteId
      ..title = j['title']?.toString() ?? ''
      ..emoji = j['emoji']?.toString()
      ..recurring = j['recurring'] != false
      ..date = _date(j['date']) ?? DateTime.now()
      ..createdBy = j['author_id']?.toString() ?? ''
      ..syncStatus = 'synced';
    await _isar.specialDateLocals.put(row);
  }

  double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  DateTime? _date(dynamic v) {
    if (v == null) return null;
    // Server timestamps are UTC; convert to local so day-based grouping
    // (calendar cells, "un día como hoy") lands on the right day.
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    return null;
  }
}
