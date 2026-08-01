import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/neo.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/sync/sync_prefs.dart';
import '../auth/profile_screen.dart';
import 'server_status_screen.dart';

/// Top-level "Ajustes" tab: account and sync — the settings that used to be
/// scattered across Profile and the Create sheet.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _wifiOnly = true;

  @override
  void initState() {
    super.initState();
    SyncPrefs.wifiOnly().then((v) {
      if (mounted) setState(() => _wifiOnly = v);
    });
  }

  Future<void> _logout() async {
    await ref.read(authRepositoryProvider).logout();
    ref.read(currentUserProvider.notifier).state = null;
    ref.read(partnerUserProvider.notifier).state = null;
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    final txt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Neo.paper,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 32),
          children: [
            Row(
              children: [
                const NeoIconBadge(
                  icon: Icons.settings_rounded,
                  color: Neo.lilac,
                ),
                const SizedBox(width: 12),
                Text('Ajustes', style: txt.titleLarge),
              ],
            ),
            const SizedBox(height: 24),

            const _SectionTitle('Cuenta'),
            const SizedBox(height: 10),
            _NeoTile(
              icon: Icons.person_rounded,
              color: Neo.rose,
              title: 'Editar perfil',
              subtitle: me?.email ?? '—',
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
            ),
            const SizedBox(height: 24),

            const _SectionTitle('Sincronización'),
            const SizedBox(height: 10),
            NeoBox(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
              shadowOffset: Neo.shadowBtn,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Sincronizar solo con Wi-Fi',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  'Las subidas en segundo plano esperan a una red Wi-Fi para ahorrar datos móviles.',
                  style: txt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                value: _wifiOnly,
                onChanged: (v) async {
                  await SyncPrefs.setWifiOnly(v);
                  if (mounted) setState(() => _wifiOnly = v);
                },
              ),
            ),
            const SizedBox(height: 24),

            const _SectionTitle('Servidor'),
            const SizedBox(height: 10),
            _NeoTile(
              icon: Icons.dns_rounded,
              color: Neo.sky,
              title: 'Estado del servidor',
              subtitle: 'Conexión, recuerdos guardados y espacio libre',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ServerStatusScreen()),
              ),
            ),
            const SizedBox(height: 32),

            NeoButton(
              label: 'Cerrar sesión',
              icon: Icons.logout_rounded,
              color: Neo.coral,
              expand: true,
              onPressed: _logout,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: Neo.ink,
        fontWeight: FontWeight.w900,
        fontSize: 12,
        letterSpacing: 2,
      ),
    );
  }
}

/// Tappable row: icon badge + title/subtitle + chevron, in a neo box.
class _NeoTile extends StatelessWidget {
  const _NeoTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    return NeoBox(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      shadowOffset: Neo.shadowBtn,
      onTap: onTap,
      child: Row(
        children: [
          NeoIconBadge(icon: icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: txt.titleSmall),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: txt.bodySmall?.copyWith(
                      color: Neo.ink.withValues(alpha: .6),
                    ),
                  ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Neo.ink),
        ],
      ),
    );
  }
}
