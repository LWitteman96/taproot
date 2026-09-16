import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/core/engine/autonomy.dart';
import 'package:taproot/core/engine/constants.dart';
import 'package:taproot/core/models/completion.dart';
import 'package:taproot/core/models/habit.dart';
import 'package:taproot/core/models/nudge.dart';
import 'package:taproot/core/utils/local_dates.dart';
import 'package:taproot/features/habits/services/habit_inputs_loader.dart';
import 'package:taproot/features/notifications/domain/evening_check_in.dart';
import 'package:taproot/features/notifications/domain/expected_occasions.dart';
import 'package:taproot/features/notifications/domain/notification_access.dart';
import 'package:taproot/features/notifications/domain/notification_gateway.dart';
import 'package:taproot/features/notifications/domain/nudge_decision.dart';
import 'package:taproot/features/notifications/domain/nudge_payload.dart';
import 'package:taproot/features/notifications/services/nudge_scheduler.dart';

import '../../../../utils/fake_notification_gateway.dart';
import '../../../../utils/fake_repositories.dart';
import '../../../../utils/store_contract.dart';
import '../../../../utils/store_fixtures.dart';

/// The scheduler, on a fake clock and a fake notification platform.
///
/// The invariant under test throughout: **every expected occasion gets a
/// ledger row, and the ones the engine deliberately stayed silent on get one
/// too.** Those rows are autonomy's denominator, and their absence is
/// indistinguishable from the absence of an occasion — so a scheduler that
/// quietly skips them breaks the measurement without breaking anything
/// visible.
void main() {
  const habitId = 'habit-1';

  /// Local wall-clock times built from calendar fields, never by adding a
  /// `Duration` to a `DateTime`.
  ///
  /// Adding 60 days of *absolute* time to a local timestamp crosses a
  /// daylight-saving boundary in some zones and not others, so the same line
  /// produced 20:00 in Europe/Amsterdam and 19:00 on a UTC CI runner — and
  /// 20:00 is the evening check-in slot, which flipped one occasion between
  /// "still schedulable" and "its evening has passed". Calendar fields are the
  /// same instant-of-day everywhere.
  DateTime dayAfterCreation(int days, {int hour = 9}) =>
      DateTime(2026, 3, 2 + days, hour);

  final createdAt = dayAfterCreation(0);

  late TestClock clock;
  late TestStore store;
  late FakeNotificationGateway gateway;
  late NudgeScheduler scheduler;
  var nextId = 0;

  /// A prompt composer that records what it was asked, standing in for the
  /// reflection feature.
  final asked = <String>[];

  Future<void> buildScheduler({
    ReflectionPromptComposer reflection = const NoReflectionPrompt(),
  }) async {
    scheduler = NudgeScheduler(
      habits: store.habits,
      nudges: store.nudges,
      inputs: HabitInputsLoader(
        habits: store.habits,
        completions: store.completions,
        reflections: store.reflections,
        nudges: store.nudges,
      ),
      gateway: gateway,
      reflection: reflection,
      clock: clock.call,
      newId: () => 'nudge-${nextId++}',
    );
  }

  setUp(() async {
    nextId = 0;
    asked.clear();
    // Mid-morning on the habit's creation day: today's occasion has already
    // lost its evening slot, tomorrow's has not.
    clock = TestClock(dayAfterCreation(0, hour: 10));
    store = await openFakeStore(clock);
    gateway = FakeNotificationGateway();
    await buildScheduler();
  });

  Future<Habit> saveHabit({
    int targetFrequency = 7,
    String id = habitId,
    String name = 'Morning run',
  }) async {
    final habit = testHabit(
      id: id,
      name: name,
      targetFrequency: targetFrequency,
      createdAt: createdAt,
    );
    await store.habits.saveHabit(habit);
    return habit;
  }

  Future<List<NudgeRecord>> ledger([String id = habitId]) =>
      store.nudges.nudgesFor(id);

  group('the ledger', () {
    test('records every expected occasion in the horizon', () async {
      await saveHabit();

      await scheduler.planAll();

      // A daily habit, planned from today through the 7-day horizon.
      final rows = await ledger();
      expect(rows, hasLength(EngineConstants.nudgeHorizonDays + 1));
      expect(
        rows.map((row) => LocalDate.from(row.expectedOccasionAt)).toList(),
        List<LocalDate>.generate(
          EngineConstants.nudgeHorizonDays + 1,
          (offset) => LocalDate(2026, 3, 2).addDays(offset),
        ),
      );
    });

    test('records the occasions it deliberately stayed silent on', () async {
      // The assertion the whole stage exists for. A faded habit whose recent
      // occasions were all nudged is in debt to its own rate, so the coming
      // ones are withheld — and every one of them still gets a row. Those rows
      // are what autonomy is divided by, and they cannot be recovered later
      // from the absence of a notification.
      await saveHabit();
      await _climbTo(store, habitId);
      clock.now = dayAfterCreation(60, hour: 10);
      await _seedNudgedHistory(store, habitId, clock.now);

      final plan = await scheduler.planAll();

      final horizon = (await ledger())
          .where((row) => row.expectedOccasionAt.isAfter(clock.now))
          .toList();

      expect(horizon, isNotEmpty, reason: 'the coming occasions are recorded');
      expect(
        horizon.every((row) => !row.sent),
        isTrue,
        reason: 'and every one of them was deliberately left silent',
      );
      expect(
        horizon.every((row) => gateway.forNudge(row.id) == null),
        isTrue,
        reason: 'no notification was queued for any of them',
      );
      expect(
        plan.withheld,
        isNotEmpty,
        reason:
            'the silence is the engine choosing, not the app failing — '
            'only that kind counts as a measurement',
      );
      expect(plan.suppressedBy(NudgeSuppression.noPermission), isEmpty);
      expect(plan.suppressedBy(NudgeSuppression.overCap), isEmpty);
    });

    test('a habit that has earned every nudge gets every nudge', () async {
      // The other end of the same rule, so the test above cannot pass by the
      // scheduler simply never nudging: below Young the rate is 1.0 and no
      // occasion is withheld.
      await saveHabit();

      final plan = await scheduler.planAll();

      expect(plan.withheld, isEmpty);
      expect(
        plan.occasions.where((occasion) => occasion.decision.shouldSend),
        isNotEmpty,
      );
    });

    test('the row count is the occasion count, whatever the fade rate', () async {
      // Stated as the negative: the number of rows must not depend on how many
      // notifications went out. If it did, a faded habit would look like a
      // habit with fewer expected occasions, and autonomy would quietly
      // improve as the app went quiet — the exact failure the ledger exists to
      // prevent.
      await saveHabit();
      await _climbTo(store, habitId);
      clock.now = dayAfterCreation(60, hour: 10);

      await scheduler.planAll();

      final rows = await ledger();
      final occasions = expectedOccasionsBetween(
        createdAt: createdAt,
        targetFrequency: 7,
        from: LocalDate.from(
          clock.now,
        ).addDays(-EngineConstants.nudgeBackfillDays),
        to: LocalDate.from(clock.now).addDays(EngineConstants.nudgeHorizonDays),
      );

      expect(rows, hasLength(occasions.length));
      expect(
        rows.where((row) => row.sent).length,
        lessThan(rows.length),
        reason: 'some of them carried no notification',
      );
    });

    test('rows for past occasions are backfilled as un-nudged', () async {
      // The phone was off for a fortnight. Nobody was there to nudge, so the
      // occasions are honestly un-nudged — but they are still occasions, and
      // leaving them out would hide two weeks of a habit standing or not
      // standing on its own.
      await saveHabit();
      clock.now = dayAfterCreation(14);

      await scheduler.planAll();

      final past = (await ledger())
          .where((row) => row.expectedOccasionAt.isBefore(clock.now))
          .toList();
      // Fifteen, not fourteen: an occasion is a local *date*, stamped at
      // local midnight, so today's own occasion is already behind the clock by
      // the time anybody opens the app.
      expect(past, hasLength(15));
      expect(past.every((row) => !row.sent), isTrue);
      expect(past.every((row) => gateway.forNudge(row.id) == null), isTrue);
    });

    test('backfill is bounded rather than replaying the whole history', () {
      expect(EngineConstants.nudgeBackfillDays, 30);
    });

    test('a paused habit expects nothing', () async {
      await saveHabit();
      await store.habits.pauseHabit(habitId);

      await scheduler.planAll();

      expect(await ledger(), isEmpty);
      expect(gateway.queued, isEmpty);
    });
  });

  group('idempotence', () {
    test(
      're-planning neither duplicates rows nor duplicates notifications',
      () async {
        await saveHabit();

        await scheduler.planAll();
        final first = await ledger();
        final firstQueue = Map<int, Object>.from(gateway.queued);

        await scheduler.planAll();
        await scheduler.planAll();

        final again = await ledger();
        expect(again.map((row) => row.id), first.map((row) => row.id));
        expect(gateway.queued.keys, firstQueue.keys);
      },
    );

    test('a decision already in the ledger is never re-decided', () async {
      // The ledger records what happened, not what the current stage would do.
      // Re-deciding would let an occasion flip from silent to nudged after the
      // fact — and a flipped row moves between autonomy's numerator and its
      // denominator retroactively.
      await saveHabit();
      await scheduler.planAll();

      final before = await ledger();
      final silent = before.firstWhere(
        (row) => !row.sent,
        orElse: () => before.first,
      );

      // Climb the habit so the fade rate changes underneath the planned rows.
      await _climbTo(store, habitId);
      await scheduler.planAll();

      final after = await ledger();
      expect(after.firstWhere((row) => row.id == silent.id).sent, silent.sent);
    });

    test('a notification the platform lost is queued again', () async {
      // A reinstall or a restore empties the OS alarm table while the ledger
      // still says the nudge was sent. Left alone that is a nudge the ledger
      // claims and the user never receives — the one direction that corrupts
      // the measurement rather than just missing a reminder.
      await saveHabit();
      await scheduler.planAll();
      final sent = (await ledger()).firstWhere(
        (row) => row.sent && row.expectedOccasionAt.isAfter(clock.now),
      );

      gateway.queued.clear();
      await scheduler.planAll();

      expect(gateway.forNudge(sent.id), isNotNull);
    });
  });

  group('when the app cannot nudge', () {
    test('denied permission still records the occasions', () async {
      // Denial is a designed app mode, not an error (guide §2). The habit
      // still has expected days and the user still either does it or does
      // not, so the engine keeps its inputs.
      gateway.grant(NotificationAccess.denied);
      await saveHabit();

      final plan = await scheduler.planAll();

      expect(await ledger(), hasLength(EngineConstants.nudgeHorizonDays + 1));
      expect(gateway.queued, isEmpty);
      expect(
        plan.suppressedBy(NudgeSuppression.noPermission),
        isNotEmpty,
        reason:
            'the silence is reported as the app failing, not the engine '
            'choosing',
      );
      expect(plan.withheld, isEmpty);
    });

    test('a refused notification leaves the row honestly un-sent', () async {
      await saveHabit();
      gateway.failNextSchedule = true;

      await scheduler.planAll();

      final rows = await ledger();
      expect(rows, isNotEmpty, reason: 'the pass carried on past the failure');
      expect(
        rows.where((row) => row.sent).length,
        lessThan(rows.length),
        reason: 'the refused occasion is not recorded as nudged',
      );
    });

    test('history does not consume the ceiling', () async {
      // The cap counts notifications the OS is holding, not decisions that
      // read "send". Every historical sent row reports `send` too, so counting
      // those against the ceiling let a few weeks of ledger exhaust it — and
      // then suppressed every *real* future nudge as overCap, silently, with
      // the ledger recording them as un-nudged.
      //
      // Three habits, because the miscount was in the *across-habit*
      // accounting and it compounds: each habit's history inflated the budget
      // the next one was handed. The clock has to be far enough past creation
      // for that history to lie inside the planning window — occasions before
      // a habit exists are not occasions, so a fresh habit has none to
      // miscount.
      final habits = <String>['habit-a', 'habit-b', 'habit-c'];
      for (final id in habits) {
        await saveHabit(id: id, name: 'Habit $id');
      }
      clock.now = dayAfterCreation(60, hour: 10);
      for (final id in habits) {
        await _seedNudgedHistory(store, id, clock.now);
      }

      // 31 sent rows plus 7 real future nudges each. Counting decisions rather
      // than notifications, the running total read 38 after the first habit
      // and 76 after the second — so by the third it was past the ceiling of
      // 60, and every one of that habit's real nudges was suppressed as
      // overCap and written to the ledger as un-nudged. Counting only what the
      // OS actually took, the same pass ends at 21.
      final plan = await scheduler.planAll();

      expect(
        plan.suppressedBy(NudgeSuppression.overCap),
        isEmpty,
        reason:
            '21 queued notifications cannot reach a ceiling of '
            '${EngineConstants.maximumPendingNudges}',
      );
      expect(
        (await ledger('habit-c')).where(
          (row) => row.sent && row.expectedOccasionAt.isAfter(clock.now),
        ),
        isNotEmpty,
        reason: 'the last habit planned still gets its nudges',
      );
    });

    test('the pending-notification ceiling is reported, not silent', () async {
      await saveHabit();
      for (
        var index = 0;
        index < EngineConstants.maximumPendingNudges;
        index++
      ) {
        await gateway.schedule(ScheduledNudgeStub.at(index));
      }

      final plan = await scheduler.planAll();

      expect(plan.suppressedBy(NudgeSuppression.overCap), isNotEmpty);
      expect(await ledger(), isNotEmpty);
    });
  });

  group('the notification itself', () {
    test('rehearses the designed cue rather than naming the app', () async {
      await saveHabit();

      await scheduler.planAll();

      final queued = gateway.everyScheduleCall.first;
      expect(queued.checkIn.title, 'Morning run');
      expect(queued.checkIn.body, contains('after breakfast'));
      expect(queued.checkIn.body, isNot(contains('Taproot')));
    });

    test('is delivered the evening before its occasion', () async {
      await saveHabit();

      await scheduler.planAll();

      final queued = gateway.everyScheduleCall.first;
      final occasionDate = LocalDate.from(
        (await ledger())
            .firstWhere((row) => row.id == queued.payload.nudgeId)
            .expectedOccasionAt,
      );
      expect(
        queued.deliverAt,
        DateTime(
          occasionDate.year,
          occasionDate.month,
          occasionDate.day,
          EngineConstants.eveningCheckInHour,
        ).subtract(const Duration(days: EngineConstants.nudgeLeadDays)),
      );
      expect(queued.deliverAt.isAfter(clock.now), isTrue);
    });

    test('carries the ledger row back with it', () async {
      await saveHabit();

      await scheduler.planAll();

      final queued = gateway.everyScheduleCall.first;
      expect(
        NudgePayload.decode(queued.payload.encode()),
        NudgePayload(nudgeId: queued.payload.nudgeId, habitId: habitId),
      );
      expect(
        (await ledger()).map((row) => row.id),
        contains(queued.payload.nudgeId),
      );
    });

    test('carries the reflection question when there is one', () async {
      // Reflection and the next-day nudge are one notification (reflection
      // spec §1) — this is the seam that keeps them from becoming two.
      await saveHabit();
      await buildScheduler(reflection: _RecordingComposer(asked));

      await scheduler.planAll();

      final queued = gateway.everyScheduleCall.first;
      expect(queued.checkIn.body, startsWith('What got you going today?'));
      expect(queued.checkIn.body, contains('after breakfast'));
      expect(asked, isNotEmpty);
    });

    test('but only one question an evening, however many habits', () async {
      // §1 buys the app "one consistent conversational slot instead of two
      // competing interruptions", and that is a claim about the user's
      // evening, not about one plant. Three habits clearing threshold for
      // Thursday must not put three questions into Thursday's notifications —
      // and the composer cannot see that, because it is asked about one habit
      // at a time and would answer yes to all three.
      await saveHabit(id: 'habit-1', name: 'Morning run');
      await saveHabit(id: 'habit-2', name: 'Read');
      await saveHabit(id: 'habit-3', name: 'Stretch');
      await buildScheduler(reflection: _RecordingComposer(asked));

      await scheduler.planAll();

      final withQuestions = gateway.everyScheduleCall
          .where((nudge) => nudge.checkIn.body.startsWith('What got you going'))
          .toList();
      final evenings = withQuestions
          .map((nudge) => LocalDate.from(nudge.deliverAt))
          .toList();

      expect(evenings, isNotEmpty);
      expect(
        evenings.toSet(),
        hasLength(evenings.length),
        reason: 'one evening carried more than one question',
      );

      // The older habit keeps it when two compete — the same creation-order
      // tie-break the pending cap uses, so the answer is stable across passes
      // rather than depending on which habit the store listed first.
      final tonight = withQuestions.firstWhere(
        (nudge) => LocalDate.from(nudge.deliverAt) == LocalDate.from(clock.now),
        orElse: () => withQuestions.first,
      );
      expect(tonight.payload.habitId, 'habit-1');
    });

    test('re-composes a queued question as its evening comes round', () async {
      // The promise on `ReflectionPromptComposer` — that re-planning keeps the
      // question from going stale — was a comment until this. A notification
      // queued a week out carries a question written against a day that had
      // not happened; nothing ever rewrote one the OS was already holding, so
      // the first pass's guess was what the user read.
      await saveHabit();
      final answers = <String>['an early guess', 'what actually happened'];
      await buildScheduler(reflection: _ChangingComposer(answers));

      await scheduler.planAll();
      final nudgeId = gateway.everyScheduleCall.first.payload.nudgeId;
      expect(gateway.forNudge(nudgeId)!.checkIn.body, startsWith(answers[0]));

      // A second pass on the same day: the notification is still pending and
      // still fires tonight, so it is re-composed in place.
      await scheduler.planAll();

      expect(gateway.forNudge(nudgeId)!.checkIn.body, startsWith(answers[1]));
      expect(
        gateway.queued.keys,
        contains(notificationIdFor(nudgeId)),
        reason: 'replaced at the same id, not queued twice',
      );
    });

    test(
      'and leaves the far end of the horizon alone until it is near',
      () async {
        // The bound on the cost. Only the notification about to fire is worth
        // re-asking, so a pass re-queues at most one per habit rather than the
        // whole horizon — which matters because a pass runs on every launch,
        // every completion and every resume.
        await saveHabit();
        await buildScheduler(reflection: _ChangingComposer(<String>['first']));

        await scheduler.planAll();
        final scheduledFirstPass = gateway.everyScheduleCall.length;
        gateway.everyScheduleCall.clear();

        await scheduler.planAll();

        expect(scheduledFirstPass, greaterThan(1));
        expect(
          gateway.everyScheduleCall,
          hasLength(1),
          reason: 'only tonight is inside the refresh window',
        );
        expect(
          gateway.everyScheduleCall.single.deliverAt
              .difference(clock.now)
              .inHours,
          lessThanOrEqualTo(EngineConstants.nudgeQuestionRefreshWindow.inHours),
        );
      },
    );
  });

  test('the withheld occasions are what autonomy is measured over', () async {
    // End to end: plan a faded habit, complete on some of the silent days,
    // and read the engine's own autonomy off the ledger the scheduler wrote.
    await saveHabit();
    await _seedLedger(store, habitId, createdAt, sent: 0, withheld: 4);
    clock.now = dayAfterCreation(4, hour: 12);

    final inputs = await HabitInputsLoader(
      habits: store.habits,
      completions: store.completions,
      reflections: store.reflections,
      nudges: store.nudges,
    ).load(habitId);

    final autonomy = computeAutonomy(inputs: inputs!, at: clock.now);
    expect(
      autonomy.occasions,
      4,
      reason: 'four silent occasions, so a denominator of four',
    );
    expect(autonomy.completed, 2);
    expect(autonomy.value, closeTo(0.5, 1e-9));
  });
}

/// A composer standing in for the reflection feature.
class _RecordingComposer implements ReflectionPromptComposer {
  _RecordingComposer(this.asked);

  final List<String> asked;

  @override
  Future<String?> promptFor({
    required Habit habit,
    required ExpectedOccasion occasion,
    required DateTime deliverAt,
  }) async {
    asked.add('${habit.id}@${occasion.date}');
    return 'What got you going today?';
  }
}

/// A composer whose answer changes between passes, so a refresh is visible.
///
/// It returns each answer once and then repeats the last, which is what makes
/// "the second pass re-composed it" a different string rather than an
/// unobservable no-op.
class _ChangingComposer implements ReflectionPromptComposer {
  _ChangingComposer(this.answers);

  final List<String> answers;
  int _asked = 0;

  @override
  Future<String?> promptFor({
    required Habit habit,
    required ExpectedOccasion occasion,
    required DateTime deliverAt,
  }) async {
    final answer = answers[_asked.clamp(0, answers.length - 1)];
    _asked++;
    return answer;
  }
}

/// Writes a ledger by hand — [sent] nudged occasions then [withheld] silent
/// ones, one per day from [from], with a completion on every other silent day.
Future<void> _seedLedger(
  TestStore store,
  String habitId,
  DateTime from, {
  required int sent,
  required int withheld,
}) async {
  var day = 0;
  for (var index = 0; index < sent; index++, day++) {
    final id = 'seed-sent-$habitId-$index';
    await store.nudges.saveNudge(
      NudgeRecord(
        id: id,
        habitId: habitId,
        expectedOccasionAt: DateTime(from.year, from.month, from.day + day),
        sent: false,
      ),
    );
    await store.nudges.markSent(id);
  }
  for (var index = 0; index < withheld; index++, day++) {
    await store.nudges.saveNudge(
      NudgeRecord(
        id: 'seed-silent-$habitId-$index',
        habitId: habitId,
        expectedOccasionAt: DateTime(from.year, from.month, from.day + day),
        sent: false,
      ),
    );
    if (index.isEven) {
      await store.completions.recordCompletion(
        Completion(
          id: 'seed-completion-$habitId-$index',
          habitId: habitId,
          completedAt: DateTime(from.year, from.month, from.day + day, 7),
        ),
      );
    }
  }
}

/// Completes the habit every day for two months, which carries it well past
/// Young — so its nudge rate is below 1.0 whatever rung it settles on.
Future<void> _climbTo(TestStore store, String habitId) async {
  for (var day = 0; day < 60; day++) {
    await store.completions.recordCompletion(
      Completion(
        id: 'climb-$day',
        habitId: habitId,
        completedAt: DateTime(2026, 3, 2 + day, 7),
      ),
    );
  }
}

/// Fills the whole backfill window with occasions that *were* nudged.
///
/// It leaves the fade rule with a sent share of 1.0 against a rate below it,
/// so every occasion the pass then plans is withheld — deterministically, at
/// any rate under 1.0, without the test having to pin the habit to one rung.
Future<void> _seedNudgedHistory(
  TestStore store,
  String habitId,
  DateTime now,
) async {
  final today = LocalDate.from(now);
  for (var offset = -EngineConstants.nudgeBackfillDays; offset <= 0; offset++) {
    // Per habit: a shared id would have the second habit's seeding *update*
    // the first habit's row and move it across, so every caller but the last
    // would silently end up with no history at all.
    final id = 'seeded-$habitId-$offset';
    await store.nudges.saveNudge(
      NudgeRecord(
        id: id,
        habitId: habitId,
        expectedOccasionAt: today.addDays(offset).startOfDay,
        sent: false,
      ),
    );
    await store.nudges.markSent(id);
  }
}

/// A notification queued by something other than the scheduler, to fill the
/// platform's pending list.
abstract final class ScheduledNudgeStub {
  static ScheduledNudge at(int index) => ScheduledNudge(
    notificationId: 900000 + index,
    payload: NudgePayload(nudgeId: 'other-$index', habitId: 'other'),
    checkIn: const EveningCheckIn(title: 'other', body: 'other'),
    deliverAt: DateTime(2026, 4, 1, 20),
  );
}
