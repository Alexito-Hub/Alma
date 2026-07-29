import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:phoenix_socket/phoenix_socket.dart';

import '../../domain/entities/status_message.dart';
import '../local/isar/status_local.dart';
import '../local/isar_service.dart';
import '../remote/ws_client.dart';
import 'auth_repository.dart';

final statusRepositoryProvider = Provider<StatusRepository>(
  (_) => StatusRepository(),
);

/// My own current status row (what I last posted), or null. Reacts to the
/// signed-in user changing.
final myStatusProvider = StreamProvider.autoDispose<StatusLocal?>((ref) {
  final me = ref.watch(currentUserProvider);
  if (me == null) return Stream.value(null);
  return ref.watch(statusRepositoryProvider).watchMine(me.id);
});

/// The partner's live status, pushed over the couple WebSocket channel.
/// Watching this provider also ensures we're subscribed to the channel.
final partnerStatusProvider = StreamProvider.autoDispose<StatusMessage>((ref) {
  final me = ref.watch(currentUserProvider);
  final repo = ref.watch(statusRepositoryProvider);
  final coupleId = me?.coupleId;
  if (coupleId != null && coupleId.isNotEmpty) {
    repo.subscribeToCouple(coupleId);
  }
  return repo.partnerStream();
});

class StatusRepository {
  Isar get _isar => IsarService.instance.db;
  PhoenixChannel? _channel;
  final _partnerCtrl = StreamController<StatusMessage>.broadcast();

  Stream<StatusLocal?> watchMine(String authorId) {
    return _isar.statusLocals
        .filter()
        .authorIdEqualTo(authorId)
        .watch(fireImmediately: true)
        .map((list) => list.isEmpty ? null : list.first);
  }

  Stream<StatusMessage> partnerStream() => _partnerCtrl.stream;

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

  String? _subscribedCoupleId;

  Future<void> subscribeToCouple(String coupleId) async {
    // Already wired to the same room — phoenix_socket only allows one
    // join() per channel, so just no-op.
    if (_subscribedCoupleId == coupleId && _channel != null) return;

    // Switching couples (rare) or reconnecting: drop the old channel first.
    if (_channel != null) {
      try {
        await _channel!.leave().future;
      } catch (_) {
        /* ignore */
      }
      _channel = null;
    }

    final socket = await WsClient.instance.connect();
    final ch = socket.addChannel(topic: 'couple:$coupleId');
    ch.messages.listen((msg) {
      if (msg.event.value == 'status_updated' && msg.payload != null) {
        _partnerCtrl.add(
          StatusMessage.fromJson(Map<String, dynamic>.from(msg.payload!)),
        );
      }
    });
    await ch.join().future;
    _channel = ch;
    _subscribedCoupleId = coupleId;
  }

  Future<void> dispose() async {
    await _channel?.leave().future;
    await _partnerCtrl.close();
  }
}
