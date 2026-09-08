import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import 'package:taproot/app/database/app_database.dart';
import 'package:taproot/app/database/store_exceptions.dart';
import 'package:taproot/app/database/store_logging.dart';
import 'package:taproot/core/models/habit.dart';
import 'package:taproot/core/models/pause_interval.dart';
import 'package:taproot/core/utils/json_codec.dart';
import 'package:taproot/features/habits/domain/habit_repository.dart';

/// SQLite-backed habits. The local store is primary, so this is the real
/// implementation rather than a cache in front of one.
class LocalHabitService implements HabitRepository {
  LocalHabitService({
    required Database database,
    DateTime Function()? clock,
    Uuid? uuid,
  }) : _database = database,
       _clock = clock ?? DateTime.now,
       _uuid = uuid ?? const Uuid();

  static final Logger _log = Logger('LocalHabitService');

  final Database _database;

  /// Injected so `updated_at` and the pause boundaries are testable.
  final DateTime Function() _clock;

  final Uuid _uuid;

  /// Habits with their pause state joined back on.
  ///
  /// `paused_at` is not a column — it is the start of the open interval in
  /// `habit_pauses`. Reading it through a join is what makes it impossible for
  /// the stamp and the ledger to disagree. At most one interval is open per
  /// habit ([pauseHabit] enforces it), so the join cannot fan out.
  static const String _habitsWithPauseState =
      '''
    SELECT h.*, p.started_at AS paused_at
    FROM ${AppSchema.habits} h
    LEFT JOIN ${AppSchema.habitPauses} p
      ON p.habit_id = h.id AND p.ended_at IS NULL
    WHERE h.deleted_at IS NULL
  ''';

  @override
  Future<List<Habit>> allHabits() => guardStore(_log, 'allHabits', () async {
    final rows = await _database.rawQuery(
      '$_habitsWithPauseState ORDER BY h.created_at ASC, h.id ASC',
    );
    return rows.map(Habit.fromJson).toList();
  });

  @override
  Future<Habit?> habitById(String habitId) =>
      guardStore(_log, 'habitById', () async {
        final rows = await _database.rawQuery(
          '$_habitsWithPauseState AND h.id = ? LIMIT 1',
          <Object?>[habitId],
        );
        return rows.isEmpty ? null : Habit.fromJson(rows.single);
      });

  @override
  Future<void> saveHabit(Habit habit) =>
      guardStore(_log, 'saveHabit', () async {
        // `habit.toJson()` deliberately carries no `paused_at`, so this cannot
        // reach pause state even by accident — that lives in habit_pauses and
        // is owned by pauseHabit/resumeHabit alone.
        final row = toRow(habit.toJson())..addAll(_syncStamp());

        // Not ConflictAlgorithm.replace: that is a DELETE followed by an
        // INSERT, which would fire ON DELETE CASCADE and take every completion,
        // reflection and nudge with it.
        await _database.transaction((transaction) async {
          final updated = await transaction.update(
            AppSchema.habits,
            row,
            // Tombstones are excluded: an update that matched one would report
            // success while habitById kept returning null and every child
            // write kept throwing UnknownHabitException.
            where: 'id = ? AND deleted_at IS NULL',
            whereArgs: <Object?>[habit.id],
          );
          if (updated > 0) return;

          if (await _isKnown(transaction, habit.id)) {
            // The row exists but is deleted — the same expected-but-abnormal
            // condition a completion for a deleted habit reports.
            throw UnknownHabitException(habit.id);
          }
          await transaction.insert(AppSchema.habits, row);
        });
      });

  Future<bool> _isKnown(DatabaseExecutor executor, String habitId) async {
    final rows = await executor.query(
      AppSchema.habits,
      columns: <String>['id'],
      where: 'id = ?',
      whereArgs: <Object?>[habitId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<void> deleteHabit(String habitId) =>
      guardStore(_log, 'deleteHabit', () async {
        final now = _clock();
        // A tombstone rather than a DELETE, so the deletion can be synced.
        await _database.update(
          AppSchema.habits,
          <String, Object?>{
            'deleted_at': encodeDateTime(now),
            ..._syncStamp(now),
          },
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: <Object?>[habitId],
        );
      });

  @override
  Future<void> pauseHabit(String habitId) =>
      guardStore(_log, 'pauseHabit', () async {
        await _database.transaction((transaction) async {
          await requireExistingHabit(transaction, habitId);
          if (await _openPause(transaction, habitId) != null) return;

          // One write, one source of truth: the open interval *is* the paused
          // state. There is no habit stamp to keep in step with it.
          final now = _clock();
          await transaction.insert(AppSchema.habitPauses, <String, Object?>{
            'id': _uuid.v4(),
            'habit_id': habitId,
            'started_at': encodeDateTime(now),
            'ended_at': null,
            ..._syncStamp(now),
          });
        });
      });

  @override
  Future<void> resumeHabit(String habitId) =>
      guardStore(_log, 'resumeHabit', () async {
        await _database.transaction((transaction) async {
          await requireExistingHabit(transaction, habitId);
          final open = await _openPause(transaction, habitId);
          if (open == null) return;

          final now = _clock();
          await transaction.update(
            AppSchema.habitPauses,
            <String, Object?>{
              'ended_at': encodeDateTime(now),
              ..._syncStamp(now),
            },
            where: 'id = ?',
            whereArgs: <Object?>[open],
          );
        });
      });

  @override
  Future<List<PauseInterval>> pausesFor(String habitId) =>
      guardStore(_log, 'pausesFor', () async {
        final rows = await _database.query(
          AppSchema.habitPauses,
          where: 'habit_id = ?',
          whereArgs: <Object?>[habitId],
          orderBy: 'started_at ASC',
        );
        return rows.map(PauseInterval.fromJson).toList();
      });

  /// The id of the running pause, or null.
  Future<String?> _openPause(DatabaseExecutor executor, String habitId) async {
    final rows = await executor.query(
      AppSchema.habitPauses,
      columns: <String>['id'],
      where: 'habit_id = ? AND ended_at IS NULL',
      whereArgs: <Object?>[habitId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['id']! as String;
  }

  Map<String, Object?> _syncStamp([DateTime? at]) => <String, Object?>{
    'updated_at': encodeDateTime(at ?? _clock()),
    'pending_sync': 1,
  };
}
