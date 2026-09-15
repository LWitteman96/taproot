/// The twelve categories the starter chip library is authored against
/// (starter-chip-library.md §7).
///
/// This exists for one reason: the **first** reflection on a habit has no
/// history to rank chips from, so it is assembled from the designed cue plus
/// starter chips "filtered by habit category and the time of day" (§0). Nothing
/// but creation can supply that category — it is a statement about what the
/// habit *is*, not something a completion or a reflection reveals — so it is
/// captured here or it is not captured at all.
///
/// It is deliberately **optional** on a habit. The library carries global cue
/// pools that backfill "for any category" (§6.1), so a habit that fits none of
/// the twelve still gets a plausible first reflection; it just gets a slightly
/// weaker one. Forcing every habit into one of twelve buckets would buy a
/// non-null column at the cost of miscategorised chips, which is the exact
/// forced-fit failure §0 is written to avoid.
enum HabitCategory {
  exercise('Exercise'),
  meditation('Meditation'),
  reading('Reading'),
  journaling('Journaling'),
  hydration('Hydration'),
  tidying('Tidying'),
  languagePractice('Language practice'),
  instrument('Instrument'),
  stretching('Stretching'),
  supplements('Supplements'),
  walking('Walking'),
  sleepRoutine('Sleep routine');

  const HabitCategory(this.label);

  /// What the user sees. Sentence case, because the app's voice is a journal
  /// rather than a form.
  final String label;
}
