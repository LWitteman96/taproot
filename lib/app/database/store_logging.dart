import 'package:logging/logging.dart';

import 'package:taproot/app/database/store_exceptions.dart';

/// Runs a store operation, logging and rethrowing anything unexpected.
///
/// The typed data-consistency exceptions pass straight through unlogged: they
/// are expected states the caller handles, and reporting them would spend the
/// error budget on non-errors. Everything else is a real fault — it is logged
/// with its stack and **rethrown**, never swallowed.
Future<T> guardStore<T>(
  Logger log,
  String action,
  Future<T> Function() body,
) async {
  try {
    return await body();
  } on UnknownHabitException {
    rethrow;
  } on UnknownNudgeException {
    rethrow;
  } on UnknownCompletionException {
    rethrow;
  } on CompletionNotRetractableException {
    rethrow;
  } on DuplicateOccasionException {
    rethrow;
  } catch (error, stackTrace) {
    log.severe('$action failed', error, stackTrace);
    rethrow;
  }
}
