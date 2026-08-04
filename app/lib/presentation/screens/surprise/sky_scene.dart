import 'dart:math' as math;
import 'dart:ui';

import '../../../core/astronomy/constellation.dart';

/// One star of the background field.
class FieldStar {
  const FieldStar(this.position, this.radius, this.depth);

  /// Position in scene coordinates.
  final Offset position;
  final double radius;

  /// Parallax factor. Below 1 is further away and moves less than the camera.
  final double depth;
}

/// The geometry of the star map: how big the sky is, where the constellation
/// hides in it, and how close the camera is to finding it.
///
/// Pure, and derived only from the viewport, so all of it can be tested
/// without pumping a frame.
///
/// **The sky is deliberately bounded.** An endless panorama guarantees she
/// gets lost; two and a half screens by two can be swept in about fifteen
/// seconds while still feeling vast, because the parallax does the work that
/// size was supposed to.
class SkyScene {
  SkyScene({required this.viewport, Constellation? target})
    : target = target ?? leo;

  final Size viewport;
  final Constellation target;

  static const double widthInScreens = 2.5;
  static const double heightInScreens = 2.0;

  /// Where the constellation sits, as a fraction of the scene. Off-centre on
  /// both axes so it is never the first thing on screen — but not in a
  /// corner either, which would make it reachable only by panning to a limit.
  static const Offset anchor = Offset(0.74, 0.30);

  Size get sceneSize =>
      Size(viewport.width * widthInScreens, viewport.height * heightInScreens);

  /// The furthest the camera may travel. Panning is clamped to this, so there
  /// is always something to find rather than an infinity of nothing.
  Offset get maxCamera => Offset(
    sceneSize.width - viewport.width,
    sceneSize.height - viewport.height,
  );

  Offset get targetCenter =>
      Offset(sceneSize.width * anchor.dx, sceneSize.height * anchor.dy);

  /// How wide the figure is drawn. Big enough to read as a shape, small
  /// enough that it fits on screen with room around it.
  double get targetWidth => viewport.width * 0.62;

  Offset clampCamera(Offset camera) => Offset(
    camera.dx.clamp(0.0, maxCamera.dx),
    camera.dy.clamp(0.0, maxCamera.dy),
  );

  /// What the middle of the screen is looking at, in scene coordinates.
  Offset lookingAt(Offset camera) =>
      camera + Offset(viewport.width / 2, viewport.height / 2);

  double distanceToTarget(Offset camera) =>
      (lookingAt(camera) - targetCenter).distance;

  /// 0 when as far from the constellation as this sky allows, 1 when centred.
  ///
  /// Drives the edge cue: something that grows smoothly never has to say
  /// "wrong", it just gets warmer.
  double proximity(Offset camera) {
    final worst = Offset(
      math.max(targetCenter.dx, sceneSize.width - targetCenter.dx),
      math.max(targetCenter.dy, sceneSize.height - targetCenter.dy),
    ).distance;
    if (worst <= 0) return 1;
    return (1 - distanceToTarget(camera) / worst).clamp(0.0, 1.0);
  }

  /// Generous on purpose: it catches when the constellation is roughly
  /// centred, not exactly. Asking for precision in a gift would be cruel.
  bool isLockedOn(Offset camera) =>
      distanceToTarget(camera) <= viewport.shortestSide / 3;

  /// Unit vector from the middle of the screen towards the constellation, or
  /// null once there is nowhere left to point.
  Offset? directionToTarget(Offset camera) {
    final delta = targetCenter - lookingAt(camera);
    final d = delta.distance;
    return d < 1 ? null : delta / d;
  }

  /// The camera offset that centres the constellation. Where the lock-on
  /// spring settles to.
  Offset cameraCentredOnTarget() => clampCamera(
    targetCenter - Offset(viewport.width / 2, viewport.height / 2),
  );

  /// Screen position of each catalogued star, for the given camera.
  Map<String, Offset> targetStarsOnScreen(Offset camera) {
    final norm = target.normalisedPositions();
    // The normalised box is square-ish; scale both axes by the same number so
    // the real proportions survive.
    final scale = targetWidth;
    final cx =
        norm.values.map((p) => p.x).reduce((a, b) => a + b) / norm.length;
    final cy =
        norm.values.map((p) => p.y).reduce((a, b) => a + b) / norm.length;
    return {
      for (final e in norm.entries)
        e.key:
            targetCenter +
            Offset((e.value.x - cx) * scale, (e.value.y - cy) * scale) -
            camera,
    };
  }

  /// Radius to draw a catalogued star at, from its real magnitude.
  ///
  /// Magnitude runs backwards — lower is brighter — and the scale is
  /// logarithmic, so this inverts and compresses it. Regulus at 1.40 has to
  /// visibly outweigh Rasalas at 3.88, because that difference is most of
  /// what makes the shape legible against the field.
  static double radiusForMagnitude(double magnitude) {
    final t = ((5.0 - magnitude) / 4.0).clamp(0.0, 1.0);
    return 1.4 + t * t * 3.6;
  }

  /// The largest a piece of background noise may be drawn.
  ///
  /// Derived from the faintest catalogued star rather than picked by hand, so
  /// the rule holds by construction: **no noise may outshine a real star.**
  /// The constellation has to win on brightness the way it does in the actual
  /// sky — that is half of what makes it findable at all — and a hand-tuned
  /// constant would drift the first time either side is adjusted.
  double get fieldRadiusCeiling {
    final faintest = target.stars
        .map((s) => s.magnitude)
        .reduce((a, b) => a > b ? a : b);
    return radiusForMagnitude(faintest) * 0.72;
  }

  /// The background field: real-feeling noise, generated once from a fixed
  /// seed so the sky is the same on both phones and across restarts.
  List<FieldStar> backgroundField({int seed = 20260814}) {
    final rng = math.Random(seed);
    const depths = [0.35, 0.6, 0.85];
    const counts = [130, 90, 60];
    const floor = 0.35;
    final ceiling = fieldRadiusCeiling;

    final stars = <FieldStar>[];
    for (var l = 0; l < depths.length; l++) {
      // Nearer layers run a little larger, but none reaches the ceiling.
      final largest = ceiling * (0.55 + l * 0.15);
      for (var i = 0; i < counts[l]; i++) {
        stars.add(
          FieldStar(
            Offset(
              rng.nextDouble() * sceneSize.width,
              rng.nextDouble() * sceneSize.height,
            ),
            floor + rng.nextDouble() * (largest - floor),
            depths[l],
          ),
        );
      }
    }
    return stars;
  }
}
