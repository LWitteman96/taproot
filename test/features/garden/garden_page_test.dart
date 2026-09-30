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
import 'package:taproot/features/garden/providers/plant_art_providers.dart';
import 'package:taproot/app/theme/garden_layout.dart';
import 'package:taproot/features/garden/widgets/empty_plot.dart';
import 'package:taproot/features/garden/widgets/plant_detail_card.dart';
import 'package:taproot/features/garden/controllers/garden_controller.dart';
import 'package:taproot/features/garden/widgets/watering_control.dart';
import 'package:taproot/features/habits/domain/completion_repository.dart';
import 'package:taproot/features/habits/domain/habit_repository.dart';
import 'package:taproot/features/habits/providers/habit_providers.dart';
import 'package:taproot/features/notifications/providers/nudge_providers.dart';
import 'package:taproot/features/reflection/controllers/check_in_controller.dart';
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
      // No plant art here, explicitly. Left alone this would try to load the
      // native library and the .riv, which is a real dependency on a setup
      // step outside `flutter pub get` — and the async load happening to lose
      // the race with the test's pumps is not the same thing as a test that
      // does not depend on it. `plant_art_view_test.dart` covers the drawn
      // path; these tests are about the card.
      plantArtFileProvider.overrideWith((ref, plantType) async => null),
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
      expect(find.byType(PlantDetailCard), findsNothing);
    });

    testWidgets('an empty garden offers the flow that fills it', (
      tester,
    ) async {
      // The dev seed button that used to sit here is gone: habit creation is
      // real, and the entry gate now sends a user with nothing planted
      // straight into it.
      final harness = PageHarness();
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(find.text(GardenPage.plantLabel), findsOneWidget);
    });

    testWidgets('holding waters the plant and it grows in place', (
      tester,
    ) async {
      final harness = PageHarness();
      await harness.store.saveHabit(testHabit(id: 'a', name: 'Morning walk'));
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      // On the card, not the plant: the silhouette carries the same word, and
      // the point here is that the card followed the engine.
      Finder onCard(String word) => find.descendant(
        of: find.byType(PlantDetailCard),
        matching: find.textContaining(word),
      );
      expect(onCard('seed'), findsOneWidget);

      await holdToWater(tester);

      expect(onCard('sprout'), findsOneWidget);
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

      // The undo sits on the detail card rather than in a snack bar. The card
      // is the standing correction for the rest of the day the watering
      // happened on, so it does not time out and it does not cover the garden.
      await tester.tap(find.text(PlantDetailCard.undoLabel));
      await tester.pumpAndSettle();

      expect(await harness.completions.completionsFor('a'), isEmpty);
      expect(find.textContaining('seed'), findsOneWidget);
    });

    testWidgets('the undo stays on the card after the offer has gone', (
      tester,
    ) async {
      // The card carries the correction for the rest of the day the watering
      // happened on, and nothing about it expires with a snack bar.
      final harness = PageHarness();
      await harness.store.saveHabit(testHabit(id: 'a'));
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await holdToWater(tester);
      await tester.pump(AppMotion.undoOfferDuration);
      await tester.pumpAndSettle();

      // No snack bar to outlive: the correction was never transient.
      expect(find.byType(SnackBar), findsNothing);

      await tester.tap(find.text(PlantDetailCard.undoLabel));
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

      expect(find.byType(PlantDetailCard), findsOneWidget);
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
      expect(find.textContaining('seed'), findsOneWidget);
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
      await tester.pumpAndSettle();
      // The garden was left open across midnight, so the card's standing offer
      // went stale.
      harness.clock.advance(const Duration(days: 1));

      await tester.tap(find.text(PlantDetailCard.undoLabel));
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

  group('the garden row', () {
    testWidgets('tapping a plant selects it and the card follows', (
      tester,
    ) async {
      final harness = PageHarness();
      await harness.store.saveHabit(testHabit(id: 'a', name: 'Morning walk'));
      await harness.store.saveHabit(testHabit(id: 'b', name: 'Evening read'));
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      // The first plant is selected by default: there is always a selected
      // habit, because an empty card would be a worse state than a stale one.
      expect(
        find.descendant(
          of: find.byType(PlantDetailCard),
          matching: find.text('Morning walk'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.bySemanticsLabel(RegExp('^Evening read,')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(PlantDetailCard),
          matching: find.text('Evening read'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the whole column is the target, not the plant', (
      tester,
    ) async {
      // A seed is 11pt wide. garden-design §4.3 makes the 128pt column the
      // target so selecting one is not a precision exercise.
      final harness = PageHarness();
      await harness.store.saveHabit(testHabit(id: 'a', name: 'Morning walk'));
      await harness.store.saveHabit(testHabit(id: 'b', name: 'Evening read'));
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      final column = find.byWidgetPredicate(
        (widget) => widget is PlantHitColumn,
      );
      expect(column, findsNWidgets(2));
      // Tall enough to cover the plant and the roots that will hang below it.
      final size = tester.getSize(column.at(1));
      expect(size.width, GardenLayout.slotPitch);
      expect(size.height, greaterThan(GardenLayout.rootsDepth));
    });

    testWidgets('the empty plot offers the flow that fills the garden', (
      tester,
    ) async {
      final harness = PageHarness();
      await harness.store.saveHabit(testHabit(id: 'a'));
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      // It follows the plants rather than floating over them: a new habit
      // appears where the offer was.
      expect(find.byType(EmptyPlot), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('a garden that could not be read offers no plot', (
      tester,
    ) async {
      // An invitation to plant something, over a garden that may already have
      // plants in it we simply could not read, is an invitation to duplicate
      // them.
      final harness = PageHarness();
      await harness.store.saveHabit(testHabit(id: 'a'));
      harness.habits.readFailure = StateError('the disk is unreadable');
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(find.byType(EmptyPlot), findsNothing);
      expect(find.text(GardenPage.unreadableHeadline), findsOneWidget);
    });

    testWidgets('the garden scrolls once there are more plants than fit', (
      tester,
    ) async {
      final harness = PageHarness();
      for (var i = 0; i < 6; i++) {
        await harness.store.saveHabit(testHabit(id: '$i', name: 'Habit $i'));
      }
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable);
      expect(scrollable, findsOneWidget);
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.axisDirection, AxisDirection.right);
      expect(position.maxScrollExtent, greaterThan(0));
    });
  });

  group('the Reflect button', () {
    testWidgets('is absent when the check-in is not about this plant', (
      tester,
    ) async {
      // reflection-logic §2 expects no check-in on most days. A standing
      // Reflect button would quietly argue the opposite, and would open a
      // sheet with nothing to ask.
      final harness = PageHarness();
      await harness.store.saveHabit(testHabit(id: 'a', name: 'Morning walk'));
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(find.text(PlantDetailCard.reflectLabel), findsNothing);
    });

    testWidgets('appears once the check-in names this plant', (tester) async {
      final harness = PageHarness();
      await harness.store.saveHabit(
        testHabit(id: 'a', name: 'Morning walk', designedCue: 'after coffee'),
      );
      await harness.completions.recordCompletion(
        Completion(
          id: 'c1',
          habitId: 'a',
          completedAt: DateTime(2026, 3, 4, 7),
          source: CompletionSource.tap,
        ),
      );
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(find.text(PlantDetailCard.reflectLabel), findsOneWidget);
    });
  });

  group('the check-in invitation', () {
    testWidgets('is absent when there is nothing worth asking', (tester) async {
      // reflection-logic §2 expects no check-in on most days. A standing button
      // that usually opens a screen saying "nothing to ask" would teach the
      // user to stop pressing it.
      final harness = PageHarness();
      await harness.store.saveHabit(testHabit(id: 'a', name: 'Morning walk'));
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(find.byType(PlantDetailCard), findsOneWidget);
      expect(find.textContaining(GardenPage.checkInInvitation), findsNothing);
    });

    testWidgets('appears, named, once something is worth asking', (
      tester,
    ) async {
      final harness = PageHarness();
      await harness.store.saveHabit(
        testHabit(
          id: 'a',
          name: 'Morning walk',
          createdAt: DateTime(2026, 2, 1),
        ),
      );
      await harness.completions.recordCompletion(
        Completion(
          id: 'c1',
          habitId: 'a',
          completedAt: DateTime(2026, 3, 4, 7),
          source: CompletionSource.tap,
        ),
      );

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      // Named, so the invitation says what it is about rather than being a
      // generic errand. Not tapped here: the destination is a route, and this
      // harness deliberately has no router — the check-in page has its own
      // tests.
      expect(find.textContaining(GardenPage.checkInInvitation), findsOneWidget);
      expect(find.textContaining('morning walk'), findsOneWidget);
    });

    testWidgets('and goes away once the question has been answered', (
      tester,
    ) async {
      // `push` leaves the garden in the stack, so its offer provider is never
      // disposed and never re-runs on the way back. Without the controller
      // invalidating it, the chip sits there naming a habit that has just been
      // answered — and tapping it lands on "nothing to ask", because the 24h
      // cooldown the answer just started is what the assembler now sees. It
      // reads as a task the app will not let you finish.
      final harness = PageHarness();
      await harness.store.saveHabit(
        testHabit(
          id: 'a',
          name: 'Morning walk',
          createdAt: DateTime(2026, 2, 1),
        ),
      );
      await harness.completions.recordCompletion(
        Completion(
          id: 'c1',
          habitId: 'a',
          completedAt: DateTime(2026, 3, 4, 7),
          source: CompletionSource.tap,
        ),
      );

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      expect(find.textContaining(GardenPage.checkInInvitation), findsOneWidget);

      // The check-in itself is a route this harness does not have, so the
      // controller is driven directly — which is the layer the invalidation
      // lives in anyway.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(GardenPage)),
      );
      final controller = container.read(checkInControllerProvider.notifier);
      await controller.load();
      await controller.cantRemember();
      await tester.pumpAndSettle();

      expect(find.textContaining(GardenPage.checkInInvitation), findsNothing);
    });
  });
}
