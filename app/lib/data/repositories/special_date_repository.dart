import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

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
    // Tombstones (pending remote delete) stay hidden from the calendar.
    return _isar.specialDateLocals
        .filter()
        .not()
        .syncStatusEqualTo('deleted')
        .sortByDate()
        .watch(fireImmediately: true);
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

  /// Never-synced rows are removed outright. Rows the server already has are
  /// kept as hidden tombstones (`syncStatus == 'deleted'`) until the sync
  /// worker confirms the remote DELETE — otherwise the next hydration would
  /// resurrect them.
  Future<void> delete(int isarId) async {
    await _isar.writeTxn(() async {
      final row = await _isar.specialDateLocals.get(isarId);
      if (row == null) return;
      if (row.remoteId == null) {
        await _isar.specialDateLocals.delete(isarId);
      } else {
        row.syncStatus = 'deleted';
        await _isar.specialDateLocals.put(row);
      }
    });
  }
}
