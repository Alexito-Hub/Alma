import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/neo.dart';
import '../../../core/utils/error_text.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/sync/hydrator.dart';
import 'auth_gate.dart' show unawaited;
import 'register_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .login(_email.text.trim(), _password.text);
      ref.read(currentUserProvider.notifier).state = user;

      // Pull fresh /me to populate partner + trigger hydration.
      final result = await ref.read(authRepositoryProvider).me();
      if (result != null) {
        ref.read(currentUserProvider.notifier).state = result.me;
        ref.read(partnerUserProvider.notifier).state = result.partner;
        final couple = result.me.coupleId;
        if (couple != null && couple.isNotEmpty) {
          unawaited(Hydrator.instance.hydrateAll(coupleId: couple));
          unawaited(Hydrator.instance.subscribeToLiveUpdates(couple));
        }
      }
    } catch (e) {
      setState(() => _error = _human(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _human(Object e) {
    final s = e.toString();
    if (s.contains('invalid_credentials')) {
      return 'Correo o contraseña incorrectos';
    }
    if (looksLikeNetworkError(s)) return 'Sin conexión con el servidor';
    return 'No se pudo iniciar sesión';
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Neo.paper,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 64,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const Spacer(),
                      Image.asset(
                        'assets/images/logotype/alma.png',
                        height: 132,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'ALMA',
                        style: txt.displaySmall?.copyWith(letterSpacing: 8),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Neo.yellow,
                          border: Neo.borderThin,
                          borderRadius: Neo.cornerSm,
                        ),
                        child: Text(
                          'un espacio para los dos',
                          style: txt.labelMedium?.copyWith(letterSpacing: 1.5),
                        ),
                      ),
                      const SizedBox(height: 40),
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Correo',
                          prefixIcon: Icon(Icons.mail_outline),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _password,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        NeoErrorBanner(message: _error!),
                      ],
                      const SizedBox(height: 24),
                      NeoButton(
                        label: 'Entrar',
                        icon: Icons.login_rounded,
                        expand: true,
                        busy: _busy,
                        onPressed: _submit,
                      ),
                      const SizedBox(height: 14),
                      NeoButton(
                        label: 'Crear cuenta',
                        color: Neo.mint,
                        expand: true,
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const RegisterScreen(),
                          ),
                        ),
                      ),
                      const Spacer(flex: 2),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
