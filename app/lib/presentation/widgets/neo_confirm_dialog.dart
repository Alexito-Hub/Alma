import 'package:flutter/material.dart';

import '../../core/theme/neo.dart';

/// Neo-styled yes/no confirmation. Pops `true` when the user taps the confirm
/// button, `false`/null otherwise.
class NeoConfirmDialog extends StatelessWidget {
  const NeoConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
  });

  final String title;
  final String message;
  final String confirmLabel;

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
            Text(title, style: txt.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: txt.bodyMedium?.copyWith(
                color: Neo.ink.withValues(alpha: .7),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: NeoButton(
                    label: 'Cancelar',
                    color: Neo.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: NeoButton(
                    label: confirmLabel,
                    color: Neo.rose,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    onPressed: () => Navigator.pop(context, true),
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
