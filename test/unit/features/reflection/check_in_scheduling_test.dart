import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/features/reflection/domain/check_in_scheduler.dart';
import 'package:taproot/features/reflection/domain/framing_selection.dart';
import 'package:taproot/features/reflection/domain/reflection_priority.dart';

void main() {
  final now = DateTime(2026, 3, 2, 20, 30);

  CheckInOccasion occasionOf(
    Occasion occasion, {
    String habitId = 'habit-1',
    bool isAnomalous = false,
  }) => CheckInOccasion(
    habitId: habitId,
    occasion: occasion,
    at: now.subtract(const Duration(hours: 12)),
    isAnomalous: isAnomalous,
  );

  group('what to ask — reflection-logic §3', () {
    test('an early completion asks whether the designed cue fired', () {
      for (final stage in <Stage>[Stage.seed, Stage.sprout, Stage.seedling]) {
        expect(
          framingFor(
            occasion: Occasion.completion,
            stage: stage,
            convergence: 0,
          ),
          Framing.validation,
          reason: stage.name,
        );
      }
    });

    test('a later completion discovers until the cue settles', () {
      expect(
        framingFor(
          occasion: Occasion.completion,
          stage: Stage.young,
          convergence: 0.59,
        ),
        Framing.discovery,
      );
    });

    test('a settled cue only asks for confirmation', () {
      // The one-tap degenerate case of Discovery. Without it, late-stage
      // reflection is either annoying or abandoned.
      expect(
        framingFor(
          occasion: Occasion.completion,
          stage: Stage.young,
          convergence: 0.6,
        ),
        Framing.confirmation,
      );
      expect(
        framingFor(
          occasion: Occasion.completion,
          stage: Stage.bloom,
          convergence: 0.95,
        ),
        Framing.confirmation,
      );
    });

    test('an un-nudged completion outranks every stage rule', () {
      // A completion nobody asked for is the richest occasion the app gets;
      // asking about it as though it were ordinary throws that away.
      for (final stage in Stage.values) {
        expect(
          framingFor(
            occasion: Occasion.autonomyCompletion,
            stage: stage,
            convergence: 0.99,
          ),
          Framing.autonomy,
          reason: stage.name,
        );
      }
    });

    test('a miss is always diagnosed, never scolded', () {
      for (final stage in Stage.values) {
        expect(
          framingFor(occasion: Occasion.miss, stage: stage, convergence: 0.99),
          Framing.diagnosis,
        );
      }
    });
  });

  group('when to ask — reflection-logic §2', () {
    double priorityOf({
      required Occasion occasion,
      double convergence = 1,
      int reflectionCount = 10,
      bool isAnomalous = false,
      DateTime? lastPromptedAt,
    }) => reflectionPriority(
      occasion: occasionOf(occasion, isAnomalous: isAnomalous),
      convergence: convergence,
      reflectionCount: reflectionCount,
      lastPromptedAt: lastPromptedAt,
      now: now,
    );

    test('an unknown cue is worth asking about on its own', () {
      // uncertainty = 1 − c, so a habit whose cue is a mystery clears the 0.5
      // bar without needing anything else to have happened.
      expect(
        priorityOf(occasion: Occasion.completion, convergence: 0),
        closeTo(1.0, 1e-9),
      );
      expect(
        priorityOf(occasion: Occasion.completion, convergence: 1),
        closeTo(0, 1e-9),
      );
    });

    test('a miss and an un-nudged completion carry their own weight', () {
      expect(priorityOf(occasion: Occasion.miss), closeTo(0.5, 1e-9));
      expect(
        priorityOf(occasion: Occasion.autonomyCompletion),
        closeTo(0.6, 1e-9),
      );
      expect(priorityOf(occasion: Occasion.completion), closeTo(0, 1e-9));
    });

    test('an anomaly adds its weight', () {
      expect(
        priorityOf(occasion: Occasion.completion, isAnomalous: true),
        closeTo(0.3, 1e-9),
      );
    });

    test('being asked recently costs half a point, for 48 hours', () {
      expect(
        priorityOf(
          occasion: Occasion.miss,
          lastPromptedAt: now.subtract(const Duration(hours: 47)),
        ),
        closeTo(0, 1e-9),
      );
      expect(
        priorityOf(
          occasion: Occasion.miss,
          lastPromptedAt: now.subtract(const Duration(hours: 49)),
        ),
        closeTo(0.5, 1e-9),
      );
    });

    group('the early bonus', () {
      test('decays to nothing by the fifth reflection', () {
        expect(earlyReflectionBonus(0), closeTo(0.4, 1e-9));
        expect(earlyReflectionBonus(1), closeTo(0.32, 1e-9));
        expect(earlyReflectionBonus(4), closeTo(0.08, 1e-9));
        expect(earlyReflectionBonus(5), 0);
        expect(earlyReflectionBonus(50), 0);
      });

      test('never steps off a cliff', () {
        // The flat reading of "+0.4 while n < 5" drops the whole bonus in one
        // step, which can silence a habit exactly when the user has started
        // answering. Each step here is at most 0.08.
        for (var count = 0; count < 5; count++) {
          expect(
            earlyReflectionBonus(count) - earlyReflectionBonus(count + 1),
            lessThanOrEqualTo(0.08 + 1e-9),
          );
        }
      });
    });
  });

  group('is this occasion unusual', () {
    test('a gap of twice the expected one is', () {
      // f = 7 means an expected gap of one day, so three days is unusual.
      expect(
        isAnomalousOccasion(
          at: DateTime(2026, 3, 4, 9),
          previousCompletions: <DateTime>[DateTime(2026, 3, 1, 9)],
          targetFrequency: 7,
        ),
        isTrue,
      );
      expect(
        isAnomalousOccasion(
          at: DateTime(2026, 3, 2, 9),
          previousCompletions: <DateTime>[DateTime(2026, 3, 1, 9)],
          targetFrequency: 7,
        ),
        isFalse,
      );
    });

    test('a completion at an unfamiliar hour is', () {
      final mornings = <DateTime>[
        DateTime(2026, 3, 1, 7),
        DateTime(2026, 3, 2, 7, 30),
        DateTime(2026, 3, 3, 7, 15),
      ];

      expect(
        isAnomalousOccasion(
          at: DateTime(2026, 3, 4, 22),
          previousCompletions: mornings,
          targetFrequency: 7,
        ),
        isTrue,
      );
      expect(
        isAnomalousOccasion(
          at: DateTime(2026, 3, 4, 7, 5),
          previousCompletions: mornings,
          targetFrequency: 7,
        ),
        isFalse,
      );
    });

    test('nothing is unusual before there is a shape to compare against', () {
      expect(
        isAnomalousOccasion(
          at: DateTime(2026, 3, 2, 22),
          previousCompletions: const <DateTime>[],
          targetFrequency: 3,
        ),
        isFalse,
      );
      // One prior completion gives a gap to measure but no modal hour.
      expect(
        isAnomalousOccasion(
          at: DateTime(2026, 3, 2, 22),
          previousCompletions: <DateTime>[DateTime(2026, 3, 2, 7)],
          targetFrequency: 7,
        ),
        isFalse,
      );
    });
  });

  group('choosing the one check-in', () {
    HabitCheckInContext contextOf({
      String habitId = 'habit-1',
      Stage stage = Stage.young,
      double convergence = 0,
      int reflectionCount = 10,
      int promptsThisWeek = 0,
      Occasion? occasion = Occasion.completion,
      DateTime? lastPromptedAt,
    }) => HabitCheckInContext(
      habitId: habitId,
      stage: stage,
      convergence: convergence,
      reflectionCount: reflectionCount,
      promptsThisWeek: promptsThisWeek,
      occasion: occasion == null
          ? null
          : occasionOf(occasion, habitId: habitId),
      lastPromptedAt: lastPromptedAt,
    );

    test('most days there is nothing to ask', () {
      // A settled habit that just did the thing teaches nothing by being asked.
      expect(
        selectCheckIn(
          habits: <HabitCheckInContext>[contextOf(convergence: 1)],
          now: now,
        ),
        isNull,
      );
    });

    test('a habit with no occasion is not asked about', () {
      expect(
        selectCheckIn(
          habits: <HabitCheckInContext>[contextOf(occasion: null)],
          now: now,
        ),
        isNull,
      );
    });

    test('below the threshold, nothing is offered', () {
      // c = 0.6 gives uncertainty 0.4, under the 0.5 bar on its own.
      expect(
        selectCheckIn(
          habits: <HabitCheckInContext>[contextOf(convergence: 0.6)],
          now: now,
        ),
        isNull,
      );
      expect(
        selectCheckIn(
          habits: <HabitCheckInContext>[contextOf(convergence: 0.5)],
          now: now,
        ),
        isNotNull,
      );
    });

    test('one check-in a day, across the whole app', () {
      // §1 gives the app one consistent conversational slot, not one per plant.
      final habits = <HabitCheckInContext>[
        contextOf(habitId: 'a'),
        contextOf(habitId: 'b'),
      ];

      expect(
        selectCheckIn(
          habits: habits,
          now: now,
          lastCheckInAnywhere: now.subtract(const Duration(hours: 23)),
        ),
        isNull,
      );
      expect(
        selectCheckIn(
          habits: habits,
          now: now,
          lastCheckInAnywhere: now.subtract(const Duration(hours: 25)),
        ),
        isNotNull,
      );
    });

    test('a habit out of weekly budget is skipped, not the whole check-in', () {
      final chosen = selectCheckIn(
        habits: <HabitCheckInContext>[
          contextOf(habitId: 'spent', promptsThisWeek: 3),
          contextOf(habitId: 'fresh'),
        ],
        now: now,
      );

      expect(chosen?.habitId, 'fresh');
    });

    test('the budget fades by stage', () {
      // Bloom gets roughly one a month; two this week is already over.
      expect(
        selectCheckIn(
          habits: <HabitCheckInContext>[
            contextOf(stage: Stage.bloom, promptsThisWeek: 1),
          ],
          now: now,
        ),
        isNull,
      );
      expect(
        selectCheckIn(
          habits: <HabitCheckInContext>[
            contextOf(stage: Stage.mature, promptsThisWeek: 1),
          ],
          now: now,
        ),
        isNotNull,
      );
    });

    test('the richest occasion wins when several clear the bar', () {
      final chosen = selectCheckIn(
        habits: <HabitCheckInContext>[
          contextOf(habitId: 'ordinary'),
          contextOf(
            habitId: 'un-nudged',
            occasion: Occasion.autonomyCompletion,
          ),
        ],
        now: now,
      );

      expect(chosen?.habitId, 'un-nudged');
      expect(chosen?.framing, Framing.autonomy);
    });

    test(
      'a recently asked habit loses to a quieter one rather than going silent',
      () {
        // The recency penalty is a score term, not a gate — that is the whole
        // difference between protecting the ritual and suppressing a habit.
        // Both occasions are ordinary completions, so the penalty is the only
        // thing separating them: 1.0 against 1.0 − 0.5.
        final chosen = selectCheckIn(
          habits: <HabitCheckInContext>[
            contextOf(
              habitId: 'asked-yesterday',
              lastPromptedAt: now.subtract(const Duration(hours: 30)),
            ),
            contextOf(habitId: 'quiet'),
          ],
          now: now,
        );
        expect(chosen?.habitId, 'quiet');

        // On its own it is still offered: 0.5 reaches the bar exactly.
        final alone = selectCheckIn(
          habits: <HabitCheckInContext>[
            contextOf(
              habitId: 'asked-yesterday',
              lastPromptedAt: now.subtract(const Duration(hours: 30)),
            ),
          ],
          now: now,
        );
        expect(alone?.habitId, 'asked-yesterday');
      },
    );

    test('the same inputs always produce the same question', () {
      // Ties break on habit id rather than on whichever the store listed first.
      final habits = <HabitCheckInContext>[
        contextOf(habitId: 'b'),
        contextOf(habitId: 'a'),
      ];

      expect(selectCheckIn(habits: habits, now: now)?.habitId, 'a');
      expect(
        selectCheckIn(habits: habits.reversed.toList(), now: now)?.habitId,
        'a',
      );
    });
  });
}
