/// Which plants have art, and what the app calls the pieces of it.
///
/// Each `.riv` is generated outside the Flutter toolchain (`fern/`, `oak/`, and
/// the shared `plantgen/`), so every name here is a contract with a project
/// `flutter analyze` cannot see. They are asserted against the shipped assets in
/// `test/features/garden/plant_art_asset_test.dart`, which is the only thing
/// that would catch a rename: a missing artboard throws, but a renamed view
/// model property fails *silently* — the plant sits at its authored pose
/// forever.
library;

import 'package:meta/meta.dart';

import 'package:taproot/core/engine/domain.dart';

/// The numbers the garden writes, on every species. Both 0–1, both the engine's
/// own ranges, no conversion either way.
///
/// Shared rather than per-species because `plantgen` fixes them: every plant it
/// generates exposes exactly these two. A species that needed a third number
/// would be a change to the generator first, and to this file second.
const String plantVitalityProperty = 'vitality';
const String plantRootsProperty = 'roots';

/// One species' art, and the names its artboards go by.
///
/// The names are **derived from [name] rather than listed**, because that is
/// the rule `plantgen` itself follows when it emits them: artboards are
/// `{Name}{Stage}` and `{Name}Roots`, and the state machine and view model are
/// both `{Name}`. Listing them again here would be a second copy of the rule,
/// free to drift from the generator's; deriving them cannot.
@immutable
class PlantArt {
  const PlantArt({
    required this.plantType,
    required this.name,
    required this.assetPath,
  });

  /// The id stored on `Habit.plantType`, from `plantChoices`.
  final String plantType;

  /// The generator's species name, PascalCase — `Species(name: ...)` in
  /// `plantgen`. Every artboard name below is built from it.
  final String name;

  final String assetPath;

  /// Every artboard carries a state machine under this name. Without it the
  /// artboard receives no data at all — Rive applies binds only while a state
  /// machine runs — so this is load-bearing, not a label.
  String get stateMachineName => name;

  /// The root system. Not a stage — 1024 x 520 with its ground line at its
  /// **top** edge, so it stacks directly under a stage artboard with the two
  /// lines meeting.
  ///
  /// It is a separate artboard rather than part of each stage because roots are
  /// the same art at every stage, and because `roots` drives it *and* a lean on
  /// the plant above it — hence the one-shared-instance rule in [PlantArtView].
  ///
  /// Every species' roots canvas is the same size, which is what lets
  /// `GardenLayout.rootsDepth` stay one constant instead of becoming
  /// per-species. The asset test pins that across species rather than trusting
  /// it.
  String get rootsArtboard => '${name}Roots';

  /// The artboard that draws [stage].
  String artboardFor(Stage stage) => '$name${_stageSuffix(stage)}';

  @override
  String toString() => 'PlantArt($plantType)';
}

/// Exhaustive on purpose: a stage added to the engine becomes a compile error
/// here rather than a plant that silently fails to render. That is worth a
/// switch even though the names are otherwise derived — string-building the
/// suffix too would turn a new stage into a missing artboard at runtime.
String _stageSuffix(Stage stage) => switch (stage) {
  Stage.seed => 'Seed',
  Stage.sprout => 'Sprout',
  Stage.seedling => 'Seedling',
  Stage.young => 'Young',
  Stage.mature => 'Mature',
  Stage.bloom => 'Bloom',
};

const PlantArt fernArt = PlantArt(
  plantType: 'fern',
  name: 'Fern',
  assetPath: 'assets/rive/fern.riv',
);

const PlantArt oakArt = PlantArt(
  plantType: 'oak',
  name: 'Oak',
  assetPath: 'assets/rive/oak.riv',
);

/// Every species with art, in no particular order.
///
/// Four of the six in `plantChoices` are still missing, and adding one is this
/// list plus the asset — nothing else in the app changes.
const List<PlantArt> plantArts = <PlantArt>[fernArt, oakArt];

/// The art for [plantType], or null if that species has none.
///
/// Null is the common case and not an error: `Habit.plantType` is a free-form
/// string, so it can also name a plant no longer offered at all.
PlantArt? plantArtFor(String? plantType) {
  if (plantType == null) return null;
  for (final art in plantArts) {
    if (art.plantType == plantType) return art;
  }
  return null;
}

/// Whether [plantType] has art to draw. Everything else keeps the word-based
/// card, which is not a placeholder — it is the semantics layer the art needs
/// anyway, and mixing drawn and described plants is honest about what exists.
bool hasPlantArt(String plantType) => plantArtFor(plantType) != null;
