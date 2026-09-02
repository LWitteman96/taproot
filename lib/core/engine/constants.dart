import 'package:meta/meta.dart';

import 'package:taproot/core/engine/domain.dart';

/// Adherence gate for one rung of the ladder (growth spec §3).
@immutable
class StageGate {
  const StageGate({
    required this.windowReps,
    required this.adherenceThreshold,
    this.rootsThreshold,
    this.rootsAdvisory = true,
    this.minimumCompletions = 0,
    this.autonomyThreshold,
    this.requiresTwoWindowsWhenClamped = false,
  });

  /// W_reps — the window measured in expected repetitions.
  final int windowReps;

  /// θ — the adherence the window must clear.
  final double adherenceThreshold;

  /// ρ — the root depth. Advisory below Bloom: the plant advances anyway but
  /// renders tall and shallow-rooted, and the awareness-gap insight fires.
  final double? rootsThreshold;

  /// False only at Bloom, where roots are a hard gate.
  final bool rootsAdvisory;

  /// Cumulative completions required regardless of the window, from the
  /// "Requirement to reach it" column (first completion, 3 completions).
  final int minimumCompletions;

  /// Autonomy floor. Bloom only — a habit that fires only when prompted
  /// cannot bloom (growth spec §6).
  final double? autonomyThreshold;

  /// When the 42-day ceiling binds, adjacent thresholds round to the same
  /// integer and the taper disappears, so Bloom tightens with *time* instead:
  /// two consecutive passing windows (growth spec §3, clamp collapse).
  final bool requiresTwoWindowsWhenClamped;
}

/// Grace and droop for one stage (growth spec §4).
@immutable
class DroopProfile {
  const DroopProfile({required this.graceDays, required this.droopDays});

  /// g — overdue days tolerated before the plant visibly reacts.
  final double graceDays;

  /// D — days from droop onset to full wilt.
  final double droopDays;
}

/// Every tunable number in the engine, in one place, with a version stamp.
///
/// The specs call these "calibrated defaults, meant to be tuned against real
/// data, not laws". Tuning one must never require a data migration — which is
/// why derived values (stage, vitality, roots, autonomy) are computed rather
/// than stored, or cached against [version].
abstract final class EngineConstants {
  /// Bump on any change below. Cached derivations keyed by an older version
  /// are invalid and must be recomputed, never migrated.
  static const int version = 1;

  // ── Inputs ────────────────────────────────────────────────────────────────

  /// f is a weekly frequency and the specs' range tops out at daily — §4
  /// reasons explicitly about "a perfect 7-of-7 at f=7" as the extreme. Twice
  /// daily would be a v2 shape, not a larger f.
  static const int minimumTargetFrequency = 1;
  static const int maximumTargetFrequency = 7;

  // ── Adherence windows (growth spec §2) ────────────────────────────────────

  /// W_days = clamp(W_reps × 7 / f, 14, 42).
  static const int minimumWindowDays = 14;
  static const int maximumWindowDays = 42;

  // ── The ladder (growth spec §3) ───────────────────────────────────────────

  static const Map<Stage, StageGate> stageGates = <Stage, StageGate>{
    Stage.sprout: StageGate(
      windowReps: 0,
      adherenceThreshold: 0,
      minimumCompletions: 1,
    ),
    Stage.seedling: StageGate(
      windowReps: 3,
      adherenceThreshold: 0.50,
      minimumCompletions: 3,
    ),
    Stage.young: StageGate(
      windowReps: 8,
      adherenceThreshold: 0.60,
      rootsThreshold: 0.30,
    ),
    Stage.mature: StageGate(
      windowReps: 12,
      adherenceThreshold: 0.75,
      rootsThreshold: 0.50,
    ),
    Stage.bloom: StageGate(
      windowReps: 20,
      adherenceThreshold: 0.80,
      rootsThreshold: 0.75,
      rootsAdvisory: false,
      autonomyThreshold: 0.50,
      requiresTwoWindowsWhenClamped: true,
    ),
  };

  // ── Vitality (growth spec §4) ─────────────────────────────────────────────

  static const Map<Stage, DroopProfile> droopProfiles = <Stage, DroopProfile>{
    Stage.seed: DroopProfile(graceDays: 0, droopDays: 2),
    Stage.sprout: DroopProfile(graceDays: 0, droopDays: 2),
    Stage.seedling: DroopProfile(graceDays: 0.5, droopDays: 3),
    Stage.young: DroopProfile(graceDays: 1.5, droopDays: 6),
    Stage.mature: DroopProfile(graceDays: 3, droopDays: 12),
    Stage.bloom: DroopProfile(graceDays: 5, droopDays: 20),
  };

  /// The pace exemption: C₇ ≥ ⌈0.8 × f⌉ ⇒ vitality 1.0 regardless of gap.
  /// The 0.8 is what keeps daily habits protected — a strict C₇ ≥ f would
  /// demand a perfect 7 of 7 at f = 7.
  static const double paceExemptionFactor = 0.8;

  /// Rolling window for C₇, in active local days.
  static const int paceWindowDays = 7;

  /// Vitality floor while a habit is a renegotiation candidate — the wilt
  /// freeze (growth spec §4). Once the app suspects the *target* is wrong,
  /// further wilting punishes the user for the app's bad assumption.
  ///
  /// OPEN: the spec says vitality "floors at droop-onset", and the value at
  /// droop onset is exactly 1.0 — so the literal reading is that the plant
  /// stops looking unwell entirely. The alternative reading (hold at whatever
  /// vitality was when candidacy began) is a different shape. Implemented
  /// literally, isolated here so it is one number to change.
  static const double wiltFreezeFloor = 1.0;

  // ── Roots (growth spec §5, reflection spec §3) ────────────────────────────

  /// The 4 in R_raw = N / (N + 4). 4 → 0.50, 10 → 0.71, 20 → 0.83.
  static const double rootsSaturationConstant = 4;

  /// Root credit by framing, for a substantive answer.
  static const Map<Framing, double> rootCreditByFraming = <Framing, double>{
    Framing.autonomy: 1.5,
    Framing.validation: 1.0,
    Framing.discovery: 1.0,
    Framing.diagnosis: 1.0,
    Framing.confirmation: 0.5,
  };

  /// An honest non-answer is real evidence of autopilot, but it builds no cue
  /// understanding — it must never be worth what an actual answer is worth.
  static const double cantRememberCredit = 0.25;
  static const double skippedCredit = 0;

  /// c is the modal cue share over the last 8 cue-bearing reflections.
  static const int convergenceWindow = 8;

  /// Below this many cue-bearing reflections in the window, c = 0. Absence of
  /// evidence is not convergence: a naive modal share of an empty set returns
  /// 1.0 and would inflate roots for the *least* self-aware user.
  static const int minimumCueBearingReflections = 3;

  /// R = R_raw × (0.5 + 0.5c). A scattered cue history halves root depth.
  static const double convergenceFloorWeight = 0.5;

  // ── Autonomy and nudge fading (growth spec §6) ────────────────────────────

  /// Autonomy is measured over the last 10 un-nudged expected occasions.
  static const int autonomySampleSize = 10;

  /// Share of expected occasions that get a nudge, by stage. Fading is
  /// load-bearing: the skipped nudges are how autonomy is measured at all.
  static const Map<Stage, double> nudgeRateByStage = <Stage, double>{
    Stage.seed: 1.0,
    Stage.sprout: 1.0,
    Stage.seedling: 1.0,
    Stage.young: 0.70,
    Stage.mature: 0.40,
    Stage.bloom: 0.10,
  };

  // ── Graduation (growth spec §6, reflection spec §7) ───────────────────────

  static const double graduationConvergence = 0.80;
  static const double graduationAutonomy = 0.60;

  // ── Renegotiation (growth spec §7) ────────────────────────────────────────

  /// Adherence below this across two consecutive windows makes the habit a
  /// renegotiation candidate.
  static const double renegotiationAdherence = 0.40;

  /// …or a plant fully wilted this many consecutive days. This second trigger
  /// exists because the first is far too slow: the over-ambitious starter is
  /// offered help on day 28, and he churns around day 10.
  static const int renegotiationWiltDays = 7;

  // ── Reflection prompting (reflection spec §2) ─────────────────────────────
  //
  // Owned by the reflection feature rather than the engine, but every tunable
  // lives in one file.

  static const double reflectionPriorityThreshold = 0.5;
  static const double reflectionEarlyBonus = 0.4;
  static const int reflectionEarlyBonusUntil = 5;
  static const double reflectionMissWeight = 0.5;
  static const double reflectionUnNudgedCompletionWeight = 0.6;
  static const double reflectionAnomalyWeight = 0.3;
  static const double reflectionRecencyPenalty = 0.5;
  static const Duration reflectionRecencyWindow = Duration(hours: 48);
  static const Duration reflectionCooldown = Duration(hours: 24);

  /// Max check-ins per week, fading by stage.
  static const Map<Stage, int> weeklyReflectionBudget = <Stage, int>{
    Stage.seed: 3,
    Stage.sprout: 3,
    Stage.seedling: 3,
    Stage.young: 3,
    Stage.mature: 2,
    Stage.bloom: 1,
  };

  /// Confirmation framing takes over from Discovery above this convergence.
  static const double confirmationConvergenceThreshold = 0.6;
}
