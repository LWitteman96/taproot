import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum Flavor { dev, stg, prod }

/// Resolves the flavor the app was launched with.
///
/// **How to set the flavor**
///
/// When running:
///   `flutter run --flavor dev|stg|prod -t lib/main_<flavor>.dart`
/// When building on Android or iOS:
///   flutter build appbundle|apk|ipa --flavor dev|stg|prod
Flavor getFlavor() {
  // On iOS/Android, `appFlavor` is populated from the --flavor option. On web it
  // is unsupported, so a WEB_FLAVOR dart-define is read instead.
  const webFlavor = String.fromEnvironment('WEB_FLAVOR');
  const flavor = kIsWeb ? webFlavor : appFlavor;
  return switch (flavor) {
    'prod' => Flavor.prod,
    'stg' => Flavor.stg,
    'dev' => Flavor.dev,
    null || '' => () {
      if (kDebugMode) {
        final logMessage = kIsWeb
            ? 'WEB_FLAVOR not set — defaulting to Flavor.dev'
            : 'Flavor not set — defaulting to Flavor.dev';
        dev.log(logMessage, name: 'Flavor');
      }
      return Flavor.dev;
    }(),
    _ => throw UnsupportedError('Invalid flavor: $flavor'),
  };
}
