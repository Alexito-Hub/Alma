import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../local/isar/date_idea_local.dart';
import '../local/isar_service.dart';
import '../sync/media_compressor.dart';

final dateIdeaRepositoryProvider = Provider<DateIdeaRepository>(
  (_) => DateIdeaRepository(),
);

/// Every date idea the couple shares, newest first. The screen splits them
/// into pending and done.
final dateIdeasProvider = StreamProvider.autoDispose<List<DateIdeaLocal>>(
  (ref) => ref.watch(dateIdeaRepositoryProvider).watchAll(),
);

class DateIdeaRepository {
  Isar get _isar => IsarService.instance.db;

  Stream<List<DateIdeaLocal>> watchAll() {
    // Tombstones (pending remote delete) stay hidden.
    return _isar.dateIdeaLocals
        .filter()
        .not()
        .syncStatusEqualTo('deleted')
        .sortByCreatedAtDesc()
        .watch(fireImmediately: true);
  }

  Future<void> create({
    required String title,
    required String proposedBy,
    String description = '',
    DateTime? plannedAt,
    double? latitude,
    double? longitude,
    String? placeLabel,
  }) async {
    final row = DateIdeaLocal()
      ..title = title
      ..description = description
      ..proposedBy = proposedBy
      ..plannedAt = plannedAt
      ..latitude = latitude
      ..longitude = longitude
      ..placeLabel = placeLabel
      ..createdAt = DateTime.now()
      ..syncStatus = 'pending';

    await _isar.writeTxn(() async {
      await _isar.dateIdeaLocals.put(row);
    });
  }

  /// Text-only edit of an idea that hasn't happened yet.
  Future<void> update({
    required int isarId,
    required String title,
    required String description,
    DateTime? plannedAt,
    String? placeLabel,
  }) async {
    await _isar.writeTxn(() async {
      final row = await _isar.dateIdeaLocals.get(isarId);
      if (row == null) return;
      row
        ..title = title
        ..description = description
        ..plannedAt = plannedAt
        ..placeLabel = placeLabel
        ..syncStatus = row.remoteId == null ? 'pending' : 'edited';
      await _isar.dateIdeaLocals.put(row);
    });
  }

  /// Mark a date as lived. Photos are compressed up front, exactly like the
  /// feed used to do, so what's stored is what gets uploaded.
  Future<void> markDone({
    required int isarId,
    String? note,
    List<File> photos = const [],
  }) async {
    final compressed = <String>[];
    for (final f in photos) {
      final out = await MediaCompressor.compressImage(f);
      compressed.add(out.path);
    }

    await _isar.writeTxn(() async {
      final row = await _isar.dateIdeaLocals.get(isarId);
      if (row == null) return;
      row
        ..done = true
        ..doneAt = DateTime.now()
        ..doneNote = (note ?? '').trim().isEmpty ? null : note!.trim()
        ..imagePaths = compressed
        ..syncStatus = row.remoteId == null ? 'pending' : 'edited';
      await _isar.dateIdeaLocals.put(row);
    });
  }

  /// Back to the pending list — for when it was marked done by mistake.
  Future<void> markPending(int isarId) async {
    await _isar.writeTxn(() async {
      final row = await _isar.dateIdeaLocals.get(isarId);
      if (row == null) return;
      row
        ..done = false
        ..doneAt = null
        ..syncStatus = row.remoteId == null ? 'pending' : 'edited';
      await _isar.dateIdeaLocals.put(row);
    });
  }

  /// Never-synced rows vanish outright; synced ones keep a hidden tombstone
  /// until the remote DELETE is confirmed, so hydration can't resurrect them.
  Future<void> delete(int isarId) async {
    await _isar.writeTxn(() async {
      final row = await _isar.dateIdeaLocals.get(isarId);
      if (row == null) return;
      if (row.remoteId == null) {
        await _isar.dateIdeaLocals.delete(isarId);
      } else {
        row.syncStatus = 'deleted';
        await _isar.dateIdeaLocals.put(row);
      }
    });
  }
}
