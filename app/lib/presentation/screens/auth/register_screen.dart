import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/neo.dart';
import '../../../core/utils/error_text.dart';
import '../../../data/repositories/auth_repository.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Las contraseñas no coinciden');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .register(_email.text.trim(), _password.text);
      ref.read(currentUserProvider.notifier).state = user;
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = _human(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _human(Object e) {
    final s = e.toString();
    if (s.contains('email_taken')) return 'Ese correo ya tiene cuenta';
    if (s.contains('weak_password')) {
      return 'La contraseña necesita 8+ caracteres';
    }
    if (s.contains('invalid_email')) return 'Correo inválido';
    // The server keeps an allowlist; this is Alma, not a signup page.
    if (s.contains('registration_closed')) {
      return 'Este servidor no acepta cuentas nuevas';
    }
    if (looksLikeNetworkError(s)) return 'Sin conexión con el servidor';
    return 'No se pudo crear la cuenta';
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Neo.paper,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: NeoIconButton(
                  icon: Icons.arrow_back_rounded,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(height: 20),
              Text('Crea tu cuenta', style: txt.headlineMedium),
              const SizedBox(height: 12),
              Text(
                'Te daremos un código corto que podrás compartirle a tu pareja para vincular sus cuentas.',
                style: txt.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
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
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  helperText: 'Mínimo 8 caracteres',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _confirm,
                obscureText: _obscure,
                decoration: const InputDecoration(
                  labelText: 'Confirmar contraseña',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                NeoErrorBanner(message: _error!),
              ],
              const SizedBox(height: 24),
              NeoButton(
                label: 'Crear cuenta',
                icon: Icons.favorite_border_rounded,
                expand: true,
                busy: _busy,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
