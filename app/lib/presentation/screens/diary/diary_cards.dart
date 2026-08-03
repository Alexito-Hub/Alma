part of 'diary_screen.dart';

// The cards a day is made of: an entry, a special date, an empty day.

class _MomentoCard extends StatelessWidget {
  const _MomentoCard({
    required this.note,
    required this.mine,
    required this.author,
    required this.onReact,
    required this.onOpenLink,
    this.onComment,
    this.onShare,
    this.onEdit,
    this.onDelete,
  });

  final NoteLocal note;
  final bool mine;
  final String author;
  final VoidCallback onReact;
  final VoidCallback onOpenLink;
  final VoidCallback? onComment;
  final VoidCallback? onShare;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    final time = TimeOfDay.fromDateTime(note.createdAt).format(context);
    final accent = mine ? Neo.pink : Neo.lilac;

    return NeoBox(
      width: double.infinity,
      padding: EdgeInsets.zero,
      shadowOffset: Neo.shadowBtn,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: accent,
              border: const Border(
                bottom: BorderSide(color: Neo.ink, width: Neo.strokeThin),
              ),
            ),
            child: Row(
              children: [
                if (note.mood != null) ...[
                  Text(note.mood!, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                ],
                Icon(
                  mine ? Icons.person_rounded : Icons.favorite_rounded,
                  size: 15,
                  color: Neo.ink,
                ),
                const SizedBox(width: 6),
                Text(author, style: txt.labelLarge?.copyWith(color: Neo.ink)),
                const Spacer(),
                if (onShare != null)
                  _HeaderAction(icon: Icons.ios_share_rounded, onTap: onShare!),
                if (onEdit != null)
                  _HeaderAction(icon: Icons.edit_outlined, onTap: onEdit!),
                if (onDelete != null)
                  _HeaderAction(
                    icon: Icons.delete_outline_rounded,
                    onTap: onDelete!,
                  ),
                Text(
                  time,
                  style: txt.labelSmall?.copyWith(
                    color: Neo.ink.withValues(alpha: .7),
                  ),
                ),
              ],
            ),
          ),
          if (entryMediaSources(note).isNotEmpty)
            DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Neo.ink, width: Neo.strokeThin),
                ),
              ),
              child: PostMediaCarousel(
                key: ValueKey('media-${note.isarId}'),
                sources: entryMediaSources(note),
              ),
            ),
          if (note.audioPath != null)
            _AudioTile(
              key: ValueKey('audio-${note.isarId}'),
              src: note.audioPath!,
            )
          else if (note.remoteAudioUrl != null)
            _AudioTile(
              key: ValueKey('audio-remote-${note.isarId}'),
              src: absoluteMediaUrl(note.remoteAudioUrl!),
              remote: true,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: SelectableText(
              note.body,
              style: txt.bodyLarge?.copyWith(
                color: Neo.ink,
                height: 1.5,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (note.placeLabel != null || note.latitude != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: _Chip(
                icon: Icons.place_rounded,
                color: Neo.mint,
                label:
                    note.placeLabel ??
                    '${note.latitude!.toStringAsFixed(3)}, ${note.longitude!.toStringAsFixed(3)}',
              ),
            ),
          if (note.link != null && note.link!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: GestureDetector(
                onTap: onOpenLink,
                child: _Chip(
                  icon: Icons.link_rounded,
                  color: Neo.sky,
                  label: note.link!,
                  trailing: Icons.copy_rounded,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Row(
              children: [
                if (note.reactionEmoji != null)
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Neo.rose,
                      border: Neo.borderThin,
                      borderRadius: Neo.cornerSm,
                    ),
                    child: Icon(
                      _iconFor(
                        note.reactionEmoji,
                        _reactionIcons,
                        Icons.favorite_rounded,
                      ),
                      size: 16,
                      color: Neo.ink,
                    ),
                  ),
                const Spacer(),
                if (onComment != null) ...[
                  NeoButton(
                    label: 'Comentar',
                    icon: Icons.mode_comment_outlined,
                    color: Neo.sky,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    shadowOffset: Neo.shadowSm,
                    textStyle: txt.labelSmall,
                    onPressed: onComment,
                  ),
                  const SizedBox(width: 8),
                ],
                if (!mine)
                  NeoButton(
                    label: note.reactionEmoji == null
                        ? 'Reaccionar'
                        : 'Cambiar',
                    icon: Icons.add_reaction_outlined,
                    color: Neo.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    shadowOffset: Neo.shadowSm,
                    textStyle: txt.labelSmall,
                    onPressed: onReact,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Flat bordered chip: icon + label (+ optional trailing icon).
class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.color,
    required this.label,
    this.trailing,
  });
  final IconData icon;
  final Color color;
  final String label;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        border: Neo.borderThin,
        borderRadius: Neo.cornerSm,
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Neo.ink),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: txt.labelSmall?.copyWith(color: Neo.ink),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 6),
            Icon(trailing, size: 14, color: Neo.ink),
          ],
        ],
      ),
    );
  }
}

/// Voice note playback: a neo bar with play/pause and a progress line.
class _AudioTile extends StatefulWidget {
  const _AudioTile({super.key, required this.src, this.remote = false});
  final String src;
  final bool remote;

  @override
  State<_AudioTile> createState() => _AudioTileState();
}

class _AudioTileState extends State<_AudioTile> {
  final _player = AudioPlayer();
  bool _loaded = false;
  bool _busy = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!_loaded) {
        // Loading on first tap keeps a screen full of entries cheap.
        if (widget.remote) {
          await _player.setUrl(widget.src, headers: mediaHeaders());
        } else {
          await _player.setFilePath(widget.src);
        }
        _loaded = true;
      }
      if (_player.playing) {
        await _player.pause();
      } else {
        if (_player.processingState == ProcessingState.completed) {
          await _player.seek(Duration.zero);
        }
        unawaited(_player.play());
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo reproducir la nota de voz')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(
        color: Neo.coral,
        border: Border(
          bottom: BorderSide(color: Neo.ink, width: Neo.strokeThin),
        ),
      ),
      child: StreamBuilder<Duration>(
        stream: _player.positionStream,
        builder: (context, snap) {
          final total = _player.duration ?? Duration.zero;
          final pos = snap.data ?? Duration.zero;
          final progress = (total.inMilliseconds == 0)
              ? 0.0
              : (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

          return Row(
            children: [
              GestureDetector(
                onTap: _toggle,
                child: Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Neo.white,
                    border: Neo.borderThin,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _player.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 22,
                    color: Neo.ink,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nota de voz', style: txt.labelSmall),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: Neo.white,
                        valueColor: const AlwaysStoppedAnimation(Neo.ink),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _ComposerState._clock(total == Duration.zero ? pos : total),
                style: txt.labelSmall,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Capsule extends StatelessWidget {
  const _Capsule({required this.memories});
  final List<NoteLocal> memories;

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    final now = DateTime.now();
    return NeoBox(
      width: double.infinity,
      color: Neo.lilac,
      shadowOffset: Neo.shadowBtn,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const NeoSectionLabel(
            icon: Icons.history_rounded,
            label: 'Un día como hoy',
            color: Neo.white,
          ),
          const SizedBox(height: 10),
          for (final m in memories)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Neo.white,
                      border: Neo.borderThin,
                      borderRadius: Neo.cornerSm,
                    ),
                    child: Text(
                      _ago(now.year - m.createdAt.year),
                      style: txt.labelSmall?.copyWith(color: Neo.ink),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      m.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: txt.bodySmall?.copyWith(
                        color: Neo.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _ago(int years) => years == 1 ? 'hace 1 año' : 'hace $years años';
}

class _SpecialDateCard extends StatelessWidget {
  const _SpecialDateCard({required this.special, required this.onDelete});
  final SpecialDateLocal special;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    return NeoBox(
      width: double.infinity,
      color: Neo.yellow,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      shadowOffset: Neo.shadowBtn,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Neo.white,
              border: Neo.borderThin,
              borderRadius: Neo.cornerSm,
            ),
            child: Icon(
              _iconFor(special.emoji, _specialIcons, Icons.star_rounded),
              size: 22,
              color: Neo.ink,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(special.title, style: txt.titleSmall),
                if (special.recurring)
                  Text(
                    'Cada año',
                    style: txt.labelSmall?.copyWith(
                      color: Neo.ink.withValues(alpha: .6),
                    ),
                  ),
              ],
            ),
          ),
          NeoIconButton(
            icon: Icons.delete_outline_rounded,
            size: 38,
            iconSize: 18,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// Compact tap target used in the entry-card header (edit / delete own entry).
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        margin: const EdgeInsets.only(right: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Neo.white,
          border: Neo.borderThin,
          borderRadius: Neo.cornerSm,
        ),
        child: Icon(icon, size: 14, color: Neo.ink),
      ),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          const NeoAvatar(
            size: 72,
            color: Neo.mint,
            child: Icon(Icons.auto_stories_rounded, size: 34, color: Neo.ink),
          ),
          const SizedBox(height: 16),
          Text(
            'Nada escrito este día',
            style: txt.titleSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Toca "Escribir" para dejar una entrada en esta fecha.',
            style: txt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
