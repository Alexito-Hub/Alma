import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'isar/comment_local.dart';
import 'isar/note_local.dart';
import 'isar/post_local.dart';
import 'isar/special_date_local.dart';
import 'isar/status_local.dart';

/// Single Isar instance for the whole app (and for the WorkManager isolate,
/// which reopens via [openForIsolate]).
class IsarService {
  IsarService._();
  static final IsarService instance = IsarService._();

  /// The one schema list, shared by the UI isolate ([open]) and any
  /// background isolate ([openForIsolate]) so the two can never drift.
  static const List<CollectionSchema<dynamic>> schemas = [
    PostLocalSchema,
    NoteLocalSchema,
    StatusLocalSchema,
    CommentLocalSchema,
    SpecialDateLocalSchema,
  ];

  Isar? _isar;
  Isar get db {
    final i = _isar;
    if (i == null) {
      throw StateError('IsarService.open() was not awaited');
    }
    return i;
  }

  Future<void> open() async {
    if (_isar != null) return;
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      schemas,
      directory: dir.path,
      name: 'alma',
      inspector: false,
    );
  }

  /// Wipes every collection. Used on logout so the next user doesn't see
  /// the previous user's data sitting in the cache.
  Future<void> wipe() async {
    final i = _isar;
    if (i == null) return;
    await i.writeTxn(() async {
      await i.postLocals.clear();
      await i.noteLocals.clear();
      await i.statusLocals.clear();
      await i.commentLocals.clear();
    });
  }

  /// Background isolates (WorkManager) need their own Isar handle.
  static Future<Isar> openForIsolate() async {
    final dir = await getApplicationDocumentsDirectory();
    return Isar.open(
      schemas,
      directory: dir.path,
      name: 'alma',
      inspector: false,
    );
  }
}
