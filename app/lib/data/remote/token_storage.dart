import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const _key = 'alma.jwt';
  static const _storage = FlutterSecureStorage();

  /// Last token read or written, held in memory for this isolate.
  ///
  /// Secure storage is async, but media widgets need the `Authorization`
  /// header *while building*: `CachedNetworkImage`, `VideoPlayerController`
  /// and the thumbnail generator all take their headers up front. Remembering
  /// the token after the first read is what lets `/media` require a session
  /// without threading a future through every image in the app.
  static String? _cached;
  static String? get cached => _cached;

  static Future<String?> read() async =>
      _cached ??= await _storage.read(key: _key);

  static Future<void> write(String token) async {
    _cached = token;
    await _storage.write(key: _key, value: token);
  }

  static Future<void> clear() async {
    _cached = null;
    await _storage.delete(key: _key);
  }
}
