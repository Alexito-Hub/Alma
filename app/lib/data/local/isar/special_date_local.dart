import 'package:isar/isar.dart';

part 'special_date_local.g.dart';

/// A meaningful date the couple marks on the calendar — an anniversary, a
/// birthday, a trip — separate from diary entries. When [recurring] is true it
/// shows every year on the same month/day.
@collection
class SpecialDateLocal {
  Id isarId = Isar.autoIncrement;

  @Index()
  String? remoteId;

  @Index()
  late DateTime date;

  bool recurring = true;

  late String title;
  String? emoji;

  late String createdBy;

  @Index()
  late String syncStatus;
}
