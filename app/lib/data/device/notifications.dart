import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notifications for partner activity.
///
/// No push service is involved: the app raises these itself when the couple
/// channel delivers an event (instant while the app is alive) and when the
/// background sync tick finds something new (up to ~15 min later if the app
/// was killed). Ids are fixed per kind so a newer notification replaces the
/// previous one of the same kind instead of piling up.
class Notifications {
  Notifications._();

  static const _channelId = 'alma_partner';
  static const _channelName = 'Actividad de tu pareja';
  static const _channelDescription =
      'Avisos cuando tu pareja comparte un siente, una foto o una entrada del diario.';

  static const idStatus = 1;
  static const idNote = 2;
  static const idPost = 3;

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Safe to call repeatedly, and required once per isolate — the background
  /// sync isolate needs its own initialization before it can post anything.
  static Future<void> init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      ),
    );
    _ready = true;
  }

  /// Android 13+ gates notifications behind a runtime permission. Called from
  /// the UI isolate after sign-in; a denial simply means no notifications.
  static Future<void> requestPermission() async {
    await init();
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  static Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    await init();
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(''),
        ),
      ),
    );
  }

  /// "May siente" + the text they wrote.
  static Future<void> partnerStatus(String? partnerName, String text) => show(
    id: idStatus,
    title: '${partnerName ?? 'Tu pareja'} siente',
    body: text,
  );

  static Future<void> partnerNote(String? partnerName, String body) => show(
    id: idNote,
    title: '${partnerName ?? 'Tu pareja'} escribió en el diario',
    body: _preview(body),
  );

  static Future<void> partnerPost(String? partnerName, String title) => show(
    id: idPost,
    title: '${partnerName ?? 'Tu pareja'} compartió un momento',
    body: _preview(title),
  );

  static String _preview(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return 'Ábrelo en Alma';
    return clean.length <= 120 ? clean : '${clean.substring(0, 117)}…';
  }
}
