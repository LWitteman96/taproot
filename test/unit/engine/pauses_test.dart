import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/core/engine/pauses.dart';
import 'package:taproot/core/models/pause_interval.dart';
import 'package:taproot/core/utils/local_dates.dart';

import '../../utils/engine_builders.dart';

void main() {
  setUp(resetFixtureIds);

  group('isPausedOn', () {
    test('covers the whole local date at both ends of the interval', () {
      final pauses = <PauseInterval>[pauseFrom(3, endDay: 6)];

      expect(isPausedOn(LocalDate.from(day(2)), pauses), isFalse);
      expect(isPausedOn(LocalDate.from(day(3)), pauses), isTrue);
      expect(isPausedOn(LocalDate.from(day(5)), pauses), isTrue);
      expect(isPausedOn(LocalDate.from(day(6)), pauses), isTrue);
      expect(isPausedOn(LocalDate.from(day(7)), pauses), isFalse);
    });

    test('an open pause covers every later date', () {
      final pauses = <PauseInterval>[pauseFrom(3)];

      expect(isPausedOn(LocalDate.from(day(2)), pauses), isFalse);
      expect(isPausedOn(LocalDate.from(day(300)), pauses), isTrue);
    });

    test('is false with no pauses', () {
      expect(
        isPausedOn(LocalDate.from(day(3)), const <PauseInterval>[]),
        isFalse,
      );
    });

    test('handles overlapping intervals', () {
      final pauses = <PauseInterval>[
        pauseFrom(3, endDay: 6),
        pauseFrom(5, endDay: 9),
      ];

      expect(isPausedOn(LocalDate.from(day(7)), pauses), isTrue);
      expect(isPausedOn(LocalDate.from(day(10)), pauses), isFalse);
    });
  });

  group('pausedDaysBetween', () {
    test('counts paused dates, excluding the opening day', () {
      // The opening day is the day an event happened on and is only partly
      // elapsed, so it never counts.
      final pauses = <PauseInterval>[pauseFrom(3, endDay: 5)];

      expect(
        pausedDaysBetween(
          after: LocalDate.from(day(0)),
          through: LocalDate.from(day(10)),
          pauses: pauses,
        ),
        3,
      );
    });

    test('does not count the opening day even when it is paused', () {
      final pauses = <PauseInterval>[pauseFrom(0, endDay: 2)];

      expect(
        pausedDaysBetween(
          after: LocalDate.from(day(0)),
          through: LocalDate.from(day(4)),
          pauses: pauses,
        ),
        2,
      );
    });

    test('counts a paused date once when intervals overlap', () {
      final pauses = <PauseInterval>[
        pauseFrom(3, endDay: 6),
        pauseFrom(5, endDay: 8),
      ];

      expect(
        pausedDaysBetween(
          after: LocalDate.from(day(0)),
          through: LocalDate.from(day(10)),
          pauses: pauses,
        ),
        6,
      );
    });

    test('is zero for an empty range', () {
      expect(
        pausedDaysBetween(
          after: LocalDate.from(day(5)),
          through: LocalDate.from(day(5)),
          pauses: <PauseInterval>[pauseFrom(0, endDay: 10)],
        ),
        0,
      );
    });
  });

  group('activeElapsedDays', () {
    test('equals wall-clock elapsed days when nothing is paused', () {
      expect(
        activeElapsedDays(
          from: day(0),
          to: day(6),
          pauses: const <PauseInterval>[],
        ),
        closeTo(6, 1e-9),
      );
    });

    test('removes whole paused days from the middle of the range', () {
      expect(
        activeElapsedDays(
          from: day(0),
          to: day(6),
          pauses: <PauseInterval>[pauseFrom(2, endDay: 4)],
        ),
        closeTo(3, 1e-9),
      );
    });

    test('keeps the fractional part of the day', () {
      expect(
        activeElapsedDays(
          from: day(0),
          to: day(6.5),
          pauses: <PauseInterval>[pauseFrom(2, endDay: 4)],
        ),
        closeTo(3.5, 1e-9),
      );
    });

    test('an open pause freezes the clock entirely', () {
      // Vitality freezes while paused (growth spec §7). A pause owns whole
      // local dates, so the clock stops at midnight opening the start date —
      // here 0.625 of a day after the 09:00 starting instant — and never
      // moves again.
      final frozen = activeElapsedDays(
        from: day(0),
        to: day(30),
        pauses: <PauseInterval>[pauseFrom(1)],
      );

      expect(frozen, closeTo(0.625, 1e-9));
    });

    test('does not move at all while the pause is running', () {
      // Regression: subtracting whole calendar days from a fractional elapsed
      // made this climb through each paused day and snap back a full day at
      // local midnight, so a paused plant drooped through the afternoon and
      // sprang back overnight.
      final pauses = <PauseInterval>[pauseFrom(3)];
      final atPauseStart = activeElapsedDays(
        from: day(0),
        to: day(3),
        pauses: pauses,
      );

      for (final t in <num>[3.2, 3.6, 3.99, 4.2, 4.6, 9.9, 40]) {
        expect(
          activeElapsedDays(from: day(0), to: day(t), pauses: pauses),
          closeTo(atPauseStart, 1e-9),
          reason: 'day $t',
        );
      }
    });

    test('resumes where it stopped once the pause ends', () {
      final active = activeElapsedDays(
        from: day(0),
        to: day(8.5),
        pauses: <PauseInterval>[pauseFrom(3, endDay: 5)],
      );

      // Days 3, 4 and 5 are owned by the pause; everything else elapsed.
      expect(active, closeTo(5.5, 1e-9));
    });

    test('never goes negative for a fully paused range', () {
      expect(
        activeElapsedDays(
          from: day(0),
          to: day(5),
          pauses: <PauseInterval>[pauseFrom(0, endDay: 10)],
        ),
        closeTo(0, 1e-9),
      );
    });
  });

  group('activeWindowDates', () {
    test('returns the last N local dates, oldest first, ending today', () {
      final dates = activeWindowDates(
        at: day(20),
        windowDays: 14,
        pauses: const <PauseInterval>[],
      );

      expect(dates, hasLength(14));
      expect(dates.first, LocalDate.from(day(7)));
      expect(dates.last, LocalDate.from(day(20)));
    });

    test('stretches backwards over paused days rather than shortening', () {
      // A pause costs the user nothing: the window still holds 14 active days,
      // it just reaches further back in wall-clock time.
      final dates = activeWindowDates(
        at: day(20),
        windowDays: 14,
        pauses: <PauseInterval>[pauseFrom(10, endDay: 13)],
      );

      expect(dates, hasLength(14));
      expect(dates.first, LocalDate.from(day(3)));
      expect(dates.contains(LocalDate.from(day(11))), isFalse);
    });

    test('excludes a paused evaluation day', () {
      final dates = activeWindowDates(
        at: day(20),
        windowDays: 3,
        pauses: <PauseInterval>[pauseFrom(19, endDay: 20)],
      );

      expect(dates, <LocalDate>[
        LocalDate.from(day(16)),
        LocalDate.from(day(17)),
        LocalDate.from(day(18)),
      ]);
    });
  });

  group('activeDaysBefore', () {
    test('walks back the requested number of active days', () {
      expect(
        LocalDate.from(
          activeDaysBefore(
            at: day(20),
            activeDays: 14,
            pauses: const <PauseInterval>[],
          ),
        ),
        LocalDate.from(day(6)),
      );
    });

    test('skips paused days on the way back', () {
      expect(
        LocalDate.from(
          activeDaysBefore(
            at: day(20),
            activeDays: 14,
            pauses: <PauseInterval>[pauseFrom(10, endDay: 13)],
          ),
        ),
        LocalDate.from(day(2)),
      );
    });
  });
}
