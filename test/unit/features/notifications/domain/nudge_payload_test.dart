import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/features/notifications/domain/nudge_payload.dart';

/// The payload a notification carries back when it is answered.
///
/// It is the only thing that survives the trip: an answer can arrive hours
/// after the app died, in a background isolate with no providers, so anything
/// not in the payload is not available to record the answer with.
void main() {
  group('round trip', () {
    test('a payload survives encoding', () {
      const payload = NudgePayload(nudgeId: 'nudge-1', habitId: 'habit-1');

      expect(NudgePayload.decode(payload.encode()), payload);
    });

    test('ids with the separator in them are rejected, not mis-parsed', () {
      // UUIDs never contain a slash, so this cannot happen today — but a
      // decoder that silently returned the wrong habit if it ever did is the
      // kind of bug that surfaces as somebody else's ledger row.
      const payload = NudgePayload(nudgeId: 'nudge/1', habitId: 'habit-1');

      expect(NudgePayload.decode(payload.encode()), isNull);
    });
  });

  group('payloads outlive the build that wrote them', () {
    test('an unversioned or foreign payload decodes to null', () {
      // A notification scheduled last week is parsed by whatever version of
      // the app is installed when it fires. An unrecognised shape has to be
      // *identified* as unrecognised rather than mapped onto the wrong row.
      for (final raw in <String?>[
        null,
        '',
        'nudge-1',
        'nudge/v2/nudge-1/habit-1',
        'reflection/v1/nudge-1/habit-1',
        'nudge/v1/nudge-1',
        'nudge/v1//habit-1',
      ]) {
        expect(NudgePayload.decode(raw), isNull, reason: 'decoding "$raw"');
      }
    });
  });

  group('actions', () {
    test('the two answers map to the two ledger marks', () {
      expect(
        NudgeActionIds.actionFor(NudgeActionIds.confirm),
        NudgeResponseAction.confirmed,
      );
      expect(
        NudgeActionIds.actionFor(NudgeActionIds.decline),
        NudgeResponseAction.declined,
      );
    });

    test('tapping the notification body is an open, not an answer', () {
      // Both platforms report a body tap as an absent action id. Reading that
      // as a confirmation would record an implementation intention the user
      // never made.
      expect(NudgeActionIds.actionFor(null), NudgeResponseAction.opened);
      expect(NudgeActionIds.actionFor(''), NudgeResponseAction.opened);
    });

    test('an unknown action is null rather than a default', () {
      expect(NudgeActionIds.actionFor('snooze'), isNull);
    });
  });
}
