import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../local/isar/note_local.dart';
import '../local/isar_service.dart';

final noteRepositoryProvider = Provider<NoteRepository>(
  (_) => NoteRepository(),
);

/// Live diary entries, newest first. Owned by Riverpod so the Isar
/// subscription is created once and disposed automatically — never rebuilt
/// per-frame from inside a widget's `build`.
final notesProvider = StreamProvider.autoDispose<List<NoteLocal>>(
  (ref) => ref.watch(noteRepositoryProvider).watchAll(),
);

/// Stream-based: the UI subscribes to Isar and re-renders the moment we
/// insert. The sync worker updates the *same* rows in the background.
class NoteRepository {
  Isar get _isar => IsarService.instance.db;

  Stream<List<NoteLocal>> watchAll() {
    return _isar.noteLocals.where().sortByCreatedAtDesc().watch(
      fireImmediately: true,
    );
  }

  /// Create a diary entry. [createdAt] lets the calendar attach an entry to a
  /// specific day; the rich attributes (mood, link, photos) are all optional.
  Future<void> create({
    required String body,
    required String authorId,
    DateTime? createdAt,
    String? mood,
    String? link,
    List<String> imagePaths = const [],
    String? audioPath,
    String? videoPath,
    double? latitude,
    double? longitude,
    String? placeLabel,
  }) async {
    final note = NoteLocal()
      ..body = body
      ..authorId = authorId
      ..createdAt = createdAt ?? DateTime.now()
      ..mood = mood
      ..link = link
      ..imagePaths = imagePaths
      ..audioPath = audioPath
      ..videoPath = videoPath
      ..latitude = latitude
      ..longitude = longitude
      ..placeLabel = placeLabel
      ..syncStatus = 'pending';
    await _isar.writeTxn(() async {
      await _isar.noteLocals.put(note);
    });
  }

  /// Set (or clear, with a null emoji) the partner's private reaction on an
  /// entry. Replaces "likes". Local-only for now.
  Future<void> setReaction({
    required int isarId,
    required String authorId,
    String? emoji,
  }) async {
    await _isar.writeTxn(() async {
      final n = await _isar.noteLocals.get(isarId);
      if (n == null) return;
      n
        ..reactionEmoji = emoji
        ..reactionAuthorId = emoji == null ? null : authorId;
      await _isar.noteLocals.put(n);
    });
  }
}
