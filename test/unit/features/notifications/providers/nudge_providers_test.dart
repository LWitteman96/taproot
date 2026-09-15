import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/app/database/database_provider.dart';
import 'package:taproot/app/startup/app_startup.dart';
import 'package:taproot/core/models/nudge.dart';
import 'package:taproot/features/habits/providers/habit_providers.dart';
import 'package:taproot/features/notifications/domain/notification_access.dart';
import 'package:taproot/features/notifications/domain/notification_gateway.dart';
import 'package:taproot/features/notifications/domain/nudge_payload.dart';
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

  /// Lets the launch re-plan finish.
  ///
  /// Startup deliberately does not await `planAll()` — the first frame must not
  /// wait on it — so the pass is still running when the test body ends. Without
  /// this the container is disposed underneath it, the database closes
  /// mid-query, and the failure surfaces as a confusing error from a pass
  /// nobody was waiting for.
  Future<void> settle() => pumpEventQueue();

  test('startup initialises the platform and plans', () async {
    final container = containerWith(gateway);

    await container.read(appStartupProvider.future);
    await settle();

    expect(gateway.initializeCalls, 1);
  });

  test('a habit in the store gets a ledger and a queued nudge', () async {
    final container = containerWith(gateway);
    await container.read(appStartupProvider.future);

    await container
        .read(habitServiceProvider)
        .saveHabit(testHabit(targetFrequency: 7, createdAt: DateTime.now()));
    await container.read(nudgeSchedulerProvider).planAll();
    await settle();

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

  group('a notification that started the app', () {
    // Neither response callback fires for it — the answer is only readable by
    // asking once, on startup — so an unasked-for question means the answer is
    // simply lost.
    Future<ProviderContainer> launchedBy(NudgeResponseAction action) async {
      final container = containerWith(gateway);
      await container.read(appStartupProvider.future);

      await container.read(habitServiceProvider).saveHabit(testHabit());
      await container
          .read(nudgeServiceProvider)
          .saveNudge(
            NudgeRecord(
              id: 'nudge-1',
              habitId: 'habit-1',
              expectedOccasionAt: DateTime.now(),
              sent: false,
            ),
          );

      gateway.launchedBy = NudgeResponse(
        payload: const NudgePayload(nudgeId: 'nudge-1', habitId: 'habit-1'),
        action: action,
      );
      container.invalidate(notificationStartupProvider);
      await container.read(appStartupProvider.future);
      await settle();
      return container;
    }

    Future<NudgeRecord> row(ProviderContainer container) async =>
        (await container.read(nudgeServiceProvider).nudgesFor('habit-1'))
            .firstWhere((nudge) => nudge.id == 'nudge-1');

    test('is recorded on the way in', () async {
      final container = await launchedBy(NudgeResponseAction.confirmed);

      expect((await row(container)).confirmed, isTrue);
    });

    test('a decline lands the same way', () async {
      final container = await launchedBy(NudgeResponseAction.declined);

      expect((await row(container)).declined, isTrue);
    });

    test('an ordinary launch records nothing', () async {
      final container = containerWith(gateway);
      await container.read(appStartupProvider.future);

      await container.read(habitServiceProvider).saveHabit(testHabit());
      await container
          .read(nudgeServiceProvider)
          .saveNudge(
            NudgeRecord(
              id: 'nudge-1',
              habitId: 'habit-1',
              expectedOccasionAt: DateTime.now(),
              sent: false,
            ),
          );

      container.invalidate(notificationStartupProvider);
      await container.read(appStartupProvider.future);
      await settle();

      expect((await row(container)).confirmed, isFalse);
      expect((await row(container)).declined, isFalse);
    });
  });

  test('startup survives a platform that will not initialise', () async {
    // A notification platform that fails is a degraded mode, not a reason to
    // hold the garden behind an error screen — the completion tap has to work
    // either way.
    final container = containerWith(_BrokenGateway());

    await expectLater(container.read(appStartupProvider.future), completes);
    await settle();
  });

  test('access is read without prompting', () async {
    // The permission prompt is a designed onboarding moment; nothing on the
    // launch path may fire it.
    gateway.grant(NotificationAccess.denied);
    final container = containerWith(gateway);

    await container.read(appStartupProvider.future);
    await settle();

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
