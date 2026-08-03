import 'package:isar_community/isar.dart';

part 'comment_local.g.dart';

@collection
class CommentLocal {
  Id isarId = Isar.autoIncrement;

  @Index()
  String? remoteId;

  /// What the thread hangs off: 'note' for diary entries, 'post' for the
  /// retired feed.
  @Index()
  String targetType = 'post';

  /// Id of that target (kept named postId for the rows written before diary
  /// comments existed).
  @Index()
  late String postId;
  late String authorId;
  late String text;

  @Index()
  late DateTime createdAt;

  @Index()
  late String syncStatus;
}
