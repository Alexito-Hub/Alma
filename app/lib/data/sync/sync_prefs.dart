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
}
