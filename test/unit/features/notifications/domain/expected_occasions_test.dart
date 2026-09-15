import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/core/models/pause_interval.dart';
import 'package:taproot/core/utils/local_dates.dart';
import 'package:taproot/features/notifications/domain/expected_occasions.dart';

/// The occasion calendar.
///
/// It is derived, not stored, so the property that matters is that it is
/// *reproducible*: two devices replaying one habit must agree on which local
/// dates are expected occasions, because those dates are what autonomy is
/// counted over.
void main() {
  final created = DateTime(2026, 3, 2, 8, 30); // a Monday morning

  List<LocalDate> datesFor(
    int targetFrequency, {
    int throughDays = 13,
    List<PauseInterval> pauses = const <PauseInterval>[],
  }) => expectedOccasionsBetween(
    createdAt: created,
    targetFrequency: targetFrequency,
    from: LocalDate.from(created),
    to: LocalDate.from(created).addDays(throughDays),
    pauses: pauses,
  ).map((occasion) => occasion.date).toList();

  group('the cadence', () {
    test('spreads f occasions across every week', () {
      // Two weeks of each frequency, counted: the long-run rate has to be f,
      // not f on average.
      for (var frequency = 1; frequency <= 7; frequency++) {
        expect(
          datesFor(frequency),
          hasLength(frequency * 2),
          reason: 'f = $frequency should give 2 weeks of $frequency',
        );
      }
    });

    test('puts them on the days the spec reasons about', () {
      // f = 3 → day 0, 2, 5, then the pattern repeats a week later.
      expect(datesFor(3, throughDays: 6), <LocalDate>[
        LocalDate(2026, 3, 2),
        LocalDate(2026, 3, 4),
        LocalDate(2026, 3, 7),
      ]);

      // f = 5 → 0, 1, 3, 4, 6. Never two gaps in a row at the same width.
      expect(datesFor(5, throughDays: 6), <LocalDate>[
        LocalDate(2026, 3, 2),
        LocalDate(2026, 3, 3),
        LocalDate(2026, 3, 5),
        LocalDate(2026, 3, 6),
        LocalDate(2026, 3, 8),
      ]);

      // f = 7 → every day, with no day skipped by a rounding error.
      expect(datesFor(7, throughDays: 3), <LocalDate>[
        LocalDate(2026, 3, 2),
        LocalDate(2026, 3, 3),
        LocalDate(2026, 3, 4),
        LocalDate(2026, 3, 5),
      ]);
    });

    test('never drifts, however far out it is asked', () {
      // A year of a daily habit is 365 occasions, not 364 or 366 — the
      // rounding is applied to n × 7 / f, so it cannot accumulate.
      final year = expectedOccasionsBetween(
        createdAt: created,
        targetFrequency: 7,
        from: LocalDate.from(created),
        to: LocalDate.from(created).addDays(364),
      );
      expect(year, hasLength(365));
      expect(year.last.date, LocalDate.from(created).addDays(364));
    });

    test('is the same whether asked for a window or the whole history', () {
      // The window query skips ahead to the first index that can reach `from`
      // instead of walking from zero. That shortcut is the one place the
      // calendar could silently disagree with itself.
      for (var frequency = 1; frequency <= 7; frequency++) {
        final whole = expectedOccasionsBetween(
          createdAt: created,
          targetFrequency: frequency,
          from: LocalDate.from(created),
          to: LocalDate.from(created).addDays(60),
        );
        final window = expectedOccasionsBetween(
          createdAt: created,
          targetFrequency: frequency,
          from: LocalDate.from(created).addDays(30),
          to: LocalDate.from(created).addDays(60),
        );

        expect(
          window,
          whole
              .where(
                (occasion) => !occasion.date.isBefore(
                  LocalDate.from(created).addDays(30),
                ),
              )
              .toList(),
          reason: 'f = $frequency',
        );
      }
    });

    test('indexes are stable, so a row keeps its identity across passes', () {
      final first = expectedOccasionsBetween(
        createdAt: created,
        targetFrequency: 3,
        from: LocalDate.from(created).addDays(14),
        to: LocalDate.from(created).addDays(21),
      ).first;

      expect(
        first.date,
        occasionDate(
          createdAt: created,
          targetFrequency: 3,
          index: first.index,
        ),
      );
    });

    test('starts at the creation date, never before it', () {
      final occasions = expectedOccasionsBetween(
        createdAt: created,
        targetFrequency: 7,
        from: LocalDate.from(created).addDays(-30),
        to: LocalDate.from(created).addDays(2),
      );

      expect(occasions.first.index, 0);
      expect(occasions.first.date, LocalDate.from(created));
    });
  });

  group('pauses', () {
    test('an occasion on a paused day is not expected at all', () {
      // Not "expected and forgiven" — absent. A row on a paused day would be
      // an un-nudged occasion in autonomy's denominator for a day the engine
      // has already agreed not to count (growth spec §7).
      final pause = PauseInterval(
        startedAt: DateTime(2026, 3, 4),
        endedAt: DateTime(2026, 3, 5),
      );

      expect(
        datesFor(7, throughDays: 6, pauses: <PauseInterval>[pause]),
        <LocalDate>[
          LocalDate(2026, 3, 2),
          LocalDate(2026, 3, 3),
          LocalDate(2026, 3, 6),
          LocalDate(2026, 3, 7),
          LocalDate(2026, 3, 8),
        ],
      );
    });

    test('an open pause removes every occasion after it starts', () {
      final open = PauseInterval(startedAt: DateTime(2026, 3, 5));

      expect(
        datesFor(7, throughDays: 10, pauses: <PauseInterval>[open]),
        <LocalDate>[
          LocalDate(2026, 3, 2),
          LocalDate(2026, 3, 3),
          LocalDate(2026, 3, 4),
        ],
      );
    });

    test('the occasions around a pause keep their original dates', () {
      // The cadence is anchored to the creation date, so a pause removes days
      // rather than shifting the ones after it. A shifting cadence would mean
      // two devices that learned about a pause at different times disagreed
      // about every occasion that followed.
      final pause = PauseInterval(
        startedAt: DateTime(2026, 3, 4),
        endedAt: DateTime(2026, 3, 4),
      );
      final paused = datesFor(
        3,
        throughDays: 13,
        pauses: <PauseInterval>[pause],
      );

      expect(paused, isNot(contains(LocalDate(2026, 3, 4))));
      expect(
        paused,
        containsAll(<LocalDate>[
          LocalDate(2026, 3, 2),
          LocalDate(2026, 3, 7),
          LocalDate(2026, 3, 9),
        ]),
      );
    });
  });

  group('delivery', () {
    test('is the evening before the occasion', () {
      expect(
        nudgeDeliveryTime(
          ExpectedOccasion(index: 4, date: LocalDate(2026, 3, 9)),
        ),
        DateTime(2026, 3, 8, 20),
      );
    });

    test('crosses a month boundary rather than clamping inside it', () {
      expect(
        nudgeDeliveryTime(
          ExpectedOccasion(index: 0, date: LocalDate(2026, 4, 1)),
        ),
        DateTime(2026, 3, 31, 20),
      );
    });

    test('is a local wall-clock time, so it survives a DST change', () {
      // 2026-03-29 is the European spring-forward. The check-in is at 20:00
      // where the user is on both sides of it, which is exactly what storing
      // a wall-clock time rather than an offset from UTC buys.
      final before = nudgeDeliveryTime(
        ExpectedOccasion(index: 0, date: LocalDate(2026, 3, 29)),
      );
      final after = nudgeDeliveryTime(
        ExpectedOccasion(index: 1, date: LocalDate(2026, 3, 31)),
      );

      expect(before.hour, 20);
      expect(after.hour, 20);
      expect(before.isUtc, isFalse);
    });
  });
}
