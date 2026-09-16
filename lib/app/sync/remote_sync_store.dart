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
/// with — it reads the three digits after `PT` as the status — so every 409 the
/// schema raises has to spell it exactly this way. Two triggers do, and the
/// shared code is why they need [staleUpdateDetail] and
/// [softDeletePinnedDetail] to tell them apart.
const String staleWriteCode = 'PT409';

/// `reject_stale_update`'s DETAIL: a newer write beat this one.
///
/// The winner is **ahead of the pull cursor** — that is what made this row a
/// loser — so the recovery is to do nothing. The next pull brings it.
const String staleUpdateDetail = 'sync_conflict=stale_update';

/// `pin_soft_delete`'s DETAIL: the row is deleted upstream.
///
/// The winner is **behind the pull cursor**. The deletion was written before
/// this drain's pull, was read by that pull, and lost the `updated_at`
/// comparison on the way in — so waiting for the next pull waits forever, and
/// treating this like a stale row is what resurrects a deleted habit for good.
/// The recovery is to apply the deletion locally. See
/// `TwoWaySyncDrain._pushOneByOne`.
const String softDeletePinnedDetail = 'sync_conflict=soft_delete_pinned';

/// A write the server refused.
///
/// Typed rather than left as a `PostgrestException` because it is not an error
/// in the sense the rest of the error handling means: nothing is broken, the
/// write simply lost a race it was always going to lose. It is an expected
/// state with a designed response, which is exactly the kind CLAUDE.md asks be
/// kept out of the error budget.
///
/// **Sealed, because the two cases have opposite recoveries** and a caller that
/// handles one has to say what it does about the other. They arrive as the same
/// HTTP status and the same SQLSTATE; only the DETAIL separates them.
sealed class SyncWriteRejected implements Exception {
  const SyncWriteRejected(this.table, this.message);

  final String table;
  final String message;
}

/// A row the server refused because it has a newer version.
///
/// Nothing to do: the version that won is ahead of the cursor, so the next pull
/// brings it and the local row is replaced then.
final class StaleRowRejected extends SyncWriteRejected {
  const StaleRowRejected(super.table, super.message);

  @override
  String toString() => 'StaleRowRejected($table: $message)';
}

/// A push the server refused because the row is soft-deleted upstream.
///
/// `deleted_at` is one-way, and a whole-row push carrying a null cannot lift a
/// deletion. Unlike [StaleRowRejected] this **is not** self-correcting: the
/// deletion that refused the write is older than the drain's own pull, so it is
/// already behind the cursor and no future pull will offer it again. The caller
/// has to apply the deletion locally or the row lives on this device forever.
final class SoftDeletePinned extends SyncWriteRejected {
  const SoftDeletePinned(super.table, super.message);

  @override
  String toString() => 'SoftDeletePinned($table: $message)';
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
      // Both forms conflict on the primary key; they differ in what happens
      // when it hits, and the difference is a **permission**, not a taste.
      //
      // A merging upsert is `ON CONFLICT DO UPDATE`, so PostgREST requires the
      // UPDATE privilege — and the append-only ledgers deliberately have no
      // UPDATE grant at all, because an edit to a past event is a different
      // event. Sending `resolution=merge-duplicates` at `completions` is a flat
      // 403 for every completion this device has ever recorded, which is the
      // whole feature. `ignore-duplicates` is `ON CONFLICT DO NOTHING` and
      // needs only INSERT.
      //
      // It is also the right semantics rather than a way around the grant: the
      // first write of an event wins, exactly as `ConflictAlgorithm.ignore`
      // makes it win on the device, which is what keeps a replay a union
      // instead of an overwrite.
      await _client
          .from(table.name)
          .upsert(
            rows,
            onConflict: table.keyColumns.join(','),
            ignoreDuplicates: !table.isMutable,
          );
    } on PostgrestException catch (error) {
      if (error.code == staleWriteCode) {
        // `details` is Postgres's DETAIL field, passed through by PostgREST.
        // An unrecognised one falls back to the stale reading, which is the
        // conservative half: it retries nothing and waits for a pull, where
        // guessing `SoftDeletePinned` would stamp a deletion nobody asked for.
        final detail = error.details;
        if (detail is String && detail.contains(softDeletePinnedDetail)) {
          throw SoftDeletePinned(table.name, error.message);
        }
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
        // A secondary key, so the walk is deterministic. Rows sharing a
        // `synced_at` have no defined order without one, and PostgreSQL is free
        // to return them differently on each request — which would let the
        // caller's `fresh.isEmpty` escape hatch fire on a page that merely
        // came back reshuffled. With this, a page is the same page every time.
        .order('id', ascending: true)
        .limit(limit);

    return rows.cast<Map<String, Object?>>();
  }
}

final remoteSyncStoreProvider = Provider<RemoteSyncStore>(
  (ref) => SupabaseRemoteSyncStore(client: ref.watch(supabaseClientProvider)),
);
