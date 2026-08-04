import 'dart:ui';

import 'package:isar_community/isar.dart';

import '../../../core/config/env.dart';
import '../../../data/local/isar/note_local.dart';
import '../../../data/local/isar_service.dart';
import 'memory_corridor.dart';

/// What the paper notes say.
///
/// **These are yours to write.** They are pinned to the memories in order —
/// the first text goes on the first photograph the corridor reaches, and a
/// blank entry leaves that memory bare, which is worth doing: a note on every
/// single one turns the corridor into a slideshow with captions. Leave gaps.
///
/// Keep them short. They are scraps of paper, not paragraphs, and they are
/// read while moving.
const List<String> paperNotes = [
  'nuestro primer cumpleaños juntos',
  '',
  'aquí me di cuenta',
  '',
  '',
  'y volvería a empezar por aquí',
];

/// The last thing she reads, after the burst. Yours to write.
const String finalMessage = 'Feliz cumpleaños, May.';

/// Builds the corridor out of the couple's own diary.
///
/// Their real photographs, oldest first, so travelling forward is travelling
/// forward in time. Nothing is invented and nothing is fetched: these are the
/// rows already on the phone, which also means the sequence works with no
/// network at midnight.
class SurpriseContent {
  SurpriseContent._();

  /// How many stops the corridor gets. Long enough to be a journey, short
  /// enough that the last one still matters.
  static const int maxBeats = 6;

  static Future<MemoryCorridor> load() async {
    final beats = <MemoryBeat>[];
    try {
      final isar = IsarService.instance.db;
      final notes = await isar.noteLocals
          .filter()
          .not()
          .syncStatusEqualTo('deleted')
          .sortByCreatedAt() // oldest first: the journey runs forwards
          .findAll();

      for (final n in notes) {
        final source = _firstPhoto(n);
        if (source == null) continue;
        final index = beats.length;
        beats.add(
          MemoryBeat(
            imagePath: source.$1,
            isRemote: source.$2,
            caption: n.body.trim().isEmpty ? null : n.body.trim(),
            note: _noteFor(index),
          ),
        );
        if (beats.length >= maxBeats) break;
      }
    } catch (_) {
      // No Isar, no diary, no corridor — the sequence still runs, just with
      // nothing to travel past. Never worth throwing over.
    }

    return MemoryCorridor(
      beats: [for (var i = 0; i < beats.length; i++) beats[i]],
    );
  }

  static PaperNote? _noteFor(int index) {
    if (index >= paperNotes.length) return null;
    final text = paperNotes[index].trim();
    if (text.isEmpty) return null;
    // Alternate which side they hang from, and lean them opposite ways, so no
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
