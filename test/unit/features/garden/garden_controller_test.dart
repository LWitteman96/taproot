import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/app/database/store_exceptions.dart';
import 'package:taproot/app/runtime/runtime_providers.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/completion.dart';
import 'package:taproot/core/models/nudge.dart';
import 'package:taproot/features/garden/controllers/garden_controller.dart';
import 'package:taproot/features/garden/domain/garden_state.dart';
import 'package:taproot/features/garden/providers/garden_selectors.dart';
import 'package:taproot/features/habits/domain/completion_repository.dart';
import 'package:taproot/features/habits/providers/habit_providers.dart';
import 'package:taproot/features/notifications/providers/nudge_providers.dart';
import 'package:taproot/features/reflection/providers/reflection_providers.dart';

import '../../../utils/fake_repositories.dart';
import '../../../utils/store_fixtures.dart';

/// A completion store the test can stall or break.
///
/// Wrapping rather than reimplementing: everything it does not intercept is the
/// same fake the SQLite services are contract-tested against, so a test about
/// failure is still running the real success path underneath.
class ControllableCompletions implements CompletionRepository {
  ControllableCompletions(this._inner);

  final CompletionRepository _inner;

  /// Completed by the test to let a recording finish.
  Completer<void>? gate;

  /// Thrown instead of recording.
  Object? recordFailure;

  @override
  Future<void> recordCompletion(Completion completion) async {
    if (gate != null) await gate!.future;
    if (recordFailure case final failure?) throw failure;
    return _inner.recordCompletion(completion);
  }

  @override
  Future<void> retractCompletion(String habitId, String completionId) =>
      _inner.retractCompletion(habitId, completionId);

  @override
  Future<void> recordRetraction(
    String habitId,
    String completionId, {
    required DateTime retractedAt,
  }) =>
      _inner.recordRetraction(habitId, completionId, retractedAt: retractedAt);

  @override
  Future<List<Completion>> completionsFor(String habitId) =>
      _inner.completionsFor(habitId);

  @override
  Future<List<Completion>> completionsOnLocalDate(String habitId, date) =>
      _inner.completionsOnLocalDate(habitId, date);

  @override
  Future<Completion?> latestCompletion(String habitId) =>
      _inner.latestCompletion(habitId);
}

class Harness {
  Harness({DateTime? now}) : clock = TestClock(now ?? DateTime(2026, 3, 4, 9)) {
    habits = FakeHabitService(clock: clock.call);
    final realCompletions = FakeCompletionService(
      habits: habits,
      clock: clock.call,
    );
    completions = ControllableCompletions(realCompletions);
    reflections = FakeReflectionService(habits: habits, clock: clock.call);
    nudges = FakeNudgeService(habits: habits);

    container = ProviderContainer(
      overrides: [
        habitServiceProvider.overrideWithValue(habits),
        completionServiceProvider.overrideWithValue(completions),
        reflectionServiceProvider.overrideWithValue(reflections),
        nudgeServiceProvider.overrideWithValue(nudges),
        clockProvider.overrideWithValue(clock.call),
        newIdProvider.overrideWithValue(() => 'id-${_nextId++}'),
      ],
    );
    addTearDown(container.dispose);
  }

  final TestClock clock;
  late final FakeHabitService habits;
  late final ControllableCompletions completions;
  late final FakeReflectionService reflections;
  late final FakeNudgeService nudges;
  late final ProviderContainer container;
  int _nextId = 1;

  GardenState get state => container.read(gardenControllerProvider);
  GardenController get controller =>
      container.read(gardenControllerProvider.notifier);

  /// Reads the provider (which starts the load) and waits for it to finish.
  Future<void> start() async {
    container.read(gardenControllerProvider);
    for (var attempt = 0; attempt < 100; attempt++) {
      if (!state.isLoading) return;
      await Future<void>.delayed(Duration.zero);
    }
    fail('the garden never finished loading');
  }
}

void main() {
  group('GardenController', () {
    test('loads every habit and runs the engine over it', () async {
      final harness = Harness();
      await harness.habits.saveHabit(testHabit(id: 'a', name: 'Morning walk'));
      await harness.habits.saveHabit(testHabit(id: 'b', name: 'Evening pages'));

      await harness.start();

      expect(harness.state.order, <String>['a', 'b']);
      expect(harness.state.plants['a']!.growth.stage, Stage.seed);
      expect(harness.state.plants['a']!.growth.constantsVersion, isPositive);
    });

    test('an empty store is an empty garden, not an error', () async {
      final harness = Harness();
      await harness.start();

      expect(harness.state.isEmpty, isTrue);
      expect(harness.state.errorMessage, isNull);
    });

    group('watering', () {
      test('records a completion and grows the plant a rung', () async {
        final harness = Harness();
        await harness.habits.saveHabit(testHabit(id: 'a'));
        await harness.start();
        expect(harness.state.plants['a']!.growth.stage, Stage.seed);

        final completion = await harness.controller.water('a');

        // Sprout is the first completion, so the watering is visible at once.
        expect(harness.state.plants['a']!.growth.stage, Stage.sprout);
        expect(completion, isNotNull);
        expect(completion!.source, CompletionSource.tap);
        expect(await harness.completions.completionsFor('a'), hasLength(1));
      });

      test('the plant changes before the write is allowed to finish', () async {
        // The whole point of the ordering: a completion tap must never spin.
        final harness = Harness();
        await harness.habits.saveHabit(testHabit(id: 'a'));
        await harness.start();

        harness.completions.gate = Completer<void>();
        final pending = harness.controller.water('a');

        expect(harness.state.plants['a']!.growth.stage, Stage.sprout);
        expect(harness.state.isLoading, isFalse, reason: 'never a spinner');

        harness.completions.gate!.complete();
        await pending;
        expect(await harness.completions.completionsFor('a'), hasLength(1));
      });

      test(
        'a failed write is rolled back rather than shown as growth',
        () async {
          final harness = Harness();
          await harness.habits.saveHabit(testHabit(id: 'a'));
          await harness.start();

          harness.completions.recordFailure = StateError('the disk is full');
          final completion = await harness.controller.water('a');

          expect(completion, isNull);
          expect(harness.state.plants['a']!.growth.stage, Stage.seed);
          expect(harness.state.errorMessage, couldNotWaterMessage);
        },
      );

      test('a habit deleted on another device leaves the garden', () async {
        final harness = Harness();
        await harness.habits.saveHabit(
          testHabit(id: 'a', name: 'Morning walk'),
        );
        await harness.start();

        harness.completions.recordFailure = const UnknownHabitException('a');
        await harness.controller.water('a');

        expect(harness.state.plants, isEmpty);
        expect(harness.state.order, isEmpty);
        expect(harness.state.errorMessage, contains('Morning walk'));
      });

      test(
        'watering with no nudge sent records an un-nudged completion',
        () async {
          final harness = Harness();
          await harness.habits.saveHabit(testHabit(id: 'a'));
          await harness.start();

          final completion = await harness.controller.water('a');

          expect(completion!.wasNudged, isFalse);
        },
      );

      test('watering on a day a nudge went out is marked nudged', () async {
        final harness = Harness();
        await harness.habits.saveHabit(testHabit(id: 'a'));
        await harness.nudges.saveNudge(
          NudgeRecord(
            id: 'nudge-1',
            habitId: 'a',
            expectedOccasionAt: harness.clock.now,
            sent: true,
          ),
        );
        await harness.start();

        final completion = await harness.controller.water('a');

        expect(completion!.wasNudged, isTrue);
      });

      test('an unknown habit is ignored rather than throwing', () async {
        final harness = Harness();
        await harness.start();

        expect(await harness.controller.water('nobody'), isNull);
      });
    });

    group('undo', () {
      test('takes the watering back, and the plant with it', () async {
        final harness = Harness();
        await harness.habits.saveHabit(testHabit(id: 'a'));
        await harness.start();

        final completion = await harness.controller.water('a');
        expect(harness.state.plants['a']!.growth.stage, Stage.sprout);

        await harness.controller.undo('a', completion!.id);

        // Stage is monotonic in time but not under an undo — this is the one
        // documented way a plant goes back down, and it is bounded to today.
        expect(harness.state.plants['a']!.growth.stage, Stage.seed);
        expect(await harness.completions.completionsFor('a'), isEmpty);
        expect(harness.state.errorMessage, isNull);
      });

      test('is offered for as long as the watering is retractable', () async {
        final harness = Harness();
        await harness.habits.saveHabit(testHabit(id: 'a'));
        await harness.start();

        await harness.controller.water('a');
        expect(harness.state.plants['a']!.canUndo, isTrue);
      });

      test(
        'past midnight the window has closed and the watering stands',
        () async {
          final harness = Harness();
          await harness.habits.saveHabit(testHabit(id: 'a'));
          await harness.start();

          final completion = await harness.controller.water('a');
          // The garden was left open overnight, so the offer went stale.
          harness.clock.advance(const Duration(days: 1));

          await harness.controller.undo('a', completion!.id);

          expect(harness.state.errorMessage, undoWindowClosedMessage);
          expect(await harness.completions.completionsFor('a'), hasLength(1));
          expect(harness.state.plants['a']!.growth.stage, Stage.sprout);
        },
      );

      test('undoing something already gone says nothing', () async {
        final harness = Harness();
        await harness.habits.saveHabit(testHabit(id: 'a'));
        await harness.start();

        final completion = await harness.controller.water('a');
        await harness.controller.undo('a', completion!.id);
        // A second press, or the same undo arriving from another device.
        await harness.controller.undo('a', completion.id);

        expect(harness.state.errorMessage, isNull);
        expect(await harness.completions.completionsFor('a'), isEmpty);
      });
    });

    group('selectors', () {
      test('watering one plant leaves the others untouched', () async {
        // CLAUDE.md's reason for the selector providers: a completion tap on
        // one plant must not rebuild the whole garden. That only holds while
        // the untouched PlantState stays the same instance.
        final harness = Harness();
        await harness.habits.saveHabit(testHabit(id: 'a'));
        await harness.habits.saveHabit(testHabit(id: 'b'));
        await harness.start();

        final before = harness.container.read(plantStateProvider('b'));
        final order = harness.container.read(plantIdsProvider);

        await harness.controller.water('a');

        expect(
          identical(harness.container.read(plantStateProvider('b')), before),
          isTrue,
        );
        expect(
          identical(harness.container.read(plantIdsProvider), order),
          isTrue,
        );
      });

      test('narrow the state down to one derived value', () async {
        final harness = Harness();
        await harness.habits.saveHabit(testHabit(id: 'a'));
        await harness.start();

        expect(harness.container.read(habitStageProvider('a')), Stage.seed);
        expect(harness.container.read(habitVitalityProvider('a')), isNotNull);
        expect(harness.container.read(habitRootDepthProvider('a')), 0);
        expect(harness.container.read(gardenIsLoadingProvider), isFalse);
      });

      test('a habit that has left the garden reads as null', () async {
        final harness = Harness();
        await harness.start();

        expect(harness.container.read(plantStateProvider('gone')), isNull);
        expect(harness.container.read(habitStageProvider('gone')), isNull);
      });
    });

    test('clearing the message is idempotent', () async {
      final harness = Harness();
      await harness.start();

      harness.controller.clearError();
      expect(harness.state.errorMessage, isNull);
    });
  });
}
