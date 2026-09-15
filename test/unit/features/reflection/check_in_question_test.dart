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
    DateTime? occasionAt,
  }) => checkInQuestion(
    framing: framing,
    habit: habitWith(designedCue: designedCue),
    occasionAt: occasionAt ?? now,
    now: now,
  );

  test('validation names the cue the user designed', () {
    expect(ask(Framing.validation), 'Did after breakfast kick it off?');
  });

  test('validation still works for a habit with no designed cue', () {
    // Journey A habits reach Validation too; asking "did null kick it off?"
    // would be the app showing its plumbing.
    expect(ask(Framing.validation, designedCue: null), 'What got you going?');
  });

  test('confirmation offers the cue back for a single tap', () {
    expect(ask(Framing.confirmation), 'Same as usual — after breakfast?');
  });

  test('autonomy names what just happened', () {
    expect(
      ask(Framing.autonomy),
      'You did this without us asking. What reminded you?',
    );
  });

  group('diagnosis', () {
    test('states the fact neutrally and asks with curiosity', () {
      // Never "you missed your run". The app is a collaborator investigating a
      // system, not a supervisor noting an absence.
      final question = ask(
        Framing.diagnosis,
        occasionAt: now.subtract(const Duration(days: 1)),
      );

      expect(question, 'No morning run yesterday — what got in the way?');
      expect(question.toLowerCase(), isNot(contains('missed')));
      expect(question.toLowerCase(), isNot(contains('you did not')));
    });

    test('says today, yesterday, or the weekday', () {
      expect(ask(Framing.diagnosis), contains('today'));
      expect(
        ask(
          Framing.diagnosis,
          occasionAt: now.subtract(const Duration(days: 1)),
        ),
        contains('yesterday'),
      );
      expect(
        ask(
          Framing.diagnosis,
          occasionAt: now.subtract(const Duration(days: 3)),
        ),
        contains('on Monday'),
      );
      expect(
        ask(
          Framing.diagnosis,
          occasionAt: now.subtract(const Duration(days: 20)),
        ),
        contains('last time'),
      );
    });
  });

  test('every framing produces a question', () {
    for (final framing in Framing.values) {
      expect(ask(framing), isNotEmpty, reason: framing.name);
      expect(ask(framing), endsWith('?'), reason: framing.name);
    }
  });

  test('only the framings that need a preamble get one', () {
    expect(checkInPreamble(Framing.validation), isNotNull);
    expect(checkInPreamble(Framing.diagnosis), isNotNull);
    expect(checkInPreamble(Framing.discovery), isNull);
    expect(checkInPreamble(Framing.confirmation), isNull);
  });
}
