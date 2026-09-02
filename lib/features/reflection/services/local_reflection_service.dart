import 'package:logging/logging.dart';

import 'package:taproot/app/database/app_database.dart';
import 'package:taproot/app/database/store_logging.dart';
import 'package:taproot/core/models/reflection.dart';
import 'package:taproot/core/utils/json_codec.dart';
import 'package:taproot/features/reflection/domain/reflection_repository.dart';

/// SQLite-backed reflections.
class LocalReflectionService implements ReflectionRepository {
  LocalReflectionService({
    required Database database,
    DateTime Function()? clock,
  }) : _database = database,
       _clock = clock ?? DateTime.now;

  static final Logger _log = Logger('LocalReflectionService');

  final Database _database;
  final DateTime Function() _clock;

  @override
  Future<void> saveReflection(Reflection reflection) =>
      guardStore(_log, 'saveReflection', () async {
        final row = toRow(reflection.toJson())
          ..addAll(<String, Object?>{
            'updated_at': encodeDateTime(_clock()),
            'pending_sync': 1,
          });

        await _database.transaction((transaction) async {
          await requireExistingHabit(transaction, reflection.habitId);
          final updated = await transaction.update(
            AppSchema.reflections,
            row,
            where: 'id = ?',
            whereArgs: <Object?>[reflection.id],
          );
          if (updated == 0) {
            await transaction.insert(AppSchema.reflections, row);
          }
        });
      });

  @override
  Future<List<Reflection>> reflectionsFor(String habitId) =>
      guardStore(_log, 'reflectionsFor', () async {
        final rows = await _database.query(
          AppSchema.reflections,
          where: 'habit_id = ?',
          whereArgs: <Object?>[habitId],
          orderBy: 'created_at ASC, id ASC',
        );
        return rows.map(Reflection.fromJson).toList();
      });

  @override
  Future<List<Reflection>> recentReflections(String habitId, {int limit = 8}) =>
      guardStore(_log, 'recentReflections', () async {
        // Newest first to take the tail, then reversed: the engine reads oldest
        // first, and no filtering happens here (see the interface).
        final rows = await _database.query(
          AppSchema.reflections,
          where: 'habit_id = ?',
          whereArgs: <Object?>[habitId],
          orderBy: 'created_at DESC, id DESC',
          limit: limit,
        );
        return rows.reversed.map(Reflection.fromJson).toList();
      });
}
