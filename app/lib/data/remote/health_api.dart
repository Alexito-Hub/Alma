import 'package:dio/dio.dart';

import 'api_client.dart';

/// Snapshot of `GET /health`. The endpoint is public, so this works even when
/// the session has expired — handy precisely when something is wrong.
class ServerHealth {
  const ServerHealth({
    required this.status,
    this.uptimeHuman,
    this.version,
    this.environment,
    this.checks = const {},
    this.error,
  });

  /// `ok`, `degraded`, `error` (server answered) or `offline` (unreachable).
  final String status;
  final String? uptimeHuman;
  final String? version;
  final String? environment;
  final Map<String, dynamic> checks;
  final String? error;

  bool get reachable => status != 'offline';
  bool get healthy => status == 'ok';

  String get label => switch (status) {
    'ok' => 'Todo bien',
    'degraded' => 'Con avisos',
    'error' => 'Con fallos',
    _ => 'Sin conexión',
  };

  Map<String, dynamic> check(String name) {
    final raw = checks[name];
    return raw is Map ? Map<String, dynamic>.from(raw) : const {};
  }

  /// Mongo round-trip in milliseconds, when the server answered.
  num? get mongoLatencyMs => check('mongo')['latency_ms'] as num?;

  /// One-line summary used by the home-screen widget.
  String get headline {
    if (!reachable) return 'No responde';
    final latency = mongoLatencyMs;
    if (status == 'ok' && latency != null) {
      return 'Mongo ${latency.round()} ms';
    }
    final mongo = check('mongo');
    if (mongo['status'] == 'error') return 'Base de datos caída';
    final disk = check('disk');
    if (disk['status'] == 'warn') return 'Disco casi lleno';
    final media = check('media');
    if (media['status'] == 'warn') return 'Almacenamiento con avisos';
    return label;
  }

  factory ServerHealth.fromJson(Map<String, dynamic> j) => ServerHealth(
    status: j['status']?.toString() ?? 'error',
    uptimeHuman: j['uptime_human']?.toString(),
    version: j['version']?.toString(),
    environment: j['environment']?.toString(),
    checks: j['checks'] is Map
        ? Map<String, dynamic>.from(j['checks'] as Map)
        : const {},
  );

  factory ServerHealth.offline(Object error) =>
      ServerHealth(status: 'offline', error: error.toString());
}

class HealthApi {
  HealthApi._();

  /// Never throws: an unreachable server is itself a health answer.
  static Future<ServerHealth> fetch() async {
    try {
      final res = await ApiClient.instance.dio.get<dynamic>(
        '/health',
        options: Options(
          // A 503 body is exactly what we want to read, not an exception.
          validateStatus: (code) => code != null && code < 600,
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
        ),
      );
      final data = res.data;
      if (data is Map) {
        return ServerHealth.fromJson(Map<String, dynamic>.from(data));
      }
      // A proxy error page (Cloudflare 502/530) instead of our JSON.
      return ServerHealth.offline('HTTP ${res.statusCode}');
    } catch (e) {
      return ServerHealth.offline(e);
    }
  }
}
