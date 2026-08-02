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

  /// Private posts only show in the PIN-gated feed, never in the main one.
  @Index()
  bool isPrivate = false;

  /// Where the moment happened (optional). [placeLabel] is what the couple
  /// actually reads — either the reverse-geocoded street/venue or a name they
  /// typed themselves ("Cine del centro").
  double? latitude;
  double? longitude;
  String? placeLabel;

  int retryCount = 0;
  String? lastError;
}
