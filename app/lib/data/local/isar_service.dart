import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'isar/comment_local.dart';
import 'isar/date_idea_local.dart';
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
  ///
  /// Every `@collection` in `data/local/isar/` must be listed here: Isar only
  /// knows about the schemas it was opened with, so a missing entry doesn't
  /// fail to compile — it throws the first time that collection is touched at
  /// runtime. That is exactly how Citas shipped broken.
  static const List<CollectionSchema<dynamic>> schemas = [
    PostLocalSchema,
    NoteLocalSchema,
    StatusLocalSchema,
    CommentLocalSchema,
    SpecialDateLocalSchema,
    DateIdeaLocalSchema,
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
  ///
  /// Deliberately `Isar.clear()` rather than a hand-written list of
  /// `.clear()` calls: the list drifted once already (special dates and citas
  /// survived logout), and this cannot drift because Isar derives it from the
  /// schemas the instance was opened with.
  Future<void> wipe() async {
    final i = _isar;
    if (i == null) return;
    await i.writeTxn(() => i.clear());
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
