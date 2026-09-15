import 'package:taproot/features/notifications/domain/notification_access.dart';
import 'package:taproot/features/notifications/domain/notification_gateway.dart';

/// The gateway on a platform that cannot post local notifications.
///
/// Every call succeeds and does nothing, and access reports [NotificationMode.denied]
/// — which is not a fiction: a build with no notification platform behind it
/// genuinely cannot nudge, and that is a mode the app already has to handle
/// (guide §2). Occasions still get ledger rows, so the engine keeps measuring.
///
/// It exists so the desktop test host is not a special case threaded through
/// startup. Without it every `ProviderContainer` test that touches startup
/// would have to know that the notification plugin has no host implementation.
class DisabledNotificationGateway implements NotificationGateway {
  const DisabledNotificationGateway();

  @override
  Future<void> initialize() async {}

  @override
  Future<NotificationAccess> currentAccess() async => NotificationAccess.denied;

  @override
  Future<NotificationAccess> requestAccess() async => NotificationAccess.denied;

  @override
  Future<void> schedule(ScheduledNudge nudge) async {}

  @override
  Future<void> cancel(int notificationId) async {}

  @override
  Future<Set<int>> pendingNotificationIds() async => const <int>{};
}
