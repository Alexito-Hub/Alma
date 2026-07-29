import 'dart:async';

import 'package:dio/dio.dart';
import 'package:isar/isar.dart';

import '../local/isar/note_local.dart';
import '../local/isar/post_local.dart';
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
    await Future.wait([_pullNotes(), _pullPosts(), _pullStatus()]);
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
      if (list.isEmpty) return;
      // One transaction for the whole page instead of one per row.
      await _isar.writeTxn(() async {
        for (final raw in list) {
          await _upsertNoteInTxn(Map<String, dynamic>.from(raw as Map));
        }
      });
    } on DioException {
      // offline / no couple yet — ignore
    }
  }

  Future<void> _pullPosts() async {
    try {
      final res = await _dio.get(Endpoints.posts);
      final list = (res.data['posts'] as List? ?? const []);
      if (list.isEmpty) return;
      await _isar.writeTxn(() async {
        for (final raw in list) {
          await _upsertPostInTxn(Map<String, dynamic>.from(raw as Map));
        }
      });
    } on DioException {
      /* ignore */
    }
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

  DateTime? _date(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}
