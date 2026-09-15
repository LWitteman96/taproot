import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/database/database_provider.dart';
import 'package:taproot/features/notifications/providers/nudge_providers.dart';

/// Everything that has to finish before the app can show its first screen.
///
/// Guide §4's slot. Two steps: open the local store, then initialise the
/// notification plugin and re-plan the evening check-ins. It is typed `<void>`
/// because callers depend on "startup finished", never on what it returned.
///
/// The order is not arbitrary — planning reads the ledger, so the store has to
/// be open first. Nor is the asymmetry in how they fail: a store that will not
/// open gets an error screen with a retry, and a notification platform that
/// will not initialise does not, because the app is fully usable without it.
final appStartupProvider = FutureProvider<void>((ref) async {
  await ref.watch(openedDatabaseProvider.future);
  await ref.watch(notificationStartupProvider.future);
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
  container.invalidate(notificationStartupProvider);
  container.invalidate(appStartupProvider);
}
