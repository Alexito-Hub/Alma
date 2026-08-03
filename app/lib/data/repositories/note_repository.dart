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

/// The PIN-gated diary: entries marked private, kept out of every other view.
final privateNotesProvider = StreamProvider.autoDispose<List<NoteLocal>>(
  (ref) => ref.watch(noteRepositoryProvider).watchPrivate(),
);

/// Stream-based: the UI subscribes to Isar and re-renders the moment we
/// insert. The sync worker updates the *same* rows in the background.
class NoteRepository {
  Isar get _isar => IsarService.instance.db;

  Stream<List<NoteLocal>> watchAll() {
    // Tombstones (pending remote delete) and private entries stay hidden.
    return _isar.noteLocals
        .filter()
        .not()
        .syncStatusEqualTo('deleted')
        .isPrivateEqualTo(false)
        .sortByCreatedAtDesc()
        .watch(fireImmediately: true);
  }

  Stream<List<NoteLocal>> watchPrivate() {
    return _isar.noteLocals
        .filter()
        .not()
        .syncStatusEqualTo('deleted')
        .isPrivateEqualTo(true)
        .sortByCreatedAtDesc()
        .watch(fireImmediately: true);
  }

  /// Text-only edit (body + mood + link). A never-synced entry stays
  /// 'pending' (its creation payload will carry the new text); a synced one is
  /// flagged 'edited' so the sync worker PUTs the change.
  Future<void> updateEntry({
    required int isarId,
    required String body,
    String? mood,
    String? link,
  }) async {
    await _isar.writeTxn(() async {
      final n = await _isar.noteLocals.get(isarId);
      if (n == null) return;
      n
        ..body = body
        ..mood = mood
        ..link = link
        ..syncStatus = n.remoteId == null ? 'pending' : 'edited';
      await _isar.noteLocals.put(n);
    });
  }

  /// Never-synced entries vanish outright; synced ones keep a hidden
  /// tombstone until the remote DELETE is confirmed (mirrors special dates) so
  /// hydration can't resurrect them.
  Future<void> delete(int isarId) async {
    await _isar.writeTxn(() async {
      final n = await _isar.noteLocals.get(isarId);
      if (n == null) return;
      if (n.remoteId == null) {
        await _isar.noteLocals.delete(isarId);
      } else {
        n.syncStatus = 'deleted';
        await _isar.noteLocals.put(n);
      }
    });
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
    List<String> videoPaths = const [],
    double? latitude,
    double? longitude,
    String? placeLabel,
    bool private = false,
  }) async {
    final note = NoteLocal()
      ..body = body
      ..authorId = authorId
      ..createdAt = createdAt ?? DateTime.now()
      ..mood = mood
      ..link = link
      ..imagePaths = imagePaths
      ..audioPath = audioPath
      ..videoPaths = videoPaths
      ..latitude = latitude
      ..longitude = longitude
      ..placeLabel = placeLabel
      ..isPrivate = private
      ..syncStatus = 'pending';
    await _isar.writeTxn(() async {
      await _isar.noteLocals.put(note);
    });
  }

  /// Set (or clear, with a null emoji) the reaction on an entry. Replaces
  /// "likes".
  ///
  /// Flagged for sync like any other change: a reaction is something you leave
  /// *for the other person*, so one that never left the phone was pointless.
  /// It travels on the same PUT as a text edit; the server scopes the reaction
  /// to the couple and the body to its author, so reacting to an entry you
  /// didn't write works and still can't rewrite it.
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
        ..reactionAuthorId = emoji == null ? null : authorId
        ..syncStatus = n.remoteId == null ? 'pending' : 'edited';
      await _isar.noteLocals.put(n);
    });
  }
}
