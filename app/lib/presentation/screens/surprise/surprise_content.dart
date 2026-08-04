import 'dart:ui';

import 'package:isar_community/isar.dart';

import '../../../core/config/env.dart';
import '../../../data/local/isar/note_local.dart';
import '../../../data/local/isar_service.dart';
import 'memory_corridor.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  EVERYTHING IN THIS FILE IS YOURS TO WRITE.
//  Nothing here is logic — it is the words and the choices. The sequence
//  reads them; it never invents them.
// ═══════════════════════════════════════════════════════════════════════════

/// The one line she sees before the sky opens. It has to say "look", and
/// nothing else — the whole point is that she does not yet know what she is
/// looking for.
const String openingLine = 'Hay algo ahí arriba esperándote';

/// Her birth date, shown only **after** she finds it. The constellation and
/// the sign are derived from this, not typed twice.
final DateTime birthDate = DateTime(2004, 8, 14);

/// What you want to tell her at that moment, when the sky has just settled
/// and she knows it was hers all along. Two or three lines at most — she is
/// reading it with the constellation still glowing behind.
const String revealMessage =
    'Naciste bajo estas estrellas.\n'
    'Llevan ahí toda tu vida, esperando\n'
    'a que alguien te las enseñara.';

/// The last thing she reads, after the burst.
const String finalMessage = 'Feliz cumpleaños, May.';

/// **The memories, chosen by you.**
///
/// One date per stop, in the order you want her to travel through them,
/// written as `YYYY-MM-DD`. The sequence takes the diary entry from that day
/// and uses its first photograph.
///
/// Leave the list empty and it falls back to picking the oldest entries with
/// photos — usable, but it will not be the story you would have told. This is
/// the part worth spending time on.
const List<String> chosenMemoryDates = [
  // '2026-07-14',
  // '2026-07-28',
  // '2026-08-02',
];

/// What the scraps of paper say, pinned to the memories **in the same order**
/// as [chosenMemoryDates].
///
/// A blank entry leaves that memory bare, and you should use that: a note on
/// every single one turns the corridor into a slideshow with captions. Leave
/// gaps. Let some photographs speak alone.
///
/// Keep them short. They are torn paper, not paragraphs, and she reads them
/// while moving.
const List<String> paperNotes = [
  'nuestro primer cumpleaños juntos',
  '',
  'aquí me di cuenta',
  '',
  '',
  'y volvería a empezar por aquí',
];

// ═══════════════════════════════════════════════════════════════════════════
//  Below here is plumbing.
// ═══════════════════════════════════════════════════════════════════════════

/// Builds the corridor out of the couple's own diary.
///
/// Their real photographs, read from Isar — no network, so the sequence works
/// at midnight whatever the server is doing.
class SurpriseContent {
  SurpriseContent._();

  /// Ceiling when falling back to automatic selection. Long enough to be a
  /// journey, short enough that the last one still matters.
  static const int maxBeats = 6;

  static Future<MemoryCorridor> load() async {
    try {
      final isar = IsarService.instance.db;
      final notes = await isar.noteLocals
          .filter()
          .not()
          .syncStatusEqualTo('deleted')
          .sortByCreatedAt()
          .findAll();

      final picked = chosenMemoryDates.isEmpty
          ? _automatic(notes)
          : _chosen(notes);

      return MemoryCorridor(
        beats: [
          for (var i = 0; i < picked.length; i++)
            if (_beat(picked[i], i) case final b?) b,
        ],
      );
    } catch (_) {
      // No Isar, no diary, no corridor. The sequence still runs; it just has
      // nothing to travel past. Never worth throwing over.
      return MemoryCorridor(beats: const []);
    }
  }

  /// Your picks, in your order. A date with no entry — or an entry with no
  /// photograph — is skipped rather than faked.
  static List<NoteLocal> _chosen(List<NoteLocal> all) {
    final byDay = <String, NoteLocal>{};
    for (final n in all) {
      final key = _dayKey(n.createdAt);
      // First entry of that day wins, and entries are already oldest-first.
      byDay.putIfAbsent(key, () => n);
    }
    return [
      for (final date in chosenMemoryDates)
        if (byDay[date.trim()] case final n?) n,
    ];
  }

  static List<NoteLocal> _automatic(List<NoteLocal> all) =>
      all.where((n) => _firstPhoto(n) != null).take(maxBeats).toList();

  static MemoryBeat? _beat(NoteLocal n, int index) {
    final source = _firstPhoto(n);
    if (source == null) return null;
    return MemoryBeat(
      imagePath: source.$1,
      isRemote: source.$2,
      caption: n.body.trim().isEmpty ? null : n.body.trim(),
      note: _noteFor(index),
    );
  }

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static PaperNote? _noteFor(int index) {
    if (index >= paperNotes.length) return null;
    final text = paperNotes[index].trim();
    if (text.isEmpty) return null;
    // Alternate the side they hang from and lean them opposite ways, so no
    // two in a row look stamped from the same template.
    final left = index.isEven;
    return PaperNote(
      text: text,
      anchor: Offset(left ? 0.30 : 0.66, index.isEven ? 0.20 : 0.74),
      tiltDegrees: left ? -3.5 : 4.0,
    );
  }

  /// The first usable photograph on an entry: a local file while it is still
  /// queued for upload, otherwise the synced URL.
  static (String, bool)? _firstPhoto(NoteLocal n) {
    if (n.imagePaths.isNotEmpty) return (n.imagePaths.first, false);
    if (n.remoteImageUrls.isNotEmpty) {
      final u = n.remoteImageUrls.first;
      return (u.startsWith('http') ? u : '${Env.apiBaseUrl}$u', true);
    }
    return null;
  }
}
