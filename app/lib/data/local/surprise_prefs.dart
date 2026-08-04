import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// What the birthday surprise remembers between launches.
///
/// Keyed per occasion so next year's is a new key rather than a reset of this
/// one — whether she has seen *this* gift is a fact worth keeping.
class SurprisePrefs {
  SurprisePrefs._();

  static const _store = FlutterSecureStorage();
  static const _keyPlayed = 'alma.surprise.birthday_2026_08_14.played';

  /// True once it has run to the end at least once. Read defensively: if
  /// storage fails, report "not played" — showing the gift twice is a far
  /// smaller failure than never showing it.
  static Future<bool> played() async {
    try {
      return await _store.read(key: _keyPlayed) == '1';
    } catch (_) {
      return false;
    }
  }

  static Future<void> markPlayed() async {
    try {
      await _store.write(key: _keyPlayed, value: '1');
    } catch (_) {
      // Worst case it plays again; nothing here is worth crashing over.
    }
  }

  /// Clears the flag. Only reachable from the owner's preview controls, so a
  /// full run can be rehearsed from scratch as many times as needed.
  static Future<void> reset() async {
    try {
      await _store.delete(key: _keyPlayed);
    } catch (_) {
      // Ignored deliberately.
    }
  }
}
