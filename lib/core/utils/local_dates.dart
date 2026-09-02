import 'package:meta/meta.dart';

/// Local-calendar day arithmetic.
///
/// Every window in the growth engine is a *local calendar* quantity — "days
/// since last completion", "rolling 7 days", "42-day window". Timestamps are
/// stored as UTC, but if the window maths were done in UTC too, vitality would
/// droop at midnight UTC for half the users. Everything here converts to local
/// time first and counts whole days through UTC anchors, so a DST transition
/// never turns a day into 23 or 25 hours.
@immutable
class LocalDate implements Comparable<LocalDate> {
  const LocalDate(this.year, this.month, this.day);

  /// The local calendar date on which [instant] falls.
  factory LocalDate.from(DateTime instant) {
    final local = instant.isUtc ? instant.toLocal() : instant;
    return LocalDate(local.year, local.month, local.day);
  }

  final int year;
  final int month;
  final int day;

  /// Local midnight opening this date.
  DateTime get startOfDay => DateTime(year, month, day);

  LocalDate addDays(int days) =>
      LocalDate.from(DateTime(year, month, day + days));

  @override
  int compareTo(LocalDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  bool isBefore(LocalDate other) => compareTo(other) < 0;

  bool isAfter(LocalDate other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => '$year-${_pad(month)}-${_pad(day)}';

  static String _pad(int value) => value.toString().padLeft(2, '0');
}

/// Whole calendar days from [from] to [to]. Negative when [to] precedes [from].
int daysBetween(LocalDate from, LocalDate to) {
  // UTC anchors: a local DateTime difference would be off by an hour across a
  // daylight-saving boundary, which is exactly the bug this file exists for.
  final start = DateTime.utc(from.year, from.month, from.day);
  final end = DateTime.utc(to.year, to.month, to.day);
  return end.difference(start).inDays;
}

/// Fractional days elapsed between two instants, measured on the local wall
/// clock. A DST shift moves the clock, not the elapsed day count.
double elapsedLocalDays(DateTime from, DateTime to) {
  final start = from.isUtc ? from.toLocal() : from;
  final end = to.isUtc ? to.toLocal() : to;
  final wholeDays = daysBetween(LocalDate.from(start), LocalDate.from(end));
  return wholeDays + (_dayFraction(end) - _dayFraction(start));
}

/// Every local date from [from] to [to], inclusive at both ends.
List<LocalDate> localDatesInRange(LocalDate from, LocalDate to) {
  final span = daysBetween(from, to);
  if (span < 0) return const <LocalDate>[];
  return List<LocalDate>.generate(span + 1, (index) => from.addDays(index));
}

double _dayFraction(DateTime local) {
  const secondsPerDay = 86400;
  final seconds = local.hour * 3600 + local.minute * 60 + local.second;
  return (seconds + local.millisecond / 1000) / secondsPerDay;
}
