import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:taproot/app/database/app_database.dart';

import '../../../utils/store_fixtures.dart';

/// The schema is the one thing here that a later migration cannot take back
/// cheaply, so it is pinned by tests rather than by reading the SQL.
void main() {
  late Database database;

  setUp(() async {
    database = await openTestDatabase();
  });

  tearDown(() => database.close());

  Future<List<String>> columnsOf(String table) async {
    final rows = await database.rawQuery('PRAGMA table_info($table)');
    return rows.map((row) => row['name']! as String).toList();
  }

  Future<List<String>> tableNames() async {
    final rows = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%'",
    );
    return rows.map((row) => row['name']! as String).toList();
  }

  group('schema', () {
    test('opens at the declared version', () async {
      expect(await database.getVersion(), AppSchema.version);
    });

    test('creates every local-first table', () async {
      expect(
        await tableNames(),
        containsAll(<String>[
          AppSchema.habits,
          AppSchema.completions,
          AppSchema.reflections,
          AppSchema.nudges,
          AppSchema.habitPauses,
          AppSchema.completionRetractions,
        ]),
      );
    });

    test('habits carry the domain fields and the sync plumbing', () async {
      expect(
        await columnsOf(AppSchema.habits),
        containsAll(<String>[
          'id',
          'name',
          'identity_statement',
          'plant_type',
          'target_frequency',
          'designed_cue',
          'designed_cue_type',
          'routine',
          'reward',
          'created_at',
          'paused_at',
          'graduated_at',
          'updated_at',
          'deleted_at',
          'pending_sync',
        ]),
      );
    });

    test('no table stores a derived engine value', () async {
      for (final table in await tableNames()) {
        expect(
          await columnsOf(table),
          isNot(
            anyOf(
              contains('stage'),
              contains('vitality'),
              contains('root_depth'),
              contains('autonomy'),
            ),
          ),
          reason: '$table should not cache a derivation',
        );
      }
    });

    test('every syncable table carries pending_sync', () async {
      for (final table in <String>[
        AppSchema.habits,
        AppSchema.completions,
        AppSchema.reflections,
        AppSchema.nudges,
        AppSchema.habitPauses,
        AppSchema.completionRetractions,
      ]) {
        expect(await columnsOf(table), contains('pending_sync'), reason: table);
      }
    });

    test('completions are keyed by (habit_id, id), not by id alone', () async {
      // The composite key is what makes multi-device sync a union: the same
      // client-generated UUID replayed for the same habit is one event.
      final info = await database.rawQuery(
        'PRAGMA table_info(${AppSchema.completions})',
      );
      final primaryKey = info.where((row) => (row['pk']! as int) > 0).toList()
        ..sort((a, b) => (a['pk']! as int).compareTo(b['pk']! as int));

      expect(primaryKey.map((row) => row['name']), <String>['habit_id', 'id']);
    });

    test(
      'completions carry no updated_at — they are append-only events',
      () async {
        expect(
          await columnsOf(AppSchema.completions),
          isNot(contains('updated_at')),
        );
        expect(
          await columnsOf(AppSchema.completions),
          isNot(contains('deleted_at')),
        );
      },
    );

    test('the nudge ledger holds one row per expected occasion', () async {
      await database.insert(AppSchema.habits, <String, Object?>{
        'id': 'habit-1',
        'name': 'Run',
        'plant_type': 'oak',
        'target_frequency': 3,
        'created_at': '2026-01-05T08:00:00.000Z',
        'updated_at': '2026-01-05T08:00:00.000Z',
        'pending_sync': 1,
      });

      Map<String, Object?> occasion(String id) => <String, Object?>{
        'id': id,
        'habit_id': 'habit-1',
        'expected_occasion_at': '2026-01-06T17:00:00.000Z',
        'sent': 0,
        'confirmed': 0,
        'declined': 0,
        'updated_at': '2026-01-05T08:00:00.000Z',
        'pending_sync': 1,
      };

      await database.insert(AppSchema.nudges, occasion('n-1'));

      expect(
        () => database.insert(AppSchema.nudges, occasion('n-2')),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('an undo is its own append-only event', () async {
      // Not a column on the completion and not a DELETE: both ledgers are
      // insert-only, so merging two devices is a union in which a retraction
      // can never be lost or reversed by a stale replay.
      expect(
        await columnsOf(AppSchema.completionRetractions),
        containsAll(<String>[
          'habit_id',
          'completion_id',
          'retracted_at',
          'pending_sync',
        ]),
      );

      final info = await database.rawQuery(
        'PRAGMA table_info(${AppSchema.completionRetractions})',
      );
      final primaryKey = info.where((row) => (row['pk']! as int) > 0).toList()
        ..sort((a, b) => (a['pk']! as int).compareTo(b['pk']! as int));
      expect(primaryKey.map((row) => row['name']), <String>[
        'habit_id',
        'completion_id',
      ]);
    });

    test('a retraction may be recorded before its completion arrives', () async {
      // Deliberately no foreign key to completions: on a multi-device sync the
      // retraction can land first, and it has to be storable when it does.
      await database.insert(AppSchema.habits, <String, Object?>{
        'id': 'habit-1',
        'name': 'Run',
        'plant_type': 'oak',
        'target_frequency': 3,
        'created_at': '2026-01-05T08:00:00.000Z',
        'updated_at': '2026-01-05T08:00:00.000Z',
        'pending_sync': 1,
      });

      await expectLater(
        database.insert(AppSchema.completionRetractions, <String, Object?>{
          'habit_id': 'habit-1',
          'completion_id': 'not-here-yet',
          'retracted_at': '2026-01-05T09:00:00.000Z',
          'pending_sync': 1,
        }),
        completes,
      );
    });

    test('the query indexes exist', () async {
      final rows = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index'",
      );
      final names = rows.map((row) => row['name']! as String);

      expect(
        names,
        containsAll(<String>[
          'idx_completions_habit_completed_at',
          'idx_reflections_habit_created_at',
          'idx_nudges_habit_occasion_at',
          'idx_habit_pauses_habit_started_at',
        ]),
      );
    });
  });

  group('foreign keys', () {
    test('are switched on for the connection', () async {
      final rows = await database.rawQuery('PRAGMA foreign_keys');
      expect(rows.single.values.single, 1);
    });

    test('reject a child row whose habit does not exist', () async {
      expect(
        () => database.insert(AppSchema.completions, <String, Object?>{
          'id': 'c-1',
          'habit_id': 'never-existed',
          'completed_at': '2026-01-05T08:00:00.000Z',
          'was_nudged': 0,
          'source': 'tap',
          'pending_sync': 1,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('rows', () {
    test('encode booleans as the integers SQLite accepts', () {
      expect(
        toRow(<String, Object?>{'sent': true, 'declined': false, 'id': 'n-1'}),
        <String, Object?>{'sent': 1, 'declined': 0, 'id': 'n-1'},
      );
    });

    test('leave nulls, strings and numbers alone', () {
      expect(
        toRow(<String, Object?>{'a': null, 'b': 'x', 'c': 3}),
        <String, Object?>{'a': null, 'b': 'x', 'c': 3},
      );
    });
  });

  group('migrations', () {
    test('adding a column is idempotent, so a re-run is safe', () async {
      await database.execute('CREATE TABLE probe (id TEXT PRIMARY KEY)');

      await ensureColumn(
        database,
        'probe',
        'pending_sync',
        'INTEGER NOT NULL DEFAULT 0',
      );
      await ensureColumn(
        database,
        'probe',
        'pending_sync',
        'INTEGER NOT NULL DEFAULT 0',
      );

      final columns = (await database.rawQuery(
        'PRAGMA table_info(probe)',
      )).map((row) => row['name']).toList();
      expect(columns, <String>['id', 'pending_sync']);
    });

    test('re-opening an existing database does not re-create it', () async {
      final directory = await Directory.systemTemp.createTemp('taproot_db');
      addTearDown(() => directory.delete(recursive: true));
      final path = p.join(directory.path, 'taproot.db');

      sqfliteFfiInit();
      final first = await openAppDatabase(
        databaseFactory: databaseFactoryFfi,
        path: path,
      );
      await first.insert(AppSchema.habits, <String, Object?>{
        'id': 'habit-1',
        'name': 'Run',
        'plant_type': 'oak',
        'target_frequency': 3,
        'created_at': '2026-01-05T08:00:00.000Z',
        'updated_at': '2026-01-05T08:00:00.000Z',
        'pending_sync': 1,
      });
      await first.close();

      final second = await openAppDatabase(
        databaseFactory: databaseFactoryFfi,
        path: path,
      );
      addTearDown(second.close);

      expect(await second.query(AppSchema.habits), hasLength(1));
      expect(await second.getVersion(), AppSchema.version);
    });
  });
}
