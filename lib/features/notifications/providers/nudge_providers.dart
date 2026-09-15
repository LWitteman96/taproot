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
  try {
    final gateway = ref.watch(notificationGatewayProvider);
    await gateway.initialize();

    // Before planning: an answer that cold-started the app reaches neither
    // response callback, so this is the only moment it can be recorded. Ask
    // first, so the plan that follows sees the ledger the user just changed.
    final launch = await gateway.launchResponse();
    if (launch != null) {
      await ref.read(nudgeResponseRecorderProvider).record(launch);
    }

    await ref.watch(nudgeSchedulerProvider).planAll();
  } catch (error, stackTrace) {
    Logger('notificationStartup').severe(
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
  await container.read(nudgeSchedulerProvider).planAll();
  return access;
}
