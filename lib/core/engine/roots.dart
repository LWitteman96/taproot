import 'package:meta/meta.dart';

import 'package:taproot/core/engine/constants.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/engine/inputs.dart';
import 'package:taproot/core/models/reflection.dart';

/// Root depth (growth spec §5).
///
/// Raw reflection count would reward grinding. Depth tracks how well the loop
/// is actually understood, which needs two components: diminishing-returns
/// volume, and convergence on a consistent cue.
@immutable
class RootDepth {
  const RootDepth({
    required this.weightedReflections,
    required this.raw,
    required this.convergence,
    required this.cueBearingReflections,
    required this.depth,
  });

  /// N — the weighted reflection count. Credit tracks information content.
  final double weightedReflections;

  /// R_raw = N / (N + 4).
  final double raw;

  /// c — modal cue share over the last 8 cue-bearing reflections.
  final double convergence;

  /// How many reflections in the convergence window carried a cue at all.
  /// Below 3, c is 0 rather than vacuously 1.
  final int cueBearingReflections;

  /// R = R_raw × (0.5 + 0.5c).
  final double depth;

  @override
  String toString() =>
      'RootDepth(N: $weightedReflections, raw: $raw, c: $convergence, R: $depth)';
}

/// Root credit for one reflection: framing x input mode (reflection spec §3).
///
/// Set by both, not framing alone — a Discovery answered "can't remember"
/// conveys no cue information and must not earn what an answer earns.
double rootCreditFor(Reflection reflection) => switch (reflection.inputMode) {
  InputMode.skipped => EngineConstants.skippedCredit,
  InputMode.cantRemember => EngineConstants.cantRememberCredit,
  InputMode.chip ||
  InputMode.typed => EngineConstants.rootCreditByFraming[reflection.framing]!,
};

/// Whether this reflection counts toward convergence. `cantRemember` and
/// skips are excluded from both numerator and denominator.
bool countsTowardConvergence(Reflection reflection) =>
    reflection.inputMode != InputMode.cantRemember &&
    reflection.inputMode != InputMode.skipped &&
    reflection.cueReported != null;

/// The key a reflection converges on: the type itself for internal states, the
/// exact cue label for everything else.
///
/// A habit genuinely anchored to an internal state ("when I feel stressed") is
/// not a badly-designed loop and shouldn't have its roots halved for varying
/// the label. That exemption is for `internal` alone — keying every
/// non-external type this way swept `unknown` in with it, and since `unknown`
/// is the default on a `Reflection`, eight genuinely different cues collapsed
/// onto one key and read as perfectly converged. Roots hard-gate Bloom, so
/// that inflated the least self-aware user straight through the top rung.
String convergenceKeyFor(Reflection reflection) =>
    reflection.cueType == CueType.internal
    ? 'type:${reflection.cueType.name}'
    : 'label:${reflection.cueReported?.trim().toLowerCase()}';

/// N — sum of credit over reflections at or before [at].
double weightedReflectionCount({
  required HabitInputs inputs,
  required DateTime at,
}) {
  var total = 0.0;
  for (final reflection in inputs.reflections) {
    if (reflection.createdAt.isAfter(at)) continue;
    total += rootCreditFor(reflection);
  }
  return total;
}

/// R_raw = N / (N + 4). Steep early, flat later.
double rawRootDepth(double weightedReflections) {
  if (weightedReflections <= 0) return 0;
  return weightedReflections /
      (weightedReflections + EngineConstants.rootsSaturationConstant);
}

/// c — modal share over the last 8 cue-bearing reflections, or 0 when fewer
/// than 3 exist.
double computeConvergence({
  required HabitInputs inputs,
  required DateTime at,
}) => _convergenceOver(_convergenceWindow(inputs, at));

/// Cue reliability — the designed cue's hit rate, as displayed by the
/// cue-testing phase ("your cue worked 6 of 8 times").
///
/// Null when no reflection has yet been scored against the designed cue.
double? cueReliability({required HabitInputs inputs, required DateTime at}) {
  final scored = inputs
      .reflectionsUpTo(at)
      .where((reflection) => reflection.matchedDesignedCue != null)
      .toList();
  if (scored.isEmpty) return null;
  final window = _lastOf(scored, EngineConstants.convergenceWindow);
  final matched = window
      .where((reflection) => reflection.matchedDesignedCue!)
      .length;
  return matched / window.length;
}

RootDepth computeRoots({required HabitInputs inputs, required DateTime at}) {
  final weighted = weightedReflectionCount(inputs: inputs, at: at);
  final raw = rawRootDepth(weighted);
  final cueBearing = _convergenceWindow(inputs, at);
  final convergence = _convergenceOver(cueBearing);

  return RootDepth(
    weightedReflections: weighted,
    raw: raw,
    convergence: convergence,
    cueBearingReflections: cueBearing.length,
    depth:
        raw *
        (EngineConstants.convergenceFloorWeight +
            (1 - EngineConstants.convergenceFloorWeight) * convergence),
  );
}

/// The cue-bearing reflections among the last 8 — not the last 8 cue-bearing
/// ones. The difference is what gives the "fewer than 3" rule its teeth: a
/// user whose recent check-ins are all `can't remember` has no modal cue, and
/// must not read as perfectly converged.
List<Reflection> _convergenceWindow(HabitInputs inputs, DateTime at) => _lastOf(
  inputs.reflectionsUpTo(at),
  EngineConstants.convergenceWindow,
).where(countsTowardConvergence).toList();

double _convergenceOver(List<Reflection> cueBearing) {
  if (cueBearing.length < EngineConstants.minimumCueBearingReflections) {
    // Absence of evidence is not convergence.
    return 0;
  }
  final counts = <String, int>{};
  for (final reflection in cueBearing) {
    counts.update(
      convergenceKeyFor(reflection),
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }
  final modal = counts.values.reduce((a, b) => a > b ? a : b);
  return modal / cueBearing.length;
}

List<T> _lastOf<T>(List<T> items, int count) =>
    items.length <= count ? items : items.sublist(items.length - count);
