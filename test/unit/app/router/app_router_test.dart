import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/app/router/app_router.dart';

void main() {
  group('the entry gate', () {
    ProviderContainer containerWith(Future<AppGate> Function() resolver) {
      final container = ProviderContainer(
        overrides: [appGateResolverProvider.overrideWithValue(resolver)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('is open while there is nothing to gate on', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(await container.read(appGateProvider.future), openAppGate);
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
