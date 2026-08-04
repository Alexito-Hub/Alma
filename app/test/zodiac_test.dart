import 'package:alma/core/astronomy/constellation.dart';
import 'package:alma/core/astronomy/zodiac.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String on(int month, int day) =>
      Zodiac.forDate(DateTime(2026, month, day)).name;

  group('her date', () {
    test('14 August is Leo', () {
      expect(on(8, 14), 'Leo');
    });

    // The window either side of her birthday, asked for explicitly. All of it
    // has to land in the same constellation or the premise breaks.
    test('the four days either side are Leo too', () {
      for (var day = 10; day <= 18; day++) {
        expect(on(8, day), 'Leo', reason: '14 - 4 .. 14 + 4 → día $day');
      }
    });
  });

  group('boundaries are strict', () {
    // The whole point of using real boundaries: one day earlier is a
    // different constellation, with no rounding and no grace period.
    test('Leo opens on 10 August, and 9 August is still Cancer', () {
      expect(on(8, 10), 'Leo');
      expect(on(8, 9), 'Cancer');
    });

    test('Leo closes when Virgo opens on 16 September', () {
      expect(on(9, 15), 'Leo');
      expect(on(9, 16), 'Virgo');
    });

    test('every band starts exactly on its own first day', () {
      for (final b in Zodiac.bands) {
        expect(
          on(b.startMonth, b.startDay),
          b.name,
          reason: '${b.name} debería empezar el ${b.startDay}/${b.startMonth}',
        );
      }
    });
  });

  group('the mapping is airtight', () {
    // A calendar with a hole in it would fail on exactly one birthday, and
    // there would be no way to know which until it happened.
    test('all 366 days resolve to a band', () {
      for (var m = 1; m <= 12; m++) {
        final days = DateTime(2024, m + 1, 0).day; // 2024 is a leap year
        for (var d = 1; d <= days; d++) {
          expect(
            Zodiac.forDate(DateTime(2024, m, d)).name,
            isNotEmpty,
            reason: '$d/$m quedó sin constelación',
          );
        }
      }
    });

    test('the year wraps: early January belongs to December\'s band', () {
      expect(on(1, 1), 'Sagittarius');
      expect(on(1, 19), 'Sagittarius');
      expect(on(1, 20), 'Capricornus');
      expect(on(12, 31), 'Sagittarius');
    });

    test('bands are listed in calendar order', () {
      var previous = 0;
      for (final b in Zodiac.bands) {
        final key = b.startMonth * 100 + b.startDay;
        expect(
          key,
          greaterThan(previous),
          reason: '${b.name} está fuera de orden',
        );
        previous = key;
      }
    });

    // Astronomy, not astrology: the Sun really does cross Ophiuchus.
    test('Ophiuchus is included', () {
      expect(Zodiac.bands.map((b) => b.name), contains('Ophiuchus'));
      expect(on(12, 1), 'Ophiuchus');
      expect(Zodiac.bands.length, 13);
    });

    // Real constellations are wildly unequal; equal slices would mean the
    // tropical zodiac had crept back in.
    test('the bands are not equal-length slices', () {
      final lengths = <int>[];
      for (var i = 0; i < Zodiac.bands.length; i++) {
        final a = Zodiac.bands[i];
        final b = Zodiac.bands[(i + 1) % Zodiac.bands.length];
        final start = DateTime(2025, a.startMonth, a.startDay);
        var end = DateTime(2025, b.startMonth, b.startDay);
        if (!end.isAfter(start)) end = DateTime(2026, b.startMonth, b.startDay);
        lengths.add(end.difference(start).inDays);
      }
      expect(lengths.reduce((a, b) => a < b ? a : b), lessThan(10)); // Scorpius
      expect(lengths.reduce((a, b) => a > b ? a : b), greaterThan(35)); // Virgo
    });
  });

  group('Leo, from catalogue', () {
    test('Regulus is the brightest', () {
      expect(leo.brightest.name, 'Régulo');
      expect(leo.brightest.magnitude, lessThan(2));
    });

    test('every line joins two stars that exist', () {
      final ids = leo.stars.map((s) => s.id).toSet();
      for (final (a, b) in leo.lines) {
        expect(ids, contains(a));
        expect(ids, contains(b));
        expect(a, isNot(b));
      }
    });

    test(
      'the Sickle is a real chain of catalogued stars ending at Regulus',
      () {
        final ids = leo.stars.map((s) => s.id).toSet();
        expect(leo.asterism.every(ids.contains), isTrue);
        expect(leo.asterism.last, 'alp');
      },
    );

    test('no star is listed twice', () {
      final ids = leo.stars.map((s) => s.id).toList();
      expect(ids.length, ids.toSet().length);
    });

    test('positions normalise into a unit box without losing shape', () {
      final p = leo.normalisedPositions();
      expect(p.length, leo.stars.length);
      for (final v in p.values) {
        expect(v.x, inInclusiveRange(0, 1));
        expect(v.y, inInclusiveRange(0, 1));
      }
      // Leo is a wide, shallow constellation: it spans about 25 degrees of sky
      // east to west and roughly half that north to south, so once the aspect
      // ratio is honoured it must not fill the box vertically.
      final ys = p.values.map((v) => v.y);
      expect(ys.reduce((a, b) => a > b ? a : b), lessThan(0.95));
    });

    test('Regulus sits south and east of the mane', () {
      final p = leo.normalisedPositions();
      // Declination: Regulus at +12 is well below Ras Elased at +24.
      expect(p['alp']!.y, greaterThan(p['eps']!.y));
    });
  });
}
