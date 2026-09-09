import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/app/runtime/runtime_providers.dart';
import 'package:taproot/app/theme/app_motion.dart';
import 'package:taproot/app/theme/themedata.dart';
import 'package:taproot/features/garden/domain/garden_ticker.dart';
import 'package:taproot/features/garden/pages/garden_page.dart';
import 'package:taproot/features/garden/widgets/plant_card.dart';
import 'package:taproot/features/garden/widgets/watering_control.dart';
import 'package:taproot/features/habits/providers/habit_providers.dart';
import 'package:taproot/features/notifications/providers/nudge_providers.dart';
import 'package:taproot/features/reflection/providers/reflection_providers.dart';

import '../../utils/fake_repositories.dart';
import '../../utils/store_fixtures.dart';

class PageHarness {
  PageHarness() {
    habits = FakeHabitService(clock: clock.call);
    completions = FakeCompletionService(habits: habits, clock: clock.call);
  }

  final TestClock clock = TestClock(DateTime(2026, 3, 4, 9));
  late final FakeHabitService habits;
  late final FakeCompletionService completions;
  int _nextId = 1;

  Widget get app => ProviderScope(
    overrides: [
      habitServiceProvider.overrideWithValue(habits),
      completionServiceProvider.overrideWithValue(completions),
      reflectionServiceProvider.overrideWithValue(
        FakeReflectionService(habits: habits, clock: clock.call),
      ),
      nudgeServiceProvider.overrideWithValue(FakeNudgeService(habits: habits)),
      clockProvider.overrideWithValue(clock.call),
      newIdProvider.overrideWithValue(() => 'id-${_nextId++}'),
      // Widget tests run against a still garden: the ambient loops never
      // settle, and a test that has to fight them is a test about the
      // animation rather than about the feature.
      gardenTickerProvider.overrideWith(() => _StillTicker()),
    ],
    child: MaterialApp(theme: AppTheme.light, home: const GardenPage()),
  );
}

class _StillTicker extends GardenTickerController {
  @override
  GardenTicker build() => GardenTicker.still;
}

/// Performs the watering gesture on the first plant.
Future<void> holdToWater(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(WateringControl).first),
  );
  await tester.pump(AppMotion.waterHoldDuration);
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  group('GardenPage', () {
    testWidgets('an empty garden says so rather than showing a task list', (
      tester,
    ) async {
      final harness = PageHarness();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(find.text(GardenPage.emptyHeadline), findsOneWidget);
      expect(find.byType(PlantCard), findsNothing);
    });

    testWidgets('the dev seed puts a plant in the garden', (tester) async {
      final harness = PageHarness();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await tester.tap(find.text(GardenPage.seedLabel));
      await tester.pumpAndSettle();

      expect(find.byType(PlantCard), findsOneWidget);
      expect(find.text('Morning walk'), findsOneWidget);
    });

    testWidgets('holding waters the plant and it grows in place', (
      tester,
    ) async {
      final harness = PageHarness();
      await harness.habits.saveHabit(testHabit(id: 'a', name: 'Morning walk'));
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(find.textContaining('Seed'), findsOneWidget);

      await holdToWater(tester);

      expect(find.textContaining('Sprout'), findsOneWidget);
      expect(await harness.completions.completionsFor('a'), hasLength(1));
    });

    testWidgets('a watering offers an undo, and the undo takes it back', (
      tester,
    ) async {
      final harness = PageHarness();
      await harness.habits.saveHabit(testHabit(id: 'a'));
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await holdToWater(tester);
      expect(find.text(GardenPage.wateredMessage), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(PlantCard.undoLabel),
        ),
      );
      await tester.pumpAndSettle();

      expect(await harness.completions.completionsFor('a'), isEmpty);
      expect(find.textContaining('Seed'), findsOneWidget);
    });

    testWidgets('the undo stays on the card after the offer has gone', (
      tester,
    ) async {
      // The transient snack bar is the shortcut; the card carries the
      // correction for the rest of the day the watering happened on.
      final harness = PageHarness();
      await harness.habits.saveHabit(testHabit(id: 'a'));
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await holdToWater(tester);
      await tester.pump(AppMotion.undoOfferDuration);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);

      await tester.tap(find.text(PlantCard.undoLabel));
      await tester.pumpAndSettle();

      expect(await harness.completions.completionsFor('a'), isEmpty);
    });

    testWidgets('a plant carries its whole state in one semantic label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final harness = PageHarness();
      await harness.habits.saveHabit(testHabit(id: 'a', name: 'Morning walk'));
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(
          RegExp(r'^Morning walk, seed, .+, no roots yet$'),
        ),
        findsOneWidget,
      );

      // The button says what it does; it does not repeat the description.
      final control = tester.getSemantics(find.byType(WateringControl));
      expect(control.label, 'Water Morning walk');
      handle.dispose();
    });

    testWidgets('watering and undoing stay separately reachable', (
      tester,
    ) async {
      // They are two tap actions on one card. If the card merged its children
      // a screen reader would only ever get one of them.
      final handle = tester.ensureSemantics();
      final harness = PageHarness();
      await harness.habits.saveHabit(testHabit(id: 'a', name: 'Morning walk'));
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await holdToWater(tester);

      tester.semantics.tap(
        find.semantics.byLabel('Undo watering Morning walk'),
      );
      await tester.pumpAndSettle();

      expect(await harness.completions.completionsFor('a'), isEmpty);
      handle.dispose();
    });
  });
}
