import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import 'package:taproot/app/database/app_database.dart';

/// How the database gets opened.
///
/// The one seam tests override to simulate a slow open, a failing open, or an
/// in-memory database. Everything else in the chain below is derived from it,
/// so overriding this one provider is enough to drive startup down any path.
final databaseOpenerProvider = Provider<Future<Database> Function()>(
  (ref) => openLocalDatabase,
);

/// The open handle, or the failure to get one.
///
/// This is the asynchronous half, and it is deliberately where the failure
/// lands: SQLite is the primary store, so "the database would not open" is a
/// state the app has to *show* — see `lib/app/startup/` — rather than a crash
/// on the way to the first frame.
///
/// It is also the provider a retry must invalidate. See [appStartupRetryTargets].
final openedDatabaseProvider = FutureProvider<Database>((ref) async {
  final database = await ref.watch(databaseOpenerProvider)();
  // Closes on dispose *and* on invalidation, so a retry after a partial open
  // does not leak the handle it is replacing.
  ref.onDispose(database.close);
  return database;
});

/// The open database, for the code that runs after startup has succeeded.
///
/// Synchronous by design: the repositories are built from it, and a completion
/// tap must never await a database handle. Reading it before startup finishes
/// throws — which is correct, because the only way to get there is to have put
/// a widget above [AppStartupWidget] that should not be there.
final appDatabaseProvider = Provider<Database>(
  (ref) => ref.watch(openedDatabaseProvider).requireValue,
);

/// Opens the on-device database. Called once, through [databaseOpenerProvider].
Future<Database> openLocalDatabase() async {
  final directory = await getApplicationDocumentsDirectory();
  return openAppDatabase(
    databaseFactory: sqflite.databaseFactory,
    path: p.join(directory.path, 'taproot.db'),
  );
}
