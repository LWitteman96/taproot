import 'package:logging/logging.dart';

import 'package:taproot/app/database/app_database.dart';
import 'package:taproot/app/database/store_exceptions.dart';
import 'package:taproot/app/database/store_logging.dart';
import 'package:taproot/core/models/nudge.dart';
import 'package:taproot/core/utils/json_codec.dart';
import 'package:taproot/features/notifications/domain/nudge_repository.dart';

/// SQLite-backed nudge ledger.
class LocalNudgeService implements NudgeRepository {
  LocalNudgeService({required Database database, DateTime Function()? clock})
    : _database = database,
      _clock = clock ?? DateTime.now;

  static final Logger _log = Logger('LocalNudgeService');

  final Database _database;
  final DateTime Function() _clock;

  @override
  Future<void> saveNudge(NudgeRecord nudge) =>
      guardStore(_log, 'saveNudge', () async {
        final row = toRow(nudge.toJson())..addAll(_syncStamp());

        await _database.transaction((transaction) async {
          await requireExistingHabit(transaction, nudge.habitId);
          final updated = await transaction.update(
            AppSchema.nudges,
            row,
            where: 'id = ?',
            whereArgs: <Object?>[nudge.id],
          );
          if (updated == 0) {
            await transaction.insert(AppSchema.nudges, row);
          }
        });
      });

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
