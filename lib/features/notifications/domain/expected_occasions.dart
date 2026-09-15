import 'package:meta/meta.dart';

import 'package:taproot/core/engine/constants.dart';
import 'package:taproot/core/engine/pauses.dart';
import 'package:taproot/core/models/pause_interval.dart';
import 'package:taproot/core/utils/local_dates.dart';

/// One expected occasion: the local date the engine expects the habit on, and
/// its index in the habit's lifetime cadence.
@immutable
class ExpectedOccasion {
  const ExpectedOccasion({required this.index, required this.date});

  /// n — counted from the habit's creation date, which is occasion 0. Stable
  /// across planning passes because it is derived from the calendar, never
  /// from how many rows happen to be in the ledger.
  final int index;

  final LocalDate date;

  @override
  bool operator ==(Object other) =>
      other is ExpectedOccasion && other.index == index && other.date == date;

  @override
  int get hashCode => Object.hash(index, date);

  @override
  String toString() => 'ExpectedOccasion($index, $date)';
}

/// The cadence: occasion n falls on the creation date plus `round(n × 7 / f)`
/// days.
///
/// **A habit carries `f` and nothing else** — no weekday set, no time of day
/// (see `Habit`). Something still has to name the days, because autonomy is
/// counted over *occasions* and a nudge has to pick an evening. Even spreading
/// from the creation date is the smallest rule that is faithful to `f`: it
/// yields exactly `f` occasions in every rolling week (f = 3 → day 0, 2, 5, 7;
/// f = 5 → 0, 1, 3, 4, 6, 7), it never drifts, and it needs no stored schedule
/// to reproduce — any device replaying the same habit derives the same dates.
///
/// **OPEN (reflection spec §8, growth spec §9).** Neither spec picks the
/// occasion calendar. The obvious alternative is letting the user choose
/// weekdays at creation, which is better UX and worse measurement: a user who
/// picks Mon/Wed/Fri and runs on Tuesday looks like a miss *and* an un-nudged
/// occasion he never had. Implemented as the default, left flagged rather than
/// presented as settled.
LocalDate occasionDate({
  required DateTime createdAt,
  required int targetFrequency,
  required int index,
}) => LocalDate.from(createdAt).addDays((index * 7 / targetFrequency).round());

/// Every expected occasion falling in `[from, to]`, oldest first.
///
/// Occasions on paused days are **not** returned. A pause excludes a day from
/// every window (growth spec §7), so an occasion there would be an expectation
/// the engine has already agreed not to hold — and, written to the ledger, an
/// un-nudged occasion the user is then measured against for a day he was
/// explicitly not expected to show up.
List<ExpectedOccasion> expectedOccasionsBetween({
  required DateTime createdAt,
  required int targetFrequency,
  required LocalDate from,
  required LocalDate to,
  List<PauseInterval> pauses = const <PauseInterval>[],
}) {
  final created = LocalDate.from(createdAt);
  if (to.isBefore(created) || to.isBefore(from)) {
    return const <ExpectedOccasion>[];
  }

  final occasions = <ExpectedOccasion>[];
  final lastOffset = daysBetween(created, to);

  // Step from the first candidate index that can reach `from` rather than from
  // zero: a two-year-old daily habit would otherwise walk 700 dead indexes on
  // every planning pass.
  var index = _firstIndexOnOrAfter(
    createdAt: createdAt,
    targetFrequency: targetFrequency,
    day: from,
  );

  while (true) {
    final offset = (index * 7 / targetFrequency).round();
    if (offset > lastOffset) break;
    final date = created.addDays(offset);
    if (!date.isBefore(from) && !isPausedOn(date, pauses)) {
      occasions.add(ExpectedOccasion(index: index, date: date));
    }
    index++;
  }
  return occasions;
}

/// The lowest index whose date is not before [day], never below zero.
int _firstIndexOnOrAfter({
  required DateTime createdAt,
  required int targetFrequency,
  required LocalDate day,
}) {
  final created = LocalDate.from(createdAt);
  final offset = daysBetween(created, day);
  if (offset <= 0) return 0;

  // Invert round(n × 7 / f) approximately, then walk back to the true first
  // index. Rounding makes the inverse off by at most one either way, so the
  // walk is bounded and cheap — but it has to happen, or f = 7 lands an index
  // late and the day is silently dropped.
  var index = (offset * targetFrequency / 7).floor();
  while (index > 0 &&
      !created
          .addDays(((index - 1) * 7 / targetFrequency).round())
          .isBefore(day)) {
    index--;
  }
  return index;
}

/// The instant the nudge for [occasion] is delivered: the evening before, on
/// the local wall clock.
///
/// Reflection and the next-day nudge are one notification (reflection spec
/// §1) — look back at today, commit to tomorrow — so this is the single slot
/// both halves arrive in.
DateTime nudgeDeliveryTime(ExpectedOccasion occasion) {
  final evening = occasion.date.addDays(-EngineConstants.nudgeLeadDays);
  return DateTime(
    evening.year,
    evening.month,
    evening.day,
    EngineConstants.eveningCheckInHour,
    EngineConstants.eveningCheckInMinute,
  );
}
