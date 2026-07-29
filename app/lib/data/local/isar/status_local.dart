import 'package:isar/isar.dart';

part 'status_local.g.dart';

@collection
class StatusLocal {
  Id isarId = Isar.autoIncrement;

  /// Stable id so we can upsert the *current* status row per author.
  @Index(unique: true, replace: true)
  late String authorId;

  late String text;

  @Index()
  late DateTime updatedAt;

  @Index()
  late String syncStatus;
}
