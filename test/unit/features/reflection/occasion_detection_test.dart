import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/completion.dart';
import 'package:taproot/core/models/nudge.dart';
import 'package:taproot/core/models/reflection.dart';
import 'package:taproot/core/utils/local_dates.dart';
import 'package:taproot/features/reflection/domain/occasion_detection.dart';
import 'package:taproot/features/reflection/domain/reflection_priority.dart';

/// Reading the two ledgers for something worth asking about — and, mostly, the
/// three ways they can be misread.
void main() {
  final now = DateTime(2026, 3, 10, 20);

  Completion completionAt(DateTime at, {String id = 'c'}) => Completion(
    id: id,
    habitId: 'habit-1',
    completedAt: at,
    source: CompletionSource.tap,
  );

  /// A ledger row **in the shape the scheduler actually writes**.
  ///
  /// `NudgeScheduler` stores `occasion.date.startOfDay` — local midnight, not
  /// the hour the user does the thing — so a helper that builds rows at 07:00
  /// is testing a row that never exists on disk. That is what hid today
  /// reading as a miss from one minute past midnight: the guards against a
  /// future-dated row all passed, because a 07:00 stamp for today is in the
  /// past by breakfast while the real 00:00 stamp is in the past all day.
  NudgeRecord occasionAt(DateTime at, {bool sent = true, String id = 'n'}) =>
      NudgeRecord(
        id: id,
        habitId: 'habit-1',
        expectedOccasionAt: LocalDate.from(at).startOfDay,
        sent: sent,
      );

  Reflection reflectionAt(DateTime at) => Reflection(
    id: 'r',
    habitId: 'habit-1',
    createdAt: at,
    occasion: Occasion.completion,
    framing: Framing.validation,
    inputMode: InputMode.chip,
  );

  CheckInOccasion? detect({
    List<Completion> completions = const <Completion>[],
    List<NudgeRecord> nudges = const <NudgeRecord>[],
    List<Reflection> reflections = const <Reflection>[],
    int targetFrequency = 3,
  }) => occasionFor(
    habitId: 'habit-1',
    completions: completions,
    nudges: nudges,
    reflections: reflections,
    targetFrequency: targetFrequency,
    at: now,
  );

  test('nothing has happened, so there is nothing to ask', () {
    expect(detect(), isNull);
  });

  test('a completion is an ordinary occasion when the app nudged', () {
    final occasion = detect(
      completions: <Completion>[completionAt(DateTime(2026, 3, 10, 7))],
      nudges: <NudgeRecord>[occasionAt(DateTime(2026, 3, 10, 6, 30))],
    );

    expect(occasion?.occasion, Occasion.completion);
  });

  test('a completion the app stayed silent on is an autonomy occasion', () {
    // The richest data the app ever gets: the habit fired without being asked.
    // The sent row two days earlier is what makes the silence a *choice* — see
    // the test below for what it looks like without one.
    final occasion = detect(
      completions: <Completion>[completionAt(DateTime(2026, 3, 10, 7))],
      nudges: <NudgeRecord>[
        occasionAt(DateTime(2026, 3, 8), id: 'sent'),
        occasionAt(DateTime(2026, 3, 10, 6, 30), sent: false),
      ],
    );

    expect(occasion?.occasion, Occasion.autonomyCompletion);
  });

  test('but silence from an app that never nudges claims nothing', () {
    // A user who declined notification permission. Every row in their ledger
    // is `sent: false`, because the reason a row was not sent is computed in
    // the scheduler and thrown away before the row is written — so without a
    // gate, *every* completion they ever log would be answered with "you did
    // this without us asking", from an app that was never allowed to ask.
    final occasion = detect(
      completions: <Completion>[completionAt(DateTime(2026, 3, 10, 7))],
      nudges: <NudgeRecord>[
        occasionAt(DateTime(2026, 3, 8), sent: false, id: 'n1'),
        occasionAt(DateTime(2026, 3, 9), sent: false, id: 'n2'),
        occasionAt(DateTime(2026, 3, 10), sent: false, id: 'n3'),
      ],
    );

    expect(occasion?.occasion, Occasion.completion);
  });

  test('a backfilled week on its own is not evidence of autonomy either', () {
    // The same gate covers the backfill: rows written after their evening had
    // passed are `sent: false` for a reason that has nothing to do with the
    // fade rule, and a phone that was off for a week produces a run of them.
    final occasion = detect(
      completions: <Completion>[completionAt(DateTime(2026, 3, 10, 7))],
      nudges: <NudgeRecord>[
        for (var day = 4; day <= 10; day++)
          occasionAt(DateTime(2026, 3, day), sent: false, id: 'n$day'),
      ],
    );

    expect(occasion?.occasion, Occasion.completion);
  });

  group('today is not a miss until today is over', () {
    // The failure this guards: a 19:00 runner opens the app at 08:00, today's
    // row is stamped 00:00, nothing is completed on today's date yet, and the
    // garden invites them to explain what got in the way — eleven hours before
    // the run they were always going to do.
    CheckInOccasion? detectAt(DateTime at) => occasionFor(
      habitId: 'habit-1',
      completions: const <Completion>[],
      nudges: <NudgeRecord>[occasionAt(DateTime(2026, 3, 10), sent: false)],
      reflections: const <Reflection>[],
      targetFrequency: 3,
      at: at,
    );

    test('at breakfast there is nothing to ask', () {
      expect(detectAt(DateTime(2026, 3, 10, 8)), isNull);
    });

    test('at one minute past midnight there is nothing to ask', () {
      expect(detectAt(DateTime(2026, 3, 10, 0, 1)), isNull);
    });

    test('at the evening check-in slot it is a miss', () {
      // The moment the app is entitled to look back at the day.
      expect(detectAt(DateTime(2026, 3, 10, 20))?.occasion, Occasion.miss);
    });

    test('and the next morning it still is', () {
      expect(detectAt(DateTime(2026, 3, 11, 9))?.occasion, Occasion.miss);
    });
  });

  test('a dismissed notification does not make a completion un-nudged', () {
    // `confirmed` and `declined` record what the user did with a
    // *notification*, not with the habit — someone can swipe the notification
    // away and go for the run anyway. Autonomy is about whether the app stayed
    // silent, which is `sent`.
    final occasion = detect(
      completions: <Completion>[completionAt(DateTime(2026, 3, 10, 7))],
      nudges: <NudgeRecord>[
        NudgeRecord(
          id: 'n',
          habitId: 'habit-1',
          expectedOccasionAt: DateTime(2026, 3, 10, 6, 30),
          sent: true,
          declined: true,
        ),
      ],
    );

    expect(occasion?.occasion, Occasion.completion);
  });

  test('an expected occasion with no completion is a miss', () {
    final occasion = detect(
      nudges: <NudgeRecord>[occasionAt(DateTime(2026, 3, 9, 7))],
    );

    expect(occasion?.occasion, Occasion.miss);
    // Local midnight, because that is what the row carries — the occasion is a
    // day, not an hour.
    expect(occasion?.at, DateTime(2026, 3, 9));
  });

  test('an expected occasion in the future is not a miss', () {
    // The ledger holds rows up to seven days ahead, because scheduling writes
    // them before the occasion arrives. Reading those as misses would diagnose
    // the user for not having done tomorrow yet.
    expect(
      detect(
        nudges: <NudgeRecord>[
          occasionAt(DateTime(2026, 3, 11, 7)),
          occasionAt(DateTime(2026, 3, 15, 7), id: 'n2'),
        ],
      ),
      isNull,
    );
  });

  test('the same completion is not asked about twice', () {
    // Without this the app asks about Tuesday's run every evening until
    // something newer happens.
    expect(
      detect(
        completions: <Completion>[completionAt(DateTime(2026, 3, 8, 7))],
        reflections: <Reflection>[reflectionAt(DateTime(2026, 3, 8, 20))],
      ),
      isNull,
    );
  });

  test('something newer than the last reflection is asked about', () {
    final occasion = detect(
      completions: <Completion>[
        completionAt(DateTime(2026, 3, 8, 7), id: 'old'),
        completionAt(DateTime(2026, 3, 10, 7), id: 'new'),
      ],
      reflections: <Reflection>[reflectionAt(DateTime(2026, 3, 8, 20))],
    );

    expect(occasion?.at, DateTime(2026, 3, 10, 7));
  });

  test('the most recent event wins when both are waiting', () {
    // A miss three days ago is not what today was about.
    final occasion = detect(
      completions: <Completion>[completionAt(DateTime(2026, 3, 10, 7))],
      nudges: <NudgeRecord>[occasionAt(DateTime(2026, 3, 7, 7))],
    );

    expect(occasion?.occasion, Occasion.completion);

    final older = occasionFor(
      habitId: 'habit-1',
      completions: <Completion>[completionAt(DateTime(2026, 3, 7, 7))],
      nudges: <NudgeRecord>[occasionAt(DateTime(2026, 3, 9, 7))],
      reflections: const <Reflection>[],
      targetFrequency: 3,
      at: now,
    );
    expect(older?.occasion, Occasion.miss);
  });

  test('an occasion that was completed that day is not a miss', () {
    expect(
      detect(
        completions: <Completion>[completionAt(DateTime(2026, 3, 9, 19))],
        nudges: <NudgeRecord>[occasionAt(DateTime(2026, 3, 9, 7))],
      )?.occasion,
      Occasion.completion,
    );
  });

  group('the weekly budget window', () {
    test('counts the last seven local days, inclusive', () {
      final reflections = <Reflection>[
        reflectionAt(DateTime(2026, 3, 10, 9)),
        reflectionAt(DateTime(2026, 3, 4, 9)),
        // Seven days back is outside a seven-day window that includes today.
        reflectionAt(DateTime(2026, 3, 3, 9)),
      ];

      expect(promptsInTheLastWeek(reflections: reflections, at: now), 2);
    });

    test('does not count a reflection in the future', () {
      expect(
        promptsInTheLastWeek(
          reflections: <Reflection>[reflectionAt(DateTime(2026, 3, 11, 9))],
          at: now,
        ),
        0,
      );
    });
  });
}
