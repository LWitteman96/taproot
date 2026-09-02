import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/database/database_provider.dart';
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
