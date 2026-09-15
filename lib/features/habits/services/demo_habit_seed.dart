import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/runtime/runtime_providers.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/habit.dart';
import 'package:taproot/core/models/habit_category.dart';
import 'package:taproot/core/models/habit_journey.dart';
import 'package:taproot/core/utils/flavor.dart';
import 'package:taproot/features/habits/domain/habit_repository.dart';
import 'package:taproot/features/habits/providers/habit_providers.dart';

/// Puts one habit in the store so the watering gesture can be performed.
///
/// **This is scaffolding and is meant to be deleted.** Habit creation is a
/// later branch with a designed flow behind it — the two journeys, the
/// plant-type identity moment, the cue/routine/reward triple — and writing a
/// stand-in form now would front-run all of it. But a completion tap nobody can
/// perform is not a finished feature either: the whole point of the hold is how
/// it *feels*, and that cannot be judged from a widget test.
///
/// So: a dev-flavor button that plants one habit, and nothing else. It seeds no
/// history — the plant starts at Seed with no completions, which makes the
/// first watering visibly move it a rung, which is the thing worth watching.
///
/// The guard is here rather than only at the call site so this cannot write to
/// a production store by being called from the wrong place later — see
/// [isDemoSeedEnabled] for why the flavor alone is not enough to do that job.
Future<Habit?> plantDemoHabit({
  required HabitRepository habits,
  required String Function() newId,
  required DateTime Function() clock,
  Flavor Function() flavor = getFlavor,
  bool isDebug = kDebugMode,
}) async {
  if (!isDemoSeedEnabled(flavor: flavor, isDebug: isDebug)) return null;

  final habit = Habit(
    id: newId(),
    name: 'Morning walk',
    identityStatement: 'I am someone who gets outside',
    plantType: 'placeholder',
    targetFrequency: 3,
    // The loop is written out below, so this is a Journey B habit — the seed
    // stands in for a habit someone designed, not one they already had.
    journey: HabitJourney.design,
    category: HabitCategory.walking,
    designedCue: 'after the kettle boils',
    designedCueType: CueType.event,
    routine: 'twice round the block',
    reward: 'coffee, sitting down',
    createdAt: clock(),
  );
  await habits.saveHabit(habit);
  return habit;
}

/// Whether the demo seed is allowed to run at all.
///
/// The flavor on its own is not a guard, and the doc above used to claim more
/// than it delivered. [getFlavor] falls back to [Flavor.dev] whenever
/// `appFlavor` is unset, which is every build not launched with `--flavor` —
/// so "dev" currently means "nobody said", not "this is the dev build", and a
/// release build made without the flag would have shipped the seed button on
/// the empty garden.
///
/// [kDebugMode] is the half that cannot be got wrong by a forgotten flag: it is
/// a compile-time constant the release build sets to false, and it tree-shakes
/// the seed out of the binary entirely. The flavor check stays alongside it, so
/// that once the flavors are genuinely wired a *debug* stg or prod build is
/// excluded too.
bool isDemoSeedEnabled({
  Flavor Function() flavor = getFlavor,
  bool isDebug = kDebugMode,
}) => isDebug && flavor() == Flavor.dev;

/// The seed, wired. Returns null anywhere [isDemoSeedEnabled] is false.
final demoHabitSeedProvider = Provider<Future<Habit?> Function()>(
  (ref) =>
      () => plantDemoHabit(
        habits: ref.read(habitServiceProvider),
        newId: ref.read(newIdProvider),
        clock: ref.read(clockProvider),
      ),
);
