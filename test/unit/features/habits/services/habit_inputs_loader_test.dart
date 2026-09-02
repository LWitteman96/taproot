import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/app/database/app_database.dart';
import 'package:taproot/app/database/database_provider.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/engine/engine.dart';
import 'package:taproot/features/habits/providers/habit_providers.dart';
import 'package:taproot/features/habits/services/habit_inputs_loader.dart';
import 'package:taproot/features/habits/services/local_completion_service.dart';
import 'package:taproot/features/habits/services/local_habit_service.dart';
import 'package:taproot/features/notifications/services/local_nudge_service.dart';
import 'package:taproot/features/reflection/services/local_reflection_service.dart';

import '../../../../utils/engine_builders.dart';
import '../../../../utils/store_fixtures.dart';

/// The end-to-end check that the store can actually drive the engine.
///
/// The engine's own tests build `HabitInputs` by hand. These build the same
/// inputs by writing rows and reading them back, so a wrong column, a lost
/// timezone or a dropped ledger row shows up as a different stage rather than
/// as a green suite.
void main() {
  late Database database;
  late TestClock clock;
  late HabitInputsLoader loader;
  late LocalHabitService habits;
  late LocalCompletionService completions;
  late LocalReflectionService reflections;
  late LocalNudgeService nudges;

  setUp(() async {
    resetFixtureIds();
    database = await openTestDatabase();
    clock = TestClock(habitCreatedAt);
    habits = LocalHabitService(database: database, clock: clock.call);
    completions = LocalCompletionService(database: database, clock: clock.call);
    reflections = LocalReflectionService(database: database, clock: clock.call);
    nudges = LocalNudgeService(database: database, clock: clock.call);
    loader = HabitInputsLoader(
      habits: habits,
      completions: completions,
      reflections: reflections,
      nudges: nudges,
    );
    await habits.saveHabit(
      testHabit(id: testHabitId, targetFrequency: 3, createdAt: habitCreatedAt),
    );
  });

  tearDown(() => database.close());

  test('an unknown habit loads as null', () async {
    expect(await loader.load('never-existed'), isNull);
  });

  test('carries the habit\'s anchor values', () async {
    final inputs = await loader.load(testHabitId);

    expect(inputs!.habitId, testHabitId);
    expect(inputs.targetFrequency, 3);
    expect(inputs.createdAt.isAtSameMomentAs(habitCreatedAt), isTrue);
    expect(inputs.expectedGapDays, closeTo(7 / 3, 1e-9));
  });

  test(
    'reproduces the spec\'s Young worked example through the store',
    () async {
      // Same fixture as the engine's worked-example test: a seedling on day 2,
      // then five runs inside the 19-day window that opens on day 6.
      for (final completion in completionsOn(<num>[
        0,
        1,
        2,
        6,
        11,
        16,
        21,
        24,
      ])) {
        await completions.recordCompletion(completion);
      }

      final inputs = await loader.load(testHabitId);

      expect(evaluateGrowth(inputs: inputs!, at: day(24)).stage, Stage.young);
    },
  );

  test('one fewer completion is still a seedling', () async {
    for (final completion in completionsOn(<num>[0, 1, 2, 6, 11, 16, 21])) {
      await completions.recordCompletion(completion);
    }

    final inputs = await loader.load(testHabitId);

    expect(evaluateGrowth(inputs: inputs!, at: day(24)).stage, Stage.seedling);
  });

  test('an undone completion is gone from the engine\'s inputs', () async {
    for (final completion in completionsOn(<num>[0, 1, 2])) {
      await completions.recordCompletion(completion);
    }
    final undone = (await completions.completionsFor(testHabitId)).last;
    clock.now = undone.completedAt;

    await completions.retractCompletion(testHabitId, undone.id);

    expect((await loader.load(testHabitId))!.completions, hasLength(2));
  });

  test('undoing the completion that earned a stage un-earns it', () async {
    // The ladder is a replay over history, so shrinking the history replays a
    // lower stage. This is the accepted cost of an honest undo: the window is
    // one local day, so the regression can only ever undo something the user
    // earned in the same day they are correcting.
    for (final completion in completionsOn(<num>[0, 1, 2, 6, 11, 16, 21, 24])) {
      await completions.recordCompletion(completion);
    }
    expect(
      evaluateGrowth(
        inputs: (await loader.load(testHabitId))!,
        at: day(24),
      ).stage,
      Stage.young,
    );

    final undone = (await completions.completionsFor(testHabitId)).last;
    clock.now = undone.completedAt;
    await completions.retractCompletion(testHabitId, undone.id);

    expect(
      evaluateGrowth(
        inputs: (await loader.load(testHabitId))!,
        at: day(24),
      ).stage,
      Stage.seedling,
    );
  });

  test('loads the whole nudge ledger, silent occasions included', () async {
    // Autonomy is un-nudged completions over un-nudged expected occasions. If
    // the loader dropped the silent rows the denominator would collapse.
    for (final nudge in nudgesOn(<num>[0, 2, 4, 6], sent: false)) {
      await nudges.saveNudge(nudge);
    }
    for (final completion in completionsOn(<num>[0, 2, 4])) {
      await completions.recordCompletion(completion);
    }

    final inputs = await loader.load(testHabitId);

    expect(inputs!.nudges, hasLength(4));
    expect(inputs.nudges.every((nudge) => !nudge.sent), isTrue);
    expect(evaluateGrowth(inputs: inputs, at: day(7)).autonomy.occasions, 4);
  });

  test(
    'loads reflections unfiltered, so convergence sees the last eight',
    () async {
      for (final reflection in reflectionsDaily(count: 10)) {
        await reflections.saveReflection(reflection);
      }

      final inputs = await loader.load(testHabitId);

      expect(inputs!.reflections, hasLength(10));
    },
  );

  test('loads pauses as intervals the engine can exclude', () async {
    clock.now = day(5);
    await habits.pauseHabit(testHabitId);
    clock.now = day(12);
    await habits.resumeHabit(testHabitId);

    final inputs = await loader.load(testHabitId);

    expect(inputs!.pauses, hasLength(1));
    expect(inputs.pauses.single.startedAt.isAtSameMomentAs(day(5)), isTrue);
    expect(inputs.pauses.single.endedAt!.isAtSameMomentAs(day(12)), isTrue);
  });

  test('resolves off the provider graph', () async {
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);

    final fromProvider = container.read(habitInputsLoaderProvider);

    expect((await fromProvider.load(testHabitId))!.targetFrequency, 3);
  });
}
