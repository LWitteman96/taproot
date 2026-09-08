import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/startup/app_startup.dart';
import 'package:taproot/app/theme/app_dimensions.dart';
import 'package:taproot/app/theme/app_spacing.dart';

/// Gates the app on [appStartupProvider].
///
/// Guide §4 puts this above the router: until the local store is open there is
/// nothing to route to, because every screen reads from it. Waiting and failing
/// are both real screens rather than a spinner and a `throw` — the database is
/// the primary store, so failing to open it is a condition the user has to be
/// able to see and act on.
class AppStartupWidget extends ConsumerWidget {
  const AppStartupWidget({super.key, this.child});

  /// The app itself — in practice `MaterialApp.router`'s navigator.
  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The order is deliberate. Riverpod keeps the previous state while a
    // provider reloads, so a retry arrives as an *error that is also loading* —
    // matching the error case first would leave the failure screen up with a
    // dead-looking button for as long as the retry takes. And a later refresh
    // of a startup that already succeeded must not blank the app, which is what
    // the `hasValue` case ahead of everything else protects.
    return switch (ref.watch(appStartupProvider)) {
      AsyncValue(hasValue: true) => child ?? const SizedBox.shrink(),
      AsyncError(isLoading: false, :final error) => AppStartupErrorScreen(
        error: error,
        onRetry: () =>
            retryAppStartup(ProviderScope.containerOf(context, listen: false)),
      ),
      _ => const AppStartupLoadingScreen(),
    };
  }
}

/// Shown while the store opens.
///
/// Deliberately quiet: opening a local SQLite file takes a few frames, and a
/// screen that announces itself would flash. It carries a semantics label
/// anyway, because a screen reader has no way to see that nothing is happening.
class AppStartupLoadingScreen extends StatelessWidget {
  const AppStartupLoadingScreen({super.key});

  static const String semanticsLabel = 'Opening your garden';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SizedBox.square(
          dimension: AppDimensions.progressIndicatorSize,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            semanticsLabel: semanticsLabel,
          ),
        ),
      ),
    );
  }
}

/// Shown when the store could not be opened.
///
/// The copy stays in the app's own voice rather than reporting a fault — the
/// user did nothing wrong and there is exactly one useful action. The technical
/// detail sits underneath in the muted style, because on a dev build it is the
/// only place the error is visible at all.
class AppStartupErrorScreen extends StatelessWidget {
  const AppStartupErrorScreen({
    required this.error,
    required this.onRetry,
    super.key,
  });

  final Object error;
  final VoidCallback onRetry;

  static const String headline = 'Your garden could not be opened';
  static const String body =
      'Nothing has been lost — the app just could not reach its own store on '
      'this device. Try again, and if it keeps happening, restarting the app '
      'usually clears it.';
  static const String retryLabel = 'Try again';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.pageHorizontal,
              vertical: AppSpacing.pageVertical,
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
                  const SizedBox(height: AppSpacing.medium),
                  Text(body, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: AppSpacing.large),
                  FilledButton(
                    onPressed: onRetry,
                    child: const Text(retryLabel),
                  ),
                  const SizedBox(height: AppSpacing.large),
                  Text(
                    '$error',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
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
