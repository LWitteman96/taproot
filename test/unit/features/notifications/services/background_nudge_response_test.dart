import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:taproot/app/database/app_database.dart';
import 'package:taproot/core/models/nudge.dart';
import 'package:taproot/features/notifications/domain/nudge_payload.dart';
import 'package:taproot/features/notifications/services/background_nudge_response.dart';
import 'package:taproot/features/notifications/services/local_nudge_service.dart';

import '../../../../utils/store_fixtures.dart';

/// Answering the check-in from the shade while the app is not running.
///
/// This is the common case for a 20:00 notification, not the edge case, and
/// the failure mode is silent: with no background handler the platform hands
/// the answer to an isolate nobody is listening on and the ledger simply never
/// records it. So the path is tested over the real SQLite store — the point of
/// the code is that it can write a row with no providers and no widget tree.
void main() {
  const habitId = 'habit-1';
  const nudgeId = 'nudge-1';

  late Directory directory;
  late String path;
  var opens = 0;

  NotificationResponse shadeAnswer(
    String? actionId, {
    String? payload = 'nudge/v1/$nudgeId/$habitId',
  }) => NotificationResponse(
    notificationResponseType:
        NotificationResponseType.selectedNotificationAction,
    actionId: actionId,
    payload: payload,
  );

  /// A handle on the same database *file*, which is the whole point.
  ///
  /// The in-memory test database cannot stand in here: every open gives back a
  /// private store, so a handler writing to one and the app reading from
  /// another would both pass and prove nothing. Two isolates share a file, so
  /// the test does too — and the handler closes the handle it opened, exactly
  /// as it does on a device.
  Future<Database> open() {
    opens++;
    return openAppDatabase(databaseFactory: databaseFactoryFfi, path: path);
  }

  setUp(() async {
    sqfliteFfiInit();
    opens = 0;
    directory = await Directory.systemTemp.createTemp('taproot-background');
    path = p.join(directory.path, 'taproot.db');

    final seed = await open();
    await seed.insert(
      AppSchema.habits,
      toRow(testHabit(id: habitId).toJson())
        ..addAll(<String, Object?>{'updated_at': '2026-03-08T10:00:00.000Z'}),
    );
    final store = LocalNudgeService(database: seed);
    await store.saveNudge(
      NudgeRecord(
        id: nudgeId,
        habitId: habitId,
        expectedOccasionAt: DateTime(2026, 3, 9),
        sent: false,
      ),
    );
    await store.markSent(nudgeId);
    await seed.close();
    opens = 0;
  });

  tearDown(() => directory.delete(recursive: true));

  /// Reads the row back the way the main isolate would: from the file, through
  /// a handle the handler never touched.
  Future<NudgeRecord> row() async {
    final reader = await open();
    final rows = await reader.query(
      AppSchema.nudges,
      where: 'id = ?',
      whereArgs: <Object?>[nudgeId],
    );
    await reader.close();
    return NudgeRecord.fromJson(rows.single);
  }

  test('"Yes" from the shade reaches the ledger with no app running', () async {
    await recordBackgroundNudgeResponse(
      shadeAnswer(NudgeActionIds.confirm),
      openDatabase: open,
    );

    expect((await row()).confirmed, isTrue);
  });

  test('"Different day" does too', () async {
    await recordBackgroundNudgeResponse(
      shadeAnswer(NudgeActionIds.decline),
      openDatabase: open,
    );

    expect((await row()).declined, isTrue);
  });

  test('neither answer disturbs whether the nudge was sent', () async {
    // `sent` is autonomy's denominator. An answer says something about the
    // user; it must never restate what the scheduler did.
    await recordBackgroundNudgeResponse(
      shadeAnswer(NudgeActionIds.confirm),
      openDatabase: open,
    );

    expect((await row()).sent, isTrue);
  });

  test('a body tap opens no database at all', () async {
    // Opening the store to record that a notification was tapped, and then
    // doing nothing with it, would be the most expensive no-op in the app.
    await recordBackgroundNudgeResponse(shadeAnswer(null), openDatabase: open);

    expect(opens, 0);
  });

  group('it survives what a background isolate cannot report', () {
    test('an unrecognised payload', () async {
      await expectLater(
        recordBackgroundNudgeResponse(
          shadeAnswer(NudgeActionIds.confirm, payload: 'nudge/v9/a/b'),
          openDatabase: open,
        ),
        completes,
      );
    });

    test('an answer for a row that is gone', () async {
      final store = await open();
      await store.delete(
        AppSchema.nudges,
        where: 'id = ?',
        whereArgs: <Object?>[nudgeId],
      );
      await store.close();

      await expectLater(
        recordBackgroundNudgeResponse(
          shadeAnswer(NudgeActionIds.confirm),
          openDatabase: open,
        ),
        completes,
      );
    });

    test('a store that will not open', () async {
      // There is no screen to show this on and the isolate is about to end
      // either way, so it is logged and swallowed rather than thrown out of
      // an isolate nobody is watching.
      await expectLater(
        recordBackgroundNudgeResponse(
          shadeAnswer(NudgeActionIds.confirm),
          openDatabase: () async => throw StateError('no store here'),
        ),
        completes,
      );
    });
  });
}
