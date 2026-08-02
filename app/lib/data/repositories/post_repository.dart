import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../device/media_tools.dart';
import '../local/isar/post_local.dart';
import '../local/isar_service.dart';
import '../sync/media_compressor.dart';

final postRepositoryProvider = Provider<PostRepository>(
  (_) => PostRepository(),
);

/// Live feed posts, newest first — private posts excluded. See
/// [notesProvider] — the stream lives in the provider, not in `build`, so it
/// is created once and auto-disposed.
final postsProvider = StreamProvider.autoDispose<List<PostLocal>>(
  (ref) => ref.watch(postRepositoryProvider).watchAll(),
);

/// The PIN-gated private feed (private posts only).
final privatePostsProvider = StreamProvider.autoDispose<List<PostLocal>>(
  (ref) => ref.watch(postRepositoryProvider).watchPrivate(),
);

class PostRepository {
  Isar get _isar => IsarService.instance.db;

  Stream<List<PostLocal>> watchAll() {
    // Tombstones (pending remote delete) and private posts stay hidden.
    return _isar.postLocals
        .filter()
        .not()
        .syncStatusEqualTo('deleted')
        .isPrivateEqualTo(false)
        .sortByCreatedAtDesc()
        .watch(fireImmediately: true);
  }

  Stream<List<PostLocal>> watchPrivate() {
    return _isar.postLocals
        .filter()
        .not()
        .syncStatusEqualTo('deleted')
        .isPrivateEqualTo(true)
        .sortByCreatedAtDesc()
        .watch(fireImmediately: true);
  }

  /// Text-only edit (title + description + tags); media is immutable. A
  /// never-synced post stays 'pending'; a synced one is flagged 'edited' for
  /// the sync worker to PUT.
  Future<void> update({
    required int isarId,
    required String title,
    required String description,
    required List<String> tags,
  }) async {
    await _isar.writeTxn(() async {
      final p = await _isar.postLocals.get(isarId);
      if (p == null) return;
      p
        ..title = title
        ..description = description
        ..tags = tags
        ..syncStatus = p.remoteId == null ? 'pending' : 'edited';
      await _isar.postLocals.put(p);
    });
  }

  /// Never-synced posts vanish outright; synced ones keep a hidden tombstone
  /// until the remote DELETE is confirmed.
  Future<void> delete(int isarId) async {
    await _isar.writeTxn(() async {
      final p = await _isar.postLocals.get(isarId);
      if (p == null) return;
      if (p.remoteId == null) {
        await _isar.postLocals.delete(isarId);
      } else {
        p.syncStatus = 'deleted';
        await _isar.postLocals.put(p);
      }
    });
  }

  Future<void> create({
    required String title,
    required String description,
    required String authorId,
    required List<String> tags,
    required List<File> media,
    bool private = false,
    double? latitude,
    double? longitude,
    String? placeLabel,
  }) async {
    // Compress synchronously so the file we save to disk is the one
    // the sync worker will eventually upload.
    final compressed = <String>[];
    for (final f in media) {
      final out = MediaTools.isVideo(f.path)
          ? await MediaCompressor.compressVideo(f)
          : await MediaCompressor.compressImage(f);
      compressed.add(out.path);
    }

    final post = PostLocal()
      ..title = title
      ..description = description
      ..authorId = authorId
      ..tags = tags
      ..localMediaPaths = compressed
      ..isPrivate = private
      ..latitude = latitude
      ..longitude = longitude
      ..placeLabel = placeLabel
      ..createdAt = DateTime.now()
      ..syncStatus = 'pending';

    await _isar.writeTxn(() async {
      await _isar.postLocals.put(post);
    });
  }
}
