import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/app/runtime/runtime_providers.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/completion.dart';
import 'package:taproot/core/models/habit_category.dart';
import 'package:taproot/features/habits/providers/habit_providers.dart';
import 'package:taproot/features/notifications/providers/nudge_providers.dart';
import 'package:taproot/features/reflection/providers/reflection_providers.dart';

import '../../../../utils/fake_notification_gateway.dart';
import '../../../../utils/fake_repositories.dart';
import '../../../../utils/store_contract.dart';
import '../../../../utils/store_fixtures.dart';

/// That the composer is actually *installed*.
///
/// **Every other test in this feature would pass with the stand-in back.** The
/// composer's own tests construct it directly and the scheduler's inject a
/// fake, so both sides of the seam are covered and the wire between them is
/// not: swap `reflectionPromptComposerProvider` back to `NoReflectionPrompt`
/// and the suite stays green while every notification the app sends loses its
/// question.
///
/// That is the shape of defect this branch fixed elsewhere — a property that
/// holds by default in every scenario the tests create, so nothing can fail
/// when it stops being true. `NoReflectionPrompt` answering null is the
/// default; a test that never reads the real provider never disturbs it. The
/// question worth asking of a guard is not whether a test exists but whether a
/// test exists that could fail.
void main() {
  late TestStore store;
  late TestClock clock;
  late FakeNotificationGateway gateway;

  // Thursday evening, with a completion this morning to ask about.
  final now = DateTime(2026, 3, 12, 18);

  setUp(() async {
    clock = TestClock(now);
    store = await openFakeStore(clock);
    addTearDown(store.dispose);
    gateway = FakeNotificationGateway();
  });

  ProviderContainer containerWith() {
    final container = ProviderContainer(
      overrides: [
        habitServiceProvider.overrideWithValue(store.habits),
        completionServiceProvider.overrideWithValue(store.completions),
        reflectionServiceProvider.overrideWithValue(store.reflections),
        nudgeServiceProvider.overrideWithValue(store.nudges),
        notificationGatewayProvider.overrideWithValue(gateway),
        clockProvider.overrideWithValue(() => clock.now),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('the app queues notifications that carry the question', () async {
    await store.habits.saveHabit(
      testHabit(
        name: 'Morning run',
        category: HabitCategory.exercise,
        designedCue: 'after breakfast',
        designedCueType: CueType.event,
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    await store.completions.recordCompletion(
      Completion(
        id: 'c1',
        habitId: 'habit-1',
        completedAt: DateTime(2026, 3, 12, 7, 10),
        source: CompletionSource.tap,
      ),
    );

    final container = containerWith();
    await container.read(nudgeSchedulerProvider).planAll();

    expect(gateway.everyScheduleCall, isNotEmpty);
    final tonight = gateway.everyScheduleCall.first;

    // The reflection half above the nudge half, in one message — and a real
    // sentence, which is the only assertion that can tell a composer that was
    // wired from one that was not.
    expect(
      tonight.checkIn.body,
      startsWith('Did after breakfast kick it off?'),
    );
    expect(tonight.checkIn.body, contains('Tomorrow, then'));
  });
}
