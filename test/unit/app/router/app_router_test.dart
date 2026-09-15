import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/app/router/app_router.dart';

import '../../../utils/fake_repositories.dart';
import '../../../utils/store_fixtures.dart';

void main() {
  group('the entry gate', () {
    Future<AppGate> gateFor(
      FakeHabitService habits, {
      bool notificationsOffered = false,
    }) => resolveAppGate(
      habits: habits,
      invitations: FakeNotificationInvitationStore(
        offered: notificationsOffered,
      ),
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
