import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/core/models/habit_category.dart';
import 'package:taproot/features/reflection/domain/chip_surfacing.dart';
import 'package:taproot/features/reflection/domain/daypart.dart';

/// The 24 worked examples from starter-chip-library.md §7.
///
/// These are the highest-signal tests in the reflection feature, for the same
/// reason `worked_examples_test.dart` is in the engine: the spec computed them
/// by hand from the rule, so they are a specification and a test suite at the
/// same time. Every guard in §5.3 — family uniqueness, the type ceiling, both
/// floors, the promotion floor, the global backfill — is exercised by at least
/// one of them, and each was derived independently of this implementation.
///
/// A failure here means the surfacing rule and the authored library disagree
/// with the document. Fix the code, or change the document deliberately and
/// move the example with it.
void main() {
  /// One row of §7: what was logged, what was pinned, and what should surface.
  void workedExample({
    required String name,
    required HabitCategory category,
    required DateTime loggedAt,
    required String? designedCueFamily,
    required List<String> expected,
  }) {
    test(name, () {
      final surfaced = surfaceStarterChips(
        category: category,
        logged: daypartFor(loggedAt),
        // The worked examples state the journey through the family, which is
        // what §7 does; the production caller passes the two separately.
        hasDesignedCue: designedCueFamily != null,
        designedCueFamily: designedCueFamily,
      );

      expect(
        surfaced.labels,
        expected,
        reason: 'got ${surfaced.chips.join(' · ')}',
      );
    });
  }

  group('7.1 exercise', () {
    workedExample(
      name: 'A — 07:10 early, designed cue in family breakfast',
      category: HabitCategory.exercise,
      loggedAt: DateTime(2026, 3, 2, 7, 10),
      designedCueFamily: 'breakfast',
      expected: const <String>[
        'after coffee',
        'put my shoes on',
        'first thing up',
        'walked past the gym',
      ],
    );

    workedExample(
      name: 'B — 18:40 evening, no designed cue',
      category: HabitCategory.exercise,
      loggedAt: DateTime(2026, 3, 2, 18, 40),
      designedCueFamily: null,
      expected: const <String>[
        'got home',
        'put my shoes on',
        'before dinner',
        'walked past the gym',
        'felt restless',
      ],
    );
  });

  group('7.2 meditation', () {
    workedExample(
      name: 'A — 06:50 early, designed cue in family coffee',
      category: HabitCategory.meditation,
      loggedAt: DateTime(2026, 3, 2, 6, 50),
      designedCueFamily: 'coffee',
      expected: const <String>[
        'got out of bed',
        'after brushing teeth',
        'felt stressed',
        'cushion was out',
      ],
    );

    workedExample(
      name: 'B — 22:10 night, designed cue in family bed',
      category: HabitCategory.meditation,
      loggedAt: DateTime(2026, 3, 2, 22, 10),
      designedCueFamily: 'bed',
      expected: const <String>[
        'after brushing teeth',
        'felt stressed',
        'cushion was out',
        'closed my laptop',
      ],
    );
  });

  group('7.3 reading', () {
    workedExample(
      name: 'A — 22:40 night, designed cue in family bed',
      category: HabitCategory.reading,
      loggedAt: DateTime(2026, 3, 2, 22, 40),
      designedCueFamily: 'bed',
      expected: const <String>[
        'got into bed',
        'put my phone down',
        'stuck waiting',
        'sat in my chair',
      ],
    );

    workedExample(
      name:
          'B — 12:30 midday, no designed cue, backfilled from the global pool',
      category: HabitCategory.reading,
      loggedAt: DateTime(2026, 3, 2, 12, 30),
      designedCueFamily: null,
      expected: const <String>[
        'stuck waiting',
        'book was out',
        'lunch break',
        'after breakfast',
        'with morning coffee',
      ],
    );
  });

  group('7.4 journaling', () {
    workedExample(
      name: 'A — 07:30 early, designed cue in family coffee',
      category: HabitCategory.journaling,
      loggedAt: DateTime(2026, 3, 2, 7, 30),
      designedCueFamily: 'coffee',
      expected: const <String>[
        'sat down with tea',
        'notebook was out',
        'something felt off',
        'felt overwhelmed',
      ],
    );

    workedExample(
      name: 'B — 22:50 night, designed cue in family bed',
      category: HabitCategory.journaling,
      loggedAt: DateTime(2026, 3, 2, 22, 50),
      designedCueFamily: 'bed',
      expected: const <String>[
        'got into bed',
        'sat down with tea',
        'end of the day',
        'after a hard day',
      ],
    );
  });

  group('7.5 hydration', () {
    workedExample(
      name: 'A — 09:30 morning, designed cue in family meal',
      category: HabitCategory.hydration,
      loggedAt: DateTime(2026, 3, 2, 9, 30),
      designedCueFamily: 'meal',
      expected: const <String>[
        'with my coffee',
        'after a bathroom trip',
        'finished a call',
        'sat at my desk',
      ],
    );

    workedExample(
      name: 'B — 20:15 evening, no designed cue',
      category: HabitCategory.hydration,
      loggedAt: DateTime(2026, 3, 2, 20, 15),
      designedCueFamily: null,
      expected: const <String>[
        'before each meal',
        'after a bathroom trip',
        'sat at my desk',
        'after a workout',
        'saw my bottle',
      ],
    );
  });

  group('7.6 tidying', () {
    workedExample(
      name: 'A — 19:30 evening, designed cue in family dinner',
      category: HabitCategory.tidying,
      loggedAt: DateTime(2026, 3, 2, 19, 30),
      designedCueFamily: 'dinner',
      expected: const <String>[
        'got home',
        'finished the dishes',
        'waiting for the kettle',
        'saw the pile',
      ],
    );

    workedExample(
      name: 'B — 09:00 morning, no designed cue, the event floor yields',
      category: HabitCategory.tidying,
      loggedAt: DateTime(2026, 3, 2, 9),
      designedCueFamily: null,
      expected: const <String>[
        'while the coffee brews',
        'saw the pile',
        'walked into the room',
        'sunday morning',
        'felt cluttered',
      ],
    );
  });

  group('7.7 language practice', () {
    workedExample(
      name: 'A — 12:45 midday, designed cue in family lunch',
      category: HabitCategory.languagePractice,
      loggedAt: DateTime(2026, 3, 2, 12, 45),
      designedCueFamily: 'lunch',
      expected: const <String>[
        'picked up my phone',
        'waiting in line',
        'sat at my desk',
        'with morning coffee',
      ],
    );

    workedExample(
      name: 'B — 21:50 night, designed cue in family bed',
      category: HabitCategory.languagePractice,
      loggedAt: DateTime(2026, 3, 2, 21, 50),
      designedCueFamily: 'bed',
      expected: const <String>[
        'got into bed',
        'picked up my phone',
        'after brushing teeth',
        'wanted a break',
      ],
    );
  });

  group('7.8 instrument', () {
    workedExample(
      name: 'A — 19:00 evening, designed cue in family dinner',
      category: HabitCategory.instrument,
      loggedAt: DateTime(2026, 3, 2, 19),
      designedCueFamily: 'dinner',
      expected: const <String>[
        'got home',
        'it was left out',
        'heard a song',
        'finished my chores',
      ],
    );

    workedExample(
      name: 'B — 08:30 morning, no designed cue',
      category: HabitCategory.instrument,
      loggedAt: DateTime(2026, 3, 2, 8, 30),
      designedCueFamily: null,
      expected: const <String>[
        'with morning coffee',
        'it was left out',
        'heard a song',
        'finished my chores',
        'felt like playing',
      ],
    );
  });

  group('7.9 stretching', () {
    workedExample(
      name: 'A — 06:40 early, designed cue in family woke',
      category: HabitCategory.stretching,
      loggedAt: DateTime(2026, 3, 2, 6, 40),
      designedCueFamily: 'woke',
      expected: const <String>[
        'after a workout',
        'after a shower',
        'after a walk',
        'felt stiff',
      ],
    );

    workedExample(
      name: 'B — 21:00 evening, no designed cue',
      category: HabitCategory.stretching,
      loggedAt: DateTime(2026, 3, 2, 21),
      designedCueFamily: null,
      expected: const <String>[
        'after a workout',
        'while watching TV',
        'after a shower',
        'felt stiff',
        'mat was out',
      ],
    );
  });

  group('7.10 supplements', () {
    workedExample(
      name: 'A — 07:45 early, designed cue in family breakfast',
      category: HabitCategory.supplements,
      loggedAt: DateTime(2026, 3, 2, 7, 45),
      designedCueFamily: 'breakfast',
      expected: const <String>[
        'with my coffee',
        'after brushing teeth',
        'packed my bag',
        'first thing up',
      ],
    );

    workedExample(
      name: 'B — 19:00 evening, no designed cue',
      category: HabitCategory.supplements,
      loggedAt: DateTime(2026, 3, 2, 19),
      designedCueFamily: null,
      expected: const <String>[
        'with dinner',
        'saw the bottle',
        'filled my water',
        'before bed',
        'after brushing teeth',
      ],
    );
  });

  group('7.11 walking', () {
    workedExample(
      name: 'A — 18:30 evening, designed cue in family dinner',
      category: HabitCategory.walking,
      loggedAt: DateTime(2026, 3, 2, 18, 30),
      designedCueFamily: 'dinner',
      expected: const <String>[
        'got home',
        'put my shoes on',
        'started a podcast',
        'needed fresh air',
      ],
    );

    workedExample(
      name: 'B — 12:40 midday, no designed cue',
      category: HabitCategory.walking,
      loggedAt: DateTime(2026, 3, 2, 12, 40),
      designedCueFamily: null,
      expected: const <String>[
        'after lunch',
        'put my shoes on',
        'sun was out',
        'needed fresh air',
        'felt stuck',
      ],
    );
  });

  group('7.12 sleep routine', () {
    workedExample(
      name: 'A — 22:20 night, designed cue in family phone',
      category: HabitCategory.sleepRoutine,
      loggedAt: DateTime(2026, 3, 2, 22, 20),
      designedCueFamily: 'phone',
      expected: const <String>[
        'brushed my teeth',
        'got into bed',
        'finished the episode',
        '10pm hit',
      ],
    );

    workedExample(
      name: 'B — 23:30 night, no designed cue',
      category: HabitCategory.sleepRoutine,
      loggedAt: DateTime(2026, 3, 2, 23, 30),
      designedCueFamily: null,
      expected: const <String>[
        'put my phone down',
        'brushed my teeth',
        'got into bed',
        '10pm hit',
        'eyes got heavy',
      ],
    );
  });
}
