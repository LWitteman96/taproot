import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:taproot/app/database/database_provider.dart';
import 'package:taproot/core/models/habit.dart';
import 'package:taproot/features/habits/domain/completion_repository.dart';
import 'package:taproot/features/habits/domain/habit_repository.dart';
import 'package:taproot/features/habits/services/habit_inputs_loader.dart';
import 'package:taproot/features/habits/services/local_completion_service.dart';
import 'package:taproot/features/habits/services/local_habit_service.dart';
import 'package:taproot/features/notifications/providers/nudge_providers.dart';
import 'package:taproot/features/reflection/providers/reflection_providers.dart';

/// Habits, backed by the local store.
///
/// Typed as the interface so a test can swap in `FakeHabitService`, and so the
/// Supabase-backed implementation can be layered in later without any caller
/// changing.
final habitServiceProvider = Provider<HabitRepository>(
  (ref) => LocalHabitService(database: ref.watch(appDatabaseProvider)),
);

final completionServiceProvider = Provider<CompletionRepository>(
  (ref) => LocalCompletionService(database: ref.watch(appDatabaseProvider)),
);

/// The seam between the store and the pure engine.
final habitInputsLoaderProvider = Provider<HabitInputsLoader>(
  (ref) => HabitInputsLoader(
    habits: ref.watch(habitServiceProvider),
    completions: ref.watch(completionServiceProvider),
    reflections: ref.watch(reflectionServiceProvider),
    nudges: ref.watch(nudgeServiceProvider),
  ),
);

/// Where a new habit's id comes from.
///
/// Generated client-side *before* the insert, the same way a completion's is,
/// so that two devices creating habits offline merge as a union.
final habitIdGeneratorProvider = Provider<String Function()>(
  (ref) => const Uuid().v4,
);

/// The clock a newly created habit is stamped from.
///
/// A seam, for the same reason the services take one: `created_at` is what
/// every engine window measures from for a habit that has never been watered
/// (growth-engine §10), so a test needs to be able to put it where it wants it.
final creationClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Every live habit.
///
/// The entry gate reads this to decide whether there is a garden to show, and
/// it is invalidated when a habit is created. Autodisposing so that the list is
/// re-read rather than served stale after the store changes underneath it.
final habitsProvider = FutureProvider.autoDispose<List<Habit>>(
  (ref) => ref.watch(habitServiceProvider).allHabits(),
);
