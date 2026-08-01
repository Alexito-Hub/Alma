import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// User-facing sync preferences. Persisted across app launches.
class SyncPrefs {
  SyncPrefs._();
  static const _store = FlutterSecureStorage();
  static const _keyWifiOnly = 'alma.sync.wifi_only';

  /// When true, the sync worker only uploads on Wi-Fi. When false, also
  /// uses mobile data. Default: true (saves bytes).
  static Future<bool> wifiOnly() async {
    final raw = await _store.read(key: _keyWifiOnly);
    return raw == null ? true : raw == '1';
  }

  static Future<void> setWifiOnly(bool value) async {
    await _store.write(key: _keyWifiOnly, value: value ? '1' : '0');
  }

  /// Last partner item we already notified about, per kind (`status`, `note`,
  /// `post`). Stores the item's timestamp so the background tick can tell new
  /// activity from what the user has already been told.
  static Future<String?> marker(String kind) =>
      _store.read(key: 'alma.notify.$kind');

  static Future<void> setMarker(String kind, String stamp) =>
      _store.write(key: 'alma.notify.$kind', value: stamp);
}
