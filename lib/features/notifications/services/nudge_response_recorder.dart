import 'package:logging/logging.dart';

import 'package:taproot/app/database/store_exceptions.dart';
import 'package:taproot/features/notifications/domain/notification_gateway.dart';
import 'package:taproot/features/notifications/domain/nudge_payload.dart';
import 'package:taproot/features/notifications/domain/nudge_repository.dart';

/// Writes a notification answer back to the ledger.
///
/// `Yes` and `Different day` are answerable from the shade without opening the
/// app (guide §14), so this runs with no UI and no user waiting on it. It
/// records and returns; deciding what the answer *means* — a declined
/// Thursday becoming "is Wednesday better?" (growth spec §8) — belongs to the
/// renegotiation and insight surfaces reading the same rows later.
class NudgeResponseRecorder {
  const NudgeResponseRecorder({required NudgeRepository nudges})
    : _nudges = nudges;

  static final Logger _log = Logger('NudgeResponseRecorder');

  final NudgeRepository _nudges;

  Future<void> record(NudgeResponse response) async {
    try {
      switch (response.action) {
        case NudgeResponseAction.confirmed:
          await _nudges.markConfirmed(response.payload.nudgeId);
        case NudgeResponseAction.declined:
          await _nudges.markDeclined(response.payload.nudgeId);
        case NudgeResponseAction.opened:
          // Opening the check-in is not an answer to it. The reflection stage
          // owns what happens on the screen the tap lands on.
          break;
      }
    } on UnknownNudgeException catch (error) {
      // Expected-but-abnormal, and deliberately not an error-budget event: a
      // notification outlives the row it belongs to whenever the habit was
      // deleted on another device while the nudge sat in the OS queue.
      _log.info('answer for a nudge that is no longer in the ledger: $error');
    }
  }
}
