import 'package:isar_community/isar.dart';

part 'status_local.g.dart';

@collection
class StatusLocal {
  Id isarId = Isar.autoIncrement;

  /// Stable id so we can upsert the *current* status row per author.
  @Index(unique: true, replace: true)
  late String authorId;

  late String text;

  /// Optional snapshot that came with the status: a photo taken right then.
  /// [imagePath] is the local file (ours, or a partner photo we haven't
  /// downloaded); [remoteImageUrl] is the server copy once uploaded.
  String? imagePath;
  String? remoteImageUrl;

  @Index()
  late DateTime updatedAt;

  @Index()
  late String syncStatus;
}
