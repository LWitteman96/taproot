import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/core/models/nudge.dart';
import 'package:taproot/features/notifications/domain/notification_gateway.dart';
import 'package:taproot/features/notifications/domain/nudge_payload.dart';
import 'package:taproot/features/notifications/services/nudge_response_recorder.dart';

import '../../../../utils/fake_repositories.dart';
import '../../../../utils/store_contract.dart';
import '../../../../utils/store_fixtures.dart';

/// Answering a notification from the shade.
///
/// It runs with no UI and nobody waiting on it, which is exactly why the
/// failure paths matter: there is no screen to show an error on.
void main() {
  const habitId = 'habit-1';
  const nudgeId = 'nudge-1';

  late TestStore store;
  late NudgeResponseRecorder recorder;

  NudgeResponse response(NudgeResponseAction action, {String id = nudgeId}) =>
      NudgeResponse(
        payload: NudgePayload(nudgeId: id, habitId: habitId),
        action: action,
      );

  setUp(() async {
    store = await openFakeStore(TestClock(DateTime(2026, 3, 8, 20, 30)));
    await store.habits.saveHabit(testHabit(id: habitId));
    await store.nudges.saveNudge(
      NudgeRecord(
        id: nudgeId,
        habitId: habitId,
        expectedOccasionAt: DateTime(2026, 3, 9),
        sent: false,
      ),
    );
    await store.nudges.markSent(nudgeId);
    recorder = NudgeResponseRecorder(nudges: store.nudges);
  });

  Future<NudgeRecord> row() async =>
      (await store.nudges.nudgesFor(habitId)).single;

  test('"Yes" is recorded as a confirmation', () async {
    await recorder.record(response(NudgeResponseAction.confirmed));

    expect((await row()).confirmed, isTrue);
    expect((await row()).declined, isFalse);
  });

  test('"Different day" is recorded as a decline', () async {
    // A decline is data, not a failure — day-of-week preference falls out of
    // these within a fortnight (growth spec §8).
    await recorder.record(response(NudgeResponseAction.declined));

    expect((await row()).declined, isTrue);
    expect((await row()).confirmed, isFalse);
  });

  test('opening the check-in is not an answer to it', () async {
    await recorder.record(response(NudgeResponseAction.opened));

    expect((await row()).confirmed, isFalse);
    expect((await row()).declined, isFalse);
  });

  test('neither answer touches whether the nudge was sent', () async {
    // `sent` is what autonomy's denominator is built from. An answer says
    // something about the user; it must never restate what the scheduler did.
    await recorder.record(response(NudgeResponseAction.confirmed));

    expect((await row()).sent, isTrue);
  });

  test('an answer for a row that is gone is survived, not thrown', () async {
    // The habit was deleted on another device while the notification sat in
    // the OS queue. Expected but abnormal, and deliberately not an error
    // report — there is no screen to show it on and nothing was lost.
    await expectLater(
      recorder.record(
        response(NudgeResponseAction.confirmed, id: 'no-such-nudge'),
      ),
      completes,
    );
  });
}
