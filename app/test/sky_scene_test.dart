import 'dart:ui';

import 'package:alma/core/astronomy/constellation.dart';
import 'package:alma/presentation/screens/surprise/sky_scene.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const viewport = Size(390, 844); // a phone
  final scene = SkyScene(viewport: viewport);

  group('the sky is bounded', () {
    // An endless panorama is how she gets lost. This has edges.
    test('the scene is a few screens, not infinite', () {
      expect(scene.sceneSize.width, viewport.width * 2.5);
      expect(scene.sceneSize.height, viewport.height * 2.0);
    });

    test('the camera cannot leave the sky', () {
      expect(scene.clampCamera(const Offset(-500, -500)), Offset.zero);
      expect(scene.clampCamera(const Offset(99999, 99999)), scene.maxCamera);
      expect(scene.maxCamera.dx, greaterThan(0));
      expect(scene.maxCamera.dy, greaterThan(0));
    });

    test('every corner of the sky is reachable', () {
      for (final c in [
        Offset.zero,
        Offset(scene.maxCamera.dx, 0),
        Offset(0, scene.maxCamera.dy),
        scene.maxCamera,
      ]) {
        expect(scene.clampCamera(c), c);
      }
    });
  });

  group('finding it', () {
    test(
      'the constellation is inside the sky, off-centre, not in a corner',
      () {
        final t = scene.targetCenter;
        expect(t.dx, greaterThan(scene.sceneSize.width * 0.1));
        expect(t.dx, lessThan(scene.sceneSize.width * 0.9));
        expect(t.dy, greaterThan(scene.sceneSize.height * 0.1));
        expect(t.dy, lessThan(scene.sceneSize.height * 0.9));
      },
    );

    test('it can actually be centred — the lock-on target is reachable', () {
      final centred = scene.cameraCentredOnTarget();
      expect(scene.clampCamera(centred), centred);
      expect(scene.isLockedOn(centred), isTrue);
      expect(scene.proximity(centred), closeTo(1, 0.001));
    });

    test('proximity rises as the camera approaches', () {
      const far = Offset.zero;
      final near = scene.cameraCentredOnTarget();
      final mid = Offset.lerp(far, near, 0.5)!;
      expect(scene.proximity(far), lessThan(scene.proximity(mid)));
      expect(scene.proximity(mid), lessThan(scene.proximity(near)));
    });

    test('proximity stays inside 0..1 anywhere in the sky', () {
      for (var x = 0.0; x <= scene.maxCamera.dx; x += scene.maxCamera.dx / 8) {
        for (
          var y = 0.0;
          y <= scene.maxCamera.dy;
          y += scene.maxCamera.dy / 8
        ) {
          final p = scene.proximity(Offset(x, y));
          expect(p, inInclusiveRange(0, 1));
        }
      }
    });

    // Asking for precision in a gift would be cruel.
    test('the catch is generous — roughly centred is enough', () {
      final centred = scene.cameraCentredOnTarget();
      final offBy = viewport.shortestSide / 4;
      expect(scene.isLockedOn(centred + Offset(offBy, 0)), isTrue);
      expect(scene.isLockedOn(centred + Offset(0, offBy)), isTrue);
    });

    test('but not so generous that it fires from across the sky', () {
      expect(scene.isLockedOn(Offset.zero), isFalse);
      expect(scene.isLockedOn(scene.maxCamera), isFalse);
    });

    test('the edge cue points the right way', () {
      final centred = scene.cameraCentredOnTarget();
      // Camera left of the target: the cue points right.
      final fromLeft = scene.directionToTarget(centred - const Offset(400, 0))!;
      expect(fromLeft.dx, greaterThan(0.5));
      // Camera below the target: it points up.
      final fromBelow = scene.directionToTarget(
        centred + const Offset(0, 400),
      )!;
      expect(fromBelow.dy, lessThan(-0.5));
    });

    test('the cue gives up rather than jitter once centred', () {
      expect(scene.directionToTarget(scene.cameraCentredOnTarget()), isNull);
    });
  });

  group('the constellation on screen', () {
    test('every catalogued star gets a position', () {
      final pos = scene.targetStarsOnScreen(scene.cameraCentredOnTarget());
      expect(pos.length, leo.stars.length);
      for (final s in leo.stars) {
        expect(pos.containsKey(s.id), isTrue);
      }
    });

    test('it fits on screen when centred', () {
      final pos = scene.targetStarsOnScreen(scene.cameraCentredOnTarget());
      for (final p in pos.values) {
        expect(p.dx, inInclusiveRange(0, viewport.width));
        expect(p.dy, inInclusiveRange(0, viewport.height));
      }
    });

    test('it moves exactly with the camera — it sits on the true plane', () {
      final a = scene.targetStarsOnScreen(Offset.zero);
      final b = scene.targetStarsOnScreen(const Offset(100, 60));
      expect(a['alp']!.dx - b['alp']!.dx, closeTo(100, 0.001));
      expect(a['alp']!.dy - b['alp']!.dy, closeTo(60, 0.001));
    });

    // Magnitude runs backwards; getting this inverted would make the faintest
    // stars the biggest and destroy the shape.
    test('brighter stars are drawn bigger', () {
      final regulus = SkyScene.radiusForMagnitude(1.40);
      final rasalas = SkyScene.radiusForMagnitude(3.88);
      expect(regulus, greaterThan(rasalas));
      expect(SkyScene.radiusForMagnitude(0), greaterThan(regulus));
    });

    test('even the faintest star stays visible', () {
      expect(SkyScene.radiusForMagnitude(6.5), greaterThan(1));
    });
  });

  group('the background field', () {
    test('is deterministic — the same sky on both phones', () {
      final a = scene.backgroundField();
      final b = scene.backgroundField();
      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].position, b[i].position);
      }
    });

    test('stays inside the scene', () {
      for (final s in scene.backgroundField()) {
        expect(s.position.dx, inInclusiveRange(0, scene.sceneSize.width));
        expect(s.position.dy, inInclusiveRange(0, scene.sceneSize.height));
      }
    });

    // The constellation has to win on brightness the way it does in the real
    // sky, so no piece of noise may outshine a catalogued star.
    test('no background star is bigger than the faintest real one', () {
      final faintest = SkyScene.radiusForMagnitude(
        leo.stars.map((s) => s.magnitude).reduce((a, b) => a > b ? a : b),
      );
      for (final s in scene.backgroundField()) {
        expect(s.radius, lessThan(faintest));
      }
    });

    test('is parallaxed behind the constellation', () {
      for (final s in scene.backgroundField()) {
        expect(s.depth, lessThan(1.0));
      }
    });
  });
}
