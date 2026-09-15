import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/core/utils/local_dates.dart';
import 'package:taproot/features/notifications/domain/evening_check_in.dart';
import 'package:taproot/features/notifications/domain/expected_occasions.dart';

import '../../../../utils/store_fixtures.dart';

/// The evening notification's text.
///
/// Its job is to rehearse the designed cue, not to remind: every cycle should
/// strengthen the breakfast→run association rather than the app→run one
/// (growth spec §6). That makes the wording a behavioural decision, so it is
/// asserted rather than left to a template nobody reads.
void main() {
  const occasion = ExpectedOccasion(index: 3, date: LocalDate(2026, 3, 9));

  test('the forward half names the cue, not the app', () {
    final checkIn = composeEveningCheckIn(
      habit: testHabit(designedCue: 'after breakfast'),
      occasion: occasion,
    );

    expect(checkIn.title, 'Morning run');
    expect(checkIn.body, 'Tomorrow, then — after breakfast?');
  });

  test(
    'a habit with no designed cue gets the plain form, not an invented cue',
    () {
      // Inventing one would be the app putting words in the user's mouth about
      // the single field the whole product is built on.
      final checkIn = composeEveningCheckIn(
        habit: testHabit(designedCue: null, designedCueType: null),
        occasion: occasion,
      );

      expect(checkIn.body, 'Tomorrow, then — Morning run?');
    },
  );

  test('a blank cue is treated as no cue', () {
    final checkIn = composeEveningCheckIn(
      habit: testHabit(designedCue: '   '),
      occasion: occasion,
    );

    expect(checkIn.body, 'Tomorrow, then — Morning run?');
  });

  test('the reflection question goes in front of it, in one notification', () {
    // Reflection and the next-day nudge are deliberately one moment
    // (reflection spec §1): look back at today, then commit to tomorrow. The
    // order is the point — you learn what cued you, then you deploy it.
    final checkIn = composeEveningCheckIn(
      habit: testHabit(),
      occasion: occasion,
      reflectionPrompt: 'You ran this morning — what got you out the door?',
    );

    expect(
      checkIn.body,
      'You ran this morning — what got you out the door?\n'
      'Tomorrow, then — after breakfast?',
    );
  });

  test('the two answers are on the notification itself', () {
    // Answerable from the shade on both platforms, which is what keeps the
    // median check-in inside the ~5 seconds reflection spec §0 budgets.
    const checkIn = EveningCheckIn(title: 'Morning run', body: 'x');

    expect(checkIn.confirmLabel, 'Yes');
    expect(checkIn.declineLabel, 'Different day');
  });

  test('the no-op composer asks nothing', () async {
    // Until the reflection feature lands, the notification is the nudge alone
    // — not a placeholder question.
    expect(
      await const NoReflectionPrompt().promptFor(
        habit: testHabit(),
        occasion: occasion,
        deliverAt: DateTime(2026, 3, 8, 20),
      ),
      isNull,
    );
  });
}
