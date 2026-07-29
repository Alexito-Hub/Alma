import 'package:isar_community/isar.dart';

part 'comment_local.g.dart';

@collection
class CommentLocal {
  Id isarId = Isar.autoIncrement;

  @Index()
  String? remoteId;

  @Index()
  late String postId;
  late String authorId;
  late String text;

  @Index()
  late DateTime createdAt;

  @Index()
  late String syncStatus;
}
