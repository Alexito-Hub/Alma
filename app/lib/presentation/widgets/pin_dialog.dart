import 'package:flutter/material.dart';

import '../../core/theme/neo.dart';

/// Asks for (or creates) the couple's shared PIN. Pops the entered PIN.
///
/// Lives here rather than in a screen because the same gate now guards the
/// private diary.
class PinDialog extends StatefulWidget {
  const PinDialog({super.key, required this.create});

  /// True the first time, when the couple is choosing their PIN.
  final bool create;

  @override
  State<PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<PinDialog> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    final p = _pin.text.trim();
    if (p.length < 4) {
      setState(() => _error = 'El PIN necesita al menos 4 dígitos');
      return;
    }
    if (widget.create && p != _confirm.text.trim()) {
      setState(() => _error = 'Los PIN no coinciden');
      return;
    }
    Navigator.pop(context, p);
  }

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(28),
      child: NeoBox(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.create ? 'Crear PIN privado' : 'Diario privado',
              style: txt.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              widget.create
                  ? 'Este PIN lo compartirán los dos para ver lo privado.'
                  : 'Ingresa el PIN de pareja.',
              textAlign: TextAlign.center,
              style: txt.bodySmall,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _pin,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(labelText: 'PIN'),
              onSubmitted: (_) {
                if (!widget.create) _submit();
              },
            ),
            if (widget.create) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _confirm,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(labelText: 'Confirmar PIN'),
                onSubmitted: (_) => _submit(),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              NeoErrorBanner(message: _error!),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: NeoButton(
                    label: 'Cancelar',
                    color: Neo.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: NeoButton(
                    label: widget.create ? 'Crear' : 'Entrar',
                    color: Neo.rose,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    onPressed: _submit,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
