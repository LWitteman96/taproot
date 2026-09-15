import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/app/runtime/runtime_providers.dart';
import 'package:taproot/core/models/completion.dart';
import 'package:taproot/core/models/habit.dart';
import 'package:taproot/core/models/pause_interval.dart';
import 'package:taproot/app/theme/app_motion.dart';
import 'package:taproot/app/theme/themedata.dart';
import 'package:taproot/features/garden/domain/garden_ticker.dart';
import 'package:taproot/features/garden/pages/garden_page.dart';
import 'package:taproot/features/garden/widgets/plant_card.dart';
import 'package:taproot/features/garden/controllers/garden_controller.dart';
import 'package:taproot/features/garden/widgets/watering_control.dart';
import 'package:taproot/features/habits/domain/completion_repository.dart';
import 'package:taproot/features/habits/domain/habit_repository.dart';
import 'package:taproot/features/habits/providers/habit_providers.dart';
import 'package:taproot/features/notifications/providers/nudge_providers.dart';
import 'package:taproot/features/reflection/providers/reflection_providers.dart';

import '../../utils/fake_repositories.dart';
import '../../utils/store_fixtures.dart';

/// A habit store whose read can be broken, so the page's failure paths are
/// reachable from a widget test.
///
/// Wrapping rather than reimplementing, for the same reason the controller test
/// does: everything it does not intercept is the fake the SQLite services are
/// contract-tested against.
class BreakableHabits implements HabitRepository {
  BreakableHabits(this.inner);

  final FakeHabitService inner;

  /// Thrown instead of listing.
  Object? readFailure;

  @override
  Future<List<Habit>> allHabits() async {
    if (readFailure case final failure?) throw failure;
    return inner.allHabits();
  }

  @override
  Future<Habit?> habitById(String habitId) => inner.habitById(habitId);

  @override
  Future<void> saveHabit(Habit habit) => inner.saveHabit(habit);

  @override
  Future<void> deleteHabit(String habitId) => inner.deleteHabit(habitId);

  @override
  Future<void> pauseHabit(String habitId) => inner.pauseHabit(habitId);

  @override
  Future<void> resumeHabit(String habitId) => inner.resumeHabit(habitId);

  @override
  Future<List<PauseInterval>> pausesFor(String habitId) =>
      inner.pausesFor(habitId);
}

/// A completion store whose write can be broken.
class BreakableCompletions implements CompletionRepository {
  BreakableCompletions(this.inner);

  final FakeCompletionService inner;

  /// Thrown instead of recording.
  Object? recordFailure;

  @override
  Future<void> recordCompletion(Completion completion) async {
    if (recordFailure case final failure?) throw failure;
    return inner.recordCompletion(completion);
  }

  @override
  Future<void> retractCompletion(String habitId, String completionId) =>
      inner.retractCompletion(habitId, completionId);

  @override
  Future<void> recordRetraction(
    String habitId,
    String completionId, {
    required DateTime retractedAt,
  }) => inner.recordRetraction(habitId, completionId, retractedAt: retractedAt);

  @override
  Future<List<Completion>> completionsFor(String habitId) =>
      inner.completionsFor(habitId);

  @override
  Future<List<Completion>> completionsOnLocalDate(String habitId, date) =>
      inner.completionsOnLocalDate(habitId, date);

  @override
  Future<Completion?> latestCompletion(String habitId) =>
      inner.latestCompletion(habitId);
}

class PageHarness {
  PageHarness() {
    store = FakeHabitService(clock: clock.call);
    habits = BreakableHabits(store);
    completions = BreakableCompletions(
      FakeCompletionService(habits: store, clock: clock.call),
    );
  }

  final TestClock clock = TestClock(DateTime(2026, 3, 4, 9));

  /// The store to write fixtures into — [habits] is the breakable face of it.
  late final FakeHabitService store;
  late final BreakableHabits habits;
  late final BreakableCompletions completions;
  int _nextId = 1;

  Widget get app => ProviderScope(
    overrides: [
      habitServiceProvider.overrideWithValue(habits),
      completionServiceProvider.overrideWithValue(completions),
      reflectionServiceProvider.overrideWithValue(
        FakeReflectionService(habits: store, clock: clock.call),
      ),
      nudgeServiceProvider.overrideWithValue(FakeNudgeService(habits: store)),
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
      await harness.store.saveHabit(testHabit(id: 'a', name: 'Morning walk'));
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
      await harness.store.saveHabit(testHabit(id: 'a'));
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
      await harness.store.saveHabit(testHabit(id: 'a'));
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

    testWidgets('a failed read says so, and does not claim the garden is '
        'empty', (tester) async {
      // A failed load leaves `plants` and `order` empty, which used to fall
      // straight through to "Nothing planted yet" — the app telling someone
      // whose store failed that their work is gone, as soon as the snack bar
      // timed out.
      final harness = PageHarness();
      await harness.store.saveHabit(testHabit(id: 'a', name: 'Morning walk'));
      harness.habits.readFailure = StateError('the disk is unreadable');

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(find.text(couldNotReadGardenMessage), findsOneWidget);
      expect(find.text(GardenPage.unreadableHeadline), findsOneWidget);
      expect(find.text(GardenPage.emptyHeadline), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // And the offer of a retry is real, which the copy used not to be: it
      // promised a pull-to-refresh that existed nowhere in the app.
      harness.habits.readFailure = null;
      await tester.tap(find.text(GardenPage.retryLabel));
      await tester.pumpAndSettle();

      expect(find.byType(PlantCard), findsOneWidget);
      expect(find.text('Morning walk'), findsOneWidget);
    });

    testWidgets('a failed watering shows its message and leaves the plant '
        'where it was', (tester) async {
      // The error paths were untested at widget level, which is what let the
      // `ref.listen` double-rebuild survive: clearing the message inside the
      // listener rebuilt `gardenErrorProvider` twice in one frame and the
      // debug scheduler threw. An uncaught framework error fails this test.
      final harness = PageHarness();
      await harness.store.saveHabit(testHabit(id: 'a'));
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      harness.completions.recordFailure = StateError('the disk is full');
      await holdToWater(tester);

      expect(find.text(couldNotWaterMessage), findsOneWidget);
      expect(find.textContaining('Seed'), findsOneWidget);
      expect(await harness.completions.completionsFor('a'), isEmpty);
    });

    testWidgets('a second failure is announced again rather than swallowed', (
      tester,
    ) async {
      // The deferred clear has to actually run, or the message stays set and
      // the identical second failure never fires the listener.
      final harness = PageHarness();
      await harness.store.saveHabit(testHabit(id: 'a'));
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      harness.completions.recordFailure = StateError('the disk is full');
      await holdToWater(tester);
      expect(find.text(couldNotWaterMessage), findsOneWidget);

      await tester.pump(AppMotion.undoOfferDuration);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      await holdToWater(tester);
      expect(find.text(couldNotWaterMessage), findsOneWidget);
    });

    testWidgets('a stale undo offer explains the window rather than throwing', (
      tester,
    ) async {
      final harness = PageHarness();
      await harness.store.saveHabit(testHabit(id: 'a'));
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await holdToWater(tester);
      // Let the transient offer go, so the only Undo left is the card's.
      await tester.pump(AppMotion.undoOfferDuration);
      await tester.pumpAndSettle();
      // The garden was left open across midnight, so the card's standing offer
      // went stale.
      harness.clock.advance(const Duration(days: 1));

      await tester.tap(find.text(PlantCard.undoLabel));
      await tester.pumpAndSettle();

      expect(find.text(undoWindowClosedMessage), findsOneWidget);
      expect(await harness.completions.completionsFor('a'), hasLength(1));
    });

    testWidgets('a plant carries its whole state in one semantic label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final harness = PageHarness();
      await harness.store.saveHabit(testHabit(id: 'a', name: 'Morning walk'));
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
      await harness.store.saveHabit(testHabit(id: 'a', name: 'Morning walk'));
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
