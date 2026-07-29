import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/sync/hydrator.dart';
import '../../data/sync/sync_worker.dart';
import '../../presentation/screens/dashboard/dashboard_screen.dart';
import '../../presentation/screens/diary/diary_screen.dart';
import '../../presentation/screens/feed/feed_screen.dart';
import '../../presentation/screens/quick_action/quick_action_sheet.dart';
import '../../presentation/screens/settings/settings_screen.dart';
import '../theme/neo.dart';

/// App shell with a neo-brutalist bottom navigation bar.
///
/// Destinations: Inicio (0) · Diario (1) · Feed (2) · Ajustes (3), with a
/// central "Crear" button that opens the capture sheet. Tabs are kept alive in
/// an [IndexedStack] so each keeps its scroll/state. The Android back button
/// returns to Inicio before it's allowed to exit the app.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  int _index = 0;

  static const _pages = [
    DashboardScreen(),
    DiaryScreen(),
    FeedScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the app is a good moment to push what we made offline and
    // pull whatever the partner did meanwhile.
    if (state == AppLifecycleState.resumed) _sync();
  }

  /// Push local pending content and pull the partner's latest.
  void _sync() {
    runForegroundSync();
    final couple = ref.read(currentUserProvider)?.coupleId;
    if (couple != null && couple.isNotEmpty) {
      Hydrator.instance.hydrateAll(coupleId: couple);
    }
  }

  void _select(int i) {
    if (i != _index) setState(() => _index = i);
  }

  void _openCreate() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const QuickActionSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Only let the system pop (exit the app) from Inicio; from any other
      // tab, "back" returns to Inicio first.
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(0);
      },
      child: Scaffold(
        backgroundColor: Neo.paper,
        body: IndexedStack(index: _index, children: _pages),
        bottomNavigationBar: _NeoBottomBar(
          index: _index,
          onSelect: _select,
          onCreate: _openCreate,
        ),
      ),
    );
  }
}

/// The bottom bar: a bordered block with four destinations and a raised,
/// pink "Crear" button in the middle.
class _NeoBottomBar extends StatelessWidget {
  const _NeoBottomBar({
    required this.index,
    required this.onSelect,
    required this.onCreate,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Neo.paper,
        border: Border(
          top: BorderSide(color: Neo.ink, width: Neo.stroke),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              _NavItem(
                icon: Icons.favorite_rounded,
                label: 'Inicio',
                color: Neo.pink,
                active: index == 0,
                onTap: () => onSelect(0),
              ),
              _NavItem(
                icon: Icons.menu_book_rounded,
                label: 'Diario',
                color: Neo.mint,
                active: index == 1,
                onTap: () => onSelect(1),
              ),
              _CreateButton(onTap: onCreate),
              _NavItem(
                icon: Icons.photo_library_rounded,
                label: 'Feed',
                color: Neo.sky,
                active: index == 2,
                onTap: () => onSelect(2),
              ),
              _NavItem(
                icon: Icons.settings_rounded,
                label: 'Ajustes',
                color: Neo.lilac,
                active: index == 3,
                onTap: () => onSelect(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: active ? color : Colors.transparent,
                border: Border.all(
                  color: active ? Neo.ink : Colors.transparent,
                  width: Neo.strokeThin,
                ),
                borderRadius: Neo.cornerSm,
              ),
              child: Icon(icon, size: 22, color: Neo.ink),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: Neo.ink,
                fontSize: 10,
                fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                letterSpacing: .3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateButton extends StatelessWidget {
  const _CreateButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          NeoIconButton(
            icon: Icons.add_rounded,
            onPressed: onTap,
            tooltip: 'Crear',
            color: Neo.pink,
            size: 50,
            iconSize: 30,
          ),
          const SizedBox(height: 3),
          const Text(
            'Crear',
            style: TextStyle(
              color: Neo.ink,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: .3,
            ),
          ),
        ],
      ),
    );
  }
}
