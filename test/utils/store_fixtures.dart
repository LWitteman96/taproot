import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:taproot/app/database/app_database.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/habit.dart';

/// A clock the tests move by hand.
///
/// Every write stamps `updated_at`, and pausing a habit records the instant it
/// started, so the services take their time from an injected clock rather than
/// calling [DateTime.now] where a test cannot see it.
class TestClock {
  TestClock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration by) => now = now.add(by);
}

/// Opens a fresh in-memory database carrying the real schema.
///
/// `sqflite_common_ffi` runs the actual SQLite engine in-process, so foreign
/// keys, conflict clauses and indexes behave exactly as they will on device.
Future<Database> openTestDatabase() {
  sqfliteFfiInit();
  return openAppDatabase(
    databaseFactory: databaseFactoryFfi,
    path: inMemoryDatabasePath,
  );
}

/// The same database, opened without sqflite's background isolate.
///
/// Widget tests run inside `flutter_test`'s fake-async zone, which pumps
/// microtasks and fake timers but never delivers a message from another
/// isolate. With the isolate-backed factory the open simply never completes:
/// the app stays on its loading screen and `pumpAndSettle` spins until it times
/// out, several minutes later, looking like a hang rather than a wrong factory.
/// Same SQLite, same schema, one isolate.
Future<Database> openTestDatabaseInWidgetTest() {
  sqfliteFfiInit();
  return openAppDatabase(
    databaseFactory: databaseFactoryFfiNoIsolate,
    path: inMemoryDatabasePath,
  );
}

/// A habit with every field filled, unless overridden.
Habit testHabit({
  String id = 'habit-1',
  String name = 'Morning run',
  String plantType = 'oak',
  int targetFrequency = 3,
  DateTime? createdAt,
  String? identityStatement = 'I am someone who runs',
  String? designedCue = 'after breakfast',
  CueType? designedCueType = CueType.event,
  String? routine = 'a 20 minute loop',
  String? reward = 'coffee on the porch',
  DateTime? pausedAt,
  DateTime? graduatedAt,
}) => Habit(
  id: id,
  name: name,
  plantType: plantType,
  targetFrequency: targetFrequency,
  createdAt: createdAt ?? DateTime(2026, 1, 5, 9),
  identityStatement: identityStatement,
  designedCue: designedCue,
  designedCueType: designedCueType,
  routine: routine,
  reward: reward,
  pausedAt: pausedAt,
  graduatedAt: graduatedAt,
);
