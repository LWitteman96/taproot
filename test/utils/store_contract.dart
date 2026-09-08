import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/app/database/store_exceptions.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/completion.dart';
import 'package:taproot/core/models/nudge.dart';
import 'package:taproot/core/models/reflection.dart';
import 'package:taproot/features/habits/domain/completion_repository.dart';
import 'package:taproot/features/habits/domain/habit_repository.dart';
import 'package:taproot/features/notifications/domain/nudge_repository.dart';
import 'package:taproot/features/reflection/domain/reflection_repository.dart';
import 'package:taproot/core/utils/local_dates.dart';

import 'store_fixtures.dart';

/// One opened store, whichever implementation is under test.
class TestStore {
  TestStore({
    required this.habits,
    required this.completions,
    required this.reflections,
    required this.nudges,
    required this.clock,
    required this.dispose,
  });

  final HabitRepository habits;
  final CompletionRepository completions;
  final ReflectionRepository reflections;
  final NudgeRepository nudges;
  final TestClock clock;
  final Future<void> Function() dispose;
}

typedef StoreOpener = Future<TestStore> Function(TestClock clock);

/// The behaviour every repository implementation owes its callers.
///
/// Both the SQLite services and the in-memory fakes in `test/utils/` are run
/// through this, because a fake that quietly disagrees with the real store is
/// worse than no fake at all — it makes feature tests pass against behaviour
/// the app does not have.
void storeContract(StoreOpener open) {
  late TestStore store;
  late TestClock clock;
  final DateTime startOfTest = DateTime(2026, 1, 5, 9);

  setUp(() async {
    clock = TestClock(startOfTest);
    store = await open(clock);
  });

  tearDown(() => store.dispose());

  Future<void> seedHabit({
    String id = 'habit-1',
    int targetFrequency = 3,
    DateTime? createdAt,
  }) => store.habits.saveHabit(
    testHabit(
      id: id,
      targetFrequency: targetFrequency,
      createdAt: createdAt ?? startOfTest,
    ),
  );

  group('HabitRepository', () {
    test('saves a habit and reads every field back', () async {
      await store.habits.saveHabit(testHabit());

      final restored = await store.habits.habitById('habit-1');

      expect(restored, isNotNull);
      expect(restored!.name, 'Morning run');
      expect(restored.identityStatement, 'I am someone who runs');
      expect(restored.plantType, 'oak');
      expect(restored.targetFrequency, 3);
      expect(restored.designedCue, 'after breakfast');
      expect(restored.designedCueType, CueType.event);
      expect(restored.routine, 'a 20 minute loop');
      expect(restored.reward, 'coffee on the porch');
      expect(restored.createdAt.isAtSameMomentAs(startOfTest), isTrue);
      expect(restored.pausedAt, isNull);
      expect(restored.graduatedAt, isNull);
    });

    test('an unknown id reads back as null rather than throwing', () async {
      expect(await store.habits.habitById('nope'), isNull);
    });

    test('saving the same id twice updates in place', () async {
      await store.habits.saveHabit(testHabit());
      await store.habits.saveHabit(testHabit(name: 'Evening run'));

      final all = await store.habits.allHabits();

      expect(all, hasLength(1));
      expect(all.single.name, 'Evening run');
    });

    test('lists habits oldest first', () async {
      await store.habits.saveHabit(
        testHabit(id: 'b', createdAt: startOfTest.add(const Duration(days: 2))),
      );
      await store.habits.saveHabit(testHabit(id: 'a', createdAt: startOfTest));

      expect(
        (await store.habits.allHabits()).map((habit) => habit.id),
        <String>['a', 'b'],
      );
    });

    test('deleting hides the habit without losing the row', () async {
      await seedHabit();
      clock.advance(const Duration(days: 1));

      await store.habits.deleteHabit('habit-1');

      expect(await store.habits.habitById('habit-1'), isNull);
      expect(await store.habits.allHabits(), isEmpty);
    });

    test('saving a stale copy cannot clear a running pause', () async {
      // The regression that motivated dropping the paused_at column: an edit
      // form holding a habit loaded before the pause used to write pausedAt:
      // null straight over it, leaving the interval open. The habit then read
      // as unpaused (so nothing offered Resume) while the engine saw an open
      // interval and treated every following day as paused — vitality frozen,
      // with no way back through the public API.
      await seedHabit();
      await store.habits.pauseHabit('habit-1');
      final stale = testHabit(createdAt: startOfTest);
      expect(stale.pausedAt, isNull);

      await store.habits.saveHabit(stale.copyWith(name: 'Evening run'));

      final habit = await store.habits.habitById('habit-1');
      expect(habit!.name, 'Evening run');
      expect(habit.isPaused, isTrue, reason: 'the pause ledger is the truth');
      expect((await store.habits.pausesFor('habit-1')).single.isOpen, isTrue);
    });

    test(
      'pause state is read back from the ledger, not from what was saved',
      () async {
        await seedHabit();
        clock.advance(const Duration(days: 4));

        // A habit claiming to be paused, saved while no interval is open.
        await store.habits.saveHabit(
          testHabit(createdAt: startOfTest, pausedAt: clock.now),
        );

        expect((await store.habits.habitById('habit-1'))!.isPaused, isFalse);
        expect(await store.habits.pausesFor('habit-1'), isEmpty);
      },
    );

    test(
      'saving a deleted habit is a typed exception, not a silent no-op',
      () async {
        await seedHabit();
        await store.habits.deleteHabit('habit-1');

        expect(
          () => store.habits.saveHabit(testHabit(name: 'Back from the dead')),
          throwsA(isA<UnknownHabitException>()),
        );
        expect(await store.habits.habitById('habit-1'), isNull);
      },
    );

    test('deleting is idempotent, and unknown ids are a no-op', () async {
      await seedHabit();

      await store.habits.deleteHabit('habit-1');

      await expectLater(store.habits.deleteHabit('habit-1'), completes);
      await expectLater(store.habits.deleteHabit('never-existed'), completes);
    });

    test('pausing stamps the habit and opens an interval', () async {
      await seedHabit();
      clock.advance(const Duration(days: 10));
      final pausedAt = clock.now;

      await store.habits.pauseHabit('habit-1');

      final habit = await store.habits.habitById('habit-1');
      expect(habit!.isPaused, isTrue);
      expect(habit.pausedAt!.isAtSameMomentAs(pausedAt), isTrue);

      final pauses = await store.habits.pausesFor('habit-1');
      expect(pauses, hasLength(1));
      expect(pauses.single.isOpen, isTrue);
      expect(pauses.single.startedAt.isAtSameMomentAs(pausedAt), isTrue);
    });

    test(
      'pausing an already-paused habit does not open a second interval',
      () async {
        await seedHabit();
        await store.habits.pauseHabit('habit-1');
        final firstPause = clock.now;
        clock.advance(const Duration(days: 3));

        await store.habits.pauseHabit('habit-1');

        final pauses = await store.habits.pausesFor('habit-1');
        expect(pauses, hasLength(1));
        expect(pauses.single.startedAt.isAtSameMomentAs(firstPause), isTrue);
      },
    );

    test('resuming closes the interval and clears the stamp', () async {
      await seedHabit();
      await store.habits.pauseHabit('habit-1');
      clock.advance(const Duration(days: 7));
      final resumedAt = clock.now;

      await store.habits.resumeHabit('habit-1');

      expect((await store.habits.habitById('habit-1'))!.isPaused, isFalse);
      final pauses = await store.habits.pausesFor('habit-1');
      expect(pauses.single.isOpen, isFalse);
      expect(pauses.single.endedAt!.isAtSameMomentAs(resumedAt), isTrue);
    });

    test('resuming a habit that is not paused is a no-op', () async {
      await seedHabit();

      await expectLater(store.habits.resumeHabit('habit-1'), completes);

      expect(await store.habits.pausesFor('habit-1'), isEmpty);
    });

    test(
      'repeated pause and resume accumulate intervals, oldest first',
      () async {
        await seedHabit();
        await store.habits.pauseHabit('habit-1');
        clock.advance(const Duration(days: 2));
        await store.habits.resumeHabit('habit-1');
        clock.advance(const Duration(days: 5));
        await store.habits.pauseHabit('habit-1');

        final pauses = await store.habits.pausesFor('habit-1');

        expect(pauses, hasLength(2));
        expect(pauses.first.startedAt.isBefore(pauses.last.startedAt), isTrue);
        expect(pauses.first.isOpen, isFalse);
        expect(pauses.last.isOpen, isTrue);
      },
    );

    test('pausing an unknown or deleted habit is a typed exception', () async {
      await seedHabit();
      await store.habits.deleteHabit('habit-1');

      expect(
        () => store.habits.pauseHabit('habit-1'),
        throwsA(isA<UnknownHabitException>()),
      );
      expect(
        () => store.habits.resumeHabit('never-existed'),
        throwsA(isA<UnknownHabitException>()),
      );
    });

    test('pauses of an unknown habit are empty, not an error', () async {
      expect(await store.habits.pausesFor('never-existed'), isEmpty);
    });
  });

  group('CompletionRepository', () {
    Completion completion(
      String id,
      DateTime at, {
      String habitId = 'habit-1',
    }) => Completion(id: id, habitId: habitId, completedAt: at);

    test('records a completion and reads it back', () async {
      await seedHabit();
      final at = startOfTest.add(const Duration(hours: 2));

      await store.completions.recordCompletion(
        Completion(
          id: 'c-1',
          habitId: 'habit-1',
          completedAt: at,
          wasNudged: true,
          source: CompletionSource.nudgeConfirmation,
        ),
      );

      final all = await store.completions.completionsFor('habit-1');
      expect(all, hasLength(1));
      expect(all.single.id, 'c-1');
      expect(all.single.completedAt.isAtSameMomentAs(at), isTrue);
      expect(all.single.wasNudged, isTrue);
      expect(all.single.source, CompletionSource.nudgeConfirmation);
    });

    test('lists completions oldest first', () async {
      await seedHabit();
      await store.completions.recordCompletion(
        completion('c-2', startOfTest.add(const Duration(days: 2))),
      );
      await store.completions.recordCompletion(completion('c-1', startOfTest));

      expect(
        (await store.completions.completionsFor('habit-1')).map((c) => c.id),
        <String>['c-1', 'c-2'],
      );
    });

    test(
      're-recording the same (habit, id) is a union, not a duplicate',
      () async {
        // The whole conflict policy rests on this: two devices replaying the
        // same client-generated UUID must converge on one event.
        await seedHabit();
        final original = completion('c-1', startOfTest);

        await store.completions.recordCompletion(original);
        await store.completions.recordCompletion(original);
        await store.completions.recordCompletion(
          original.copyWith(
            completedAt: startOfTest.add(const Duration(days: 9)),
          ),
        );

        final all = await store.completions.completionsFor('habit-1');
        expect(all, hasLength(1));
        // First write wins: a completion is an event that already happened.
        expect(all.single.completedAt.isAtSameMomentAs(startOfTest), isTrue);
      },
    );

    test('two ids at the same instant are two completions', () async {
      await seedHabit();

      await store.completions.recordCompletion(completion('c-1', startOfTest));
      await store.completions.recordCompletion(completion('c-2', startOfTest));

      expect(await store.completions.completionsFor('habit-1'), hasLength(2));
    });

    test('another habit\'s completions are not returned', () async {
      await seedHabit();
      await seedHabit(id: 'habit-2');

      await store.completions.recordCompletion(completion('c-1', startOfTest));
      await store.completions.recordCompletion(
        completion('c-2', startOfTest, habitId: 'habit-2'),
      );

      expect(await store.completions.completionsFor('habit-1'), hasLength(1));
      expect(await store.completions.completionsFor('habit-2'), hasLength(1));
    });

    test('a completion for an unknown habit is a typed exception', () async {
      expect(
        () => store.completions.recordCompletion(
          completion('c-1', startOfTest, habitId: 'never-existed'),
        ),
        throwsA(
          isA<UnknownHabitException>().having(
            (error) => error.habitId,
            'habitId',
            'never-existed',
          ),
        ),
      );
    });

    test('a completion for a deleted habit is a typed exception', () async {
      // The expected-but-abnormal case: the habit was deleted on another
      // device between the garden rendering and the tap landing.
      await seedHabit();
      await store.habits.deleteHabit('habit-1');

      expect(
        () =>
            store.completions.recordCompletion(completion('c-1', startOfTest)),
        throwsA(isA<UnknownHabitException>()),
      );
    });

    test('a local day runs midnight to midnight on the local clock', () async {
      // Not on the UTC clock: east of Greenwich the late-evening tap and the
      // early-morning one fall on different UTC dates but the same local day.
      await seedHabit();
      final date = LocalDate(2026, 3, 12);
      final justAfterMidnight = DateTime(2026, 3, 12, 0, 30);
      final lateEvening = DateTime(2026, 3, 12, 23, 30);
      final previousEvening = DateTime(2026, 3, 11, 23, 30);
      final nextMorning = DateTime(2026, 3, 13, 0, 30);

      await store.completions.recordCompletion(
        completion('c-1', justAfterMidnight),
      );
      await store.completions.recordCompletion(completion('c-2', lateEvening));
      await store.completions.recordCompletion(
        completion('c-0', previousEvening),
      );
      await store.completions.recordCompletion(completion('c-3', nextMorning));

      final onTheDay = await store.completions.completionsOnLocalDate(
        'habit-1',
        date,
      );

      expect(onTheDay.map((c) => c.id), <String>['c-1', 'c-2']);
    });

    group('undo', () {
      test('a retracted completion is gone from every read', () async {
        await seedHabit();
        await store.completions.recordCompletion(
          completion('c-1', startOfTest),
        );
        await store.completions.recordCompletion(
          completion('c-2', startOfTest.add(const Duration(hours: 2))),
        );

        await store.completions.retractCompletion('habit-1', 'c-2');

        expect(
          (await store.completions.completionsFor('habit-1')).map((c) => c.id),
          <String>['c-1'],
        );
        expect(
          (await store.completions.latestCompletion('habit-1'))!.id,
          'c-1',
        );
        expect(
          (await store.completions.completionsOnLocalDate(
            'habit-1',
            LocalDate.from(startOfTest),
          )).map((c) => c.id),
          <String>['c-1'],
        );
      });

      test('undoing the only completion leaves the habit unwatered', () async {
        await seedHabit();
        await store.completions.recordCompletion(
          completion('c-1', startOfTest),
        );

        await store.completions.retractCompletion('habit-1', 'c-1');

        expect(await store.completions.completionsFor('habit-1'), isEmpty);
        expect(await store.completions.latestCompletion('habit-1'), isNull);
      });

      test('a retracted completion cannot be resurrected by a replay', () async {
        // The retraction is an append-only event too, so the union of both
        // ledgers is order-independent: a device that still holds the original
        // completion and pushes it again must not undo the undo.
        await seedHabit();
        final original = completion('c-1', startOfTest);
        await store.completions.recordCompletion(original);
        await store.completions.retractCompletion('habit-1', 'c-1');

        await store.completions.recordCompletion(original);

        expect(await store.completions.completionsFor('habit-1'), isEmpty);
      });

      test('a fresh tap after an undo is a new completion', () async {
        await seedHabit();
        await store.completions.recordCompletion(
          completion('c-1', startOfTest),
        );
        await store.completions.retractCompletion('habit-1', 'c-1');

        await store.completions.recordCompletion(
          completion('c-2', startOfTest.add(const Duration(minutes: 5))),
        );

        expect(
          (await store.completions.completionsFor('habit-1')).map((c) => c.id),
          <String>['c-2'],
        );
      });

      test('undoing twice is a no-op, whatever the clock says', () async {
        await seedHabit();
        await store.completions.recordCompletion(
          completion('c-1', startOfTest),
        );
        await store.completions.retractCompletion('habit-1', 'c-1');

        await expectLater(
          store.completions.retractCompletion('habit-1', 'c-1'),
          completes,
        );
        // Idempotence must not depend on the undo window: a retraction that
        // already happened stays a no-op after the day has turned.
        clock.advance(const Duration(days: 2));
        await expectLater(
          store.completions.retractCompletion('habit-1', 'c-1'),
          completes,
        );
      });

      test('is refused once the local day has turned', () async {
        await seedHabit();
        await store.completions.recordCompletion(
          completion('c-1', startOfTest),
        );
        clock.now = DateTime(
          startOfTest.year,
          startOfTest.month,
          startOfTest.day + 1,
          0,
          1,
        );

        expect(
          () => store.completions.retractCompletion('habit-1', 'c-1'),
          throwsA(
            isA<CompletionNotRetractableException>().having(
              (error) => error.completionId,
              'completionId',
              'c-1',
            ),
          ),
        );
        expect(await store.completions.completionsFor('habit-1'), hasLength(1));
      });

      test('is allowed right up to the end of the local day', () async {
        await seedHabit();
        await store.completions.recordCompletion(
          completion('c-1', startOfTest),
        );
        clock.now = DateTime(
          startOfTest.year,
          startOfTest.month,
          startOfTest.day,
          23,
          59,
        );

        await store.completions.retractCompletion('habit-1', 'c-1');

        expect(await store.completions.completionsFor('habit-1'), isEmpty);
      });

      test(
        'a retraction can be recorded before its completion arrives',
        () async {
          // The sync path. The retraction ledger has no foreign key to
          // completions precisely so this can land first; recordRetraction is
          // what makes that reachable without bypassing the repository.
          await seedHabit();

          await store.completions.recordRetraction(
            'habit-1',
            'c-1',
            retractedAt: startOfTest,
          );
          await store.completions.recordCompletion(
            completion('c-1', startOfTest),
          );

          expect(await store.completions.completionsFor('habit-1'), isEmpty);
        },
      );

      test('an ingested retraction ignores the undo window', () async {
        // The window was already judged on the device where the user pressed
        // undo. Re-judging it here, against another clock in another timezone,
        // would drop legitimate undos.
        await seedHabit();
        await store.completions.recordCompletion(
          completion('c-1', startOfTest),
        );
        clock.advance(const Duration(days: 30));

        await expectLater(
          store.completions.recordRetraction(
            'habit-1',
            'c-1',
            retractedAt: startOfTest,
          ),
          completes,
        );
        expect(await store.completions.completionsFor('habit-1'), isEmpty);
      });

      test('an unknown completion is a typed exception', () async {
        await seedHabit();

        expect(
          () => store.completions.retractCompletion('habit-1', 'never-existed'),
          throwsA(
            isA<UnknownCompletionException>().having(
              (error) => error.completionId,
              'completionId',
              'never-existed',
            ),
          ),
        );
      });

      test('an unknown habit is a typed exception', () async {
        expect(
          () => store.completions.retractCompletion('never-existed', 'c-1'),
          throwsA(isA<UnknownHabitException>()),
        );
      });

      test('does not reach another habit\'s identically-named row', () async {
        await seedHabit();
        await seedHabit(id: 'habit-2');
        await store.completions.recordCompletion(
          completion('c-1', startOfTest),
        );
        await store.completions.recordCompletion(
          completion('c-1', startOfTest, habitId: 'habit-2'),
        );

        await store.completions.retractCompletion('habit-1', 'c-1');

        expect(await store.completions.completionsFor('habit-1'), isEmpty);
        expect(await store.completions.completionsFor('habit-2'), hasLength(1));
      });
    });

    test('the latest completion is the newest one, or null', () async {
      await seedHabit();
      expect(await store.completions.latestCompletion('habit-1'), isNull);

      await store.completions.recordCompletion(completion('c-1', startOfTest));
      await store.completions.recordCompletion(
        completion('c-2', startOfTest.add(const Duration(days: 3))),
      );
      await store.completions.recordCompletion(
        completion('c-3', startOfTest.add(const Duration(days: 1))),
      );

      expect((await store.completions.latestCompletion('habit-1'))!.id, 'c-2');
    });
  });

  group('ReflectionRepository', () {
    Reflection reflection(
      String id,
      DateTime at, {
      String habitId = 'habit-1',
      InputMode inputMode = InputMode.chip,
      CueType cueType = CueType.event,
    }) => Reflection(
      id: id,
      habitId: habitId,
      createdAt: at,
      occasion: Occasion.completion,
      framing: Framing.discovery,
      inputMode: inputMode,
      cueReported: inputMode == InputMode.chip ? 'after breakfast' : null,
      cueType: cueType,
    );

    test('saves a reflection and reads every field back', () async {
      await seedHabit();
      final at = startOfTest.add(const Duration(hours: 12));

      await store.reflections.saveReflection(
        Reflection(
          id: 'r-1',
          habitId: 'habit-1',
          createdAt: at,
          occasion: Occasion.miss,
          framing: Framing.diagnosis,
          inputMode: InputMode.typed,
          cueReported: 'got home from work',
          cueType: CueType.event,
          matchedDesignedCue: false,
          frictionReported: 'too tired',
          frictionType: FrictionType.energy,
          wasNudged: true,
        ),
      );

      final restored = (await store.reflections.reflectionsFor(
        'habit-1',
      )).single;
      expect(restored.createdAt.isAtSameMomentAs(at), isTrue);
      expect(restored.occasion, Occasion.miss);
      expect(restored.framing, Framing.diagnosis);
      expect(restored.inputMode, InputMode.typed);
      expect(restored.cueReported, 'got home from work');
      expect(restored.matchedDesignedCue, isFalse);
      expect(restored.frictionReported, 'too tired');
      expect(restored.frictionType, FrictionType.energy);
      expect(restored.wasNudged, isTrue);
    });

    test('lists reflections oldest first', () async {
      await seedHabit();
      await store.reflections.saveReflection(
        reflection('r-2', startOfTest.add(const Duration(days: 2))),
      );
      await store.reflections.saveReflection(reflection('r-1', startOfTest));

      expect(
        (await store.reflections.reflectionsFor('habit-1')).map((r) => r.id),
        <String>['r-1', 'r-2'],
      );
    });

    test('saving the same id twice updates in place', () async {
      await seedHabit();
      await store.reflections.saveReflection(reflection('r-1', startOfTest));
      await store.reflections.saveReflection(
        reflection('r-1', startOfTest, cueType: CueType.location),
      );

      final all = await store.reflections.reflectionsFor('habit-1');
      expect(all, hasLength(1));
      expect(all.single.cueType, CueType.location);
    });

    test(
      'recent reflections are the newest N, returned oldest first',
      () async {
        await seedHabit();
        for (var index = 0; index < 12; index++) {
          await store.reflections.saveReflection(
            reflection('r-$index', startOfTest.add(Duration(days: index))),
          );
        }

        final recent = await store.reflections.recentReflections(
          'habit-1',
          limit: 8,
        );

        expect(recent.map((r) => r.id), <String>[
          'r-4',
          'r-5',
          'r-6',
          'r-7',
          'r-8',
          'r-9',
          'r-10',
          'r-11',
        ]);
      },
    );

    test('recent reflections are not filtered to cue-bearing ones', () async {
      // Convergence is measured over the last 8 reflections and *then* filtered
      // (growth-engine §10). Filtering here would hand the engine eight
      // cue-bearing reflections and quietly delete the "< 3 ⇒ c = 0" rule.
      await seedHabit();
      await store.reflections.saveReflection(
        reflection(
          'r-1',
          startOfTest,
          inputMode: InputMode.cantRemember,
          cueType: CueType.unknown,
        ),
      );
      await store.reflections.saveReflection(
        reflection(
          'r-2',
          startOfTest.add(const Duration(days: 1)),
          inputMode: InputMode.skipped,
          cueType: CueType.unknown,
        ),
      );

      final recent = await store.reflections.recentReflections(
        'habit-1',
        limit: 8,
      );

      expect(recent, hasLength(2));
    });

    test('a reflection for an unknown habit is a typed exception', () async {
      expect(
        () => store.reflections.saveReflection(
          reflection('r-1', startOfTest, habitId: 'never-existed'),
        ),
        throwsA(isA<UnknownHabitException>()),
      );
    });
  });

  group('NudgeRepository', () {
    NudgeRecord nudge(
      String id,
      DateTime occasionAt, {
      String habitId = 'habit-1',
      bool sent = true,
    }) => NudgeRecord(
      id: id,
      habitId: habitId,
      expectedOccasionAt: occasionAt,
      sent: sent,
      scheduledFor: sent ? occasionAt : null,
    );

    test('saves an occasion and reads it back', () async {
      await seedHabit();
      final occasionAt = startOfTest.add(const Duration(hours: 9));

      await store.nudges.saveNudge(nudge('n-1', occasionAt));

      final restored = (await store.nudges.nudgesFor('habit-1')).single;
      expect(restored.id, 'n-1');
      expect(restored.expectedOccasionAt.isAtSameMomentAs(occasionAt), isTrue);
      expect(restored.sent, isTrue);
      expect(restored.scheduledFor!.isAtSameMomentAs(occasionAt), isTrue);
      expect(restored.confirmed, isFalse);
      expect(restored.declined, isFalse);
    });

    test(
      'occasions the engine stayed silent on are stored and returned',
      () async {
        // These rows are autonomy's denominator. They cannot be inferred from
        // the absence of a notification, so the ledger has to carry them.
        await seedHabit();

        await store.nudges.saveNudge(nudge('n-1', startOfTest, sent: false));
        await store.nudges.saveNudge(
          nudge('n-2', startOfTest.add(const Duration(days: 2))),
        );

        final ledger = await store.nudges.nudgesFor('habit-1');
        expect(ledger, hasLength(2));
        expect(ledger.first.sent, isFalse);
        expect(ledger.first.scheduledFor, isNull);
      },
    );

    test('lists occasions oldest first', () async {
      await seedHabit();
      await store.nudges.saveNudge(
        nudge('n-2', startOfTest.add(const Duration(days: 2))),
      );
      await store.nudges.saveNudge(nudge('n-1', startOfTest));

      expect(
        (await store.nudges.nudgesFor('habit-1')).map((n) => n.id),
        <String>['n-1', 'n-2'],
      );
    });

    test('saving the same id twice updates the schedule in place', () async {
      await seedHabit();
      await store.nudges.saveNudge(nudge('n-1', startOfTest, sent: false));
      final rescheduled = startOfTest.add(const Duration(hours: 3));

      await store.nudges.saveNudge(
        NudgeRecord(
          id: 'n-1',
          habitId: 'habit-1',
          expectedOccasionAt: startOfTest,
          sent: false,
          scheduledFor: rescheduled,
        ),
      );

      final ledger = await store.nudges.nudgesFor('habit-1');
      expect(ledger, hasLength(1));
      expect(ledger.single.scheduledFor!.isAtSameMomentAs(rescheduled), isTrue);
    });

    test(
      'a re-save cannot roll back an outcome the mark methods set',
      () async {
        // sent / confirmed / declined belong to markSent and friends once the
        // row exists. A scheduler re-saving the occasion used to flip sent back
        // to 0, moving an occasion that *was* nudged into autonomy's un-nudged
        // denominator and quietly depressing the graduation gate.
        await seedHabit();
        await store.nudges.saveNudge(nudge('n-1', startOfTest, sent: false));
        await store.nudges.markSent('n-1');
        await store.nudges.markConfirmed('n-1');

        await store.nudges.saveNudge(nudge('n-1', startOfTest, sent: false));

        final row = (await store.nudges.nudgesFor('habit-1')).single;
        expect(row.sent, isTrue);
        expect(row.confirmed, isTrue);
      },
    );

    test('a second occasion on the same local day is refused', () async {
      // The ledger is one row per occasion, and computeAutonomy matches
      // occasions to completions by local date — so uniqueness is per local
      // day, not per instant. Two rows hours apart would both land in the
      // denominator.
      await seedHabit();
      await store.nudges.saveNudge(nudge('n-1', startOfTest));

      expect(
        () => store.nudges.saveNudge(
          nudge('n-2', startOfTest.add(const Duration(hours: 6))),
        ),
        throwsA(
          isA<DuplicateOccasionException>().having(
            (error) => error.existingNudgeId,
            'existingNudgeId',
            'n-1',
          ),
        ),
      );
      expect(await store.nudges.nudgesFor('habit-1'), hasLength(1));
    });

    test('the next local day is a different occasion', () async {
      await seedHabit();
      await store.nudges.saveNudge(nudge('n-1', startOfTest));

      await expectLater(
        store.nudges.saveNudge(
          nudge(
            'n-2',
            DateTime(
              startOfTest.year,
              startOfTest.month,
              startOfTest.day + 1,
              9,
            ),
          ),
        ),
        completes,
      );
      expect(await store.nudges.nudgesFor('habit-1'), hasLength(2));
    });

    test('marks a nudge sent, confirmed and declined', () async {
      await seedHabit();
      await store.nudges.saveNudge(nudge('n-1', startOfTest, sent: false));

      await store.nudges.markSent('n-1');
      expect((await store.nudges.nudgesFor('habit-1')).single.sent, isTrue);

      await store.nudges.markConfirmed('n-1');
      expect(
        (await store.nudges.nudgesFor('habit-1')).single.confirmed,
        isTrue,
      );

      await store.nudges.markDeclined('n-1');
      expect((await store.nudges.nudgesFor('habit-1')).single.declined, isTrue);
    });

    test('marking an unknown nudge is a typed exception', () async {
      expect(
        () => store.nudges.markSent('never-existed'),
        throwsA(isA<UnknownNudgeException>()),
      );
    });

    test('a nudge for an unknown habit is a typed exception', () async {
      expect(
        () => store.nudges.saveNudge(
          nudge('n-1', startOfTest, habitId: 'never-existed'),
        ),
        throwsA(isA<UnknownHabitException>()),
      );
    });
  });
}
