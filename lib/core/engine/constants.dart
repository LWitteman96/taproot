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
  ///
  /// 2 — the notification scheduling block. It is not decoration: the occasion
  /// cadence decides *which* local dates are expected occasions, and those are
  /// the rows autonomy's denominator is counted over. Changing the cadence
  /// changes a derivation.
  static const int version = 2;

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

  // ── Starter chip surfacing (starter-chip-library.md §5) ───────────────────
  //
  // Same arrangement as the block above: owned by the reflection feature, kept
  // here because every tunable lives in one file.
  //
  // Adding these did **not** bump [version], deliberately. The version exists
  // so that a cached derivation computed under different numbers is discarded,
  // and nothing here feeds stage, vitality, roots or autonomy — these rank the
  // chips a first reflection offers. Bumping would invalidate every cached
  // derivation to change the order of four buttons.

  /// How much of a chip's prior survives its daypart. Multiplicative — see
  /// `daypartFactor`, where the reasoning lives.
  static const double daypartFactorMatch = 1.0;
  static const double daypartFactorNeutral = 0.8;

  /// A guess, and flagged as one in §9. It is what stops `after lunch` leading
  /// an 18:30 walking set while still letting `with morning coffee` reach a
  /// midday reading set.
  static const double daypartFactorAdjacent = 0.35;

  /// The ranking preference for habit stacking, made numeric.
  ///
  /// The event bonus is the single most consequential number in the chip
  /// library (§9): it trades the app's belief that stacking is the most
  /// reliable anchor against its ability to discover that a given user's habit
  /// is genuinely internally cued. Roughly a third of the prior range — enough
  /// that a moderately common event cue beats a very common time cue, not so
  /// much that it steamrolls a category whose honest answer is internal.
  static const Map<CueType, double> cueTypeBonus = <CueType, double>{
    CueType.event: 0.30,
    CueType.location: 0.15,
    CueType.time: 0.10,
    CueType.internal: 0.05,
    CueType.social: 0.0,
    CueType.unknown: 0.0,
  };

  /// Below this, a chip is not offered at all. Max possible score is 1.30.
  ///
  /// A mismatched daypart leaves a chip scoring at most its type bonus (0.30),
  /// which sits below this floor by construction — so mismatches self-eliminate
  /// and no separate rule is needed.
  static const double starterChipScoreFloor = 0.35;

  /// The event floor may only promote chips scoring at least this.
  ///
  /// This matters more than it looks. Without it the guard happily pushes
  /// `after dinner` into a 09:00 tidying set to satisfy its own arithmetic, and
  /// a guard that forces in a chip nobody would tap is worse than the imbalance
  /// it was correcting.
  static const double starterChipEventPromotionFloor = 0.60;

  /// How many starter chips a first reflection offers, beside the pinned
  /// designed cue.
  static const int starterChipCount = 4;

  /// Journey A has no designed cue to pin, so it surfaces one more — and
  /// raises the non-event floor, because its job is discovering a cue *type*
  /// the user has not named and an event-heavy set biases that discovery
  /// toward the answer the app already prefers.
  static const int starterChipCountWithoutDesignedCue = 5;
  static const int nonEventFloorWithoutDesignedCue = 2;

  /// At most this many chips of any one cue type, so no set is a monoculture.
  static const int starterChipTypeCeiling = 3;

  /// At least this many non-event chips, so an internally-, time- or socially-
  /// cued user always has a true answer available — which is also what keeps
  /// the growth-engine §5 internal-cue exemption reachable.
  static const int starterChipNonEventFloor = 1;

  /// At least this many event chips, subject to the promotion floor above.
  static const int starterChipEventFloor = 2;

  /// Diagnosis surfaces this many friction chips beside `Something else`.
  static const int frictionChipCount = 5;

  /// At most this many chips of any one friction type.
  static const int frictionTypeCap = 2;
  // ── Notification scheduling (reflection spec §1, guide §14) ───────────────
  //
  // Owned by the notifications feature; here for the same reason the
  // reflection block is — one home for every tunable.

  /// The evening check-in slot, on the local wall clock. Reflection and the
  /// next-day nudge are one notification (reflection spec §1), so this is the
  /// hour both arrive at.
  static const int eveningCheckInHour = 20;
  static const int eveningCheckInMinute = 0;

  /// How far ahead of its occasion a nudge is delivered. 1 — the evening
  /// before, which is what makes the nudge a *rehearsal* of tomorrow's cue
  /// rather than a reminder of a deadline (growth spec §6).
  static const int nudgeLeadDays = 1;

  /// How far ahead occasions are planned and notifications are queued.
  ///
  /// Short on purpose. Planning freezes the send/withhold decision against the
  /// stage the habit is at *now*, so a long horizon would keep nudging at a
  /// faded-out rate long after the plant climbed a rung — or the reverse.
  static const int nudgeHorizonDays = 7;

  /// How far back a planning pass will write occasions that nobody was around
  /// to schedule — the phone was off, or the app was not opened for a week.
  ///
  /// Those rows are real un-nudged occasions and belong in the denominator,
  /// but an unbounded backfill would re-derive a year of history on a launch.
  static const int nudgeBackfillDays = 30;

  /// How close to delivery a queued notification's **question** is re-composed.
  ///
  /// The reflection half of the evening message looks back at the day it
  /// arrives, but it is written when the notification is queued — up to
  /// [nudgeHorizonDays] earlier, against a day that had not happened yet. The
  /// planning pass therefore re-composes a pending notification once it is
  /// this close to firing, which is what makes "re-planning on every launch
  /// and after every completion keeps it from going stale" true rather than
  /// merely intended.
  ///
  /// Twenty-four hours, because the question is about *today*: a pass inside
  /// this window is reading the day the message will actually ask about. It is
  /// also what bounds the cost — at one occasion per habit per day, only the
  /// next evening's notification is ever in range, so a re-plan re-queues at
  /// most one notification per habit rather than the whole horizon.
  static const Duration nudgeQuestionRefreshWindow = Duration(hours: 24);

  /// Ceiling on notifications queued at once, across all habits.
  ///
  /// iOS keeps only the 64 soonest pending notifications and silently drops
  /// the rest, so the cap is ours to enforce with something left over — an
  /// app that hits the platform limit loses the *furthest out* nudges without
  /// being told.
  static const int maximumPendingNudges = 60;
}
