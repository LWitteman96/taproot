import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/core/engine/autonomy.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/nudge.dart';

import '../../utils/engine_builders.dart';

void main() {
  setUp(resetFixtureIds);

  group('computeAutonomy', () {
    test('is completions on un-nudged occasions over un-nudged occasions', () {
      final habit = inputs(
        completions: completionsOn(<num>[0, 1, 2, 3, 4]),
        nudges: nudgesOn(<num>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9], sent: false),
      );
      final autonomy = computeAutonomy(inputs: habit, at: day(20));

      expect(autonomy.occasions, 10);
      expect(autonomy.completed, 5);
      expect(autonomy.value, closeTo(0.5, 1e-9));
      expect(autonomy.hasEvidence, isTrue);
    });

    test('nudged occasions are not in the denominator', () {
      // The skipped nudges are the measurement instrument. An occasion the app
      // propped up says nothing about whether the habit stands on its own.
      final habit = inputs(
        completions: completionsOn(<num>[0, 1, 2, 3, 4, 5, 6, 10, 11]),
        nudges: <NudgeRecord>[
          ...nudgesOn(<num>[0, 1, 2, 3, 4, 5, 6], sent: true),
          ...nudgesOn(<num>[10, 11, 12, 13], sent: false),
        ],
      );
      final autonomy = computeAutonomy(inputs: habit, at: day(20));

      expect(autonomy.occasions, 4);
      expect(autonomy.completed, 2);
      expect(autonomy.value, closeTo(0.5, 1e-9));
    });

    test('only the last ten un-nudged occasions count', () {
      final habit = inputs(
        completions: completionsOn(<num>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]),
        nudges: nudgesOn(<num>[
          0,
          1,
          2,
          3,
          4,
          5,
          6,
          7,
          8,
          9,
          20,
          21,
          22,
          23,
          24,
          25,
          26,
          27,
          28,
          29,
        ], sent: false),
      );
      final autonomy = computeAutonomy(inputs: habit, at: day(40));

      expect(autonomy.occasions, 10);
      expect(autonomy.completed, 0);
      expect(autonomy.value, 0);
    });

    test('a completion counts only on the occasion it belongs to', () {
      final habit = inputs(
        completions: completionsOn(<num>[1.5]),
        nudges: nudgesOn(<num>[0, 1, 2], sent: false),
      );
      final autonomy = computeAutonomy(inputs: habit, at: day(10));

      expect(autonomy.completed, 1);
      expect(autonomy.occasions, 3);
    });

    test('occasions after the evaluation instant are excluded', () {
      final habit = inputs(
        completions: completionsOn(<num>[0, 1, 5, 6]),
        nudges: nudgesOn(<num>[0, 1, 5, 6], sent: false),
      );
      final autonomy = computeAutonomy(inputs: habit, at: day(2));

      expect(autonomy.occasions, 2);
      expect(autonomy.completed, 2);
    });

    test('an unmeasured habit has not demonstrated autonomy', () {
      // Zero, not one, and not null: you cannot know whether a habit stands on
      // its own until you have stopped holding it up.
      final habit = inputs(
        completions: completionsEvery(every: 1, count: 30),
        nudges: nudgesOn(<num>[0, 1, 2, 3], sent: true),
      );
      final autonomy = computeAutonomy(inputs: habit, at: day(40));

      expect(autonomy.occasions, 0);
      expect(autonomy.completed, 0);
      expect(autonomy.value, 0);
      expect(autonomy.hasEvidence, isFalse);
    });

    test('a perfect record on un-nudged occasions reads 1.0', () {
      final habit = inputs(
        completions: completionsOn(<num>[0, 1, 2]),
        nudges: nudgesOn(<num>[0, 1, 2], sent: false),
      );

      expect(computeAutonomy(inputs: habit, at: day(10)).value, 1.0);
    });
  });

  group('nudge fading', () {
    test('fades from every occasion to a spot check', () {
      expect(nudgeRateForStage(Stage.sprout), 1.0);
      expect(nudgeRateForStage(Stage.seedling), 1.0);
      expect(nudgeRateForStage(Stage.young), closeTo(0.70, 1e-9));
      expect(nudgeRateForStage(Stage.mature), closeTo(0.40, 1e-9));
      expect(nudgeRateForStage(Stage.bloom), closeTo(0.10, 1e-9));
    });

    test('is monotonically decreasing up the ladder', () {
      // If the app nudges every time, the notification becomes the cue.
      final rates = Stage.values.map(nudgeRateForStage).toList();

      for (var i = 1; i < rates.length; i++) {
        expect(rates[i], lessThanOrEqualTo(rates[i - 1]));
      }
    });
  });

  group('the first un-nudged completion', () {
    test('is false while every occasion has been propped up', () {
      final habit = inputs(
        completions: completionsOn(<num>[0, 1, 2]),
        nudges: nudgesOn(<num>[0, 1, 2], sent: true),
      );

      expect(hasUnNudgedCompletion(inputs: habit, at: day(10)), isFalse);
    });

    test('fires the moment one lands', () {
      // "You ran without us asking" — the app's whole thesis, in week two.
      final habit = inputs(
        completions: completionsOn(<num>[0, 1, 5]),
        nudges: <NudgeRecord>[
          ...nudgesOn(<num>[0, 1], sent: true),
          nudgeOn(5, sent: false),
        ],
      );

      expect(hasUnNudgedCompletion(inputs: habit, at: day(4)), isFalse);
      expect(hasUnNudgedCompletion(inputs: habit, at: day(6)), isTrue);
    });
  });

  group('graduation', () {
    test('needs Bloom, c >= 0.8 and autonomy >= 0.6', () {
      expect(
        isGraduated(stage: Stage.bloom, convergence: 0.8, autonomy: 0.6),
        isTrue,
      );
    });

    test('is refused below any one of the three', () {
      expect(
        isGraduated(stage: Stage.mature, convergence: 1.0, autonomy: 1.0),
        isFalse,
      );
      expect(
        isGraduated(stage: Stage.bloom, convergence: 0.79, autonomy: 1.0),
        isFalse,
      );
      expect(
        isGraduated(stage: Stage.bloom, convergence: 1.0, autonomy: 0.59),
        isFalse,
      );
    });

    test('holds a higher autonomy bar than Bloom itself does', () {
      // Bloom needs 0.5; the app only backs off entirely at 0.6.
      expect(
        isGraduated(stage: Stage.bloom, convergence: 1.0, autonomy: 0.5),
        isFalse,
      );
    });
  });
}
