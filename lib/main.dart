import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/core/utils/flavor.dart';

/// Shared bootstrap for every flavor entry point.
///
/// The full startup chain is specified in docs/infrastructure-guide.md §4 and
/// is not wired up yet — it adds, in order:
///   SentryWidgetsFlutterBinding.ensureInitialized()  (enables frame tracking)
///   setupLogging()
///   await Supabase.initialize(url, anonKey)
///   SentryFlutter.init(appRunner: ...)
/// Supabase and Sentry are omitted deliberately rather than stubbed: the .env
/// files hold no credentials yet, and Supabase.initialize on an empty URL throws
/// at launch. Add them alongside the first real backend call.
Future<void> runMainApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: TaprootApp()));
}

class TaprootApp extends ConsumerWidget {
  const TaprootApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Taproot',
      // State restoration, so an in-progress reflection check-in survives
      // Android killing the process in the background (guide §4).
      restorationScopeId: 'taproot',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4F6F52)),
      ),
      home: const _PlaceholderHome(),
    );
  }
}

/// Temporary landing screen. It exists to make the active flavor visible so the
/// native flavor configuration can be verified end to end; the garden replaces
/// it once the engine and habit store are in place.
class _PlaceholderHome extends StatelessWidget {
  const _PlaceholderHome();

  @override
  Widget build(BuildContext context) {
    final flavor = getFlavor();
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Taproot', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'flavor: ${flavor.name}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
