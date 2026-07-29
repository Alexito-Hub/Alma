import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const _key = 'alma.jwt';
  static const _storage = FlutterSecureStorage();

  static Future<String?> read() => _storage.read(key: _key);
  static Future<void> write(String token) =>
      _storage.write(key: _key, value: token);
  static Future<void> clear() => _storage.delete(key: _key);
}
