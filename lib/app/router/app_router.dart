import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:taproot/app/startup/app_startup.dart';
import 'package:taproot/app/theme/app_dimensions.dart';
import 'package:taproot/app/theme/app_spacing.dart';
import 'package:taproot/features/garden/pages/garden_page.dart';
import 'package:taproot/features/habits/domain/habit_repository.dart';
import 'package:taproot/features/habits/pages/habit_creation_page.dart';
import 'package:taproot/features/habits/providers/habit_providers.dart';
import 'package:taproot/features/notifications/domain/notification_invitation.dart';
import 'package:taproot/features/notifications/pages/notification_invitation_page.dart';
import 'package:taproot/features/notifications/providers/notification_onboarding_providers.dart';
import 'package:taproot/features/reflection/pages/check_in_page.dart';
import 'package:taproot/features/reflection/services/check_in_assembler.dart';

/// Every path in the app, in one place.
abstract final class AppRoutes {
  /// The garden. Home is accumulated progress, not a task list (design-spec §6).
  static const String garden = '/';

  /// Where a user with no habits yet is sent.
  static const String habitCreation = '/habits/new';

  /// The notification invitation, offered once, after the first habit.
  static const String notificationInvitation = '/notifications/invitation';

  /// The evening check-in. Reached from the garden today, and from the evening
  /// notification once that seam is wired.
  static const String checkIn = '/check-in';
}

/// What the router needs to know about a user before letting them in.
///
/// Guide §7's shape, with Taproot's contents. `hasProfile` joins these when
/// auth lands.
typedef AppGate = ({bool hasFirstHabit, bool notificationsOffered});

/// The gate that lets everything through.
const AppGate openAppGate = (hasFirstHabit: true, notificationsOffered: true);

/// The gate used when the real one could not be resolved.
///
/// Guide §7: "needs onboarding, not restricted". Both halves matter. Sending a
/// user who *does* have habits into habit creation costs them one tap on the
/// way back; refusing entry to a user whose profile read timed out costs them
/// the app. So the safe answer is always the one that keeps moving.
///
/// The two fields fail in opposite directions, and deliberately. Habit
/// creation is somewhere to *be* — a user with an empty garden has nowhere
/// else — so an unresolved gate sends them there. The notification invitation
/// is somewhere to be *asked*, and a failed read is not a reason to interrupt
/// someone with a permission request they may already have answered, so that
/// half fails as offered.
const AppGate failSafeAppGate = (
  hasFirstHabit: false,
  notificationsOffered: true,
);

/// How the gate gets resolved. The seam tests override.
///
/// The startup future is **watched** here and awaited inside the closure, which
/// is doing two things at once. Awaiting it means the gate is never answered
/// before the local store is open — `habitServiceProvider` reads the database
/// synchronously and throws until then, and a gate that resolved from that
/// throw would report "no habits" on every cold start and send a user with a
/// full garden into habit creation. Watching it means that when a failed
/// startup is retried, this provider is rebuilt and the gate is asked again
/// rather than serving the fail-safe it cached the first time.
final appGateResolverProvider = Provider<Future<AppGate> Function()>((ref) {
  final startup = ref.watch(appStartupProvider.future);
  return () async {
    await startup;
    return resolveAppGate(
      habits: ref.read(habitServiceProvider),
      invitations: ref.read(notificationInvitationStoreProvider),
    );
  };
});

/// Resolves the gate: has this user planted anything, and have they been asked
/// about notifications.
///
/// The first habit is what the app needs before it has a home screen worth
/// showing — the garden leads with accumulated progress (design-spec §6), and
/// an empty one has none.
///
/// The invitation is read from the app's own record rather than from the
/// platform, because the platform cannot answer it: Android reports the same
/// "not enabled" for a user who refused and a user nobody has asked. See
/// [NotificationInvitationStore].
///
/// Takes the repositories rather than a `Ref` so it can be tested as a
/// function.
Future<AppGate> resolveAppGate({
  required HabitRepository habits,
  required NotificationInvitationStore invitations,
}) async => (
  hasFirstHabit: (await habits.allHabits()).isNotEmpty,
  notificationsOffered: await invitations.hasBeenOffered(),
);

/// The gate, resolved, with the failure folded into a value.
///
/// The `catch` is the point of this provider. A gate that can throw makes the
/// redirect below have to decide what an error means at the moment it is least
/// able to — mid-navigation — so the error is turned into [failSafeAppGate]
/// here instead, and the redirect only ever sees a gate.
final appGateProvider = FutureProvider.autoDispose<AppGate>((ref) async {
  try {
    return await ref.watch(appGateResolverProvider)();
  } catch (_) {
    return failSafeAppGate;
  }
});

/// Where [gate] should send someone standing on [location], if anywhere.
///
/// Pulled out of the router so it can be tested as a function rather than by
/// driving a navigator. Two rules:
///
/// - It only evaluates on the root path. inkBlox's guard re-runs on every
///   navigation otherwise, which turns one profile read into one per push.
/// - A `null` gate — not resolved yet — never redirects. Guessing during the
///   loading frame is how a guard bounces a user off a screen they were
///   entitled to.
///
/// The order of the two questions is the onboarding order, and it is the
/// product decision rather than an implementation detail: nobody is asked to
/// accept notifications before they have a habit worth being notified about.
/// Habit creation leaves for the garden, lands on the root path, and this sends
/// them on to the invitation — so the invitation arrives on the beat after
/// planting, without habit creation having to know it exists.
String? redirectFor(AppGate? gate, String location) {
  if (location != AppRoutes.garden) return null;
  if (gate == null) return null;
  if (!gate.hasFirstHabit) return AppRoutes.habitCreation;
  if (!gate.notificationsOffered) return AppRoutes.notificationInvitation;
  return null;
}

/// The app's router: a flat route list plus one gate (guide §7).
final goRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.garden,
    redirect: (context, state) =>
        redirectFor(ref.read(appGateProvider).value, state.matchedLocation),
    errorBuilder: (context, state) =>
        AppRouteErrorPage(location: state.uri.toString()),
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.garden,
        builder: (context, state) => const GardenPage(),
      ),
      GoRoute(
        path: AppRoutes.habitCreation,
        builder: (context, state) => const HabitCreationPage(),
      ),
      GoRoute(
        path: AppRoutes.notificationInvitation,
        builder: (context, state) => const NotificationInvitationPage(),
      ),
      GoRoute(
        path: AppRoutes.checkIn,
        // The garden hands its already-assembled offer over as `extra`, so the
        // screen re-verifies one habit instead of re-electing a winner among
        // all of them. Absent — a deep link, a cold start on this path — the
        // screen assembles from scratch.
        builder: (context, state) =>
            CheckInPage(offered: state.extra as CheckInOffer?),
      ),
    ],
  );

  // The gate resolves after the first redirect has already run, so without this
  // the guard would evaluate exactly once, against a loading value, and never
  // again. Refreshing re-runs it — and keeps the autoDispose gate alive for as
  // long as the router is.
  ref.listen(appGateProvider, (previous, next) => router.refresh());
  ref.onDispose(router.dispose);

  return router;
});

/// Shown for a path the router does not know.
///
/// A skeleton needs this more than a finished app does: half the routes it will
/// eventually carry do not exist yet, and a deep link into one of them should
/// land somewhere with a way out rather than on a red screen.
class AppRouteErrorPage extends StatelessWidget {
  const AppRouteErrorPage({required this.location, super.key});

  final String location;

  static const String headline = 'There is nothing here yet';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.pageHorizontal,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppDimensions.maximumContentWidth,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(headline, style: theme.textTheme.headlineMedium),
                  const SizedBox(height: AppSpacing.small),
                  Text(location, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: AppSpacing.large),
                  FilledButton(
                    onPressed: () => context.go(AppRoutes.garden),
                    child: const Text('Back to the garden'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
