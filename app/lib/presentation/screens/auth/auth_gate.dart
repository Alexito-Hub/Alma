import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/neo.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/sync/hydrator.dart';
import 'couple_link_screen.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';

/// Decides between Login → CoupleLink → AppShell based on session + couple
/// state. On a fresh session we pull the couple's data down from the server
/// into Isar and subscribe to live updates so both phones converge fast.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  Future<void>? _bootstrap;

  @override
  void initState() {
    super.initState();
    _bootstrap = _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      final result = await ref.read(authRepositoryProvider).me();
      if (result == null) return;
      ref.read(currentUserProvider.notifier).state = result.me;
      ref.read(partnerUserProvider.notifier).state = result.partner;

      final couple = result.me.coupleId;
      if (couple != null && couple.isNotEmpty) {
        // Fire-and-forget: don't block UI on the hydration network calls.
        unawaited(Hydrator.instance.hydrateAll(coupleId: couple));
        unawaited(
          Hydrator.instance.subscribeToLiveUpdates(
            couple,
            onPartnerUpdated: (payload) async {
              // Cheapest path: re-fetch /me which already includes the partner.
              final refreshed = await ref.read(authRepositoryProvider).me();
              if (refreshed != null) {
                ref.read(partnerUserProvider.notifier).state =
                    refreshed.partner;
              }
            },
          ),
        );
      }
    } catch (_) {
      // No session — login screen will appear.
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _bootstrap,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _NeoSplash();
        }
        final user = ref.watch(currentUserProvider);
        if (user == null) return const LoginScreen();

        // Onboarding step: no display_name → ask for identity first.
        final needsIdentity = (user.displayName ?? '').trim().isEmpty;
        if (needsIdentity) {
          return OnboardingScreen(
            onDone: () {
              // Trigger a rebuild — currentUserProvider state already updated.
              setState(() {});
            },
          );
        }

        if (user.coupleId == null) return const CoupleLinkScreen();
        return widget.child;
      },
    );
  }
}

/// Branded neo-brutalist loading screen shown while the session restores.
class _NeoSplash extends StatelessWidget {
  const _NeoSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Neo.paper,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NeoAvatar(
              size: 96,
              color: Neo.pink,
              shadowOffset: Neo.shadowCard,
              child: Icon(Icons.favorite, color: Neo.ink, size: 44),
            ),
            SizedBox(height: 24),
            Text(
              'ALMA',
              style: TextStyle(
                color: Neo.ink,
                fontWeight: FontWeight.w900,
                fontSize: 34,
                letterSpacing: 6,
              ),
            ),
            SizedBox(height: 20),
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 3, color: Neo.ink),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small helper — Dart's `unawaited` isn't in older SDKs.
void unawaited(Future<void> f) {
  // Intentionally ignored.
}
