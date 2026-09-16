import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:taproot/app/runtime/runtime_providers.dart';
import 'package:taproot/core/engine/constants.dart';
import 'package:taproot/core/models/habit.dart';
import 'package:taproot/core/utils/local_dates.dart';
import 'package:taproot/features/habits/providers/habit_providers.dart';
import 'package:taproot/features/notifications/domain/evening_check_in.dart';
import 'package:taproot/features/notifications/domain/expected_occasions.dart';
import 'package:taproot/features/notifications/domain/notification_access.dart';
import 'package:taproot/features/notifications/domain/notification_invitation.dart';
import 'package:taproot/features/notifications/providers/nudge_providers.dart';
import 'package:taproot/features/notifications/services/nudge_scheduler.dart';
import 'package:taproot/features/notifications/services/preferences_invitation_store.dart';

final notificationInvitationStoreProvider =
    Provider<NotificationInvitationStore>(
      (ref) => PreferencesInvitationStore(),
    );

/// The habit the invitation speaks about: the most recently planted one.
///
/// The invitation arrives straight after a habit is planted, so this is the
/// cue the user has just finished designing — which is what lets the screen
/// show the real notification rather than describe one. Null when there are no
/// habits, or when the store cannot be read; the screen then makes the offer
/// in general terms rather than failing.
final newestHabitProvider = FutureProvider<Habit?>((ref) async {
  final habits = await ref.watch(habitServiceProvider).allHabits();
  return habits.isEmpty ? null : habits.last;
});

/// The notification the invitation screen shows, composed the way the
/// scheduler composes the one it sends.
///
/// **The screen's whole claim is that it cannot promise something the app does
/// not send, and that only holds if it goes through the same call.** There are
/// three parts to "the same call", and the seam was open at all three:
///
/// - `composeEveningCheckIn` takes a `reflectionPrompt`, which the scheduler
///   fills from [reflectionPromptComposerProvider]. A preview that omits the
///   argument matched a scheduler that passed it only because the stand-in
///   composer always answered null — so the wire was untested by construction,
///   and the day a real composer lands the sent body gains a line the preview
///   does not show, silently.
/// - The occasion is the habit's **real next one**, derived from the same
///   calendar the scheduler plans over, rather than a fabricated
///   `ExpectedOccasion(index: 0, …)`. `composeEveningCheckIn` ignores the index
///   today; a fabricated one is a fact waiting to be believed.
/// - The delivery instant is [nudgeDeliveryTime] of that occasion, because the
///   composer is given it and may score on it.
///
/// Null when there is no habit yet, or no occasion inside the planning horizon
/// — a paused habit, most likely. The screen then makes the offer in general
/// terms rather than showing an invented notification.
///
/// One honest limitation, since this is the screen that is not allowed to
/// mislead: at the invitation the real composer is expected to answer *null*,
/// because priority is scored per occasion and a habit planted a minute ago has
/// none. So the preview is least representative for exactly the habit the user
/// is looking at. That is why the copy around it says the reflection question
/// is occasional rather than promising it every evening.
final notificationPreviewProvider = FutureProvider<EveningCheckIn?>((
  ref,
) async {
  final habit = await ref.watch(newestHabitProvider.future);
  if (habit == null) return null;

  final occasion = nextNudgeableOccasion(
    habit: habit,
    now: ref.watch(clockProvider)(),
  );
  if (occasion == null) return null;

  final deliverAt = nudgeDeliveryTime(occasion);
  final prompt = await ref
      .watch(reflectionPromptComposerProvider)
      .promptFor(habit: habit, occasion: occasion, deliverAt: deliverAt);

  return composeEveningCheckIn(
    habit: habit,
    occasion: occasion,
    reflectionPrompt: prompt,
  );
});

/// The first occasion inside the planning horizon whose evening is still
/// ahead, or null.
///
/// Pauses are deliberately not loaded: this runs on the beat after a habit is
/// planted, so there are none, and reaching for the inputs loader here would
/// buy a database round trip to answer a question that cannot yet be yes.
@visibleForTesting
ExpectedOccasion? nextNudgeableOccasion({
  required Habit habit,
  required DateTime now,
}) {
  final today = LocalDate.from(now);
  final occasions = expectedOccasionsBetween(
    createdAt: habit.createdAt,
    targetFrequency: habit.targetFrequency,
    from: today,
    to: today.addDays(EngineConstants.nudgeHorizonDays),
  );
  for (final occasion in occasions) {
    // `isAfter(now)`, the same test the scheduler applies before queueing:
    // tonight's eight o'clock is a real occasion at seven and a notification
    // nobody will get at nine.
    if (nudgeDeliveryTime(occasion).isAfter(now)) return occasion;
  }
  return null;
}

/// Keeps [notificationAccessProvider] honest across a trip to system settings.
///
/// Permission is revocable, and it is revoked *outside the app* — the user
/// walks to Settings, switches Taproot's notifications off, and comes back.
/// Nothing tells the app. Without this, a screen that read access once would
/// keep describing a state that stopped being true while it was backgrounded,
/// and the app would go on believing it was nudging.
///
/// **Somebody has to hold this provider.** The listener is registered in the
/// body below, so a provider nothing ever touches is a listener that does not
/// exist — and nothing looks wrong, because an app that never notices a
/// revocation and an app where nothing was revoked read the same.
/// `TaprootApp` watches it for the life of the app, which is the only scope
/// that makes sense for "notice when the user comes back".
///
/// The guard on that is a widget test that pumps `TaprootApp` and drives a
/// resume through it, not a unit test with a hand-made container: the thing
/// that can break is the wiring, and a container that subscribes by hand
/// supplies the very thing whose absence is the bug.
final notificationAccessRefreshProvider = Provider<void>((ref) {
  final log = Logger('notificationAccessRefresh');

  final listener = AppLifecycleListener(
    onResume: () {
      ref.invalidate(notificationAccessProvider);

      // Revocation is the case this exists for, but the mirror case is the one
      // that needs work done rather than merely noticed: a user who turned
      // notifications *on* in settings has occasions already recorded and
      // nothing queued for them, and would get silence until the next launch or
      // the next completion. Re-planning is idempotent, so doing it on a resume
      // that changed nothing costs a pass that writes nothing.
      unawaited(
        ref.read(nudgeSchedulerProvider).planAll().catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          log.severe('the resume re-plan did not finish', error, stackTrace);
          return const NudgePlan(
            access: NotificationAccess.denied,
            occasions: <PlannedOccasion>[],
          );
        }),
      );
    },
  );

  ref.onDispose(listener.dispose);
});
