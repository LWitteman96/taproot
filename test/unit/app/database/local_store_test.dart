import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/app/database/app_database.dart';
import 'package:taproot/app/database/database_provider.dart';
import 'package:taproot/core/models/completion.dart';
import 'package:taproot/features/habits/domain/completion_repository.dart';
import 'package:taproot/features/habits/domain/habit_repository.dart';
import 'package:taproot/features/habits/providers/habit_providers.dart';
import 'package:taproot/features/habits/services/local_completion_service.dart';
import 'package:taproot/features/habits/services/local_habit_service.dart';
import 'package:taproot/features/notifications/domain/nudge_repository.dart';
import 'package:taproot/features/notifications/providers/nudge_providers.dart';
import 'package:taproot/features/notifications/services/local_nudge_service.dart';
import 'package:taproot/features/reflection/domain/reflection_repository.dart';
import 'package:taproot/features/reflection/providers/reflection_providers.dart';
import 'package:taproot/features/reflection/services/local_reflection_service.dart';

import '../../../utils/store_contract.dart';
import '../../../utils/store_fixtures.dart';

void main() {
  group('SQLite store', () {
    storeContract((clock) async {
      final database = await openTestDatabase();
      return TestStore(
        habits: LocalHabitService(database: database, clock: clock.call),
        completions: LocalCompletionService(
          database: database,
          clock: clock.call,
        ),
        reflections: LocalReflectionService(
          database: database,
          clock: clock.call,
        ),
        nudges: LocalNudgeService(database: database, clock: clock.call),
        clock: clock,
        dispose: database.close,
      );
    });
  });

  group('sync plumbing', () {
    late Database database;
    late TestClock clock;
    late LocalHabitService habits;
    late LocalCompletionService completions;

    setUp(() async {
      database = await openTestDatabase();
      clock = TestClock(DateTime(2026, 1, 5, 9));
      habits = LocalHabitService(database: database, clock: clock.call);
      completions = LocalCompletionService(
        database: database,
        clock: clock.call,
      );
      await habits.saveHabit(testHabit());
    });

    tearDown(() => database.close());

    Future<Map<String, Object?>> habitRow() async => (await database.query(
      AppSchema.habits,
      where: 'id = ?',
      whereArgs: <Object?>['habit-1'],
    )).single;

    test('a saved habit is queued for sync and stamped', () async {
      final row = await habitRow();

      expect(row['pending_sync'], 1);
      expect(row['updated_at'], clock.now.toUtc().toIso8601String());
      expect(row['deleted_at'], isNull);
    });

    test('a deleted habit is a tombstone, still queued for sync', () async {
      clock.advance(const Duration(days: 1));

      await habits.deleteHabit('habit-1');

      final row = await habitRow();
      expect(row['deleted_at'], clock.now.toUtc().toIso8601String());
      expect(row['pending_sync'], 1);
    });

    test('a completion is queued for sync', () async {
      await completions.recordCompletion(
        Completion(id: 'c-1', habitId: 'habit-1', completedAt: clock.now),
      );

      final row = (await database.query(AppSchema.completions)).single;
      expect(row['pending_sync'], 1);
    });

    test('an undo is queued for sync and stamped', () async {
      await completions.recordCompletion(
        Completion(id: 'c-1', habitId: 'habit-1', completedAt: clock.now),
      );
      clock.advance(const Duration(minutes: 5));

      await completions.retractCompletion('habit-1', 'c-1');

      final row = (await database.query(
        AppSchema.completionRetractions,
      )).single;
      expect(row['completion_id'], 'c-1');
      expect(row['retracted_at'], clock.now.toUtc().toIso8601String());
      expect(row['pending_sync'], 1);
      // The completion row itself is untouched — it is still an event that was
      // recorded, and the retraction is the thing that says it did not count.
      expect(await database.query(AppSchema.completions), hasLength(1));
    });

    test('a pause opens and closes one habit_pauses row', () async {
      await habits.pauseHabit('habit-1');
      clock.advance(const Duration(days: 3));
      await habits.resumeHabit('habit-1');

      final row = (await database.query(AppSchema.habitPauses)).single;
      expect(row['habit_id'], 'habit-1');
      expect(row['ended_at'], clock.now.toUtc().toIso8601String());
      expect(row['pending_sync'], 1);
    });

    test('a failed pause leaves no half-written interval', () async {
      // Pause and resume touch two tables; if the habit stamp and the interval
      // could diverge, paused days would stop lining up with the pause ledger
      // and the engine would count a miss on a day the user had paused.
      await expectLater(habits.pauseHabit('never-existed'), throwsA(anything));

      expect(await database.query(AppSchema.habitPauses), isEmpty);
    });
  });

  group('providers', () {
    test(
      'resolve the local implementations off the database provider',
      () async {
        final database = await openTestDatabase();
        addTearDown(database.close);

        final container = ProviderContainer(
          overrides: [appDatabaseProvider.overrideWithValue(database)],
        );
        addTearDown(container.dispose);

        expect(container.read(habitServiceProvider), isA<HabitRepository>());
        expect(container.read(habitServiceProvider), isA<LocalHabitService>());
        expect(
          container.read(completionServiceProvider),
          isA<CompletionRepository>(),
        );
        expect(
          container.read(reflectionServiceProvider),
          isA<ReflectionRepository>(),
        );
        expect(container.read(nudgeServiceProvider), isA<NudgeRepository>());
      },
    );

    test('the database provider is unreadable until startup has opened it', () {
      // The handle is derived from openedDatabaseProvider rather than injected,
      // so a read before the open finishes is a programming error rather than a
      // silent null. Startup's loading and error screens are what stop callers
      // ever getting here — see test/unit/app/startup/app_startup_test.dart.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Riverpod wraps anything a provider throws, and the wrapper is not part
      // of its public API, so this asserts on the message rather than the type.
      expect(
        () => container.read(appDatabaseProvider),
        throwsA(
          isA<Object>().having(
            (error) => error.toString(),
            'toString',
            contains('AsyncValueIsLoadingException'),
          ),
        ),
      );
    });
  });
}
