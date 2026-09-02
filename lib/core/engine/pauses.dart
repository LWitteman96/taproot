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
///
/// Whole-day granularity, to match the windows. **Not** the right tool for
/// elapsed-time arithmetic — using it that way is what made vitality sawtooth
/// through a pause. No caller in `lib/` needs it since that fix; it is kept
/// because "how many days of this window were paused" is a question the
/// window explanations will want to answer.
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

/// Fractional days elapsed between two instants with paused time removed.
/// This is the "days since last completion" every droop curve uses.
///
/// The paused portion is measured as *time*, not as a count of calendar days.
/// Subtracting whole days from a fractional elapsed made active-elapsed climb
/// through each paused day and snap back at local midnight, so a paused plant
/// drooped through the afternoon and sprang back overnight — the opposite of
/// the freeze this is for.
double activeElapsedDays({
  required DateTime from,
  required DateTime to,
  required List<PauseInterval> pauses,
}) {
  final elapsed = elapsedLocalDays(from, to);
  if (pauses.isEmpty || elapsed <= 0) return elapsed;
  final active =
      elapsed - _pausedElapsedDays(from: from, to: to, pauses: pauses);
  return active < 0 ? 0 : active;
}

/// Paused time inside `[from, to]`, in local days.
///
/// A pause owns whole local dates — from midnight opening its start date to
/// midnight closing its end date — so the arithmetic below clips those spans
/// to the range and merges overlaps before measuring.
double _pausedElapsedDays({
  required DateTime from,
  required DateTime to,
  required List<PauseInterval> pauses,
}) {
  final spans = <List<DateTime>>[];
  for (final pause in pauses) {
    final opens = LocalDate.from(pause.startedAt).startOfDay;
    final endedAt = pause.endedAt;
    final closes = endedAt == null
        ? null
        : LocalDate.from(endedAt).addDays(1).startOfDay;

    final start = opens.isBefore(from) ? from : opens;
    final end = (closes == null || closes.isAfter(to)) ? to : closes;
    if (!end.isAfter(start)) continue;
    spans.add(<DateTime>[start, end]);
  }
  if (spans.isEmpty) return 0;

  spans.sort((a, b) => a.first.compareTo(b.first));
  var total = 0.0;
  var mergedStart = spans.first.first;
  var mergedEnd = spans.first.last;
  for (final span in spans.skip(1)) {
    if (span.first.isAfter(mergedEnd)) {
      total += elapsedLocalDays(mergedStart, mergedEnd);
      mergedStart = span.first;
      mergedEnd = span.last;
    } else if (span.last.isAfter(mergedEnd)) {
      mergedEnd = span.last;
    }
  }
  return total + elapsedLocalDays(mergedStart, mergedEnd);
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
