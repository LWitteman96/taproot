/// Data-consistency conditions that are **expected but abnormal**.
///
/// These are deliberately kept out of Sentry. A completion whose habit was
/// deleted on another device is a real state the app must handle, not a bug —
/// and letting states like it into the error budget is what makes Sentry
/// useless. Catch them where they are meaningful; do not report them.
library;

/// A write named a habit that is not in the local store, or has been deleted.
class UnknownHabitException implements Exception {
  const UnknownHabitException(this.habitId);

  final String habitId;

  @override
  String toString() => 'UnknownHabitException($habitId)';
}

/// A ledger update named a nudge row that is not in the local store.
class UnknownNudgeException implements Exception {
  const UnknownNudgeException(this.nudgeId);

  final String nudgeId;

  @override
  String toString() => 'UnknownNudgeException($nudgeId)';
}

/// An undo named a completion that is not in the local store.
class UnknownCompletionException implements Exception {
  const UnknownCompletionException(this.habitId, this.completionId);

  final String habitId;
  final String completionId;

  @override
  String toString() => 'UnknownCompletionException($habitId/$completionId)';
}

/// An undo arrived after its window closed.
///
/// A completion can be undone for the rest of the local day it falls on. This
/// is a normal thing for a user to attempt — they opened the app the next
/// morning and thought better of yesterday's tap — so it is a state the UI
/// explains, not a fault.
class CompletionNotRetractableException implements Exception {
  const CompletionNotRetractableException(this.habitId, this.completionId);

  final String habitId;
  final String completionId;

  @override
  String toString() =>
      'CompletionNotRetractableException($habitId/$completionId)';
}
