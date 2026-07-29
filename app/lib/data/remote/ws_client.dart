import 'dart:async';

import 'package:phoenix_socket/phoenix_socket.dart';

import '../../core/config/env.dart';
import 'token_storage.dart';

/// Singleton Phoenix socket. Authenticates with the JWT as a query param
/// and auto-reconnects on drops (phoenix_socket already retries, but we
/// expose a fresh handle each time so previous channels reattach).
class WsClient {
  WsClient._();
  static final WsClient instance = WsClient._();

  PhoenixSocket? _socket;
  Future<PhoenixSocket>? _connecting;

  Future<PhoenixSocket> connect() async {
    final cached = _socket;
    if (cached != null) return cached;
    // Coalesce concurrent calls onto one connect.
    final inFlight = _connecting;
    if (inFlight != null) return inFlight;

    final fut = _doConnect();
    _connecting = fut;
    try {
      final s = await fut;
      _socket = s;
      return s;
    } finally {
      _connecting = null;
    }
  }

  Future<PhoenixSocket> _doConnect() async {
    final token = await TokenStorage.read();
    final s = PhoenixSocket(
      Env.wsUrl,
      socketOptions: PhoenixSocketOptions(
        params: {if (token != null) 'token': token},
      ),
    );

    // Drop our cached socket when the connection closes so the next
    // connect() request opens a fresh one.
    s.closeStream.listen((_) {
      if (identical(_socket, s)) _socket = null;
    });

    await s.connect();
    return s;
  }

  PhoenixChannel channel(String topic, [Map<String, dynamic>? params]) {
    final s = _socket;
    if (s == null) {
      throw StateError('WsClient.connect() not called yet');
    }
    return s.addChannel(topic: topic, parameters: params);
  }

  Future<void> dispose() async {
    final s = _socket;
    _socket = null;
    _connecting = null;
    try {
      s?.close();
    } catch (_) {
      /* ignore */
    }
  }
}
