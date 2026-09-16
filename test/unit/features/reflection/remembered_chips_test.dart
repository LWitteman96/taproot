import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/reflection.dart';
import 'package:taproot/features/reflection/domain/remembered_chips.dart';

void main() {
  var nextId = 0;

  Reflection answered(
    String? cue, {
    required DateTime at,
    CueType cueType = CueType.event,
    InputMode inputMode = InputMode.chip,
  }) => Reflection(
    id: 'r${nextId++}',
    habitId: 'habit-1',
    createdAt: at,
    occasion: Occasion.completion,
    framing: Framing.discovery,
    inputMode: inputMode,
    cueReported: cue,
    cueType: cueType,
  );

  setUp(() => nextId = 0);

  test('offers back what the user actually said', () {
    final chips = rememberedCues(
      reflections: <Reflection>[
        answered('after breakfast', at: DateTime(2026, 3, 1)),
        answered('after breakfast', at: DateTime(2026, 3, 3)),
        answered('the dog woke me', at: DateTime(2026, 3, 2)),
      ],
    );

    expect(chips.map((chip) => chip.label), <String>[
      'after breakfast',
      'the dog woke me',
    ]);
  });

  test('carries the type the user gave, not a guess', () {
    // Tapping a remembered chip has to record the same cue_type the original
    // answer did, or a habit's convergence history quietly changes meaning the
    // second time the user taps the same words.
    final chips = rememberedCues(
      reflections: <Reflection>[
        answered(
          'felt restless',
          at: DateTime(2026, 3, 1),
          cueType: CueType.internal,
        ),
      ],
    );

    expect(chips.single.cueType, CueType.internal);
  });

  test('between equally frequent answers, the recent one wins', () {
    // This is what the recency half of "recency-weighted frequency" buys:
    // same number of mentions, and the one the user is saying now leads.
    final chips = rememberedCues(
      reflections: <Reflection>[
        for (var day = 1; day <= 4; day++)
          answered('an old answer', at: DateTime(2026, 1, day)),
        for (var day = 8; day <= 11; day++)
          answered('what I say now', at: DateTime(2026, 3, day)),
      ],
    );

    expect(chips.first.label, 'what I say now');
  });

  test('a long-standing answer still outranks a rare recent one', () {
    // And this is the frequency half, which is not a flaw to be tuned out: a
    // cue the user has named a dozen times *is* their cue, and burying it under
    // something said once last night would offer them a worse first tap.
    final chips = rememberedCues(
      reflections: <Reflection>[
        for (var day = 1; day <= 12; day++)
          answered('what I always say', at: DateTime(2026, 1, day)),
        answered('a one-off', at: DateTime(2026, 3, 11)),
      ],
    );

    expect(chips.first.label, 'what I always say');
    expect(chips.map((chip) => chip.label), contains('a one-off'));
  });

  test("a can't remember is never offered back as a suggestion", () {
    // It is a first-class answer to *give*, but it is not a cue.
    final chips = rememberedCues(
      reflections: <Reflection>[
        answered(
          null,
          at: DateTime(2026, 3, 1),
          inputMode: InputMode.cantRemember,
        ),
        answered(
          'nothing',
          at: DateTime(2026, 3, 2),
          inputMode: InputMode.skipped,
        ),
        answered('after breakfast', at: DateTime(2026, 3, 3)),
      ],
    );

    expect(chips.map((chip) => chip.label), <String>['after breakfast']);
  });

  test('caps at five, however many the user has given', () {
    final chips = rememberedCues(
      reflections: <Reflection>[
        for (var day = 1; day <= 9; day++)
          answered('answer $day', at: DateTime(2026, 3, day)),
      ],
    );

    expect(chips, hasLength(5));
  });

  test('the same history always produces the same offer', () {
    // Two answers sharing a timestamp — a backfill, or a coarse clock. Without
    // a second sort key the input order decides the ranking.
    final reflections = <Reflection>[
      answered('one', at: DateTime(2026, 3, 1)),
      answered('two', at: DateTime(2026, 3, 1)),
    ];

    expect(
      rememberedCues(reflections: reflections).map((chip) => chip.label),
      rememberedCues(
        reflections: reflections.reversed.toList(),
      ).map((chip) => chip.label),
    );
  });

  test('a habit with no reflections is a first reflection', () {
    expect(isFirstReflection(const <Reflection>[]), isTrue);
    expect(
      isFirstReflection(<Reflection>[answered('x', at: DateTime(2026, 3, 1))]),
      isFalse,
    );
  });
}
