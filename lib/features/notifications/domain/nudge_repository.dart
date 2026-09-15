import 'package:taproot/core/models/nudge.dart';

/// The nudge ledger — one row per **expected occasion**.
///
/// A row exists even for the occasions the engine deliberately stayed silent
/// on. Those un-sent rows are autonomy's denominator: the app can only learn
/// whether a habit stands on its own by withholding the nudge and writing down
/// that it did. Their absence cannot be inferred from the absence of a
/// notification, so nothing here is optional bookkeeping.
/// **Reading this ledger from another feature.** Rows are per-aggregate and
/// shared for reads — reflection's priority scoring needs occasion outcomes,
/// including un-nudged completions (reflection spec §2). Three things a raw
/// read can misinterpret, all of them consequences of the ledger being written
/// by a *scheduler* rather than by events as they happen:
///
/// - **Rows exist for occasions that have not happened yet.** A planning pass
///   records the whole horizon at once, up to a week ahead. Anything reading
///   outcomes must filter to `expectedOccasionAt` at or before now — which is
///   what `HabitInputs.nudgesUpTo` does, and why the engine uses it.
/// - **`sent` means a notification was queued with the OS, not that the user
///   saw one.** It is set when the nudge is scheduled, because delivery is not
///   observable. For a future row it is a statement of intent.
/// - **`confirmed` and `declined` are answers to the notification**, not facts
///   about the habit. An unconfirmed row means "no button was pressed", which
///   covers both a decline-by-silence and a user who simply did the thing. Only
///   `completions` say whether the habit happened.
///
/// - **`confirmed` and `declined` may be written by a background isolate**,
///   with no widget tree and no `ProviderContainer`, while the app is not
///   running — that is the normal path for an answer given from the shade.
///   SQLite serialises the write, so the row is safe, but nothing in the main
///   isolate is notified: anything holding nudge rows in memory has to re-read
///   on resume rather than trust what it is holding.
///
/// The notifications feature is the only **writer**; `markConfirmed`,
/// `markDeclined` and `markSent` are the outcome columns and belong to it.
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
