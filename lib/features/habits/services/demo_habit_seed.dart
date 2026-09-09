import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/runtime/runtime_providers.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/habit.dart';
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
/// The flavor check is here rather than only at the call site so this cannot
/// write to a production store by being called from the wrong place later.
Future<Habit?> plantDemoHabit({
  required HabitRepository habits,
  required String Function() newId,
  required DateTime Function() clock,
  Flavor Function() flavor = getFlavor,
}) async {
  if (flavor() != Flavor.dev) return null;

  final habit = Habit(
    id: newId(),
    name: 'Morning walk',
    identityStatement: 'I am someone who gets outside',
    plantType: 'placeholder',
    targetFrequency: 3,
    designedCue: 'after the kettle boils',
    designedCueType: CueType.event,
    routine: 'twice round the block',
    reward: 'coffee, sitting down',
    createdAt: clock(),
  );
  await habits.saveHabit(habit);
  return habit;
}

/// The seed, wired. Returns null on any flavor but dev.
final demoHabitSeedProvider = Provider<Future<Habit?> Function()>(
  (ref) =>
      () => plantDemoHabit(
        habits: ref.read(habitServiceProvider),
        newId: ref.read(newIdProvider),
        clock: ref.read(clockProvider),
      ),
);
