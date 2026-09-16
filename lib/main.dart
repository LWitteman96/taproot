import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:taproot/app/logging/logging.dart';
import 'package:taproot/app/router/app_router.dart';
import 'package:taproot/app/startup/app_startup_widget.dart';
import 'package:taproot/app/supabase/supabase_config.dart';
import 'package:taproot/app/theme/themedata.dart';
import 'package:taproot/features/notifications/providers/notification_onboarding_providers.dart';

/// Shared bootstrap for every flavor entry point.
///
/// The full startup chain is specified in docs/infrastructure-guide.md §4. The
/// asynchronous half of it — opening the local store, and later the timezone
/// database, the notification permission check and the evening check-in — lives
/// in `appStartupProvider` rather than here, so it has loading and error states
/// instead of a chance to fail before the first frame.
///
/// What is still missing from this function, in the order §4 puts it:
///   SentryWidgetsFlutterBinding.ensureInitialized()  (enables frame tracking)
///   SentryFlutter.init(appRunner: ...)
/// Sentry is omitted deliberately rather than stubbed: no DSN exists yet, and
/// a stub would be a second thing to remove later. Add it with the first real
/// crash budget.
Future<void> runMainApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  setupLogging();
  await _initialiseSupabase();
  runApp(const ProviderScope(child: TaprootApp()));
}

/// Brings up Supabase, if this flavor has a backend to bring up.
///
/// The conditional is not defensive coding — it is the difference between a
/// flavor that runs and one that cannot start. Only `.env.dev` holds real
/// credentials; stg and prod are placeholders until a remote project is
/// provisioned, and `Supabase.initialize` on an empty URL throws before the
/// first frame.
///
/// Skipping is safe in a way it would not be in most apps, because SQLite is
/// the *primary* store rather than a cache: the app is fully usable with no
/// backend at all, and what is lost is durable backup and cross-device sync.
/// `SyncService` reports that as `SyncStatus.unavailable` rather than as a
/// sync that is idle forever, so nothing tells the user their work is backed
/// up when it is not.
Future<void> _initialiseSupabase() async {
  final config = SupabaseConfig.fromEnvironment(loadedEnvironment());
  if (!config.isConfigured) {
    Logger('Bootstrap').warning(
      'no Supabase credentials for this flavor — starting without a backend. '
      'The local store is primary, so the app works; nothing is backed up.',
    );
    return;
  }
  await Supabase.initialize(
    url: config.url,
    publishableKey: config.publishableKey,
  );
}

class TaprootApp extends ConsumerWidget {
  const TaprootApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watched, not read, and watched *here* because this widget outlives every
    // screen. Riverpod 3 pauses a provider whose listeners are all paused —
    // and one nobody listens to is in that set — so a lifecycle listener
    // parked in a provider nothing watches never fires, and the app would go
    // on believing it may post notifications after the user switched them off
    // in system settings.
    ref.watch(notificationAccessRefreshProvider);

    return MaterialApp.router(
      title: 'Taproot',
      // State restoration, so an in-progress reflection check-in survives
      // Android killing the process in the background (guide §4).
      restorationScopeId: 'taproot',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: ref.watch(goRouterProvider),
      // Startup gates the whole app rather than one route, and sits *inside*
      // MaterialApp so its loading and error screens get the theme, the
      // directionality and the media query like any other screen.
      builder: (context, child) => AppStartupWidget(child: child),
    );
  }
}
