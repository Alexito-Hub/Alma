import 'dart:async';

import 'package:dio/dio.dart';
import 'package:isar_community/isar.dart';

import '../local/isar/note_local.dart';
import '../local/isar/post_local.dart';
import '../local/isar/special_date_local.dart';
import '../local/isar/status_local.dart';
import '../local/isar_service.dart';
import '../remote/api_client.dart';
import '../remote/endpoints.dart';
import '../remote/ws_client.dart';

/// Pulls the couple's data down from the server into Isar so the offline
/// caches reflect what the partner has been doing. Idempotent: a row already
/// present locally (by `remoteId`) is updated in place, never duplicated.
class Hydrator {
  Hydrator._();
  static final Hydrator instance = Hydrator._();

  final _dio = ApiClient.instance.dio;
  Isar get _isar => IsarService.instance.db;

  /// Full initial sync. Safe to call repeatedly.
  Future<void> hydrateAll({required String? coupleId}) async {
    if (coupleId == null) return;
    await Future.wait([
      _pullNotes(),
      _pullPosts(),
      _pullStatus(),
      _pullSpecialDates(),
    ]);
  }

  String? _subscribedCoupleId;
  StreamSubscription? _wsSub;

  /// Subscribe to the couple channel so live new_post/new_note from the
  /// partner are persisted as soon as they happen. `onPartnerUpdated` is
  /// invoked when the partner changes profile data (avatar, email).
  Future<void> subscribeToLiveUpdates(
    String coupleId, {
    void Function(Map<String, dynamic>)? onPartnerUpdated,
  }) async {
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
        switch (ev) {
          case 'new_post':
            await _upsertPost(p);
            break;
          case 'new_note':
            await _upsertNote(p);
            break;
          case 'new_special_date':
            await _upsertSpecialDate(p);
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
      await _isar.writeTxn(() async {
        for (final raw in list) {
          await _upsertStatusInTxn(Map<String, dynamic>.from(raw as Map));
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
    final existing = await _isar.noteLocals
        .filter()
        .remoteIdEqualTo(remoteId)
        .findFirst();
    final row = existing ?? NoteLocal();
    row
      ..remoteId = remoteId
      ..body = j['body']?.toString() ?? ''
      ..authorId = j['author_id']?.toString() ?? ''
      ..createdAt = _date(j['created_at']) ?? DateTime.now()
      ..mood = j['mood']?.toString()
      ..link = j['link']?.toString()
      ..remoteImageUrls = (j['image_urls'] as List? ?? const [])
          .map((u) => u.toString())
          .toList()
      ..remoteVideoUrl = j['video_url']?.toString()
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
    final existing = await _isar.postLocals
        .filter()
        .remoteIdEqualTo(remoteId)
        .findFirst();
    final row = existing ?? PostLocal();
    row
      ..remoteId = remoteId
      ..title = j['title']?.toString() ?? ''
      ..description = j['description']?.toString() ?? ''
      ..authorId = j['author_id']?.toString() ?? ''
      ..tags = (j['tags'] as List? ?? const [])
          .map((t) => t.toString())
          .toList()
      ..localMediaPaths = const []
      ..remoteMediaUrls = (j['media_urls'] as List? ?? const [])
          .map((u) => u.toString())
          .toList()
      ..createdAt = _date(j['created_at']) ?? DateTime.now()
      ..syncStatus = 'synced';
    await _isar.postLocals.put(row);
  }

  Future<void> _upsertStatusInTxn(Map<String, dynamic> j) async {
    final authorId = j['author_id']?.toString();
    if (authorId == null) return;
    final existing = await _isar.statusLocals
        .filter()
        .authorIdEqualTo(authorId)
        .findFirst();
    final row = existing ?? StatusLocal();
    row
      ..authorId = authorId
      ..text = j['text']?.toString() ?? ''
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

  Future<void> _upsertSpecialDate(Map<String, dynamic> j) =>
      _isar.writeTxn(() => _upsertSpecialDateInTxn(j));

  Future<void> _upsertSpecialDateInTxn(Map<String, dynamic> j) async {
    final remoteId = (j['_id'] ?? j['id'])?.toString();
    if (remoteId == null) return;
    final existing = await _isar.specialDateLocals
        .filter()
        .remoteIdEqualTo(remoteId)
        .findFirst();
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
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}
