import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import 'package:taproot/app/database/app_database.dart';

/// The open local database.
///
/// Opening is asynchronous and happens once during startup, so this provider
/// holds the already-open handle and must be overridden before it is read —
/// with the real database in `main()`, and with an in-memory one in tests.
final appDatabaseProvider = Provider<Database>(
  (ref) => throw StateError(
    'appDatabaseProvider must be overridden with an open database. '
    'Call openLocalDatabase() during startup, or override it with an '
    'in-memory database in tests.',
  ),
);

/// Opens the on-device database. Call once, during startup.
Future<Database> openLocalDatabase() async {
  final directory = await getApplicationDocumentsDirectory();
  return openAppDatabase(
    databaseFactory: sqflite.databaseFactory,
    path: p.join(directory.path, 'taproot.db'),
  );
}
