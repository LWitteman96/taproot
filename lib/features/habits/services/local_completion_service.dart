import 'package:logging/logging.dart';

import 'package:taproot/app/database/app_database.dart';
import 'package:taproot/app/database/store_exceptions.dart';
import 'package:taproot/app/database/store_logging.dart';
import 'package:taproot/core/models/completion.dart';
import 'package:taproot/core/utils/json_codec.dart';
import 'package:taproot/core/utils/local_dates.dart';
import 'package:taproot/features/habits/domain/completion_repository.dart';
import 'package:taproot/features/habits/domain/completion_retraction.dart';

/// SQLite-backed completions — the write behind the tap, and the undo behind
/// the mis-tap.
class LocalCompletionService implements CompletionRepository {
  LocalCompletionService({
    required Database database,
    DateTime Function()? clock,
  }) : _database = database,
       _clock = clock ?? DateTime.now;

  static final Logger _log = Logger('LocalCompletionService');

  final Database _database;

  /// Injected so the undo window is testable without waiting for midnight.
  final DateTime Function() _clock;

  /// Every read joins against the undo ledger. Writing it once here is what
  /// stops a later query from quietly forgetting to exclude retractions.
  static const String _liveCompletions =
      '''
    SELECT c.* FROM ${AppSchema.completions} c
    WHERE c.habit_id = ?
      AND NOT EXISTS (
        SELECT 1 FROM ${AppSchema.completionRetractions} r
        WHERE r.habit_id = c.habit_id AND r.completion_id = c.id
      )
  ''';

  @override
  Future<void> recordCompletion(Completion completion) =>
      guardStore(_log, 'recordCompletion', () async {
        await _database.transaction((transaction) async {
          await requireExistingHabit(transaction, completion.habitId);
          await transaction.insert(
            AppSchema.completions,
            toRow(completion.toJson())
              ..addAll(<String, Object?>{'pending_sync': 1}),
            // Ignore, not replace: a completion is an event that already
            // happened, so a replayed `(habit_id, id)` is the same event and
            // the first write stands.
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        });
      });

  @override
  Future<List<Completion>> completionsFor(String habitId) =>
      guardStore(_log, 'completionsFor', () async {
        final rows = await _database.rawQuery(
          '$_liveCompletions ORDER BY c.completed_at ASC, c.id ASC',
          <Object?>[habitId],
        );
        return rows.map(Completion.fromJson).toList();
      });

  @override
  Future<List<Completion>> completionsOnLocalDate(
    String habitId,
    LocalDate date,
  ) => guardStore(_log, 'completionsOnLocalDate', () async {
    // Local midnight to local midnight, converted to the UTC instants the
    // column stores. A UTC day would put the late-evening tap and the
    // early-morning one on different days for most of the world.
    final rows = await _database.rawQuery(
      '$_liveCompletions AND c.completed_at >= ? AND c.completed_at < ? '
      'ORDER BY c.completed_at ASC, c.id ASC',
      <Object?>[
        habitId,
        encodeDateTime(date.startOfDay),
        encodeDateTime(date.addDays(1).startOfDay),
      ],
    );
    return rows.map(Completion.fromJson).toList();
  });

  @override
  Future<Completion?> latestCompletion(String habitId) =>
      guardStore(_log, 'latestCompletion', () async {
        final rows = await _database.rawQuery(
          '$_liveCompletions ORDER BY c.completed_at DESC, c.id DESC LIMIT 1',
          <Object?>[habitId],
        );
        return rows.isEmpty ? null : Completion.fromJson(rows.single);
      });

  @override
  Future<void> retractCompletion(String habitId, String completionId) =>
      guardStore(_log, 'retractCompletion', () async {
        await _database.transaction((transaction) async {
          await requireExistingHabit(transaction, habitId);

          // Already undone: a no-op, and deliberately checked before the
          // window, so idempotence does not expire at midnight.
          if (await _isRetracted(transaction, habitId, completionId)) return;

          final rows = await transaction.query(
            AppSchema.completions,
            where: 'habit_id = ? AND id = ?',
            whereArgs: <Object?>[habitId, completionId],
            limit: 1,
          );
          if (rows.isEmpty) {
            throw UnknownCompletionException(habitId, completionId);
          }

          final completion = Completion.fromJson(rows.single);
          if (!isRetractable(completion, at: _clock())) {
            throw CompletionNotRetractableException(habitId, completionId);
          }

          // The completion row stays. It is still an event that was recorded;
          // this is the event that says it did not count.
          await transaction.insert(
            AppSchema.completionRetractions,
            <String, Object?>{
              'habit_id': habitId,
              'completion_id': completionId,
              'retracted_at': encodeDateTime(_clock()),
              'pending_sync': 1,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        });
      });

  Future<bool> _isRetracted(
    DatabaseExecutor executor,
    String habitId,
    String completionId,
  ) async {
    final rows = await executor.query(
      AppSchema.completionRetractions,
      columns: <String>['completion_id'],
      where: 'habit_id = ? AND completion_id = ?',
      whereArgs: <Object?>[habitId, completionId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}
