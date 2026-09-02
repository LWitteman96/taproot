/// Enumerations shared by the whole growth engine (growth spec §0, §3;
/// reflection spec §3, §4, §5).
library;

/// The stage ladder. Monotonic — an earned stage is banked and never lost
/// (growth spec §0).
enum Stage {
  seed,
  sprout,
  seedling,
  young,
  mature,
  bloom;

  bool isAtLeast(Stage other) => index >= other.index;

  bool isBelow(Stage other) => index < other.index;

  /// The stage immediately above this one, or null at the top of the ladder.
  Stage? get next => this == Stage.bloom ? null : Stage.values[index + 1];
}

/// Cue taxonomy (reflection spec §4).
///
/// Only external types may anchor a *designed* cue — the engine cannot
/// schedule, nudge, or fairly measure a habit hung on a mood (growth spec §1).
/// All five are valid as cues *discovered* through reflection.
enum CueType {
  event,
  time,
  location,
  internal,
  social,
  unknown;

  /// Whether convergence is measured on the exact cue label (external) rather
  /// than on type stability (internal) — growth spec §5 exemption.
  bool get isExternal =>
      this == CueType.event ||
      this == CueType.time ||
      this == CueType.location ||
      this == CueType.social;

  /// Whether this type may be chosen as the designed cue at habit creation.
  bool get isSchedulable => isExternal;
}

/// Friction taxonomy for diagnosis reflections (reflection spec §4).
enum FrictionType { forgot, time, energy, competing, environment, motivation }

/// What the check-in asked (reflection spec §3).
enum Framing { validation, discovery, confirmation, diagnosis, autonomy }

/// What the check-in was about (reflection spec §5).
enum Occasion { completion, miss, autonomyCompletion }

/// How the user answered. `cantRemember` is a first-class answer, not a gap
/// (reflection spec §4).
enum InputMode { chip, typed, cantRemember, skipped }
