import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/engine/vitality.dart';
import 'package:taproot/core/models/pause_interval.dart';

import '../../utils/engine_builders.dart';

void main() {
  setUp(resetFixtureIds);

  group('the droop table', () {
    test('grace and full-wilt days per stage', () {
      expect(graceDaysForStage(Stage.sprout), 0);
      expect(graceDaysForStage(Stage.seedling), 0.5);
      expect(graceDaysForStage(Stage.young), 1.5);
      expect(graceDaysForStage(Stage.mature), 3);
      expect(graceDaysForStage(Stage.bloom), 5);

      expect(droopDaysForStage(Stage.sprout), 2);
      expect(droopDaysForStage(Stage.seedling), 3);
      expect(droopDaysForStage(Stage.young), 6);
      expect(droopDaysForStage(Stage.mature), 12);
      expect(droopDaysForStage(Stage.bloom), 20);
    });
  });

  group('V snaps to 1.0 on completion', () {
    test('the moment the plant is watered', () {
      final habit = inputs(completions: completionsOn(<num>[0, 12]));

      expect(
        computeVitality(inputs: habit, stage: Stage.seedling, at: day(12)),
        1.0,
      );
    });

    test('however wilted it was a second earlier', () {
      final habit = inputs(completions: completionsOn(<num>[0, 12]));

      expect(
        rawVitality(inputs: habit, stage: Stage.seedling, at: day(11.99)),
        0.0,
      );
      expect(
        rawVitality(inputs: habit, stage: Stage.seedling, at: day(12)),
        1.0,
      );
    });
  });

  group('the droop curve at f = 3 (G = 2.33)', () {
    // The spec's worked example: a seedling starts drooping 2.8 days after its
    // last watering and is fully wilted at 5.8.
    double seedlingVitalityAt(num days) => rawVitality(
      inputs: inputs(completions: completionsOn(<num>[0])),
      stage: Stage.seedling,
      at: day(days),
    );

    test('a seedling is untouched right up to droop onset at 2.83 days', () {
      expect(seedlingVitalityAt(2.5), 1.0);
      expect(seedlingVitalityAt(2.8), closeTo(1.0, 1e-9));
      expect(seedlingVitalityAt(2 + 1 / 3 + 0.5), closeTo(1.0, 1e-9));
    });

    test('a seedling is half wilted at 4.33 days', () {
      expect(seedlingVitalityAt(2 + 1 / 3 + 0.5 + 1.5), closeTo(0.5, 1e-9));
    });

    test('a seedling is fully wilted at 5.83 days and stays there', () {
      expect(seedlingVitalityAt(2 + 1 / 3 + 0.5 + 3), closeTo(0.0, 1e-9));
      expect(seedlingVitalityAt(20), 0.0);
      expect(seedlingVitalityAt(400), 0.0);
    });

    test('a mature tree does not visibly react until 5.33 days', () {
      double matureVitalityAt(num days) => rawVitality(
        inputs: inputs(completions: completionsOn(<num>[0])),
        stage: Stage.mature,
        at: day(days),
      );

      // Miss one run as an oak and nothing happens.
      expect(matureVitalityAt(4), 1.0);
      expect(matureVitalityAt(2 + 1 / 3 + 3), closeTo(1.0, 1e-9));
      expect(matureVitalityAt(2 + 1 / 3 + 3 + 6), closeTo(0.5, 1e-9));
      expect(matureVitalityAt(2 + 1 / 3 + 3 + 12), closeTo(0.0, 1e-9));
    });

    test('every stage droops on its own schedule', () {
      double vitalityFor(Stage stage, num days) => rawVitality(
        inputs: inputs(completions: completionsOn(<num>[0])),
        stage: stage,
        at: day(days),
      );

      expect(vitalityFor(Stage.sprout, 2 + 1 / 3 + 1), closeTo(0.5, 1e-9));
      expect(vitalityFor(Stage.young, 2 + 1 / 3 + 1.5 + 3), closeTo(0.5, 1e-9));
      expect(vitalityFor(Stage.bloom, 2 + 1 / 3 + 5 + 10), closeTo(0.5, 1e-9));
    });

    test('vitality is never outside [0, 1]', () {
      for (final days in <num>[0, 0.5, 3, 5, 8, 40]) {
        expect(seedlingVitalityAt(days), inInclusiveRange(0.0, 1.0));
      }
    });
  });

  group('a habit that has never been watered', () {
    test('measures its gap from creation, not from nothing', () {
      // A designed-but-never-watered seed should wilt on the same schedule as
      // a plant whose last watering was at creation.
      expect(rawVitality(inputs: inputs(), stage: Stage.seed, at: day(1)), 1.0);
      expect(
        rawVitality(
          inputs: inputs(),
          stage: Stage.seed,
          at: day(2 + 1 / 3 + 1),
        ),
        closeTo(0.5, 1e-9),
      );
      expect(
        rawVitality(inputs: inputs(), stage: Stage.seed, at: day(10)),
        0.0,
      );
    });

    test('daysSinceLastCompletion is null with no completions', () {
      expect(daysSinceLastCompletion(inputs: inputs(), at: day(3)), isNull);
    });

    test('daysSinceLastCompletion measures the most recent watering', () {
      expect(
        daysSinceLastCompletion(
          inputs: inputs(completions: completionsOn(<num>[0, 4])),
          at: day(6.5),
        ),
        closeTo(2.5, 1e-9),
      );
    });
  });

  group('the pace exemption — C7 >= ceil(0.8 x f)', () {
    test('the threshold protects daily habits without gifting weekly ones', () {
      expect(paceExemptionThreshold(1), 1);
      expect(paceExemptionThreshold(2), 2);
      expect(paceExemptionThreshold(3), 3);
      expect(paceExemptionThreshold(4), 4);
      expect(paceExemptionThreshold(5), 4);
      expect(paceExemptionThreshold(6), 5);
      expect(paceExemptionThreshold(7), 6);
    });

    test('Mon/Tue/Wed then rest does not droop at f = 3', () {
      // The pacing trap: the user hit 3x/week exactly, so the plant answers to
      // the week, not to the calendar gap.
      final habit = inputs(completions: completionsOn(<num>[0, 1, 2]));

      expect(completionsLastSevenDays(inputs: habit, at: day(6)), 3);
      expect(
        computeVitality(inputs: habit, stage: Stage.seedling, at: day(6)),
        1.0,
      );
    });

    test('but droops once the week rolls off', () {
      final habit = inputs(completions: completionsOn(<num>[0, 1, 2]));

      expect(completionsLastSevenDays(inputs: habit, at: day(7)), 2);
      expect(
        computeVitality(inputs: habit, stage: Stage.seedling, at: day(7)),
        closeTo(1 - (5 - 7 / 3 - 0.5) / 3, 1e-9),
      );
    });

    test('a daily habit survives one missed day at 6 of 7', () {
      // A strict C7 >= f would demand a perfect 7 of 7 at f = 7, leaving the
      // habits that trip the gap formula most often with no protection at all.
      final habit = inputs(
        targetFrequency: 7,
        completions: completionsOn(<num>[0, 1, 2, 3, 4, 5]),
      );

      expect(completionsLastSevenDays(inputs: habit, at: day(6.5)), 6);
      expect(
        computeVitality(inputs: habit, stage: Stage.seedling, at: day(6.5)),
        1.0,
      );
    });

    test('and droops on the second missed day', () {
      final habit = inputs(
        targetFrequency: 7,
        completions: completionsOn(<num>[0, 1, 2, 3, 4]),
      );

      expect(completionsLastSevenDays(inputs: habit, at: day(6.5)), 5);
      expect(
        computeVitality(inputs: habit, stage: Stage.seedling, at: day(6.5)),
        closeTo(1 - (2.5 - 1 - 0.5) / 3, 1e-9),
      );
    });

    test('C7 counts the last seven active days', () {
      final habit = inputs(
        completions: completionsOn(<num>[0, 1, 2]),
        pauses: <PauseInterval>[pauseFrom(3, endDay: 9)],
      );

      // Seven paused days do not roll the week off.
      expect(completionsLastSevenDays(inputs: habit, at: day(12)), 3);
    });
  });

  group('pauses freeze vitality', () {
    test('paused days do not count toward the gap', () {
      final paused = inputs(
        completions: completionsOn(<num>[0]),
        pauses: <PauseInterval>[pauseFrom(2, endDay: 8)],
      );

      expect(
        rawVitality(inputs: paused, stage: Stage.seedling, at: day(10)),
        closeTo(1 - (3 - 2 - 1 / 3 - 0.5) / 3, 1e-9),
      );
      expect(
        rawVitality(
          inputs: inputs(completions: completionsOn(<num>[0])),
          stage: Stage.seedling,
          at: day(10),
        ),
        0.0,
      );
    });

    test('vitality does not move within a paused day', () {
      // Regression: whole-day pause arithmetic made a paused plant droop
      // through the afternoon and recover at midnight, every day.
      final paused = inputs(
        completions: completionsOn(<num>[0]),
        pauses: <PauseInterval>[pauseFrom(3)],
      );
      final frozen = rawVitality(
        inputs: paused,
        stage: Stage.seedling,
        at: day(3),
      );

      for (final t in <num>[3.2, 3.6, 3.99, 4.2, 4.6, 12]) {
        expect(
          rawVitality(inputs: paused, stage: Stage.seedling, at: day(t)),
          closeTo(frozen, 1e-9),
          reason: 'day $t',
        );
      }
    });

    test('an open pause holds vitality indefinitely', () {
      final paused = inputs(
        completions: completionsOn(<num>[0]),
        pauses: <PauseInterval>[pauseFrom(1)],
      );

      expect(
        rawVitality(inputs: paused, stage: Stage.seedling, at: day(90)),
        1.0,
      );
    });
  });

  group('the wilt freeze', () {
    test('a renegotiation candidate stops wilting', () {
      // Once the app suspects the target is wrong, further wilting punishes
      // the user for the app's bad assumption.
      final habit = inputs(completions: completionsOn(<num>[0]));

      expect(
        rawVitality(inputs: habit, stage: Stage.seedling, at: day(30)),
        0.0,
      );
      expect(
        computeVitality(
          inputs: habit,
          stage: Stage.seedling,
          at: day(30),
          isRenegotiationCandidate: true,
        ),
        1.0,
      );
    });

    test('is not applied unless the habit is a candidate', () {
      final habit = inputs(completions: completionsOn(<num>[0]));

      expect(
        computeVitality(inputs: habit, stage: Stage.seedling, at: day(30)),
        0.0,
      );
    });
  });
}
