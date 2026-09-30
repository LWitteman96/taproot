import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The one enforcement of "the invitation record must not sync" that lives
/// outside Dart.
///
/// `NotificationInvitationStore` argues at length that the record is
/// device-local, and the storage choice does keep it out of Taproot's own sync.
/// What it does not escape is Android Auto Backup, which carries the app's
/// files to a new phone on both cloud restore and device-to-device transfer.
/// Permission does not travel with them — it is granted per install — so a
/// restored record saying "already asked" lands on an install that has never
/// prompted, and that user is never offered notifications again.
///
/// Nothing else in the suite can see this: it is three XML files, and a
/// `flutter test` run never opens them. So this reads them, and it reads the
/// *whole* chain — a rule file that excludes the right path is worth nothing
/// if the manifest does not point at it, and a manifest attribute is worth
/// nothing if only one of the two API-version rule files carries the exclusion.
void main() {
  const String androidDirectory = 'android/app/src/main';

  /// Where `SharedPreferencesAsync` actually writes on Android.
  ///
  /// **Not `shared_prefs/`.** `shared_preferences_android` backs the async API
  /// with Jetpack DataStore by default (`useDataStore` defaults to true), which
  /// writes `files/datastore/FlutterSharedPreferences.preferences_pb` — a
  /// different Auto Backup domain from the legacy XML file. Excluding
  /// `shared_prefs` instead would look exactly as correct and protect nothing.
  const String excludedPath = 'datastore/';

  String read(String path) {
    final file = File('$androidDirectory/$path');
    expect(
      file.existsSync(),
      isTrue,
      reason: '$path is what keeps the invitation record off a restored phone',
    );
    return file.readAsStringSync();
  }

  test('the manifest points at both rule files', () {
    // Two attributes, because the platform picks by version: API 31+ reads
    // dataExtractionRules and everything below it reads fullBackupContent.
    // Declaring one alone leaves the other half of the installed base backing
    // the record up.
    final manifest = read('AndroidManifest.xml');

    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
  });

  test('API 30 and below exclude the preference store', () {
    final rules = read('res/xml/backup_rules.xml');

    expect(rules, contains('<full-backup-content>'));
    expect(rules, contains('<exclude domain="file" path="$excludedPath" />'));
  });

  test('API 31 and above exclude it from backup *and* transfer', () {
    // Device-to-device transfer is the likelier route of the two — it is the
    // ordinary "I got a new phone" path — and it is its own section, so an
    // exclusion written only under <cloud-backup> would miss it entirely.
    final rules = read('res/xml/data_extraction_rules.xml');
    final cloud = _section(rules, 'cloud-backup');
    final transfer = _section(rules, 'device-transfer');

    expect(cloud, contains('<exclude domain="file" path="$excludedPath" />'));
    expect(
      transfer,
      contains('<exclude domain="file" path="$excludedPath" />'),
    );
  });

  test('the garden is deliberately still backed up', () {
    // This is a rule rather than android:allowBackup="false" on purpose: the
    // local SQLite store is the primary copy of everything the user has
    // planted, and it *should* come back on a new phone. A blanket opt-out
    // would fix the record and lose the garden.
    final manifest = read('AndroidManifest.xml');
    final rules = read('res/xml/data_extraction_rules.xml');

    expect(manifest, isNot(contains('android:allowBackup="false"')));
    expect(rules, isNot(contains('path="databases/')));
  });
}

/// The text inside one `<name>…</name>` element.
String _section(String xml, String name) {
  final match = RegExp('<$name>(.*?)</$name>', dotAll: true).firstMatch(xml);
  expect(match, isNotNull, reason: '<$name> is missing from the rules');
  return match!.group(1)!;
}
