import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';

import '../local/isar/special_date_local.dart';
import '../local/isar_service.dart';

final specialDateRepositoryProvider = Provider<SpecialDateRepository>(
  (_) => SpecialDateRepository(),
);

/// Live list of the couple's special dates (anniversaries, birthdays…).
final specialDatesProvider = StreamProvider.autoDispose<List<SpecialDateLocal>>(
  (ref) => ref.watch(specialDateRepositoryProvider).watchAll(),
);

class SpecialDateRepository {
  Isar get _isar => IsarService.instance.db;

  Stream<List<SpecialDateLocal>> watchAll() {
    return _isar.specialDateLocals.where().sortByDate().watch(
      fireImmediately: true,
    );
  }

  Future<void> create({
    required DateTime date,
    required String title,
    required String createdBy,
    String? emoji,
    bool recurring = true,
  }) async {
    final row = SpecialDateLocal()
      ..date = DateTime(date.year, date.month, date.day)
      ..title = title
      ..emoji = emoji
      ..recurring = recurring
      ..createdBy = createdBy
      ..syncStatus = 'pending';
    await _isar.writeTxn(() async {
      await _isar.specialDateLocals.put(row);
    });
  }

  Future<void> delete(int isarId) async {
    await _isar.writeTxn(() async {
      await _isar.specialDateLocals.delete(isarId);
    });
  }
}
