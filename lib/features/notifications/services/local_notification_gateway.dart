import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import 'package:taproot/features/notifications/domain/notification_access.dart';
import 'package:taproot/features/notifications/domain/notification_gateway.dart';
import 'package:taproot/features/notifications/domain/nudge_payload.dart';
import 'package:taproot/features/notifications/services/background_nudge_response.dart';

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
    Future<PermissionStatus> Function()? notificationPermissionStatus,
    this.onResponse,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _permissionStatus =
           notificationPermissionStatus ?? _askPermissionHandler;

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

  /// Whether iOS has ever put the notification prompt to this install.
  ///
  /// A seam rather than a direct call, because it is the one thing here worth
  /// a unit test: the [NotificationMode.undecided] it produces is what tells a
  /// restored backup's invitation record from a real one.
  final Future<PermissionStatus> Function() _permissionStatus;

  static Future<PermissionStatus> _askPermissionHandler() =>
      Permission.notification.status;

  /// Invoked when a notification is tapped or answered from the shade.
  final void Function(NudgeResponse response)? onResponse;

  bool _initialized = false;

  /// The access this pass is scheduling against.
  ///
  /// Refreshed by [currentAccess] and [requestAccess], and read by [schedule].
  /// Two reasons not to re-derive it per notification: on Android it is two
  /// platform round trips each, so a pass queuing N nudges made ~2N redundant
  /// channel calls — and, worse, the scheduler decided `canPost` from one
  /// snapshot while the gateway scheduled against another taken moments later,
  /// so a permission flip mid-pass left the ledger written against one state
  /// and the notifications queued against a different one.
  NotificationAccess _access = const NotificationAccess(
    mode: NotificationMode.undecided,
  );

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
      // The one that matters most, and the easiest to leave out. Both actions
      // are `showsUserInterface: false`, so the platform delivers them to a
      // background isolate whenever the app is not in the foreground — which
      // at 20:00 is nearly always. Without this the answer is dropped and
      // nothing reports it.
      onDidReceiveBackgroundNotificationResponse:
          backgroundNudgeResponseHandler,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);

    _initialized = true;
  }

  void _handleResponse(NotificationResponse response) {
    final answer = NudgeResponse.from(response.payload, response.actionId);
    if (answer == null) {
      _log.warning(
        'unrecognised notification response: '
        '${response.payload} / ${response.actionId}',
      );
      return;
    }
    onResponse?.call(answer);
  }

  @override
  Future<NotificationAccess> currentAccess() async {
    return _access = await _readAccess();
  }

  Future<NotificationAccess> _readAccess() async {
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
      if (options?.isEnabled ?? false) {
        return const NotificationAccess(mode: NotificationMode.granted);
      }
      return NotificationAccess(mode: await _unGrantedIOSMode());
    }

    return const NotificationAccess(mode: NotificationMode.denied);
  }

  @override
  Future<NotificationAccess> requestAccess() async {
    await initialize();

    // Prompt, then *read*. Deriving the result from the prompt's own return
    // value duplicated `currentAccess` in full, and the copies had already
    // drifted: iOS reports a provisional grant incorrectly here, while
    // `checkPermissions` sees it. One derivation to maintain when the
    // undecided-state mapping or macOS support arrives.
    if (_isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } else if (_isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }

    return currentAccess();
  }

  /// Which kind of "not granted" iOS is in.
  ///
  /// **iOS is the one platform that can tell "never asked" from "refused"**,
  /// and it is worth the second plugin to ask it. `UNAuthorizationStatus` has
  /// `notDetermined`; `flutter_local_notifications` does not surface it —
  /// `checkPermissions` answers a flat `isEnabled` — so `permission_handler`
  /// is asked instead, where iOS's `notDetermined` arrives as
  /// [PermissionStatus.denied] ("needs to be asked first") and a real refusal
  /// as `permanentlyDenied`.
  ///
  /// What that buys is the restore case. The invitation record lives in
  /// `NSUserDefaults`, which rides iCloud and encrypted local backups and
  /// cannot be excluded from either; permission does not restore, because it
  /// is granted per install. So a restored phone has a record saying "already
  /// asked" and a platform that has never prompted — and `undecided` is the
  /// only evidence that ever existed of it. [resolveAppGate] is where it is
  /// spent.
  ///
  /// Android gets `denied` and nothing better, which is why this is only half
  /// of the fix: `areNotificationsEnabled()` reads the same for both, so that
  /// side is covered by excluding the record from Auto Backup instead
  /// (`android/app/src/main/res/xml/`).
  Future<NotificationMode> _unGrantedIOSMode() async {
    try {
      final status = await _permissionStatus();
      return status == PermissionStatus.denied
          ? NotificationMode.undecided
          : NotificationMode.denied;
    } catch (error, stackTrace) {
      // Denied is the safe wrong answer: it is what this method returned
      // before it could tell the two apart, and it costs the user nothing
      // beyond not being re-offered on a restored phone.
      _log.warning(
        'the notification authorization status could not be read',
        error,
        stackTrace,
      );
      return NotificationMode.denied;
    }
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

    await _plugin.zonedSchedule(
      id: nudge.notificationId,
      title: nudge.checkIn.title,
      body: nudge.checkIn.body,
      payload: nudge.payload.encode(),
      scheduledDate: timezone.TZDateTime.from(nudge.deliverAt, timezone.local),
      androidScheduleMode: _access.exactAlarms.allowsExact
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
  Future<NudgeResponse?> launchResponse() async {
    // The cold-start path: an answer given to a notification that started the
    // app is never delivered to either callback, it is only readable here.
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;

    final raw = details.notificationResponse;
    return NudgeResponse.from(raw?.payload, raw?.actionId);
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
