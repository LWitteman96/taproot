/// Whether there is anything to commit to, and which occasion it is.
library;

import 'package:meta/meta.dart';

import 'package:taproot/core/models/habit.dart';
import 'package:taproot/core/models/nudge.dart';
import 'package:taproot/core/models/pause_interval.dart';
import 'package:taproot/core/utils/local_dates.dart';
import 'package:taproot/features/notifications/domain/expected_occasions.dart';

/// The next expected occasion the commit step would ask about.
@immutable
class CommitTarget {
  const CommitTarget({required this.occasion, required this.nudge});

  final ExpectedOccasion occasion;

  /// The ledger row to record the answer against. Every expected occasion has
  /// one — including the ones deliberately not nudged, which is what autonomy's
  /// denominator is counted over (CLAUDE.md) — so a missing row means the
  /// planner has not reached this occasion yet.
  final NudgeRecord nudge;

  DateTime get at => occasion.date.startOfDay;
}

/// The occasion to commit to, or null when there is nothing to ask.
///
/// check-in-design §4.3 skips step 2 entirely in three cases, and they are all
/// the same case really: there is no open question about tomorrow. Asking
/// anyway would be the app pretending to listen.
///
/// - the next occasion already has an answer, for example from the
///   notification's own Yes action;
/// - the habit is paused or graduated;
/// - the engine has no next expected occasion at all.
CommitTarget? commitTargetFor({
  required Habit habit,
  required List<NudgeRecord> nudges,
  required List<PauseInterval> pauses,
  required DateTime now,
  int horizonDays = 14,
}) {
  if (habit.isPaused || habit.graduatedAt != null) return null;

  final today = LocalDate.from(now);
  final occasions = expectedOccasionsBetween(
    createdAt: habit.createdAt,
    targetFrequency: habit.targetFrequency,
    // From tomorrow: the check-in happens in the evening of a day whose
    // occasion has already been and gone, and committing to it would be
    // committing to the past.
    from: today.addDays(1),
    to: today.addDays(horizonDays),
    pauses: pauses,
  );
  if (occasions.isEmpty) return null;

  final next = occasions.first;
  for (final nudge in nudges) {
    if (!LocalDate.from(nudge.expectedOccasionAt).isSameDay(next.date)) {
      continue;
    }
    // Already answered — by the notification, or by an earlier check-in.
    if (nudge.confirmed || nudge.declined) return null;
    return CommitTarget(occasion: next, nudge: nudge);
  }

  // No ledger row yet: the planner has not reached this occasion. Recording an
  // answer against a row that does not exist would be inventing one, and the
  // planner would then overwrite it.
  return null;
}

extension on LocalDate {
  bool isSameDay(LocalDate other) =>
      year == other.year && month == other.month && day == other.day;
}
