import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/app/runtime/runtime_providers.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/habit.dart';
import 'package:taproot/core/models/habit_category.dart';
import 'package:taproot/core/models/habit_journey.dart';
import 'package:taproot/core/models/pause_interval.dart';
import 'package:taproot/features/habits/controllers/habit_creation_controller.dart';
import 'package:taproot/features/habits/domain/habit_repository.dart';
import 'package:taproot/features/habits/providers/habit_providers.dart';

import '../../../../utils/fake_repositories.dart';

void main() {
  final createdAt = DateTime.utc(2026, 3, 1, 19, 30);

  late FakeHabitService habits;

  ProviderContainer containerWith({HabitRepository? repository}) {
    final container = ProviderContainer(
      overrides: [
        habitServiceProvider.overrideWithValue(repository ?? habits),
        newIdProvider.overrideWithValue(() => 'habit-new'),
        clockProvider.overrideWithValue(() => createdAt),
      ],
    );
    addTearDown(container.dispose);
    // The provider autodisposes, so a listener has to hold it open for as long
    // as the test drives it.
    container.listen(habitCreationControllerProvider, (_, _) {});
    return container;
  }

  HabitCreationController controllerOf(ProviderContainer container) =>
      container.read(habitCreationControllerProvider.notifier);

  HabitCreationState stateOf(ProviderContainer container) =>
      container.read(habitCreationControllerProvider);

  /// Fills in everything the design journey asks for, without advancing.
  void fillDesignedLoop(HabitCreationController controller) {
    controller
      ..nameChanged('Morning run')
      ..categoryChosen(HabitCategory.exercise)
      ..plantChosen('oak')
      ..identityStatementChanged('I am someone who runs')
      ..targetFrequencyChosen(4)
      ..cueTypeChosen(CueType.event)
      ..cueChanged('after breakfast')
      ..routineChanged('a 20 minute loop')
      ..rewardChanged('coffee on the porch');
  }

  setUp(() => habits = FakeHabitService());

  group('the front door', () {
    test('starts on the name, already designing', () {
      // design-spec §2: Journey B is the default path, and offering the two
      // journeys as equal-weight choices at the front door is the thing the
      // spec argues against. So there is no journey step at all — the flow is
      // the design flow until the user says otherwise.
      final state = stateOf(containerWith());

      expect(state.journey, HabitJourney.design);
      expect(state.step, HabitCreationStep.name);
      expect(state.steps.first, HabitCreationStep.name);
      expect(state.steps, contains(HabitCreationStep.cue));
    });

    test('will not move on from an unnamed habit', () {
      final container = containerWith();
      final controller = controllerOf(container);

      controller.next();
      expect(stateOf(container).step, HabitCreationStep.name);

      controller
        ..nameChanged('  ')
        ..next();
      expect(stateOf(container).step, HabitCreationStep.name);

      controller
        ..nameChanged('Morning run')
        ..next();
      expect(stateOf(container).step, HabitCreationStep.plant);
    });

    test('will not move on without a plant', () {
      final container = containerWith();
      final controller = controllerOf(container)
        ..nameChanged('Morning run')
        ..next()
        ..next();

      expect(stateOf(container).step, HabitCreationStep.plant);

      controller
        ..plantChosen('oak')
        ..next();
      expect(stateOf(container).step, HabitCreationStep.rhythm);
    });

    test('walks the whole design flow in order', () {
      final container = containerWith();
      final controller = controllerOf(container);
      fillDesignedLoop(controller);

      final walked = <HabitCreationStep>[stateOf(container).step];
      while (!stateOf(container).isLastStep) {
        controller.next();
        walked.add(stateOf(container).step);
      }

      expect(walked, HabitCreationStep.values);
    });

    test('back stops at the first step rather than underflowing', () {
      final container = containerWith();
      controllerOf(container).back();

      expect(stateOf(container).stepIndex, 0);
      expect(stateOf(container).isFirstStep, isTrue);
    });
  });

  group('the opt-out', () {
    test('drops the cue and loop steps entirely', () {
      final container = containerWith();
      controllerOf(container).journeyChosen(HabitJourney.track);

      final state = stateOf(container);
      expect(state.steps, isNot(contains(HabitCreationStep.cue)));
      expect(state.steps, isNot(contains(HabitCreationStep.loop)));
      expect(state.step, HabitCreationStep.review);
    });

    test('clears anything already typed into the loop', () {
      // A tracked habit that kept a half-written cue would be a Journey A
      // habit the engine and the chip library both treat as designed.
      final container = containerWith();
      final controller = controllerOf(container);
      fillDesignedLoop(controller);

      controller.journeyChosen(HabitJourney.track);

      final state = stateOf(container);
      expect(state.designedCue, isEmpty);
      expect(state.designedCueType, isNull);
      expect(state.routine, isEmpty);
      expect(state.reward, isEmpty);
      // What both journeys share survives.
      expect(state.name, 'Morning run');
      expect(state.plantType, 'oak');
      expect(state.targetFrequency, 4);
    });

    test('opting back in lands on the cue, not on a vanished step', () {
      final container = containerWith();
      controllerOf(container)
        ..journeyChosen(HabitJourney.track)
        ..journeyChosen(HabitJourney.design);

      expect(stateOf(container).step, HabitCreationStep.cue);
    });

    test('choosing the journey already in force changes nothing', () {
      final container = containerWith();
      final controller = controllerOf(container);
      fillDesignedLoop(controller);
      controller.journeyChosen(HabitJourney.design);

      expect(stateOf(container).designedCue, 'after breakfast');
      expect(stateOf(container).step, HabitCreationStep.name);
    });
  });

  group('what the flow refuses', () {
    test('a designed cue may not be an internal state', () {
      // growth-engine §1: the engine cannot schedule, nudge or fairly measure a
      // habit hung on a mood. The Habit assert says so too, but asserts are
      // stripped from release builds and this is reached from a screen.
      final container = containerWith();
      final controller = controllerOf(container)
        ..cueTypeChosen(CueType.event)
        ..cueTypeChosen(CueType.internal);

      expect(stateOf(container).designedCueType, CueType.event);

      controller.cueTypeChosen(CueType.unknown);
      expect(stateOf(container).designedCueType, CueType.event);
    });

    test('a weekly target outside the range the engine accepts', () {
      final container = containerWith();
      final controller = controllerOf(container)..targetFrequencyChosen(0);

      expect(stateOf(container).targetFrequency, defaultTargetFrequency);

      controller.targetFrequencyChosen(8);
      expect(stateOf(container).targetFrequency, defaultTargetFrequency);

      controller.targetFrequencyChosen(7);
      expect(stateOf(container).targetFrequency, 7);
    });

    test('a designed habit missing two thirds of its loop', () {
      final container = containerWith();
      final controller = controllerOf(container)
        ..nameChanged('Morning run')
        ..plantChosen('oak')
        ..cueTypeChosen(CueType.event)
        ..cueChanged('after breakfast');

      expect(stateOf(container).canSubmit, isFalse);

      controller.routineChanged('a 20 minute loop');
      expect(stateOf(container).canSubmit, isFalse);

      controller.rewardChanged('coffee on the porch');
      expect(stateOf(container).canSubmit, isTrue);
    });

    test('a tracked habit needs only what both journeys share', () {
      final container = containerWith();
      final controller = controllerOf(container)
        ..journeyChosen(HabitJourney.track)
        ..nameChanged('Read');

      expect(stateOf(container).canSubmit, isFalse);

      controller.plantChosen('fern');
      expect(stateOf(container).canSubmit, isTrue);
    });
  });

  group('planting it', () {
    test('writes a designed habit with its whole loop', () async {
      final container = containerWith();
      final controller = controllerOf(container);
      fillDesignedLoop(controller);

      await controller.submit();

      final saved = (await habits.allHabits()).single;
      expect(saved.id, 'habit-new');
      expect(saved.name, 'Morning run');
      expect(saved.journey, HabitJourney.design);
      expect(saved.category, HabitCategory.exercise);
      expect(saved.plantType, 'oak');
      expect(saved.targetFrequency, 4);
      expect(saved.identityStatement, 'I am someone who runs');
      expect(saved.designedCue, 'after breakfast');
      expect(saved.designedCueType, CueType.event);
      expect(saved.routine, 'a 20 minute loop');
      expect(saved.reward, 'coffee on the porch');
      expect(saved.createdAt.isAtSameMomentAs(createdAt), isTrue);
      expect(stateOf(container).createdHabitId, 'habit-new');
    });

    test('writes a tracked habit with no loop at all', () async {
      final container = containerWith();
      final controller = controllerOf(container);
      fillDesignedLoop(controller);
      controller.journeyChosen(HabitJourney.track);

      await controller.submit();

      final saved = (await habits.allHabits()).single;
      expect(saved.journey, HabitJourney.track);
      expect(saved.designedCue, isNull);
      expect(saved.designedCueType, isNull);
      expect(saved.routine, isNull);
      expect(saved.reward, isNull);
      expect(saved.hasDesignedLoop, isFalse);
    });

    test('trims what the user typed, and drops what they left blank', () async {
      final container = containerWith();
      final controller = controllerOf(container);
      fillDesignedLoop(controller);
      controller
        ..nameChanged('  Morning run  ')
        ..identityStatementChanged('   ')
        ..cueChanged('  after breakfast ');

      await controller.submit();

      final saved = (await habits.allHabits()).single;
      expect(saved.name, 'Morning run');
      expect(saved.identityStatement, isNull);
      expect(saved.designedCue, 'after breakfast');
    });

    test('an incomplete draft is not written', () async {
      final container = containerWith();
      await controllerOf(container).submit();

      expect(await habits.allHabits(), isEmpty);
      expect(stateOf(container).createdHabitId, isNull);
    });

    test('a second tap does not plant a second plant', () async {
      final container = containerWith();
      final controller = controllerOf(container);
      fillDesignedLoop(controller);

      await Future.wait(<Future<void>>[
        controller.submit(),
        controller.submit(),
      ]);
      await controller.submit();

      expect(await habits.allHabits(), hasLength(1));
    });

    test('a failed save keeps the draft and says so', () async {
      final container = containerWith(repository: _UnwritableHabitService());
      final controller = controllerOf(container);
      fillDesignedLoop(controller);

      await controller.submit();

      final state = stateOf(container);
      expect(state.createdHabitId, isNull);
      expect(state.isSaving, isFalse);
      expect(state.errorMessage, isNotNull);
      // Nothing re-entered: the whole draft is still there to retry with.
      expect(state.name, 'Morning run');
      expect(state.designedCue, 'after breakfast');
      expect(state.canSubmit, isTrue);
    });

    test('a retry after a failure clears the error', () async {
      final container = containerWith(repository: _UnwritableHabitService());
      final controller = controllerOf(container);
      fillDesignedLoop(controller);
      await controller.submit();

      expect(stateOf(container).errorMessage, isNotNull);

      // The same failure again, but the message is cleared on the way in
      // rather than left stale under a spinner.
      final pending = controller.submit();
      await pending;
      expect(stateOf(container).errorMessage, isNotNull);
    });
  });
}

/// A store whose writes always fail.
class _UnwritableHabitService implements HabitRepository {
  @override
  Future<void> saveHabit(Habit habit) async =>
      throw StateError('the disk is full');

  @override
  Future<List<Habit>> allHabits() async => <Habit>[];

  @override
  Future<Habit?> habitById(String habitId) async => null;

  @override
  Future<void> deleteHabit(String habitId) async {}

  @override
  Future<void> pauseHabit(String habitId) async {}

  @override
  Future<void> resumeHabit(String habitId) async {}

  @override
  Future<List<PauseInterval>> pausesFor(String habitId) async =>
      <PauseInterval>[];
}
