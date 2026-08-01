import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/entities/user.dart';

/// Snapshot of the last successful `/me` response. When the server is
/// unreachable at startup, AuthGate restores the session from here so the app
/// still opens with all local data (feed, diary, info) instead of bouncing to
/// the login screen; anything created meanwhile stays queued until sync.
class UserCache {
  static const _key = 'alma.session_snapshot';
  static const _storage = FlutterSecureStorage();

  static Future<void> write(
    Map<String, dynamic> me,
    Map<String, dynamic>? partner,
  ) => _storage.write(
    key: _key,
    value: jsonEncode({'me': me, 'partner': partner}),
  );

  static Future<({User me, User? partner})?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final me = User.fromJson(Map<String, dynamic>.from(j['me'] as Map));
      final rawPartner = j['partner'];
      return (
        me: me,
        partner: rawPartner == null
            ? null
            : User.fromJson(Map<String, dynamic>.from(rawPartner as Map)),
      );
    } catch (_) {
      return null; // Corrupt/legacy snapshot — treat as absent.
    }
  }

  static Future<void> clear() => _storage.delete(key: _key);
}
