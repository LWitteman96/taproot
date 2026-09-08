import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:taproot/app/theme/app_dimensions.dart';
import 'package:taproot/app/theme/app_spacing.dart';
import 'package:taproot/features/garden/pages/garden_page.dart';
import 'package:taproot/features/habits/pages/habit_creation_page.dart';

/// Every path in the app, in one place.
abstract final class AppRoutes {
  /// The garden. Home is accumulated progress, not a task list (design-spec §6).
  static const String garden = '/';

  /// Where a user with no habits yet is sent.
  static const String habitCreation = '/habits/new';
}

/// What the router needs to know about a user before letting them in.
///
/// Guide §7's shape, with Taproot's contents. It is one field today because
/// there is only one thing worth gating on that the app could ever answer;
/// `hasProfile` joins it when auth lands, and `notificationsDecided` when the
/// permission flow does.
typedef AppGate = ({bool hasFirstHabit});

/// The gate that lets everything through.
const AppGate openAppGate = (hasFirstHabit: true);

/// The gate used when the real one could not be resolved.
///
/// Guide §7: "needs onboarding, not restricted". Both halves matter. Sending a
/// user who *does* have habits into habit creation costs them one tap on the
/// way back; refusing entry to a user whose profile read timed out costs them
/// the app. So the safe answer is always the one that keeps moving.
const AppGate failSafeAppGate = (hasFirstHabit: false);

/// How the gate gets resolved. The seam tests override.
final appGateResolverProvider = Provider<Future<AppGate> Function()>(
  (ref) => resolveAppGate,
);

/// Resolves the gate.
///
/// **Stubbed.** There is no auth, no profile row and no habit creation yet, so
/// there is nothing to read and nothing that could route a user anywhere useful
/// — reporting "no habits" today would strand every launch on a placeholder.
/// It returns the open gate until the habit count is real.
///
/// What is *not* stubbed is the failure path in [appGateProvider]. That is the
/// half that is easy to get wrong later, so it is written and tested now.
Future<AppGate> resolveAppGate() async => openAppGate;

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
String? redirectFor(AppGate? gate, String location) {
  if (location != AppRoutes.garden) return null;
  if (gate == null) return null;
  return gate.hasFirstHabit ? null : AppRoutes.habitCreation;
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
