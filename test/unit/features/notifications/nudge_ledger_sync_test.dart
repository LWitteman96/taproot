import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/app/database/app_database.dart';
import 'package:taproot/app/sync/local_sync_store.dart';
import 'package:taproot/app/sync/sync_tables.dart';
import 'package:taproot/core/models/nudge.dart';
import 'package:taproot/core/utils/json_codec.dart';
import 'package:taproot/features/habits/services/local_habit_service.dart';
import 'package:taproot/features/notifications/services/local_nudge_service.dart';

import '../../../utils/store_fixtures.dart';

/// The duplicate-occasion path end to end: a row arrives from another device
/// through sync, and the ledger's reader is what stops it being counted twice.
///
/// Worth its own file rather than folding into the unit tests for the collapse,
/// because the interesting part is the *seam*. `saveNudge` refuses a second row
/// for one local date, so the only way to get one is the path that does not go
/// through it — `LocalSyncStore.applyPulled`, which writes rows by key. A test
/// that builds the duplicate by hand proves the merge; this proves the merge is
/// reached by the thing that actually creates duplicates.
void main() {
  late Database database;
  late LocalHabitService habits;
  late LocalNudgeService nudges;
  late LocalSyncStore sync;
  late TestClock clock;

  final SyncTable nudgeTable = syncTables.firstWhere(
    (table) => table.name == AppSchema.nudges,
  );

  setUp(() async {
    clock = TestClock(DateTime(2026, 3, 4, 9));
    database = await openTestDatabase();
    habits = LocalHabitService(database: database, clock: clock.call);
    nudges = LocalNudgeService(database: database, clock: clock.call);
    sync = LocalSyncStore(database: database);
    addTearDown(database.close);

    await habits.saveHabit(testHabit(id: 'habit-1'));
  });

  /// A nudge row as the server hands it back.
  Map<String, Object?> remoteNudge({
    required String id,
    required DateTime expectedOccasionAt,
    bool sent = false,
    bool confirmed = false,
  }) => <String, Object?>{
    'id': id,
    'habit_id': 'habit-1',
    'user_id': '11111111-0000-0000-0000-000000000001',
    'synced_at': encodeDateTime(clock.now),
    'expected_occasion_at': encodeDateTime(expectedOccasionAt),
    'scheduled_for': null,
    'sent': sent,
    'confirmed': confirmed,
    'declined': false,
    'updated_at': encodeDateTime(clock.now),
  };

  test('the ledger refuses a second row for one occasion itself', () async {
    // The rule the write path already enforces, and the reason a duplicate can
    // only ever arrive the other way.
    await nudges.saveNudge(
      NudgeRecord(
        id: 'from-phone',
        habitId: 'habit-1',
        expectedOccasionAt: DateTime(2026, 3, 4, 19),
        sent: true,
      ),
    );

    await expectLater(
      nudges.saveNudge(
        NudgeRecord(
          id: 'from-tablet',
          habitId: 'habit-1',
          expectedOccasionAt: DateTime(2026, 3, 4, 20),
          sent: false,
        ),
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('a duplicate pulled from another device is counted once', () async {
    await nudges.saveNudge(
      NudgeRecord(
        id: 'aaa-from-phone',
        habitId: 'habit-1',
        expectedOccasionAt: DateTime(2026, 3, 4, 19),
        sent: false,
      ),
    );

    // Sync writes by key, so it does not meet the duplicate check above.
    final written = await sync.applyPulled(nudgeTable, <Map<String, Object?>>[
      remoteNudge(
        id: 'zzz-from-tablet',
        expectedOccasionAt: DateTime(2026, 3, 4, 21),
        sent: true,
      ),
    ]);
    expect(written, 1, reason: 'the row really does land in the table');

    final rows = await database.query(AppSchema.nudges);
    expect(rows, hasLength(2), reason: 'two rows, one occasion');

    final ledger = await nudges.nudgesFor('habit-1');
    expect(
      ledger,
      hasLength(1),
      reason:
          'autonomy counts these as its denominator, so two entries for an '
          'occasion that happened once halves it',
    );
    expect(ledger.single.id, 'aaa-from-phone', reason: 'lowest id is stable');
    expect(
      ledger.single.sent,
      isTrue,
      reason: 'the other device queued a notification, so one was queued',
    );
  });

  test('two genuine occasions are still two', () async {
    await nudges.saveNudge(
      NudgeRecord(
        id: 'aaa',
        habitId: 'habit-1',
        expectedOccasionAt: DateTime(2026, 3, 4, 19),
        sent: true,
      ),
    );
    await sync.applyPulled(nudgeTable, <Map<String, Object?>>[
      remoteNudge(id: 'bbb', expectedOccasionAt: DateTime(2026, 3, 5, 19)),
    ]);

    expect(await nudges.nudgesFor('habit-1'), hasLength(2));
  });

  test('a re-pull of the same duplicate changes nothing', () async {
    // The reason this is a read-time collapse rather than a delete: no client
    // role has DELETE, so the duplicate is permanent on the server and comes
    // back every cycle. Dropping it locally would undo itself.
    await nudges.saveNudge(
      NudgeRecord(
        id: 'aaa-from-phone',
        habitId: 'habit-1',
        expectedOccasionAt: DateTime(2026, 3, 4, 19),
        sent: false,
      ),
    );
    final duplicate = <Map<String, Object?>>[
      remoteNudge(
        id: 'zzz-from-tablet',
        expectedOccasionAt: DateTime(2026, 3, 4, 21),
        sent: true,
      ),
    ];

    for (var cycle = 0; cycle < 3; cycle++) {
      await sync.applyPulled(nudgeTable, duplicate);
      final ledger = await nudges.nudgesFor('habit-1');
      expect(ledger, hasLength(1));
      expect(ledger.single.id, 'aaa-from-phone');
      expect(ledger.single.sent, isTrue);
    }
  });
}
