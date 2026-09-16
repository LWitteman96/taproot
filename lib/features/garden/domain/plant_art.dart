/// Which plant art exists, and what the app calls the pieces of it.
///
/// The Rive file is generated outside the Flutter toolchain (`fern/`), so every
/// name here is a contract with a project `flutter analyze` cannot see. They are
/// asserted against the shipped asset in
/// `test/features/garden/fern_asset_test.dart`, which is the only thing that
/// would catch a rename: a missing artboard throws, but a renamed view model
/// property fails *silently* — the plant sits at its authored pose forever.
library;

import 'package:taproot/core/engine/domain.dart';

/// The one plant with art. `Habit.plantType` carries the id the user picked at
/// creation, and five of the six in `plantChoices` have nothing to draw yet.
const String fernPlantType = 'fern';

const String fernAssetPath = 'assets/rive/fern.riv';

/// Every artboard carries a state machine under this name. Without it the
/// artboard receives no data at all — Rive applies binds only while a state
/// machine runs — so this is load-bearing, not a label.
const String fernStateMachineName = 'Fern';

/// The number the garden writes. 0–1, the engine's own range, no conversion.
const String fernVitalityProperty = 'vitality';

/// The artboard that draws [stage].
///
/// Exhaustive on purpose: a stage added to the engine becomes a compile error
/// here rather than a plant that silently fails to render.
String fernArtboardFor(Stage stage) => switch (stage) {
  Stage.seed => 'FernSeed',
  Stage.sprout => 'FernSprout',
  Stage.seedling => 'FernSeedling',
  Stage.young => 'FernYoung',
  Stage.mature => 'FernMature',
  Stage.bloom => 'FernBloom',
};

/// Whether [plantType] has art to draw. Everything else keeps the word-based
/// card, which is not a placeholder — it is the semantics layer the art needs
/// anyway, and mixing drawn and described plants is honest about what exists.
bool hasPlantArt(String plantType) => plantType == fernPlantType;
