import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/theme/neo.dart';
import '../../../data/device/media_tools.dart';
import '../../../data/device/voice_recorder.dart';
import '../../../data/local/diary_prefs.dart';
import '../../../data/local/isar/comment_local.dart';
import '../../../data/local/isar/note_local.dart';
import '../../../data/local/isar/special_date_local.dart';
import '../../../data/remote/api_client.dart';
import '../../../data/remote/endpoints.dart';
import '../../../data/remote/media_headers.dart';
import '../../../data/remote/pin_gate.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/comment_repository.dart';
import '../../../data/repositories/note_repository.dart';
import '../../../data/repositories/special_date_repository.dart';
import '../../../data/sync/sync_worker.dart';
import '../../../domain/entities/user.dart';
import '../../widgets/neo_confirm_dialog.dart';
import '../../widgets/pin_dialog.dart';
import '../../widgets/post_media.dart';
import 'share_card_screen.dart';

part 'diary_calendar.dart';
part 'diary_cards.dart';
part 'diary_comments.dart';
part 'diary_composer.dart';
part 'diary_dialogs.dart';
part 'private_diary_screen.dart';

// Mood stays as emoji (the one place emoji reads best). Everything else uses
// neo icons keyed by a stable string.
const _moods = ['😊', '🥰', '😌', '🤩', '😢', '😡', '😴', '🤔'];

const _reactionIcons = <String, IconData>{
  'heart': Icons.favorite_rounded,
  'star': Icons.star_rounded,
  'laugh': Icons.sentiment_very_satisfied_rounded,
  'wow': Icons.mood_rounded,
  'sad': Icons.sentiment_dissatisfied_rounded,
  'fire': Icons.local_fire_department_rounded,
  'hug': Icons.volunteer_activism_rounded,
  'thumb': Icons.thumb_up_rounded,
};

const _specialIcons = <String, IconData>{
  'star': Icons.star_rounded,
  'cake': Icons.cake_rounded,
  'heart': Icons.favorite_rounded,
  'trip': Icons.flight_takeoff_rounded,
  'party': Icons.celebration_rounded,
  'ring': Icons.diamond_rounded,
  'home': Icons.home_rounded,
  'gift': Icons.card_giftcard_rounded,
};

IconData _iconFor(String? key, Map<String, IconData> map, IconData fallback) =>
    map[key] ?? fallback;

/// One entry's rich payload, assembled by the composer.
class EntryDraft {
  const EntryDraft({
    required this.body,
    this.mood,
    this.link,
    this.imagePaths = const [],
    this.videoPaths = const [],
    this.audioPath,
    this.geo,
    this.private = false,
  });
  final String body;
  final String? mood;
  final String? link;
  final List<String> imagePaths;
  final List<String> videoPaths;
  final String? audioPath;
  final GeoTag? geo;
  final bool private;
}

/// Everything an entry shows in its carousel: photos first, then clips.
/// Local files win while the entry is still queued; otherwise the server
/// copies. The legacy single-video fields are folded in for old entries.
List<String> entryMediaSources(NoteLocal n) {
  final local = <String>[
    ...n.imagePaths,
    ...n.videoPaths,
    if (n.videoPath != null) n.videoPath!,
  ];
  if (local.isNotEmpty) return local.toSet().toList();

  final remote = <String>{
    ...n.remoteImageUrls.map(absoluteMediaUrl),
    ...n.remoteVideoUrls.map(absoluteMediaUrl),
    if (n.remoteVideoUrl != null) absoluteMediaUrl(n.remoteVideoUrl!),
  };
  return remote.toList();
}

/// The Diary as a calendar of rich "Momentos": mood, photos, voice notes, short
/// videos, a location and a private reaction from your partner. Frontend-local.
class DiaryScreen extends ConsumerStatefulWidget {
  const DiaryScreen({super.key});

  @override
  ConsumerState<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends ConsumerState<DiaryScreen> {
  bool _sending = false;
  bool _composerOpen = false;

  /// Calendar starts collapsed; the preference is remembered across sessions.
  bool _calendarOpen = false;

  /// How the diary is being looked at: 0 calendar, 1 continuous list,
  /// 2 gallery grid. The Feed used to be the only place with a grid; those
  /// ways of browsing belong here, with the memories themselves.
  int _view = 0;
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  @override
  void initState() {
    super.initState();
    DiaryPrefs.calendarOpen().then((open) {
      if (mounted && open) setState(() => _calendarOpen = true);
    });
  }

  void _toggleCalendar() {
    setState(() => _calendarOpen = !_calendarOpen);
    unawaited(DiaryPrefs.setCalendarOpen(_calendarOpen));
  }

  DateTime _key(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  Future<void> _submit(EntryDraft d) async {
    if (d.body.trim().isEmpty || _sending) return;
    final me = ref.read(currentUserProvider);
    if (me == null) return;
    setState(() => _sending = true);
    try {
      final now = DateTime.now();
      final at = DateTime(
        _selectedDay.year,
        _selectedDay.month,
        _selectedDay.day,
        now.hour,
        now.minute,
        now.second,
      );
      await ref
          .read(noteRepositoryProvider)
          .create(
            body: d.body.trim(),
            authorId: me.id,
            createdAt: at,
            mood: d.mood,
            link: d.link,
            imagePaths: d.imagePaths,
            videoPaths: d.videoPaths,
            audioPath: d.audioPath,
            latitude: d.geo?.latitude,
            longitude: d.geo?.longitude,
            placeLabel: d.geo?.label,
            private: d.private,
          );
      if (mounted) setState(() => _composerOpen = false);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _react(NoteLocal note) async {
    final me = ref.read(currentUserProvider);
    if (me == null) return;
    final key = await _pickReaction(context, note.reactionEmoji);
    if (key == null) return;
    await ref
        .read(noteRepositoryProvider)
        .setReaction(
          isarId: note.isarId,
          authorId: me.id,
          emoji: key.isEmpty ? null : key,
        );
    // A reaction is for the other person — push it now, not in 15 minutes.
    unawaited(runForegroundSync());
  }

  Future<void> _addSpecialDate() async {
    final me = ref.read(currentUserProvider);
    if (me == null) return;
    final result = await showDialog<_SpecialInput>(
      context: context,
      builder: (_) => _SpecialDateDialog(day: _selectedDay),
    );
    if (result == null) return;
    await ref
        .read(specialDateRepositoryProvider)
        .create(
          date: _selectedDay,
          title: result.title,
          emoji: result.iconKey,
          createdBy: me.id,
        );
    // Push it to the server right away so the partner's calendar updates.
    unawaited(runForegroundSync());
  }

  Future<void> _confirmDeleteSpecial(SpecialDateLocal s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => NeoConfirmDialog(
        title: 'Eliminar fecha',
        message: '¿Quieres eliminar "${s.title}"? No se puede deshacer.',
        confirmLabel: 'Eliminar',
      ),
    );
    if (ok == true) {
      await ref.read(specialDateRepositoryProvider).delete(s.isarId);
      // Propagate the deletion to the server (tombstone → remote DELETE).
      unawaited(runForegroundSync());
    }
  }

  Future<void> _confirmDeleteEntry(NoteLocal n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const NeoConfirmDialog(
        title: 'Eliminar entrada',
        message:
            '¿Quieres eliminar esta entrada del diario? También desaparecerá '
            'para tu pareja y no se puede deshacer.',
        confirmLabel: 'Eliminar',
      ),
    );
    if (ok == true) {
      await ref.read(noteRepositoryProvider).delete(n.isarId);
      unawaited(runForegroundSync());
    }
  }

  Future<void> _editEntry(NoteLocal n) async {
    final result = await showDialog<({String body, String? mood})>(
      context: context,
      builder: (_) => _EditEntryDialog(note: n),
    );
    if (result == null) return;
    await ref
        .read(noteRepositoryProvider)
        .updateEntry(
          isarId: n.isarId,
          body: result.body,
          mood: result.mood,
          link: n.link,
        );
    unawaited(runForegroundSync());
  }

  Future<void> _openComments(NoteLocal n) async {
    final remoteId = n.remoteId;
    if (remoteId == null) {
      _snack('Esta entrada aun se esta sincronizando');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CommentsSheet(noteId: remoteId),
    );
  }

  /// PIN gate: create the couple PIN on first use, verify afterwards, then
  /// open the private diary. The unlock lasts for this app session.
  Future<void> _openPrivate() async {
    final gate = PinGate.instance;
    if (!gate.unlocked) {
      bool isSet;
      try {
        isSet = await gate.isSet();
      } catch (_) {
        _snack('Necesitas conexión para abrir el diario privado');
        return;
      }
      if (!mounted) return;
      final pin = await showDialog<String>(
        context: context,
        builder: (_) => PinDialog(create: !isSet),
      );
      if (pin == null) return;
      try {
        if (isSet) {
          final check = await gate.verify(pin);
          if (!check.ok) {
            _snack(
              check.throttled
                  ? 'Demasiados intentos. Inténtalo en '
                        '${_minutes(check.retryAfter!)}.'
                  : 'PIN incorrecto',
            );
            return;
          }
        } else {
          await gate.setPin(pin);
        }
      } catch (_) {
        _snack('No se pudo validar el PIN');
        return;
      }
      gate.unlocked = true;
    }
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PrivateDiaryScreen()));
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// "un momento" / "3 minutos" — a lockout in seconds reads like a bug.
  String _minutes(int seconds) {
    final m = (seconds / 60).ceil();
    if (m <= 1) return 'un momento';
    return '$m minutos';
  }

  Widget _entryCard(NoteLocal n, User? me, User? partner) {
    final mine = n.authorId == me?.id;
    final author = mine
        ? (me?.prettyName ?? 'tú')
        : (partner?.prettyName ?? 'pareja');

    return _MomentoCard(
      note: n,
      mine: mine,
      author: author,
      onReact: () => _react(n),
      onOpenLink: () => _copyLink(context, n.link),
      onComment: () => _openComments(n),
      onEdit: mine ? () => _editEntry(n) : null,
      onShare: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ShareCardScreen(note: n, author: author),
        ),
      ),
      onDelete: mine ? () => _confirmDeleteEntry(n) : null,
    );
  }

  /// Every entry, newest first — the diary read straight through instead of
  /// one day at a time.
  Widget _listView(List<NoteLocal> notes, User? me, User? partner) {
    if (notes.isEmpty) return const _EmptyDay();
    final ordered = [...notes]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 24),
      itemCount: ordered.length,
      itemBuilder: (_, i) {
        final n = ordered[i];
        return Padding(
          key: ValueKey('feed-note-${n.isarId}'),
          padding: const EdgeInsets.only(bottom: 12),
          child: _entryCard(n, me, partner),
        );
      },
    );
  }

  /// Every photo and clip the diary holds, as a grid of thumbnails. Tapping
  /// one opens the full-screen viewer positioned on it.
  Widget _galleryView(List<NoteLocal> notes) {
    final ordered = [...notes]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final sources = <String>[for (final n in ordered) ...entryMediaSources(n)];

    if (sources.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Todavía no hay fotos ni vídeos en el diario.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: sources.length,
      itemBuilder: (_, i) {
        final src = sources[i];
        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  MediaViewerScreen(sources: sources, initialIndex: i),
            ),
          ),
          child: NeoFrame(
            shadowOffset: const Offset(3, 3),
            child: MediaTools.isVideo(src)
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      VideoPosterImage(src: src),
                      const Center(
                        child: Icon(
                          Icons.play_circle_fill_rounded,
                          color: Neo.white,
                          size: 26,
                        ),
                      ),
                    ],
                  )
                : postMediaTile(src),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    final partner = ref.watch(partnerUserProvider);
    final notes = ref.watch(notesProvider).valueOrNull ?? const <NoteLocal>[];
    final specials =
        ref.watch(specialDatesProvider).valueOrNull ??
        const <SpecialDateLocal>[];
    final txt = Theme.of(context).textTheme;

    final events = <DateTime, List<NoteLocal>>{};
    for (final n in notes) {
      events.putIfAbsent(_key(n.createdAt), () => []).add(n);
    }
    final dayEntries = [...(events[_key(_selectedDay)] ?? const <NoteLocal>[])]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final daySpecials = specials
        .where((s) => _matchesDay(s, _selectedDay))
        .toList();
    final memories = _matchesToday(_selectedDay)
        ? _memoriesFor(notes, _selectedDay)
        : const <NoteLocal>[];

    return Scaffold(
      backgroundColor: Neo.paper,
      floatingActionButton: _composerOpen
          ? null
          : Padding(
              padding: const EdgeInsets.only(right: 4, bottom: 4),
              child: NeoButton(
                label: 'Escribir',
                icon: Icons.edit_rounded,
                onPressed: () => setState(() => _composerOpen = true),
              ),
            ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
              child: Row(
                children: [
                  const NeoIconBadge(
                    icon: Icons.menu_book_rounded,
                    color: Neo.mint,
                  ),
                  const SizedBox(width: 12),
                  Text('Diario', style: txt.titleLarge),
                  const Spacer(),
                  if (_view == 0) ...[
                    NeoButton(
                      label: 'Hoy',
                      color: Neo.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      shadowOffset: Neo.shadowSm,
                      onPressed: () => setState(() {
                        _focusedDay = DateTime.now();
                        _selectedDay = DateTime.now();
                      }),
                    ),
                    const SizedBox(width: 8),
                  ],
                  _ViewSwitch(
                    index: _view,
                    onChanged: (i) => setState(() => _view = i),
                  ),
                  const SizedBox(width: 8),
                  NeoIconButton(
                    icon: Icons.lock_outline_rounded,
                    tooltip: 'Diario privado',
                    color: Neo.rose,
                    size: 40,
                    iconSize: 19,
                    onPressed: _openPrivate,
                  ),
                ],
              ),
            ),
            Expanded(
              child: switch (_view) {
                1 => _listView(notes, me, partner),
                2 => _galleryView(notes),
                _ => ListView(
                  padding: const EdgeInsets.fromLTRB(22, 6, 22, 24),
                  children: [
                    _CalendarToggle(
                      open: _calendarOpen,
                      onTap: _toggleCalendar,
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: !_calendarOpen
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: _CalendarCard(
                                focusedDay: _focusedDay,
                                selectedDay: _selectedDay,
                                events: events,
                                specials: specials,
                                dayKey: _key,
                                matchesDay: _matchesDay,
                                onDaySelected: (selected, focused) =>
                                    setState(() {
                                      _selectedDay = selected;
                                      _focusedDay = focused;
                                    }),
                                onPageChanged: (focused) =>
                                    _focusedDay = focused,
                              ),
                            ),
                    ),
                    const SizedBox(height: 20),
                    if (memories.isNotEmpty) ...[
                      _Capsule(memories: memories),
                      const SizedBox(height: 18),
                    ],
                    for (final s in daySpecials)
                      Padding(
                        // Keyed by row id: without it Flutter matches children by
                        // position, so deleting one leaves the next card wearing
                        // the previous one's state.
                        key: ValueKey('special-${s.isarId}'),
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _SpecialDateCard(
                          special: s,
                          onDelete: () => _confirmDeleteSpecial(s),
                        ),
                      ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Neo.yellow,
                            border: Neo.borderThin,
                            borderRadius: Neo.cornerSm,
                          ),
                          child: Text(
                            _dayLabel(_selectedDay),
                            style: txt.labelMedium?.copyWith(letterSpacing: 1),
                          ),
                        ),
                        const Spacer(),
                        NeoIconButton(
                          icon: Icons.star_rounded,
                          tooltip: 'Marcar fecha especial',
                          color: Neo.lilac,
                          size: 40,
                          iconSize: 20,
                          onPressed: _addSpecialDate,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (dayEntries.isEmpty)
                      const _EmptyDay()
                    else
                      for (final n in dayEntries)
                        Padding(
                          // Keys keep each entry's photos and video bound to the
                          // entry, not to its slot in the list.
                          key: ValueKey('note-${n.isarId}'),
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _entryCard(n, me, partner),
                        ),
                  ],
                ),
              },
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: _composerOpen
                  ? _Composer(
                      dayLabel: _dayLabel(_selectedDay).toLowerCase(),
                      sending: _sending,
                      onSubmit: _submit,
                      onClose: () => setState(() => _composerOpen = false),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── helpers ─────────────────────────────────────────────────────────────────

bool _matchesToday(DateTime d) {
  final n = DateTime.now();
  return d.year == n.year && d.month == n.month && d.day == n.day;
}

bool _matchesDay(SpecialDateLocal s, DateTime day) {
  if (s.recurring) return s.date.month == day.month && s.date.day == day.day;
  return s.date.year == day.year &&
      s.date.month == day.month &&
      s.date.day == day.day;
}

List<NoteLocal> _memoriesFor(List<NoteLocal> notes, DateTime today) {
  return notes
      .where(
        (n) =>
            n.createdAt.month == today.month &&
            n.createdAt.day == today.day &&
            n.createdAt.year < today.year,
      )
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}

void _copyLink(BuildContext context, String? link) {
  if (link == null || link.isEmpty) return;
  Clipboard.setData(ClipboardData(text: link));
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('Enlace copiado')));
}

String _dayLabel(DateTime date) {
  final now = DateTime.now();
  bool same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  if (same(date, now)) return 'HOY';
  if (same(date, now.subtract(const Duration(days: 1)))) return 'AYER';
  final ddMM = DateFormat("d 'de' MMMM", 'es').format(date).toUpperCase();
  return date.year != now.year ? '$ddMM, ${date.year}' : ddMM;
}

/// Icon reaction picker. Returns the icon key, '' to clear, or null.
Future<String?> _pickReaction(BuildContext context, String? current) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Neo.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      side: BorderSide(color: Neo.ink, width: Neo.stroke),
    ),
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'REACCIONAR',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(letterSpacing: 1.5),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final e in _reactionIcons.entries)
                  GestureDetector(
                    onTap: () => Navigator.pop(context, e.key),
                    child: Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: current == e.key ? Neo.pink : Neo.white,
                        border: Neo.border,
                        borderRadius: Neo.cornerSm,
                      ),
                      child: Icon(e.value, size: 26, color: Neo.ink),
                    ),
                  ),
              ],
            ),
            if (current != null) ...[
              const SizedBox(height: 16),
              NeoButton(
                label: 'Quitar reacción',
                icon: Icons.close_rounded,
                color: Neo.white,
                expand: true,
                onPressed: () => Navigator.pop(context, ''),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
