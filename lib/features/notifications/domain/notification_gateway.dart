import 'package:meta/meta.dart';

import 'package:taproot/features/notifications/domain/evening_check_in.dart';
import 'package:taproot/features/notifications/domain/notification_access.dart';
import 'package:taproot/features/notifications/domain/nudge_payload.dart';

/// One notification queued with the operating system.
@immutable
class ScheduledNudge {
  const ScheduledNudge({
    required this.notificationId,
    required this.payload,
    required this.checkIn,
    required this.deliverAt,
  });

  /// The platform's handle on this notification. Derived from the ledger row
  /// id (see `notificationIdFor`) so that re-scheduling the same occasion
  /// replaces its notification instead of queueing a second one.
  final int notificationId;

  final NudgePayload payload;
  final EveningCheckIn checkIn;

  /// Local wall-clock time. Not UTC: the evening check-in is at 20:00 *where
  /// the user is*, and a DST change must move it with the clock.
  final DateTime deliverAt;

  @override
  String toString() =>
      'ScheduledNudge($notificationId, ${payload.nudgeId}, $deliverAt)';
}

/// A notification the user answered.
@immutable
class NudgeResponse {
  const NudgeResponse({required this.payload, required this.action});

  final NudgePayload payload;
  final NudgeResponseAction action;

  @override
  String toString() => 'NudgeResponse(${payload.nudgeId}, ${action.name})';
}

/// Everything the scheduler needs from the platform, and nothing else.
///
/// The interface exists so the scheduling *decisions* — who gets nudged, when,
/// and which occasions are deliberately left silent — are testable without a
/// device. Those decisions are the part that can be wrong in a way nobody
/// notices; `flutter_local_notifications` either posts a notification or it
/// does not.
///
/// Implementations must be idempotent on [schedule]: queueing the same
/// [ScheduledNudge.notificationId] twice replaces the pending notification
/// rather than doubling it, because every planning pass re-offers occasions it
/// has already queued.
abstract class NotificationGateway {
  /// Loads the timezone database and registers the response handler. Safe to
  /// call more than once.
  Future<void> initialize();

  /// What the app is currently allowed to do, without prompting.
  Future<NotificationAccess> currentAccess();

  /// Prompts for notification permission. A designed onboarding moment — never
  /// call it speculatively on launch.
  Future<NotificationAccess> requestAccess();

  Future<void> schedule(ScheduledNudge nudge);

  Future<void> cancel(int notificationId);

  /// Ids the OS is still holding. Used to reconcile the ledger against the
  /// queue after the app has been away.
  Future<Set<int>> pendingNotificationIds();
}
