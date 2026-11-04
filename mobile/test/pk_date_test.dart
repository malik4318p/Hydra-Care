import 'package:flutter_test/flutter_test.dart';

import 'package:purify_mobile/core/utils/pk_date.dart';

void main() {
  group('PakistanDate.utcBoundsFor', () {
    test('converts a Pakistan local day to its UTC half-open interval', () {
      final (startUtc, endUtc) =
          PakistanDate.utcBoundsFor(DateTime.utc(2026, 11, 4));

      // Pakistan midnight (00:00 PKT, UTC+05:00) on 2026-11-04 is
      // 2026-11-03T19:00:00Z, and the interval is exactly 24 hours.
      expect(startUtc, DateTime.utc(2026, 11, 3, 19, 0, 0));
      expect(endUtc, DateTime.utc(2026, 11, 4, 19, 0, 0));
      expect(endUtc.difference(startUtc), const Duration(days: 1));
    });

    test('ignores any time-of-day on the input, only year/month/day matter',
        () {
      final fromMidnight = PakistanDate.utcBoundsFor(DateTime.utc(2026, 1, 1));
      final fromNoon =
          PakistanDate.utcBoundsFor(DateTime.utc(2026, 1, 1, 12, 30));
      expect(fromMidnight, fromNoon);
    });

    test('a timestamp just before Pakistan midnight falls in the prior day',
        () {
      final (startUtc, endUtc) =
          PakistanDate.utcBoundsFor(DateTime.utc(2026, 11, 4));
      final justBefore = startUtc.subtract(const Duration(seconds: 1));
      final justAfter = startUtc;

      expect(justBefore.isBefore(startUtc), isTrue);
      expect(justAfter.isBefore(endUtc), isTrue);
      expect(justAfter.isAtSameMomentAs(startUtc), isTrue);
    });
  });

  group('PakistanDate.todayLocal', () {
    test('matches a manual UTC+5 conversion of the current instant', () {
      final nowUtc = DateTime.now().toUtc();
      final expectedPakistanNow = nowUtc.add(const Duration(hours: 5));
      final expected = DateTime.utc(
        expectedPakistanNow.year,
        expectedPakistanNow.month,
        expectedPakistanNow.day,
      );

      expect(PakistanDate.todayLocal(), expected);
    });
  });
}
