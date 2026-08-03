part of 'diary_screen.dart';

// The PIN-gated diary.

/// The PIN-gated diary: entries marked private, which never appear in the
/// calendar, the list or the gallery.
class PrivateDiaryScreen extends ConsumerWidget {
  const PrivateDiaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes =
        ref.watch(privateNotesProvider).valueOrNull ?? const <NoteLocal>[];
    final me = ref.watch(currentUserProvider);
    final partner = ref.watch(partnerUserProvider);
    final txt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Neo.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  NeoIconButton(
                    icon: Icons.arrow_back_rounded,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 12),
                  const NeoIconBadge(icon: Icons.lock_rounded, color: Neo.rose),
                  const SizedBox(width: 10),
                  Text('Diario privado', style: txt.titleLarge),
                ],
              ),
            ),
            Expanded(
              child: notes.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          'Nada privado aún. Al escribir una entrada, márcala '
                          'como "Privada" y solo aparecerá aquí.',
                          textAlign: TextAlign.center,
                          style: txt.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(22, 6, 22, 24),
                      itemCount: notes.length,
                      itemBuilder: (_, i) {
                        final n = notes[i];
                        final mine = n.authorId == me?.id;
                        final author = mine
                            ? (me?.prettyName ?? 'tú')
                            : (partner?.prettyName ?? 'pareja');
                        return Padding(
                          key: ValueKey('private-note-${n.isarId}'),
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _MomentoCard(
                            note: n,
                            mine: mine,
                            author: author,
                            onReact: () {},
                            onOpenLink: () => _copyLink(context, n.link),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
