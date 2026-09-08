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
  Future<void> markConfirmed(String nudgeId);

  /// Throws [UnknownNudgeException] if the row is not in the ledger.
  Future<void> markDeclined(String nudgeId);
}
