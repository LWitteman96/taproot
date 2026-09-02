import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/core/utils/local_dates.dart';

void main() {
  group('LocalDate', () {
    test('takes the local calendar date of an instant', () {
      final local = DateTime(2026, 3, 14, 23, 30);

      expect(LocalDate.from(local), const LocalDate(2026, 3, 14));
    });

    test('a UTC instant resolves to the same date as its local form', () {
      // The whole point of the file: windows are local-calendar quantities, so
      // a stored UTC timestamp must be converted before the date is read off.
      final instant = DateTime(2026, 3, 14, 23, 30).toUtc();

      expect(LocalDate.from(instant), LocalDate.from(instant.toLocal()));
      expect(LocalDate.from(instant), const LocalDate(2026, 3, 14));
    });

    test('addDays rolls over month and year boundaries', () {
      expect(
        const LocalDate(2026, 1, 30).addDays(3),
        const LocalDate(2026, 2, 2),
      );
      expect(
        const LocalDate(2025, 12, 31).addDays(1),
        const LocalDate(2026, 1, 1),
      );
      expect(
        const LocalDate(2026, 3, 1).addDays(-1),
        const LocalDate(2026, 2, 28),
      );
    });

    test('addDays handles a leap day', () {
      expect(
        const LocalDate(2028, 2, 28).addDays(1),
        const LocalDate(2028, 2, 29),
      );
      expect(
        const LocalDate(2028, 2, 29).addDays(1),
        const LocalDate(2028, 3, 1),
      );
    });

    test('equality is by value, so dates work as map and set keys', () {
      final dates = <LocalDate>{
        const LocalDate(2026, 1, 5),
        LocalDate.from(DateTime(2026, 1, 5, 23, 59)),
      };

      expect(dates, hasLength(1));
      expect(dates.contains(const LocalDate(2026, 1, 5)), isTrue);
    });

    test('orders chronologically', () {
      final dates = <LocalDate>[
        const LocalDate(2026, 2, 1),
        const LocalDate(2025, 12, 31),
        const LocalDate(2026, 1, 15),
      ]..sort();

      expect(dates, <LocalDate>[
        const LocalDate(2025, 12, 31),
        const LocalDate(2026, 1, 15),
        const LocalDate(2026, 2, 1),
      ]);
      expect(
        const LocalDate(2026, 1, 15).isBefore(const LocalDate(2026, 2, 1)),
        isTrue,
      );
      expect(
        const LocalDate(2026, 2, 1).isAfter(const LocalDate(2026, 1, 15)),
        isTrue,
      );
    });

    test('startOfDay is local midnight', () {
      expect(const LocalDate(2026, 1, 5).startOfDay, DateTime(2026, 1, 5));
    });

    test('renders as an ISO date', () {
      expect(const LocalDate(2026, 1, 5).toString(), '2026-01-05');
    });
  });

  group('daysBetween', () {
    test('counts whole calendar days', () {
      expect(
        daysBetween(const LocalDate(2026, 1, 1), const LocalDate(2026, 1, 8)),
        7,
      );
    });

    test('crosses month and year boundaries', () {
      expect(
        daysBetween(const LocalDate(2025, 12, 31), const LocalDate(2026, 1, 1)),
        1,
      );
      expect(
        daysBetween(const LocalDate(2028, 2, 27), const LocalDate(2028, 3, 1)),
        3,
      );
    });

    test('is negative when the range runs backwards', () {
      expect(
        daysBetween(const LocalDate(2026, 1, 8), const LocalDate(2026, 1, 1)),
        -7,
      );
    });

    test('is zero for the same date', () {
      expect(
        daysBetween(const LocalDate(2026, 1, 8), const LocalDate(2026, 1, 8)),
        0,
      );
    });
  });

  group('elapsedLocalDays', () {
    test('measures fractional days on the wall clock', () {
      expect(
        elapsedLocalDays(DateTime(2026, 1, 1, 6), DateTime(2026, 1, 1, 18)),
        closeTo(0.5, 1e-9),
      );
      expect(
        elapsedLocalDays(DateTime(2026, 1, 1, 8), DateTime(2026, 1, 4, 8)),
        closeTo(3.0, 1e-9),
      );
      expect(
        elapsedLocalDays(DateTime(2026, 1, 1, 8), DateTime(2026, 1, 3, 20)),
        closeTo(2.5, 1e-9),
      );
    });

    test('is negative when the range runs backwards', () {
      expect(
        elapsedLocalDays(DateTime(2026, 1, 4, 8), DateTime(2026, 1, 1, 8)),
        closeTo(-3.0, 1e-9),
      );
    });

    test('converts UTC instants before measuring', () {
      final from = DateTime(2026, 1, 1, 8).toUtc();
      final to = DateTime(2026, 1, 4, 8).toUtc();

      expect(elapsedLocalDays(from, to), closeTo(3.0, 1e-9));
    });

    test('a day is a wall-clock day, not a 24-hour block', () {
      // Same local time-of-day on two dates is exactly N days apart, whatever
      // the offset did in between. This is what stops vitality drooping an
      // hour early after a DST transition.
      final from = DateTime(2026, 3, 27, 9);
      final to = DateTime(2026, 3, 30, 9);

      expect(elapsedLocalDays(from, to), closeTo(3.0, 1e-9));
    });
  });

  group('localDatesInRange', () {
    test('is inclusive at both ends', () {
      final dates = localDatesInRange(
        const LocalDate(2026, 1, 30),
        const LocalDate(2026, 2, 2),
      );

      expect(dates, <LocalDate>[
        const LocalDate(2026, 1, 30),
        const LocalDate(2026, 1, 31),
        const LocalDate(2026, 2, 1),
        const LocalDate(2026, 2, 2),
      ]);
    });

    test('is a single date when both ends match', () {
      expect(
        localDatesInRange(
          const LocalDate(2026, 1, 5),
          const LocalDate(2026, 1, 5),
        ),
        <LocalDate>[const LocalDate(2026, 1, 5)],
      );
    });

    test('is empty when the range runs backwards', () {
      expect(
        localDatesInRange(
          const LocalDate(2026, 1, 8),
          const LocalDate(2026, 1, 5),
        ),
        isEmpty,
      );
    });
  });
}
