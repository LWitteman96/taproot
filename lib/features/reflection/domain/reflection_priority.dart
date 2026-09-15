import 'package:meta/meta.dart';

import 'package:taproot/core/engine/constants.dart';
import 'package:taproot/core/engine/domain.dart';

/// One occasion worth scoring — a completion, a missed expected occasion, or a
/// completion on an occasion the app deliberately stayed silent on.
@immutable
class CheckInOccasion {
  const CheckInOccasion({
    required this.habitId,
    required this.occasion,
    required this.at,
    this.isAnomalous = false,
    this.wasNudged = false,
  });

  final String habitId;
  final Occasion occasion;

  /// When it happened: the completion's timestamp, or the expected occasion's
  /// for a miss. **Not** the check-in time — the daypart the chips rank
  /// against comes from here, or every morning habit gets evening chips.
  final DateTime at;

  /// Whether this occasion is out of the ordinary for the habit — see
  /// `isAnomalousOccasion`.
  final bool isAnomalous;

  /// Whether the app nudged this occasion.
  ///
  /// Recorded onto the reflection rather than used here. Nothing in the engine
  /// reads `Reflection.wasNudged` today — it is kept faithful because the
  /// question it answers later ("do people reflect differently when we asked
  /// them to?") cannot be reconstructed from anything else once the row is
  /// written.
  final bool wasNudged;
}

/// `Priority = uncertainty + early_bonus + occasion_weight + anomaly −
/// recency_penalty` (reflection-logic §2).
///
/// [reflectionCount] is the **raw** number of reflections recorded for the
/// habit, not roots' weighted N. The early bonus exists because "no prior means
/// everything teaches", which is a statement about how many times the user has
/// been asked, not about how much those answers were worth.
double reflectionPriority({
  required CheckInOccasion occasion,
  required double convergence,
  required int reflectionCount,
  required DateTime? lastPromptedAt,
  required DateTime now,
}) {
  // An unknown cue is the highest-information thing the app can ask about.
  final uncertainty = 1 - convergence;

  final earlyBonus = earlyReflectionBonus(reflectionCount);

  // Misses and autonomy events are the richest data; an ordinary completion
  // adds nothing on its own.
  final occasionWeight = switch (occasion.occasion) {
    Occasion.miss => EngineConstants.reflectionMissWeight,
    Occasion.autonomyCompletion =>
      EngineConstants.reflectionUnNudgedCompletionWeight,
    Occasion.completion => 0.0,
  };

  final anomaly = occasion.isAnomalous
      ? EngineConstants.reflectionAnomalyWeight
      : 0.0;

  // Protects the ritual. Asking twice in two days is how a check-in stops
  // feeling like a conversation and starts feeling like a form.
  final recencyPenalty =
      lastPromptedAt != null &&
          now.difference(lastPromptedAt) <
              EngineConstants.reflectionRecencyWindow
      ? EngineConstants.reflectionRecencyPenalty
      : 0.0;

  return uncertainty + earlyBonus + occasionWeight + anomaly - recencyPenalty;
}

/// The early bonus, decaying to nothing by the fifth reflection.
///
/// **A reconciliation.** §2 gives this as "`+0.4` while n < 5, decaying",
/// which names two different shapes: a flat bonus that switches off at 5, and
/// one that tapers. Implemented as a linear taper from 0.4 at n = 0 to 0 at
/// n = 5, because it satisfies both halves of the sentence — nonzero only below
/// 5, and decaying throughout — where a flat step satisfies only the first.
///
/// It also avoids a cliff the flat reading creates: a habit sitting just above
/// threshold on its fourth reflection would drop 0.4 in one step and go silent
/// exactly when the user has started answering.
double earlyReflectionBonus(int reflectionCount) {
  if (reflectionCount >= EngineConstants.reflectionEarlyBonusUntil) return 0;
  final remaining = EngineConstants.reflectionEarlyBonusUntil - reflectionCount;
  return EngineConstants.reflectionEarlyBonus *
      remaining /
      EngineConstants.reflectionEarlyBonusUntil;
}

/// Whether an occasion is unusual enough to be worth the anomaly weight.
///
/// §2 names three causes — "unusual time, unusual gap, first completion after
/// droop". **The third is the second.** A droop *is* what a long gap produces,
/// so the completion that ends an unusually long gap and the first completion
/// after a droop are the same event described from two directions; implementing
/// them separately would double-count it.
///
/// Both thresholds here are guesses and belong in §8's list rather than being
/// presented as settled.
bool isAnomalousOccasion({
  required DateTime at,
  required List<DateTime> previousCompletions,
  required int targetFrequency,
}) {
  if (previousCompletions.isEmpty) return false;

  final sorted = List<DateTime>.from(previousCompletions)..sort();
  final previous = sorted.last;

  // An unusually long gap. The expected gap is 7/f days, so twice that is a
  // habit that has visibly slipped — which is also when it droops.
  final expectedGapDays = 7 / targetFrequency;
  final gapDays = at.difference(previous).inMinutes / (60 * 24);
  if (gapDays >= expectedGapDays * 2) return true;

  // An unusual time of day. Needs a mode to be unusual *against*, so it stays
  // silent until the habit has a shape — three completions is the same floor
  // convergence uses for the same reason.
  if (sorted.length >= EngineConstants.minimumCueBearingReflections) {
    final counts = <int, int>{};
    for (final completion in sorted) {
      final hour = completion.toLocal().hour;
      counts.update(hour ~/ 3, (count) => count + 1, ifAbsent: () => 1);
    }
    final modalBand = counts.entries
        .reduce((a, b) => b.value > a.value ? b : a)
        .key;
    if (at.toLocal().hour ~/ 3 != modalBand) return true;
  }

  return false;
}
