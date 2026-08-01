import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small UI preferences for the diary screen.
class DiaryPrefs {
  static const _kCalendarOpen = 'alma.diary.calendar_open';
  static const _storage = FlutterSecureStorage();

  /// Whether the calendar is expanded. Defaults to false (collapsed).
  static Future<bool> calendarOpen() async =>
      (await _storage.read(key: _kCalendarOpen)) == '1';

  static Future<void> setCalendarOpen(bool open) =>
      _storage.write(key: _kCalendarOpen, value: open ? '1' : '0');
}
