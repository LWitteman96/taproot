import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/database/database_provider.dart';

/// Everything that has to finish before the app can show its first screen.
///
/// Guide §4's slot. It holds one step today — opening the local store — and is
/// typed `<void>` because it will hold several: timezone database
/// initialisation, the notification permission check, and scheduling the
/// evening check-in all land here in later branches. Callers depend on "startup
/// finished", never on what it returned.
final appStartupProvider = FutureProvider<void>((ref) async {
  await ref.watch(openedDatabaseProvider.future);
});

/// Re-runs startup from the top.
///
/// **What it invalidates is the whole point.** Invalidating [appStartupProvider]
/// alone re-runs its body, but that body only awaits [openedDatabaseProvider] —
/// which is still holding the error it cached the first time. The retry would
/// re-read the old failure and the button would do nothing, convincingly.
/// So the provider that did the failing work is the one that gets invalidated;
/// the startup provider rebuilds behind it because it depends on it, and is
/// invalidated too so that a future step of its own is reset with it.
///
/// It takes a [ProviderContainer] rather than a `WidgetRef` so the retry button
/// and the test that proves the retry re-opens the database run the exact same
/// code. Riverpod does not export the type the two `invalidate` methods share,
/// and a second copy of these two calls is precisely how the two drift apart.
///
/// Every future step added to [appStartupProvider] that caches its own failure
/// belongs here too.
void retryAppStartup(ProviderContainer container) {
  container.invalidate(openedDatabaseProvider);
  container.invalidate(appStartupProvider);
}
