class Env {
  static const String apiBaseUrl = String.fromEnvironment(
    'ALMA_API_URL',
    defaultValue: 'http://10.0.2.2:4000',
  );

  static const String wsUrl = String.fromEnvironment(
    'ALMA_WS_URL',
    defaultValue: 'ws://10.0.2.2:4000/socket/websocket',
  );

  static const Duration syncBatchInterval = Duration(minutes: 15);
  static const int syncBatchSize = 50;

  /// After this many failed upload attempts a post is marked `failed`
  /// (terminal) instead of being retried forever.
  static const int syncMaxRetries = 5;
}
