import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/core/engine/adherence.dart';
import 'package:taproot/core/models/pause_interval.dart';
import 'package:taproot/core/utils/local_dates.dart';

import '../../utils/engine_builders.dart';

void main() {
  setUp(resetFixtureIds);

  group('windowDaysForReps — W_days = clamp(W_reps x 7 / f, 14, 42)', () {
    test('f = 3, the spec worked example', () {
      expect(windowDaysForReps(windowReps: 3, targetFrequency: 3), 14);
      expect(windowDaysForReps(windowReps: 8, targetFrequency: 3), 19);
      expect(windowDaysForReps(windowReps: 12, targetFrequency: 3), 28);
      expect(windowDaysForReps(windowReps: 20, targetFrequency: 3), 42);
    });

    test('the 14-day floor binds at high frequency', () {
      // 3 reps at 7x/week is 3 days, which is far too short to judge anything.
      expect(windowDaysForReps(windowReps: 3, targetFrequency: 7), 14);
      expect(windowDaysForReps(windowReps: 8, targetFrequency: 7), 14);
      expect(windowDaysForReps(windowReps: 12, targetFrequency: 7), 14);
      expect(windowDaysForReps(windowReps: 20, targetFrequency: 7), 20);
    });

    test('the 42-day ceiling binds at low frequency', () {
      expect(windowDaysForReps(windowReps: 3, targetFrequency: 1), 21);
      expect(windowDaysForReps(windowReps: 8, targetFrequency: 1), 42);
      expect(windowDaysForReps(windowReps: 12, targetFrequency: 1), 42);
      expect(windowDaysForReps(windowReps: 20, targetFrequency: 1), 42);
    });

    test('rounds a fractional window up to a whole calendar day', () {
      // 8 x 7 / 3 = 18.67 days. The spec's worked example reads 19 days with
      // an expectation of 8.1, which is the rounded-up window.
      expect(windowDaysForReps(windowReps: 8, targetFrequency: 3), 19);
      expect(windowDaysForReps(windowReps: 8, targetFrequency: 5), 14);
      expect(windowDaysForReps(windowReps: 20, targetFrequency: 6), 24);
    });
  });

  group('windowCeilingBinds — the clamp-collapse condition', () {
    test('binds for Bloom below f = 3.3', () {
      expect(windowCeilingBinds(windowReps: 20, targetFrequency: 1), isTrue);
      expect(windowCeilingBinds(windowReps: 20, targetFrequency: 2), isTrue);
      expect(windowCeilingBinds(windowReps: 20, targetFrequency: 3), isTrue);
      expect(windowCeilingBinds(windowReps: 20, targetFrequency: 4), isFalse);
    });

    test('binds for Mature below f = 2', () {
      expect(windowCeilingBinds(windowReps: 12, targetFrequency: 1), isTrue);
      // 12 x 7 / 2 = 42 exactly, so the ceiling is touched but not binding.
      expect(windowCeilingBinds(windowReps: 12, targetFrequency: 2), isFalse);
      expect(windowCeilingBinds(windowReps: 12, targetFrequency: 3), isFalse);
    });
  });

  group('computeAdherence', () {
    test('A = completions / expected over the window', () {
      // f = 3, W_reps = 8: a 19-day window expecting 8.14 runs. Five
      // completions is the first integer that clears the 0.60 Young bar.
      final window = computeAdherence(
        inputs: inputs(completions: completionsOn(<num>[0, 4, 8, 12, 16])),
        windowReps: 8,
        at: day(18),
      );

      expect(window.windowDays, 19);
      expect(window.expectedCompletions, closeTo(8.142857, 1e-6));
      expect(window.completions, 5);
      expect(window.adherence, closeTo(0.614035, 1e-6));
      expect(window.adherence, greaterThanOrEqualTo(0.60));
    });

    test('reports the oldest local date in the window', () {
      final window = computeAdherence(
        inputs: inputs(),
        windowReps: 8,
        at: day(18),
      );

      expect(window.windowStart, LocalDate.from(day(0)));
    });

    test('excludes completions that fall before the window', () {
      final window = computeAdherence(
        inputs: inputs(completions: completionsOn(<num>[0, 1, 2])),
        windowReps: 8,
        at: day(30),
      );

      expect(window.completions, 0);
      expect(window.adherence, 0);
    });

    test('excludes completions after the evaluation instant', () {
      // History replay evaluates at past instants; the future must not leak in.
      final window = computeAdherence(
        inputs: inputs(completions: completionsOn(<num>[1, 2, 9])),
        windowReps: 8,
        at: day(5),
      );

      expect(window.completions, 2);
    });

    test('counts a completion made later on the evaluation day', () {
      final window = computeAdherence(
        inputs: inputs(completions: completionsOn(<num>[5.4])),
        windowReps: 8,
        at: day(5.5),
      );

      expect(window.completions, 1);
    });

    test('caps at 1.0 — overperformance buys no slack', () {
      final window = computeAdherence(
        inputs: inputs(completions: completionsEvery(every: 1, count: 28)),
        windowReps: 12,
        at: day(27),
      );

      expect(window.completions, 28);
      expect(window.expectedCompletions, closeTo(12, 1e-9));
      expect(window.adherence, 1.0);
    });

    test('counts every completion, including two on one day', () {
      // "completions_in_window", not "days with a completion" — a double
      // watering is two reps. The 1.0 cap is what bounds the effect.
      final window = computeAdherence(
        inputs: inputs(completions: completionsOn(<num>[3, 3.2, 7])),
        windowReps: 8,
        at: day(10),
      );

      expect(window.completions, 3);
    });

    test('paused days stretch the window rather than shortening it', () {
      // 14 active days ending at day 20 reach back to day 3 once days 10-13
      // are paused out, so the completion on day 4 is still in the window.
      final paused = computeAdherence(
        inputs: inputs(
          completions: completionsOn(<num>[4]),
          pauses: <PauseInterval>[pauseFrom(10, endDay: 13)],
        ),
        windowReps: 3,
        at: day(20),
      );
      final unpaused = computeAdherence(
        inputs: inputs(completions: completionsOn(<num>[4])),
        windowReps: 3,
        at: day(20),
      );

      expect(paused.windowDays, 14);
      expect(paused.windowStart, LocalDate.from(day(3)));
      expect(paused.completions, 1);
      expect(unpaused.completions, 0);
    });

    test(
      'expected stays at the full window — a paused stretch is not a miss',
      () {
        final window = computeAdherence(
          inputs: inputs(pauses: <PauseInterval>[pauseFrom(10, endDay: 13)]),
          windowReps: 3,
          at: day(20),
        );

        expect(window.expectedCompletions, closeTo(6, 1e-9));
      },
    );

    test('a completion on a paused day is outside the window', () {
      final window = computeAdherence(
        inputs: inputs(
          completions: completionsOn(<num>[11]),
          pauses: <PauseInterval>[pauseFrom(10, endDay: 13)],
        ),
        windowReps: 3,
        at: day(20),
      );

      expect(window.completions, 0);
    });

    test('a brand-new habit is measured against the full window', () {
      // The window is not truncated to the habit's age: bloom must take 42
      // days of evidence, not 42 days minus however young the habit is.
      final window = computeAdherence(
        inputs: inputs(completions: completionsOn(<num>[0, 1, 2])),
        windowReps: 20,
        at: day(2),
      );

      expect(window.windowDays, 42);
      expect(window.expectedCompletions, closeTo(18, 1e-9));
      expect(window.adherence, closeTo(3 / 18, 1e-9));
    });
  });

  group('the stage thresholds, as integers', () {
    test('f = 3 needs 3 / 5 / 9 / 15 completions', () {
      int completionsNeeded(int windowReps, double threshold) {
        final window = computeAdherence(
          inputs: inputs(),
          windowReps: windowReps,
          at: day(50),
        );
        return (window.expectedCompletions * threshold).ceil();
      }

      expect(completionsNeeded(3, 0.50), 3);
      expect(completionsNeeded(8, 0.60), 5);
      expect(completionsNeeded(12, 0.75), 9);
      expect(completionsNeeded(20, 0.80), 15);
    });

    test('f = 1 collapses Mature and Bloom onto the same integer', () {
      // Both windows clamp to 42 days expecting 6 calls: 0.75 x 6 = 4.5 and
      // 0.80 x 6 = 4.8 both round to 5. The ladder has no top rung, which is
      // why Bloom tightens with time instead (see ladder_test).
      final mature = computeAdherence(
        inputs: inputs(targetFrequency: 1),
        windowReps: 12,
        at: day(50),
      );
      final bloom = computeAdherence(
        inputs: inputs(targetFrequency: 1),
        windowReps: 20,
        at: day(50),
      );

      expect((mature.expectedCompletions * 0.75).ceil(), 5);
      expect((bloom.expectedCompletions * 0.80).ceil(), 5);
    });

    test('f = 1 still separates Young from Mature at 4 vs 5', () {
      final young = computeAdherence(
        inputs: inputs(targetFrequency: 1),
        windowReps: 8,
        at: day(50),
      );
      final mature = computeAdherence(
        inputs: inputs(targetFrequency: 1),
        windowReps: 12,
        at: day(50),
      );

      expect((young.expectedCompletions * 0.60).ceil(), 4);
      expect((mature.expectedCompletions * 0.75).ceil(), 5);
    });
  });
}
