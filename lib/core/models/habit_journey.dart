/// Which route a habit took into the garden (design-spec §2).
///
/// **Recorded, not inferred.** The spec leaves this open — record the route, or
/// infer it from "was a designed cue present at creation" — and the inference
/// is wrong the moment it matters. A Journey A habit that discovers a reliable
/// cue through reflection has one locked in as its official cue (design-spec
/// §3), at which point it is indistinguishable from a habit designed up front.
/// That is precisely the population the spec wants to be able to tell apart:
/// the two behave differently under every metric in the growth engine, and a
/// reverse-engineered loop arriving at a cue is *a graduation worth seeing*.
///
/// The inference is kept, once, as the backfill for rows written before this
/// column existed — see the schema-version-2 upgrade step.
enum HabitJourney {
  /// Journey B — the loop was designed up front. The default path.
  design,

  /// Journey A — an existing habit, tracked so its loop can be reverse-
  /// engineered through reflection. An explicit opt-out, never the path of
  /// least resistance (design-spec §2).
  track;

  /// Whether creation asks for the cue → routine → reward triple.
  bool get designsTheLoop => this == HabitJourney.design;
}
