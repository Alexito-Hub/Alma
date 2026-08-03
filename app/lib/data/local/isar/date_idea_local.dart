import 'package:isar_community/isar.dart';

part 'date_idea_local.g.dart';

/// A "cita": somewhere the couple wants to go, or somewhere they already went.
///
/// Unlike a diary entry — which records what happened — this looks forward:
/// it starts as an idea anyone can propose, and becomes a memory when it's
/// marked done, optionally with photos and a note about how it went.
@collection
class DateIdeaLocal {
  Id isarId = Isar.autoIncrement;

  @Index()
  String? remoteId;

  late String title;
  String description = '';

  /// Who proposed it.
  late String proposedBy;

  /// Optional day they're aiming for.
  DateTime? plannedAt;

  @Index()
  bool done = false;
  DateTime? doneAt;

  /// How it went, written when marking it done.
  String? doneNote;

  /// Photos attached when marking it done.
  List<String> imagePaths = const [];
  List<String> remoteImageUrls = const [];

  double? latitude;
  double? longitude;
  String? placeLabel;

  @Index()
  late DateTime createdAt;

  /// 'pending' | 'synced' | 'edited' | 'deleted'
  @Index()
  late String syncStatus;
}
