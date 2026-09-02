import 'dart:math' as math;

import 'package:taproot/core/engine/constants.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/engine/pauses.dart';
import 'package:taproot/core/engine/inputs.dart';
import 'package:taproot/core/models/completion.dart';
import 'package:taproot/core/utils/local_dates.dart';

/// Vitality — droop without punishment (growth spec §4).
///
/// Stage never falls; vitality is the layer that visibly reacts.
///
///   o = days_since_last_completion − G
///   V = 1 − clamp((o − g) / D, 0, 1)
///
/// V snaps to 1.0 on completion. Always. That's the watering payoff.

/// g — grace days before the plant visibly reacts.
double graceDaysForStage(Stage stage) =>
    EngineConstants.droopProfiles[stage]!.graceDays;

/// D — days from droop onset to full wilt.
double droopDaysForStage(Stage stage) =>
    EngineConstants.droopProfiles[stage]!.droopDays;

/// ceil(0.8 x f) — the pace exemption bar. At f = 7 this is 6, so a daily
/// habit stays healthy at 6 of 7 and only droops on a second miss. At f = 3 it
/// is still 3, so Mon/Tue/Wed-then-rest is unchanged.
int paceExemptionThreshold(int targetFrequency) {
  final bar = EngineConstants.paceExemptionFactor * targetFrequency;
  // 0.8 has no exact binary form, so 0.8 x 5 lands a hair above 4 and would
  // otherwise round up to 5.
  return (bar - _floatingPointSlack).ceil();
}

/// C7 — completions in the last 7 active days.
int completionsLastSevenDays({
  required HabitInputs inputs,
  required DateTime at,
}) {
  final window = activeWindowDates(
    at: at,
    windowDays: EngineConstants.paceWindowDays,
    pauses: inputs.pauses,
  ).toSet();

  var completions = 0;
  for (final completion in inputs.completions) {
    if (completion.completedAt.isAfter(at)) continue;
    if (window.contains(LocalDate.from(completion.completedAt))) completions++;
  }
  return completions;
}

/// Active days since the last completion, or null if there is none.
double? daysSinceLastCompletion({
  required HabitInputs inputs,
  required DateTime at,
}) {
  final last = _lastCompletionAt(inputs, at);
  if (last == null) return null;
  return activeElapsedDays(from: last, to: at, pauses: inputs.pauses);
}

/// Vitality before the renegotiation wilt freeze is applied.
///
/// The freeze is deliberately kept out of this function: the wilt-duration
/// renegotiation trigger is computed against the *raw* curve, and reading a
/// frozen value there would make the trigger erase its own evidence.
double rawVitality({
  required HabitInputs inputs,
  required Stage stage,
  required DateTime at,
}) {
  if (completionsLastSevenDays(inputs: inputs, at: at) >=
      paceExemptionThreshold(inputs.targetFrequency)) {
    return 1.0;
  }

  // A habit that has never been watered is measured from its creation, so a
  // designed-but-abandoned seed wilts on the same schedule as any other plant.
  final elapsed =
      daysSinceLastCompletion(inputs: inputs, at: at) ??
      activeElapsedDays(from: inputs.createdAt, to: at, pauses: inputs.pauses);

  final overdue = elapsed - inputs.expectedGapDays;
  final wilt = ((overdue - graceDaysForStage(stage)) / droopDaysForStage(stage))
      .clamp(0.0, 1.0);
  return 1.0 - wilt;
}

/// Vitality as displayed, with the wilt freeze applied while the habit is a
/// renegotiation candidate.
double computeVitality({
  required HabitInputs inputs,
  required Stage stage,
  required DateTime at,
  bool isRenegotiationCandidate = false,
}) {
  final vitality = rawVitality(inputs: inputs, stage: stage, at: at);
  if (!isRenegotiationCandidate) return vitality;
  return math.max(vitality, EngineConstants.wiltFreezeFloor);
}

const double _floatingPointSlack = 1e-9;

DateTime? _lastCompletionAt(HabitInputs inputs, DateTime at) {
  DateTime? last;
  for (final Completion completion in inputs.completions) {
    if (completion.completedAt.isAfter(at)) continue;
    if (last == null || completion.completedAt.isAfter(last)) {
      last = completion.completedAt;
    }
  }
  return last;
}
