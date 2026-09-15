import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/app/runtime/runtime_providers.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/completion.dart';
import 'package:taproot/core/models/habit_category.dart';
import 'package:taproot/core/models/nudge.dart';
import 'package:taproot/features/habits/providers/habit_providers.dart';
import 'package:taproot/features/notifications/providers/nudge_providers.dart';
import 'package:taproot/features/reflection/pages/check_in_page.dart';
import 'package:taproot/features/reflection/providers/reflection_providers.dart';
import 'package:taproot/features/reflection/widgets/cue_answers.dart';
import 'package:taproot/features/reflection/widgets/friction_answers.dart';

import '../../utils/fake_repositories.dart';
import '../../utils/store_contract.dart';
import '../../utils/store_fixtures.dart';

void main() {
  late TestStore store;
  late TestClock clock;

  final now = DateTime(2026, 3, 12, 20);

  setUp(() async {
    clock = TestClock(now);
    store = await openFakeStore(clock);
    addTearDown(store.dispose);
  });

  Future<void> pumpCheckIn(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          habitServiceProvider.overrideWithValue(store.habits),
          completionServiceProvider.overrideWithValue(store.completions),
          reflectionServiceProvider.overrideWithValue(store.reflections),
          nudgeServiceProvider.overrideWithValue(store.nudges),
          clockProvider.overrideWithValue(() => clock.now),
          newIdProvider.overrideWithValue(() => 'reflection-1'),
        ],
        child: const MaterialApp(home: CheckInPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> plantAndWater({
    String? designedCue = 'after breakfast',
    HabitCategory? category = HabitCategory.exercise,
  }) async {
    await store.habits.saveHabit(
      testHabit(
        category: category,
        designedCue: designedCue,
        designedCueType: designedCue == null ? null : CueType.event,
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    await store.completions.recordCompletion(
      Completion(
        id: 'c1',
        habitId: 'habit-1',
        completedAt: DateTime(2026, 3, 12, 7, 10),
        source: CompletionSource.tap,
      ),
    );
  }

  testWidgets('says so calmly when there is nothing to ask', (tester) async {
    // Most days there is no check-in, and that is the design rather than a
    // failure to find one.
    await pumpCheckIn(tester);

    expect(find.text(CheckInPage.nothingHeadline), findsOneWidget);
    expect(find.byType(CueAnswers), findsNothing);
  });

  testWidgets('asks about the cue, with the designed one pinned first', (
    tester,
  ) async {
    await plantAndWater();
    await pumpCheckIn(tester);

    expect(find.text('Did after breakfast kick it off?'), findsOneWidget);
    expect(find.byType(CueAnswers), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'after breakfast'), findsOneWidget);
    expect(
      find.widgetWithText(ActionChip, CueAnswers.cantRememberLabel),
      findsOneWidget,
    );
  });

  testWidgets('a tapped chip is written down and acknowledged', (tester) async {
    await plantAndWater();
    await pumpCheckIn(tester);

    await tester.tap(find.widgetWithText(ActionChip, 'after breakfast'));
    await tester.pumpAndSettle();

    final saved = (await store.reflections.reflectionsFor('habit-1')).single;
    expect(saved.inputMode, InputMode.chip);
    expect(saved.cueReported, 'after breakfast');
    expect(saved.cueType, CueType.event);
    expect(saved.framing, Framing.validation);
    // The designed cue was the answer, which is what cue reliability counts.
    expect(saved.matchedDesignedCue, isTrue);

    expect(find.text(CheckInPage.doneHeadline), findsOneWidget);
  });

  testWidgets("can't remember is recorded, not discarded", (tester) async {
    // A rising can't-remember rate is itself the signal that a habit is running
    // on autopilot without awareness.
    await plantAndWater();
    await pumpCheckIn(tester);

    await tester.tap(
      find.widgetWithText(ActionChip, CueAnswers.cantRememberLabel),
    );
    await tester.pumpAndSettle();

    final saved = (await store.reflections.reflectionsFor('habit-1')).single;
    expect(saved.inputMode, InputMode.cantRemember);
    expect(saved.cueReported, isNull);
  });

  testWidgets('typing is available, but it is not the default', (tester) async {
    await plantAndWater();
    await pumpCheckIn(tester);

    // No field until it is asked for.
    expect(find.byType(TextField), findsNothing);

    await tester.tap(
      find.widgetWithText(ActionChip, CueAnswers.somethingElseLabel),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'the dog woke me');
    await tester.pumpAndSettle();

    final submit = find.widgetWithText(FilledButton, CueAnswers.submitLabel);
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    final saved = (await store.reflections.reflectionsFor('habit-1')).single;
    expect(saved.inputMode, InputMode.typed);
    expect(saved.cueReported, 'the dog woke me');
    // Typed answers carry no type until something infers one, and `unknown` is
    // deliberately not treated as an internal state by convergence.
    expect(saved.cueType, CueType.unknown);
    expect(saved.matchedDesignedCue, isFalse);
  });

  testWidgets('a miss is diagnosed with friction chips, never scolded', (
    tester,
  ) async {
    await store.habits.saveHabit(
      testHabit(
        category: HabitCategory.exercise,
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    await store.nudges.saveNudge(
      NudgeRecord(
        id: 'n1',
        habitId: 'habit-1',
        expectedOccasionAt: DateTime(2026, 3, 11, 7),
        sent: true,
      ),
    );
    await pumpCheckIn(tester);

    expect(find.byType(FrictionAnswers), findsOneWidget);
    expect(find.byType(CueAnswers), findsNothing);
    expect(find.textContaining('what got in the way?'), findsOneWidget);
    expect(find.textContaining('missed'), findsNothing);

    await tester.tap(find.widgetWithText(ActionChip, 'just forgot'));
    await tester.pumpAndSettle();

    final saved = (await store.reflections.reflectionsFor('habit-1')).single;
    expect(saved.framing, Framing.diagnosis);
    expect(saved.frictionType, FrictionType.forgot);
    expect(saved.frictionReported, 'just forgot');
  });

  testWidgets('declining to answer is itself recorded', (tester) async {
    // A habit the user keeps declining to talk about is a signal worth having.
    await plantAndWater();
    await pumpCheckIn(tester);

    await tester.tap(find.widgetWithText(TextButton, CheckInPage.skipLabel));
    await tester.pumpAndSettle();

    final saved = (await store.reflections.reflectionsFor('habit-1')).single;
    expect(saved.inputMode, InputMode.skipped);
  });
}
