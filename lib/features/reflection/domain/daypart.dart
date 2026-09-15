/// The six daypart buckets the chip library ranks against
/// (starter-chip-library.md §4).
///
/// Keyed off the **completion timestamp**, never the check-in time. The evening
/// check-in asking about a 07:00 run has to rank against 07:00, or every
/// morning habit gets evening chips.
library;

import 'package:taproot/core/engine/constants.dart';

enum Daypart {
  early,
  morning,
  midday,
  afternoon,
  evening,
  night;

  /// Whether [other] sits next to this bucket on the line.
  ///
  /// **Adjacency is linear and does not wrap.** `night` neighbours `evening`
  /// only. The wrap is tempting — 02:00 and 05:00 really are neighbours — but
  /// `night` spans six and a half hours and most logs in it are closer to 22:00
  /// than to 03:00, so wrapping mostly leaked `with morning coffee` into 21:50
  /// sets. The oversized night bucket is the underlying problem and is an open
  /// question in §9, not something adjacency should paper over.
  bool isAdjacentTo(Daypart other) => (index - other.index).abs() == 1;
}

/// The bucket [at] falls in, by **local** clock time.
///
/// Local, like every other window in the app: a completion's daypart is a fact
/// about the user's day, and reading it in UTC would rank a 19:00 log as
/// morning for half the world.
Daypart daypartFor(DateTime at) {
  final local = at.toLocal();
  final minutes = local.hour * 60 + local.minute;

  // Written as ascending bounds rather than ranges so the night bucket's wrap
  // past midnight is handled once, at the top, instead of in every comparison.
  if (minutes < _minutes(4, 0)) return Daypart.night;
  if (minutes < _minutes(8, 0)) return Daypart.early;
  if (minutes < _minutes(11, 0)) return Daypart.morning;
  if (minutes < _minutes(14, 0)) return Daypart.midday;
  if (minutes < _minutes(18, 0)) return Daypart.afternoon;
  if (minutes < _minutes(21, 30)) return Daypart.evening;
  return Daypart.night;
}

int _minutes(int hour, int minute) => hour * 60 + minute;

/// How much of a chip's prior survives, given where it was logged
/// (starter-chip-library.md §5.1).
///
/// **Multiplicative, and that is the load-bearing choice.** An additive penalty
/// lets a high-prior chip survive anywhere — `after lunch` in the walking
/// category (prior 0.65) would still rank second in an 18:30 set, because a
/// large prior outruns any fixed penalty. Multiplying zeroes the prior on a
/// mismatch, leaving `score = type_bonus`, at most 0.30 — below the score floor
/// by construction. Mismatched chips therefore self-eliminate without a special
/// rule, and the floor does the filtering.
double daypartFactor({
  required Daypart logged,
  required Set<Daypart> chipDayparts,
}) {
  // `any` is modelled as an empty set rather than a sentinel member: a chip is
  // either pinned to particular buckets or it is daypart-neutral.
  if (chipDayparts.isEmpty) return EngineConstants.daypartFactorNeutral;
  if (chipDayparts.contains(logged)) return EngineConstants.daypartFactorMatch;
  if (chipDayparts.any(logged.isAdjacentTo)) {
    return EngineConstants.daypartFactorAdjacent;
  }
  return 0;
}
