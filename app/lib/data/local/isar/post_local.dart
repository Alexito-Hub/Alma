import 'package:isar_community/isar.dart';

part 'post_local.g.dart';

@collection
class PostLocal {
  Id isarId = Isar.autoIncrement;

  @Index()
  String? remoteId;

  late String title;
  late String description;
  late String authorId;
  List<String> tags = const [];

  /// Local file paths waiting to be uploaded; replaced with remote URLs after sync.
  List<String> localMediaPaths = const [];
  List<String> remoteMediaUrls = const [];

  @Index()
  late DateTime createdAt;

  /// 'pending' | 'syncing' | 'synced' | 'failed'
  @Index()
  late String syncStatus;

  int retryCount = 0;
  String? lastError;
}
