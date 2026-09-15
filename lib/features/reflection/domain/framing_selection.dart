import 'package:taproot/core/engine/constants.dart';
import 'package:taproot/core/engine/domain.dart';

/// Which question to ask (reflection-logic §3).
///
/// Selection is driven by **occasion type × habit state**, not stage alone.
/// The design spec named three framings; practice needs a fourth —
/// [Framing.confirmation], the one-tap degenerate case of Discovery for habits
/// whose cue has already converged, without which late-stage reflection is
/// either annoying or abandoned. [Framing.autonomy] is the fifth, and it
/// outranks every stage rule below: a completion nobody asked for is the
/// richest occasion the app ever gets, and asking about it as though it were
/// ordinary throws that away.
Framing framingFor({
  required Occasion occasion,
  required Stage stage,
  required double convergence,
}) => switch (occasion) {
  // "You did this without us asking. What reminded you?" — at any stage.
  Occasion.autonomyCompletion => Framing.autonomy,

  // "No run yesterday — what got in the way?" State the fact neutrally, ask
  // with curiosity. Never "you missed your run": the app is a collaborator
  // investigating a system, not a supervisor noting an absence.
  Occasion.miss => Framing.diagnosis,

  Occasion.completion =>
    stage.isBelow(Stage.young)
        // "Did [designed cue] kick it off?" — the cue is still being tested.
        ? Framing.validation
        : convergence < EngineConstants.confirmationConvergenceThreshold
        // "What got you going today?" — the cue has not settled.
        ? Framing.discovery
        // "Same as usual — after breakfast?" One tap.
        : Framing.confirmation,
};
