import 'package:flutter/material.dart';

import '../../../core/theme/neo.dart';
import '../../../data/remote/health_api.dart';

/// "Estado del servidor" — a readable view of `GET /health`: whether Mongo
/// answers and how fast, how much media and disk are in use, and how the VM
/// is doing. Refreshing here also updates the home-screen widget.
class ServerStatusScreen extends StatefulWidget {
  const ServerStatusScreen({super.key});

  @override
  State<ServerStatusScreen> createState() => _ServerStatusScreenState();
}

class _ServerStatusScreenState extends State<ServerStatusScreen> {
  ServerHealth? _health;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final health = await HealthApi.fetch();
    if (!mounted) return;
    setState(() {
      _health = health;
      _loading = false;
    });
  }

  Color get _accent => switch (_health?.status) {
    'ok' => Neo.mint,
    'degraded' => Neo.yellow,
    null => Neo.white,
    _ => Neo.coral,
  };

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    final h = _health;

    return Scaffold(
      backgroundColor: Neo.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  NeoIconButton(
                    icon: Icons.arrow_back_rounded,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Estado del servidor', style: txt.titleLarge),
                  ),
                  NeoIconButton(
                    icon: Icons.refresh_rounded,
                    color: Neo.sky,
                    onPressed: _loading ? null : _load,
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                color: Neo.ink,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
                  children: [
                    if (h == null && _loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 60),
                        child: Center(
                          child: NeoLoader(size: 16, fill: Neo.paper),
                        ),
                      )
                    else if (h != null) ...[
                      _Summary(health: h, accent: _accent, busy: _loading),
                      const SizedBox(height: 18),
                      if (!h.reachable)
                        _Card(
                          icon: Icons.cloud_off_rounded,
                          color: Neo.coral,
                          title: 'Sin respuesta',
                          rows: [
                            ('Detalle', h.error ?? 'No se pudo conectar'),
                            ('Qué revisar', 'Que la laptop esté encendida'),
                          ],
                        )
                      else ...[
                        _Card(
                          icon: Icons.storage_rounded,
                          color: Neo.sky,
                          title: 'Base de datos',
                          rows: _mongoRows(h),
                        ),
                        const SizedBox(height: 12),
                        _Card(
                          icon: Icons.photo_library_rounded,
                          color: Neo.rose,
                          title: 'Recuerdos guardados',
                          rows: _mediaRows(h),
                        ),
                        const SizedBox(height: 12),
                        _Card(
                          icon: Icons.save_rounded,
                          color: Neo.yellow,
                          title: 'Espacio en disco',
                          rows: _diskRows(h),
                        ),
                        const SizedBox(height: 12),
                        _Card(
                          icon: Icons.memory_rounded,
                          color: Neo.lilac,
                          title: 'Sistema',
                          rows: _systemRows(h),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<(String, String)> _mongoRows(ServerHealth h) {
    final m = h.check('mongo');
    return [
      ('Estado', _statusWord(m['status'])),
      ('Latencia', m['latency_ms'] == null ? '—' : '${m['latency_ms']} ms'),
      if (m['error'] != null) ('Error', '${m['error']}'),
    ];
  }

  List<(String, String)> _mediaRows(ServerHealth h) {
    final m = h.check('media');
    return [
      ('Archivos', '${m['files'] ?? '—'}'),
      ('Ocupado', '${m['size_human'] ?? '—'}'),
      ('Escribible', m['writable'] == true ? 'Sí' : 'No'),
    ];
  }

  List<(String, String)> _diskRows(ServerHealth h) {
    final d = h.check('disk');
    return [
      ('Libre', '${d['free_human'] ?? '—'}'),
      ('Total', '${d['total_human'] ?? '—'}'),
      ('En uso', d['used_percent'] == null ? '—' : '${d['used_percent']}%'),
    ];
  }

  List<(String, String)> _systemRows(ServerHealth h) {
    final s = h.check('system');
    return [
      ('Memoria', '${s['memory_human'] ?? '—'}'),
      ('Procesos', '${s['processes'] ?? '—'}'),
      ('Elixir / OTP', '${s['elixir'] ?? '—'} / ${s['otp'] ?? '—'}'),
      if (h.version != null) ('Versión', h.version!),
      if (h.environment != null) ('Entorno', h.environment!),
    ];
  }

  static String _statusWord(Object? raw) => switch (raw) {
    'ok' => 'Correcto',
    'warn' => 'Con avisos',
    'error' => 'Con fallos',
    _ => '—',
  };
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.health,
    required this.accent,
    required this.busy,
  });

  final ServerHealth health;
  final Color accent;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    return NeoBox(
      width: double.infinity,
      color: accent,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              NeoIconBadge(
                icon: health.healthy
                    ? Icons.check_circle_rounded
                    : Icons.warning_amber_rounded,
                color: Neo.white,
                size: 40,
                iconSize: 22,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(health.label, style: txt.headlineSmall)),
              if (busy) const NeoLoader(size: 9),
            ],
          ),
          const SizedBox(height: 12),
          Text(health.headline, style: txt.bodyMedium),
          if (health.uptimeHuman != null) ...[
            const SizedBox(height: 4),
            Text(
              'Encendido hace ${health.uptimeHuman}',
              style: txt.bodySmall?.copyWith(
                color: Neo.ink.withValues(alpha: .7),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.color,
    required this.title,
    required this.rows,
  });

  final IconData icon;
  final Color color;
  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    return NeoBox(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      shadowOffset: Neo.shadowBtn,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NeoSectionLabel(icon: icon, label: title, color: color),
          const SizedBox(height: 12),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: txt.bodySmall?.copyWith(
                      color: Neo.ink.withValues(alpha: .6),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      value,
                      textAlign: TextAlign.right,
                      style: txt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
