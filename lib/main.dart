import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/logging/logging.dart';
import 'package:taproot/app/router/app_router.dart';
import 'package:taproot/app/startup/app_startup_widget.dart';
import 'package:taproot/app/theme/themedata.dart';

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
///   await Supabase.initialize(url, anonKey)
///   SentryFlutter.init(appRunner: ...)
/// Supabase and Sentry are omitted deliberately rather than stubbed: the .env
/// files hold no credentials yet, and Supabase.initialize on an empty URL
/// throws at launch. Add them alongside the first real backend call.
Future<void> runMainApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  setupLogging();
  runApp(const ProviderScope(child: TaprootApp()));
}

class TaprootApp extends ConsumerWidget {
  const TaprootApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
