import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/engine/inputs.dart';
import 'package:taproot/core/engine/ladder.dart';
import 'package:taproot/core/models/completion.dart';
import 'package:taproot/core/models/nudge.dart';
import 'package:taproot/core/models/reflection.dart';

import '../../utils/engine_builders.dart';

/// A steady 3x/week history: Mon/Wed/Fri, ten weeks.
List<Completion> steadyThreePerWeek({int weeks = 10}) =>
    completionsWeekly(offsetsInWeek: <num>[0, 2, 4], weeks: weeks);

/// A steady 4x/week history, eleven weeks.
List<Completion> steadyFourPerWeek({int weeks = 11}) =>
    completionsWeekly(offsetsInWeek: <num>[0, 2, 4, 6], weeks: weeks);

/// Twenty converged reflections, which puts roots at 0.83 — over the Bloom
/// gate of 0.75.
List<Reflection> deepRoots({num from = 40}) =>
    reflectionsDaily(count: 20, from: from);

/// Un-nudged occasions, split into the ones the user completed anyway and the
/// ones they didn't. Ten occasions at six completed reads as autonomy 0.6.
List<NudgeRecord> autonomyLedger({
  required List<num> completed,
  required List<num> missed,
}) => <NudgeRecord>[
  ...nudgesOn(completed, sent: false),
  ...nudgesOn(missed, sent: false),
];

/// The 4x/week fixture's own occasions: 42/44/46/48/49/51 are run days,
/// 43/45/47/50 are not.
List<NudgeRecord> fourPerWeekLedger() => autonomyLedger(
  completed: <num>[42, 44, 46, 48, 49, 51],
  missed: <num>[43, 45, 47, 50],
);

void main() {
  setUp(resetFixtureIds);

  group('the bottom of the ladder', () {
    test('a designed habit with no completions is a Seed', () {
      expect(computeStage(inputs: inputs(), at: day(30)), Stage.seed);
    });

    test('the first completion sprouts it', () {
      final habit = inputs(completions: completionsOn(<num>[0]));

      expect(computeStage(inputs: habit, at: day(0)), Stage.sprout);
    });

    test('two completions are not yet a Seedling', () {
      final habit = inputs(completions: completionsOn(<num>[0, 2]));

      expect(computeStage(inputs: habit, at: day(3)), Stage.sprout);
    });

    test('three completions inside the window make a Seedling', () {
      final habit = inputs(completions: completionsOn(<num>[0, 2, 4]));

      expect(computeStage(inputs: habit, at: day(4)), Stage.seedling);
    });

    test('three completions spread too thin do not', () {
      // At f = 3 the Seedling window expects 6 runs in 14 days and asks for
      // half of them; three runs spread over 40 days is one run in the window.
      final habit = inputs(completions: completionsOn(<num>[0, 20, 40]));

      expect(computeStage(inputs: habit, at: day(40)), Stage.sprout);
    });

    test('a daily habit is held to its own pace, not to three runs', () {
      // f = 7: the Seedling window expects 14 runs in 14 days, so it takes
      // seven, not three.
      final threeRuns = inputs(
        targetFrequency: 7,
        completions: completionsOn(<num>[0, 1, 2]),
      );
      final sevenRuns = inputs(
        targetFrequency: 7,
        completions: completionsOn(<num>[0, 1, 2, 3, 4, 5, 6]),
      );

      expect(computeStage(inputs: threeRuns, at: day(6)), Stage.sprout);
      expect(computeStage(inputs: sevenRuns, at: day(6)), Stage.seedling);
    });
  });

  group('a qualifying window may not start before the previous stage', () {
    // This is what makes the ladder sequential rather than concurrent, and it
    // is where the spec's "fastest possible path to bloom ~96 days" comes from.
    test('Young waits a full 19-day window after Seedling', () {
      final habit = inputs(completions: steadyThreePerWeek());

      // Seedling lands on day 4, so the 19-day Young window cannot close
      // before day 22 however good the completion record is.
      expect(computeStage(inputs: habit, at: day(4)), Stage.seedling);
      expect(computeStage(inputs: habit, at: day(21)), Stage.seedling);
      expect(computeStage(inputs: habit, at: day(22)), Stage.young);
    });

    test('Mature waits a full 28-day window after Young', () {
      final habit = inputs(completions: steadyThreePerWeek());

      expect(computeStage(inputs: habit, at: day(48)), Stage.young);
      expect(computeStage(inputs: habit, at: day(49)), Stage.mature);
    });

    test('passesGate on its own ignores history', () {
      // Without the constraint the same record satisfies every window at once.
      final habit = inputs(completions: steadyThreePerWeek());

      expect(
        passesGate(inputs: habit, stage: Stage.young, at: day(21)),
        isTrue,
      );
      expect(
        passesGate(
          inputs: habit,
          stage: Stage.young,
          at: day(21),
          notBefore: day(4),
        ),
        isFalse,
      );
    });

    test('records when each stage was earned', () {
      final progress = computeStageProgress(
        inputs: inputs(completions: steadyThreePerWeek()),
        at: day(60),
      );

      expect(progress.stage, Stage.mature);
      expect(progress.earnedAtFor(Stage.seed), isNotNull);
      expect(progress.earnedAtFor(Stage.sprout), isNotNull);
      expect(progress.earnedAtFor(Stage.bloom), isNull);
      expect(
        progress
            .earnedAtFor(Stage.young)!
            .isBefore(progress.earnedAtFor(Stage.mature)!),
        isTrue,
      );
    });
  });

  group('roots are advisory below Bloom', () {
    test('behaviour alone carries a habit to Mature', () {
      // The user who taps through every reflection still earns what his
      // completion record plainly earned.
      final habit = inputs(completions: steadyThreePerWeek());

      expect(computeStage(inputs: habit, at: day(60)), Stage.mature);
    });

    test('but the plant renders tall and shallow-rooted', () {
      expect(isShallowRooted(stage: Stage.young, roots: 0.29), isTrue);
      expect(isShallowRooted(stage: Stage.young, roots: 0.30), isFalse);
      expect(isShallowRooted(stage: Stage.mature, roots: 0.49), isTrue);
      expect(isShallowRooted(stage: Stage.mature, roots: 0.50), isFalse);
    });

    test('there is nothing to be shallow about below Seedling', () {
      expect(isShallowRooted(stage: Stage.seed, roots: 0), isFalse);
      expect(isShallowRooted(stage: Stage.sprout, roots: 0), isFalse);
      expect(isShallowRooted(stage: Stage.seedling, roots: 0), isFalse);
    });

    test('a bloomed habit cannot be shallow — the gate is hard there', () {
      expect(isShallowRooted(stage: Stage.bloom, roots: 0.75), isFalse);
    });
  });

  group('Bloom is absolute', () {
    HabitInputs bloomCandidate({
      List<Reflection>? reflections,
      List<NudgeRecord>? nudges,
    }) => inputs(
      targetFrequency: 4,
      completions: steadyFourPerWeek(),
      reflections: reflections ?? deepRoots(),
      nudges: nudges ?? fourPerWeekLedger(),
    );

    test('blooms on adherence plus roots plus autonomy', () {
      final habit = bloomCandidate();

      expect(computeStage(inputs: habit, at: day(72)), Stage.mature);
      expect(computeStage(inputs: habit, at: day(73)), Stage.bloom);
    });

    test(
      'no amount of consistency blooms a habit the user does not understand',
      () {
        final habit = bloomCandidate(reflections: const <Reflection>[]);

        expect(computeStage(inputs: habit, at: day(80)), Stage.mature);
      },
    );

    test('shallow roots block it even at c = 1', () {
      // Ten confirmations weigh 5, which lands roots at 0.56.
      final habit = bloomCandidate(
        reflections: reflectionsDaily(
          count: 10,
          from: 40,
          framing: Framing.confirmation,
        ),
      );

      expect(computeStage(inputs: habit, at: day(80)), Stage.mature);
    });

    test('a habit that only fires when prompted cannot bloom', () {
      final habit = bloomCandidate(
        nudges: nudgesOn(<num>[42, 44, 46, 48, 50], sent: true),
      );

      expect(computeStage(inputs: habit, at: day(80)), Stage.mature);
    });

    test('an unmeasured habit cannot bloom either', () {
      // No un-nudged occasions means no evidence, and no evidence is not a
      // pass — autonomy has to be demonstrated.
      final habit = bloomCandidate(nudges: const <NudgeRecord>[]);

      expect(computeStage(inputs: habit, at: day(80)), Stage.mature);
    });

    test('autonomy below 0.5 blocks it', () {
      final habit = bloomCandidate(
        nudges: autonomyLedger(
          completed: <num>[42, 44, 46, 48],
          missed: <num>[43, 45, 47, 50, 52, 54],
        ),
      );

      expect(computeStage(inputs: habit, at: day(80)), Stage.mature);
    });
  });

  group('clamp collapse — Bloom needs two consecutive windows at low f', () {
    // At f = 1 the Mature and Bloom windows both clamp to 42 days expecting 6
    // calls, and 0.75 x 6 and 0.80 x 6 both round to 5. The ladder would have
    // no top rung, so Bloom tightens with time instead: a weekly habit must
    // hold the bar for twelve weeks rather than six.
    HabitInputs weeklyHabit({required int weeks, num from = 0}) => inputs(
      targetFrequency: 1,
      completions: completionsEvery(every: 7, count: weeks, from: from),
      reflections: deepRoots(from: from + 20),
      nudges: autonomyLedger(
        completed: <num>[
          from + 7,
          from + 14,
          from + 21,
          from + 28,
          from + 35,
          from + 42,
        ],
        missed: <num>[from + 8, from + 9, from + 10, from + 11],
      ),
    );

    test('one passing window is not enough', () {
      // Six perfect weeks, and nothing at all before them.
      final habit = weeklyHabit(weeks: 7, from: 96);

      expect(
        passesGate(inputs: habit, stage: Stage.bloom, at: day(137)),
        isFalse,
      );
    });

    test('two consecutive passing windows are', () {
      final habit = weeklyHabit(weeks: 24);

      expect(
        passesGate(inputs: habit, stage: Stage.bloom, at: day(137)),
        isTrue,
      );
    });

    test('a habit above the clamp needs only the one window', () {
      // The same shape at f = 4, where the 35-day window sits under the
      // ceiling: one window of evidence is the whole requirement.
      final habit = inputs(
        targetFrequency: 4,
        completions: completionsWeekly(
          offsetsInWeek: <num>[0, 2, 4, 6],
          weeks: 5,
          from: 39,
        ),
        reflections: deepRoots(),
        nudges: autonomyLedger(
          completed: <num>[43, 45, 46, 48, 50, 52],
          missed: <num>[44, 47, 49, 51],
        ),
      );

      expect(
        passesGate(inputs: habit, stage: Stage.bloom, at: day(73)),
        isTrue,
      );
    });
  });

  group('the gate a habit is working toward', () {
    test('skips Sprout, which has no window of its own', () {
      // Sprout's gate is a raw first-completion milestone (windowReps: 0),
      // which windowDaysForReps would clamp into a phantom 14-day window
      // belonging to no gate at all.
      expect(gateInProgress(Stage.seed).windowReps, 3);
      expect(gateInProgress(Stage.sprout).windowReps, 3);
      expect(gateInProgress(Stage.seedling).windowReps, 8);
      expect(gateInProgress(Stage.young).windowReps, 12);
      expect(gateInProgress(Stage.mature).windowReps, 20);
    });

    test('a bloomed habit keeps measuring against its own gate', () {
      expect(gateInProgress(Stage.bloom).windowReps, 20);
    });
  });

  group('stage is monotonic', () {
    test('an earned stage is banked, never lost', () {
      final habit = inputs(completions: steadyThreePerWeek(weeks: 4));

      expect(computeStage(inputs: habit, at: day(25)), Stage.young);
      // Then the user disappears for two months.
      expect(computeStage(inputs: habit, at: day(90)), Stage.young);
      expect(computeStage(inputs: habit, at: day(400)), Stage.young);
    });

    test('while the underlying gate plainly stops passing', () {
      final habit = inputs(completions: steadyThreePerWeek(weeks: 4));

      expect(
        passesGate(inputs: habit, stage: Stage.young, at: day(90)),
        isFalse,
      );
    });

    test('never decreases over any random input sequence', () {
      for (var seed = 0; seed < 5; seed++) {
        final random = Random(seed);
        final completions = <Completion>[];
        final reflections = <Reflection>[];
        final nudges = <NudgeRecord>[];

        for (var d = 0; d < 120; d++) {
          if (random.nextDouble() < 0.45) completions.add(completionOn(d));
          if (random.nextDouble() < 0.2) {
            reflections.add(
              reflectionOn(
                d,
                framing: Framing.values[random.nextInt(Framing.values.length)],
                inputMode:
                    InputMode.values[random.nextInt(InputMode.values.length)],
                cueReported: 'cue ${random.nextInt(3)}',
              ),
            );
          }
          if (random.nextDouble() < 0.3) {
            nudges.add(nudgeOn(d, sent: random.nextBool()));
          }
        }

        final habit = inputs(
          targetFrequency: 1 + random.nextInt(7),
          completions: completions,
          reflections: reflections,
          nudges: nudges,
        );

        // Sampled at quarter-day steps, not whole days. Time of day is part
        // of the input space: an earlier replay grid was anchored to the
        // evaluation instant's clock time, so the stage was monotone when
        // asked at 09:00 every day and regressed when asked twice in one
        // evening.
        var previous = Stage.seed;
        for (var quarter = 0; quarter <= 130 * 4; quarter++) {
          final at = quarter / 4;
          final stage = computeStage(inputs: habit, at: day(at));
          expect(
            stage.index,
            greaterThanOrEqualTo(previous.index),
            reason: 'seed $seed regressed from $previous to $stage on day $at',
          );
          previous = stage;
        }
      }
    });
  });
}
