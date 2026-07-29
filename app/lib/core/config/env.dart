class Env {
  /// Base URL of the Alma backend (production origin behind the Cloudflare
  /// tunnel). Override for local dev with a dart-define, e.g.:
  ///   --dart-define=ALMA_API_URL=http://10.0.2.2:4000      (Android emulator)
  ///   --dart-define=ALMA_API_URL=http://192.168.1.11:4000  (device on the LAN)
  static const String apiBaseUrl = String.fromEnvironment(
    'ALMA_API_URL',
    defaultValue: 'https://alma.naziventas.shop',
  );

  /// Phoenix socket endpoint — same host as [apiBaseUrl], over wss in prod.
  /// Local dev override, e.g.:
  ///   --dart-define=ALMA_WS_URL=ws://10.0.2.2:4000/socket/websocket
  static const String wsUrl = String.fromEnvironment(
    'ALMA_WS_URL',
    defaultValue: 'wss://alma.naziventas.shop/socket/websocket',
  );

  static const Duration syncBatchInterval = Duration(minutes: 15);
  static const int syncBatchSize = 50;

  /// After this many failed upload attempts a post is marked `failed`
  /// (terminal) instead of being retried forever.
  static const int syncMaxRetries = 5;
}
