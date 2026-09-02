import 'package:sqflite/sqflite.dart';

import 'package:taproot/app/database/store_exceptions.dart';

export 'package:sqflite/sqflite.dart'
    show
        ConflictAlgorithm,
        Database,
        DatabaseException,
        DatabaseExecutor,
        Transaction;

/// The local SQLite database — the app's **primary** store, not a cache.
///
/// A completion tap must never fail, never spin and never be lost, so every
/// read is local and every write is local-then-queued. Supabase is durable
/// backup and cross-device sync, and the `pending_sync` column on every table
/// is the queue it drains.
///
/// Two shapes here are load-bearing and should not be "tidied":
///
/// - `completions` is keyed by `(habit_id, id)` with the UUID generated
///   client-side before insert, which makes multi-device sync a union rather
///   than a merge and removes essentially all conflict handling.
/// - `nudges` holds a row for every expected occasion **including the ones the
///   engine deliberately stayed silent on**. Those rows are autonomy's
///   denominator; they cannot be inferred from the absence of a notification.
/// - An undo is a row in `completion_retractions`, not a DELETE and not a flag
///   on the completion. Both ledgers stay insert-only, so merging two devices
///   is still a union — and a device replaying a completion it has not heard
///   was undone cannot resurrect it.
///
/// No table stores a derived engine value. Stage, vitality, roots and autonomy
/// are computed from these rows at read time, so tuning an engine constant is
/// never a data migration.
abstract final class AppSchema {
  /// Bump on every schema change, and add the matching step to [_upgrade].
  static const int version = 1;

  static const String habits = 'habits';
  static const String completions = 'completions';
  static const String reflections = 'reflections';
  static const String nudges = 'nudges';
  static const String habitPauses = 'habit_pauses';
  static const String completionRetractions = 'completion_retractions';
}

/// Opens the database at [path], creating or upgrading the schema.
///
/// Both parameters are explicit rather than defaulted so that tests can hand in
/// `databaseFactoryFfi` and `inMemoryDatabasePath` and exercise the real SQLite
/// engine in-process. Production wiring supplies the platform factory and a
/// path under the app's documents directory.
Future<Database> openAppDatabase({
  required DatabaseFactory databaseFactory,
  required String path,
}) => databaseFactory.openDatabase(
  path,
  options: OpenDatabaseOptions(
    version: AppSchema.version,
    onConfigure: _configure,
    onCreate: _create,
    onUpgrade: _upgrade,
  ),
);

/// Converts a model's JSON into a row SQLite will accept.
///
/// `toJson` emits real booleans because that is what Supabase wants on the
/// wire; SQLite has no boolean type. This is the one place that difference is
/// resolved — the readers in `json_codec.dart` accept either on the way back.
Map<String, Object?> toRow(Map<String, Object?> json) => <String, Object?>{
  for (final entry in json.entries)
    entry.key: entry.value is bool
        ? ((entry.value! as bool) ? 1 : 0)
        : entry.value,
};

/// Adds [column] to [table] only if it is not already there.
///
/// `ALTER TABLE ... ADD COLUMN` has no `IF NOT EXISTS`, and an upgrade step can
/// be re-entered after a partial failure, so every column add goes through
/// here. Same rule as the SQL migrations: idempotent and re-runnable.
Future<void> ensureColumn(
  Database database,
  String table,
  String column,
  String definition,
) async {
  final existing = await database.rawQuery('PRAGMA table_info($table)');
  final present = existing.any((row) => row['name'] == column);
  if (present) return;
  await database.execute('ALTER TABLE $table ADD COLUMN $column $definition');
}

Future<void> _configure(Database database) =>
    // Off by default in SQLite. Without it a completion could be written for a
    // habit that no longer exists and simply disappear from every query.
    database.execute('PRAGMA foreign_keys = ON');

Future<void> _create(Database database, int version) async {
  final batch = database.batch();

  batch.execute('''
    CREATE TABLE ${AppSchema.habits} (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      identity_statement TEXT,
      plant_type TEXT NOT NULL,
      target_frequency INTEGER NOT NULL,
      designed_cue TEXT,
      designed_cue_type TEXT,
      routine TEXT,
      reward TEXT,
      created_at TEXT NOT NULL,
      paused_at TEXT,
      graduated_at TEXT,
      updated_at TEXT NOT NULL,
      deleted_at TEXT,
      pending_sync INTEGER NOT NULL DEFAULT 0
    )
  ''');

  // Append-only events: no updated_at, no deleted_at, and a composite primary
  // key so replaying the same client UUID for the same habit is a union.
  batch.execute('''
    CREATE TABLE ${AppSchema.completions} (
      habit_id TEXT NOT NULL,
      id TEXT NOT NULL,
      completed_at TEXT NOT NULL,
      was_nudged INTEGER NOT NULL DEFAULT 0,
      source TEXT NOT NULL,
      pending_sync INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (habit_id, id),
      FOREIGN KEY (habit_id) REFERENCES ${AppSchema.habits} (id) ON DELETE CASCADE
    )
  ''');

  // The undo ledger. Deliberately **no** foreign key to completions: on a
  // multi-device sync the retraction can arrive before the completion it
  // retracts, and it has to be storable when it does.
  batch.execute('''
    CREATE TABLE ${AppSchema.completionRetractions} (
      habit_id TEXT NOT NULL,
      completion_id TEXT NOT NULL,
      retracted_at TEXT NOT NULL,
      pending_sync INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (habit_id, completion_id),
      FOREIGN KEY (habit_id) REFERENCES ${AppSchema.habits} (id) ON DELETE CASCADE
    )
  ''');

  batch.execute('''
    CREATE TABLE ${AppSchema.reflections} (
      id TEXT PRIMARY KEY,
      habit_id TEXT NOT NULL,
      created_at TEXT NOT NULL,
      occasion TEXT NOT NULL,
      framing TEXT NOT NULL,
      input_mode TEXT NOT NULL,
      cue_reported TEXT,
      cue_type TEXT NOT NULL,
      matched_designed_cue INTEGER,
      friction_reported TEXT,
      friction_type TEXT,
      was_nudged INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL,
      pending_sync INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (habit_id) REFERENCES ${AppSchema.habits} (id) ON DELETE CASCADE
    )
  ''');

  batch.execute('''
    CREATE TABLE ${AppSchema.nudges} (
      id TEXT PRIMARY KEY,
      habit_id TEXT NOT NULL,
      expected_occasion_at TEXT NOT NULL,
      scheduled_for TEXT,
      sent INTEGER NOT NULL DEFAULT 0,
      confirmed INTEGER NOT NULL DEFAULT 0,
      declined INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL,
      pending_sync INTEGER NOT NULL DEFAULT 0,
      UNIQUE (habit_id, expected_occasion_at),
      FOREIGN KEY (habit_id) REFERENCES ${AppSchema.habits} (id) ON DELETE CASCADE
    )
  ''');

  batch.execute('''
    CREATE TABLE ${AppSchema.habitPauses} (
      id TEXT PRIMARY KEY,
      habit_id TEXT NOT NULL,
      started_at TEXT NOT NULL,
      ended_at TEXT,
      updated_at TEXT NOT NULL,
      pending_sync INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (habit_id) REFERENCES ${AppSchema.habits} (id) ON DELETE CASCADE
    )
  ''');

  // Every engine window scans one habit's events in time order.
  batch.execute(
    'CREATE INDEX IF NOT EXISTS idx_completions_habit_completed_at '
    'ON ${AppSchema.completions} (habit_id, completed_at)',
  );
  batch.execute(
    'CREATE INDEX IF NOT EXISTS idx_reflections_habit_created_at '
    'ON ${AppSchema.reflections} (habit_id, created_at)',
  );
  batch.execute(
    'CREATE INDEX IF NOT EXISTS idx_nudges_habit_occasion_at '
    'ON ${AppSchema.nudges} (habit_id, expected_occasion_at)',
  );
  batch.execute(
    'CREATE INDEX IF NOT EXISTS idx_habit_pauses_habit_started_at '
    'ON ${AppSchema.habitPauses} (habit_id, started_at)',
  );

  await batch.commit(noResult: true);
}

Future<void> _upgrade(Database database, int from, int to) async {
  // Steps are cumulative and each must be idempotent, so an upgrade that dies
  // half-way can simply be re-run. Use [ensureColumn] for column adds and
  // `CREATE INDEX IF NOT EXISTS` for indexes.
  //
  // if (from < 2) { await ensureColumn(database, AppSchema.habits, ...); }
}

/// Throws [UnknownHabitException] unless [habitId] names a live habit.
///
/// Every child write goes through this rather than relying on the foreign key,
/// so the caller gets a typed, non-reportable exception instead of a generic
/// [DatabaseException] — and so a *soft-deleted* habit is rejected too, which
/// the foreign key cannot see.
Future<void> requireExistingHabit(
  DatabaseExecutor executor,
  String habitId,
) async {
  final rows = await executor.query(
    AppSchema.habits,
    columns: <String>['id'],
    where: 'id = ? AND deleted_at IS NULL',
    whereArgs: <Object?>[habitId],
    limit: 1,
  );
  if (rows.isEmpty) throw UnknownHabitException(habitId);
}
