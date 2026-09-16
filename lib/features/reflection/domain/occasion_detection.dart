import 'package:taproot/core/engine/constants.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/completion.dart';
import 'package:taproot/core/models/nudge.dart';
import 'package:taproot/core/models/reflection.dart';
import 'package:taproot/core/utils/local_dates.dart';
import 'package:taproot/features/reflection/domain/reflection_priority.dart';

/// The one thing about this habit worth asking about, if anything is.
///
/// Every occasion type in reflection-logic §2 — a completion, a missed expected
/// occasion, an un-nudged completion — is read out of the two ledgers here. The
/// rules that matter:
///
/// - **Only events since the last reflection count.** Otherwise the same
///   completion is asked about every evening until something newer happens.
/// - **An occasion is only a miss once it is over.** The ledger's
///   `expected_occasion_at` is `startOfDay` — local midnight, not the hour the
///   user actually does the thing — so a row for *today* looks exactly like a
///   row for a day that has been and gone. Reading it as a miss diagnoses a
///   19:00 runner at 08:00 for a run they were always going to do. An occasion
///   becomes missable when its day is over, or when its own evening check-in
///   slot has passed, which is the moment the app looks back at today anyway
///   (reflection spec §1). Future-dated rows are excluded by the same rule.
/// - **`sent` is what makes a completion un-nudged, not `confirmed`.**
///   `confirmed` and `declined` record what the user did with a *notification*,
///   which is not the same as what they did with the habit — someone can
///   dismiss the notification and go for the run. Autonomy is measured by
///   whether the app stayed silent, which is `sent`.
/// - **But an un-sent row is not by itself evidence of autonomy.** `sent:
///   false` is written for all four of `_decide`'s outcomes — the fade rule
///   choosing silence, an evening that had already passed when the backfill
///   ran, no notification permission, and the pending-notification cap — and
///   the reason is discarded before the row is persisted. Only the first is
///   autonomy. Saying *"you did this without us asking"* to someone who
///   declined notifications, on every check-in, is the app claiming a
///   restraint it never exercised. Until the ledger carries the reason (see
///   [_nudgingWasLiveAround]), the claim is gated on evidence that the app was
///   actually nudging this habit around that occasion.
CheckInOccasion? occasionFor({
  required String habitId,
  required List<Completion> completions,
  required List<NudgeRecord> nudges,
  required List<Reflection> reflections,
  required int targetFrequency,
  required DateTime at,
}) {
  final askedAlready = reflections.isEmpty
      ? null
      : reflections
            .map((reflection) => reflection.createdAt)
            .reduce((a, b) => a.isAfter(b) ? a : b);

  bool isNew(DateTime when) =>
      !when.isAfter(at) && (askedAlready == null || when.isAfter(askedAlready));

  final completedOn = <LocalDate>{
    for (final completion in completions)
      LocalDate.from(completion.completedAt),
  };

  // The silent occasions — the ones the engine chose not to nudge. These are
  // what make a completion an autonomy event.
  final silentDates = <LocalDate>{
    for (final nudge in nudges)
      if (!nudge.sent) LocalDate.from(nudge.expectedOccasionAt),
  };
  final nudgedDates = <LocalDate>{
    for (final nudge in nudges)
      if (nudge.sent) LocalDate.from(nudge.expectedOccasionAt),
  };

  final freshCompletions =
      completions.where((completion) => isNew(completion.completedAt)).toList()
        ..sort((a, b) => a.completedAt.compareTo(b.completedAt));

  final missed =
      nudges
          .where(
            (nudge) =>
                isNew(nudge.expectedOccasionAt) &&
                _occasionIsOver(nudge.expectedOccasionAt, at) &&
                !completedOn.contains(LocalDate.from(nudge.expectedOccasionAt)),
          )
          .toList()
        ..sort((a, b) => a.expectedOccasionAt.compareTo(b.expectedOccasionAt));

  final latestCompletion = freshCompletions.isEmpty
      ? null
      : freshCompletions.last;
  final latestMiss = missed.isEmpty ? null : missed.last;

  if (latestCompletion == null && latestMiss == null) return null;

  // The most recent thing wins. The evening check-in looks back at today, and
  // a miss three days ago is not what today was about.
  final askAboutCompletion =
      latestMiss == null ||
      (latestCompletion != null &&
          latestCompletion.completedAt.isAfter(latestMiss.expectedOccasionAt));

  if (askAboutCompletion) {
    final completion = latestCompletion!;
    final completedDate = LocalDate.from(completion.completedAt);
    // Silence only means something against a background of nudges. See the
    // `sent: false` note above: without the suppression reason on the row,
    // "the app was nudging this habit that week and stayed quiet on this day"
    // is the strongest evidence available that the silence was chosen.
    final wasSilent =
        silentDates.contains(completedDate) &&
        _nudgingWasLiveAround(completedDate, nudges);

    return CheckInOccasion(
      habitId: habitId,
      occasion: wasSilent ? Occasion.autonomyCompletion : Occasion.completion,
      at: completion.completedAt,
      wasNudged: nudgedDates.contains(LocalDate.from(completion.completedAt)),
      isAnomalous: isAnomalousOccasion(
        at: completion.completedAt,
        previousCompletions: completions
            .where(
              (earlier) => earlier.completedAt.isBefore(completion.completedAt),
            )
            .map((earlier) => earlier.completedAt)
            .toList(),
        targetFrequency: targetFrequency,
      ),
    );
  }

  return CheckInOccasion(
    habitId: habitId,
    occasion: Occasion.miss,
    at: latestMiss.expectedOccasionAt,
    wasNudged: latestMiss.sent,
  );
}

/// Whether an expected occasion has finished, as far as asking about it goes.
///
/// The row's timestamp is local midnight, so "has this occasion happened" can
/// never be read off it directly. A day that is over is over; today counts
/// once its evening check-in slot has passed, because that is the moment the
/// app is entitled to look back at the day (reflection spec §1).
bool _occasionIsOver(DateTime expectedOccasionAt, DateTime at) {
  final day = LocalDate.from(expectedOccasionAt);
  if (day.isBefore(LocalDate.from(at))) return true;
  if (day.isAfter(LocalDate.from(at))) return false;

  final slot = DateTime(
    day.year,
    day.month,
    day.day,
    EngineConstants.eveningCheckInHour,
    EngineConstants.eveningCheckInMinute,
  );
  return !at.isBefore(slot);
}

/// Whether the app was demonstrably nudging this habit around [date].
///
/// **A stand-in for a column the ledger does not have.** `NudgeRecord` keeps
/// `sent` and `scheduledFor`; the suppression reason that would separate *the
/// engine chose silence* from *there was no permission*, *the evening had
/// already passed when the backfill ran* and *the pending cap was full* is
/// computed in `NudgeScheduler._decide` and dropped on the floor. A
/// `suppression_reason` column on `nudges` is what closes this properly, and
/// it closes it for `autonomy.dart` at the same time — the convention is
/// inherited from there, and this is the first consumer that says it out loud
/// to the user.
///
/// Until then: a sent nudge within a horizon either side of the occasion means
/// notifications were permitted, the scheduler was running, and the cap was
/// not exhausted — so an un-sent day inside that span is the fade rule at
/// work. A habit with no sends anywhere near it is a habit the app was not
/// nudging, and its silence claims nothing.
bool _nudgingWasLiveAround(LocalDate date, List<NudgeRecord> nudges) {
  final from = date.addDays(-EngineConstants.nudgeHorizonDays);
  final to = date.addDays(EngineConstants.nudgeHorizonDays);
  for (final nudge in nudges) {
    if (!nudge.sent) continue;
    final sentOn = LocalDate.from(nudge.expectedOccasionAt);
    if (!sentOn.isBefore(from) && !sentOn.isAfter(to)) return true;
  }
  return false;
}

/// Check-ins already spent on this habit in the last seven local days.
int promptsInTheLastWeek({
  required List<Reflection> reflections,
  required DateTime at,
}) {
  final cutoff = LocalDate.from(at).addDays(-6);
  return reflections
      .where(
        (reflection) =>
            !LocalDate.from(reflection.createdAt).isBefore(cutoff) &&
            !reflection.createdAt.isAfter(at),
      )
      .length;
}
