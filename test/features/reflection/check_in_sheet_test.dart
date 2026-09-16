/// The check-in as a sheet over the garden.
///
/// These are about *where* the check-in is and what surrounds it. What it asks
/// is covered by the copy tests; whether to ask at all is reflection-logic's.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/app/runtime/runtime_providers.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/habit.dart';
import 'package:taproot/features/reflection/domain/check_in_scheduler.dart';
import 'package:taproot/features/reflection/domain/reflection_priority.dart';
import 'package:taproot/features/reflection/domain/starter_chip.dart';
import 'package:taproot/features/garden/domain/garden_camera.dart';
import 'package:taproot/features/garden/domain/garden_ticker.dart';
import 'package:taproot/features/garden/pages/garden_page.dart';
import 'package:taproot/features/garden/providers/plant_art_providers.dart';
import 'package:taproot/features/garden/widgets/plant_detail_card.dart';
import 'package:taproot/features/habits/providers/habit_providers.dart';
import 'package:taproot/features/notifications/providers/nudge_providers.dart';
import 'package:taproot/features/reflection/providers/reflection_providers.dart';
import 'package:taproot/features/reflection/services/check_in_assembler.dart';
import 'package:taproot/features/reflection/widgets/check_in_sheet.dart';

import '../../utils/fake_repositories.dart';
import '../../utils/store_fixtures.dart';

void main() {
  group('GardenCamera', () {
    test('home leaves the scene where it is', () {
      expect(GardenCamera.home.isHome, isTrue);
      expect(
        GardenCamera.home.transformFor(
          viewport: const Size(402, 874),
          groundLine: 463,
        ),
        Matrix4.identity(),
      );
    });

    test('the sheet camera raises the ground and pulls in', () {
      final camera = GardenCamera.onPlant(1);
      expect(camera.isHome, isFalse);
      expect(camera.groundLineFraction, 0.38);
      expect(camera.scale, 2.2);
    });

    test('the focused plant lands at the centre of the viewport', () {
      // The whole point of the move: the habit being reflected on is the one
      // in front of you, whatever it was doing in the scroll before.
      const viewport = Size(402, 874);
      const groundLine = 332.0;
      final camera = GardenCamera.onPlant(3);
      final transform = camera.transformFor(
        viewport: viewport,
        groundLine: groundLine,
      );
      final focused = MatrixUtils.transformPoint(
        transform,
        Offset(camera.focusSceneX!, groundLine),
      );
      expect(focused.dx, closeTo(viewport.width / 2, 1e-6));
      // And the ground line does not slide out from under it.
      expect(focused.dy, closeTo(groundLine, 1e-6));
    });

    test('full roots still fit below the raised ground line', () {
      // check-in-design §3: at 2.2x roots reach about 170pt, and the sheet has
      // to stay clear of them.
      final camera = GardenCamera.onPlant(0);
      expect(camera.rootsReach, closeTo(171.6, 0.1));
      const viewport = Size(402, 874);
      final groundLine = viewport.height * camera.groundLineFraction;
      expect(groundLine + camera.rootsReach, lessThan(viewport.height));
    });

    test(
      'a move interpolates without losing the plant it is moving around',
      () {
        // Mid-move the camera is neither home nor arrived, and a null focus
        // halfway through would snap the scene back to the scroll position.
        final target = GardenCamera.onPlant(2);
        final half = GardenCamera.lerp(GardenCamera.home, target, 0.5);
        expect(half.focusSceneX, target.focusSceneX);
        expect(half.scale, closeTo(1.6, 1e-9));
        expect(half.groundLineFraction, closeTo((0.53 + 0.38) / 2, 1e-9));
      },
    );
  });

  group('the sheet on the garden', () {
    testWidgets('the check-in opens over the garden, not instead of it', (
      tester,
    ) async {
      final harness = _Harness();
      final habit = testHabit(id: 'a', name: 'Morning run');
      await harness.store.saveHabit(habit);
      await tester.pumpWidget(harness.app(checkIn: harness.offerFor(habit)));
      await tester.pumpAndSettle();

      expect(find.byType(CheckInSheet), findsOneWidget);
      // The garden is still there behind it — which is the entire reason the
      // check-in is a sheet.
      expect(find.byType(GardenPage), findsOneWidget);
      // And its detail card is not, because the sheet covers that corner.
      expect(find.byType(PlantDetailCard), findsNothing);
    });

    testWidgets('the sheet names the habit and the step', (tester) async {
      final harness = _Harness();
      final habit = testHabit(id: 'a', name: 'Morning run');
      await harness.store.saveHabit(habit);
      await tester.pumpWidget(harness.app(checkIn: harness.offerFor(habit)));
      await tester.pumpAndSettle();

      expect(find.text(CheckInSheet.title), findsOneWidget);
      // The sheet covers the garden's own card, so without this nothing on
      // screen says which plant the question is about.
      expect(find.textContaining('Morning run'), findsWidgets);
    });

    testWidgets('no sheet without an offer', (tester) async {
      final harness = _Harness();
      await harness.store.saveHabit(testHabit(id: 'a'));
      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      expect(find.byType(CheckInSheet), findsNothing);
      expect(find.byType(PlantDetailCard), findsOneWidget);
    });
  });
}

class _Harness {
  _Harness() {
    store = FakeHabitService(clock: clock.call);
    completions = FakeCompletionService(habits: store, clock: clock.call);
  }

  final TestClock clock = TestClock(DateTime(2026, 3, 12, 20));
  late final FakeHabitService store;
  late final FakeCompletionService completions;

  /// An offer for [habit], assembled by hand. The sheet re-verifies whatever it
  /// is handed, so this only has to be shaped right — which habit and which
  /// framing are reflection-logic's job, not this test's.
  CheckInOffer offerFor(Habit habit) => CheckInOffer(
    habit: habit,
    candidate: CheckInCandidate(
      occasion: CheckInOccasion(
        habitId: habit.id,
        occasion: Occasion.completion,
        at: clock.call().subtract(const Duration(hours: 13)),
      ),
      framing: Framing.discovery,
      priority: 1,
    ),
    cueChips: const <StarterChip>[],
    frictionChips: const [],
    isFirstReflection: true,
  );

  Widget app({CheckInOffer? checkIn}) => ProviderScope(
    overrides: [
      habitServiceProvider.overrideWithValue(store),
      completionServiceProvider.overrideWithValue(completions),
      reflectionServiceProvider.overrideWithValue(
        FakeReflectionService(habits: store, clock: clock.call),
      ),
      nudgeServiceProvider.overrideWithValue(FakeNudgeService(habits: store)),
      clockProvider.overrideWithValue(clock.call),
      // No plant art: these tests are about the sheet, and loading the native
      // library for them would make every one depend on a setup step.
      riveFernFileProvider.overrideWith((ref) async => null),
      gardenTickerProvider.overrideWith(_StillTicker.new),
    ],
    child: MaterialApp(home: GardenPage(checkIn: checkIn)),
  );
}

class _StillTicker extends GardenTickerController {
  @override
  GardenTicker build() => GardenTicker.still;
}
