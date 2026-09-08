import 'package:logging/logging.dart';

import 'package:taproot/app/database/app_database.dart';
import 'package:taproot/app/database/store_exceptions.dart';
import 'package:taproot/app/database/store_logging.dart';
import 'package:taproot/core/models/nudge.dart';
import 'package:taproot/core/utils/json_codec.dart';
import 'package:taproot/core/utils/local_dates.dart';
import 'package:taproot/features/notifications/domain/nudge_repository.dart';

/// SQLite-backed nudge ledger.
class LocalNudgeService implements NudgeRepository {
  LocalNudgeService({required Database database, DateTime Function()? clock})
    : _database = database,
      _clock = clock ?? DateTime.now;

  static final Logger _log = Logger('LocalNudgeService');

  final Database _database;
  final DateTime Function() _clock;

  /// The columns [markSent], [markConfirmed] and [markDeclined] own once the
  /// row exists.
  ///
  /// A save is the scheduler saying "this occasion exists, and here is when it
  /// is due". The outcome of the occasion is not its to restate: rolling `sent`
  /// back to 0 after the notification fired would move an occasion that *was*
  /// nudged into autonomy's un-nudged denominator and quietly depress the
  /// graduation gate.
  static const List<String> _outcomeColumns = <String>[
    'sent',
    'confirmed',
    'declined',
  ];

  @override
  Future<void> saveNudge(NudgeRecord nudge) =>
      guardStore(_log, 'saveNudge', () async {
        await _database.transaction((transaction) async {
          await requireExistingHabit(transaction, nudge.habitId);

          final clash = await _occasionOnSameLocalDate(transaction, nudge);
          if (clash != null) {
            throw DuplicateOccasionException(nudge.habitId, clash);
          }

          final row = toRow(nudge.toJson())..addAll(_syncStamp());
          final exists = await _exists(transaction, nudge.id);
          if (!exists) {
            await transaction.insert(AppSchema.nudges, row);
            return;
          }

          row.removeWhere((column, _) => _outcomeColumns.contains(column));
          await transaction.update(
            AppSchema.nudges,
            row,
            where: 'id = ?',
            whereArgs: <Object?>[nudge.id],
          );
        });
      });

  /// The id of another row already holding [nudge]'s local date, or null.
  ///
  /// Uniqueness is per habit per **local day**, not per instant, because that
  /// is the grain `computeAutonomy` matches occasions to completions at. A
  /// constraint on the timestamp would have let two occasions an hour apart
  /// both count in the denominator.
  Future<String?> _occasionOnSameLocalDate(
    DatabaseExecutor executor,
    NudgeRecord nudge,
  ) async {
    final date = LocalDate.from(nudge.expectedOccasionAt);
    final rows = await executor.query(
      AppSchema.nudges,
      columns: <String>['id'],
      where:
          'habit_id = ? AND id != ? AND '
          'expected_occasion_at >= ? AND expected_occasion_at < ?',
      whereArgs: <Object?>[
        nudge.habitId,
        nudge.id,
        encodeDateTime(date.startOfDay),
        encodeDateTime(date.addDays(1).startOfDay),
      ],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['id']! as String;
  }

  Future<bool> _exists(DatabaseExecutor executor, String nudgeId) async {
    final rows = await executor.query(
      AppSchema.nudges,
      columns: <String>['id'],
      where: 'id = ?',
      whereArgs: <Object?>[nudgeId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<List<NudgeRecord>> nudgesFor(String habitId) =>
      guardStore(_log, 'nudgesFor', () async {
        final rows = await _database.query(
          AppSchema.nudges,
          where: 'habit_id = ?',
          whereArgs: <Object?>[habitId],
          orderBy: 'expected_occasion_at ASC, id ASC',
        );
        return rows.map(NudgeRecord.fromJson).toList();
      });

  @override
  Future<void> markSent(String nudgeId) => _mark(nudgeId, 'sent');

  @override
  Future<void> markConfirmed(String nudgeId) => _mark(nudgeId, 'confirmed');

  @override
  Future<void> markDeclined(String nudgeId) => _mark(nudgeId, 'declined');

  Future<void> _mark(String nudgeId, String column) =>
      guardStore(_log, 'mark $column', () async {
        final updated = await _database.update(
          AppSchema.nudges,
          <String, Object?>{column: 1, ..._syncStamp()},
          where: 'id = ?',
          whereArgs: <Object?>[nudgeId],
        );
        if (updated == 0) throw UnknownNudgeException(nudgeId);
      });

  Map<String, Object?> _syncStamp() => <String, Object?>{
    'updated_at': encodeDateTime(_clock()),
    'pending_sync': 1,
  };
}
