import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/completion.dart';
import 'package:taproot/core/models/habit_category.dart';
import 'package:taproot/core/models/nudge.dart';
import 'package:taproot/core/models/reflection.dart';
import 'package:taproot/features/habits/services/habit_inputs_loader.dart';
import 'package:taproot/features/reflection/services/check_in_assembler.dart';

import '../../../utils/fake_repositories.dart';
import '../../../utils/store_contract.dart';
import '../../../utils/store_fixtures.dart';

void main() {
  late TestStore store;
  late TestClock clock;
  late CheckInAssembler assembler;

  final now = DateTime(2026, 3, 12, 20);

  setUp(() async {
    clock = TestClock(now);
    store = await openFakeStore(clock);
    addTearDown(store.dispose);
    assembler = CheckInAssembler(
      habits: store.habits,
      loader: HabitInputsLoader(
        habits: store.habits,
        completions: store.completions,
        reflections: store.reflections,
        nudges: store.nudges,
      ),
      clock: () => clock.now,
    );
  });

  Future<void> plant({
    String id = 'habit-1',
    String name = 'Morning run',
    HabitCategory? category = HabitCategory.exercise,
    String? designedCue = 'after breakfast',
  }) => store.habits.saveHabit(
    testHabit(
      id: id,
      name: name,
      category: category,
      designedCue: designedCue,
      designedCueType: designedCue == null ? null : CueType.event,
      createdAt: DateTime(2026, 1, 1),
    ),
  );

  Future<void> water(DateTime at, {String habitId = 'habit-1'}) =>
      store.completions.recordCompletion(
        Completion(
          id: 'c-${at.millisecondsSinceEpoch}',
          habitId: habitId,
          completedAt: at,
          source: CompletionSource.tap,
        ),
      );

  Future<void> expect_(DateTime at, {bool sent = true}) =>
      store.nudges.saveNudge(
        NudgeRecord(
          id: 'n-${at.millisecondsSinceEpoch}',
          habitId: 'habit-1',
          expectedOccasionAt: at,
          sent: sent,
        ),
      );

  test('an empty garden has nothing to ask about', () async {
    expect(await assembler.nextCheckIn(), isNull);
  });

  test('a habit nothing has happened to is not asked about', () async {
    await plant();

    expect(await assembler.nextCheckIn(), isNull);
  });

  test(
    'a first completion is a validation, with the library behind it',
    () async {
      await plant();
      await water(DateTime(2026, 3, 12, 7, 10));

      final offer = await assembler.nextCheckIn();

      expect(offer, isNotNull);
      expect(offer!.framing, Framing.validation);
      expect(offer.isFirstReflection, isTrue);
      expect(offer.habit.id, 'habit-1');

      // The designed cue is pinned in slot 0 — that is what makes Validation a
      // single tap — and nothing from its family is offered twice.
      expect(offer.cueChips.first.label, 'after breakfast');
      expect(
        offer.cueChips.skip(1).map((chip) => chip.family),
        isNot(contains('breakfast')),
      );
    },
  );

  test('the chips rank against the completion, not against now', () async {
    // The check-in happens at 20:00; the run happened at 07:10. Ranking against
    // the check-in would give every morning habit evening chips.
    await plant();
    await water(DateTime(2026, 3, 12, 7, 10));

    final morning = await assembler.nextCheckIn();
    expect(
      morning!.cueChips.map((chip) => chip.label),
      contains('after coffee'),
    );

    // The same habit, watered in the evening, gets a different set.
    await store.reflections.saveReflection(
      Reflection(
        id: 'r1',
        habitId: 'habit-1',
        createdAt: DateTime(2026, 3, 12, 8),
        occasion: Occasion.completion,
        framing: Framing.validation,
        inputMode: InputMode.chip,
        cueReported: 'after breakfast',
        cueType: CueType.event,
      ),
    );
    clock.now = DateTime(2026, 3, 14, 21);
    await water(DateTime(2026, 3, 14, 18, 40));

    final evening = await assembler.nextCheckIn();
    expect(evening, isNotNull);
    expect(evening!.isFirstReflection, isFalse);
  });

  test(
    'a completion the app stayed silent on becomes an autonomy question',
    () async {
      await plant();
      await expect_(DateTime(2026, 3, 12, 6, 30), sent: false);
      await water(DateTime(2026, 3, 12, 7, 10));

      final offer = await assembler.nextCheckIn();

      expect(offer!.framing, Framing.autonomy);
      expect(offer.occasion, Occasion.autonomyCompletion);
    },
  );

  test('a missed occasion becomes a diagnosis, with friction chips', () async {
    await plant();
    await expect_(DateTime(2026, 3, 11, 7));

    final offer = await assembler.nextCheckIn();

    expect(offer!.framing, Framing.diagnosis);
    expect(offer.isDiagnosis, isTrue);
    expect(offer.cueChips, isEmpty);
    expect(offer.frictionChips, hasLength(5));
    expect(
      offer.frictionChips.map((chip) => chip.frictionType),
      containsAll(<FrictionType>[FrictionType.forgot, FrictionType.motivation]),
    );
  });

  test('a paused habit is never diagnosed', () async {
    // Paused days are excluded from every engine window because they are not
    // misses. Asking someone about a day they told us about would be the app
    // not listening.
    await plant();
    await expect_(DateTime(2026, 3, 11, 7));
    await store.habits.pauseHabit('habit-1');

    expect(await assembler.nextCheckIn(), isNull);
  });

  test(
    'a returning reflection offers the user their own past answers',
    () async {
      await plant();
      await water(DateTime(2026, 3, 10, 7));
      await store.reflections.saveReflection(
        Reflection(
          id: 'r1',
          habitId: 'habit-1',
          createdAt: DateTime(2026, 3, 10, 20),
          occasion: Occasion.completion,
          framing: Framing.validation,
          inputMode: InputMode.chip,
          cueReported: 'put my shoes on',
          cueType: CueType.event,
        ),
      );
      await water(DateTime(2026, 3, 12, 7));

      final offer = await assembler.nextCheckIn();

      expect(offer!.isFirstReflection, isFalse);
      expect(
        offer.cueChips.map((chip) => chip.label),
        contains('put my shoes on'),
      );
    },
  );

  test('only one habit is asked about, however many are waiting', () async {
    await plant(id: 'habit-1', name: 'Morning run');
    await plant(id: 'habit-2', name: 'Read');
    await water(DateTime(2026, 3, 12, 7), habitId: 'habit-1');
    await water(DateTime(2026, 3, 12, 8), habitId: 'habit-2');

    final offer = await assembler.nextCheckIn();

    expect(offer, isNotNull);
    // One conversational slot in the user's day, not one per plant.
    expect(offer!.habit.id, anyOf('habit-1', 'habit-2'));
  });

  test('a habit with no category still gets a question', () async {
    await plant(category: null);
    await water(DateTime(2026, 3, 12, 7, 10));

    final offer = await assembler.nextCheckIn();

    expect(offer, isNotNull);
    expect(offer!.cueChips, isNotEmpty);
  });
}
