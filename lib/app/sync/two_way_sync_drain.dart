import 'package:logging/logging.dart';

import 'package:taproot/app/sync/local_sync_store.dart';
import 'package:taproot/app/sync/remote_sync_store.dart';
import 'package:taproot/app/sync/sync_drain.dart';
import 'package:taproot/app/sync/sync_tables.dart';
import 'package:taproot/core/utils/json_codec.dart';

/// Pull everything new, then push everything still pending.
///
/// **Pull first, and the order is the whole correctness argument.** The upsert
/// this pushes with is unconditional — PostgREST has no "only if newer" — so
/// the server takes whatever it is last sent. Push first and a device holding a
/// stale edit overwrites a *newer* one made on another device, which is
/// cross-device data loss with nothing anywhere to notice it.
///
/// Pulling first puts the last-write-wins comparison where it is actually
/// implemented: in [LocalSyncStore.applyPulled], against `updated_at`. A local
/// row that loses that comparison is replaced and comes off the queue, so the
/// push that follows cannot send it. A row that wins stays pending and is sent.
/// Either way the server only ever receives rows that have already been judged
/// against what it holds.
///
/// The cost is that a failed pull defers the push to the next drain. That is
/// the cheap direction: the local store is primary, so nothing is lost by being
/// backed up a few minutes later — where a clobbered edit is gone for good.
///
/// Each table is drained whole before the next. That is not parallelism left on
/// the table so much as the foreign keys asserting themselves: every child row
/// points at `habits`, on both sides.
class TwoWaySyncDrain implements SyncDrain {
  TwoWaySyncDrain({
    required LocalSyncStore local,
    required RemoteSyncStore remote,
    DateTime Function() clock = DateTime.now,
  }) : _local = local,
       _remote = remote,
       _clock = clock;

  static final Logger _log = Logger('TwoWaySyncDrain');

  final LocalSyncStore _local;
  final RemoteSyncStore _remote;

  /// Only ever read to stamp a deletion the server refused a push for — see
  /// [LocalSyncStore.pinDeleted]. Injectable so a test can assert on the value
  /// rather than on "some time around now".
  final DateTime Function() _clock;

  /// A bound on the pages one drain will walk per table.
  ///
  /// Not an expected limit — 20 pages is 10,000 rows, well past any real
  /// backlog. It is there because both loops below are "keep going until there
  /// is nothing left", and a bug that stops them making progress would
  /// otherwise spin forever inside a single drain rather than ending, logging,
  /// and letting the next connectivity edge try again.
  static const int _maximumPages = 20;

  @override
  Future<DrainOutcome> drain() async {
    final userId = _remote.currentUserId;
    if (userId == null) {
      // Signed out. Not a failure: the app runs on the local store, and there
      // is nowhere to sync to. The queue keeps until there is.
      //
      // Reported rather than returned silently, because the caller stamps
      // "last backed up" on a clean return and this one backed nothing up.
      _log.info('nobody is signed in; nothing to drain');
      return DrainOutcome.signedOut;
    }

    for (final table in syncTables) {
      await _pull(table);
    }
    for (final table in syncTables) {
      await _push(table, userId);
    }
    return DrainOutcome.drained;
  }

  /// Sends everything queued for one table.
  Future<void> _push(SyncTable table, String userId) async {
    for (var page = 0; page < _maximumPages; page++) {
      final rows = await _local.pendingRows(table, limit: syncPageSize);
      if (rows.isEmpty) return;

      // `user_id` is the one column the device does not carry and the server
      // cannot do without: RLS is `user_id = auth.uid()` on every table, so a
      // row without it is rejected rather than misfiled.
      final stamped = <Map<String, Object?>>[
        for (final row in rows) <String, Object?>{...row, 'user_id': userId},
      ];

      try {
        await _remote.push(table, stamped);
      } on SyncWriteRejected {
        // One row in the batch was refused, and an upsert is all-or-nothing, so
        // the whole page failed for it. Retry them individually to find it
        // rather than giving up on the rest — the others are perfectly good
        // writes that happened to travel with it.
        await _pushOneByOne(table, stamped);
      }

      // Losers included. A row that lost last-write-wins has nothing to gain
      // from being sent again, and leaving it queued would retry it on every
      // drain forever. The winning version arrives on the next pull: the row
      // that beat it was written after this device last pulled — that is what
      // made it a loser — so its `synced_at` is ahead of the cursor.
      //
      // That argument holds for a [StaleRowRejected] and **only** for one. A
      // [SoftDeletePinned] loser was beaten by a row that is behind the cursor,
      // so no pull will bring it; [_pushOneByOne] applies that deletion locally
      // before this runs, which is what stops the row coming off the queue
      // still alive and never being reconciled again.
      await _local.clearPending(table, rows);

      if (rows.length < syncPageSize) return;
    }

    _log.warning(
      'stopped pushing ${table.name} after $_maximumPages pages; the next '
      'drain will continue',
    );
  }

  /// Sends [rows] one at a time, so that one loser does not cost the rest.
  ///
  /// Only reached after a batch came back `PT409`, which the ordering makes
  /// rare: a row that had already lost would have been replaced by the pull and
  /// taken off the queue before the push ran. Getting here means the row was
  /// overtaken in the window between this drain's pull and its push.
  ///
  /// **The two refusals are handled differently, and that is the point of
  /// telling them apart.** A stale row needs nothing done: the version that
  /// beat it is ahead of the cursor and the next pull applies it. A row the
  /// server refused because it is soft-deleted needs the deletion applied here
  /// and now — the deletion that refused it is *behind* the cursor, already
  /// read and rejected by this drain's own pull, so waiting for a pull waits
  /// forever and the habit stays alive on this device with nothing left to
  /// correct it.
  Future<void> _pushOneByOne(
    SyncTable table,
    List<Map<String, Object?>> rows,
  ) async {
    var lost = 0;
    var deleted = 0;
    for (final row in rows) {
      try {
        await _remote.push(table, <Map<String, Object?>>[row]);
      } on SoftDeletePinned {
        await _local.pinDeleted(table, row, _clock().toUtc());
        deleted++;
      } on StaleRowRejected {
        lost++;
      }
    }

    if (lost > 0) {
      _log.info(
        '$lost ${table.name} row(s) were overtaken and not sent; the pull '
        'brings the version that won',
      );
    }
    if (deleted > 0) {
      _log.info(
        '$deleted ${table.name} row(s) are deleted upstream; the deletion has '
        'been applied here rather than waiting for a pull that cannot bring it',
      );
    }
  }

  /// Reads everything new for one table.
  Future<void> _pull(SyncTable table) async {
    final cursor = await _local.cursorFor(table);

    // From the beginning on a first sync; otherwise back by the overlap window,
    // which is what closes the commit-time gap. See [syncOverlapWindow].
    var since = cursor?.subtract(syncOverlapWindow) ?? DateTime.utc(1970);
    var newest = cursor;

    // Rows already applied this cycle. The window overlaps and `gte` re-reads
    // the cursor instant, so the same row legitimately arrives more than once;
    // this keeps the writes down and, more importantly, is how the loop knows
    // whether a page contained anything it had not already seen.
    final seen = <String>{};

    for (var page = 0; page < _maximumPages; page++) {
      final rows = await _remote.pullPage(
        table,
        since: since,
        limit: syncPageSize,
      );
      if (rows.isEmpty) break;

      final fresh = rows.where((row) => seen.add(table.keyOf(row))).toList();
      if (fresh.isNotEmpty) await _local.applyPulled(table, fresh);

      for (final row in rows) {
        final syncedAt = readDateTime(row, 'synced_at');
        if (syncedAt == null) continue;
        if (newest == null || syncedAt.isAfter(newest)) newest = syncedAt;
      }

      // A short page is the end of the table.
      if (rows.length < syncPageSize) break;

      final last = readDateTime(rows.last, 'synced_at');
      if (last == null) break;

      // Normally the next page starts at the last row's instant, so its
      // siblings are not skipped. The exception is a full page in which
      // everything was already seen: that can only repeat, so step past the
      // instant to guarantee progress. It would take more than a page of rows
      // sharing one `clock_timestamp()` to reach — which is why it is logged
      // rather than handled quietly.
      if (fresh.isEmpty) {
        _log.warning(
          'a full page of ${table.name} at $last was entirely already seen; '
          'stepping past it',
        );
        since = last.add(const Duration(microseconds: 1));
      } else {
        since = last;
      }

      if (page == _maximumPages - 1) {
        // The same warning `_push` carries, for the same reason. Ending the
        // loop here is safe — rows come back ascending on `synced_at`, so
        // everything unpulled is ahead of `newest` and the next drain resumes
        // from there — but a first install restoring a year of history across
        // more than 10,000 rows would otherwise finish partially and say
        // nothing, with the garden showing an incomplete history and no
        // indication why. The trigger is a connectivity edge rather than a
        // timer, so "the next drain" on a phone that stays on one network may
        // be days away.
        _log.warning(
          'stopped pulling ${table.name} after $_maximumPages pages; the next '
          'drain will continue from $newest',
        );
      }
    }

    // Moved only at the end, and only forward. A cursor advanced per page would
    // record ground the drain had not finished covering if a later page threw.
    if (newest != null) await _local.setCursor(table, newest);
  }
}
