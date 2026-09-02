import 'package:meta/meta.dart';

import 'package:taproot/core/engine/adherence.dart';
import 'package:taproot/core/engine/autonomy.dart';
import 'package:taproot/core/engine/constants.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/engine/ladder.dart';
import 'package:taproot/core/engine/inputs.dart';
import 'package:taproot/core/engine/renegotiation.dart';
import 'package:taproot/core/engine/vitality.dart';
import 'package:taproot/core/engine/roots.dart';

/// Everything the engine derives for one habit at one instant.
///
/// None of this is stored. If it is cached, it is cached against
/// [constantsVersion] — tuning a θ must never require a data migration.
@immutable
class HabitGrowth {
  const HabitGrowth({
    required this.stage,
    required this.vitality,
    required this.roots,
    required this.autonomy,
    required this.currentWindow,
    required this.isShallowRooted,
    required this.renegotiationTrigger,
    required this.isGraduated,
    required this.constantsVersion,
  });

  final Stage stage;
  final double vitality;
  final RootDepth roots;
  final AutonomyResult autonomy;

  /// The window for the gate the habit is currently working toward.
  final AdherenceWindow currentWindow;

  /// Tall and shallow-rooted: the visual that says "something is missing here"
  /// without confiscating anything.
  final bool isShallowRooted;

  final RenegotiationTrigger? renegotiationTrigger;

  final bool isGraduated;

  final int constantsVersion;

  bool get isRenegotiationCandidate => renegotiationTrigger != null;
}

HabitGrowth evaluateGrowth({
  required HabitInputs inputs,
  required DateTime at,
}) {
  final stage = computeStageProgress(inputs: inputs, at: at).stage;
  final roots = computeRoots(inputs: inputs, at: at);
  final autonomy = computeAutonomy(inputs: inputs, at: at);
  final trigger = renegotiationTrigger(inputs: inputs, stage: stage, at: at);

  return HabitGrowth(
    stage: stage,
    vitality: computeVitality(
      inputs: inputs,
      stage: stage,
      at: at,
      isRenegotiationCandidate: trigger != null,
    ),
    roots: roots,
    autonomy: autonomy,
    currentWindow: computeAdherence(
      inputs: inputs,
      windowReps: gateInProgress(stage).windowReps,
      at: at,
    ),
    isShallowRooted: isShallowRooted(stage: stage, roots: roots.depth),
    renegotiationTrigger: trigger,
    isGraduated: isGraduated(
      stage: stage,
      convergence: roots.convergence,
      autonomy: autonomy.value,
    ),
    constantsVersion: EngineConstants.version,
  );
}
