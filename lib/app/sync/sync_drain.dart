import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/database/database_provider.dart';
import 'package:taproot/app/supabase/supabase_config.dart';
import 'package:taproot/app/sync/local_sync_store.dart';
import 'package:taproot/app/sync/remote_sync_store.dart';
import 'package:taproot/app/sync/two_way_sync_drain.dart';

/// One round of synchronisation: push everything pending, pull everything new.
///
/// The seam between [SyncService], which decides *when* to sync, and the code
/// that knows *what* the tables are. They are split because they change for
/// completely different reasons — the trigger is a connectivity question and is
/// finished; the drain is a schema question and is not — and because it lets
/// the trigger be tested exhaustively against a fake without a database or a
/// network anywhere near it.
///
/// Two properties the implementation has to hold, both relied on above:
///
/// - **Idempotent.** `isOnlineProvider` reports an interface, not reachability,
///   so a drain will be started on connections that turn out to be captive
///   portals and tunnels to nowhere. Running twice, or running against a
///   half-finished previous attempt, must be safe. Every table in the schema
///   upserts on a key the device minted, which is what makes that true.
/// - **Failure is throwing, not returning.** A drain that could not finish must
///   throw so the state says so; swallowing an error here produces the exact
///   thing this feature exists to prevent, an app reporting that work is backed
///   up when it is not.
abstract class SyncDrain {
  Future<void> drain();
}

/// The drain for a build with no backend.
///
/// Never actually run — [SyncService] answers `SyncStatus.unavailable` before
/// it reaches a drain — but it means the provider has a real value on every
/// flavor rather than throwing when something reads it.
class UnconfiguredSyncDrain implements SyncDrain {
  const UnconfiguredSyncDrain();

  @override
  Future<void> drain() async {}
}

/// The drain in use.
///
/// [UnconfiguredSyncDrain] on a flavor with no backend, where reading
/// `supabaseClientProvider` would throw because `Supabase.initialize` was never
/// called. `SyncService` answers `SyncStatus.unavailable` before it ever
/// reaches a drain there, so this is belt and braces — but it is the kind that
/// keeps a provider readable on every flavor rather than only on the ones that
/// happen to be wired.
final syncDrainProvider = Provider<SyncDrain>((ref) {
  if (!ref.watch(supabaseConfigProvider).isConfigured) {
    return const UnconfiguredSyncDrain();
  }
  return TwoWaySyncDrain(
    local: LocalSyncStore(database: ref.watch(appDatabaseProvider)),
    remote: ref.watch(remoteSyncStoreProvider),
  );
});
