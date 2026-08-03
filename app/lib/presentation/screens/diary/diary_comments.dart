part of 'diary_screen.dart';

// The conversation hanging off a diary entry.

/// The conversation hanging off a diary entry. Offline-first like the rest:
/// what you write appears immediately and is pushed when there's signal.
class _CommentsSheet extends ConsumerStatefulWidget {
  const _CommentsSheet({required this.noteId});
  final String noteId;

  @override
  ConsumerState<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<_CommentsSheet> {
  final _input = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(commentRepositoryProvider);
    try {
      final res = await ApiClient.instance.dio.get(
        Endpoints.noteComments(widget.noteId),
      );
      for (final c in (res.data['comments'] as List? ?? const [])) {
        await repo.upsertFromRemote(Map<String, dynamic>.from(c as Map));
      }
    } catch (_) {
      /* offline - whatever is cached still shows */
    }
    await repo.flushPending(postId: widget.noteId);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final me = ref.read(currentUserProvider);
    if (text.isEmpty || _sending || me == null) return;
    setState(() => _sending = true);
    try {
      final repo = ref.read(commentRepositoryProvider);
      await repo.create(
        postId: widget.noteId,
        targetType: 'note',
        authorId: me.id,
        text: text,
      );
      _input.clear();
      await repo.flushPending(postId: widget.noteId);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final comments =
        ref.watch(commentsForNoteProvider(widget.noteId)).valueOrNull ??
        const <CommentLocal>[];
    final me = ref.watch(currentUserProvider);
    final partner = ref.watch(partnerUserProvider);
    final txt = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Neo.paper,
          border: Border(
            top: BorderSide(color: Neo.ink, width: Neo.stroke),
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const NeoIconBadge(
                    icon: Icons.mode_comment_rounded,
                    color: Neo.sky,
                    size: 30,
                    iconSize: 16,
                  ),
                  const SizedBox(width: 10),
                  Text('Comentarios', style: txt.titleMedium),
                ],
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * .42,
                ),
                child: comments.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 22),
                        child: Text(
                          'Sin comentarios todavia.',
                          style: txt.bodySmall,
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: comments.length,
                        itemBuilder: (_, i) {
                          final c = comments[i];
                          final mine = c.authorId == me?.id;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: NeoBox(
                              width: double.infinity,
                              color: mine ? Neo.rose : Neo.white,
                              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                              shadowOffset: Neo.shadowSm,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        mine
                                            ? (me?.prettyName ?? 'tu')
                                            : (partner?.prettyName ?? 'pareja'),
                                        style: txt.labelSmall,
                                      ),
                                      const Spacer(),
                                      if (c.syncStatus != 'synced')
                                        const Icon(
                                          Icons.schedule_rounded,
                                          size: 13,
                                          color: Neo.ink,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(c.text, style: txt.bodyMedium),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Escribe algo',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  NeoIconButton(
                    icon: Icons.send_rounded,
                    color: Neo.mint,
                    onPressed: _sending ? null : _send,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
