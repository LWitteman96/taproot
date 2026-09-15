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
  /// `pending_sync` is stripped: it is the device's queue flag and means
  /// nothing to the server, which would reject the column outright.
  Future<List<Map<String, Object?>>> pendingRows(
    SyncTable table, {
    int limit = 500,
  }) => guardStore(_log, 'pendingRows', () async {
    final rows = await _database.query(
      table.name,
      where: 'pending_sync = 1',
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
        if (!_incomingWins(row, local)) continue;

        await transaction.update(
          table.name,
          toRow(_reconciled(table, incoming: row, local: local)),
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
  /// Two of them, both on `habits`, and both cases where "the incoming row is
  /// newer" is the wrong question:
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
  Map<String, Object?> _reconciled(
    SyncTable table, {
    required Map<String, Object?> incoming,
    required Map<String, Object?> local,
  }) {
    if (table.name != AppSchema.habits) return incoming;

    return <String, Object?>{
      ...incoming,
      if (incoming['category'] == null && local['category'] != null)
        'category': local['category'],
      if (incoming['deleted_at'] == null && local['deleted_at'] != null)
        'deleted_at': local['deleted_at'],
    };
  }

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
