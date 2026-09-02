import 'package:meta/meta.dart';

import 'package:taproot/core/engine/constants.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/engine/inputs.dart';
import 'package:taproot/core/utils/local_dates.dart';

/// Autonomy — does the habit fire without the app? (growth spec §6)
///
/// Completions on un-nudged expected occasions, over the last 10 such
/// occasions. The skipped nudges are the measurement instrument: you cannot
/// know whether the habit stands on its own until you stop holding it up.
@immutable
class AutonomyResult {
  const AutonomyResult({
    required this.value,
    required this.occasions,
    required this.completed,
  });

  /// completed / occasions, or 0 when nothing has been measured yet — an
  /// unmeasured habit has not demonstrated autonomy.
  final double value;

  /// Un-nudged expected occasions in the sample. Insight rules key off this:
  /// nudge dependence needs at least 6.
  final int occasions;

  final int completed;

  bool get hasEvidence => occasions > 0;

  @override
  String toString() => 'AutonomyResult($completed/$occasions = $value)';
}

AutonomyResult computeAutonomy({
  required HabitInputs inputs,
  required DateTime at,
}) {
  final unNudged = inputs.nudgesUpTo(at).where((nudge) => !nudge.sent).toList();
  final sample = unNudged.length <= EngineConstants.autonomySampleSize
      ? unNudged
      : unNudged.sublist(unNudged.length - EngineConstants.autonomySampleSize);

  final completedDates = <LocalDate>{};
  for (final completion in inputs.completions) {
    if (completion.completedAt.isAfter(at)) continue;
    completedDates.add(LocalDate.from(completion.completedAt));
  }

  final completed = sample
      .where(
        (nudge) =>
            completedDates.contains(LocalDate.from(nudge.expectedOccasionAt)),
      )
      .length;

  return AutonomyResult(
    value: sample.isEmpty ? 0 : completed / sample.length,
    occasions: sample.length,
    completed: completed,
  );
}

/// Share of expected occasions that should be nudged at this stage. Fading is
/// what makes autonomy measurable — and what stops the notification becoming
/// the cue.
double nudgeRateForStage(Stage stage) =>
    EngineConstants.nudgeRateByStage[stage]!;

/// Whether the first un-nudged completion has happened — the app's whole
/// thesis landing, and an explicit milestone.
bool hasUnNudgedCompletion({
  required HabitInputs inputs,
  required DateTime at,
}) => computeAutonomy(inputs: inputs, at: at).completed > 0;

/// Graduation: Bloom, c >= 0.8, autonomy >= 0.6. "This one seems locked in —
/// we'll stop asking."
bool isGraduated({
  required Stage stage,
  required double convergence,
  required double autonomy,
}) =>
    stage == Stage.bloom &&
    convergence >= EngineConstants.graduationConvergence &&
    autonomy >= EngineConstants.graduationAutonomy;
