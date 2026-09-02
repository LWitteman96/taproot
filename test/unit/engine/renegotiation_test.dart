import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/engine/renegotiation.dart';
import 'package:taproot/core/models/pause_interval.dart';

import '../../utils/engine_builders.dart';

void main() {
  setUp(resetFixtureIds);

  group('the over-ambitious starter', () {
    // Declares gym 5x/week, manages 1x. His windows are 14 days, so the
    // two-window rule offers help on day 28 — and he churns around day 10.
    final habit = inputs(
      targetFrequency: 5,
      completions: completionsEvery(every: 7, count: 6),
    );

    test(
      'is not flagged while the app has less than two windows of evidence',
      () {
        // An empty pre-history window is not evidence of a mismatched target.
        expect(
          renegotiationTrigger(inputs: habit, stage: Stage.sprout, at: day(13)),
          isNull,
        );
      },
    );

    test('is flagged on adherence after two consecutive failing windows', () {
      expect(
        renegotiationTrigger(inputs: habit, stage: Stage.sprout, at: day(27)),
        isNull,
      );
      expect(
        renegotiationTrigger(inputs: habit, stage: Stage.sprout, at: day(28)),
        RenegotiationTrigger.sustainedLowAdherence,
      );
    });
  });

  group('the wilt-duration trigger', () {
    // The reason the adherence trigger cannot stand alone: it reaches the user
    // a fortnight after he has already left.
    final habit = inputs(
      targetFrequency: 5,
      completions: completionsOn(<num>[0]),
    );

    test('catches the drowning user in his second week', () {
      expect(
        renegotiationTrigger(inputs: habit, stage: Stage.sprout, at: day(9)),
        isNull,
      );
      expect(
        renegotiationTrigger(inputs: habit, stage: Stage.sprout, at: day(10)),
        RenegotiationTrigger.prolongedWilt,
      );
    });

    test('fires long before the adherence trigger could', () {
      expect(
        isRenegotiationCandidate(
          inputs: habit,
          stage: Stage.sprout,
          at: day(10),
        ),
        isTrue,
      );
    });

    test('needs seven consecutive wilted days, not seven scattered ones', () {
      // Watering on day 6 resets the run entirely.
      final watered = inputs(
        targetFrequency: 5,
        completions: completionsOn(<num>[0, 6]),
      );

      expect(
        renegotiationTrigger(inputs: watered, stage: Stage.sprout, at: day(10)),
        isNull,
      );
    });

    test('a mature tree wilts far too slowly to trip it early', () {
      expect(
        renegotiationTrigger(inputs: habit, stage: Stage.mature, at: day(10)),
        isNull,
      );
    });
  });

  group('a habit that is fine is left alone', () {
    test('steady 3x/week is never a candidate', () {
      final habit = inputs(
        completions: completionsWeekly(
          offsetsInWeek: <num>[0, 2, 4],
          weeks: 10,
        ),
      );

      for (final d in <num>[10, 20, 30, 45, 60]) {
        expect(
          isRenegotiationCandidate(
            inputs: habit,
            stage: Stage.young,
            at: day(d),
          ),
          isFalse,
          reason: 'day $d',
        );
      }
    });

    test('a paused habit is not renegotiated', () {
      // Pause already says "not now". Proposing a lower target on top of it
      // punishes exactly the honesty the mechanic exists to protect.
      final habit = inputs(
        targetFrequency: 5,
        completions: completionsOn(<num>[0]),
        pauses: <PauseInterval>[pauseFrom(1)],
      );

      expect(
        renegotiationTrigger(inputs: habit, stage: Stage.sprout, at: day(30)),
        isNull,
      );
    });
  });

  group('the mechanic runs upward too', () {
    test(
      'sustained overperformance asks whether the target is now too low',
      () {
        // "You're running 5x — is that who you are now?"
        final habit = inputs(
          completions: completionsWeekly(
            offsetsInWeek: <num>[0, 1, 2, 3, 4],
            weeks: 13,
          ),
        );

        expect(
          renegotiationTrigger(inputs: habit, stage: Stage.mature, at: day(84)),
          RenegotiationTrigger.sustainedOverperformance,
        );
      },
    );
  });

  group('suggestedTargetFrequency', () {
    test('reads the pace the user is actually keeping', () {
      final habit = inputs(
        targetFrequency: 5,
        completions: completionsEvery(every: 7, count: 6),
      );

      expect(suggestedTargetFrequency(inputs: habit, at: day(35)), 1);
    });

    test('is null when the observed pace already matches the target', () {
      final habit = inputs(
        completions: completionsWeekly(offsetsInWeek: <num>[0, 2, 4], weeks: 8),
      );

      expect(suggestedTargetFrequency(inputs: habit, at: day(40)), isNull);
    });

    test('proposes an increase as readily as a decrease', () {
      final habit = inputs(
        completions: completionsWeekly(
          offsetsInWeek: <num>[0, 1, 2, 3, 4],
          weeks: 8,
        ),
      );

      expect(suggestedTargetFrequency(inputs: habit, at: day(40)), 5);
    });

    test('says nothing before there is a month of evidence', () {
      final habit = inputs(
        targetFrequency: 5,
        completions: completionsOn(<num>[0, 7, 14]),
      );

      expect(suggestedTargetFrequency(inputs: habit, at: day(20)), isNull);
    });

    test('never proposes zero', () {
      final habit = inputs(
        targetFrequency: 5,
        completions: completionsOn(<num>[0]),
      );

      expect(suggestedTargetFrequency(inputs: habit, at: day(60)), 1);
    });
  });
}
