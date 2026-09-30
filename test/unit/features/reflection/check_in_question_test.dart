import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/habit.dart';
import 'package:taproot/core/models/habit_journey.dart';
import 'package:taproot/features/reflection/domain/check_in_question.dart';

void main() {
  final now = DateTime(2026, 3, 12, 20);

  Habit habitWith({String? designedCue = 'after breakfast'}) => Habit(
    id: 'habit-1',
    name: 'Morning run',
    plantType: 'oak',
    targetFrequency: 3,
    journey: designedCue == null ? HabitJourney.track : HabitJourney.design,
    designedCue: designedCue,
    designedCueType: designedCue == null ? null : CueType.event,
    createdAt: DateTime(2026, 1, 1),
  );

  String ask(
    Framing framing, {
    String? designedCue = 'after breakfast',
    bool expanded = false,
  }) => checkInQuestion(
    framing: framing,
    habit: habitWith(designedCue: designedCue),
    expanded: expanded,
  );

  String fact(
    Framing framing, {
    String? designedCue = 'after breakfast',
    DateTime? occasionAt,
  }) => checkInFact(
    framing: framing,
    habit: habitWith(designedCue: designedCue),
    occasionAt: occasionAt ?? now,
    now: now,
  );

  group('the fact line', () {
    // check-in-design §5, one test per row. The fact line replaced the
    // preambles, which were reassurance nobody asked for -- and reassurance
    // implies there was something to be reassured about.
    test('states what happened, neutrally', () {
      expect(
        fact(Framing.validation, occasionAt: DateTime(2026, 3, 12, 7)),
        'Morning run — done this morning.',
      );
      expect(
        fact(Framing.confirmation, occasionAt: DateTime(2026, 3, 12, 7)),
        'Morning run — done this morning.',
      );
      expect(
        fact(Framing.discovery, occasionAt: DateTime(2026, 3, 12, 7)),
        'Morning run — done this morning.',
      );
    });

    test('autonomy names the thing that makes it autonomy', () {
      expect(
        fact(Framing.autonomy, occasionAt: DateTime(2026, 3, 12, 7)),
        'Morning run — done this morning, without us asking.',
      );
    });

    test('diagnosis states the absence, never the person', () {
      // "No morning run yesterday" is a fact about a day. "You missed your
      // run" is a fact about a user, and the app is not a supervisor.
      expect(
        fact(Framing.diagnosis, occasionAt: DateTime(2026, 3, 11, 7)),
        'No morning run yesterday.',
      );
    });

    test('today is spoken as a daypart, not as "today"', () {
      expect(
        fact(Framing.discovery, occasionAt: DateTime(2026, 3, 12, 7)),
        contains('this morning'),
      );
      expect(
        fact(Framing.discovery, occasionAt: DateTime(2026, 3, 12, 12)),
        contains('this afternoon'),
      );
      expect(
        fact(Framing.discovery, occasionAt: DateTime(2026, 3, 12, 19)),
        contains('this evening'),
      );
    });

    test('midday and night are spoken as afternoon and evening', () {
      // The six chip-ranking buckets exist to rank chips, not to be spoken:
      // "this midday" and "this night" are not things people say.
      expect(
        fact(Framing.discovery, occasionAt: DateTime(2026, 3, 12, 11, 30)),
        contains('this afternoon'),
      );
      expect(
        fact(Framing.discovery, occasionAt: DateTime(2026, 3, 12, 23)),
        contains('this evening'),
      );
    });

    test('earlier days are named, never counted', () {
      // "3 days ago" reads like an accusation with arithmetic attached.
      expect(
        fact(Framing.discovery, occasionAt: DateTime(2026, 3, 9, 7)),
        'Morning run — done on Monday.',
      );
    });
  });

  group('step 1 questions', () {
    test('validation names the cue the user designed', () {
      expect(ask(Framing.validation), 'Did after breakfast kick it off?');
    });

    test('validation falls back when there is no designed cue', () {
      // Journey A habits reach Validation too; asking "did null kick it off?"
      // would be the app showing its plumbing.
      expect(ask(Framing.validation, designedCue: null), 'What got you going?');
    });

    test('confirmation asks whether it was the same as usual', () {
      expect(ask(Framing.confirmation), 'Same as usual — after breakfast?');
      expect(ask(Framing.confirmation, designedCue: null), 'Same as usual?');
    });

    test('the yes/no framings expand into an open question', () {
      // "No, something else" is not an answer by itself; only the pick after
      // it is, so the expansion has to ask something answerable.
      expect(
        ask(Framing.validation, expanded: true),
        'What got you going, then?',
      );
      expect(
        ask(Framing.confirmation, expanded: true),
        'What was it this time?',
      );
    });

    test('the open framings ask openly', () {
      expect(ask(Framing.discovery), 'What got you going?');
      expect(ask(Framing.autonomy), 'What reminded you?');
      expect(ask(Framing.diagnosis), 'What got in the way?');
    });

    test('the when has moved out of the question and into the fact', () {
      // It used to be inside the question ("What got you going today?"), which
      // made the question longer every time it was about an older occasion.
      for (final framing in Framing.values) {
        expect(ask(framing), isNot(contains('this ')));
        expect(ask(framing), isNot(contains('yesterday')));
      }
    });
  });

  group('step 2', () {
    final tomorrow = DateTime(2026, 3, 13, 7);
    final thursday = DateTime(2026, 3, 19, 7);

    test('the fact says when the next one is', () {
      expect(commitFact(nextOccasionAt: tomorrow, now: now), 'Tomorrow, then.');
      expect(
        commitFact(nextOccasionAt: thursday, now: now),
        'Thursday next, then.',
      );
    });

    test('the question rehearses the cue, never the app', () {
      // growth-engine §6: every cycle should strengthen the breakfast->run
      // association, not the app->run one.
      expect(
        commitQuestion(habit: habitWith(), framing: Framing.discovery),
        'After breakfast?',
      );
      expect(
        commitQuestion(habit: habitWith(), framing: Framing.discovery),
        isNot(contains('Morning run')),
      );
    });

    test('diagnosis asks whether the plan still stands', () {
      // It has just established the plan did not happen; asking "after
      // breakfast?" as though nothing had would read as not listening.
      expect(
        commitQuestion(habit: habitWith(), framing: Framing.diagnosis),
        'After breakfast — still the plan?',
      );
    });

    test('a habit with no designed cue gets the plain form', () {
      // And never an invented cue.
      expect(
        commitQuestion(
          habit: habitWith(designedCue: null),
          framing: Framing.discovery,
        ),
        'Morning run?',
      );
    });
  });

  test('the notification and the sheet ask the same thing', () {
    // check-in-design §5: "These must match what composeEveningCheckIn() says.
    // If they differ, change both together." The only way to guarantee that is
    // for both to come from here, which this asserts rather than assumes.
    final line = commitLine(
      habit: habitWith(),
      framing: Framing.discovery,
      nextOccasionAt: DateTime(2026, 3, 13, 7),
      now: now,
    );
    expect(line, 'Tomorrow, then — after breakfast?');
  });
}
