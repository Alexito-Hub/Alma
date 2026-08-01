import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../local/isar/status_local.dart';
import '../local/isar_service.dart';
import 'auth_repository.dart';

final statusRepositoryProvider = Provider<StatusRepository>(
  (_) => StatusRepository(),
);

/// My own current status row (what I last posted), or null. Reacts to the
/// signed-in user changing.
final myStatusProvider = StreamProvider.autoDispose<StatusLocal?>((ref) {
  final me = ref.watch(currentUserProvider);
  if (me == null) return Stream.value(null);
  return ref.watch(statusRepositoryProvider).watchByAuthor(me.id);
});

/// The partner's current status, read from the local cache — which both the
/// initial hydration and the live couple channel keep fresh (see [Hydrator],
/// the single owner of that subscription). Reading from Isar instead of only
/// a live stream means it also shows right after an app restart, not just
/// when the partner posts while we happen to be online.
final partnerStatusProvider = StreamProvider.autoDispose<StatusLocal?>((ref) {
  final partner = ref.watch(partnerUserProvider);
  final repo = ref.watch(statusRepositoryProvider);
  final partnerId = partner?.id;
  if (partnerId == null) return Stream<StatusLocal?>.value(null);
  return repo.watchByAuthor(partnerId);
});

/// Local reads/writes for statuses. Incoming partner statuses are persisted by
/// [Hydrator], which owns the couple channel.
class StatusRepository {
  Isar get _isar => IsarService.instance.db;

  Stream<StatusLocal?> watchByAuthor(String authorId) {
    return _isar.statusLocals
        .filter()
        .authorIdEqualTo(authorId)
        .watch(fireImmediately: true)
        .map((list) => list.isEmpty ? null : list.first);
  }

  Future<void> updateMine({
    required String authorId,
    required String text,
  }) async {
    final existing = await _isar.statusLocals
        .filter()
        .authorIdEqualTo(authorId)
        .findFirst();
    final row = existing ?? StatusLocal();
    row
      ..authorId = authorId
      ..text = text
      ..updatedAt = DateTime.now()
      ..syncStatus = 'pending';
    await _isar.writeTxn(() async {
      await _isar.statusLocals.put(row);
    });
  }
}
