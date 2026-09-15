import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/app/database/app_database.dart';
import 'package:taproot/app/sync/local_sync_store.dart';
import 'package:taproot/app/sync/sync_tables.dart';
import 'package:taproot/core/utils/json_codec.dart';

import '../../../utils/store_fixtures.dart';

final SyncTable habits = syncTables.firstWhere(
  (table) => table.name == AppSchema.habits,
);
final SyncTable completions = syncTables.firstWhere(
  (table) => table.name == AppSchema.completions,
);

/// A server-shaped habit row: the device's columns plus the two only the
/// server has.
Map<String, Object?> remoteHabit({
  String id = 'habit-1',
  String name = 'Morning run',
  required DateTime updatedAt,
  String? category = 'exercise',
  String? deletedAt,
}) => <String, Object?>{
  'id': id,
  'user_id': '11111111-0000-0000-0000-000000000001',
  'synced_at': encodeDateTime(updatedAt.add(const Duration(seconds: 1))),
  'name': name,
  'identity_statement': null,
  'plant_type': 'oak',
  'target_frequency': 3,
  'journey': 'design',
  'category': category,
  'designed_cue': 'after the kettle boils',
  'designed_cue_type': 'event',
  'routine': 'twice round the block',
  'reward': 'coffee',
  'created_at': encodeDateTime(DateTime.utc(2026, 3, 1)),
  'graduated_at': null,
  'updated_at': encodeDateTime(updatedAt),
  'deleted_at': deletedAt,
};

void main() {
  late Database database;
  late LocalSyncStore store;

  setUp(() async {
    database = await openTestDatabase();
    store = LocalSyncStore(database: database);
    addTearDown(database.close);
  });

  Future<Map<String, Object?>> readHabit(String id) async =>
      (await database.query(
        AppSchema.habits,
        where: 'id = ?',
        whereArgs: <Object?>[id],
      )).single;

  group('the push queue', () {
    test('offers rows marked pending, without the flag itself', () async {
      await database.insert(
        AppSchema.habits,
        toRow(remoteHabit(updatedAt: DateTime.utc(2026, 3, 4)))
          ..remove('user_id')
          ..remove('synced_at')
          ..['pending_sync'] = 1,
      );

      final pending = await store.pendingRows(habits);

      expect(pending, hasLength(1));
      expect(
        pending.single.containsKey('pending_sync'),
        isFalse,
        reason: 'the queue flag is the device\'s, and the server rejects it',
      );
      expect(pending.single['id'], 'habit-1');
    });

    test('ignores rows that are already up', () async {
      await database.insert(
        AppSchema.habits,
        toRow(remoteHabit(updatedAt: DateTime.utc(2026, 3, 4)))
          ..remove('user_id')
          ..remove('synced_at')
          ..['pending_sync'] = 0,
      );

      expect(await store.pendingRows(habits), isEmpty);
    });

    test('clearing takes a pushed row off the queue', () async {
      await database.insert(
        AppSchema.habits,
        toRow(remoteHabit(updatedAt: DateTime.utc(2026, 3, 4)))
          ..remove('user_id')
          ..remove('synced_at')
          ..['pending_sync'] = 1,
      );

      final pending = await store.pendingRows(habits);
      await store.clearPending(habits, pending);

      expect(await store.pendingRows(habits), isEmpty);
    });

    test('an edit made mid-push stays on the queue', () async {
      // The race that loses a write silently, and gets likelier the slower the
      // network is: the row is read for the push, the user edits it while the
      // push is in flight, and a clear by key alone wipes the flag that edit
      // just set. The edit would then never be sent, with nothing to see.
      await database.insert(
        AppSchema.habits,
        toRow(remoteHabit(updatedAt: DateTime.utc(2026, 3, 4)))
          ..remove('user_id')
          ..remove('synced_at')
          ..['pending_sync'] = 1,
      );

      final pushed = await store.pendingRows(habits);

      // The user renames it while the push is in flight.
      await database.update(
        AppSchema.habits,
        <String, Object?>{
          'name': 'Evening run',
          'updated_at': encodeDateTime(DateTime.utc(2026, 3, 5)),
          'pending_sync': 1,
        },
        where: 'id = ?',
        whereArgs: <Object?>['habit-1'],
      );

      await store.clearPending(habits, pushed);

      final stillPending = await store.pendingRows(habits);
      expect(stillPending, hasLength(1));
      expect(stillPending.single['name'], 'Evening run');
    });

    test('an append-only row clears by key alone', () async {
      // It has no updated_at to compare, and needs none: the row cannot change
      // after it is written.
      await database.insert(
        AppSchema.habits,
        toRow(remoteHabit(updatedAt: DateTime.utc(2026, 3, 4)))
          ..remove('user_id')
          ..remove('synced_at')
          ..['pending_sync'] = 0,
      );
      await database.insert(AppSchema.completions, <String, Object?>{
        'habit_id': 'habit-1',
        'id': 'completion-1',
        'completed_at': encodeDateTime(DateTime.utc(2026, 3, 4, 9)),
        'was_nudged': 0,
        'source': 'tap',
        'pending_sync': 1,
      });

      final pending = await store.pendingRows(completions);
      expect(pending, hasLength(1));

      await store.clearPending(completions, pending);
      expect(await store.pendingRows(completions), isEmpty);
    });
  });

  group('applying what came down', () {
    test('a new row lands, and is not queued straight back up', () async {
      final written = await store.applyPulled(habits, <Map<String, Object?>>[
        remoteHabit(updatedAt: DateTime.utc(2026, 3, 4)),
      ]);

      expect(written, 1);
      final row = await readHabit('habit-1');
      expect(row['name'], 'Morning run');
      expect(
        row['pending_sync'],
        0,
        reason: 'it arrived from the server; pushing it back is an echo',
      );
    });

    test('the server-only columns are dropped rather than rejected', () async {
      // user_id and synced_at exist on no device table, and SQLite rejects an
      // insert naming a column that is not there.
      await store.applyPulled(habits, <Map<String, Object?>>[
        remoteHabit(updatedAt: DateTime.utc(2026, 3, 4)),
      ]);

      final row = await readHabit('habit-1');
      expect(row.containsKey('user_id'), isFalse);
      expect(row.containsKey('synced_at'), isFalse);
    });

    test('a newer edit from elsewhere wins', () async {
      await store.applyPulled(habits, <Map<String, Object?>>[
        remoteHabit(updatedAt: DateTime.utc(2026, 3, 4)),
      ]);

      final written = await store.applyPulled(habits, <Map<String, Object?>>[
        remoteHabit(name: 'Evening run', updatedAt: DateTime.utc(2026, 3, 5)),
      ]);

      expect(written, 1);
      expect((await readHabit('habit-1'))['name'], 'Evening run');
    });

    test('a staler edit from elsewhere does not', () async {
      await store.applyPulled(habits, <Map<String, Object?>>[
        remoteHabit(name: 'Evening run', updatedAt: DateTime.utc(2026, 3, 5)),
      ]);

      final written = await store.applyPulled(habits, <Map<String, Object?>>[
        remoteHabit(updatedAt: DateTime.utc(2026, 3, 4)),
      ]);

      expect(written, 0);
      expect((await readHabit('habit-1'))['name'], 'Evening run');
    });

    test('a tie goes to the row already here, and stays there', () async {
      // Called the same way every time, so a re-pull does not keep flipping it.
      await store.applyPulled(habits, <Map<String, Object?>>[
        remoteHabit(name: 'Evening run', updatedAt: DateTime.utc(2026, 3, 5)),
      ]);

      for (var attempt = 0; attempt < 3; attempt++) {
        await store.applyPulled(habits, <Map<String, Object?>>[
          remoteHabit(name: 'Morning run', updatedAt: DateTime.utc(2026, 3, 5)),
        ]);
        expect((await readHabit('habit-1'))['name'], 'Evening run');
      }
    });

    test('a null category never erases one that is here', () async {
      // The ambiguity `readOpenEnum` creates: a build that has not heard of a
      // category reads it as null, so "the user cleared it" and "that device
      // could not decode it" are the same value on the wire. Taking it at face
      // value erases categories every time an older build syncs.
      await store.applyPulled(habits, <Map<String, Object?>>[
        remoteHabit(category: 'exercise', updatedAt: DateTime.utc(2026, 3, 4)),
      ]);

      await store.applyPulled(habits, <Map<String, Object?>>[
        remoteHabit(
          name: 'Evening run',
          category: null,
          updatedAt: DateTime.utc(2026, 3, 5),
        ),
      ]);

      final row = await readHabit('habit-1');
      expect(row['category'], 'exercise', reason: 'null is no opinion');
      expect(row['name'], 'Evening run', reason: 'the rest of the row lands');
    });

    test('a category the device does know about still replaces one', () async {
      await store.applyPulled(habits, <Map<String, Object?>>[
        remoteHabit(category: 'exercise', updatedAt: DateTime.utc(2026, 3, 4)),
      ]);

      await store.applyPulled(habits, <Map<String, Object?>>[
        remoteHabit(category: 'walking', updatedAt: DateTime.utc(2026, 3, 5)),
      ]);

      expect((await readHabit('habit-1'))['category'], 'walking');
    });

    test('a row without the stamp cannot lift a deletion', () async {
      // The same one-way rule the server pins with a trigger. A device that
      // never heard about the deletion pushes a row carrying no deleted_at;
      // newer or not, it must not resurrect the habit.
      await store.applyPulled(habits, <Map<String, Object?>>[
        remoteHabit(
          updatedAt: DateTime.utc(2026, 3, 4),
          deletedAt: encodeDateTime(DateTime.utc(2026, 3, 4, 12)),
        ),
      ]);

      await store.applyPulled(habits, <Map<String, Object?>>[
        remoteHabit(name: 'Evening run', updatedAt: DateTime.utc(2026, 3, 5)),
      ]);

      final row = await readHabit('habit-1');
      expect(row['deleted_at'], isNotNull);
      expect(row['name'], 'Evening run');
    });

    test('an append-only event is a union: the first write stands', () async {
      await store.applyPulled(habits, <Map<String, Object?>>[
        remoteHabit(updatedAt: DateTime.utc(2026, 3, 4)),
      ]);

      Map<String, Object?> completion(bool wasNudged) => <String, Object?>{
        'habit_id': 'habit-1',
        'id': 'completion-1',
        'user_id': '11111111-0000-0000-0000-000000000001',
        'synced_at': encodeDateTime(DateTime.utc(2026, 3, 4, 9)),
        'completed_at': encodeDateTime(DateTime.utc(2026, 3, 4, 9)),
        'was_nudged': wasNudged,
        'source': 'tap',
      };

      expect(
        await store.applyPulled(completions, <Map<String, Object?>>[
          completion(false),
        ]),
        1,
      );
      expect(
        await store.applyPulled(completions, <Map<String, Object?>>[
          completion(true),
        ]),
        0,
        reason: 'a replayed event is the same event, not an edit',
      );

      final rows = await database.query(AppSchema.completions);
      expect(rows, hasLength(1));
      expect(rows.single['was_nudged'], 0);
    });
  });

  group('the pull cursor', () {
    test('is null until a pull has run', () async {
      expect(await store.cursorFor(habits), isNull);
    });

    test('remembers how far the pull got', () async {
      await store.setCursor(habits, DateTime.utc(2026, 3, 4, 9));

      expect(await store.cursorFor(habits), DateTime.utc(2026, 3, 4, 9));
    });

    test('only ever moves forward', () async {
      // A page that came back out of order, or a retry that re-read an earlier
      // window, must not wind it back and re-pull the world every cycle.
      await store.setCursor(habits, DateTime.utc(2026, 3, 4, 9));
      await store.setCursor(habits, DateTime.utc(2026, 3, 4, 8));

      expect(await store.cursorFor(habits), DateTime.utc(2026, 3, 4, 9));
    });

    test('is kept per table', () async {
      await store.setCursor(habits, DateTime.utc(2026, 3, 4, 9));

      expect(await store.cursorFor(completions), isNull);
    });
  });
}
