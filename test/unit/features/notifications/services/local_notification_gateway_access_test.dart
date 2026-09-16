import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:taproot/features/notifications/domain/notification_access.dart';
import 'package:taproot/features/notifications/services/local_notification_gateway.dart';

/// The one platform question that is worth asking a second plugin.
///
/// Almost everything in `LocalNotificationGateway` is channel calls a unit test
/// can only re-assert, and it is written that way on purpose. This is the
/// exception: [NotificationMode.undecided] is the only evidence that ever
/// exists of an invitation record restored from another phone, and it is
/// spent by `resolveAppGate`. `flutter_local_notifications` cannot produce it —
/// `checkPermissions` answers a flat `isEnabled` — so it comes from
/// `permission_handler`, where iOS's `notDetermined` arrives as
/// [PermissionStatus.denied] and a real refusal as `permanentlyDenied`.
///
/// Reading that mapping backwards is silent and total: every restored phone
/// looks refused, nobody is re-offered, and no test that does not check the
/// mapping itself would notice.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    // No iOS implementation is registered on the test host, so
    // `resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>`
    // answers null and `checkPermissions` is skipped — which is the
    // un-granted branch, and the only branch this file is about. Something
    // has to be here all the same: the static is `late` and reading it
    // unset throws before the code under test is reached.
    FlutterLocalNotificationsPlatform.instance = _UnregisteredPlatform();
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  Future<NotificationMode> modeFor(
    Future<PermissionStatus> Function() status,
  ) async => (await LocalNotificationGateway(
    notificationPermissionStatus: status,
  ).currentAccess()).mode;

  test('never prompted on this install reads as undecided', () async {
    // iOS `notDetermined`. This is what a restored backup looks like: the
    // record travelled in NSUserDefaults, the authorisation did not.
    expect(
      await modeFor(() async => PermissionStatus.denied),
      NotificationMode.undecided,
    );
  });

  test('refused on this install reads as denied', () async {
    // iOS `denied` — asked, and the answer was no. The user must not be asked
    // again, so this may never be confused with the above.
    expect(
      await modeFor(() async => PermissionStatus.permanentlyDenied),
      NotificationMode.denied,
    );
  });

  test('a restriction is not an invitation to ask again', () async {
    // Parental controls and the like. Nothing was refused and nothing was
    // asked, but prompting would not help either.
    expect(
      await modeFor(() async => PermissionStatus.restricted),
      NotificationMode.denied,
    );
  });

  test('a status that cannot be read falls back to denied', () async {
    // The safe wrong answer: it is what this returned before it could tell the
    // two apart, and it costs only the re-offer on a restored phone.
    expect(
      await modeFor(
        () async => throw StateError('the permission channel is not there'),
      ),
      NotificationMode.denied,
    );
  });
}

/// Stands in for the platform implementation a test host does not register.
class _UnregisteredPlatform extends FlutterLocalNotificationsPlatform {}
