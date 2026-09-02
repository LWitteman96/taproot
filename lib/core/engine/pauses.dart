import 'package:taproot/core/models/pause_interval.dart';
import 'package:taproot/core/utils/local_dates.dart';

/// Pause arithmetic (growth spec §7).
///
/// Paused days are excluded from every window and vitality freezes across
/// them. Pausing is whole-day granular: a day is paused if any interval covers
/// its local date.

/// Walking back day by day needs a bound, or an interval that opens before the
/// habit did would loop forever.
const int _maximumLookbackDays = 36500;

bool isPausedOn(LocalDate day, List<PauseInterval> pauses) {
  for (final pause in pauses) {
    if (day.isBefore(LocalDate.from(pause.startedAt))) continue;
    final endedAt = pause.endedAt;
    if (endedAt == null || !day.isAfter(LocalDate.from(endedAt))) return true;
  }
  return false;
}

/// Paused local dates in the half-open range (after, through].
///
/// The opening day is excluded because it is the day an event happened on, and
/// is therefore only partially elapsed.
int pausedDaysBetween({
  required LocalDate after,
  required LocalDate through,
  required List<PauseInterval> pauses,
}) {
  if (pauses.isEmpty) return 0;
  final span = daysBetween(after, through);
  var paused = 0;
  for (var offset = 1; offset <= span; offset++) {
    if (isPausedOn(after.addDays(offset), pauses)) paused++;
  }
  return paused;
}

/// Fractional days elapsed between two instants with paused whole days
/// removed. This is the "days since last completion" every droop curve uses.
double activeElapsedDays({
  required DateTime from,
  required DateTime to,
  required List<PauseInterval> pauses,
}) {
  final elapsed = elapsedLocalDays(from, to);
  if (pauses.isEmpty || elapsed <= 0) return elapsed;
  final paused = pausedDaysBetween(
    after: LocalDate.from(from),
    through: LocalDate.from(to),
    pauses: pauses,
  );
  final active = elapsed - paused;
  return active < 0 ? 0 : active;
}

/// The most recent [windowDays] *unpaused* local dates ending on the local
/// date of [at], oldest first.
///
/// A pause stretches the window backwards in wall-clock time rather than
/// shortening it, so a paused stretch costs the user nothing.
List<LocalDate> activeWindowDates({
  required DateTime at,
  required int windowDays,
  required List<PauseInterval> pauses,
}) {
  if (windowDays <= 0) return const <LocalDate>[];
  final dates = <LocalDate>[];
  var cursor = LocalDate.from(at);
  var steps = 0;
  while (dates.length < windowDays && steps < _maximumLookbackDays) {
    if (!isPausedOn(cursor, pauses)) dates.add(cursor);
    cursor = cursor.addDays(-1);
    steps++;
  }
  return dates.reversed.toList();
}

/// The instant [activeDays] active days before [at], on the local clock.
DateTime activeDaysBefore({
  required DateTime at,
  required int activeDays,
  required List<PauseInterval> pauses,
}) {
  final local = at.isUtc ? at.toLocal() : at;
  var cursor = LocalDate.from(local);
  var remaining = activeDays;
  var steps = 0;
  while (remaining > 0 && steps < _maximumLookbackDays) {
    cursor = cursor.addDays(-1);
    if (!isPausedOn(cursor, pauses)) remaining--;
    steps++;
  }
  return DateTime(
    cursor.year,
    cursor.month,
    cursor.day,
    local.hour,
    local.minute,
    local.second,
    local.millisecond,
  );
}
