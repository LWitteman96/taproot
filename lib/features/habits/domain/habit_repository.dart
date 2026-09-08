import 'package:taproot/core/models/habit.dart';
import 'package:taproot/core/models/pause_interval.dart';

/// Habits and their pauses.
///
/// Split by aggregate from day one — completions, reflections and the nudge
/// ledger each have their own repository. One repository per aggregate is what
/// keeps any of them from growing into a seven-concern interface.
///
/// Everything here is local and fast: the store is primary, and no method on
/// this interface waits on a network.
abstract class HabitRepository {
  /// Live habits, oldest first. Deleted habits are excluded.
  Future<List<Habit>> allHabits();

  /// The habit, or null if it is unknown or deleted.
  Future<Habit?> habitById(String habitId);

  /// Inserts or updates. Habits are mutable and sync last-write-wins, so there
  /// is one method rather than a create/update pair.
  Future<void> saveHabit(Habit habit);

  /// Soft-deletes. The row stays as a tombstone so the deletion can be synced;
  /// deleting twice, or deleting an unknown id, is a no-op.
  Future<void> deleteHabit(String habitId);

  /// Starts a pause, if one is not already running.
  ///
  /// Paused days are excluded from every engine window — they are not misses.
  /// The habit stamp and the open interval are written together.
  ///
  /// Throws [UnknownHabitException] if the habit is unknown or deleted.
  Future<void> pauseHabit(String habitId);

  /// Ends the running pause. A no-op if the habit is not paused.
  ///
  /// Throws [UnknownHabitException] if the habit is unknown or deleted.
  Future<void> resumeHabit(String habitId);

  /// Every pause the habit has had, oldest first. The last one is open while a
  /// pause is running. An unknown habit has no pauses rather than being an
  /// error, because this is a read.
  Future<List<PauseInterval>> pausesFor(String habitId);
}
