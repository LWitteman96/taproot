import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/app/database/database_provider.dart';
import 'package:taproot/features/habits/providers/habit_providers.dart';
import 'package:taproot/features/notifications/domain/notification_access.dart';
import 'package:taproot/features/notifications/providers/notification_onboarding_providers.dart';
import 'package:taproot/features/notifications/providers/nudge_providers.dart';
import 'package:taproot/main.dart';

import '../../utils/fake_notification_gateway.dart';
import '../../utils/fake_repositories.dart';
import '../../utils/store_fixtures.dart';

/// The guard on `main.dart`'s `ref.watch(notificationAccessRefreshProvider)`.
///
/// **This one has to pump `TaprootApp`.** The refresh listener lives in a
/// provider, and Riverpod 3 pauses a provider whose listeners are all paused —
/// one nobody listens to is in that set — so the listener only ever fires
/// because a widget that outlives every screen is watching it. Everything
/// about that is a property of the *wiring*, not of the provider: a test that
/// builds its own `ProviderContainer` and subscribes by hand proves the
/// provider works when listened to, and proves nothing at all about whether
/// anything listens.
///
/// The edit this exists to catch is one word. `notificationAccessRefreshProvider`
/// returns void, so "why are we watching a void?" is a reasonable-looking
/// cleanup, and `ref.read` compiles, analyses clean, and ships an app that goes
/// on believing it may post notifications after the user switched them off in
/// system settings. The unit tests next door all stayed green through exactly
/// that edit, which is why this file exists.
void main() {
  late FakeHabitService habits;
  late FakeNotificationGateway gateway;

  setUp(() async {
    habits = FakeHabitService();
    await habits.saveHabit(testHabit(targetFrequency: 7));
    gateway = FakeNotificationGateway(
      access: const NotificationAccess(mode: NotificationMode.granted),
    );
  });

  /// The real app, past the gate, on the garden.
  Future<ProviderContainer> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseOpenerProvider.overrideWithValue(
            openTestDatabaseInWidgetTest,
          ),
          habitServiceProvider.overrideWithValue(habits),
          nudgeServiceProvider.overrideWithValue(
            FakeNudgeService(habits: habits),
          ),
          notificationGatewayProvider.overrideWithValue(gateway),
          notificationInvitationStoreProvider.overrideWithValue(
            FakeNotificationInvitationStore(offered: true),
          ),
        ],
        child: const TaprootApp(),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(TaprootApp)));
  }

  /// A trip to system settings and back.
  ///
  /// Both halves are required: the binding starts at a **null** lifecycle
  /// state and `AppLifecycleListener` fires `onResume` on the *transition*
  /// into resumed, so jumping straight to resumed is testing an app that never
  /// left.
  Future<void> leaveAndComeBack(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  }

  testWidgets('the running app notices a revocation made while it was away', (
    tester,
  ) async {
    final container = await pumpApp(tester);
    expect(
      (await container.read(notificationAccessProvider.future)).canPost,
      isTrue,
    );

    // Off to system settings, Taproot's notifications switched off, back.
    gateway.grant(NotificationAccess.denied);
    await leaveAndComeBack(tester);

    expect(
      (await container.read(notificationAccessProvider.future)).canPost,
      isFalse,
      reason:
          'nothing in the running app was listening, so the lifecycle '
          'listener never fired — check that main.dart still *watches* '
          'notificationAccessRefreshProvider',
    );
  });

  testWidgets('and gets the nudges queued when one is made the other way', (
    tester,
  ) async {
    // The mirror case, through the same wiring: a user who switched
    // notifications *on* has occasions already recorded with nothing queued
    // against them, and would hear silence until the next launch.
    gateway.grant(NotificationAccess.denied);
    final container = await pumpApp(tester);
    await container.read(nudgeSchedulerProvider).planAll();
    expect(gateway.queued, isEmpty);

    gateway.grant(const NotificationAccess(mode: NotificationMode.granted));
    await leaveAndComeBack(tester);

    expect(gateway.queued, isNotEmpty);
  });
}
