import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/completion.dart';
import 'package:taproot/core/models/nudge.dart';
import 'package:taproot/core/models/reflection.dart';
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

  NudgeRecord occasionAt(DateTime at, {bool sent = true, String id = 'n'}) =>
      NudgeRecord(
        id: id,
        habitId: 'habit-1',
        expectedOccasionAt: at,
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
    final occasion = detect(
      completions: <Completion>[completionAt(DateTime(2026, 3, 10, 7))],
      nudges: <NudgeRecord>[
        occasionAt(DateTime(2026, 3, 10, 6, 30), sent: false),
      ],
    );

    expect(occasion?.occasion, Occasion.autonomyCompletion);
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
    expect(occasion?.at, DateTime(2026, 3, 9, 7));
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
