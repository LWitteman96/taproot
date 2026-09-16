/// Every sentence the check-in says, as pure functions.
///
/// One voice, deliberately (check-in-design §2.4). The sheet on screen and the
/// evening notification — composed up to a week before it fires — ask the same
/// thing, so they compose it from here rather than each writing their own. Two
/// places asking the same question in two different voices would be worse than
/// either voice on its own.
///
/// These are *presentation*. Which habit, which framing and whether to ask at
/// all stay with reflection-logic §2–§3 and `framing_selection.dart`.
library;

import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/habit.dart';
import 'package:taproot/core/utils/local_dates.dart';
import 'package:taproot/features/reflection/domain/daypart.dart';

/// The neutral line above the question: what happened, stated as a fact.
///
/// check-in-design §1 drops the old preambles ("Testing the cue you
/// designed…", "No judgement…") in favour of this. They were reassurance the
/// user had not asked for, and reassurance implies there was something to be
/// reassured about — which is the opposite of neutral.
String checkInFact({
  required Framing framing,
  required Habit habit,
  required DateTime occasionAt,
  required DateTime now,
}) {
  final when = whenPhrase(occasionAt, now);
  return switch (framing) {
    // State the absence, never the person. "No morning run yesterday" is a
    // fact about a day; "you missed your run" is a fact about a user.
    Framing.diagnosis => 'No ${habit.name.toLowerCase()} $when.',
    // The one that earns its own framing: a completion nobody asked for is the
    // app's best evidence the habit stands on its own, and naming that back is
    // the point.
    Framing.autonomy => '${habit.name} — done $when, without us asking.',
    _ => '${habit.name} — done $when.',
  };
}

/// What the check-in asks (reflection-logic §3).
///
/// [expanded] is the second half of the two yes/no framings: the user has said
/// the designed cue was *not* what happened, and is being asked what was.
String checkInQuestion({
  required Framing framing,
  required Habit habit,
  bool expanded = false,
}) {
  final cue = _cue(habit);
  return switch (framing) {
    Framing.validation when expanded => 'What got you going, then?',
    Framing.confirmation when expanded => 'What was it this time?',

    // No designed cue means nothing to validate or confirm, so both fall back
    // to asking openly rather than inventing a cue to put in the sentence.
    Framing.validation =>
      cue == null ? 'What got you going?' : 'Did $cue kick it off?',
    Framing.confirmation =>
      cue == null ? 'Same as usual?' : 'Same as usual — $cue?',

    Framing.discovery => 'What got you going?',
    Framing.autonomy => 'What reminded you?',
    Framing.diagnosis => 'What got in the way?',
  };
}

/// The fact line on the commit step: when the next occasion is.
String commitFact({required DateTime nextOccasionAt, required DateTime now}) {
  final days = daysBetween(LocalDate.from(now), LocalDate.from(nextOccasionAt));
  return days <= 1
      ? 'Tomorrow, then.'
      : '${weekdayName(nextOccasionAt.toLocal().weekday)} next, then.';
}

/// The question on the commit step.
///
/// **Rehearses the designed cue rather than naming the app** — "after
/// breakfast?", never "don't forget to run". That is the single strongest idea
/// in the flow (growth-engine §6): every cycle strengthens the breakfast→run
/// association instead of the app→run one. A habit with no designed cue gets
/// the plain form and never an invented one.
String commitQuestion({required Habit habit, required Framing framing}) =>
    _commitQuestion(habit: habit, framing: framing, standalone: true);

/// The one-line body of the evening notification's forward half.
///
/// The same words as [commitFact] + [commitQuestion], joined into one sentence
/// — so the notification and the sheet cannot drift apart (check-in-design §5).
String commitLine({
  required Habit habit,
  required Framing framing,
  required DateTime nextOccasionAt,
  required DateTime now,
}) {
  final fact = commitFact(nextOccasionAt: nextOccasionAt, now: now);
  final question = _commitQuestion(
    habit: habit,
    framing: framing,
    standalone: false,
  );
  return '${fact.substring(0, fact.length - 1)} — $question';
}

/// [standalone] capitalises the subject, for a line of its own in the sheet.
///
/// Mid-sentence in the notification it keeps the case it was written in, which
/// matters because the subject is a **cue** ("after breakfast") for most habits
/// and a **name** ("Morning run") for one with no designed cue — and
/// lowercasing a name is not the same kindness as lowercasing a cue.
String _commitQuestion({
  required Habit habit,
  required Framing framing,
  required bool standalone,
}) {
  final cue = _cue(habit);
  final subject = cue == null
      ? habit.name
      : (standalone ? _capitalise(cue) : cue);
  // Diagnosis has just established the plan did not happen, so asking
  // "after breakfast?" as though nothing had would read as not listening.
  return framing == Framing.diagnosis && cue != null
      ? '$subject — still the plan?'
      : '$subject?';
}

/// `this morning` / `this afternoon` / `this evening` for today, `yesterday`,
/// or `on {Weekday}`.
///
/// Local calendar days, like every other window in the app. Saying "3 days ago"
/// reads like an accusation with arithmetic attached; a weekday does not.
String whenPhrase(DateTime occasionAt, DateTime now) {
  final days = daysBetween(LocalDate.from(occasionAt), LocalDate.from(now));
  return switch (days) {
    <= 0 => 'this ${_daypartPhrase(occasionAt)}',
    1 => 'yesterday',
    < 7 => 'on ${weekdayName(occasionAt.toLocal().weekday)}',
    _ => 'last time',
  };
}

/// The six chip-ranking dayparts collapse to the three a sentence can use.
///
/// `midday` reads as afternoon and `night` as evening, because "this midday"
/// and "this night" are not things people say. The six-bucket split exists to
/// rank chips (starter-chip-library §4), not to be spoken.
String _daypartPhrase(DateTime at) => switch (daypartFor(at)) {
  Daypart.early || Daypart.morning => 'morning',
  Daypart.midday || Daypart.afternoon => 'afternoon',
  Daypart.evening || Daypart.night => 'evening',
};

String weekdayName(int weekday) => const <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
][weekday - 1];

String? _cue(Habit habit) {
  final cue = habit.designedCue?.trim();
  return cue == null || cue.isEmpty ? null : cue;
}

String _capitalise(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
