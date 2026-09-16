import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rive/rive.dart' as rive;

import 'package:taproot/features/garden/domain/plant_art.dart';

/// The decoded Rive file, loaded once and shared by every plant on screen.
///
/// One file, many artboards: each card builds its own controller and its own
/// view model instance from this, so plants do not share a vitality.
///
/// **Null is a supported outcome, not an error to surface.** `rive_native`
/// needs a platform library that `pub get` does not fetch (`dart run
/// rive_native:setup`), and a device that cannot load it should still get a
/// usable garden — the word-based card is a complete description of the plant,
/// so falling back to it costs the user nothing but the picture. That also
/// keeps every existing widget test working without a native dependency: they
/// override this with `null` and never construct a Rive widget.
final riveFernFileProvider = FutureProvider<rive.File?>((ref) async {
  try {
    if (!await rive.RiveNative.init()) {
      dev.log(
        'rive native unavailable; plants fall back to text',
        name: 'PlantArt',
      );
      return null;
    }
    // Factory.flutter, not Factory.rive. The Rive renderer wants a graphics
    // context and aborts the process in native code without one, which takes
    // `flutter test` down with a SIGABRT rather than a failed expectation.
    final file = await rive.File.asset(
      fernAssetPath,
      riveFactory: rive.Factory.flutter,
    );
    if (file == null) {
      dev.log('$fernAssetPath did not decode', name: 'PlantArt');
    }
    ref.onDispose(() => file?.dispose());
    return file;
  } catch (error, stackTrace) {
    // Deliberately not rethrown. A plant that cannot be drawn is a degraded
    // garden, not a broken one, and the card behind it still says everything.
    dev.log(
      'could not load plant art',
      name: 'PlantArt',
      error: error,
      stackTrace: stackTrace,
    );
    return null;
  }
});
