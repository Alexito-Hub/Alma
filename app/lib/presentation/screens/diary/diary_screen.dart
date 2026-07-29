import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/neo.dart';
import '../../../data/device/media_tools.dart';
import '../../../data/local/isar/note_local.dart';
import '../../../data/local/isar/special_date_local.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/note_repository.dart';
import '../../../data/repositories/special_date_repository.dart';

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
    this.videoPath,
    this.geo,
  });
  final String body;
  final String? mood;
  final String? link;
  final List<String> imagePaths;
  final String? videoPath;
  final GeoTag? geo;
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
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

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
            videoPath: d.videoPath,
            latitude: d.geo?.latitude,
            longitude: d.geo?.longitude,
            placeLabel: d.geo?.label,
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
                  NeoButton(
                    label: 'Hoy',
                    color: Neo.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    shadowOffset: Neo.shadowSm,
                    onPressed: () => setState(() {
                      _focusedDay = DateTime.now();
                      _selectedDay = DateTime.now();
                    }),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 24),
                children: [
                  _CalendarCard(
                    focusedDay: _focusedDay,
                    selectedDay: _selectedDay,
                    events: events,
                    specials: specials,
                    dayKey: _key,
                    matchesDay: _matchesDay,
                    onDaySelected: (selected, focused) => setState(() {
                      _selectedDay = selected;
                      _focusedDay = focused;
                    }),
                    onPageChanged: (focused) => _focusedDay = focused,
                  ),
                  const SizedBox(height: 20),
                  if (memories.isNotEmpty) ...[
                    _Capsule(memories: memories),
                    const SizedBox(height: 18),
                  ],
                  for (final s in daySpecials)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _SpecialDateCard(
                        special: s,
                        onDelete: () => ref
                            .read(specialDateRepositoryProvider)
                            .delete(s.isarId),
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
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _MomentoCard(
                          note: n,
                          mine: n.authorId == me?.id,
                          author: n.authorId == me?.id
                              ? (me?.prettyName ?? 'tú')
                              : (partner?.prettyName ?? 'pareja'),
                          onReact: () => _react(n),
                          onOpenLink: () => _copyLink(context, n.link),
                        ),
                      ),
                ],
              ),
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

// ─── calendar ────────────────────────────────────────────────────────────────

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({
    required this.focusedDay,
    required this.selectedDay,
    required this.events,
    required this.specials,
    required this.dayKey,
    required this.matchesDay,
    required this.onDaySelected,
    required this.onPageChanged,
  });

  final DateTime focusedDay;
  final DateTime selectedDay;
  final Map<DateTime, List<NoteLocal>> events;
  final List<SpecialDateLocal> specials;
  final DateTime Function(DateTime) dayKey;
  final bool Function(SpecialDateLocal, DateTime) matchesDay;
  final void Function(DateTime selected, DateTime focused) onDaySelected;
  final void Function(DateTime focused) onPageChanged;

  bool _isSpecial(DateTime day) => specials.any((s) => matchesDay(s, day));

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    return NeoBox(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      shadowOffset: Neo.shadowBtn,
      child: TableCalendar<NoteLocal>(
        locale: 'es',
        firstDay: DateTime.utc(2015),
        lastDay: DateTime.utc(2035, 12, 31),
        focusedDay: focusedDay,
        currentDay: DateTime.now(),
        startingDayOfWeek: StartingDayOfWeek.monday,
        availableCalendarFormats: const {CalendarFormat.month: 'Mes'},
        selectedDayPredicate: (d) => isSameDay(selectedDay, d),
        eventLoader: (day) => events[dayKey(day)] ?? const [],
        onDaySelected: onDaySelected,
        onPageChanged: onPageChanged,
        rowHeight: 46,
        daysOfWeekHeight: 22,
        headerStyle: HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          headerPadding: const EdgeInsets.symmetric(vertical: 6),
          titleTextStyle:
              txt.titleMedium ?? const TextStyle(fontWeight: FontWeight.w800),
          leftChevronIcon: const Icon(
            Icons.chevron_left_rounded,
            color: Neo.ink,
          ),
          rightChevronIcon: const Icon(
            Icons.chevron_right_rounded,
            color: Neo.ink,
          ),
        ),
        daysOfWeekStyle: const DaysOfWeekStyle(
          weekdayStyle: TextStyle(
            color: Neo.ink,
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
          weekendStyle: TextStyle(
            color: Neo.ink,
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
        calendarBuilders: CalendarBuilders<NoteLocal>(
          defaultBuilder: (context, day, _) => _cell(day),
          outsideBuilder: (context, day, _) => _cell(day, outside: true),
          disabledBuilder: (context, day, _) => _cell(day, outside: true),
          todayBuilder: (context, day, _) =>
              _cell(day, fill: Neo.yellow, heavy: true),
          selectedBuilder: (context, day, _) =>
              _cell(day, fill: Neo.pink, heavy: true),
          markerBuilder: (context, day, dayEvents) {
            final special = _isSpecial(day);
            final hasEntries = dayEvents.isNotEmpty;
            if (!special && !hasEntries) return const SizedBox.shrink();
            return Positioned(
              bottom: 4,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasEntries)
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Neo.ink,
                        shape: BoxShape.circle,
                      ),
                    ),
                  if (special)
                    const Padding(
                      padding: EdgeInsets.only(left: 2),
                      child: Icon(Icons.star_rounded, size: 9, color: Neo.ink),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _cell(
    DateTime day, {
    Color? fill,
    bool outside = false,
    bool heavy = false,
  }) {
    return Container(
      margin: const EdgeInsets.all(3),
      alignment: Alignment.center,
      decoration: fill == null
          ? null
          : BoxDecoration(
              color: fill,
              border: Neo.borderThin,
              borderRadius: Neo.cornerSm,
            ),
      child: Text(
        '${day.day}',
        style: TextStyle(
          color: outside ? Neo.ink.withValues(alpha: .3) : Neo.ink,
          fontWeight: heavy ? FontWeight.w900 : FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );
  }
}

// ─── entry card ──────────────────────────────────────────────────────────────

class _MomentoCard extends StatelessWidget {
  const _MomentoCard({
    required this.note,
    required this.mine,
    required this.author,
    required this.onReact,
    required this.onOpenLink,
  });

  final NoteLocal note;
  final bool mine;
  final String author;
  final VoidCallback onReact;
  final VoidCallback onOpenLink;

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
                Text(
                  time,
                  style: txt.labelSmall?.copyWith(
                    color: Neo.ink.withValues(alpha: .7),
                  ),
                ),
              ],
            ),
          ),
          if (note.imagePaths.isNotEmpty)
            _PhotoCarousel(paths: note.imagePaths),
          if (note.videoPath != null) _VideoTile(path: note.videoPath!),
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

class _PhotoCarousel extends StatefulWidget {
  const _PhotoCarousel({required this.paths});
  final List<String> paths;

  @override
  State<_PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends State<_PhotoCarousel> {
  final _pc = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Neo.ink, width: Neo.strokeThin),
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 220,
            child: PageView(
              controller: _pc,
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                for (final p in widget.paths)
                  Image.file(
                    File(p),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const ColoredBox(color: Color(0xFFF3E6CF)),
                  ),
              ],
            ),
          ),
          if (widget.paths.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < widget.paths.length; i++)
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i == _page
                            ? Neo.ink
                            : Neo.ink.withValues(alpha: .25),
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Short video: shows a tap-to-play cover, then plays inline (no autoplay).
class _VideoTile extends StatefulWidget {
  const _VideoTile({required this.path});
  final String path;

  @override
  State<_VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<_VideoTile> {
  VideoPlayerController? _controller;
  bool _ready = false;

  Future<void> _initAndPlay() async {
    final c = VideoPlayerController.file(File(widget.path));
    _controller = c;
    try {
      await c.initialize();
      if (!mounted) return;
      setState(() => _ready = true);
      await c.play();
      c.addListener(() {
        if (mounted) setState(() {});
      });
    } catch (_) {
      // Playback unavailable (e.g. codec) — leave the cover in place.
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Neo.ink, width: Neo.strokeThin),
        ),
      ),
      child: AspectRatio(
        aspectRatio: (_ready && c != null) ? c.value.aspectRatio : 16 / 9,
        child: GestureDetector(
          onTap: () {
            if (!_ready) {
              _initAndPlay();
            } else if (c != null) {
              c.value.isPlaying ? c.pause() : c.play();
              setState(() {});
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_ready && c != null)
                VideoPlayer(c)
              else
                const ColoredBox(color: Neo.ink),
              if (!_ready || (c != null && !c.value.isPlaying))
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Neo.pink,
                      border: Neo.border,
                      borderRadius: BorderRadius.circular(56),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Neo.ink,
                      size: 30,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── capsule + special date ──────────────────────────────────────────────────

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

// ─── composer ────────────────────────────────────────────────────────────────

class _Composer extends StatefulWidget {
  const _Composer({
    required this.dayLabel,
    required this.sending,
    required this.onSubmit,
    required this.onClose,
  });
  final String dayLabel;
  final bool sending;
  final ValueChanged<EntryDraft> onSubmit;
  final VoidCallback onClose;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _body = TextEditingController();
  final _link = TextEditingController();
  String? _mood;
  final List<String> _photos = [];
  String? _videoPath;
  GeoTag? _geo;
  bool _locating = false;

  @override
  void dispose() {
    _body.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final shots = await ImagePicker().pickMultiImage(imageQuality: 88);
    if (shots.isEmpty) return;
    setState(() => _photos.addAll(shots.map((x) => x.path)));
  }

  Future<void> _pickVideo() async {
    final v = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (v != null) setState(() => _videoPath = v.path);
  }

  Future<void> _addLocation() async {
    setState(() => _locating = true);
    final geo = await MediaTools.captureLocation();
    if (!mounted) return;
    setState(() {
      _locating = false;
      _geo = geo;
    });
    if (geo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo obtener la ubicación')),
      );
    }
  }

  void _submit() {
    if (_body.text.trim().isEmpty) return;
    widget.onSubmit(
      EntryDraft(
        body: _body.text,
        mood: _mood,
        link: _link.text.trim().isEmpty ? null : _link.text.trim(),
        imagePaths: List.of(_photos),
        videoPath: _videoPath,
        geo: _geo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    final maxH = MediaQuery.of(context).size.height * 0.62;
    return Container(
      decoration: const BoxDecoration(
        color: Neo.paper,
        border: Border(
          top: BorderSide(color: Neo.ink, width: Neo.stroke),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        14,
        16,
        MediaQuery.of(context).viewInsets.bottom + 14,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const NeoIconBadge(
                    icon: Icons.edit_rounded,
                    color: Neo.pink,
                    size: 30,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'ESCRIBIR · ${widget.dayLabel}',
                      style: txt.labelMedium?.copyWith(letterSpacing: 1.2),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  NeoIconButton(
                    icon: Icons.close_rounded,
                    size: 40,
                    iconSize: 20,
                    onPressed: widget.onClose,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Mood (emoji is fine here).
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final m in _moods)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _mood = _mood == m ? null : m),
                          child: Container(
                            width: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _mood == m ? Neo.mint : Neo.white,
                              border: Neo.borderThin,
                              borderRadius: Neo.cornerSm,
                            ),
                            child: Text(
                              m,
                              style: const TextStyle(fontSize: 20),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _body,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Lo que sientes ahora, o lo que quieres recordar…',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _link,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  hintText: 'Enlace (opcional): canción, artículo…',
                  prefixIcon: Icon(Icons.link_rounded),
                ),
              ),
              const SizedBox(height: 12),
              // Attachment previews.
              if (_photos.isNotEmpty) _photoStrip(),
              if (_videoPath != null)
                _attachmentChip(
                  Icons.movie_rounded,
                  'Vídeo adjunto',
                  Neo.sky,
                  () => setState(() => _videoPath = null),
                ),
              if (_geo != null)
                _attachmentChip(
                  Icons.place_rounded,
                  _geo!.label ?? 'Ubicación',
                  Neo.mint,
                  () => setState(() => _geo = null),
                ),
              // Attachment buttons.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _attachBtn(
                    Icons.add_photo_alternate_outlined,
                    'Fotos',
                    _pickPhotos,
                  ),
                  _attachBtn(Icons.videocam_rounded, 'Vídeo', _pickVideo),
                  _attachBtn(
                    Icons.place_rounded,
                    _locating ? '…' : 'Ubicación',
                    _addLocation,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              NeoButton(
                label: 'Guardar',
                icon: Icons.check_rounded,
                expand: true,
                busy: widget.sending,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachBtn(IconData icon, String label, VoidCallback onTap) {
    return NeoButton(
      label: label,
      icon: icon,
      color: Neo.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      shadowOffset: Neo.shadowSm,
      textStyle: Theme.of(context).textTheme.labelSmall,
      onPressed: onTap,
    );
  }

  Widget _attachmentChip(
    IconData icon,
    String label,
    Color color,
    VoidCallback onRemove,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
        decoration: BoxDecoration(
          color: color,
          border: Neo.borderThin,
          borderRadius: Neo.cornerSm,
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Neo.ink),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: Neo.ink),
              ),
            ),
            GestureDetector(
              onTap: onRemove,
              child: const Icon(Icons.close_rounded, size: 18, color: Neo.ink),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoStrip() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        height: 72,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final p in _photos)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Stack(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        border: Neo.borderThin,
                        borderRadius: Neo.cornerSm,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.file(File(p), fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () => setState(() => _photos.remove(p)),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Neo.ink,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 13,
                            color: Neo.white,
                          ),
                        ),
                      ),
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

// ─── special date dialog ─────────────────────────────────────────────────────

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
