import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/completion.dart';
import 'package:taproot/core/models/habit.dart';
import 'package:taproot/core/models/habit_category.dart';
import 'package:taproot/core/models/nudge.dart';
import 'package:taproot/core/models/reflection.dart';
import 'package:taproot/core/utils/local_dates.dart';
import 'package:taproot/features/habits/services/habit_inputs_loader.dart';
import 'package:taproot/features/notifications/domain/expected_occasions.dart';
import 'package:taproot/features/reflection/domain/check_in_question.dart';
import 'package:taproot/features/reflection/services/check_in_assembler.dart';
import 'package:taproot/features/reflection/services/check_in_prompt_composer.dart';

import '../../../utils/fake_repositories.dart';
import '../../../utils/store_contract.dart';
import '../../../utils/store_fixtures.dart';

/// The reflection half of the evening notification, composed early.
///
/// Two properties carry this file. **The notification asks what the screen
/// would ask** — same functions, same sentence, or the app has two voices. And
/// **composing early never invents a day**: the ledger holds rows for occasions
/// that have not happened, and reading those as the user's failures is the
/// whole hazard of writing a question up to a week before it is read.
void main() {
  late TestStore store;
  late TestClock clock;
  late HabitInputsLoader loader;
  late CheckInPromptComposer composer;

  // Thursday, 2026-03-12, mid-evening.
  final now = DateTime(2026, 3, 12, 20);

  setUp(() async {
    clock = TestClock(now);
    store = await openFakeStore(clock);
    addTearDown(store.dispose);
    loader = HabitInputsLoader(
      habits: store.habits,
      completions: store.completions,
      reflections: store.reflections,
      nudges: store.nudges,
    );
    composer = CheckInPromptComposer(loader: loader, clock: () => clock.now);
  });

  Future<Habit> plant({
    String? designedCue = 'after breakfast',
    HabitCategory? category = HabitCategory.exercise,
  }) async {
    final habit = testHabit(
      name: 'Morning run',
      category: category,
      designedCue: designedCue,
      designedCueType: designedCue == null ? null : CueType.event,
      createdAt: DateTime(2026, 1, 1),
    );
    await store.habits.saveHabit(habit);
    return habit;
  }

  Future<void> water(DateTime at) => store.completions.recordCompletion(
    Completion(
      id: 'c-${at.millisecondsSinceEpoch}',
      habitId: 'habit-1',
      completedAt: at,
      source: CompletionSource.tap,
    ),
  );

  /// A ledger row in the shape the scheduler writes: local midnight.
  Future<void> expect_(DateTime day, {bool sent = true}) =>
      store.nudges.saveNudge(
        NudgeRecord(
          id: 'n-${day.millisecondsSinceEpoch}',
          habitId: 'habit-1',
          expectedOccasionAt: DateTime(day.year, day.month, day.day),
          sent: sent,
        ),
      );

  /// The occasion the notification commits the user to — the day *after* the
  /// evening it arrives, which is what the nudge half is about.
  ExpectedOccasion occasionOn(DateTime day) =>
      ExpectedOccasion(index: 0, date: LocalDate.from(day));

  Future<String?> promptFor(Habit habit, {required DateTime deliverAt}) =>
      composer.promptFor(
        habit: habit,
        occasion: occasionOn(deliverAt.add(const Duration(days: 1))),
        deliverAt: deliverAt,
      );

  test('a habit nothing has happened to carries no question', () async {
    // The common answer, and the one the freshly-planted habit gets: scoring
    // is per *occasion* — a completion, a missed expected occasion, an
    // un-nudged completion — and a habit planted an hour ago has none. Nothing
    // is scored and rejected; there is nothing to score.
    final habit = await plant();

    expect(await promptFor(habit, deliverAt: now), isNull);
  });

  test('a paused habit is never asked', () async {
    await plant();
    await water(DateTime(2026, 3, 12, 7, 10));
    await store.habits.pauseHabit('habit-1');

    final paused = (await store.habits.habitById('habit-1'))!;
    expect(await promptFor(paused, deliverAt: now), isNull);
  });

  test('the notification asks what the screen would ask', () async {
    // The guarantee the whole seam exists for. Reflection and the next-day
    // nudge are one message (§1), and the screen and the notification compose
    // it through the same functions — so this compares the two surfaces
    // directly rather than asserting a copied sentence in either.
    final habit = await plant();
    await water(DateTime(2026, 3, 12, 7, 10));

    final assembler = CheckInAssembler(
      habits: store.habits,
      loader: loader,
      clock: () => clock.now,
    );
    final onScreen = await assembler.nextCheckIn();
    expect(onScreen, isNotNull);

    final screenQuestion = checkInQuestion(
      framing: onScreen!.framing,
      habit: onScreen.habit,
      occasionAt: onScreen.candidate.occasion.at,
      now: now,
    );

    expect(await promptFor(habit, deliverAt: now), screenQuestion);
    expect(screenQuestion, 'Did after breakfast kick it off?');
  });

  test('the wording is read at delivery, not at composition', () async {
    // Composed this evening, read tomorrow evening. `today` would be a day
    // wrong by the time anybody sees it.
    final habit = await plant();
    await expect_(DateTime(2026, 3, 11), sent: false);
    await expect_(DateTime(2026, 3, 9));

    final tonight = await promptFor(habit, deliverAt: now);
    final tomorrow = await promptFor(
      habit,
      deliverAt: DateTime(2026, 3, 13, 20),
    );

    expect(tonight, 'No morning run yesterday — what got in the way?');
    expect(
      tomorrow,
      'No morning run on Wednesday — what got in the way?',
      reason: 'two days back by the time it arrives, so it says the weekday',
    );
  });

  group('composing early never invents a day', () {
    test('a question written a week out asks about the last real day', () async {
      // The hazard in one test. The ledger holds rows up to seven days ahead —
      // written before the occasions happen, which is the scheduler's whole
      // job — and every one of them is un-completed, because the days have not
      // arrived. Detected at `deliverAt` they would all read as misses, and
      // the app would queue *"No morning run on Tuesday — what got in the
      // way?"* about a Tuesday nobody has lived yet.
      final habit = await plant();
      await water(DateTime(2026, 3, 12, 7, 10));
      for (var day = 13; day <= 19; day++) {
        await expect_(DateTime(2026, 3, day), sent: false);
      }

      final question = await promptFor(
        habit,
        deliverAt: DateTime(2026, 3, 18, 20),
      );

      expect(question, isNotNull);
      expect(
        question,
        isNot(contains('what got in the way')),
        reason: 'no day between now and delivery has happened yet',
      );
      expect(question, 'Did after breakfast kick it off?');
    });

    test(
      'and today is not yet a miss when the pass runs in the morning',
      () async {
        // The same rule one day in: a row for today is stamped local midnight,
        // so a morning pass must not read it as a day already lost.
        final habit = await plant();
        clock.now = DateTime(2026, 3, 12, 8);
        await expect_(DateTime(2026, 3, 12), sent: false);

        expect(
          await promptFor(habit, deliverAt: DateTime(2026, 3, 12, 20)),
          isNull,
        );
      },
    );
  });

  test('the weekly budget is spent by the evening it arrives', () async {
    // A question queued on Monday for Thursday is Thursday's spend, not
    // Monday's — which is what lets §2's budget mean the same thing here and
    // on the screen.
    //
    // The occasion is a miss rather than a completion so that the budget is
    // the only thing under test: a miss carries enough weight to clear the
    // threshold on its own, so a null answer here is the budget and nothing
    // else.
    final habit = await plant();
    for (var index = 0; index < 3; index++) {
      await store.reflections.saveReflection(
        Reflection(
          id: 'r$index',
          habitId: 'habit-1',
          createdAt: DateTime(2026, 3, 8 + index, 20),
          occasion: Occasion.completion,
          framing: Framing.validation,
          inputMode: InputMode.chip,
          cueReported: 'after breakfast',
          cueType: CueType.event,
        ),
      );
    }
    await expect_(DateTime(2026, 3, 11), sent: false);

    // Tonight, all three are inside the seven-day window: the week is full.
    expect(await promptFor(habit, deliverAt: now), isNull);

    // By the following Tuesday they have aged out of it, and the same occasion
    // is worth asking about again.
    expect(
      await promptFor(habit, deliverAt: DateTime(2026, 3, 17, 20)),
      isNotNull,
    );
  });
}
