import 'package:taproot/core/models/completion.dart';
import 'package:taproot/core/utils/local_dates.dart';

/// Completions — the watering events.
///
/// Append-only. There is no update and no delete: a completion is an event that
/// already happened, keyed by `(habitId, id)` with the id generated client-side
/// before insert. That is what makes multi-device sync a union rather than a
/// merge, and it is why re-recording the same completion is a no-op instead of
/// an overwrite.
///
/// Undo does not break that. A retraction is *another* append-only event, so
/// the two ledgers together are still a union: retracted wins, whichever order
/// the devices sync in, and a stale replay of the completion cannot resurrect
/// it. Every read here excludes retracted completions.
abstract class CompletionRepository {
  /// Records a completion. Recording one that is already stored does nothing —
  /// the first write wins.
  ///
  /// Throws [UnknownHabitException] if the habit is unknown or deleted, which
  /// is the expected-but-abnormal case of a habit removed on another device.
  Future<void> recordCompletion(Completion completion);

  /// Every completion for the habit, oldest first.
  Future<List<Completion>> completionsFor(String habitId);

  /// Completions falling on [date] in **local calendar** terms — local midnight
  /// to local midnight, not a UTC day.
  Future<List<Completion>> completionsOnLocalDate(
    String habitId,
    LocalDate date,
  );

  /// The most recent completion, or null if the habit has never been watered.
  Future<Completion?> latestCompletion(String habitId);

  /// Undoes a completion — the accidental tap while looking at the garden.
  ///
  /// Idempotent: undoing something already undone does nothing, regardless of
  /// how much later it is asked. The undo window is `isRetractable`, and past
  /// it this throws [CompletionNotRetractableException]. An id the store has
  /// never seen throws [UnknownCompletionException].
  Future<void> retractCompletion(String habitId, String completionId);

  /// Records a retraction that happened elsewhere — the sync path, not the UI.
  ///
  /// Unlike [retractCompletion] this asks no questions: it neither requires the
  /// completion to be present nor checks the undo window. Both are deliberate.
  /// A retraction can reach this device **before** the completion it retracts
  /// (which is why `completion_retractions` has no foreign key to
  /// `completions`), and the window was already judged on the device where the
  /// user actually pressed undo — re-judging it here against a different clock
  /// and a different timezone would drop legitimate undos.
  ///
  /// Idempotent. Still throws [UnknownHabitException] for an unknown habit.
  Future<void> recordRetraction(
    String habitId,
    String completionId, {
    required DateTime retractedAt,
  });
}
