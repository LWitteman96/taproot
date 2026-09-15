import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/features/habits/providers/habit_providers.dart';
import 'package:taproot/features/notifications/domain/notification_access.dart';
import 'package:taproot/features/notifications/providers/notification_onboarding_providers.dart';
import 'package:taproot/features/notifications/providers/nudge_providers.dart';
import 'package:taproot/features/reflection/providers/reflection_providers.dart';

import '../../../../utils/fake_notification_gateway.dart';
import '../../../../utils/fake_repositories.dart';
import '../../../../utils/store_fixtures.dart';

/// Noticing that permission changed while the app was away.
///
/// Permission is revocable, and it is revoked *outside the app*: the user walks
/// to system settings, switches Taproot off, and comes back. Nothing tells the
/// app. Without a listener the app goes on believing it may post notifications,
/// and — in the mirror case — a user who switched them *on* gets silence until
/// something else happens to trigger a plan.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHabitService habits;
  late FakeNotificationGateway gateway;

  setUp(() async {
    habits = FakeHabitService();
    await habits.saveHabit(testHabit(targetFrequency: 7));
    gateway = FakeNotificationGateway(access: NotificationAccess.denied);
  });

  ProviderContainer containerWith() {
    final container = ProviderContainer(
      // All four repositories, because the planner assembles HabitInputs from
      // every one of them — and with all four faked there is no database to
      // open, so a resume is the only asynchronous thing happening.
      overrides: [
        habitServiceProvider.overrideWithValue(habits),
        completionServiceProvider.overrideWithValue(
          FakeCompletionService(habits: habits),
        ),
        reflectionServiceProvider.overrideWithValue(
          FakeReflectionService(habits: habits),
        ),
        nudgeServiceProvider.overrideWithValue(
          FakeNudgeService(habits: habits),
        ),
        notificationGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// A trip to system settings and back.
  ///
  /// Both halves are required, and finding that out cost an hour: the binding
  /// starts with a **null** lifecycle state, and `AppLifecycleListener` fires
  /// `onResume` on the *transition* into resumed — so jumping straight to
  /// resumed from nothing is not a resume, and a test that does it is testing
  /// an app that never left.
  Future<void> leaveAndComeBack() async {
    final binding = TestWidgetsFlutterBinding.instance
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await pumpEventQueue();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    // Generously: the re-plan is a long chain of awaits — habit list, four
    // repository reads per habit, then a write and a platform call per
    // occasion — and the default 20 turns does not see the end of it.
    await pumpEventQueue(times: 500);
  }

  test('a revocation made in system settings is noticed', () async {
    final container = containerWith();
    gateway.grant(const NotificationAccess(mode: NotificationMode.granted));
    container.listen(notificationAccessRefreshProvider, (_, _) {});

    expect(
      (await container.read(notificationAccessProvider.future)).canPost,
      isTrue,
    );

    // Off to settings, and back.
    gateway.grant(NotificationAccess.denied);
    await leaveAndComeBack();

    expect(
      (await container.read(notificationAccessProvider.future)).canPost,
      isFalse,
      reason: 'the cached answer stopped being true while we were away',
    );
  });

  test('a grant made in system settings gets the nudges scheduled', () async {
    // The mirror case, and the one that needs work done rather than merely
    // noticed: occasions are already recorded with nothing queued against
    // them, so without this the user hears nothing until the next launch or
    // the next completion.
    final container = containerWith();
    container.listen(notificationAccessRefreshProvider, (_, _) {});
    await container.read(nudgeSchedulerProvider).planAll();
    expect(gateway.queued, isEmpty);

    gateway.grant(const NotificationAccess(mode: NotificationMode.granted));
    await leaveAndComeBack();

    expect(gateway.queued, isNotEmpty);
  });

  test('a resume that changed nothing writes nothing', () async {
    // Planning is idempotent, so the cost of doing this on every resume is a
    // pass that finds every occasion already recorded.
    final container = containerWith();
    container.listen(notificationAccessRefreshProvider, (_, _) {});
    await container.read(nudgeSchedulerProvider).planAll();
    final before = await container
        .read(nudgeServiceProvider)
        .nudgesFor('habit-1');

    await leaveAndComeBack();

    final after = await container
        .read(nudgeServiceProvider)
        .nudgesFor('habit-1');
    expect(after.map((row) => row.id), before.map((row) => row.id));
  });

  test('nobody listening means nobody notices', () async {
    // Riverpod 3 pauses a provider whose listeners are all paused, and one
    // nobody listens to is in that set — so this is not a hypothetical. It is
    // why `TaprootApp` watches the provider rather than reading it once, and
    // this test fails if that watch is ever dropped for a read.
    final container = containerWith();
    gateway.grant(const NotificationAccess(mode: NotificationMode.granted));
    await container.read(notificationAccessProvider.future);

    // Deliberately not listened to.
    gateway.grant(NotificationAccess.denied);
    await leaveAndComeBack();

    expect(
      (await container.read(notificationAccessProvider.future)).canPost,
      isTrue,
      reason: 'an unwatched lifecycle listener never fired',
    );
  });
}
