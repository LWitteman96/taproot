import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/runtime/runtime_providers.dart';
import 'package:taproot/features/habits/providers/habit_providers.dart';
import 'package:taproot/features/reflection/services/check_in_assembler.dart';

import 'package:taproot/app/database/database_provider.dart';
import 'package:taproot/features/reflection/domain/reflection_repository.dart';
import 'package:taproot/features/reflection/services/local_reflection_service.dart';

final reflectionServiceProvider = Provider<ReflectionRepository>(
  (ref) => LocalReflectionService(database: ref.watch(appDatabaseProvider)),
);

/// Assembles the evening check-in from the four repositories.
///
/// Read rather than watched by the controller, and holding no state of its own:
/// the nudge ledger can be written by a background isolate, so anything
/// remembered between check-ins would be wrong exactly when it mattered.
final checkInAssemblerProvider = Provider<CheckInAssembler>(
  (ref) => CheckInAssembler(
    habits: ref.watch(habitServiceProvider),
    loader: ref.watch(habitInputsLoaderProvider),
    clock: ref.watch(clockProvider),
  ),
);
