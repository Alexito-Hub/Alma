import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';

import '../local/isar/post_local.dart';
import '../local/isar_service.dart';
import '../sync/media_compressor.dart';

final postRepositoryProvider = Provider<PostRepository>(
  (_) => PostRepository(),
);

/// Live feed posts, newest first. See [notesProvider] — the stream lives in
/// the provider, not in `build`, so it is created once and auto-disposed.
final postsProvider = StreamProvider.autoDispose<List<PostLocal>>(
  (ref) => ref.watch(postRepositoryProvider).watchAll(),
);

class PostRepository {
  Isar get _isar => IsarService.instance.db;

  Stream<List<PostLocal>> watchAll() {
    return _isar.postLocals.where().sortByCreatedAtDesc().watch(
      fireImmediately: true,
    );
  }

  Future<void> create({
    required String title,
    required String description,
    required String authorId,
    required List<String> tags,
    required List<File> media,
  }) async {
    // Compress synchronously so the file we save to disk is the one
    // the sync worker will eventually upload.
    final compressed = <String>[];
    for (final f in media) {
      final isVideo =
          f.path.toLowerCase().endsWith('.mp4') ||
          f.path.toLowerCase().endsWith('.mov');
      final out = isVideo
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
      ..createdAt = DateTime.now()
      ..syncStatus = 'pending';

    await _isar.writeTxn(() async {
      await _isar.postLocals.put(post);
    });
  }
}
