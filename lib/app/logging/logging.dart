import 'dart:async';
import 'dart:developer' as dev;

import 'package:logging/logging.dart';

import 'package:taproot/core/utils/flavor.dart';

/// Attaches `package:logging` to a sink. Call once, from [runMainApp].
///
/// The services already hold `Logger` instances — `LocalHabitService`,
/// `LocalCompletionService` and the rest each log through `guardStore`. Until
/// this is called, `Logger.root` has no listener and every one of those records
/// is discarded, which is why a store failure currently leaves no trace at all.
///
/// [sink] exists so tests can read what was logged; production uses
/// [logRecordToDeveloper], which routes into `dart:developer` and therefore
/// into the IDE's log view and `flutter logs`.
///
/// Calling this again replaces the previous subscription rather than adding a
/// second one, so a hot restart — or a test that sets up twice — does not
/// double every line.
void setupLogging({
  Flavor? flavor,
  void Function(LogRecord) sink = logRecordToDeveloper,
}) {
  final resolved = flavor ?? getFlavor();

  // Release builds keep the noise down; dev and stg want everything, because a
  // dropped store write is far easier to diagnose from a FINE line that already
  // exists than from one added after the fact.
  Logger.root.level = switch (resolved) {
    Flavor.prod => Level.WARNING,
    Flavor.stg || Flavor.dev => Level.ALL,
  };

  stopLogging();
  _subscription = Logger.root.onRecord.listen(sink);
}

/// Detaches the sink. Test-facing — production never stops logging.
void stopLogging() {
  unawaited(_subscription?.cancel());
  _subscription = null;
}

/// The production sink.
void logRecordToDeveloper(LogRecord record) => dev.log(
  record.message,
  time: record.time,
  level: record.level.value,
  name: record.loggerName,
  error: record.error,
  stackTrace: record.stackTrace,
);

StreamSubscription<LogRecord>? _subscription;
