import 'package:meta/meta.dart';

import 'package:taproot/core/engine/adherence.dart';
import 'package:taproot/core/engine/autonomy.dart';
import 'package:taproot/core/engine/constants.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/engine/inputs.dart';
import 'package:taproot/core/engine/pauses.dart';
import 'package:taproot/core/engine/roots.dart';
import 'package:taproot/core/utils/local_dates.dart';

/// Stage advancement (growth spec §3).
///
/// Advancement is gated on adherence, tapering 0.50 → 0.80: early on you may
/// miss half your intended runs and still grow; at the top you're held to four
/// in five. Roots hard-gate Bloom only — below the advisory ρ the plant
/// advances but renders tall and shallow-rooted, because the metaphor already
/// carries that message and the gate was redundant force.
///
/// **A qualifying window may not begin before the previous stage was earned**
/// (Young upward). This is what makes the ladder sequential rather than
/// concurrent, and it is where the spec's "fastest possible path to bloom
/// ≈ 96 days" comes from: 19 + 28 + 42 days of *successive* windows. Without
/// it the same completion history satisfies every window at once and a habit
/// blooms in six weeks.
@immutable
class StageProgress {
  const StageProgress({required this.stage, required this.earnedAt});

  /// The highest stage earned at or before the evaluation instant. Monotonic
  /// by construction.
  final Stage stage;

  /// When each stage was first earned. Replayed from history rather than
  /// stored, so tuning a constant can't leave a stale stage behind.
  final Map<Stage, DateTime> earnedAt;

  DateTime? earnedAtFor(Stage stage) => earnedAt[stage];
}

/// Whether [stage]'s own gate passes at [at].
///
/// [notBefore] enforces the sequential-window rule: the qualifying window may
/// not reach back past the instant the previous stage was earned.
bool passesGate({
  required HabitInputs inputs,
  required Stage stage,
  required DateTime at,
  DateTime? notBefore,
}) {
  final gate = EngineConstants.stageGates[stage];
  // Seed is the base of the ladder: designing the habit is the whole gate.
  if (gate == null) return stage == Stage.seed;

  var completions = 0;
  for (final completion in inputs.completions) {
    if (!completion.completedAt.isAfter(at)) completions++;
  }
  if (completions < gate.minimumCompletions) return false;
  if (gate.windowReps <= 0) return true;

  final window = computeAdherence(
    inputs: inputs,
    windowReps: gate.windowReps,
    at: at,
  );
  if (notBefore != null &&
      window.windowStart.isBefore(LocalDate.from(notBefore))) {
    return false;
  }
  if (window.adherence < gate.adherenceThreshold) return false;

  // Clamp collapse: when the ceiling binds, adjacent thresholds round to the
  // same integer, so the top rung tightens with time instead.
  if (gate.requiresTwoWindowsWhenClamped && window.ceilingBinds) {
    final previous = computeAdherence(
      inputs: inputs,
      windowReps: gate.windowReps,
      at: activeDaysBefore(
        at: at,
        activeDays: window.windowDays,
        pauses: inputs.pauses,
      ),
    );
    if (previous.adherence < gate.adherenceThreshold) return false;
  }

  final rootsThreshold = gate.rootsThreshold;
  if (rootsThreshold != null && !gate.rootsAdvisory) {
    if (computeRoots(inputs: inputs, at: at).depth < rootsThreshold) {
      return false;
    }
  }

  final autonomyThreshold = gate.autonomyThreshold;
  if (autonomyThreshold != null) {
    final autonomy = computeAutonomy(inputs: inputs, at: at);
    // No evidence is not a pass: autonomy has to be demonstrated.
    if (!autonomy.hasEvidence || autonomy.value < autonomyThreshold) {
      return false;
    }
  }

  return true;
}

/// Replays the ladder over history and reports where the habit stands.
StageProgress computeStageProgress({
  required HabitInputs inputs,
  required DateTime at,
}) {
  final earnedAt = <Stage, DateTime>{Stage.seed: inputs.createdAt};
  final candidates = _candidateInstants(inputs, at);
  var current = Stage.seed;

  for (final stage in Stage.values.skip(1)) {
    final previousEarnedAt = earnedAt[Stage.values[stage.index - 1]];
    if (previousEarnedAt == null) break;

    // Only Young and above must wait out a full window: Seedling is reached
    // as soon as three completions land inside its own.
    final notBefore = stage.index >= Stage.young.index
        ? previousEarnedAt
        : null;

    DateTime? earned;
    for (final candidate in candidates) {
      if (candidate.isBefore(previousEarnedAt)) continue;
      if (passesGate(
        inputs: inputs,
        stage: stage,
        at: candidate,
        notBefore: notBefore,
      )) {
        earned = candidate;
        break;
      }
    }
    if (earned == null) break;

    earnedAt[stage] = earned;
    current = stage;
  }

  return StageProgress(stage: current, earnedAt: earnedAt);
}

/// The stage as displayed: the highest ever earned at or before [at].
Stage computeStage({required HabitInputs inputs, required DateTime at}) =>
    computeStageProgress(inputs: inputs, at: at).stage;

/// Whether the plant renders top-heavy — at this stage in behaviour, below its
/// advisory root threshold in understanding.
bool isShallowRooted({required Stage stage, required double roots}) {
  final gate = EngineConstants.stageGates[stage];
  final threshold = gate?.rootsThreshold;
  if (gate == null || threshold == null || !gate.rootsAdvisory) return false;
  return roots < threshold;
}

/// One instant per local day the habit has existed for, plus [at] itself.
///
/// Day granularity is enough: every gate is a day-scale quantity, and the
/// alternative — replaying every event instant plus every window offset — buys
/// nothing a user could see.
List<DateTime> _candidateInstants(HabitInputs inputs, DateTime at) {
  final instants = <DateTime>[inputs.createdAt];
  final local = at.isUtc ? at.toLocal() : at;
  final span = daysBetween(
    LocalDate.from(inputs.createdAt),
    LocalDate.from(local),
  );

  for (var offset = 0; offset <= span; offset++) {
    final date = LocalDate.from(inputs.createdAt).addDays(offset);
    final candidate = DateTime(
      date.year,
      date.month,
      date.day,
      local.hour,
      local.minute,
      local.second,
      local.millisecond,
    );
    if (candidate.isAfter(inputs.createdAt) && !candidate.isAfter(at)) {
      instants.add(candidate);
    }
  }
  if (instants.last != at) instants.add(at);
  return instants;
}
