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
import 'package:taproot/features/garden/domain/garden_ticker.dart';
import 'package:taproot/features/garden/pages/garden_page.dart';
import 'package:taproot/features/garden/providers/plant_art_providers.dart';
import 'package:taproot/core/models/reflection.dart';
import 'package:taproot/features/reflection/domain/reflection_repository.dart';
import 'package:taproot/features/reflection/providers/reflection_providers.dart';
import 'package:taproot/features/reflection/widgets/check_in_chip.dart';
import 'package:taproot/features/reflection/widgets/check_in_commit.dart';
import 'package:taproot/features/reflection/widgets/check_in_done.dart';
import 'package:taproot/features/reflection/widgets/check_in_sheet.dart';
import 'package:taproot/features/reflection/widgets/check_in_look_back.dart';
import 'package:taproot/features/reflection/widgets/check_in_sheet_host.dart';

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

  Future<void> pumpCheckIn(
    WidgetTester tester, {
    ReflectionRepository? reflections,
    String Function()? newId,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          habitServiceProvider.overrideWithValue(store.habits),
          completionServiceProvider.overrideWithValue(store.completions),
          reflectionServiceProvider.overrideWithValue(
            reflections ?? store.reflections,
          ),
          nudgeServiceProvider.overrideWithValue(store.nudges),
          clockProvider.overrideWithValue(() => clock.now),
          newIdProvider.overrideWithValue(newId ?? () => 'reflection-1'),
          // The check-in is a sheet on the garden now, so these pump the
          // garden. No plant art: the sheet is what is under test, and
          // loading the native library would make every one of these depend on
          // a setup step outside `flutter pub get`.
          plantArtFileProvider.overrideWith((ref, plantType) async => null),
          gardenTickerProvider.overrideWith(_StillTicker.new),
        ],
        child: const MaterialApp(home: GardenPage(showCheckIn: true)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> plantAndWater({
    String? designedCue = 'after breakfast',
    HabitCategory? category = HabitCategory.exercise,
    // Daily by default in the commit tests, so "the next occasion" is
    // unambiguously tomorrow rather than whichever day a 3-a-week cadence
    // happens to land on.
    int targetFrequency = 3,
  }) async {
    await store.habits.saveHabit(
      testHabit(
        category: category,
        targetFrequency: targetFrequency,
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

  /// The chip carrying [label], whatever state it is in.
  Finder chip(String label) => find.widgetWithText(CheckInChip, label);
  Finder link(String label) => find.widgetWithText(CheckInFooterLink, label);

  testWidgets('says so calmly when there is nothing to ask', (tester) async {
    // Most days there is no check-in, and that is the design rather than a
    // failure to find one.
    await pumpCheckIn(tester);

    expect(find.text(CheckInSheetHost.nothingHeadline), findsOneWidget);
    expect(find.byType(CheckInChip), findsNothing);
  });

  testWidgets('validation asks yes or no before it asks anything else', (
    tester,
  ) async {
    // reflection-logic §3 wants the designed cue *tested*, which is a yes/no
    // question. Showing the full chip list immediately — which is what the
    // page used to do — makes a Validation indistinguishable from a Discovery.
    await plantAndWater();
    await pumpCheckIn(tester);

    expect(find.text('Did after breakfast kick it off?'), findsOneWidget);
    expect(chip(CheckInLookBack.yesLabel), findsOneWidget);
    expect(chip(CheckInLookBack.validationNoLabel), findsOneWidget);
    // Not yet: `Something else` and `Can't remember` answer an open question,
    // and there is not one on screen.
    expect(link(CheckInLookBack.somethingElseLabel), findsNothing);
    expect(link(CheckInLookBack.cantRememberLabel), findsNothing);
    // The way out is always available.
    expect(link(CheckInLookBack.skipLabel), findsOneWidget);
  });

  testWidgets('yes answers with the designed cue, and counts as a match', (
    tester,
  ) async {
    await plantAndWater();
    await pumpCheckIn(tester);

    await tester.tap(chip(CheckInLookBack.yesLabel));
    await tester.pumpAndSettle();

    final saved = (await store.reflections.reflectionsFor('habit-1')).single;
    expect(saved.cueReported, 'after breakfast');
    expect(saved.framing, Framing.validation);
    // Which is what cue reliability counts.
    expect(saved.matchedDesignedCue, isTrue);
  });

  testWidgets('no opens the list, without the cue that was just ruled out', (
    tester,
  ) async {
    await plantAndWater();
    await pumpCheckIn(tester);

    await tester.tap(chip(CheckInLookBack.validationNoLabel));
    await tester.pumpAndSettle();

    expect(find.text('What got you going, then?'), findsOneWidget);
    // The user has just said it was not that, so offering it back would be
    // the app not listening.
    expect(chip('after breakfast'), findsNothing);
    // And "No, something else" was not itself an answer.
    expect(await store.reflections.reflectionsFor('habit-1'), isEmpty);
    // The open question brings its footer with it.
    expect(link(CheckInLookBack.somethingElseLabel), findsOneWidget);
    expect(link(CheckInLookBack.cantRememberLabel), findsOneWidget);
  });

  testWidgets("can't remember is recorded, not discarded", (tester) async {
    // A rising can't-remember rate is itself the signal that a habit is running
    // on autopilot without awareness.
    await plantAndWater();
    await pumpCheckIn(tester);
    await tester.tap(chip(CheckInLookBack.validationNoLabel));
    await tester.pumpAndSettle();

    await tester.tap(link(CheckInLookBack.cantRememberLabel));
    await tester.pumpAndSettle();

    final saved = (await store.reflections.reflectionsFor('habit-1')).single;
    expect(saved.inputMode, InputMode.cantRemember);
    expect(saved.cueReported, isNull);
  });

  testWidgets('typing is available, but it is not the default', (tester) async {
    await plantAndWater();
    await pumpCheckIn(tester);
    await tester.tap(chip(CheckInLookBack.validationNoLabel));
    await tester.pumpAndSettle();

    // No field until it is asked for.
    expect(find.byType(TextField), findsNothing);

    await tester.tap(link(CheckInLookBack.somethingElseLabel));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'the dog woke me');
    await tester.pumpAndSettle();

    final save = find.widgetWithText(FilledButton, CheckInLookBack.saveLabel);
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
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

    expect(find.textContaining('What got in the way?'), findsOneWidget);
    // States the absence, never the person.
    expect(find.textContaining('missed'), findsNothing);
    expect(find.textContaining('No morning run'), findsOneWidget);
    // Diagnosis never offers `Can't remember`: "I don't know why I didn't" is
    // not evidence of autopilot, it is just a shrug.
    expect(link(CheckInLookBack.cantRememberLabel), findsNothing);

    await tester.tap(chip('just forgot'));
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

    await tester.tap(link(CheckInLookBack.skipLabel));
    await tester.pumpAndSettle();

    final saved = (await store.reflections.reflectionsFor('habit-1')).single;
    expect(saved.inputMode, InputMode.skipped);
  });

  testWidgets('answering moves on to committing to the next occasion', (
    tester,
  ) async {
    await plantAndWater(targetFrequency: 7);
    // Every expected occasion gets a ledger row, including the ones
    // deliberately not nudged — that is what autonomy is counted over.
    await store.nudges.saveNudge(
      NudgeRecord(
        id: 'n-next',
        habitId: 'habit-1',
        expectedOccasionAt: DateTime(2026, 3, 13, 7),
        sent: false,
      ),
    );
    await pumpCheckIn(tester);

    await tester.tap(chip(CheckInLookBack.yesLabel));
    await tester.pumpAndSettle();
    // Tests run with motion off, so there is no auto-advance and a Next button
    // appears instead — which is the reduced-motion contract, not a detour.
    await tester.tap(
      find.widgetWithText(FilledButton, CheckInLookBack.nextLabel),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tomorrow, then.'), findsOneWidget);
    expect(chip(CheckInCommit.differentDayLabel), findsOneWidget);
  });

  testWidgets('the commitment goes to the ledger, not onto the reflection', (
    tester,
  ) async {
    // It is an answer about a *future* occasion, and the ledger is what the
    // engine reads for autonomy and day-of-week preference.
    await plantAndWater(targetFrequency: 7);
    await store.nudges.saveNudge(
      NudgeRecord(
        id: 'n-next',
        habitId: 'habit-1',
        expectedOccasionAt: DateTime(2026, 3, 13, 7),
        sent: false,
      ),
    );
    await pumpCheckIn(tester);

    await tester.tap(chip(CheckInLookBack.yesLabel));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, CheckInLookBack.nextLabel),
    );
    await tester.pumpAndSettle();
    await tester.tap(chip(CheckInCommit.differentDayLabel));
    await tester.pumpAndSettle();

    final ledger = await store.nudges.nudgesFor('habit-1');
    final next = ledger.firstWhere((row) => row.id == 'n-next');
    // A decline is not a failure, it is data.
    expect(next.declined, isTrue);
    expect(next.confirmed, isFalse);
  });

  testWidgets('there is no commit step when there is nothing to commit to', (
    tester,
  ) async {
    // No ledger row means the planner has not reached the occasion, and
    // recording against a row that does not exist would invent one.
    await plantAndWater();
    await pumpCheckIn(tester);

    // The meta row promises one step, not two, before the answer lands.
    expect(find.textContaining('1 of 1'), findsOneWidget);

    await tester.tap(chip(CheckInLookBack.yesLabel));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, CheckInLookBack.nextLabel),
    );
    await tester.pumpAndSettle();

    // Straight to done, skipping the step it never promised. Asserted on the
    // meta row rather than a chip, because both steps have a chip called "Yes".
    expect(find.textContaining('done'), findsOneWidget);
    expect(find.text('Tomorrow, then.'), findsNothing);
  });

  testWidgets('the roots grow when done appears, never earlier', (
    tester,
  ) async {
    // The whole reason the check-in is a sheet over the garden: the reflection
    // is written on *answer*, so the engine's root depth moves immediately.
    // Pinning it until done is what makes the growth land with the payoff
    // rather than while the user is still mid-question.
    await plantAndWater();
    await pumpCheckIn(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(CheckInSheet)),
    );
    final before = container.read(drawnRootDepthProvider('habit-1'));

    await tester.tap(chip(CheckInLookBack.yesLabel));
    await tester.pumpAndSettle();

    // Answered and written, but the roots have not moved.
    expect((await store.reflections.reflectionsFor('habit-1')), hasLength(1));
    expect(container.read(drawnRootDepthProvider('habit-1')), before);

    await tester.tap(
      find.widgetWithText(FilledButton, CheckInLookBack.nextLabel),
    );
    await tester.pumpAndSettle();

    expect(find.text(CheckInDone.rootsTitle), findsOneWidget);
    // Released, so Rive can ease them to their new depth.
    expect(
      container.read(drawnRootDepthProvider('habit-1')),
      greaterThan(before),
    );
  });

  testWidgets('done never shows a credit value or a reflection count', (
    tester,
  ) async {
    await plantAndWater();
    await pumpCheckIn(tester);
    await tester.tap(chip(CheckInLookBack.yesLabel));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, CheckInLookBack.nextLabel),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('credit'), findsNothing);
    expect(find.textContaining('reflections'), findsNothing);
    expect(find.text(CheckInDone.backLabel), findsOneWidget);
  });

  testWidgets('a retry after a failed save writes one reflection, not two', (
    tester,
  ) async {
    // `saveReflection` inserts or updates **by id**, so a retry is idempotent
    // as long as it retries with the same id. Minting a fresh one per attempt
    // threw that away: two rows for one check-in, `reflectionCount` up, the
    // weekly budget spent twice, and the same cue counted twice in the
    // convergence window — all off a single answer the user gave once.
    var ids = 0;
    final flaky = _FlakyReflections(store.reflections);

    await plantAndWater();
    await pumpCheckIn(
      tester,
      reflections: flaky,
      newId: () => 'reflection-${++ids}',
    );

    await tester.tap(chip(CheckInLookBack.yesLabel));
    await tester.pumpAndSettle();

    // The first attempt wrote the row and then threw on the way out, so the
    // sheet is back on the question with the chips live again.
    expect(chip(CheckInLookBack.yesLabel), findsOneWidget);

    await tester.tap(chip(CheckInLookBack.yesLabel));
    await tester.pumpAndSettle();

    final saved = await store.reflections.reflectionsFor('habit-1');
    expect(saved, hasLength(1));
    expect(ids, 1, reason: 'the id is minted once per offer, not per attempt');
  });
}

/// Writes the row and *then* fails, once — the failure nobody can classify.
///
/// This is the shape that makes the id matter: the caller cannot tell whether
/// the row landed, so the honest thing to do is offer a retry, and the retry
/// has to be safe.
class _FlakyReflections implements ReflectionRepository {
  _FlakyReflections(this._inner);

  final ReflectionRepository _inner;
  bool _hasFailed = false;

  @override
  Future<void> saveReflection(Reflection reflection) async {
    await _inner.saveReflection(reflection);
    if (_hasFailed) return;
    _hasFailed = true;
    throw StateError('the connection dropped on the way out');
  }

  @override
  Future<List<Reflection>> reflectionsFor(String habitId) =>
      _inner.reflectionsFor(habitId);

  @override
  Future<List<Reflection>> recentReflections(String habitId, {int limit = 8}) =>
      _inner.recentReflections(habitId, limit: limit);
}

class _StillTicker extends GardenTickerController {
  @override
  GardenTicker build() => GardenTicker.still;
}
