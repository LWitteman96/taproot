import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/habit.dart';
import 'package:taproot/core/utils/local_dates.dart';

/// What the check-in actually asks (reflection-logic §3).
///
/// A pure function of the framing and the habit, so the same sentence can be
/// composed on screen and — later — into the evening notification, which is
/// written up to seven days before it fires. Two places asking the same
/// question in two different voices would be worse than either voice.
String checkInQuestion({
  required Framing framing,
  required Habit habit,
  required DateTime occasionAt,
  required DateTime now,
}) => switch (framing) {
  Framing.validation =>
    habit.designedCue == null
        ? 'What got you going?'
        : 'Did ${habit.designedCue} kick it off?',

  Framing.discovery => 'What got you going ${_when(occasionAt, now)}?',

  Framing.confirmation =>
    habit.designedCue == null
        ? 'Same as usual?'
        : 'Same as usual — ${habit.designedCue}?',

  // The one that earns its own framing. A completion nobody asked for is the
  // app's best evidence that the habit stands on its own, and naming that back
  // to the user is the point.
  Framing.autonomy => 'You did this without us asking. What reminded you?',

  // **State the fact neutrally, ask with curiosity.** Never "you missed your
  // run" — the app is a collaborator investigating a system, not a supervisor
  // noting an absence. The habit's own name goes in, lowercased, so the
  // sentence reads as speech rather than as a record.
  Framing.diagnosis =>
    'No ${habit.name.toLowerCase()} ${_when(occasionAt, now)} — '
        'what got in the way?',
};

/// The one line under the question, where one helps.
String? checkInPreamble(Framing framing) => switch (framing) {
  Framing.validation =>
    'Testing the cue you designed. A no is as useful as a yes.',
  Framing.discovery => null,
  Framing.confirmation => null,
  Framing.autonomy => null,
  Framing.diagnosis => 'No judgement — we are looking for the pattern.',
};

/// `today`, `yesterday`, or a weekday — in local calendar days.
///
/// The evening check-in usually asks about today, sometimes about yesterday,
/// and occasionally about a miss further back. Saying "on Tuesday" for
/// something three days ago is kinder and clearer than "3 days ago", which
/// reads like an accusation with arithmetic attached.
String _when(DateTime occasionAt, DateTime now) {
  final days = daysBetween(LocalDate.from(occasionAt), LocalDate.from(now));
  return switch (days) {
    <= 0 => 'today',
    1 => 'yesterday',
    < 7 => 'on ${_weekday(occasionAt.toLocal().weekday)}',
    _ => 'last time',
  };
}

String _weekday(int weekday) => const <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
][weekday - 1];
