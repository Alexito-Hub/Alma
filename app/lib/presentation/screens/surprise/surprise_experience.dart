import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../core/astronomy/constellation.dart';
import '../../../core/astronomy/zodiac.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/local/surprise_prefs.dart';
import '../../../data/remote/media_headers.dart';
import 'memory_corridor.dart';
import 'sky_scene.dart';
import 'surprise_content.dart';

/// Where the camera is in the one continuous take.
///
/// Stages, not screens. Each flows into the next by motion — never by a
/// route, never by a cut — and the velocity carries across every seam.
enum _Stage {
  intro,
  searching,
  locking,

  /// The moment it becomes hers: her date, her sign, and what you wanted to
  /// say. Deliberately *after* the search — telling her up front would have
  /// spent the recognition before she earned it.
  reveal,
  diving,
  memories,
  folding,
  capsule,
  bursting,
  message,
}

/// May's birthday sequence.
///
/// Fullscreen, immersive, and identical whoever is watching: there is no
/// preview chrome, no debug overlay and no shortcuts. If it can't be judged
/// by looking at it, it isn't finished.
class SurpriseExperience extends StatefulWidget {
  const SurpriseExperience({super.key, this.preview = false});

  /// Rehearsal only changes bookkeeping — it never marks the gift as played.
  /// Nothing about it is visible.
  final bool preview;

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
  _Stage _stage = _Stage.intro;
  Ticker? _ticker;
  Duration _last = Duration.zero;

  // ── the single camera ───────────────────────────────────────────────────
  Offset _camera = Offset.zero;
  Offset _velocity = Offset.zero;
  bool _cameraPlaced = false;

  /// How deep the dive has gone, 0 to 1. Also drives the sky receding, so the
  /// two can never disagree.
  double _dive = 0;

  /// Distance travelled along the corridor, in beats.
  double _travel = 0;
  double _travelVelocity = 0;

  double _intro = 0;
  double _searching = 0;
  double _lock = 0;
  double _held = 0;
  double _revealed = 0;
  double _fold = 0;
  double _float = 0;
  double _burst = 0;
  double _message = 0;

  Offset _lockFrom = Offset.zero;

  /// Clock for the marked constellation's breathing. Runs from the first
  /// frame so the mark is there before she starts looking, not switched on
  /// once a timer decides to help her.
  double _breath = 0;

  /// Accumulated shake energy, and the still moment before the burst.
  double _shake = 0;
  double _freeze = 0;
  StreamSubscription<AccelerometerEvent>? _accel;

  SkyScene? _scene;
  List<FieldStar> _field = const [];
  MemoryCorridor _corridor = MemoryCorridor(beats: const []);

  @override
  void initState() {
    super.initState();
    // Immersive, not merely edge-to-edge: the system bars are the one thing
    // that would prove this is still an app.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _ticker = createTicker(_onTick)..start();
    unawaited(_loadCorridor());
  }

  Future<void> _loadCorridor() async {
    final corridor = await SurpriseContent.load();
    if (mounted) setState(() => _corridor = corridor);
  }

  @override
  void dispose() {
    _accel?.cancel();
    _ticker?.dispose();
    AppTheme.restoreSystemChrome();
    super.dispose();
  }

  void _listenForShake() {
    _accel ??= accelerometerEventStream().listen((e) {
      // Gravity removed crudely: what matters is the change, not the vector.
      final magnitude = (math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z) - 9.81)
          .abs();
      if (magnitude > 3.5) {
        _shake = (_shake + magnitude * 0.035).clamp(0.0, 1.4);
      }
    });
  }

  void _ensureScene(Size viewport) {
    if (_scene?.viewport == viewport) return;
    final scene = SkyScene(viewport: viewport);
    _scene = scene;
    _field = scene.backgroundField();
    if (!_cameraPlaced) {
      // Open looking away from her constellation — far enough that finding it
      // is a discovery, close enough that it is reachable.
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
        _breath += dt;
        if (_intro >= _introSeconds) _stage = _Stage.searching;

      case _Stage.searching:
        _searching += dt;
        _breath += dt;
        if (_velocity.distance > 1) {
          // Exponential decay, never linear: a linear stop reads as mechanical.
          _camera = scene.clampCamera(_camera + _velocity * dt);
          _velocity *= math.pow(0.06, dt).toDouble();
        } else if (_velocity != Offset.zero) {
          _velocity = Offset.zero;
        }
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
        // The sky settles rather than snapping: she feels the world agree with
        // her, not the app award her a point.
        _camera = Offset.lerp(
          _lockFrom,
          scene.cameraCentredOnTarget(),
          Curves.easeOutCubic.transform(_lock),
        )!;
        if (_lock >= 1) {
          _held += dt;
          // A breath with just the constellation, before any words land.
          if (_held >= _holdSeconds) _stage = _Stage.reveal;
        }

      case _Stage.reveal:
        _revealed += dt;
        if (_revealed >= _revealSeconds) _stage = _Stage.diving;

      case _Stage.diving:
        // Ease **in**: it starts slow and keeps accelerating through the
        // whiteout. Decelerating before a seam is what reads as a cut.
        _dive = (_dive + dt / _diveSeconds).clamp(0.0, 1.0);
        if (_dive >= 1) _stage = _Stage.memories;

      case _Stage.memories:
        if (_travelVelocity.abs() > 0.01) {
          _travel += _travelVelocity * dt;
          _travelVelocity *= math.pow(0.12, dt).toDouble();
        }
        // Never quite still: a slow drift forward carries her if she stops.
        _travel += _corridorDrift * dt;
        _travel = _travel.clamp(0.0, _corridor.length + 0.4);
        if (_corridor.isFinished(_travel)) {
          _stage = _Stage.folding;
          _travelVelocity = 0;
        }

      case _Stage.folding:
        _fold = (_fold + dt / _foldSeconds).clamp(0.0, 1.0);
        if (_fold >= 1) {
          _stage = _Stage.capsule;
          _listenForShake();
        }

      case _Stage.capsule:
        _float += dt;
        // Shake energy bleeds away, so it has to be sustained rather than
        // reached once by accident.
        _shake = math.max(0, _shake - dt * 0.55);
        // The fallback: if the accelerometer never cooperates, the gift must
        // not dead-end here. After a while a press does it too.
        if (_shake >= 1.0) {
          _stage = _Stage.bursting;
        }

      case _Stage.bursting:
        // The stillness before the release is the whole trick.
        if (_freeze < _freezeSeconds) {
          _freeze += dt;
        } else {
          _burst = (_burst + dt / _burstSeconds).clamp(0.0, 1.0);
          if (_burst >= 1) _stage = _Stage.message;
        }

      case _Stage.message:
        _message += dt;
    }

    if (mounted) setState(() {});
  }

  // ── input ────────────────────────────────────────────────────────────────

  void _onPanUpdate(DragUpdateDetails d) {
    final scene = _scene;
    if (scene == null) return;
    switch (_stage) {
      case _Stage.searching:
        setState(() {
          // Below 1:1 — the sky moves less than the finger, and that shortfall
          // is its mass.
          _camera = scene.clampCamera(_camera - d.delta * _dragRatio);
          _velocity = Offset.zero;
        });
      case _Stage.memories:
        setState(() {
          _travel = (_travel - d.delta.dy / _pixelsPerBeat).clamp(
            0.0,
            _corridor.length + 0.4,
          );
          _travelVelocity = 0;
        });
      case _ when _stage == _Stage.capsule:
        // Dragging the capsule swings it, which is what invites the shake.
        setState(
          () => _shake = math.min(1.0, _shake + d.delta.distance * 0.002),
        );
      default:
        break;
    }
  }

  void _onPanEnd(DragEndDetails d) {
    switch (_stage) {
      case _Stage.searching:
        setState(() => _velocity = -d.velocity.pixelsPerSecond * _dragRatio);
      case _Stage.memories:
        setState(
          () =>
              _travelVelocity = -d.velocity.pixelsPerSecond.dy / _pixelsPerBeat,
        );
      default:
        break;
    }
  }

  void _onTap() {
    if (_stage == _Stage.intro) setState(() => _stage = _Stage.searching);
  }

  /// The safety net under the shake. Accelerometers vary by phone, and a gift
  /// that dead-ends because a sensor was unhelpful would be unforgivable.
  void _onLongPress() {
    if (_stage == _Stage.capsule && _float > _pressFallbackAfter) {
      setState(() => _stage = _Stage.bursting);
    }
  }

  Future<void> _leave() async {
    if (!widget.preview) await SurprisePrefs.markPlayed();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    // Leaving is deliberately possible: trapping her would be a worse failure
    // than an early exit. `dispose` restores the system chrome either way.
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = Size(constraints.maxWidth, constraints.maxHeight);
          _ensureScene(viewport);
          final scene = _scene!;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onTap,
            onLongPress: _onLongPress,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_stage.index <= _Stage.diving.index)
                  CustomPaint(
                    painter: _SkyPainter(
                      scene: scene,
                      field: _field,
                      camera: _camera,
                      searching: _searching,
                      isSearching: _stage == _Stage.searching,
                      breath: _breath,
                      lock: _lock,
                      dive: _dive,
                    ),
                    isComplex: true,
                    willChange: true,
                  ),
                if (_stage == _Stage.intro) _Intro(progress: _intro),
                if (_stage == _Stage.reveal) _Reveal(t: _revealed),
                if (_stage.index >= _Stage.diving.index &&
                    _stage.index <= _Stage.folding.index)
                  _Corridor(
                    corridor: _corridor,
                    travel: _travel,
                    arriving: _stage == _Stage.diving ? _dive : 1,
                    fold: _fold,
                    viewport: viewport,
                  ),
                if (_stage == _Stage.diving) _Whiteout(dive: _dive),
                if (_stage == _Stage.capsule ||
                    _stage == _Stage.bursting ||
                    _stage == _Stage.folding)
                  _Capsule(
                    fold: _fold,
                    float: _float,
                    strain: _shake,
                    frozen: _stage == _Stage.bursting,
                  ),
                if (_stage == _Stage.bursting && _burst > 0)
                  CustomPaint(painter: _BurstPainter(progress: _burst)),
                if (_stage == _Stage.message) _FinalMessage(t: _message),
                if (_stage == _Stage.message && _message > 6)
                  _Ending(onClose: _leave),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── the feel, in one place ─────────────────────────────────────────────────
const double _dragRatio = 0.6;
const double _ambientDrift = 0.3;
const double _introSeconds = 4.6;
const double _lockSeconds = 0.75;
const double _holdSeconds = 1.6;
const double _revealSeconds = 8.5;
const double _diveSeconds = 1.9;
const double _foldSeconds = 1.3;
const double _burstSeconds = 0.7;
const double _freezeSeconds = 0.1;
const double _corridorDrift = 0.05;
const double _pixelsPerBeat = 420;
const double _pressFallbackAfter = 14;

/// The ladder of help while she searches, in seconds. She always gets there;
/// how fast decides how much of it was hers.
const double _hintEdge = 20;
const double _hintPulse = 45;
const double _hintLines = 75;

// ═══ phase one ═════════════════════════════════════════════════════════════

/// The opening. One line, and then it gets out of the way.
///
/// It used to show her the constellation up front so she would know what to
/// look for — which worked, and spent the recognition before she had earned
/// it. She finds it because it is *marked*: hers is the only thing in that
/// sky that breathes. Nothing has to be explained.
class _Intro extends StatelessWidget {
  const _Intro({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final fadeIn = (progress / 1.4).clamp(0.0, 1.0);
    final fadeOut = ((_introSeconds - progress) / 1.2).clamp(0.0, 1.0);
    final opacity = Curves.easeInOut.transform(math.min(fadeIn, fadeOut));

    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              openingLine,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 16,
                height: 1.6,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The moment it turns out to be hers.
///
/// Arrives only after she has found it, with the constellation still lit
/// behind: her date, the sign that sky really gives her, and your words. The
/// figure is drawn small alongside, from the same catalogue geometry, so what
/// she is told matches what she is looking at.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    // Staggered: the date, then the sign, then what you wanted to say. All
    // three at once would read as a certificate.
    double at(double start, double span) =>
        Curves.easeOut.transform(((t - start) / span).clamp(0.0, 1.0));
    final out = ((_revealSeconds - t) / 1.1).clamp(0.0, 1.0);

    final sign = Zodiac.forDate(birthDate).name;
    final day = birthDate.day;
    const months = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];

    return IgnorePointer(
      child: Opacity(
        opacity: out,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.55 * at(0, 1.2)),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: at(0.5, 1.2),
                  child: Text(
                    '$day de ${months[birthDate.month - 1]} '
                    'de ${birthDate.year}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 15,
                      letterSpacing: 4,
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                Opacity(
                  opacity: at(1.4, 1.4),
                  child: SizedBox(
                    width: 190,
                    height: 132,
                    child: CustomPaint(
                      painter: _FigurePainter(reveal: at(1.4, 2.0)),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Opacity(
                  opacity: at(2.0, 1.2),
                  child: Text(
                    sign,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      letterSpacing: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                Opacity(
                  opacity: at(3.2, 1.8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      revealMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.80),
                        fontSize: 15,
                        height: 1.75,
                        letterSpacing: 1,
                      ),
                    ),
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

/// The constellation alone, for the opening card. Real positions, real
/// magnitudes, lines tracing themselves in.
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

    // The sickle first: it is the shape she has to hold on to.
    final ordered = [
      for (var i = 0; i < leo.asterism.length - 1; i++)
        (leo.asterism[i], leo.asterism[i + 1]),
      ...leo.lines.where(
        (l) => !leo.asterism.contains(l.$1) || !leo.asterism.contains(l.$2),
      ),
    ];

    for (var i = 0; i < ordered.length; i++) {
      final t = (reveal * ordered.length - i).clamp(0.0, 1.0);
      if (t <= 0) continue;
      final a = at(ordered[i].$1);
      final b = at(ordered[i].$2);
      canvas.drawLine(a, Offset.lerp(a, b, t)!, line);
    }

    final dot = Paint();
    for (final s in leo.stars) {
      canvas.drawCircle(
        at(s.id),
        SkyScene.radiusForMagnitude(s.magnitude) * 0.62,
        dot..color = Colors.white.withValues(alpha: 0.55 + reveal * 0.45),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FigurePainter old) => old.reveal != reveal;
}

class _SkyPainter extends CustomPainter {
  _SkyPainter({
    required this.scene,
    required this.field,
    required this.camera,
    required this.searching,
    required this.isSearching,
    required this.breath,
    required this.lock,
    required this.dive,
  });

  final SkyScene scene;
  final List<FieldStar> field;
  final Offset camera;
  final double searching;
  final bool isSearching;

  /// Clock for the mark. See [_paintConstellation].
  final double breath;

  final double lock;
  final double dive;

  @override
  void paint(Canvas canvas, Size size) {
    // The dive is sold by the foreground streaming past the camera, not by
    // the target scaling up. Everything is pushed outward from Regulus.
    final centre = Offset(size.width / 2, size.height / 2);
    if (dive > 0) {
      canvas.save();
      final push = 1 + Curves.easeInCubic.transform(dive) * 7.5;
      canvas.translate(centre.dx, centre.dy);
      canvas.scale(push);
      canvas.translate(-centre.dx, -centre.dy);
    }

    _paintField(canvas, size);
    _paintEdgeCue(canvas, size);
    _paintConstellation(canvas);

    if (dive > 0) canvas.restore();
  }

  void _paintField(Canvas canvas, Size size) {
    final paint = Paint();
    final fade = 1 - dive;
    for (final star in field) {
      final p = star.position - camera * star.depth;
      if (p.dx < -8 ||
          p.dy < -8 ||
          p.dx > size.width + 8 ||
          p.dy > size.height + 8) {
        continue;
      }
      // Dimmer than anything catalogued: the constellation wins on brightness
      // the way it does in the real sky.
      paint.color = Colors.white.withValues(
        alpha: (0.20 + star.depth * 0.28) * fade,
      );
      canvas.drawCircle(p, star.radius, paint);
    }
  }

  /// A warmth at the edge, on the side the constellation lies. It never says
  /// "wrong" and never points with an arrow — it just gets stronger.
  void _paintEdgeCue(Canvas canvas, Size size) {
    if (!isSearching || searching < _hintEdge) return;
    final dir = scene.directionToTarget(camera);
    if (dir == null) return;

    final ramp = ((searching - _hintEdge) / 3).clamp(0.0, 1.0);
    final strength = (0.10 + scene.proximity(camera) * 0.5) * ramp;
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
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

    // **The mark.** Her stars are the only thing in this sky that breathes,
    // and they breathe *together* — everything else is fixed. That is what
    // makes the constellation findable without ever being explained: the eye
    // catches motion in a still field long before the mind names a shape.
    // Slow, so it reads as alive rather than as a blinking indicator.
    final marked = (math.sin(breath * 1.15) * 0.5 + 0.5) * 0.34;

    // The ladder of help deepens the same breath rather than adding a second
    // effect on top; two rhythms at once would look like a malfunction.
    final pulse =
        marked +
        (isSearching && searching >= _hintPulse
            ? (math.sin(searching * 2.2) * 0.5 + 0.5) *
                  ((searching - _hintPulse) / 4).clamp(0.0, 1.0) *
                  0.5
            : 0.0);

    final hinted = isSearching && searching >= _hintLines
        ? ((searching - _hintLines) / 6).clamp(0.0, 0.55)
        : 0.0;
    final drawn = math.max(hinted, lock);

    if (drawn > 0) {
      final line = Paint()
        ..color = Colors.white.withValues(alpha: 0.16 + drawn * 0.5)
        ..strokeWidth = 1.1
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < leo.lines.length; i++) {
        final t = (drawn * leo.lines.length - i).clamp(0.0, 1.0);
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
      // Regulus is the door: it keeps brightening through the dive while the
      // rest of the sky is left behind.
      final isDoor = s.id == 'alp';
      final glow =
          lock * 0.9 + pulse * 0.35 + near * 0.15 + (isDoor ? dive * 6 : 0);

      if (glow > 0.02) {
        canvas.drawCircle(
          p,
          r * (2.2 + glow * 3.0),
          paint
            ..color = Colors.white.withValues(alpha: (0.07 * glow).clamp(0, 1))
            ..blendMode = BlendMode.plus,
        );
      }
      canvas.drawCircle(
        p,
        r * (1 + glow * 0.25),
        paint
          ..color = Colors.white.withValues(
            alpha: ((0.72 + glow * 0.28) * (isDoor ? 1 : 1 - dive)).clamp(0, 1),
          )
          ..blendMode = BlendMode.srcOver,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SkyPainter old) =>
      old.camera != camera ||
      old.searching != searching ||
      old.breath != breath ||
      old.lock != lock ||
      old.dive != dive ||
      old.isSearching != isSearching;
}

/// The light Regulus becomes. Grows through the end of the dive and is gone
/// by the time the corridor has arrived, so the seam is inside the brightest
/// frame rather than at a cut.
class _Whiteout extends StatelessWidget {
  const _Whiteout({required this.dive});

  final double dive;

  @override
  Widget build(BuildContext context) {
    final t = Curves.easeInCubic.transform(dive);
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            radius: 0.15 + t * 2.4,
            colors: [
              Colors.white.withValues(alpha: (t * 1.6).clamp(0, 1)),
              Colors.white.withValues(alpha: 0),
            ],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

// ═══ phase two ═════════════════════════════════════════════════════════════

/// The corridor of memories, with the paper stuck over them.
class _Corridor extends StatelessWidget {
  const _Corridor({
    required this.corridor,
    required this.travel,
    required this.arriving,
    required this.fold,
    required this.viewport,
  });

  final MemoryCorridor corridor;
  final double travel;

  /// 0 while still inside the light, 1 once the corridor has arrived. Eases
  /// **out**, continuing the dive's motion instead of restarting it.
  final double arriving;

  final double fold;
  final Size viewport;

  @override
  Widget build(BuildContext context) {
    if (corridor.beats.isEmpty) return const SizedBox.shrink();
    final settle = Curves.easeOutCubic.transform(arriving);

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (var i = corridor.beats.length - 1; i >= 0; i--)
            _MemoryFrame(
              beat: corridor.beats[i],
              presence: corridor.presence(i, travel),
              offsetInBeats: travel - corridor.depthOf(i),
              lateral: corridor.lateralOf(i),
              settle: settle,
              // Only the last one folds; the rest have already gone by.
              fold: i == corridor.beats.length - 1 ? fold : 0,
              viewport: viewport,
            ),
        ],
      ),
    );
  }
}

class _MemoryFrame extends StatelessWidget {
  const _MemoryFrame({
    required this.beat,
    required this.presence,
    required this.offsetInBeats,
    required this.lateral,
    required this.settle,
    required this.fold,
    required this.viewport,
  });

  final MemoryBeat beat;
  final double presence;
  final double offsetInBeats;
  final double lateral;
  final double settle;
  final double fold;
  final Size viewport;

  @override
  Widget build(BuildContext context) {
    if (presence <= 0.001 && fold <= 0) return const SizedBox.shrink();

    // Distance along the corridor drives scale, so passing one is a dolly
    // rather than a slide.
    final depthScale = (1.0 - offsetInBeats * 0.42).clamp(0.25, 1.6);
    final scale = depthScale * (0.86 + settle * 0.14);

    // Off the centre line, and shifting as it is passed — a memory squared up
    // dead centre reads as a slide.
    final dx = lateral * viewport.width * 0.17 * (1 - offsetInBeats * 0.35);
    final dy = -offsetInBeats * viewport.height * 0.30;

    final width = viewport.width * 0.72;
    final height = width * 1.18;

    // The fold: anisotropic and in stages, so the eye reads paper being
    // rolled rather than an image being shrunk.
    final foldX = fold <= 0
        ? 1.0
        : 1 - Curves.easeInOut.transform((fold / 0.55).clamp(0.0, 1.0)) * 0.92;
    final foldY = fold <= 0.4
        ? 1.0
        : 1 -
              Curves.easeInOut.transform(((fold - 0.4) / 0.6).clamp(0.0, 1.0)) *
                  0.86;
    final foldTwist = fold <= 0.7
        ? 0.0
        : Curves.easeOut.transform(((fold - 0.7) / 0.3).clamp(0.0, 1.0)) * 0.22;

    return Center(
      child: Transform.translate(
        offset: Offset(dx, dy),
        child: Transform.rotate(
          angle: lateral * 0.035 + foldTwist,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..scaleByDouble(scale * foldX, scale * foldY, 1, 1),
            child: Opacity(
              opacity: (presence * settle).clamp(0.0, 1.0),
              child: SizedBox(
                width: width,
                height: height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(child: _photo()),
                    if (beat.note != null && fold <= 0)
                      _Note(
                        note: beat.note!,
                        frame: Size(width, height),
                        // Paper lags the photograph and settles with a single
                        // overshoot. One overshoot is paper; two is jelly and
                        // none is a sticker.
                        lag: offsetInBeats,
                        presence: presence,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _photo() {
    final image = beat.isRemote
        ? CachedNetworkImage(
            imageUrl: beat.imagePath,
            httpHeaders: mediaHeaders(),
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => const ColoredBox(color: Colors.black26),
          )
        : Image.file(
            File(beat.imagePath),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black26),
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 30,
            spreadRadius: 4,
          ),
        ],
      ),
      child: image,
    );
  }
}

/// A scrap of torn paper, stuck on.
class _Note extends StatelessWidget {
  const _Note({
    required this.note,
    required this.frame,
    required this.lag,
    required this.presence,
  });

  final PaperNote note;
  final Size frame;
  final double lag;
  final double presence;

  @override
  Widget build(BuildContext context) {
    final width = frame.width * note.widthFraction;
    // Parallax against the photograph: small, on purpose. Too much separation
    // and it stops being stuck on and starts floating like a balloon.
    const parallax = 1.18;
    final drift = lag * frame.height * 0.30 * (parallax - 1);
    // The single overshoot that makes paper read as paper.
    final settle = math.sin(lag * 3.2) * math.exp(-lag.abs() * 2.4) * 4;

    return Positioned(
      left: frame.width * note.anchor.dx - width * note.pivot.dx,
      top: frame.height * note.anchor.dy + drift + settle,
      child: Opacity(
        opacity: presence,
        child: Transform.rotate(
          alignment: Alignment(-1 + note.pivot.dx * 2, -1 + note.pivot.dy * 2),
          angle: note.tiltDegrees * math.pi / 180,
          child: Container(
            width: width,
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 13),
            decoration: BoxDecoration(
              color: const Color(0xFFF6EFE1),
              boxShadow: [
                // Hard-edged, offset: the shadow of a lifted corner, and the
                // strongest cue that the note sits *above* the photograph.
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  offset: const Offset(3, 5),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Text(
              note.text,
              style: const TextStyle(
                color: Color(0xFF241F1A),
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══ phase three ═══════════════════════════════════════════════════════════

/// What the last memory folds into: a small thing held in the middle of an
/// emptied screen, with enough weight to be worth shaking.
class _Capsule extends StatelessWidget {
  const _Capsule({
    required this.fold,
    required this.float,
    required this.strain,
    required this.frozen,
  });

  final double fold;
  final double float;

  /// Accumulated shake energy, 0 to 1. Everything about the capsule reacts to
  /// it, so she can see she is doing it right.
  final double strain;

  final bool frozen;

  @override
  Widget build(BuildContext context) {
    if (fold < 0.62) return const SizedBox.shrink();
    final born = ((fold - 0.62) / 0.38).clamp(0.0, 1.0);

    // Two sines of incommensurate period, so the drift never visibly repeats.
    final driftX = frozen ? 0.0 : math.sin(float * 1.26) * 7;
    final driftY = frozen ? 0.0 : math.cos(float * 0.9) * 9;

    // The tremble: it starts on its own after a while — something inside
    // wanting out — and grows with how hard she shakes.
    final restless = frozen
        ? 0.0
        : ((float - 5) / 6).clamp(0.0, 1.0) * 0.6 + strain;
    final jitter = frozen ? 0.0 : math.sin(float * 34) * restless * 3.2;

    return IgnorePointer(
      child: Center(
        child: Transform.translate(
          offset: Offset(driftX + jitter, driftY),
          child: Transform.scale(
            // Strained along the axis she is shaking.
            scaleX: born * (1 + strain * 0.16),
            scaleY: born * (1 - strain * 0.07),
            child: Container(
              width: 58,
              height: 92,
              decoration: BoxDecoration(
                color: const Color(0xFFF6EFE1),
                borderRadius: BorderRadius.circular(29),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.10 + strain * 0.45),
                    blurRadius: 26 + strain * 46,
                    spreadRadius: 2 + strain * 12,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══ phase four ════════════════════════════════════════════════════════════

/// The shockwave. Fast out of the gate and decelerating as it goes, because a
/// shockwave loses energy — and with a crisp edge, because a soft one reads
/// as a fade instead of a wipe.
class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final reach = size.longestSide * 0.95;
    final t = Curves.easeOutQuart.transform(progress);
    final radius = t * reach;

    // Everything the wave has passed is gone; everything ahead is untouched.
    canvas.drawCircle(
      centre,
      radius,
      Paint()..color = Colors.black.withValues(alpha: 1),
    );
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 + (1 - t) * 12
        ..color = Colors.white.withValues(alpha: (1 - t) * 0.9),
    );
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) => old.progress != progress;
}

/// What the wave leaves behind. Silence first — the emptiness before the
/// words is doing as much work as the words.
class _FinalMessage extends StatelessWidget {
  const _FinalMessage({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final appear = Curves.easeOut.transform(((t - 0.9) / 2.2).clamp(0.0, 1.0));
    return IgnorePointer(
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _RingsPainter(t: t)),
            Center(
              child: Opacity(
                opacity: appear,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    finalMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 24,
                      height: 1.5,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rings born low and centre, expanding and decaying so several coexist. They
/// trail rather than track — a perfectly synced visualiser reads as a media
/// player; one that lags slightly reads as resonance.
class _RingsPainter extends CustomPainter {
  _RingsPainter({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * 0.72);
    const period = 1.7;
    const lifetime = 2.0;

    for (var i = 0; i < 4; i++) {
      final age = t - i * period / 2;
      if (age <= 0) continue;
      final phase = (age % lifetime) / lifetime;
      final radius = phase * size.longestSide * 0.55;
      final fade = (1 - phase) * 0.30;
      if (fade <= 0.01) continue;
      canvas.drawCircle(
        origin,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 + (1 - phase) * 1.6
          ..color = Colors.white.withValues(alpha: fade),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingsPainter old) => old.t != t;
}

/// The way back. It never snaps to the app — the last state holds until she
/// decides she is done.
class _Ending extends StatelessWidget {
  const _Ending({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, 0.88),
      child: TextButton(
        onPressed: onClose,
        child: Text(
          'volver',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 13,
            letterSpacing: 4,
          ),
        ),
      ),
    );
  }
}
