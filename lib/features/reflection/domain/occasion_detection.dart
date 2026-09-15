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
/// - **An expected occasion in the future is not a miss.** The nudge ledger
///   holds rows up to seven days ahead, because scheduling writes them before
///   the occasion arrives. Reading those as misses would diagnose the user for
///   not having done tomorrow yet.
/// - **`sent` is what makes a completion un-nudged, not `confirmed`.**
///   `confirmed` and `declined` record what the user did with a *notification*,
///   which is not the same as what they did with the habit — someone can
///   dismiss the notification and go for the run. Autonomy is measured by
///   whether the app stayed silent, which is `sent`.
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

  final freshCompletions =
      completions.where((completion) => isNew(completion.completedAt)).toList()
        ..sort((a, b) => a.completedAt.compareTo(b.completedAt));

  final missed =
      nudges
          .where(
            (nudge) =>
                isNew(nudge.expectedOccasionAt) &&
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
    final wasSilent = silentDates.contains(
      LocalDate.from(completion.completedAt),
    );

    return CheckInOccasion(
      habitId: habitId,
      occasion: wasSilent ? Occasion.autonomyCompletion : Occasion.completion,
      at: completion.completedAt,
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
  );
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
