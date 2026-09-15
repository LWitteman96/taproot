import 'dart:async';

import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logging/logging.dart';

import 'package:taproot/app/database/app_database.dart';
import 'package:taproot/app/database/database_provider.dart';
import 'package:taproot/features/notifications/domain/notification_gateway.dart';
import 'package:taproot/features/notifications/domain/nudge_payload.dart';
import 'package:taproot/features/notifications/services/local_nudge_service.dart';
import 'package:taproot/features/notifications/services/nudge_response_recorder.dart';

/// Answers given from the notification shade while the app is not running.
///
/// **This is the common case, not the edge case.** The check-in arrives at
/// 20:00; the odds that Taproot is in the foreground at that moment are low.
/// Both actions are declared `showsUserInterface: false` precisely so that
/// answering costs nothing — which means the platform hands the answer to a
/// *background isolate*, and an app that registers no background callback
/// silently drops it. The ledger would simply never record a confirm, with no
/// error anywhere.
///
/// A background isolate has no `ProviderContainer` and no widget tree, so this
/// path deliberately shares nothing with the app's wiring except the code that
/// opens the store and the repository that writes the row.
///
/// **On two isolates writing one database.** SQLite serialises the writes, so
/// the row is safe. What is *not* shared is memory: the main isolate's
/// `GardenController` holds each habit's history in state and will not see this
/// write until it next reads. Nothing is stale in a way that matters today —
/// `confirmed` feeds the insight surfaces, which read the store rather than the
/// garden's state — but anything that starts caching nudge rows in the main
/// isolate has to re-read on resume rather than trust what it is holding. It is
/// the same misread family as the ledger's future-dated rows, documented on
/// `NudgeRepository`.
Future<void> recordBackgroundNudgeResponse(
  NotificationResponse raw, {
  Future<Database> Function() openDatabase = openLocalDatabase,
}) async {
  final log = Logger('backgroundNudgeResponse');

  final answer = NudgeResponse.from(raw.payload, raw.actionId);
  if (answer == null) {
    log.warning('unrecognised background response: ${raw.payload}');
    return;
  }
  // Opening a database to record that a notification was tapped, and then
  // doing nothing with it, would be the most expensive no-op in the app.
  if (answer.action == NudgeResponseAction.opened) return;

  Database? database;
  try {
    database = await openDatabase();
    await NudgeResponseRecorder(
      nudges: LocalNudgeService(database: database),
    ).record(answer);
  } catch (error, stackTrace) {
    // Nothing above this catch has a screen to show, and the isolate is about
    // to end either way. A lost answer costs the ledger one confirm flag; a
    // thrown error out of a background isolate costs the same and is noisier.
    log.severe('the background answer was not recorded', error, stackTrace);
  } finally {
    await database?.close();
  }
}

/// The isolate entry point handed to `flutter_local_notifications`.
///
/// `@pragma('vm:entry-point')` is load-bearing: without it the Dart compiler
/// strips a function nothing in the app appears to call, and the plugin's
/// callback lookup fails at runtime in release builds only.
@pragma('vm:entry-point')
void backgroundNudgeResponseHandler(NotificationResponse response) {
  // The isolate starts with no plugins registered, so `path_provider` and
  // `sqflite` — everything `openLocalDatabase` needs — are absent until this
  // runs.
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  unawaited(recordBackgroundNudgeResponse(response));
}
