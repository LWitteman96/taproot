import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/core/utils/flavor.dart';
import 'package:taproot/features/habits/services/demo_habit_seed.dart';

import '../../../../utils/fake_repositories.dart';
import '../../../../utils/store_fixtures.dart';

void main() {
  group('isDemoSeedEnabled', () {
    test('a debug dev build may seed', () {
      expect(
        isDemoSeedEnabled(flavor: () => Flavor.dev, isDebug: true),
        isTrue,
      );
    });

    test('a release build may not, whatever the flavor resolves to', () {
      // The point of the second half of the guard. `getFlavor()` falls back to
      // Flavor.dev whenever `appFlavor` is unset — which is every build not
      // launched with `--flavor` — so a release build made without the flag
      // used to look exactly like a dev one and shipped the seed button on the
      // empty garden.
      expect(
        isDemoSeedEnabled(flavor: () => Flavor.dev, isDebug: false),
        isFalse,
      );
    });

    test('a debug stg or prod build may not', () {
      // Kept alongside kDebugMode so that once the flavors are genuinely wired
      // a debug build of the other two is still excluded.
      for (final flavor in <Flavor>[Flavor.stg, Flavor.prod]) {
        expect(
          isDemoSeedEnabled(flavor: () => flavor, isDebug: true),
          isFalse,
          reason: '$flavor must not seed',
        );
      }
    });
  });

  group('plantDemoHabit', () {
    test('plants one habit in a debug dev build', () async {
      final clock = TestClock(DateTime(2026, 3, 4, 9));
      final habits = FakeHabitService(clock: clock.call);

      final habit = await plantDemoHabit(
        habits: habits,
        newId: () => 'habit-1',
        clock: clock.call,
        flavor: () => Flavor.dev,
        isDebug: true,
      );

      expect(habit, isNotNull);
      expect(habit!.name, 'Morning walk');
      // No history, so the first watering visibly moves it a rung.
      expect(await habits.allHabits(), hasLength(1));
    });

    test('writes nothing in a release build', () async {
      // The guard is inside the function, not only at the call site, so this
      // cannot reach a production store from somewhere else later.
      final clock = TestClock(DateTime(2026, 3, 4, 9));
      final habits = FakeHabitService(clock: clock.call);

      final habit = await plantDemoHabit(
        habits: habits,
        newId: () => 'habit-1',
        clock: clock.call,
        flavor: () => Flavor.dev,
        isDebug: false,
      );

      expect(habit, isNull);
      expect(await habits.allHabits(), isEmpty);
    });
  });
}
