import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../local/isar/comment_local.dart';
import '../local/isar_service.dart';
import '../remote/api_client.dart';
import '../remote/endpoints.dart';

final commentRepositoryProvider = Provider<CommentRepository>(
  (_) => CommentRepository(),
);

/// Live comments for a single post, newest first. Keyed by postId so each
/// open sheet gets its own auto-disposed subscription.
final commentsForPostProvider = StreamProvider.autoDispose
    .family<List<CommentLocal>, String>(
      (ref, postId) =>
          ref.watch(commentRepositoryProvider).watchForPost(postId),
    );

/// Offline-first comments for a post:
/// 1. `create` writes to Isar with sync_status:pending and returns immediately.
/// 2. `flushPending` is called by the sheet right after the optimistic write
///    (or by the sync worker on its tick) to push pending rows to the server.
/// 3. Successful push flips the row to `synced` and stamps the remote id.
class CommentRepository {
  final _dio = ApiClient.instance.dio;
  Isar get _isar => IsarService.instance.db;

  Stream<List<CommentLocal>> watchForPost(String postId) {
    return _isar.commentLocals
        .filter()
        .postIdEqualTo(postId)
        .sortByCreatedAtDesc()
        .watch(fireImmediately: true);
  }

  Future<CommentLocal> create({
    required String postId,
    required String authorId,
    required String text,
  }) async {
    final row = CommentLocal()
      ..postId = postId
      ..authorId = authorId
      ..text = text
      ..createdAt = DateTime.now()
      ..syncStatus = 'pending';
    await _isar.writeTxn(() async {
      await _isar.commentLocals.put(row);
    });
    return row;
  }

  /// Pushes every pending comment for [postId] (or all if null). Errors are
  /// kept as 'pending' so the next call retries.
  Future<void> flushPending({String? postId}) async {
    final query = postId == null
        ? _isar.commentLocals.filter().syncStatusEqualTo('pending')
        : _isar.commentLocals
              .filter()
              .postIdEqualTo(postId)
              .syncStatusEqualTo('pending');

    final pending = await query.findAll();
    for (final c in pending) {
      try {
        final res = await _dio.post(
          Endpoints.postComments(c.postId),
          data: {'body': c.text},
        );
        if (res.statusCode == 200 || res.statusCode == 201) {
          final remoteId =
              (res.data['comment']?['id'] ?? res.data['comment']?['_id'])
                  ?.toString();
          await _isar.writeTxn(() async {
            c
              ..remoteId = remoteId
              ..syncStatus = 'synced';
            await _isar.commentLocals.put(c);
          });
        }
      } on DioException {
        // Stays pending; will retry on next tick.
        break;
      }
    }
  }

  /// Persist a remote-origin comment (received via WebSocket) so it appears
  /// when the user reopens the sheet offline.
  Future<void> upsertFromRemote(Map<String, dynamic> j) async {
    final remoteId = (j['id'] ?? j['_id'])?.toString();
    final postId = j['post_id']?.toString();
    if (remoteId == null || postId == null) return;
    final authorId = j['author_id']?.toString() ?? '';
    final text = (j['body'] ?? j['text'])?.toString() ?? '';

    // Prefer a row already tied to this remoteId. Failing that, adopt our own
    // optimistic *pending* row with the same content, so the server's echo of
    // a comment we just posted updates that row instead of creating a
    // duplicate next to it.
    final existing =
        await _isar.commentLocals
            .filter()
            .remoteIdEqualTo(remoteId)
            .findFirst() ??
        await _isar.commentLocals
            .filter()
            .postIdEqualTo(postId)
            .authorIdEqualTo(authorId)
            .textEqualTo(text)
            .syncStatusEqualTo('pending')
            .findFirst();

    await _isar.writeTxn(() async {
      final row = existing ?? CommentLocal();
      row
        ..remoteId = remoteId
        ..postId = postId
        ..authorId = authorId
        ..text = text
        ..createdAt =
            DateTime.tryParse(j['created_at']?.toString() ?? '') ??
            DateTime.now()
        ..syncStatus = 'synced';
      await _isar.commentLocals.put(row);
    });
  }
}
