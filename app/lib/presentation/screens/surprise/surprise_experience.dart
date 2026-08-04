import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/local/surprise_prefs.dart';

/// The four places the single take passes through.
///
/// Phases, not screens: they are regions of one continuous space, and the
/// camera never cuts between them. Nothing here is ever pushed as a route.
enum SurprisePhase { sky, memories, capsule, message }

/// Fullscreen host for May's birthday sequence.
///
/// Everything the sequence needs lives under one widget with one camera, so
/// the illusion of a single unbroken shot is structural rather than something
/// each phase has to remember to preserve.
///
/// [preview] is the author's rehearsal mode: it adds a way out and a phase
/// jumper, and never marks the gift as played.
class SurpriseExperience extends StatefulWidget {
  const SurpriseExperience({super.key, this.preview = false});

  final bool preview;

  /// Opens the sequence fullscreen.
  ///
  /// Deliberately a plain fade with no Material chrome: a slide transition
  /// would announce "new screen" before the first frame, which is exactly the
  /// cut the whole thing is built to avoid.
  static Future<void> open(BuildContext context, {bool preview = false}) {
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 650),
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
  SurprisePhase _phase = SurprisePhase.sky;

  /// Where the camera is looking, in scene units. Shared by every phase —
  /// this single value is what makes the sequence one shot.
  Offset _camera = Offset.zero;

  /// Residual velocity after a fling, in scene units per second.
  Offset _velocity = Offset.zero;

  Ticker? _ticker;
  Duration _lastTick = Duration.zero;

  late final _StarField _field = _StarField.generate(seed: 20260814);

  @override
  void initState() {
    super.initState();
    // Immersive rather than merely edge-to-edge: the system bars are the one
    // thing that would prove this is still an app.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    AppTheme.restoreSystemChrome();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 0.016
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0) return;

    // Inertia: exponential decay, never linear — a linear stop reads as
    // mechanical the instant you see it.
    if (_velocity.distance > 1) {
      _camera += _velocity * dt;
      _velocity *= math.pow(0.06, dt).toDouble();
    } else if (_velocity != Offset.zero) {
      _velocity = Offset.zero;
    }

    // The sky is never still, even untouched — so there is always something
    // to repaint.
    _camera += const Offset(_ambientDriftPerSecond, 0) * dt;

    if (mounted) setState(() {});
  }

  void _onDragUpdate(DragUpdateDetails d) {
    // Finger-to-sky ratio below 1: the sky moves less than the finger, and
    // that shortfall is what gives it mass.
    setState(() {
      _camera -= d.delta * _dragRatio;
      _velocity = Offset.zero;
    });
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond * _dragRatio;
    setState(() => _velocity = -v);
  }

  Future<void> _finish() async {
    if (!widget.preview) await SurprisePrefs.markPlayed();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    // Leaving is deliberately allowed, in both modes: trapping her inside
    // would be a worse failure than an early exit. Back pops the route, and
    // `dispose` puts the system chrome back either way.
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: _onDragUpdate,
        onPanEnd: _onDragEnd,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _SkyPainter(field: _field, camera: _camera),
              isComplex: true,
              willChange: true,
            ),
            if (widget.preview) _previewControls(),
          ],
        ),
      ),
    );
  }

  /// Rehearsal chrome. Only ever built when [SurpriseExperience.preview] is
  /// true, so there is no code path that can put it in front of her.
  Widget _previewControls() {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                onPressed: _finish,
              ),
              for (final p in SurprisePhase.values)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: TextButton(
                    onPressed: () => setState(() => _phase = p),
                    child: Text(
                      p.name,
                      style: TextStyle(
                        color: _phase == p ? Colors.white : Colors.white38,
                        fontSize: 12,
                      ),
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

// The feel, in one place so it can be tuned without hunting.
const double _dragRatio = 0.6;
const double _ambientDriftPerSecond = 0.3;

/// Parallax depth. The last layer moves *faster* than the finger, which is
/// what sells "in front of the glass" rather than "behind it".
const List<double> _layerFactors = [0.15, 0.35, 0.6, 1.1];
const List<int> _layerCounts = [90, 70, 55, 18];
const List<double> _layerRadius = [0.6, 0.9, 1.4, 2.2];

class _Star {
  const _Star(this.position, this.radius, this.phase, this.period);
  final Offset position;
  final double radius;
  final double phase;
  final double period;
}

/// A deterministic sky. Generated from a fixed seed so the same stars sit in
/// the same places on both phones and across restarts.
class _StarField {
  const _StarField(this.layers);
  final List<List<_Star>> layers;

  static _StarField generate({required int seed}) {
    final rng = math.Random(seed);
    return _StarField([
      for (var l = 0; l < _layerFactors.length; l++)
        [
          for (var i = 0; i < _layerCounts[l]; i++)
            _Star(
              Offset(
                rng.nextDouble() * 2400 - 400,
                rng.nextDouble() * 2000 - 400,
              ),
              _layerRadius[l] * (0.6 + rng.nextDouble() * 0.8),
              // Desynchronised on purpose: stars twinkling in step read as a
              // loading spinner, not as a sky.
              rng.nextDouble() * math.pi * 2,
              1.5 + rng.nextDouble() * 2.5,
            ),
        ],
    ]);
  }
}

class _SkyPainter extends CustomPainter {
  _SkyPainter({required this.field, required this.camera});

  final _StarField field;
  final Offset camera;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    for (var l = 0; l < field.layers.length; l++) {
      final factor = _layerFactors[l];
      for (final star in field.layers[l]) {
        final p = star.position - camera * factor;
        // Wrap so the sky is endless in every direction.
        final x = (p.dx % (size.width + 400)) - 200;
        final y = (p.dy % (size.height + 400)) - 200;
        canvas.drawCircle(Offset(x, y), star.radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SkyPainter old) => old.camera != camera;
}
