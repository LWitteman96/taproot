import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/core/engine/adherence.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/engine/engine.dart';
import 'package:taproot/core/engine/ladder.dart';
import 'package:taproot/core/engine/roots.dart';
import 'package:taproot/core/engine/vitality.dart';
import 'package:taproot/core/models/completion.dart';
import 'package:taproot/core/models/nudge.dart';
import 'package:taproot/core/models/reflection.dart';

import '../../utils/engine_builders.dart';

/// The growth spec's worked examples, run against the engine.
///
/// These are a specification and a test suite at the same time: every number
/// here is quoted from the spec, and they are what catch off-by-ones in the
/// window arithmetic.
void main() {
  setUp(resetFixtureIds);

  group('growth spec §3 — the ladder at f = 3', () {
    int completionsNeededFor(int windowReps, double threshold) {
      final window = computeAdherence(
        inputs: inputs(),
        windowReps: windowReps,
        at: day(60),
      );
      return (window.expectedCompletions * threshold).ceil();
    }

    test('Young: window 19 days, expected 8.1, need 5 completions', () {
      final window = computeAdherence(
        inputs: inputs(),
        windowReps: 8,
        at: day(60),
      );

      expect(window.windowDays, 19);
      expect(window.expectedCompletions, closeTo(8.1, 0.05));
      expect(completionsNeededFor(8, 0.60), 5);
    });

    test('Mature: window 28 days, expected 12, need 9 completions', () {
      final window = computeAdherence(
        inputs: inputs(),
        windowReps: 12,
        at: day(60),
      );

      expect(window.windowDays, 28);
      expect(window.expectedCompletions, closeTo(12, 1e-9));
      expect(completionsNeededFor(12, 0.75), 9);
    });

    test('Bloom: window 42 days, expected 18, need 15 completions', () {
      final window = computeAdherence(
        inputs: inputs(),
        windowReps: 20,
        at: day(60),
      );

      expect(window.windowDays, 42);
      expect(window.expectedCompletions, closeTo(18, 1e-9));
      expect(completionsNeededFor(20, 0.80), 15);
    });

    test('five completions in the window make a Young plant, four do not', () {
      // Seedling on day 2, then five runs inside a window that opens on day 6.
      final five = inputs(
        completions: completionsOn(<num>[0, 1, 2, 6, 11, 16, 21, 24]),
      );
      final four = inputs(
        completions: completionsOn(<num>[0, 1, 2, 6, 11, 16, 21]),
      );

      expect(computeStage(inputs: five, at: day(24)), Stage.young);
      expect(computeStage(inputs: four, at: day(24)), Stage.seedling);
    });
  });

  group('growth spec §3 — clamp collapse at f = 1', () {
    test('Mature and Bloom both round to 5 calls in a 42-day window', () {
      final mature = computeAdherence(
        inputs: inputs(targetFrequency: 1),
        windowReps: 12,
        at: day(60),
      );
      final bloom = computeAdherence(
        inputs: inputs(targetFrequency: 1),
        windowReps: 20,
        at: day(60),
      );

      expect(mature.windowDays, 42);
      expect(bloom.windowDays, 42);
      expect(mature.expectedCompletions, closeTo(6, 1e-9));
      expect((mature.expectedCompletions * 0.75).ceil(), 5);
      expect((bloom.expectedCompletions * 0.80).ceil(), 5);
      expect(bloom.ceilingBinds, isTrue);
    });
  });

  group('growth spec §4 — the droop curve at f = 3', () {
    test('a seedling droops at 2.8 days and fully wilts at 5.8', () {
      final habit = inputs(completions: completionsOn(<num>[0]));

      expect(
        rawVitality(inputs: habit, stage: Stage.seedling, at: day(2.83)),
        closeTo(1.0, 0.01),
      );
      expect(
        rawVitality(inputs: habit, stage: Stage.seedling, at: day(2.9)),
        lessThan(1.0),
      );
      expect(
        rawVitality(inputs: habit, stage: Stage.seedling, at: day(5.83)),
        closeTo(0.0, 0.01),
      );
    });

    test('a mature tree does not react until 5.3 days, wilting at 17.3', () {
      final habit = inputs(completions: completionsOn(<num>[0]));

      expect(
        rawVitality(inputs: habit, stage: Stage.mature, at: day(5.3)),
        closeTo(1.0, 0.01),
      );
      expect(
        rawVitality(inputs: habit, stage: Stage.mature, at: day(17.33)),
        closeTo(0.0, 0.01),
      );
      expect(
        rawVitality(inputs: habit, stage: Stage.mature, at: day(17)),
        greaterThan(0.0),
      );
    });

    test('the pace exemption keeps a daily habit healthy at 6 of 7', () {
      final habit = inputs(
        targetFrequency: 7,
        completions: completionsOn(<num>[0, 1, 2, 3, 4, 5]),
      );

      expect(paceExemptionThreshold(7), 6);
      expect(
        computeVitality(inputs: habit, stage: Stage.young, at: day(6.5)),
        1.0,
      );
    });
  });

  group('growth spec §5 — N / (N + 4)', () {
    test('gives 0.50 at 4, 0.71 at 10 and 0.83 at 20', () {
      expect(rawRootDepth(4), closeTo(0.50, 0.005));
      expect(rawRootDepth(10), closeTo(0.71, 0.005));
      expect(rawRootDepth(20), closeTo(0.83, 0.005));
    });

    test(
      'six of eight on one cue deepens roots; eight of eight scattered does not',
      () {
        final converged = computeRoots(
          inputs: inputs(reflections: reflectionsDaily(count: 8)),
          at: day(10),
        );
        final scattered = computeRoots(
          inputs: inputs(
            reflections: <Reflection>[
              for (var i = 0; i < 8; i++)
                reflectionOn(i, cueReported: 'cue $i'),
            ],
          ),
          at: day(10),
        );

        expect(converged.convergence, 1.0);
        expect(scattered.convergence, closeTo(0.125, 1e-9));
        expect(scattered.depth, lessThan(converged.depth));
      },
    );
  });

  group('growth spec §3 — the fastest path to Bloom', () {
    test('takes roughly three months of flawless play, not six weeks', () {
      // The spec puts the floor at ~96 days, deliberately past the ~66-day
      // median for automaticity in Lally et al. Bloom should mean actually
      // ingrained, not stuck with it for a month.
      final habit = inputs(
        completions: <Completion>[
          ...completionsOn(<num>[0, 1, 2]),
          ...completionsWeekly(
            offsetsInWeek: <num>[0, 2, 4],
            weeks: 14,
            from: 7,
          ),
        ],
        reflections: reflectionsDaily(count: 20, from: 21),
        nudges: <NudgeRecord>[
          ...nudgesOn(<num>[63, 65, 67, 70, 72, 74], sent: false),
          ...nudgesOn(<num>[64, 66, 68, 69], sent: false),
        ],
      );

      var firstBloomDay = -1;
      for (var d = 0; d <= 140; d++) {
        if (computeStage(inputs: habit, at: day(d)) == Stage.bloom) {
          firstBloomDay = d;
          break;
        }
      }

      expect(firstBloomDay, greaterThan(84));
      expect(firstBloomDay, lessThan(105));
    });
  });

  group('the engine facade', () {
    test('reports every derived value together, stamped with a version', () {
      final habit = inputs(
        completions: completionsWeekly(
          offsetsInWeek: <num>[0, 2, 4],
          weeks: 10,
        ),
        reflections: reflectionsDaily(count: 12, from: 20),
        nudges: <NudgeRecord>[
          ...nudgesOn(<num>[42, 44, 46], sent: false),
          ...nudgesOn(<num>[43, 45, 47], sent: false),
        ],
      );
      final growth = evaluateGrowth(inputs: habit, at: day(60));

      expect(growth.stage, Stage.mature);
      expect(growth.vitality, 1.0);
      expect(growth.roots.depth, closeTo(12 / 16, 1e-9));
      expect(growth.autonomy.value, closeTo(0.5, 1e-9));
      expect(growth.currentWindow.windowReps, 20);
      expect(growth.isShallowRooted, isFalse);
      expect(growth.isRenegotiationCandidate, isFalse);
      expect(growth.isGraduated, isFalse);
      expect(growth.constantsVersion, 1);
    });

    test(
      'a graduated habit is Bloom with a converged cue and real autonomy',
      () {
        final habit = inputs(
          targetFrequency: 4,
          completions: completionsWeekly(
            offsetsInWeek: <num>[0, 2, 4, 6],
            weeks: 12,
          ),
          reflections: reflectionsDaily(count: 20, from: 40),
          nudges: <NudgeRecord>[
            ...nudgesOn(<num>[42, 44, 46, 48, 49, 51, 53], sent: false),
            ...nudgesOn(<num>[43, 45, 47], sent: false),
          ],
        );
        final growth = evaluateGrowth(inputs: habit, at: day(80));

        expect(growth.stage, Stage.bloom);
        expect(growth.roots.convergence, greaterThanOrEqualTo(0.8));
        expect(growth.autonomy.value, greaterThanOrEqualTo(0.6));
        expect(growth.isGraduated, isTrue);
      },
    );
  });
}
