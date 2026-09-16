import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/app/router/app_router.dart';
import 'package:taproot/features/notifications/domain/notification_access.dart';
import 'package:taproot/features/notifications/domain/notification_gateway.dart';

import '../../../utils/fake_notification_gateway.dart';
import '../../../utils/fake_repositories.dart';
import '../../../utils/store_fixtures.dart';

void main() {
  group('the entry gate', () {
    Future<AppGate> gateFor(
      FakeHabitService habits, {
      bool notificationsOffered = false,
      NotificationAccess access = NotificationAccess.denied,
      NotificationGateway? notifications,
    }) => resolveAppGate(
      habits: habits,
      invitations: FakeNotificationInvitationStore(
        offered: notificationsOffered,
      ),
      notifications: notifications ?? FakeNotificationGateway(access: access),
    );

    ProviderContainer containerWith(Future<AppGate> Function() resolver) {
      final container = ProviderContainer(
        overrides: [appGateResolverProvider.overrideWithValue(resolver)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('is shut until something has been planted', () async {
      // One habit is the whole question: the garden leads with accumulated
      // progress, and an empty one has none to lead with.
      final habits = FakeHabitService();

      expect((await gateFor(habits)).hasFirstHabit, isFalse);

      await habits.saveHabit(testHabit());
      expect((await gateFor(habits)).hasFirstHabit, isTrue);
    });

    group('a record that arrived on a restored phone', () {
      // The record is device-local and unsynced, but it is not unmoved: on iOS
      // it lives in NSUserDefaults, which rides iCloud and encrypted local
      // backups. Permission does not ride along. So "record says offered,
      // platform says undecided" is a pair reachable only by a restore — and
      // without this cross-check that user is never offered notifications
      // again, on any device.
      test('is treated as a question this install has not put', () async {
        final habits = FakeHabitService();
        await habits.saveHabit(testHabit());

        final gate = await gateFor(
          habits,
          notificationsOffered: true,
          access: const NotificationAccess(mode: NotificationMode.undecided),
        );

        expect(gate.notificationsOffered, isFalse);
      });

      test(
        'while a refusal made on this install still counts as asked',
        () async {
          // The distinction is the whole mechanism: a user who was asked and
          // said no leaves the platform `denied`, not `undecided`, and must not
          // be asked twice.
          final habits = FakeHabitService();
          await habits.saveHabit(testHabit());

          final gate = await gateFor(
            habits,
            notificationsOffered: true,
            access: NotificationAccess.denied,
          );

          expect(gate.notificationsOffered, isTrue);
        },
      );

      test('and a platform that cannot be read trusts the record', () async {
        // The opposite fail direction from a failed record *read*, and
        // deliberately: there is a positive record here that simply could not
        // be corroborated, and re-asking on a channel hiccup puts a once-ever
        // question a second time.
        final habits = FakeHabitService();
        await habits.saveHabit(testHabit());

        final gate = await gateFor(
          habits,
          notificationsOffered: true,
          notifications: _UnreadableGateway(),
        );

        expect(gate.notificationsOffered, isTrue);
      });
    });

    test('a deleted last habit shuts it again', () async {
      final habits = FakeHabitService();
      await habits.saveHabit(testHabit());
      await habits.deleteHabit('habit-1');

      expect((await gateFor(habits)).hasFirstHabit, isFalse);
    });

    test('falls back to the safe gate when the resolver throws', () async {
      final container = containerWith(
        () =>
            Future<AppGate>.error(StateError('the profile row is unreachable')),
      );

      expect(await container.read(appGateProvider.future), failSafeAppGate);
    });

    test(
      'the safe gate sends a new user onward, it does not lock them out',
      () {
        // Guide §7: on any error, "needs onboarding, not restricted". Routing
        // into habit creation is recoverable; refusing entry is not.
        expect(failSafeAppGate.hasFirstHabit, isFalse);
        expect(
          redirectFor(failSafeAppGate, AppRoutes.garden),
          AppRoutes.habitCreation,
        );
      },
    );

    test('an open gate leaves the garden alone', () {
      expect(redirectFor(openAppGate, AppRoutes.garden), isNull);
    });

    group('the notification invitation', () {
      test('is offered once a habit exists', () async {
        // The order is the product decision: nobody is asked to accept
        // notifications before they have a habit worth being notified about.
        final habits = FakeHabitService();
        await habits.saveHabit(testHabit());

        final gate = await gateFor(habits);

        expect(gate.notificationsOffered, isFalse);
        expect(
          redirectFor(gate, AppRoutes.garden),
          AppRoutes.notificationInvitation,
        );
      });

      test('never comes before the first habit', () async {
        final gate = await gateFor(FakeHabitService());

        expect(
          redirectFor(gate, AppRoutes.garden),
          AppRoutes.habitCreation,
          reason: 'a permission request about nothing is an interrogation',
        );
      });

      test('is asked once, and then never again', () async {
        final habits = FakeHabitService();
        await habits.saveHabit(testHabit());

        final gate = await gateFor(habits, notificationsOffered: true);

        expect(redirectFor(gate, AppRoutes.garden), isNull);
      });

      test('a gate that could not be read does not interrupt', () {
        // The two halves of the safe gate fail in opposite directions.
        // Creation is somewhere to *be*; the invitation is somewhere to be
        // *asked*, and a failed read is no reason to put a permission request
        // in front of someone who may well have answered it already.
        expect(failSafeAppGate.notificationsOffered, isTrue);
      });
    });

    test('the gate only evaluates on the root path', () {
      // inkBlox's guard reruns on every navigation otherwise, which turns one
      // profile read into one per push.
      expect(redirectFor(failSafeAppGate, AppRoutes.habitCreation), isNull);
    });

    test('an unresolved gate never guesses', () {
      expect(redirectFor(null, AppRoutes.garden), isNull);
    });
  });
}

/// A platform whose permission state cannot be read at all.
class _UnreadableGateway extends FakeNotificationGateway {
  @override
  Future<NotificationAccess> currentAccess() async =>
      throw StateError('the notification channel is not there');
}
