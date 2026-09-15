import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logging/logging.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import 'package:taproot/features/notifications/domain/notification_access.dart';
import 'package:taproot/features/notifications/domain/notification_gateway.dart';
import 'package:taproot/features/notifications/domain/nudge_payload.dart';

/// `flutter_local_notifications` + `timezone`, behind [NotificationGateway].
///
/// Everything here is plumbing on purpose. The decisions worth protecting —
/// which occasions are nudged, which are deliberately silent, what goes in the
/// ledger — live in `NudgeScheduler` and are tested against a fake of this
/// interface; what remains is channel calls, which a unit test can only
/// re-assert.
class LocalNotificationGateway implements NotificationGateway {
  LocalNotificationGateway({
    FlutterLocalNotificationsPlugin? plugin,
    this.onResponse,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static final Logger _log = Logger('LocalNotificationGateway');

  /// The Android channel. Its importance is fixed at creation — changing it
  /// later needs a new channel id, because Android hands channel settings to
  /// the user the moment the channel exists.
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'taproot_evening_check_in',
    'Evening check-in',
    description:
        'One notification in the evening: how today went, and tomorrow’s cue.',
    importance: Importance.high,
  );

  final FlutterLocalNotificationsPlugin _plugin;

  /// Invoked when a notification is tapped or answered from the shade.
  final void Function(NudgeResponse response)? onResponse;

  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    // The scheduler works in local wall-clock DateTimes; `zonedSchedule` wants
    // a TZDateTime in a named zone. Without this the plugin has no zone
    // database at all and every schedule throws.
    timezone_data.initializeTimeZones();
    timezone.setLocalLocation(timezone.local);

    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // All three false: permission is a designed onboarding moment, not
          // something to fire on first launch (guide §2).
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: <DarwinNotificationCategory>[
            DarwinNotificationCategory(
              NudgeActionIds.category,
              actions: <DarwinNotificationAction>[
                DarwinNotificationAction.plain(
                  NudgeActionIds.confirm,
                  'Yes',
                  options: <DarwinNotificationActionOption>{
                    DarwinNotificationActionOption.authenticationRequired,
                  },
                ),
                DarwinNotificationAction.plain(
                  NudgeActionIds.decline,
                  'Different day',
                  options: <DarwinNotificationActionOption>{
                    DarwinNotificationActionOption.authenticationRequired,
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      onDidReceiveNotificationResponse: _handleResponse,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);

    _initialized = true;
  }

  void _handleResponse(NotificationResponse response) {
    final payload = NudgePayload.decode(response.payload);
    final action = NudgeActionIds.actionFor(response.actionId);
    if (payload == null || action == null) {
      _log.warning(
        'unrecognised notification response: '
        '${response.payload} / ${response.actionId}',
      );
      return;
    }
    onResponse?.call(NudgeResponse(payload: payload, action: action));
  }

  @override
  Future<NotificationAccess> currentAccess() async {
    if (_isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final enabled = await android?.areNotificationsEnabled() ?? false;
      return NotificationAccess(
        // Android cannot distinguish "never asked" from "refused" after the
        // fact, so an un-granted state reads as denied and the app's
        // permission mode is driven by its own onboarding record instead.
        mode: enabled ? NotificationMode.granted : NotificationMode.denied,
        exactAlarms: await _exactAlarmCapability(android),
      );
    }

    if (_isIOS) {
      final options = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.checkPermissions();
      final granted = options?.isEnabled ?? false;
      return NotificationAccess(
        mode: granted ? NotificationMode.granted : NotificationMode.denied,
      );
    }

    return const NotificationAccess(mode: NotificationMode.denied);
  }

  @override
  Future<NotificationAccess> requestAccess() async {
    await initialize();

    if (_isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await android?.requestNotificationsPermission() ?? false;
      return NotificationAccess(
        mode: granted ? NotificationMode.granted : NotificationMode.denied,
        exactAlarms: await _exactAlarmCapability(android),
      );
    }

    if (_isIOS) {
      final granted =
          await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
      return NotificationAccess(
        mode: granted ? NotificationMode.granted : NotificationMode.denied,
      );
    }

    return const NotificationAccess(mode: NotificationMode.denied);
  }

  /// Exactness is never *requested*, only observed.
  ///
  /// `SCHEDULE_EXACT_ALARM` is a full-screen system settings trip on Android
  /// 12+, and the evening check-in does not need it: a slot the OS may slide
  /// by a few minutes is still the ritual. So the app reads the capability,
  /// schedules inexactly when it is absent, and spends no permission prompt on
  /// it (guide §14, the decision it asks to make early).
  Future<ExactAlarmCapability> _exactAlarmCapability(
    AndroidFlutterLocalNotificationsPlugin? android,
  ) async {
    if (android == null) return ExactAlarmCapability.notApplicable;
    final canSchedule = await android.canScheduleExactNotifications();
    if (canSchedule == null) return ExactAlarmCapability.notApplicable;
    return canSchedule
        ? ExactAlarmCapability.granted
        : ExactAlarmCapability.unavailable;
  }

  @override
  Future<void> schedule(ScheduledNudge nudge) async {
    await initialize();
    final access = await currentAccess();

    await _plugin.zonedSchedule(
      id: nudge.notificationId,
      title: nudge.checkIn.title,
      body: nudge.checkIn.body,
      payload: nudge.payload.encode(),
      scheduledDate: timezone.TZDateTime.from(nudge.deliverAt, timezone.local),
      androidScheduleMode: access.exactAlarms.allowsExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction(
              NudgeActionIds.confirm,
              nudge.checkIn.confirmLabel,
              showsUserInterface: false,
              cancelNotification: true,
            ),
            AndroidNotificationAction(
              NudgeActionIds.decline,
              nudge.checkIn.declineLabel,
              showsUserInterface: false,
              cancelNotification: true,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(
          categoryIdentifier: NudgeActionIds.category,
        ),
      ),
    );
  }

  @override
  Future<void> cancel(int notificationId) => _plugin.cancel(id: notificationId);

  @override
  Future<Set<int>> pendingNotificationIds() async {
    final pending = await _plugin.pendingNotificationRequests();
    return pending.map((request) => request.id).toSet();
  }

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
}

/// Whether this build can post local notifications at all. False on the
/// desktop and web targets the app does not ship to, where the plugin's
/// platform implementations are absent.
bool get supportsLocalNotifications =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);
