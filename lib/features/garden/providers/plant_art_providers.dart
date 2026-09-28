import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rive/rive.dart' as rive;

import 'package:taproot/features/garden/domain/plant_art.dart';
import 'package:taproot/features/garden/providers/garden_selectors.dart';

/// The decoded Rive file for one species, keyed by `Habit.plantType`.
///
/// **One file per species, not one per plant.** Every fern on screen shares a
/// decoded `fern.riv` and every oak a decoded `oak.riv`; each card then builds
/// its own controller and its own view model instance from it, so two plants of
/// the same species do not share a vitality. Keying the family by species
/// rather than by habit is what keeps that true — a family per habit would
/// decode the same megabyte once per card.
///
/// A species with no art returns null without touching the filesystem, which is
/// the four species in `plantChoices` that `plantArts` does not cover.
///
/// **Null is a supported outcome, not an error to surface.** `rive_native`
/// needs a platform library that `pub get` does not fetch (`dart run
/// rive_native:setup`), and a device that cannot load it should still get a
/// usable garden — the word-based card is a complete description of the plant,
/// so falling back to it costs the user nothing but the picture. That also
/// keeps every existing widget test working without a native dependency: they
/// override this with `null` and never construct a Rive widget.
final plantArtFileProvider = FutureProvider.family<rive.File?, String>((
  ref,
  plantType,
) async {
  final art = plantArtFor(plantType);
  if (art == null) return null;
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
      art.assetPath,
      riveFactory: rive.Factory.flutter,
    );
    if (file == null) {
      dev.log('${art.assetPath} did not decode', name: 'PlantArt');
    }
    ref.onDispose(() => file?.dispose());
    return file;
  } catch (error, stackTrace) {
    // Deliberately not rethrown. A plant that cannot be drawn is a degraded
    // garden, not a broken one, and the card behind it still says everything.
    dev.log(
      'could not load ${art.assetPath}',
      name: 'PlantArt',
      error: error,
      stackTrace: stackTrace,
    );
    return null;
  }
});

/// Roots pinned at their pre-answer depth while a check-in is being answered.
///
/// The art reads `roots` from the engine's selector, which recomputes the
/// moment a reflection is written — and the reflection is written on *answer*,
/// not on done. Left alone, the roots would therefore grow while the user was
/// still mid-question, and the done state would have nothing to show.
///
/// check-in-design §7.2 is explicit that the payoff lands "when done appears
/// (never earlier)", so the sheet pins the old value here on open and releases
/// it on done. Releasing is what triggers the 1.2s Rive interpolator.
final heldRootDepthProvider =
    NotifierProvider<
      HeldRootDepthController,
      ({String habitId, double depth})?
    >(HeldRootDepthController.new);

class HeldRootDepthController
    extends Notifier<({String habitId, double depth})?> {
  @override
  ({String habitId, double depth})? build() => null;

  void hold({required String habitId, required double depth}) =>
      state = (habitId: habitId, depth: depth);

  void release() => state = null;
}

/// The root depth the art should draw for [habitId]: the held one while a
/// check-in is mid-flight, the engine's otherwise.
final drawnRootDepthProvider = Provider.family<double, String>((ref, habitId) {
  final held = ref.watch(heldRootDepthProvider);
  if (held != null && held.habitId == habitId) return held.depth;
  return ref.watch(habitRootDepthProvider(habitId)) ?? 0;
});
