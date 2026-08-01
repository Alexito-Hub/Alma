import 'package:home_widget/home_widget.dart';

/// Bridge to the Android home-screen widgets.
///
/// Values are written into the shared preferences `home_widget` exposes to the
/// native side; each `updateWidget` call then asks Android to redraw. Both
/// widgets are read-only surfaces, so the app is the single writer: the couple
/// channel and the periodic sync push fresh values in.
class HomeWidgets {
  HomeWidgets._();

  static const _statusProvider = 'pro.alma.piwkenyeyu.StatusWidgetProvider';
  static const _serverProvider = 'pro.alma.piwkenyeyu.ServerWidgetProvider';

  // Keys mirrored in the Kotlin providers.
  static const kStatusText = 'status_text';
  static const kStatusAuthor = 'status_author';
  static const kStatusAt = 'status_at';
  static const kServerStatus = 'server_status';
  static const kServerDetail = 'server_detail';
  static const kServerAt = 'server_at';

  /// Partner's current "siente" shown on the home screen.
  static Future<void> pushStatus({
    required String? author,
    required String? text,
    DateTime? at,
  }) async {
    await _write(kStatusAuthor, author ?? 'Tu pareja');
    await _write(kStatusText, text ?? '');
    await _write(kStatusAt, _stamp(at));
    await _update(_statusProvider);
  }

  /// Server health: `status` is ok/degraded/error/offline, `detail` a short
  /// line such as "Mongo 93 ms".
  static Future<void> pushServer({
    required String status,
    required String detail,
    DateTime? at,
  }) async {
    await _write(kServerStatus, status);
    await _write(kServerDetail, detail);
    await _write(kServerAt, _stamp(at));
    await _update(_serverProvider);
  }

  static Future<void> _write(String key, String value) async {
    try {
      await HomeWidget.saveWidgetData<String>(key, value);
    } catch (_) {
      // Widgets are a nice-to-have; never let them break a sync.
    }
  }

  static Future<void> _update(String provider) async {
    try {
      await HomeWidget.updateWidget(qualifiedAndroidName: provider);
    } catch (_) {
      /* no widget on the home screen yet, or platform without support */
    }
  }

  static String _stamp(DateTime? at) {
    final t = (at ?? DateTime.now()).toLocal();
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }
}
