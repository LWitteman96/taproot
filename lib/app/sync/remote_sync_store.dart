import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:taproot/app/supabase/supabase_providers.dart';
import 'package:taproot/app/sync/sync_tables.dart';

/// How many rows move in one request.
///
/// PostgREST is configured with `max_rows = 1000` and **truncates silently** —
/// a first-install pull of a year of completions gets exactly one page and no
/// signal that there is more. So the pull pages rather than treating one
/// response as the whole answer, and this stays comfortably under that ceiling
/// so the page size is ours rather than the server's.
const int syncPageSize = 500;

/// How far back of already-seen ground each pull re-reads.
///
/// This closes the gap the schema's header warns about. `synced_at` is stamped
/// when a row is written; the row becomes *visible* when its transaction
/// commits, which is later by however long the rest of that transaction took.
/// A pull that reads at T and stores `cursor = T` can therefore miss a row
/// stamped before T that commits after it — and miss it permanently, because
/// the cursor has already moved past.
///
/// Re-reading a window rather than moving the cursor exactly is the cheaper of
/// the two fixes the schema offers (the other being an `xid8` cursor), and it
/// is safe here for one reason: every upsert on both sides is idempotent, so
/// the only cost of seeing a row twice is having seen it twice.
///
/// Thirty seconds is a transaction length, not a network guess. It wants to be
/// comfortably longer than the slowest write transaction the app produces, and
/// those are single-row upserts.
const Duration syncOverlapWindow = Duration(seconds: 30);

/// The SQLSTATE the server raises when a write has lost.
///
/// `PT`-prefixed codes are how PostgREST is told which HTTP status to answer
/// with, so this arrives as a 409 Conflict. Two triggers raise it, and they
/// mean the same thing to a caller: `reject_stale_update` when an `updated_at`
/// goes backwards, and `pin_soft_delete` when a push tries to clear a
/// `deleted_at`. Both say *this row has moved on without you* — pull, do not
/// retry.
const String staleWriteCode = 'PT409';

/// A row the server refused because it has a newer version.
///
/// Typed rather than left as a `PostgrestException` because it is not an error
/// in the sense the rest of the error handling means: nothing is broken, the
/// write simply lost a race it was always going to lose. It is an expected
/// state with a designed response, which is exactly the kind CLAUDE.md asks be
/// kept out of the error budget.
class StaleRowRejected implements Exception {
  const StaleRowRejected(this.table, this.message);

  final String table;
  final String message;

  @override
  String toString() => 'StaleRowRejected($table: $message)';
}

/// The server, as sync sees it.
///
/// Two operations, because sync performs exactly two: push a batch of rows, and
/// read a page of what has changed. Neither is on the repository interfaces —
/// those speak in habits and completions for the app's benefit, and nothing in
/// the app reads a habit over the network. The local store is primary; this is
/// backup and cross-device merge.
abstract class RemoteSyncStore {
  /// Who the rows belong to, or null if nobody is signed in.
  ///
  /// Null is an ordinary state rather than an error: the app is fully usable
  /// signed out, because SQLite is the primary store. There is simply nowhere
  /// to sync to, and RLS would reject every row anyway.
  String? get currentUserId;

  /// Upserts [rows] on [SyncTable.keyColumns]. Idempotent by construction.
  Future<void> push(SyncTable table, List<Map<String, Object?>> rows);

  /// One page of rows whose `synced_at` is at or after [since], oldest first.
  Future<List<Map<String, Object?>>> pullPage(
    SyncTable table, {
    required DateTime since,
    required int limit,
  });
}

class SupabaseRemoteSyncStore implements RemoteSyncStore {
  SupabaseRemoteSyncStore({required SupabaseClient client}) : _client = client;

  static final Logger _log = Logger('SupabaseRemoteSyncStore');

  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<void> push(SyncTable table, List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return;
    _log.fine('pushing ${rows.length} rows to ${table.name}');

    try {
      // On the primary key, so a row this device has already pushed — or one
      // another device pushed first — is an update rather than a duplicate.
      await _client
          .from(table.name)
          .upsert(rows, onConflict: table.keyColumns.join(','));
    } on PostgrestException catch (error) {
      if (error.code == staleWriteCode) {
        throw StaleRowRejected(table.name, error.message);
      }
      rethrow;
    }
  }

  @override
  Future<List<Map<String, Object?>>> pullPage(
    SyncTable table, {
    required DateTime since,
    required int limit,
  }) async {
    // `gte`, not `gt`. Rows can share a `synced_at`, and the pull walks the
    // cursor forward by the last row it saw; excluding that instant would skip
    // every one of its siblings that did not fit in the page. Seeing them twice
    // instead is free — the caller dedupes, and the upsert is idempotent.
    final rows = await _client
        .from(table.name)
        .select()
        .gte('synced_at', since.toUtc().toIso8601String())
        .order('synced_at', ascending: true)
        .limit(limit);

    return rows.cast<Map<String, Object?>>();
  }
}

final remoteSyncStoreProvider = Provider<RemoteSyncStore>(
  (ref) => SupabaseRemoteSyncStore(client: ref.watch(supabaseClientProvider)),
);
