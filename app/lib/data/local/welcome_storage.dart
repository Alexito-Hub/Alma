import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Remembers whether the one-time welcome/onboarding has already been shown,
/// so it only appears on the very first launch.
class WelcomeStorage {
  static const _key = 'alma.welcome_seen';
  static const _storage = FlutterSecureStorage();

  static Future<bool> hasSeen() async =>
      (await _storage.read(key: _key)) == '1';

  static Future<void> markSeen() => _storage.write(key: _key, value: '1');
}
