import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:taproot/app/database/database_provider.dart';
import 'package:taproot/app/runtime/runtime_providers.dart';
import 'package:taproot/features/habits/providers/habit_providers.dart';
import 'package:taproot/features/notifications/domain/evening_check_in.dart';
import 'package:taproot/features/notifications/domain/notification_access.dart';
import 'package:taproot/features/notifications/domain/notification_gateway.dart';
import 'package:taproot/features/notifications/domain/nudge_repository.dart';
import 'package:taproot/features/notifications/services/disabled_notification_gateway.dart';
import 'package:taproot/features/notifications/services/local_notification_gateway.dart';
import 'package:taproot/features/notifications/services/local_nudge_service.dart';
import 'package:taproot/features/notifications/services/nudge_response_recorder.dart';
import 'package:taproot/features/notifications/services/nudge_scheduler.dart';

final nudgeServiceProvider = Provider<NudgeRepository>(
  (ref) => LocalNudgeService(database: ref.watch(appDatabaseProvider)),
);

final nudgeResponseRecorderProvider = Provider<NudgeResponseRecorder>(
  (ref) => NudgeResponseRecorder(nudges: ref.watch(nudgeServiceProvider)),
);

/// The platform seam. Overridden with a fake in every test that reaches the
/// scheduler, which is why nothing above it ever touches the plugin directly.
///
/// Off Android and iOS it resolves to the disabled gateway rather than to a
/// plugin with no host implementation — so the desktop test host runs the real
/// startup path in the app's real denied-permission mode.
final notificationGatewayProvider = Provider<NotificationGateway>((ref) {
  if (!supportsLocalNotifications) return const DisabledNotificationGateway();
  return LocalNotificationGateway(
    onResponse: (response) =>
        ref.read(nudgeResponseRecorderProvider).record(response),
  );
});

/// Initialises the plugin and re-plans every habit's upcoming occasions.
///
/// Awaited by `appStartupProvider`, because a launch is the app's only
/// reliable chance to notice that the phone was off for a week, that a nudge
/// fired while it was, or that the ledger is missing occasions nobody was
/// around to record.
///
/// **It never fails the launch.** A notification platform that will not
/// initialise is a degraded mode, not a reason to hold the garden behind an
/// error screen — the completion tap has to work either way. The failure is
/// logged and the app carries on with no notifications, which is a mode it
/// already handles.
final notificationStartupProvider = FutureProvider<void>((ref) async {
  final log = Logger('notificationStartup');
  final scheduler = ref.watch(nudgeSchedulerProvider);

  try {
    final gateway = ref.watch(notificationGatewayProvider);
    await gateway.initialize();

    // Awaited, because it is the only moment a cold-start answer can be
    // recorded — neither response callback fires for the notification that
    // launched the app — and because the screen behind it may show the habit
    // it concerns.
    final launch = await gateway.launchResponse();
    if (launch != null) {
      await ref.read(nudgeResponseRecorderProvider).record(launch);
    }

    // **Not** awaited. A full pass is a per-habit history load, up to ~37
    // ledger writes after a quiet week, and a platform call per queued nudge —
    // and nothing on the first screen reads any of it. The doc above says a
    // notification failure never gates the launch; the same has to hold for
    // its latency. It stays in this chain rather than becoming a bare
    // `unawaited` at the top, so the pass still runs after the launch answer
    // is in the ledger and sees it.
    // The one cost of not awaiting: a startup retry invalidates the database
    // provider and closes the handle, which can land mid-pass. That surfaces
    // here as a logged failure rather than a crash, and the retry's own pass
    // replaces it — the ledger is rebuilt from the calendar every time, so a
    // pass that dies half-written loses nothing that the next one will not
    // write again.
    unawaited(
      scheduler.planAll().catchError((Object error, StackTrace stackTrace) {
        log.severe('the launch re-plan did not finish', error, stackTrace);
        return const NudgePlan(
          access: NotificationAccess.denied,
          occasions: <PlannedOccasion>[],
        );
      }),
    );
  } catch (error, stackTrace) {
    log.severe(
      'notification scheduling is unavailable this launch',
      error,
      stackTrace,
    );
  }
});

/// The reflection question that rides along on the evening notification.
///
/// Left as the no-op composer and overridden by the reflection feature when it
/// lands — the point being that the *notification* is one object with one
/// slot, not two features racing for the same evening (reflection spec §1).
///
/// **Two call sites read this, and they have to stay the same call.**
/// `NudgeScheduler._queue` composes what is sent; `notificationPreviewProvider`
/// composes what the invitation screen shows. That screen's entire claim is
/// that it cannot promise something the app does not send, and overriding this
/// provider is what makes the claim testable at all: while [NoReflectionPrompt]
/// is installed the prompt is always null, and null is indistinguishable from
/// an omitted argument at both ends — which is exactly how the two drifted the
/// first time. Any change to what this composes belongs in
/// `test/features/notifications/notification_invitation_page_test.dart` as well
/// as in the scheduler's tests.
final reflectionPromptComposerProvider = Provider<ReflectionPromptComposer>(
  (ref) => const NoReflectionPrompt(),
);

final nudgeSchedulerProvider = Provider<NudgeScheduler>(
  (ref) => NudgeScheduler(
    habits: ref.watch(habitServiceProvider),
    nudges: ref.watch(nudgeServiceProvider),
    inputs: ref.watch(habitInputsLoaderProvider),
    gateway: ref.watch(notificationGatewayProvider),
    reflection: ref.watch(reflectionPromptComposerProvider),
    clock: ref.watch(clockProvider),
    // Deliberately *not* wired to newIdProvider. The ledger mints its own
    // UUIDs — the same v4 either way in production — because sharing one
    // sequence makes every test that pins an id depend on how many occasions
    // the scheduler happened to plan first. It cost an unrelated completion
    // its expected id the moment the garden started re-planning.
  ),
);

/// What the app is allowed to post, right now.
///
/// A `FutureProvider` rather than a field on some state object because denial
/// is an app mode the UI renders (guide §2): the screens that explain the
/// no-notifications experience watch this, and it is invalidated after the
/// permission prompt and on resume from system settings.
final notificationAccessProvider = FutureProvider<NotificationAccess>(
  (ref) => ref.watch(notificationGatewayProvider).currentAccess(),
);

/// Prompts for permission and re-plans, since granting it turns every
/// already-recorded future occasion into one that could carry a nudge.
Future<NotificationAccess> requestNotificationAccess(
  ProviderContainer container,
) async {
  final access = await container
      .read(notificationGatewayProvider)
      .requestAccess();
  container.invalidate(notificationAccessProvider);

  // The answer is known the moment the dialog closes; the re-plan is a habit
  // list, full histories, ledger writes and platform calls. Awaiting it would
  // stall the permission screen for a stretch proportional to how many habits
  // the user has, after a dialog they have already dismissed. The ledger
  // invariant does not depend on the caller waiting, and the pass owns its own
  // failures.
  unawaited(
    container.read(nudgeSchedulerProvider).planAll().catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      Logger(
        'requestNotificationAccess',
      ).severe('the post-permission re-plan did not finish', error, stackTrace);
      return const NudgePlan(
        access: NotificationAccess.denied,
        occasions: <PlannedOccasion>[],
      );
    }),
  );
  return access;
}
