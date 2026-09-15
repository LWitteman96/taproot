import 'package:taproot/core/models/nudge.dart';

/// The nudge ledger — one row per **expected occasion**.
///
/// A row exists even for the occasions the engine deliberately stayed silent
/// on. Those un-sent rows are autonomy's denominator: the app can only learn
/// whether a habit stands on its own by withholding the nudge and writing down
/// that it did. Their absence cannot be inferred from the absence of a
/// notification, so nothing here is optional bookkeeping.
abstract class NudgeRepository {
  /// Inserts or updates by id.
  ///
  /// Throws [UnknownHabitException] if the habit is unknown or deleted.
  Future<void> saveNudge(NudgeRecord nudge);

  /// Every recorded occasion for the habit, oldest first.
  Future<List<NudgeRecord>> nudgesFor(String habitId);

  /// Throws [UnknownNudgeException] if the row is not in the ledger.
  Future<void> markSent(String nudgeId);

  /// Throws [UnknownNudgeException] if the row is not in the ledger.
  ///
  /// TODO(notifications): cascade an undo back onto this flag. Retracting a
  /// completion leaves the row still saying a nudge was confirmed by a
  /// completion that no longer counts. Autonomy self-corrects — it matches
  /// completions against occasions, so the undone completion drops out of the
  /// numerator on its own — but the column is stale, and the insight surfaces
  /// that read confirms/declines directly (growth spec §8) would read it.
  /// Deliberately left open rather than built against the completion-tap
  /// branch mid-flight; it is a cross-aggregate cascade and needs an owner,
  /// see docs/progress-log.md for this branch's "Left open".
  Future<void> markConfirmed(String nudgeId);

  /// Throws [UnknownNudgeException] if the row is not in the ledger.
  Future<void> markDeclined(String nudgeId);
}
