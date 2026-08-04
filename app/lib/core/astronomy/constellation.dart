import 'dart:math' as math;

/// One catalogued star.
class CatalogStar {
  const CatalogStar({
    required this.id,
    required this.name,
    required this.rightAscensionHours,
    required this.declinationDegrees,
    required this.magnitude,
  });

  /// Bayer designation, used to wire the figure's lines.
  final String id;

  /// Proper name where it has one; empty when it only goes by its letter.
  final String name;

  /// Right ascension in hours (0–24), J2000.
  final double rightAscensionHours;

  /// Declination in degrees, J2000. Positive north.
  final double declinationDegrees;

  /// Apparent visual magnitude. **Lower is brighter** — Regulus at 1.40
  /// outshines Denebola at 2.14 — so anything sizing a dot from this has to
  /// invert it.
  final double magnitude;
}

/// A constellation as it is actually catalogued: real positions, real
/// brightnesses, and the line figure normally drawn between them.
class Constellation {
  const Constellation({
    required this.name,
    required this.stars,
    required this.lines,
    required this.asterismName,
    required this.asterism,
  });

  final String name;
  final List<CatalogStar> stars;

  /// Pairs of [CatalogStar.id] joined by a line in the stick figure.
  final List<(String, String)> lines;

  /// The sub-shape people actually recognise, and its name.
  final String asterismName;
  final List<String> asterism;

  CatalogStar byId(String id) => stars.firstWhere((s) => s.id == id);

  /// The brightest star, by magnitude. The natural place to aim a lock-on.
  CatalogStar get brightest =>
      stars.reduce((a, b) => a.magnitude <= b.magnitude ? a : b);

  /// Positions mapped into a unit box, y already flipped for screen space
  /// (north up). Keeps the true aspect ratio: right ascension is an angle
  /// that narrows with declination, so hours are scaled by cos(dec) before
  /// being compared with degrees. Skipping that correction is what turns a
  /// real constellation into a stretched approximation of one.
  Map<String, ({double x, double y})> normalisedPositions() {
    final meanDecRad =
        stars.map((s) => s.declinationDegrees).reduce((a, b) => a + b) /
        stars.length *
        math.pi /
        180;
    final cosDec = math.cos(meanDecRad);

    // 1 hour of RA is 15 degrees of arc, shrunk by cos(declination).
    final points = {
      for (final s in stars)
        s.id: (
          // Right ascension increases eastwards, which is leftwards on a sky
          // chart, hence the negation.
          x: -s.rightAscensionHours * 15 * cosDec,
          y: -s.declinationDegrees,
        ),
    };

    final xs = points.values.map((p) => p.x);
    final ys = points.values.map((p) => p.y);
    final minX = xs.reduce(math.min);
    final maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min);
    final maxY = ys.reduce(math.max);
    // One divisor for both axes, so the shape keeps its proportions instead
    // of being stretched to fill a square.
    final span = math.max(maxX - minX, maxY - minY);

    return {
      for (final e in points.entries)
        e.key: (x: (e.value.x - minX) / span, y: (e.value.y - minY) / span),
    };
  }
}

/// Leo, from catalogue (J2000).
///
/// Chosen by date, not by decoration: on 14 August the Sun is inside Leo
/// under both the astronomical and the tropical boundaries, so there is no
/// edge case to argue about.
///
/// The Sickle is what makes it findable — the reversed question mark hanging
/// off Regulus is the one shape in this part of the sky a person can be told
/// to look for and actually recognise.
const Constellation leo = Constellation(
  name: 'Leo',
  asterismName: 'La Hoz',
  asterism: ['eps', 'mu', 'zet', 'gam', 'eta', 'alp'],
  stars: [
    CatalogStar(
      id: 'alp',
      name: 'Régulo',
      rightAscensionHours: 10.1395,
      declinationDegrees: 11.9672,
      magnitude: 1.40,
    ),
    CatalogStar(
      id: 'bet',
      name: 'Denébola',
      rightAscensionHours: 11.8177,
      declinationDegrees: 14.5720,
      magnitude: 2.14,
    ),
    CatalogStar(
      id: 'gam',
      name: 'Algieba',
      rightAscensionHours: 10.3328,
      declinationDegrees: 19.8415,
      magnitude: 2.08,
    ),
    CatalogStar(
      id: 'del',
      name: 'Zosma',
      rightAscensionHours: 11.2351,
      declinationDegrees: 20.5237,
      magnitude: 2.56,
    ),
    CatalogStar(
      id: 'eps',
      name: 'Ras Elased',
      rightAscensionHours: 9.7642,
      declinationDegrees: 23.7743,
      magnitude: 2.98,
    ),
    CatalogStar(
      id: 'zet',
      name: 'Adhafera',
      rightAscensionHours: 10.2782,
      declinationDegrees: 23.4173,
      magnitude: 3.44,
    ),
    CatalogStar(
      id: 'the',
      name: 'Chertan',
      rightAscensionHours: 11.2372,
      declinationDegrees: 15.4297,
      magnitude: 3.32,
    ),
    CatalogStar(
      id: 'eta',
      name: '',
      rightAscensionHours: 10.1222,
      declinationDegrees: 16.7627,
      magnitude: 3.48,
    ),
    CatalogStar(
      id: 'mu',
      name: 'Rasalas',
      rightAscensionHours: 9.8794,
      declinationDegrees: 26.0068,
      magnitude: 3.88,
    ),
  ],
  lines: [
    // The Sickle, from the mane down to Regulus.
    ('eps', 'mu'),
    ('mu', 'zet'),
    ('zet', 'gam'),
    ('gam', 'eta'),
    ('eta', 'alp'),
    // Body and hindquarters.
    ('alp', 'the'),
    ('the', 'bet'),
    ('bet', 'del'),
    ('del', 'the'),
    ('del', 'gam'),
  ],
);
