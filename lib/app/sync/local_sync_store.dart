import 'package:logging/logging.dart';

import 'package:taproot/app/database/app_database.dart';
import 'package:taproot/app/database/store_logging.dart';
import 'package:taproot/app/sync/sync_tables.dart';
import 'package:taproot/core/utils/json_codec.dart';

/// The device side of a drain: what is waiting to go up, and what to do with
/// what comes back down.
///
/// Separate from the repositories on purpose. They speak in habits and
/// completions because the app does; this speaks in rows and keys because sync
/// does, and giving sync its own surface is what keeps the two vocabularies
/// from leaking into each other.
class LocalSyncStore {
  LocalSyncStore({required Database database}) : _database = database;

  static final Logger _log = Logger('LocalSyncStore');

  final Database _database;

  /// The device's columns, per table, cached after the first read.
  ///
  /// A pulled row carries two columns the device has never had — `user_id`,
  /// because RLS needs it, and `synced_at`, because the pull ranges over it —
  /// and SQLite rejects an insert naming a column that does not exist. Asking
  /// the schema rather than hard-coding a list means a column added to a table
  /// later starts syncing without anyone remembering to update a constant.
  final Map<String, Set<String>> _deviceColumns = <String, Set<String>>{};

  Future<Set<String>> _columnsOf(String table) async {
    final cached = _deviceColumns[table];
    if (cached != null) return cached;

    final rows = await _database.rawQuery('PRAGMA table_info($table)');
    final columns = rows.map((row) => row['name']! as String).toSet();
    _deviceColumns[table] = columns;
    return columns;
  }

  /// Rows waiting to be pushed, oldest first, at most [limit] of them.
  ///
  /// "Oldest first" is a guarantee, so it is ordered rather than left to
  /// SQLite. Without an `ORDER BY` the engine may return rows in any order and
  /// in practice returns rowid order — insertion order, not edit order — so a
  /// row edited today can precede one queued last week. Nothing depends on it
  /// today, because [clearPending] and the re-query drain the backlog whatever
  /// order it arrives in; it is ordered because the sentence above reads as a
  /// promise a later reader could build on.
  ///
  /// The mutable tables order on `updated_at`, which is the age that means
  /// something. The append-only ledgers have no such column — their rows never
  /// change — so they order on their key, which is at least stable across
  /// reads even though it is not chronological.
  ///
  /// `pending_sync` is stripped: it is the device's queue flag and means
  /// nothing to the server, which would reject the column outright.
  Future<List<Map<String, Object?>>> pendingRows(
    SyncTable table, {
    int limit = 500,
  }) => guardStore(_log, 'pendingRows', () async {
    final keyOrder = table.keyColumns.map((column) => '$column ASC').join(', ');
    final rows = await _database.query(
      table.name,
      where: 'pending_sync = 1',
      orderBy: table.isMutable ? 'updated_at ASC, $keyOrder' : keyOrder,
      limit: limit,
    );
    return rows
        .map(
          (row) => <String, Object?>{
            for (final entry in row.entries)
              if (entry.key != 'pending_sync') entry.key: entry.value,
          },
        )
        .toList();
  });

  /// Takes [rows] off the queue, having pushed them.
  ///
  /// For a mutable table the clear is conditional on `updated_at` still being
  /// what was pushed. That is not belt and braces: the user can edit a row in
  /// the time between it being read for the push and the push returning, which
  /// sets `pending_sync` back to 1. Clearing by key alone would wipe that flag
  /// and the edit would never be sent — a write silently lost to a race that
  /// gets *more* likely the slower the network is.
  ///
  /// The append-only ledgers need no such care. Their rows never change, so a
  /// key is enough.
  Future<void> clearPending(SyncTable table, List<Map<String, Object?>> rows) =>
      guardStore(_log, 'clearPending', () async {
        if (rows.isEmpty) return;

        await _database.transaction((transaction) async {
          for (final row in rows) {
            final where = <String>[
              for (final column in table.keyColumns) '$column = ?',
              if (table.isMutable) 'updated_at = ?',
            ];
            final args = <Object?>[
              for (final column in table.keyColumns) row[column],
              if (table.isMutable) row['updated_at'],
            ];

            await transaction.update(
              table.name,
              <String, Object?>{'pending_sync': 0},
              where: where.join(' AND '),
              whereArgs: args,
            );
          }
        });
      });

  /// Writes rows that came down from the server.
  ///
  /// Everything written here lands with `pending_sync = 0`: it arrived *from*
  /// the server, so pushing it straight back would be an echo that never
  /// settles.
  ///
  /// Returns the number of rows actually written, which is not the number
  /// offered — see the conflict rules below.
  Future<int> applyPulled(
    SyncTable table,
    List<Map<String, Object?>> rows,
  ) => guardStore(_log, 'applyPulled', () async {
    if (rows.isEmpty) return 0;

    final columns = await _columnsOf(table.name);
    var written = 0;

    await _database.transaction((transaction) async {
      for (final incoming in rows) {
        final row = <String, Object?>{
          for (final entry in incoming.entries)
            if (columns.contains(entry.key)) entry.key: entry.value,
          'pending_sync': 0,
        };

        if (!table.isMutable) {
          // A union, and nothing more. The first write of an event wins, so a
          // replay of a completion this device already has is a no-op rather
          // than an overwrite — and a retraction cannot be undone by a stale
          // device replaying the completion it retracts.
          final inserted = await transaction.insert(
            table.name,
            toRow(row),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          if (inserted != 0) written++;
          continue;
        }

        final existing = await transaction.query(
          table.name,
          where: table.keyColumns.map((column) => '$column = ?').join(' AND '),
          whereArgs: table.keyColumns.map((column) => row[column]).toList(),
          limit: 1,
        );

        if (existing.isEmpty) {
          await transaction.insert(
            table.name,
            toRow(row),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          written++;
          continue;
        }

        final local = existing.single;

        // The winner-takes-the-row question and the one-way questions are
        // different questions, and asking only the first is what let a
        // deletion be discarded. A losing row can still carry something the
        // rules say cannot be reversed — see [_pinnedOntoLoser].
        final merged = _incomingWins(row, local)
            ? _reconciled(table, incoming: row, local: local)
            : _pinnedOntoLoser(table, incoming: row, local: local);
        if (merged == null) continue;

        await transaction.update(
          table.name,
          toRow(merged),
          where: table.keyColumns.map((column) => '$column = ?').join(' AND '),
          whereArgs: table.keyColumns.map((column) => row[column]).toList(),
        );
        written++;
      }
    });

    return written;
  });

  /// Last write wins, on the **client's** clock.
  ///
  /// `updated_at` is compared rather than `synced_at` because `synced_at` says
  /// when the server heard about a row, not when the user changed it: a device
  /// that was offline for a week pushes edits that are older than everything
  /// stamped in the meantime, and ordering on the server's clock would let the
  /// sync order rewrite the edit order.
  ///
  /// Ties go to the row already here. Two edits in the same millisecond on two
  /// devices is a coin toss whichever way it is called; what matters is that it
  /// is called the same way every time, so a re-pull does not keep flipping it.
  bool _incomingWins(
    Map<String, Object?> incoming,
    Map<String, Object?> local,
  ) {
    final incomingAt = readDateTime(incoming, 'updated_at');
    final localAt = readDateTime(local, 'updated_at');
    if (incomingAt == null) return false;
    if (localAt == null) return true;
    return incomingAt.isAfter(localAt);
  }

  /// The winning row, with the columns that do not simply take the winner's
  /// value put back.
  ///
  /// Three of them, all cases where "the incoming row is newer" is the wrong
  /// question:
  ///
  /// - **`category` is read leniently.** `readOpenEnum` turns a category this
  ///   build has not heard of into null, because the set widens with the chip
  ///   library. So a null arriving from another device is ambiguous — "the user
  ///   cleared it" and "that device could not decode it" are the same value on
  ///   the wire — and taking it at face value would erase categories every time
  ///   an older build synced. Null is treated as *no opinion*: it never
  ///   overwrites a category that is already here.
  /// - **`deleted_at` is one-way**, the same rule the server pins with a
  ///   trigger. A row that arrives without the stamp cannot lift a deletion
  ///   this device already knows about, whatever its `updated_at` says.
  /// - **The nudge ledger's flags are monotonic.** `sent`, `confirmed` and
  ///   `declined` each record that something happened, and nothing that
  ///   happened can un-happen, so a winning row may set one and may never
  ///   clear one. `LocalNudgeService._outcomeColumns` refuses exactly this
  ///   write on the local path — "rolling `sent` back to 0 after the
  ///   notification fired would move an occasion that *was* nudged into
  ///   autonomy's un-nudged denominator" — and without this the pull
  ///   reintroduced it from the network. `merge_nudge_flags()` is the same rule
  ///   on the server.
  Map<String, Object?> _reconciled(
    SyncTable table, {
    required Map<String, Object?> incoming,
    required Map<String, Object?> local,
  }) => switch (table.name) {
    AppSchema.habits => <String, Object?>{
      ...incoming,
      if (incoming['category'] == null && local['category'] != null)
        'category': local['category'],
      if (incoming['deleted_at'] == null && local['deleted_at'] != null)
        'deleted_at': local['deleted_at'],
    },
    AppSchema.nudges => <String, Object?>{
      ...incoming,
      for (final flag in _monotonicNudgeFlags)
        flag: _eitherIsSet(incoming[flag], local[flag]),
    },
    _ => incoming,
  };

  /// What a **losing** incoming row still gets to change.
  ///
  /// Null when it changes nothing, which is the usual answer and means "leave
  /// the local row alone".
  ///
  /// The two rules above that are not about winning are applied here too, from
  /// the other side. [_reconciled] was a winner-side fixup for rules that are
  /// not about winners, and that asymmetry was a bug rather than a shortcut:
  ///
  /// - **A deletion is exactly the kind of row that loses.** Device B deletes a
  ///   habit at t1; device A is offline and renames it at t2 > t1. A's pull
  ///   reads the deletion, `_incomingWins` says no, and the deletion was
  ///   discarded — leaving a habit alive on A that every other device and the
  ///   server consider deleted, with the pull cursor already advanced past the
  ///   only row that would have corrected it. It never self-heals, and A keeps
  ///   planning occasions and recording completions against it.
  /// - **A flag set on another device is still set**, whichever row is newer.
  ///   Losing the comparison says this version of the row is older; it does not
  ///   say the notification was never queued or the answer never given.
  ///
  /// The local row keeps everything else, `pending_sync` included: an edit
  /// waiting to go up is still waiting, and stamping a deletion onto it does
  /// not make it sent. The next push carries both, which the server accepts —
  /// `pin_soft_delete` passes a `deleted_at` that is not distinct from the one
  /// it holds.
  Map<String, Object?>? _pinnedOntoLoser(
    SyncTable table, {
    required Map<String, Object?> incoming,
    required Map<String, Object?> local,
  }) {
    if (table.name == AppSchema.habits) {
      if (incoming['deleted_at'] == null || local['deleted_at'] != null) {
        return null;
      }
      // The incoming stamp rather than one invented here: it is the server's,
      // and it is the instant the deletion actually happened.
      return <String, Object?>{...local, 'deleted_at': incoming['deleted_at']};
    }

    if (table.name == AppSchema.nudges) {
      final gained = <String, Object?>{
        for (final flag in _monotonicNudgeFlags)
          if (_isSet(incoming[flag]) && !_isSet(local[flag]))
            flag: _eitherIsSet(incoming[flag], local[flag]),
      };
      return gained.isEmpty ? null : <String, Object?>{...local, ...gained};
    }

    return null;
  }

  /// Once true, never false — see [_reconciled].
  static const List<String> _monotonicNudgeFlags = <String>[
    'sent',
    'confirmed',
    'declined',
  ];

  /// SQLite has no boolean: these arrive as 0/1 from the device and can arrive
  /// as a real `bool` from PostgREST, so both spellings are read.
  static bool _isSet(Object? value) => value == 1 || value == true;

  static int _eitherIsSet(Object? a, Object? b) =>
      _isSet(a) || _isSet(b) ? 1 : 0;

  /// Applies a deletion the server refused a push for.
  ///
  /// The recovery for [SoftDeletePinned], and the reason that conflict needed
  /// telling apart from a stale one. The row is dead upstream; the deletion
  /// that killed it is *behind* this device's pull cursor, so no future pull
  /// will offer it and doing nothing leaves the habit alive here forever.
  ///
  /// [deletedAt] is the client's clock rather than the server's, which the
  /// error does not carry. Only null-ness is ever compared — here, in
  /// `pin_soft_delete`, and in the repository's live-habit filter — and the
  /// server keeps its own stamp regardless, since `pin_soft_delete` pins
  /// `old.deleted_at` through any later push. This is the narrow race left
  /// after [_pinnedOntoLoser] handles the common case: a deletion written
  /// *after* this drain's pull and before its push.
  Future<void> pinDeleted(
    SyncTable table,
    Map<String, Object?> row,
    DateTime deletedAt,
  ) => guardStore(_log, 'pinDeleted', () async {
    await _database.update(
      table.name,
      <String, Object?>{'deleted_at': encodeDateTime(deletedAt)},
      where:
          '${table.keyColumns.map((column) => '$column = ?').join(' AND ')} '
          'AND deleted_at IS NULL',
      whereArgs: table.keyColumns.map((column) => row[column]).toList(),
    );
  });

  /// How far the pull for [table] has got, or null if it has never run.
  Future<DateTime?> cursorFor(SyncTable table) =>
      guardStore(_log, 'cursorFor', () async {
        final rows = await _database.query(
          AppSchema.syncCursors,
          where: 'table_name = ?',
          whereArgs: <Object?>[table.name],
          limit: 1,
        );
        if (rows.isEmpty) return null;
        return readDateTime(rows.single, 'synced_through');
      });

  /// Records how far the pull got.
  ///
  /// Only ever moves forward. A page that came back out of order, or a retry
  /// that re-read an earlier window, must not wind the cursor back and re-pull
  /// the world on every cycle.
  Future<void> setCursor(SyncTable table, DateTime syncedThrough) =>
      guardStore(_log, 'setCursor', () async {
        final current = await cursorFor(table);
        if (current != null && !syncedThrough.isAfter(current)) return;

        await _database.insert(AppSchema.syncCursors, <String, Object?>{
          'table_name': table.name,
          'synced_through': encodeDateTime(syncedThrough),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });
}
