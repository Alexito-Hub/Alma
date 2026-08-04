import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../core/astronomy/constellation.dart';
import '../../../core/astronomy/zodiac.dart';
import '../../../core/config/birthday_surprise.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/local/surprise_prefs.dart';
import 'sky_scene.dart';

/// The four places the single take passes through.
///
/// Phases, not screens: regions of one continuous space that the camera moves
/// between. Nothing here is ever pushed as a route.
enum SurprisePhase { sky, memories, capsule, message }

/// What the sky is doing right now.
enum _Stage { intro, searching, locking, arrived }

/// Fullscreen host for May's birthday sequence.
///
/// One widget, one camera, one world — so the unbroken-shot illusion is
/// structural rather than something each phase has to remember to preserve.
class SurpriseExperience extends StatefulWidget {
  const SurpriseExperience({super.key, this.preview = false});

  /// The author's rehearsal mode: adds a way out and a set of shortcuts, and
  /// never marks the gift as played.
  final bool preview;

  /// Opens the sequence fullscreen.
  ///
  /// A plain fade, never a slide: a slide would announce "new screen" before
  /// the first frame, which is exactly the cut this is built to avoid.
  static Future<void> open(BuildContext context, {bool preview = false}) {
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 900),
        reverseTransitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, _, _) => SurpriseExperience(preview: preview),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: child,
        ),
      ),
    );
  }

  @override
  State<SurpriseExperience> createState() => _SurpriseExperienceState();
}

class _SurpriseExperienceState extends State<SurpriseExperience>
    with SingleTickerProviderStateMixin {
  // ── the single camera ────────────────────────────────────────────────────
  Offset _camera = Offset.zero;
  Offset _velocity = Offset.zero;
  bool _cameraPlaced = false;

  _Stage _stage = _Stage.intro;
  Ticker? _ticker;
  Duration _last = Duration.zero;

  /// Seconds spent looking. Drives the ladder of hints — she always finds it,
  /// and the faster she does the more it was hers.
  double _searching = 0;

  /// Progress through the lock-on, 0 to 1.
  double _lock = 0;

  double _intro = 0;
  Offset _lockFrom = Offset.zero;

  SkyScene? _scene;
  List<FieldStar> _field = const [];

  @override
  void initState() {
    super.initState();
    // Immersive, not merely edge-to-edge: the system bars are the one thing
    // that would prove this is still an app.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    AppTheme.restoreSystemChrome();
    super.dispose();
  }

  void _ensureScene(Size viewport) {
    if (_scene?.viewport == viewport) return;
    final scene = SkyScene(viewport: viewport);
    _scene = scene;
    _field = scene.backgroundField();
    if (!_cameraPlaced) {
      // Open looking away from her constellation, but not at a wall: far
      // enough that finding it is a discovery, close enough to be reachable.
      _camera = scene.clampCamera(
        Offset(scene.maxCamera.dx * 0.08, scene.maxCamera.dy * 0.78),
      );
      _cameraPlaced = true;
    }
  }

  void _onTick(Duration elapsed) {
    final dt = _last == Duration.zero
        ? 0.016
        : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0 || dt > 0.25) return;

    final scene = _scene;
    if (scene == null) return;

    switch (_stage) {
      case _Stage.intro:
        _intro += dt;
        if (_intro >= _introSeconds) _stage = _Stage.searching;

      case _Stage.searching:
        _searching += dt;
        // Inertia: exponential decay, never linear.
        if (_velocity.distance > 1) {
          _camera = scene.clampCamera(_camera + _velocity * dt);
          _velocity *= math.pow(0.06, dt).toDouble();
        } else if (_velocity != Offset.zero) {
          _velocity = Offset.zero;
        }
        // A sky that is never quite still.
        _camera = scene.clampCamera(
          _camera + const Offset(_ambientDrift, 0) * dt,
        );
        if (scene.isLockedOn(_camera)) {
          _stage = _Stage.locking;
          _lockFrom = _camera;
          _velocity = Offset.zero;
        }

      case _Stage.locking:
        _lock = (_lock + dt / _lockSeconds).clamp(0.0, 1.0);
        // The sky settles into place rather than snapping: she feels the world
        // agree with her, not the app award her a point.
        final t = Curves.easeOutCubic.transform(_lock);
        _camera = Offset.lerp(_lockFrom, scene.cameraCentredOnTarget(), t)!;
        if (_lock >= 1) _stage = _Stage.arrived;

      case _Stage.arrived:
        _searching += dt; // keeps the glow animating
    }

    if (mounted) setState(() {});
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_stage != _Stage.searching) return;
    final scene = _scene;
    if (scene == null) return;
    setState(() {
      // Below 1:1 — the sky moves less than the finger, and that shortfall is
      // its mass.
      _camera = scene.clampCamera(_camera - d.delta * _dragRatio);
      _velocity = Offset.zero;
    });
  }

  void _onPanEnd(DragEndDetails d) {
    if (_stage != _Stage.searching) return;
    setState(() => _velocity = -d.velocity.pixelsPerSecond * _dragRatio);
  }

  void _skipIntro() {
    if (_stage == _Stage.intro) setState(() => _stage = _Stage.searching);
  }

  Future<void> _leave() async {
    if (!widget.preview) await SurprisePrefs.markPlayed();
    if (mounted) Navigator.of(context).maybePop();
  }

  void _restart() => setState(() {
    _stage = _Stage.intro;
    _intro = 0;
    _searching = 0;
    _lock = 0;
    _velocity = Offset.zero;
    _cameraPlaced = false;
    _scene = null;
  });

  @override
  Widget build(BuildContext context) {
    // Leaving is deliberately allowed in both modes: trapping her would be a
    // worse failure than an early exit. `dispose` restores the chrome either
    // way.
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = Size(constraints.maxWidth, constraints.maxHeight);
          _ensureScene(viewport);
          final scene = _scene!;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _skipIntro,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: _SkyPainter(
                    scene: scene,
                    field: _field,
                    camera: _camera,
                    stage: _stage,
                    searching: _searching,
                    lock: _lock,
                  ),
                  isComplex: true,
                  willChange: true,
                ),
                if (_stage == _Stage.intro) _Intro(progress: _intro),
                if (_stage == _Stage.arrived) _Arrived(t: _searching),
                if (widget.preview) _previewControls(scene),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Rehearsal chrome. Built only when [SurpriseExperience.preview] is true,
  /// so there is no code path that can put it in front of her.
  Widget _previewControls(SkyScene scene) {
    final style = TextButton.styleFrom(
      foregroundColor: Colors.white54,
      minimumSize: Size.zero,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    );
    return SafeArea(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white54),
                onPressed: _leave,
              ),
              const Spacer(),
              Text(
                '${_stage.name} · ${_searching.toStringAsFixed(0)}s · '
                '${(scene.proximity(_camera) * 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(width: 12),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  style: style,
                  onPressed: _restart,
                  child: const Text('reiniciar'),
                ),
                TextButton(
                  style: style,
                  onPressed: () => setState(() => _searching = _hintEdge + 0.1),
                  child: const Text('pista 1'),
                ),
                TextButton(
                  style: style,
                  onPressed: () =>
                      setState(() => _searching = _hintPulse + 0.1),
                  child: const Text('pista 2'),
                ),
                TextButton(
                  style: style,
                  onPressed: () =>
                      setState(() => _searching = _hintLines + 0.1),
                  child: const Text('pista 3'),
                ),
                TextButton(
                  style: style,
                  onPressed: () => setState(() {
                    _camera = scene.cameraCentredOnTarget();
                    _stage = _Stage.arrived;
                    _lock = 1;
                  }),
                  child: const Text('encontrar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── the feel, in one place ─────────────────────────────────────────────────
const double _dragRatio = 0.6;
const double _ambientDrift = 0.3;
const double _introSeconds = 4.2;
const double _lockSeconds = 0.75;

/// The ladder of help, in seconds of searching. She always gets there; how
/// fast decides how much of it was hers.
const double _hintEdge = 20; // a warmth at the edge, pointing
const double _hintPulse = 45; // her stars start to breathe
const double _hintLines = 75; // the figure begins to draw itself

/// The opening: her date, the shape she is looking for, and its name.
///
/// Without this the sky is a riddle with no clue — she would be hunting
/// something she has never seen. Drawn from the same catalogue geometry as
/// the real thing, so what she is shown is exactly what she has to find.
class _Intro extends StatelessWidget {
  const _Intro({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    // In, hold, out — the fade out overlaps the sky becoming interactive.
    final fadeIn = (progress / 1.1).clamp(0.0, 1.0);
    final fadeOut = ((_introSeconds - progress) / 1.0).clamp(0.0, 1.0);
    final opacity = Curves.easeInOut.transform(math.min(fadeIn, fadeOut));

    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.55),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '14 de agosto',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 15,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 34),
                SizedBox(
                  width: 210,
                  height: 150,
                  child: CustomPaint(
                    painter: _FigurePainter(
                      reveal: Curves.easeOut.transform(
                        (progress / 2.6).clamp(0.0, 1.0),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 34),
                Text(
                  Zodiac.forDate(BirthdaySurprise.momentFor()).name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    letterSpacing: 8,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Encuentra ${leo.asterismName}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 13,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The constellation drawn on its own, for the opening card. Real positions,
/// real magnitudes, lines tracing themselves in.
class _FigurePainter extends CustomPainter {
  _FigurePainter({required this.reveal});

  final double reveal;

  @override
  void paint(Canvas canvas, Size size) {
    final norm = leo.normalisedPositions();
    final scale = math.min(size.width, size.height / 0.62) * 0.86;
    final cx =
        norm.values.map((p) => p.x).reduce((a, b) => a + b) / norm.length;
    final cy =
        norm.values.map((p) => p.y).reduce((a, b) => a + b) / norm.length;
    Offset at(String id) => Offset(
      size.width / 2 + (norm[id]!.x - cx) * scale,
      size.height / 2 + (norm[id]!.y - cy) * scale,
    );

    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;

    // Trace the sickle first — it is the shape she has to hold on to.
    final ordered = [
      for (var i = 0; i < leo.asterism.length - 1; i++)
        (leo.asterism[i], leo.asterism[i + 1]),
      ...leo.lines.where((l) => !_inAsterism(l.$1) || !_inAsterism(l.$2)),
    ];

    final total = ordered.length;
    for (var i = 0; i < total; i++) {
      final t = (reveal * total - i).clamp(0.0, 1.0);
      if (t <= 0) continue;
      final a = at(ordered[i].$1);
      final b = at(ordered[i].$2);
      canvas.drawLine(a, Offset.lerp(a, b, t)!, line);
    }

    final dot = Paint()..color = Colors.white;
    for (final s in leo.stars) {
      canvas.drawCircle(
        at(s.id),
        SkyScene.radiusForMagnitude(s.magnitude) * 0.62,
        dot..color = Colors.white.withValues(alpha: 0.55 + reveal * 0.45),
      );
    }
  }

  static bool _inAsterism(String id) => leo.asterism.contains(id);

  @override
  bool shouldRepaint(covariant _FigurePainter old) => old.reveal != reveal;
}

/// Held at the end of phase one until phase two exists.
class _Arrived extends StatelessWidget {
  const _Arrived({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final o = (math.sin(t * 1.6) * 0.5 + 0.5) * 0.35 + 0.35;
    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, 0.78),
        child: Text(
          'La encontraste',
          style: TextStyle(
            color: Colors.white.withValues(alpha: o),
            fontSize: 14,
            letterSpacing: 5,
          ),
        ),
      ),
    );
  }
}

class _SkyPainter extends CustomPainter {
  _SkyPainter({
    required this.scene,
    required this.field,
    required this.camera,
    required this.stage,
    required this.searching,
    required this.lock,
  });

  final SkyScene scene;
  final List<FieldStar> field;
  final Offset camera;
  final _Stage stage;
  final double searching;
  final double lock;

  @override
  void paint(Canvas canvas, Size size) {
    _paintField(canvas, size);
    _paintEdgeCue(canvas, size);
    _paintConstellation(canvas);
  }

  void _paintField(Canvas canvas, Size size) {
    final paint = Paint();
    for (final star in field) {
      final p = star.position - camera * star.depth;
      if (p.dx < -8 ||
          p.dy < -8 ||
          p.dx > size.width + 8 ||
          p.dy > size.height + 8) {
        continue;
      }
      // Dimmer than anything catalogued: the constellation has to win on
      // brightness, the way it does in the real sky.
      paint.color = Colors.white.withValues(alpha: 0.20 + star.depth * 0.28);
      canvas.drawCircle(p, star.radius, paint);
    }
  }

  /// A warmth at the edge of the screen, on the side the constellation lies.
  ///
  /// It never says "wrong" and never points with an arrow — it just gets
  /// stronger as she gets closer, which is enough for anyone to read.
  void _paintEdgeCue(Canvas canvas, Size size) {
    if (stage != _Stage.searching || searching < _hintEdge) return;
    final dir = scene.directionToTarget(camera);
    if (dir == null) return;

    final ramp = ((searching - _hintEdge) / 3).clamp(0.0, 1.0);
    final strength = (0.10 + scene.proximity(camera) * 0.5) * ramp;

    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          // Anchored to the edge she should head for, so the glow is a
          // direction rather than an ambient wash.
          center: Alignment(dir.dx, dir.dy),
          radius: 1.1,
          colors: [
            Colors.white.withValues(alpha: strength * 0.30),
            Colors.transparent,
          ],
        ).createShader(rect)
        ..blendMode = BlendMode.plus,
    );
  }

  void _paintConstellation(Canvas canvas) {
    final pos = scene.targetStarsOnScreen(camera);
    final near = scene.proximity(camera);

    // Hint two: her stars begin to breathe.
    final pulse = stage == _Stage.searching && searching >= _hintPulse
        ? (math.sin(searching * 2.2) * 0.5 + 0.5) *
              ((searching - _hintPulse) / 4).clamp(0.0, 1.0)
        : 0.0;

    // Hint three: the figure starts drawing itself. Also what the lock-on
    // completes, so the two share one value and never fight.
    final hinted = stage == _Stage.searching && searching >= _hintLines
        ? ((searching - _hintLines) / 6).clamp(0.0, 0.55)
        : 0.0;
    final drawn = math.max(hinted, lock);

    if (drawn > 0) {
      final line = Paint()
        ..color = Colors.white.withValues(alpha: 0.16 + drawn * 0.5)
        ..strokeWidth = 1.1
        ..strokeCap = StrokeCap.round;
      final total = leo.lines.length;
      for (var i = 0; i < total; i++) {
        final t = (drawn * total - i).clamp(0.0, 1.0);
        if (t <= 0) continue;
        final a = pos[leo.lines[i].$1]!;
        final b = pos[leo.lines[i].$2]!;
        canvas.drawLine(a, Offset.lerp(a, b, t)!, line);
      }
    }

    final paint = Paint();
    for (final s in leo.stars) {
      final p = pos[s.id]!;
      final r = SkyScene.radiusForMagnitude(s.magnitude);
      final glow = lock * 0.9 + pulse * 0.35 + near * 0.15;

      if (glow > 0.02) {
        canvas.drawCircle(
          p,
          r * (2.2 + glow * 3.0),
          paint
            ..color = Colors.white.withValues(alpha: 0.07 * glow)
            ..blendMode = BlendMode.plus,
        );
      }
      canvas.drawCircle(
        p,
        r * (1 + glow * 0.25),
        paint
          ..color = Colors.white.withValues(
            alpha: (0.72 + glow * 0.28).clamp(0.0, 1.0),
          )
          ..blendMode = BlendMode.srcOver,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SkyPainter old) =>
      old.camera != camera ||
      old.stage != stage ||
      old.searching != searching ||
      old.lock != lock;
}
