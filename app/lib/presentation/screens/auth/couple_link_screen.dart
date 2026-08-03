import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/neo.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/couple_repository.dart';
import '../../../domain/entities/couple_request.dart';

/// Two-pane couple invitation flow:
///   • "Tu código"        : show + copy, plus inbox of pending requests
///   • "Enviar invitación": form with partner code, started_at, message
///
/// While mounted we poll the inbox + /me every 4s so:
///   1. New incoming requests appear without manual refresh.
///   2. When the partner accepts our request, /me returns a coupleId and
///      AuthGate transitions us into the AppShell automatically.
class CoupleLinkScreen extends ConsumerStatefulWidget {
  const CoupleLinkScreen({super.key});

  @override
  ConsumerState<CoupleLinkScreen> createState() => _CoupleLinkScreenState();
}

class _CoupleLinkScreenState extends ConsumerState<CoupleLinkScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Timer? _poll;

  String _myCode = '';
  List<CoupleRequest> _received = const [];
  bool _loadingInbox = true;
  String? _inboxError;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    try {
      final repo = ref.read(coupleRepositoryProvider);
      final inbox = await repo.inbox();

      // Did our partner accept while we were waiting? Check /me.
      final result = await ref.read(authRepositoryProvider).me();
      if (result != null) {
        ref.read(currentUserProvider.notifier).state = result.me;
        ref.read(partnerUserProvider.notifier).state = result.partner;
        if (result.me.coupleId != null && result.me.coupleId!.isNotEmpty) {
          return; // AuthGate will rebuild and route us to AppShell.
        }
      }

      if (!mounted) return;
      setState(() {
        _myCode = inbox.myCode;
        _received = inbox.requests
            .where((r) => r.status == CoupleRequestStatus.pending)
            .toList();
        _loadingInbox = false;
        _inboxError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingInbox = false;
        _inboxError = 'No se pudo conectar al servidor';
      });
    }
  }

  Future<void> _accept(CoupleRequest req) async {
    try {
      await ref.read(coupleRepositoryProvider).accept(req.id);
      final result = await ref.read(authRepositoryProvider).me();
      if (result != null) {
        ref.read(partnerUserProvider.notifier).state = result.partner;

        // Show the bond celebration before letting AuthGate route us to
        // the Dashboard.
        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            barrierColor: Neo.ink.withValues(alpha: .8),
            builder: (_) => _BondCelebration(
              partnerName: result.partner?.prettyName ?? 'tu pareja',
            ),
          );
        }
        ref.read(currentUserProvider.notifier).state = result.me;
      }
    } catch (_) {
      _snack('No se pudo aceptar la invitación');
    }
  }

  Future<void> _reject(CoupleRequest req) async {
    try {
      await ref.read(coupleRepositoryProvider).reject(req.id);
      await _refresh();
    } catch (_) {
      _snack('No se pudo rechazar');
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              myCode: _myCode,
              onLogout: () async {
                await ref.read(authRepositoryProvider).logout();
                ref.read(currentUserProvider.notifier).state = null;
              },
            ),
            const SizedBox(height: 12),
            TabBar(
              controller: _tabs,
              labelColor: Neo.ink,
              unselectedLabelColor: Neo.ink.withValues(alpha: .45),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Recibidas'),
                      if (_received.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        _Badge(count: _received.length),
                      ],
                    ],
                  ),
                ),
                const Tab(text: 'Enviar'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _InboxPane(
                    loading: _loadingInbox,
                    error: _inboxError,
                    requests: _received,
                    onAccept: _accept,
                    onReject: _reject,
                    onRefresh: _refresh,
                  ),
                  _SendPane(
                    onSent: () {
                      _refresh();
                      _tabs.animateTo(0);
                      _snack('Invitación enviada');
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.myCode, required this.onLogout});
  final String myCode;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const NeoAvatar(
                size: 44,
                color: Neo.pink,
                child: Icon(Icons.favorite, color: Neo.ink, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'ALMA',
                  style: txt.headlineSmall?.copyWith(letterSpacing: 4),
                ),
              ),
              NeoIconButton(
                tooltip: 'Cerrar sesión',
                onPressed: onLogout,
                icon: Icons.logout_rounded,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Conecta tu cuenta con la de tu pareja',
            style: txt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          _CodeCard(code: myCode),
        ],
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final chars = (code.isEmpty ? '········' : code.toUpperCase())
        .padRight(8)
        .split('');

    return NeoBox(
      width: double.infinity,
      color: Neo.lilac,
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const NeoIconBadge(icon: Icons.vpn_key_rounded),
              const SizedBox(width: 10),
              Text(
                'TU LLAVE DE CONEXIÓN',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(letterSpacing: 1.5),
              ),
              const Spacer(),
              NeoIconButton(
                tooltip: 'Copiar',
                size: 40,
                iconSize: 18,
                onPressed: code.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(text: code.toUpperCase()),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Código copiado')),
                          );
                        }
                      },
                icon: Icons.copy_rounded,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: chars
                .map((c) => _KeyChip(char: c, empty: code.isEmpty))
                .toList(),
          ),
          const SizedBox(height: 14),
          Text(
            'Comparte esta llave con tu pareja. Cuando te envíe la invitación, aparecerá en "Recibidas".',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Neo.ink.withValues(alpha: .75),
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyChip extends StatelessWidget {
  const _KeyChip({required this.char, required this.empty});
  final String char;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: empty ? Neo.white : Neo.yellow,
        borderRadius: Neo.cornerSm,
        border: Neo.borderThin,
      ),
      child: Text(
        char,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontFamily: 'monospace',
          fontWeight: FontWeight.w900,
          color: empty ? Neo.ink.withValues(alpha: .3) : Neo.ink,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Neo.accent,
        borderRadius: Neo.cornerSm,
        border: Neo.borderThin,
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Neo.white,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _InboxPane extends StatelessWidget {
  const _InboxPane({
    required this.loading,
    required this.error,
    required this.requests,
    required this.onAccept,
    required this.onReject,
    required this.onRefresh,
  });

  final bool loading;
  final String? error;
  final List<CoupleRequest> requests;
  final void Function(CoupleRequest) onAccept;
  final void Function(CoupleRequest) onReject;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: NeoSpinner(size: 34));
    }
    if (error != null) {
      return _EmptyMessage(
        icon: Icons.wifi_off_rounded,
        title: 'Sin conexión',
        subtitle: error!,
        action: NeoButton(
          label: 'Reintentar',
          icon: Icons.refresh_rounded,
          color: Neo.coral,
          onPressed: onRefresh,
        ),
      );
    }
    if (requests.isEmpty) {
      return _EmptyMessage(
        icon: Icons.mail_outline_rounded,
        title: 'Aún no llegó nada',
        subtitle:
            'Compártele tu código a tu pareja para que te envíe una invitación. Esta pantalla se actualiza sola.',
        action: NeoButton(
          label: 'Refrescar',
          icon: Icons.refresh_rounded,
          color: Neo.sky,
          onPressed: onRefresh,
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        itemCount: requests.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _RequestCard(
          request: requests[i],
          onAccept: () => onAccept(requests[i]),
          onReject: () => onReject(requests[i]),
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.onAccept,
    required this.onReject,
  });

  final CoupleRequest request;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    final started = request.proposedStartedAt;
    final fmt = DateFormat('d MMM y', 'es');

    return NeoBox(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              NeoAvatar(
                size: 48,
                color: Neo.sky,
                child: Text(
                  _initials(request.fromEmail),
                  style: const TextStyle(
                    color: Neo.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.fromEmail,
                      style: txt.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (started != null)
                      Text(
                        'Quiere empezar el ${fmt.format(started.toLocal())}',
                        style: txt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (request.message != null && request.message!.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Neo.rose,
                border: Neo.borderThin,
                borderRadius: Neo.cornerSm,
              ),
              child: Text(
                '"${request.message}"',
                style: txt.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: NeoButton(
                  label: 'Rechazar',
                  color: Neo.white,
                  expand: true,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  onPressed: onReject,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: NeoButton(
                  label: 'Aceptar',
                  color: Neo.mint,
                  expand: true,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  onPressed: onAccept,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _initials(String email) {
    final name = email.split('@').first;
    if (name.isEmpty) return '·';
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SendPane extends ConsumerStatefulWidget {
  const _SendPane({required this.onSent});
  final VoidCallback onSent;

  @override
  ConsumerState<_SendPane> createState() => _SendPaneState();
}

class _SendPaneState extends ConsumerState<_SendPane> {
  final _formKey = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  DateTime _startedAt = DateTime.now();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startedAt,
      firstDate: DateTime(1980),
      lastDate: DateTime.now(),
      helpText: '¿Cuándo empezaron?',
    );
    if (picked != null) setState(() => _startedAt = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(coupleRepositoryProvider)
          .sendRequest(
            partnerCode: _codeCtrl.text,
            startedAt: _startedAt,
            message: _messageCtrl.text,
          );
      _codeCtrl.clear();
      _messageCtrl.clear();
      widget.onSent();
    } catch (e) {
      setState(() => _error = _humanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _humanError(Object e) {
    final s = e.toString();
    if (s.contains('recipient_not_found')) {
      return 'No encontré a esa persona. Revisa el código.';
    }
    if (s.contains('already_linked')) {
      return 'Ya estás vinculado con alguien.';
    }
    if (s.contains('request_already_sent')) {
      return 'Ya le enviaste una invitación a esa persona.';
    }
    if (s.contains('invalid_code')) {
      return 'El código debe tener al menos 8 caracteres.';
    }
    return 'No se pudo enviar. Intenta de nuevo.';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    final fmt = DateFormat('EEEE d MMMM y', 'es');

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Invita a tu pareja',
              style: txt.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Escribe su código (los primeros 8 caracteres de su ID, te lo puede pasar por mensaje) y elige la fecha desde la que cuentan juntos.',
              style: txt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _codeCtrl,
              textCapitalization: TextCapitalization.characters,
              maxLength: 12,
              decoration: const InputDecoration(
                labelText: 'Código de tu pareja',
                hintText: 'ABCD1234',
                prefixIcon: Icon(Icons.tag),
              ),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.length < 8) return 'Mínimo 8 caracteres';
                return null;
              },
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Empezamos a estar juntos',
                  prefixIcon: Icon(Icons.calendar_today),
                ),
                child: Text(fmt.format(_startedAt)),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _messageCtrl,
              maxLines: 3,
              maxLength: 240,
              decoration: const InputDecoration(
                labelText: 'Mensaje (opcional)',
                hintText: '¡Vamos a guardar nuestros recuerdos aquí!',
                alignLabelWithHint: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              NeoErrorBanner(message: _error!),
            ],
            const SizedBox(height: 20),
            NeoButton(
              label: _busy ? 'Enviando…' : 'Enviar invitación',
              icon: Icons.send_rounded,
              expand: true,
              busy: _busy,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          NeoAvatar(
            size: 84,
            color: Neo.yellow,
            child: Icon(icon, size: 40, color: Neo.ink),
          ),
          const SizedBox(height: 20),
          Text(title, style: txt.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: txt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Full-screen "vínculo exitoso" celebration: two hearts converge into one,
/// halo expands. Auto-dismisses after a beat so AuthGate can route us to
/// the Dashboard.
class _BondCelebration extends StatefulWidget {
  const _BondCelebration({required this.partnerName});
  final String partnerName;

  @override
  State<_BondCelebration> createState() => _BondCelebrationState();
}

class _BondCelebrationState extends State<_BondCelebration>
    with TickerProviderStateMixin {
  late final AnimationController _converge = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final AnimationController _halo = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await _converge.forward();
    _halo.forward();
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _converge.dispose();
    _halo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(28),
      child: NeoBox(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
        child: AnimatedBuilder(
          animation: Listenable.merge([_converge, _halo]),
          builder: (_, _) {
            final t = Curves.easeOutCubic.transform(_converge.value);
            final haloT = Curves.easeOutQuart.transform(_halo.value);

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 150,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Expanding solid halo ring with a hard stroke.
                      Opacity(
                        opacity: (1 - haloT).clamp(0.0, 1.0),
                        child: Container(
                          width: 60 + haloT * 200,
                          height: 60 + haloT * 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Neo.yellow,
                            border: Neo.borderThin,
                          ),
                        ),
                      ),
                      // Left heart converging from left
                      Transform.translate(
                        offset: Offset(-52 + t * 52, 0),
                        child: Opacity(
                          opacity: 1 - haloT * .8,
                          child: const Icon(
                            Icons.favorite,
                            color: Neo.pink,
                            size: 40,
                          ),
                        ),
                      ),
                      // Right heart converging from right
                      Transform.translate(
                        offset: Offset(52 - t * 52, 0),
                        child: Opacity(
                          opacity: 1 - haloT * .8,
                          child: const Icon(
                            Icons.favorite,
                            color: Neo.coral,
                            size: 40,
                          ),
                        ),
                      ),
                      // Merged heart in a hard-shadowed avatar
                      Transform.scale(
                        scale: (.6 + haloT * .4).clamp(0.0, 1.0),
                        child: Opacity(
                          opacity: haloT,
                          child: const NeoAvatar(
                            size: 84,
                            color: Neo.pink,
                            shadowOffset: Neo.shadowCard,
                            child: Icon(
                              Icons.favorite,
                              color: Neo.ink,
                              size: 42,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '¡Vínculo exitoso!',
                  style: txt.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Tú y ${widget.partnerName} ahora comparten Alma.',
                  textAlign: TextAlign.center,
                  style: txt.bodyMedium?.copyWith(
                    color: Neo.ink.withValues(alpha: .7),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
