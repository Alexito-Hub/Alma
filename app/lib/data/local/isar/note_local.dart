import 'package:isar/isar.dart';

part 'note_local.g.dart';

@collection
class NoteLocal {
  Id isarId = Isar.autoIncrement;

  @Index()
  String? remoteId;

  late String body;
  late String authorId;

  @Index()
  late DateTime createdAt;

  @Index()
  late String syncStatus;

  int retryCount = 0;
  String? lastError;

  // ── Diario 2.0: optional rich attributes ──────────────────────────────
  /// Mood emoji chosen for the entry (e.g. 😊). Null = no mood set.
  String? mood;

  /// An optional link the entry references (song, article, place…).
  String? link;

  /// Locally-stored photos attached to the entry (a carousel). Uploaded copies
  /// land in [remoteImageUrls] once sync is wired up.
  List<String> imagePaths = const [];
  List<String> remoteImageUrls = const [];

  /// The partner's private reaction to this entry (replaces likes): an icon
  /// key (see the diary's reaction map) and who left it.
  String? reactionEmoji;
  String? reactionAuthorId;

  /// A voice note attached to the entry (local path; remote once synced).
  String? audioPath;
  String? remoteAudioUrl;

  /// A short video attached to the entry (local path; remote once synced).
  String? videoPath;
  String? remoteVideoUrl;

  /// Where the entry was written (optional geotag) + a human place label.
  double? latitude;
  double? longitude;
  String? placeLabel;
}
