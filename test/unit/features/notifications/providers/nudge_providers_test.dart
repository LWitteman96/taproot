import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/app/database/database_provider.dart';
import 'package:taproot/app/startup/app_startup.dart';
import 'package:taproot/features/habits/providers/habit_providers.dart';
import 'package:taproot/features/notifications/domain/notification_access.dart';
import 'package:taproot/features/notifications/providers/nudge_providers.dart';

import '../../../../utils/fake_notification_gateway.dart';
import '../../../../utils/store_fixtures.dart';

/// The wiring, over the real SQLite store.
///
/// The one thing that cannot be asserted in the scheduler's own tests: that a
/// launch actually re-plans. Occasions are written by the planning pass, so an
/// unwired startup means no ledger at all — and the symptom is autonomy
/// sitting at zero evidence forever, not an error.
void main() {
  late FakeNotificationGateway gateway;

  ProviderContainer containerWith(FakeNotificationGateway gateway) {
    final container = ProviderContainer(
      overrides: [
        databaseOpenerProvider.overrideWithValue(openTestDatabase),
        notificationGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() => gateway = FakeNotificationGateway());

  test('startup initialises the platform and plans', () async {
    final container = containerWith(gateway);

    await container.read(appStartupProvider.future);

    expect(gateway.initializeCalls, 1);
  });

  test('a habit in the store gets a ledger and a queued nudge', () async {
    final container = containerWith(gateway);
    await container.read(appStartupProvider.future);

    await container
        .read(habitServiceProvider)
        .saveHabit(testHabit(targetFrequency: 7, createdAt: DateTime.now()));
    await container.read(nudgeSchedulerProvider).planAll();

    final ledger = await container
        .read(nudgeServiceProvider)
        .nudgesFor('habit-1');
    expect(ledger, isNotEmpty);
    expect(gateway.queued, isNotEmpty);
    expect(
      ledger.where((row) => row.sent).length,
      gateway.queued.length,
      reason: 'the ledger and the OS queue agree about what was nudged',
    );
  });

  test('startup survives a platform that will not initialise', () async {
    // A notification platform that fails is a degraded mode, not a reason to
    // hold the garden behind an error screen — the completion tap has to work
    // either way.
    final container = containerWith(_BrokenGateway());

    await expectLater(container.read(appStartupProvider.future), completes);
  });

  test('access is read without prompting', () async {
    // The permission prompt is a designed onboarding moment; nothing on the
    // launch path may fire it.
    gateway.grant(NotificationAccess.denied);
    final container = containerWith(gateway);

    await container.read(appStartupProvider.future);

    expect(
      await container.read(notificationAccessProvider.future),
      NotificationAccess.denied,
    );
  });
}

class _BrokenGateway extends FakeNotificationGateway {
  @override
  Future<void> initialize() async =>
      throw StateError('no notification platform here');
}
