import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/app/database/app_database.dart';
import 'package:taproot/app/sync/local_sync_store.dart';
import 'package:taproot/app/sync/remote_sync_store.dart';
import 'package:taproot/app/sync/sync_tables.dart';
import 'package:taproot/app/sync/two_way_sync_drain.dart';
import 'package:taproot/core/utils/json_codec.dart';

import '../../../utils/store_fixtures.dart';

/// A server the test owns: rows in, pages out.
///
/// Holds them the way the real one does — keyed, so an upsert of a row it
/// already has is an update — and stamps `synced_at` off a clock the test
/// moves, because the pull's whole job is to range over that column.
class FakeRemoteSyncStore implements RemoteSyncStore {
  FakeRemoteSyncStore({required this.clock});

  final TestClock clock;

  @override
  String? currentUserId = 'user-1';

  /// Every row the server holds, by table then key.
  final Map<String, Map<String, Map<String, Object?>>> tables =
      <String, Map<String, Map<String, Object?>>>{};

  /// Pages served, so a test can assert the pull actually paged.
  int pullRequests = 0;

  /// Tables in the order they were pushed to, so a test can assert habits
  /// went first.
  final List<String> pushOrder = <String>[];

  Object? pushFailure;

  Map<String, Map<String, Object?>> _tableOf(SyncTable table) =>
      tables.putIfAbsent(table.name, () => <String, Map<String, Object?>>{});

  /// Puts a row on the server as though another device had pushed it.
  void seed(SyncTable table, Map<String, Object?> row, {DateTime? syncedAt}) {
    _tableOf(table)[table.keyOf(row)] = <String, Object?>{
      ...row,
      'synced_at': encodeDateTime(syncedAt ?? clock.now),
    };
  }

  /// Enforces the same last-write-wins rule the `reject_stale_update` trigger
  /// does, so a test exercises what the server actually answers rather than a
  /// fake that is more forgiving than production.
  ///
  /// All-or-nothing, like the real upsert: one stale row fails the batch.
  @override
  Future<void> push(SyncTable table, List<Map<String, Object?>> rows) async {
    if (pushFailure case final failure?) throw failure;
    if (rows.isEmpty) return;
    pushOrder.add(table.name);

    if (table.isMutable) {
      for (final row in rows) {
        final existing = _tableOf(table)[table.keyOf(row)];
        if (existing == null) continue;
        final incomingAt = requireDateTime(row, 'updated_at');
        // Strictly older only — an equal replay is what sync does all day.
        if (incomingAt.isBefore(requireDateTime(existing, 'updated_at'))) {
          throw StaleRowRejected(table.name, 'stale write to ${table.name}');
        }
      }
    }

    for (final row in rows) {
      _tableOf(table)[table.keyOf(row)] = <String, Object?>{
        ...row,
        'synced_at': encodeDateTime(clock.now),
      };
    }
  }

  @override
  Future<List<Map<String, Object?>>> pullPage(
    SyncTable table, {
    required DateTime since,
    required int limit,
  }) async {
    pullRequests++;
    final rows = _tableOf(table).values.toList()
      ..sort(
        (a, b) => requireDateTime(
          a,
          'synced_at',
        ).compareTo(requireDateTime(b, 'synced_at')),
      );

    final matching = rows
        .where((row) => !requireDateTime(row, 'synced_at').isBefore(since))
        .toList();
    return matching.take(limit).toList();
  }
}

Map<String, Object?> habitRow({
  required String id,
  String name = 'Morning run',
  required DateTime updatedAt,
}) => <String, Object?>{
  'id': id,
  'user_id': 'user-1',
  'name': name,
  'identity_statement': null,
  'plant_type': 'oak',
  'target_frequency': 3,
  'journey': 'design',
  'category': 'exercise',
  'designed_cue': 'after the kettle boils',
  'designed_cue_type': 'event',
  'routine': 'twice round the block',
  'reward': 'coffee',
  'created_at': encodeDateTime(DateTime.utc(2026, 3, 1)),
  'graduated_at': null,
  'updated_at': encodeDateTime(updatedAt),
  'deleted_at': null,
};

void main() {
  late Database database;
  late LocalSyncStore local;
  late FakeRemoteSyncStore remote;
  late TwoWaySyncDrain drain;
  late TestClock clock;

  final SyncTable habits = syncTables.firstWhere(
    (table) => table.name == AppSchema.habits,
  );
  final SyncTable completions = syncTables.firstWhere(
    (table) => table.name == AppSchema.completions,
  );

  setUp(() async {
    clock = TestClock(DateTime.utc(2026, 3, 4, 9));
    database = await openTestDatabase();
    local = LocalSyncStore(database: database);
    remote = FakeRemoteSyncStore(clock: clock);
    drain = TwoWaySyncDrain(local: local, remote: remote);
    addTearDown(database.close);
  });

  /// Writes a habit to the device, queued for push.
  Future<void> insertLocalHabit({
    required String id,
    String name = 'Morning run',
    required DateTime updatedAt,
    int pendingSync = 1,
  }) async {
    final row = habitRow(id: id, name: name, updatedAt: updatedAt)
      ..remove('user_id');
    await database.insert(
      AppSchema.habits,
      toRow(row)..['pending_sync'] = pendingSync,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  group('signed out', () {
    test('is not a failure, and leaves the queue alone', () async {
      remote.currentUserId = null;
      await insertLocalHabit(id: 'habit-1', updatedAt: clock.now);

      await drain.drain();

      expect(remote.tables, isEmpty);
      expect(
        await local.pendingRows(habits),
        hasLength(1),
        reason: 'the queue keeps until there is somewhere to send it',
      );
    });
  });

  group('the push', () {
    test('sends queued rows and takes them off the queue', () async {
      await insertLocalHabit(id: 'habit-1', updatedAt: clock.now);

      await drain.drain();

      expect(remote.tables[AppSchema.habits], hasLength(1));
      expect(await local.pendingRows(habits), isEmpty);
    });

    test('stamps every row with the signed-in user', () async {
      // RLS is `user_id = auth.uid()` on every table, and the device carries no
      // such column — a row without it is rejected rather than misfiled.
      await insertLocalHabit(id: 'habit-1', updatedAt: clock.now);

      await drain.drain();

      expect(
        remote.tables[AppSchema.habits]!.values.single['user_id'],
        'user-1',
      );
    });

    test('sends habits before the rows that hang off them', () async {
      // Every child table has a composite foreign key into habits, so on a
      // first sync — where both are new — the wrong order is a 23503.
      await insertLocalHabit(id: 'habit-1', updatedAt: clock.now);
      await database.insert(AppSchema.completions, <String, Object?>{
        'habit_id': 'habit-1',
        'id': 'completion-1',
        'completed_at': encodeDateTime(clock.now),
        'was_nudged': 0,
        'source': 'tap',
        'pending_sync': 1,
      });

      await drain.drain();

      expect(
        remote.pushOrder.indexOf(AppSchema.habits),
        lessThan(remote.pushOrder.indexOf(AppSchema.completions)),
      );
    });

    test('a failure leaves the queue intact for the next attempt', () async {
      await insertLocalHabit(id: 'habit-1', updatedAt: clock.now);
      remote.pushFailure = StateError('the network went away');

      await expectLater(drain.drain(), throwsStateError);

      expect(await local.pendingRows(habits), hasLength(1));
    });
  });

  group('the pull', () {
    test('brings down a row written on another device', () async {
      remote.seed(habits, habitRow(id: 'habit-2', updatedAt: clock.now));

      await drain.drain();

      final rows = await database.query(AppSchema.habits);
      expect(rows, hasLength(1));
      expect(rows.single['id'], 'habit-2');
      expect(
        rows.single['pending_sync'],
        0,
        reason: 'it came from the server; sending it back is an echo',
      );
    });

    test('pages rather than trusting one response', () async {
      // PostgREST truncates at max_rows and says nothing about it, so a pull
      // that treats one response as the whole answer silently loses the rest.
      for (var index = 0; index < syncPageSize + 20; index++) {
        clock.advance(const Duration(milliseconds: 1));
        remote.seed(habits, habitRow(id: 'habit-$index', updatedAt: clock.now));
      }

      await drain.drain();

      expect(
        await database.query(AppSchema.habits),
        hasLength(syncPageSize + 20),
      );
      expect(remote.pullRequests, greaterThan(syncTables.length));
    });

    test('a second drain re-reads only the overlap window', () async {
      remote.seed(habits, habitRow(id: 'habit-2', updatedAt: clock.now));
      await drain.drain();

      final cursor = await local.cursorFor(habits);
      expect(cursor, isNotNull);

      // Well past the overlap, so the row is behind the window now.
      clock.advance(const Duration(minutes: 5));
      remote.pullRequests = 0;
      await drain.drain();

      expect(
        await local.cursorFor(habits),
        cursor,
        reason: 'nothing new, so the cursor stays where it was',
      );
    });

    test('a row that commits late is still caught', () async {
      // The commit-time gap the overlap window exists for: synced_at is
      // stamped when the row is written, but the row is only visible once its
      // transaction commits. A cursor moved exactly to the read time would
      // step over this row permanently.
      remote.seed(habits, habitRow(id: 'habit-2', updatedAt: clock.now));
      await drain.drain();
      final cursor = await local.cursorFor(habits);

      // Stamped just before the cursor, but only now visible.
      remote.seed(
        habits,
        habitRow(id: 'habit-late', updatedAt: clock.now),
        syncedAt: cursor!.subtract(const Duration(seconds: 5)),
      );

      await drain.drain();

      final ids = (await database.query(
        AppSchema.habits,
      )).map((row) => row['id']).toSet();
      expect(ids, contains('habit-late'));
    });

    test('the cursor only moves forward', () async {
      remote.seed(habits, habitRow(id: 'habit-2', updatedAt: clock.now));
      await drain.drain();
      final cursor = await local.cursorFor(habits);

      // An older row appearing does not wind the cursor back to its stamp.
      remote.seed(
        habits,
        habitRow(id: 'habit-old', updatedAt: clock.now),
        syncedAt: clock.now.subtract(const Duration(seconds: 10)),
      );
      await drain.drain();

      expect(await local.cursorFor(habits), cursor);
    });

    test('is kept per table', () async {
      remote.seed(habits, habitRow(id: 'habit-2', updatedAt: clock.now));

      await drain.drain();

      expect(await local.cursorFor(habits), isNotNull);
      expect(
        await local.cursorFor(completions),
        isNull,
        reason: 'no completion has ever been seen, so there is nothing to mark',
      );
    });
  });

  group('pull before push', () {
    test(
      'a stale local edit never overwrites a newer one from elsewhere',
      () async {
        // The ordering argument, and the case that decides it. The upsert is
        // unconditional — PostgREST has no "only if newer" — so the server takes
        // whatever it is last sent. Pushing first would send this device's older
        // row straight over the newer one, and that edit is gone for good with
        // nothing anywhere to notice.
        await insertLocalHabit(
          id: 'habit-1',
          name: 'what this device last saw',
          updatedAt: DateTime.utc(2026, 3, 4),
        );

        // Another device edited it later, and got there first.
        remote.seed(
          habits,
          habitRow(
            id: 'habit-1',
            name: 'renamed on the other device',
            updatedAt: DateTime.utc(2026, 3, 5),
          ),
        );

        await drain.drain();

        expect(
          remote.tables[AppSchema.habits]!.values.single['name'],
          'renamed on the other device',
          reason: 'the newer edit survives on the server',
        );
        expect(
          (await database.query(AppSchema.habits)).single['name'],
          'renamed on the other device',
          reason:
              'and this device takes it, which is what last-write-wins means',
        );
        expect(
          await local.pendingRows(habits),
          isEmpty,
          reason:
              'the losing row came off the queue with it, so a later drain '
              'cannot resurrect it',
        );
      },
    );

    test('a newer local edit still wins and is sent', () async {
      // The other half: pulling first must not cost this device an edit that
      // genuinely is the latest.
      remote.seed(
        habits,
        habitRow(
          id: 'habit-1',
          name: 'what the server had',
          updatedAt: DateTime.utc(2026, 3, 4),
        ),
      );
      await insertLocalHabit(
        id: 'habit-1',
        name: 'edited here, later',
        updatedAt: DateTime.utc(2026, 3, 5),
      );

      await drain.drain();

      expect(
        remote.tables[AppSchema.habits]!.values.single['name'],
        'edited here, later',
      );
      expect(
        (await database.query(AppSchema.habits)).single['name'],
        'edited here, later',
      );
    });

    test('a row overtaken between the pull and the push is not sent', () async {
      // The window the ordering cannot close, which is why the server enforces
      // the rule too. The push is what discovers it, and the answer is 409.
      remote.seed(
        habits,
        habitRow(
          id: 'habit-1',
          name: 'from the other device',
          updatedAt: DateTime.utc(2026, 3, 6),
        ),
        // Behind the cursor this drain will end up with, so the pull does not
        // see it and cannot reconcile it away first.
        syncedAt: DateTime.utc(2020),
      );
      await insertLocalHabit(
        id: 'habit-1',
        name: 'stale, pushed anyway',
        updatedAt: DateTime.utc(2026, 3, 4),
      );

      await drain.drain();

      expect(
        remote.tables[AppSchema.habits]!.values.single['name'],
        'from the other device',
        reason: 'the server refused the stale row rather than taking it',
      );
      expect(
        await local.pendingRows(habits),
        isEmpty,
        reason: 'and it is off the queue, not retried on every drain forever',
      );
    });

    test('one overtaken row does not cost the rest of its batch', () async {
      // An upsert is all-or-nothing, so a single loser fails the whole page.
      // The others are perfectly good writes that happened to travel with it.
      remote.seed(
        habits,
        habitRow(
          id: 'habit-1',
          name: 'from the other device',
          updatedAt: DateTime.utc(2026, 3, 6),
        ),
        syncedAt: DateTime.utc(2020),
      );
      await insertLocalHabit(
        id: 'habit-1',
        name: 'stale',
        updatedAt: DateTime.utc(2026, 3, 4),
      );
      await insertLocalHabit(
        id: 'habit-2',
        name: 'perfectly good',
        updatedAt: DateTime.utc(2026, 3, 4),
      );

      await drain.drain();

      expect(
        remote.tables[AppSchema.habits]!['habit-2']!['name'],
        'perfectly good',
        reason: 'the innocent row in the batch still got through',
      );
      expect(
        remote.tables[AppSchema.habits]!['habit-1']!['name'],
        'from the other device',
      );
    });

    test('an equal replay is accepted rather than rejected', () async {
      // The overlap window re-reads covered ground and a retried push resends
      // a batch verbatim, so an identical row arriving again is the normal
      // case, not an anomaly.
      await insertLocalHabit(
        id: 'habit-1',
        updatedAt: DateTime.utc(2026, 3, 4),
      );
      await drain.drain();

      await database.update(
        AppSchema.habits,
        <String, Object?>{'pending_sync': 1},
        where: 'id = ?',
        whereArgs: <Object?>['habit-1'],
      );

      await expectLater(drain.drain(), completes);
      expect(await local.pendingRows(habits), isEmpty);
    });

    test('an append-only event is unaffected by the ordering', () async {
      // Completions merge as a union on a key the device minted, so there is
      // no newer and older to get wrong — the tap made offline is kept either
      // way, which is the guarantee that matters most.
      await insertLocalHabit(id: 'habit-1', updatedAt: clock.now);
      await database.insert(AppSchema.completions, <String, Object?>{
        'habit_id': 'habit-1',
        'id': 'completion-1',
        'completed_at': encodeDateTime(clock.now),
        'was_nudged': 0,
        'source': 'tap',
        'pending_sync': 1,
      });

      await drain.drain();

      expect(remote.tables[AppSchema.completions], hasLength(1));
      expect(await local.pendingRows(completions), isEmpty);
    });
  });
}
