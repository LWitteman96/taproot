import 'package:taproot/features/notifications/domain/notification_access.dart';
import 'package:taproot/features/notifications/domain/notification_gateway.dart';
import 'package:taproot/features/notifications/services/nudge_scheduler.dart';

/// An in-memory notification platform.
///
/// It behaves like the real one in the two ways the scheduler depends on:
/// queueing the same notification id twice **replaces** the pending
/// notification rather than doubling it, and a refused schedule throws rather
/// than returning quietly.
class FakeNotificationGateway implements NotificationGateway {
  FakeNotificationGateway({
    NotificationAccess access = const NotificationAccess(
      mode: NotificationMode.granted,
    ),
  }) : _access = access;

  NotificationAccess _access;

  /// Set to have the next [schedule] throw — the platform refusing a
  /// notification mid-pass.
  bool failNextSchedule = false;

  /// Set to have [requestAccess] throw — the plugin failing to initialise, or
  /// the permission channel failing under it.
  bool failRequestAccess = false;

  /// The answer the app was launched by, if any.
  NudgeResponse? launchedBy;

  int initializeCalls = 0;

  final Map<int, ScheduledNudge> queued = <int, ScheduledNudge>{};
  final List<ScheduledNudge> everyScheduleCall = <ScheduledNudge>[];
  final List<int> cancelled = <int>[];

  void grant(NotificationAccess access) => _access = access;

  /// The notification queued for a ledger row, or null.
  ScheduledNudge? forNudge(String nudgeId) =>
      queued[notificationIdFor(nudgeId)];

  @override
  Future<void> initialize() async => initializeCalls++;

  @override
  Future<NotificationAccess> currentAccess() async => _access;

  @override
  Future<NotificationAccess> requestAccess() async {
    if (failRequestAccess) {
      throw StateError('the notifications plugin could not be initialised');
    }
    return _access;
  }

  @override
  Future<void> schedule(ScheduledNudge nudge) async {
    if (failNextSchedule) {
      failNextSchedule = false;
      throw StateError('the platform refused the notification');
    }
    everyScheduleCall.add(nudge);
    queued[nudge.notificationId] = nudge;
  }

  @override
  Future<NudgeResponse?> launchResponse() async => launchedBy;

  @override
  Future<void> cancel(int notificationId) async {
    cancelled.add(notificationId);
    queued.remove(notificationId);
  }

  @override
  Future<Set<int>> pendingNotificationIds() async => queued.keys.toSet();
}
