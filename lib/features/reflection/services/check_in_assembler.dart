import 'package:meta/meta.dart';

import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/engine/engine.dart';
import 'package:taproot/core/models/habit.dart';
import 'package:taproot/core/models/reflection.dart';
import 'package:taproot/features/habits/domain/habit_repository.dart';
import 'package:taproot/features/habits/services/habit_inputs_loader.dart';
import 'package:taproot/features/reflection/domain/check_in_scheduler.dart';
import 'package:taproot/features/reflection/domain/chip_surfacing.dart';
import 'package:taproot/features/reflection/domain/cue_families.dart';
import 'package:taproot/features/reflection/domain/daypart.dart';
import 'package:taproot/features/reflection/domain/friction_surfacing.dart';
import 'package:taproot/features/reflection/domain/occasion_detection.dart';
import 'package:taproot/features/reflection/domain/remembered_chips.dart';
import 'package:taproot/features/reflection/domain/starter_chip.dart';

/// A check-in the app is ready to show: what to ask, about what, with what to
/// tap.
@immutable
class CheckInOffer {
  const CheckInOffer({
    required this.habit,
    required this.candidate,
    required this.cueChips,
    required this.frictionChips,
    required this.isFirstReflection,
  });

  final Habit habit;
  final CheckInCandidate candidate;

  /// The cue chips to offer, pinned cue first where there is one. Empty for a
  /// Diagnosis, which asks about friction instead.
  final List<StarterChip> cueChips;

  final List<FrictionChip> frictionChips;

  /// Whether this is the habit's first reflection — the one the starter
  /// library exists for.
  final bool isFirstReflection;

  Framing get framing => candidate.framing;

  Occasion get occasion => candidate.occasion.occasion;

  bool get isDiagnosis => framing == Framing.diagnosis;
}

/// Assembles the evening check-in from the store.
///
/// The decisions all live in `domain/` as pure functions; this is the part that
/// has to talk to four repositories, and it is deliberately the only part that
/// does. It holds **no state between calls**: notification answers are written
/// by a background isolate, so a `confirmed` nudge row can land without the main
/// isolate observing the write, and a remembered ledger would be wrong exactly
/// when it mattered.
class CheckInAssembler {
  const CheckInAssembler({
    required HabitRepository habits,
    required HabitInputsLoader loader,
    required DateTime Function() clock,
  }) : _habits = habits,
       _loader = loader,
       _clock = clock;

  final HabitRepository _habits;
  final HabitInputsLoader _loader;
  final DateTime Function() _clock;

  /// The one check-in to offer now, or null — which is the usual answer.
  Future<CheckInOffer?> nextCheckIn() async {
    final now = _clock();
    final habits = await _habits.allHabits();

    final contexts = <HabitCheckInContext>[];
    final byId = <String, (Habit, List<Reflection>)>{};
    DateTime? lastCheckInAnywhere;

    for (final habit in habits) {
      // A paused habit is not asked about. Paused days are excluded from every
      // engine window because they are not misses, and diagnosing someone for
      // a day they told us about would be the app not listening.
      if (habit.isPaused) continue;

      final inputs = await _loader.load(habit.id);
      if (inputs == null) continue;

      final growth = evaluateGrowth(inputs: inputs, at: now);
      final reflections = inputs.reflections;

      for (final reflection in reflections) {
        if (lastCheckInAnywhere == null ||
            reflection.createdAt.isAfter(lastCheckInAnywhere)) {
          lastCheckInAnywhere = reflection.createdAt;
        }
      }

      contexts.add(
        HabitCheckInContext(
          habitId: habit.id,
          stage: growth.stage,
          convergence: growth.roots.convergence,
          reflectionCount: reflections.length,
          promptsThisWeek: promptsInTheLastWeek(
            reflections: reflections,
            at: now,
          ),
          occasion: occasionFor(
            habitId: habit.id,
            completions: inputs.completions,
            nudges: inputs.nudges,
            reflections: reflections,
            targetFrequency: habit.targetFrequency,
            at: now,
          ),
          lastPromptedAt: reflections.isEmpty
              ? null
              : reflections
                    .map((reflection) => reflection.createdAt)
                    .reduce((a, b) => a.isAfter(b) ? a : b),
        ),
      );
      byId[habit.id] = (habit, reflections);
    }

    final candidate = selectCheckIn(
      habits: contexts,
      now: now,
      lastCheckInAnywhere: lastCheckInAnywhere,
    );
    if (candidate == null) return null;

    final (habit, reflections) = byId[candidate.habitId]!;
    final first = isFirstReflection(reflections);

    return CheckInOffer(
      habit: habit,
      candidate: candidate,
      isFirstReflection: first,
      frictionChips: candidate.framing == Framing.diagnosis
          ? surfaceFrictionChips(habit.category)
          : const <FrictionChip>[],
      cueChips: candidate.framing == Framing.diagnosis
          ? const <StarterChip>[]
          : _cueChipsFor(
              habit: habit,
              reflections: reflections,
              isFirst: first,
              loggedAt: candidate.occasion.at,
            ),
    );
  }

  /// The chips for a cue question.
  ///
  /// The first reflection is the only one with no history to rank, so it is the
  /// only one the starter library answers. Everything after it offers the
  /// user's own past answers back (§4) — which is what makes tapping rather
  /// than typing sustainable.
  List<StarterChip> _cueChipsFor({
    required Habit habit,
    required List<Reflection> reflections,
    required bool isFirst,
    required DateTime loggedAt,
  }) {
    final family = familyForCueText(
      habit.designedCue,
      category: habit.category,
    );
    final pinned = pinnedDesignedCue(
      designedCue: habit.designedCue,
      designedCueType: habit.designedCueType,
      family: family ?? 'designed-cue',
    );

    if (!isFirst) {
      final remembered = rememberedCues(reflections: reflections);
      return <StarterChip>[
        for (final cue in remembered)
          StarterChip(cue.label, cue.cueType, 1, cue.label),
      ];
    }

    // The daypart comes from the **completion**, not from now. The evening
    // check-in asking about a 07:00 run has to rank against 07:00, or every
    // morning habit gets evening chips.
    final starters = surfaceStarterChips(
      category: habit.category,
      logged: daypartFor(loggedAt),
      designedCueFamily: family,
    );

    return <StarterChip>[
      if (pinned != null) pinned,
      for (final scored in starters.chips) scored.chip,
    ];
  }
}
