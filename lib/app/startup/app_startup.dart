import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/database/database_provider.dart';
import 'package:taproot/app/sync/sync_service.dart';
import 'package:taproot/features/notifications/providers/nudge_providers.dart';

/// Everything that has to finish before the app can show its first screen.
///
/// Guide §4's slot. Three steps: open the local store, start sync listening,
/// then initialise the notification plugin and re-plan the evening check-ins.
/// It is typed `<void>` because callers depend on "startup finished", never on
/// what it returned.
///
/// The order is not arbitrary — planning reads the ledger, so the store has to
/// be open first, and sync sits between them for a reason of its own (below).
/// Nor is the asymmetry in how they fail: a store that will not open gets an
/// error screen with a retry, and a notification platform that will not
/// initialise does not, because the app is fully usable without it.
final appStartupProvider = FutureProvider<void>((ref) async {
  await ref.watch(openedDatabaseProvider.future);
  if (!ref.mounted) return;

  // Started here, and deliberately *not* awaited: sync is not something the
  // first frame waits for. What this line buys is that something listens to it
  // for the lifetime of the app.
  //
  // That is load-bearing rather than tidy. Riverpod 3 pauses a provider whose
  // listeners are all paused, and a provider nobody listens to at all is in
  // that set — so without this, `SyncService` builds, subscribes to
  // connectivity, is immediately paused, and never hears the network come
  // back. Nothing looks wrong: the state reads `idle`, which is also what a
  // working sync with nothing to do reads.
  //
  // It cannot hang off a widget instead. Sync has to run whether or not any
  // screen happens to be showing its status, and this slot is exactly what
  // guide §4 describes it for — in inkBlox it earns its keep by doing nothing
  // but holding a listener alive.
  //
  // **After the store, before the notifications.** After, because the drain
  // reads the local database and one that fired first would fail on launch for
  // no reason. Before, because the notification step *can* fail — that is the
  // designed asymmetry above — and a device with notifications denied or a
  // plugin that will not initialise must still back its garden up.
  ref.listen(syncServiceProvider, (previous, next) {});

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
