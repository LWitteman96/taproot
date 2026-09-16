import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:taproot/core/models/habit.dart';
import 'package:taproot/features/habits/providers/habit_providers.dart';
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
