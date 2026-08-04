/// A constellation the Sun actually crosses, with the dates it does it.
class ZodiacBand {
  const ZodiacBand({
    required this.name,
    required this.startMonth,
    required this.startDay,
  });

  /// Latin name, as it is catalogued.
  final String name;

  /// First day the Sun is inside this constellation. The band runs from here
  /// until the next band's start, exclusive.
  final int startMonth;
  final int startDay;
}

/// Where the Sun really is on a given date.
///
/// These are the **astronomical** boundaries — the ones the IAU fixed when it
/// carved the sky into 88 constellations — not the tropical zodiac of
/// horoscopes. The two disagree by about three weeks, and they disagree in
/// shape too: real constellations are not twelve equal thirty-day slices. The
/// Sun spends thirty-eight days crossing Virgo and six crossing Scorpius.
///
/// Which is why **Ophiuchus is here**. The Sun passes through it every year
/// between Scorpius and Sagittarius; leaving it out would make the mapping
/// astrology rather than astronomy.
///
/// Boundaries are treated strictly: a date one day either side of a boundary
/// gives a different constellation, with no rounding and no fuzzy margin.
class Zodiac {
  Zodiac._();

  /// Ordered by start date through the year.
  static const List<ZodiacBand> bands = [
    ZodiacBand(name: 'Capricornus', startMonth: 1, startDay: 20),
    ZodiacBand(name: 'Aquarius', startMonth: 2, startDay: 16),
    ZodiacBand(name: 'Pisces', startMonth: 3, startDay: 11),
    ZodiacBand(name: 'Aries', startMonth: 4, startDay: 18),
    ZodiacBand(name: 'Taurus', startMonth: 5, startDay: 13),
    ZodiacBand(name: 'Gemini', startMonth: 6, startDay: 21),
    ZodiacBand(name: 'Cancer', startMonth: 7, startDay: 20),
    ZodiacBand(name: 'Leo', startMonth: 8, startDay: 10),
    ZodiacBand(name: 'Virgo', startMonth: 9, startDay: 16),
    ZodiacBand(name: 'Libra', startMonth: 10, startDay: 30),
    ZodiacBand(name: 'Scorpius', startMonth: 11, startDay: 23),
    ZodiacBand(name: 'Ophiuchus', startMonth: 11, startDay: 29),
    ZodiacBand(name: 'Sagittarius', startMonth: 12, startDay: 17),
  ];

  /// The constellation the Sun is crossing on [date].
  ///
  /// Only month and day are read — the boundaries barely shift from year to
  /// year, and a birthday is a month and a day.
  static ZodiacBand forDate(DateTime date) {
    final key = _key(date.month, date.day);

    // Walk backwards to the last band that has already started. Anything
    // before the first start (1 January to 19 January) belongs to the band
    // that opened in December and runs across the new year.
    for (var i = bands.length - 1; i >= 0; i--) {
      final b = bands[i];
      if (key >= _key(b.startMonth, b.startDay)) return b;
    }
    return bands.last;
  }

  static int _key(int month, int day) => month * 100 + day;
}
