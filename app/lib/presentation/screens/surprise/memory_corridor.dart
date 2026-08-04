import 'dart:math' as math;
import 'dart:ui';

/// A torn scrap of paper stuck over a memory.
class PaperNote {
  const PaperNote({
    required this.text,
    this.anchor = const Offset(0.62, 0.18),
    this.tiltDegrees = -3.5,
    this.widthFraction = 0.52,
  });

  final String text;

  /// Where it sits over its memory, as a fraction of the memory's frame.
  final Offset anchor;

  /// Paper is never straight. Small angles only — past about six degrees it
  /// stops reading as "stuck on" and starts reading as "decoration".
  final double tiltDegrees;

  final double widthFraction;

  /// The corner the note pivots and lifts from. Rotating about the geometric
  /// centre is what makes a note read as a sticker instead of paper.
  Offset get pivot => const Offset(0.12, 0.08);
}

/// One stop along the corridor: a photograph, when it was, and whatever is
/// pinned to it.
class MemoryBeat {
  const MemoryBeat({
    required this.imagePath,
    required this.isRemote,
    this.caption,
    this.note,
    this.depth = 0,
  });

  final String imagePath;
  final bool isRemote;
  final String? caption;
  final PaperNote? note;

  /// Position along the corridor, in beats. Set by [MemoryCorridor].
  final double depth;

  MemoryBeat at(double depth) => MemoryBeat(
    imagePath: imagePath,
    isRemote: isRemote,
    caption: caption,
    note: note,
    depth: depth,
  );
}

/// The corridor the camera travels after the dive.
///
/// Not a carousel: the beats sit at different distances and are nudged off
/// the centre line, so travelling past them shows each from a shifting angle.
/// A memory squared up dead centre reads as a slide, and slides break the
/// single take faster than anything else here.
class MemoryCorridor {
  MemoryCorridor({required this.beats});

  final List<MemoryBeat> beats;

  /// Spacing in beats. The gap before the last one is deliberately wider —
  /// emptiness before the final memory is what makes it land.
  static const double spacing = 1.0;
  static const double finalGap = 1.9;

  /// Total travel from the first beat to past the last.
  double get length =>
      beats.isEmpty ? 0 : depthOf(beats.length - 1) + finalGap * 0.5;

  double depthOf(int index) {
    if (index <= 0) return 0;
    final base = index * spacing;
    return index == beats.length - 1 ? base + (finalGap - spacing) : base;
  }

  /// How far off the centre line beat [index] sits, -1 to 1. Alternates, with
  /// a wobble so it never reads as a zigzag pattern.
  double lateralOf(int index) {
    final side = index.isEven ? 1.0 : -1.0;
    final wobble = 0.55 + (math.sin(index * 2.3) * 0.5 + 0.5) * 0.35;
    return side * wobble;
  }

  /// Visibility of a beat for a camera at [travel], 0 when it is nowhere near
  /// and 1 when the camera is level with it.
  double presence(int index, double travel) {
    final d = (travel - depthOf(index)).abs();
    return (1 - d / 1.6).clamp(0.0, 1.0);
  }

  /// True once the camera has travelled past everything.
  bool isFinished(double travel) => travel >= length;
}
