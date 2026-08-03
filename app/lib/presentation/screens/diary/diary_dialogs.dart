part of 'diary_screen.dart';

// Dialogs: editing an entry, and adding a special date.

/// Text-only edit of an own diary entry: body + mood. Media stays immutable.
class _EditEntryDialog extends StatefulWidget {
  const _EditEntryDialog({required this.note});
  final NoteLocal note;

  @override
  State<_EditEntryDialog> createState() => _EditEntryDialogState();
}

class _EditEntryDialogState extends State<_EditEntryDialog> {
  late final TextEditingController _body = TextEditingController(
    text: widget.note.body,
  );
  String? _mood;

  @override
  void initState() {
    super.initState();
    _mood = widget.note.mood;
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
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
              'Editar entrada',
              style: txt.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _body,
              autofocus: true,
              minLines: 2,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Lo que quieras recordar…',
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in _moods)
                  GestureDetector(
                    onTap: () => setState(() => _mood = _mood == m ? null : m),
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _mood == m ? Neo.yellow : Neo.white,
                        border: Neo.borderThin,
                        borderRadius: Neo.cornerSm,
                      ),
                      child: Text(m, style: const TextStyle(fontSize: 18)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
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
                    label: 'Guardar',
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    onPressed: () {
                      final t = _body.text.trim();
                      if (t.isEmpty) return;
                      Navigator.pop(context, (body: t, mood: _mood));
                    },
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

class _SpecialInput {
  const _SpecialInput(this.title, this.iconKey);
  final String title;
  final String iconKey;
}

class _SpecialDateDialog extends StatefulWidget {
  const _SpecialDateDialog({required this.day});
  final DateTime day;

  @override
  State<_SpecialDateDialog> createState() => _SpecialDateDialogState();
}

class _SpecialDateDialogState extends State<_SpecialDateDialog> {
  final _title = TextEditingController();
  String _iconKey = 'star';

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
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
              'Fecha especial',
              style: txt.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              _dayLabel(widget.day),
              textAlign: TextAlign.center,
              style: txt.labelSmall?.copyWith(
                color: Neo.ink.withValues(alpha: .6),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Aniversario, viaje, cumpleaños…',
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in _specialIcons.entries)
                  GestureDetector(
                    onTap: () => setState(() => _iconKey = e.key),
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _iconKey == e.key ? Neo.yellow : Neo.white,
                        border: Neo.borderThin,
                        borderRadius: Neo.cornerSm,
                      ),
                      child: Icon(e.value, size: 20, color: Neo.ink),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
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
                    label: 'Guardar',
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    onPressed: () {
                      final t = _title.text.trim();
                      if (t.isEmpty) return;
                      Navigator.pop(context, _SpecialInput(t, _iconKey));
                    },
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
