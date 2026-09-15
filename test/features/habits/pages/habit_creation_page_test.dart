import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/app/database/database_provider.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/habit.dart';
import 'package:taproot/core/models/habit_category.dart';
import 'package:taproot/core/models/habit_journey.dart';
import 'package:taproot/features/garden/pages/garden_page.dart';
import 'package:taproot/features/habits/domain/habit_repository.dart';
import 'package:taproot/features/habits/pages/habit_creation_page.dart';
import 'package:taproot/features/habits/providers/habit_providers.dart';
import 'package:taproot/features/habits/widgets/cue_step.dart';
import 'package:taproot/features/habits/widgets/loop_step.dart';
import 'package:taproot/features/habits/widgets/name_step.dart';
import 'package:taproot/features/habits/widgets/review_step.dart';
import 'package:taproot/main.dart';

import '../../../utils/fake_repositories.dart';
import '../../../utils/store_fixtures.dart';

void main() {
  /// The app with an empty store, which the entry gate lands on habit
  /// creation. Driving the real app rather than the page alone is deliberate:
  /// planting a habit is supposed to end on the garden, and that is routing.
  Future<void> pumpCreation(
    WidgetTester tester, {
    HabitRepository? habits,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseOpenerProvider.overrideWithValue(
            openTestDatabaseInWidgetTest,
          ),
          habitServiceProvider.overrideWithValue(habits ?? FakeHabitService()),
        ],
        child: const TaprootApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String label) async {
    final target = find.text(label);
    await tester.ensureVisible(target.first);
    await tester.pumpAndSettle();
    await tester.tap(target.first);
    await tester.pumpAndSettle();
  }

  Future<void> tapNext(WidgetTester tester) =>
      tapText(tester, HabitCreationPage.nextLabel);

  /// Walks name → plant → rhythm, which both journeys share.
  Future<void> walkTheShared(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), 'Morning run');
    await tester.pumpAndSettle();
    await tapNext(tester);

    await tapText(tester, 'Oak');
    await tapNext(tester);

    await tapText(tester, '4');
    await tapNext(tester);
  }

  testWidgets('the first screen is the design flow, not a choice of two', (
    tester,
  ) async {
    // design-spec §2: offering designing and tracking as equal-weight choices
    // at the front door is the thing the spec argues against.
    await pumpCreation(tester);

    expect(find.byType(HabitCreationPage), findsOneWidget);
    expect(find.text(NameStep.question), findsOneWidget);
    expect(find.text(CueStep.optOutLabel), findsNothing);
  });

  testWidgets('will not advance past a step it has not been given', (
    tester,
  ) async {
    await pumpCreation(tester);

    final next = find.widgetWithText(FilledButton, HabitCreationPage.nextLabel);
    expect(tester.widget<FilledButton>(next).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Morning run');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(next).onPressed, isNotNull);
  });

  testWidgets('designs a whole loop and plants it', (tester) async {
    final habits = FakeHabitService();
    await pumpCreation(tester, habits: habits);

    await walkTheShared(tester);

    // The cue.
    await tapText(tester, 'After something');
    await tester.enterText(find.byType(TextField), 'after breakfast');
    await tester.pumpAndSettle();
    await tapNext(tester);

    // The routine and the reward.
    await tester.enterText(find.byType(TextField).first, 'a 20 minute loop');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'coffee on the porch');
    await tester.pumpAndSettle();
    await tapNext(tester);

    expect(find.text(ReviewStep.question), findsOneWidget);
    await tapText(tester, HabitCreationPage.plantLabel);

    final planted = (await habits.allHabits()).single;
    expect(planted.name, 'Morning run');
    expect(planted.journey, HabitJourney.design);
    expect(planted.plantType, 'oak');
    expect(planted.targetFrequency, 4);
    expect(planted.designedCue, 'after breakfast');
    expect(planted.designedCueType, CueType.event);
    expect(planted.routine, 'a 20 minute loop');
    expect(planted.reward, 'coffee on the porch');

    // And it ends where the app lives.
    expect(find.byType(GardenPage), findsOneWidget);
  });

  testWidgets('the opt-out skips the loop and plants a tracked habit', (
    tester,
  ) async {
    final habits = FakeHabitService();
    await pumpCreation(tester, habits: habits);

    await walkTheShared(tester);
    await tapText(tester, CueStep.optOutLabel);

    // Straight to the review: the steps it skipped no longer exist.
    expect(find.text(ReviewStep.question), findsOneWidget);
    expect(find.text(ReviewStep.trackingNote), findsOneWidget);

    await tapText(tester, HabitCreationPage.plantLabel);

    final planted = (await habits.allHabits()).single;
    expect(planted.journey, HabitJourney.track);
    expect(planted.hasDesignedLoop, isFalse);
    expect(planted.routine, isNull);
    expect(planted.reward, isNull);
    expect(find.byType(GardenPage), findsOneWidget);
  });

  testWidgets('the opt-out is reversible right up to planting', (tester) async {
    await pumpCreation(tester);

    await walkTheShared(tester);
    await tapText(tester, CueStep.optOutLabel);
    await tapText(tester, ReviewStep.designInsteadLabel);

    expect(find.text(CueStep.question), findsOneWidget);
  });

  testWidgets('a cue example fills the field rather than being typed', (
    tester,
  ) async {
    // design-spec §3 — tap, don't type.
    await pumpCreation(tester);
    await walkTheShared(tester);

    await tapText(tester, 'After something');
    // The chip specifically — the same words are also the field's hint while
    // it is empty, which is the point of the example.
    final example = find.widgetWithText(ActionChip, 'after breakfast');
    await tester.ensureVisible(example);
    await tester.pumpAndSettle();
    await tester.tap(example);
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'after breakfast',
    );
  });

  testWidgets('a category can be chosen and skipped', (tester) async {
    final habits = FakeHabitService();
    await pumpCreation(tester, habits: habits);

    await tester.enterText(find.byType(TextField), 'Morning run');
    await tester.pumpAndSettle();
    await tapText(tester, HabitCategory.exercise.label);
    await tapNext(tester);

    await tapText(tester, 'Oak');
    await tapNext(tester);
    await tapNext(tester);
    await tapText(tester, CueStep.optOutLabel);
    await tapText(tester, HabitCreationPage.plantLabel);

    expect((await habits.allHabits()).single.category, HabitCategory.exercise);
  });

  testWidgets('a failed save says so and keeps the draft', (tester) async {
    await pumpCreation(tester, habits: _UnwritableHabitService());

    await walkTheShared(tester);
    await tapText(tester, CueStep.optOutLabel);
    await tapText(tester, HabitCreationPage.plantLabel);

    expect(find.byType(HabitCreationPage), findsOneWidget);
    expect(find.byType(GardenPage), findsNothing);
    expect(find.textContaining('Nothing has been lost'), findsOneWidget);
    // Still on the review, with everything still there to retry with.
    expect(find.text('Morning run'), findsOneWidget);
  });

  testWidgets('back returns to the step before it, with what was typed', (
    tester,
  ) async {
    await pumpCreation(tester);
    await walkTheShared(tester);

    await tapText(tester, 'After something');
    await tester.enterText(find.byType(TextField), 'after breakfast');
    await tester.pumpAndSettle();
    await tapNext(tester);

    expect(find.text(LoopStep.question), findsOneWidget);

    await tapText(tester, HabitCreationPage.backLabel);

    expect(find.text(CueStep.question), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'after breakfast',
    );
  });
}

/// A store whose writes always fail.
class _UnwritableHabitService extends FakeHabitService {
  @override
  Future<void> saveHabit(Habit habit) async =>
      throw StateError('the disk is full');
}
