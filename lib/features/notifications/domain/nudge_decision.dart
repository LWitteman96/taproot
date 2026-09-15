import 'package:meta/meta.dart';

/// Why an occasion carries no notification.
///
/// Only [withheld] is the engine measuring something. The rest are the app
/// failing to nudge for reasons that have nothing to do with the habit, and
/// they are named separately because conflating them is how a measurement
/// instrument turns into a rounding error.
enum NudgeSuppression {
  /// The engine chose silence at this stage's fade rate. This is autonomy's
  /// denominator and the whole point of the mechanism (growth spec §6).
  withheld,

  /// Its evening slot is already in the past — the phone was off, or the app
  /// had not been opened since before the occasion.
  deliveryPassed,

  /// The user has not granted notification permission. A designed app mode,
  /// not an error (guide §2).
  noPermission,

  /// The platform pending-notification ceiling was reached.
  overCap,
}

/// What the scheduler decided about one expected occasion.
@immutable
class NudgeDecision {
  const NudgeDecision.send() : suppression = null;

  const NudgeDecision.suppress(NudgeSuppression reason) : suppression = reason;

  final NudgeSuppression? suppression;

  bool get shouldSend => suppression == null;

  /// Whether this decision leaves an occasion in autonomy's denominator *by
  /// design*, as opposed to by accident.
  bool get isDeliberateSilence => suppression == NudgeSuppression.withheld;

  @override
  String toString() =>
      shouldSend ? 'NudgeDecision.send' : 'NudgeDecision.${suppression!.name}';
}

/// Whether the next occasion should carry a nudge, at a fade rate of
/// [nudgeRate] (growth spec §6).
///
/// Send unless the share already sent has caught up with the rate:
///
/// ```
/// send  ⇔  priorSent < nudgeRate × (priorOccasions + 1)
/// ```
///
/// Three properties, all of which a coin flip at `p = nudgeRate` fails:
///
/// - **Exact in the long run.** At 0.70 the pattern is send·send·send·skip,
///   send·send·skip, send·send·skip — 7 of every 10, not 7 on average.
/// - **Deterministic.** Two devices replaying the same ledger make the same
///   decisions, which matters because the ledger is the measurement and it
///   syncs.
/// - **Front-loaded, and self-correcting when the rate changes.** A habit that
///   has just climbed to Mature carries a sent-share from Young; the rule
///   simply withholds until the share falls to 0.40, rather than restarting a
///   counter and nudging through the transition.
///
/// It also never opens a silent run longer than the rate implies — a random
/// draw at Bloom's 0.10 can trivially go 30 occasions without a spot check.
bool shouldSendNudge({
  required double nudgeRate,
  required int priorOccasions,
  required int priorSent,
}) => priorSent < nudgeRate * (priorOccasions + 1);
