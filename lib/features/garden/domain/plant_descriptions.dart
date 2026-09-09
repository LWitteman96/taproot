/// Words for things the garden otherwise only says in pictures.
///
/// Stage, vitality and root depth are rendered as a plant's height, its droop
/// and what is under the soil — which is the whole design, and which is also
/// completely unavailable to a screen reader. CLAUDE.md treats these labels as
/// part of the feature rather than a retrofit, so they are written here, as
/// pure functions, and tested like the engine is.
///
/// They are also the reason the garden can be asserted on in a widget test at
/// all: a test can read "drooping" where a human reads a tilted stem.
library;

import 'package:taproot/core/engine/domain.dart';

/// The plant's height, in words.
String stageLabel(Stage stage) => switch (stage) {
  Stage.seed => 'Seed',
  Stage.sprout => 'Sprout',
  Stage.seedling => 'Seedling',
  Stage.young => 'Young',
  Stage.mature => 'Mature',
  Stage.bloom => 'In bloom',
};

/// How the plant is holding itself up.
///
/// Vitality is continuous and the bands are for language only — the rendering
/// stays continuous. The wording carries no blame in any band: a wilting plant
/// is a plant that needs water, never a user who failed.
String vitalityLabel(double vitality) => switch (vitality) {
  >= 0.95 => 'thriving',
  >= 0.6 => 'healthy',
  >= 0.25 => 'drooping',
  > 0 => 'wilting',
  _ => 'fully wilted',
};

/// How deep the roots have gone.
///
/// Roots are reflection, so the vocabulary is about understanding rather than
/// effort — the point of the below-ground half is that it cannot be earned by
/// repetition alone.
String rootDepthLabel(double depth) => switch (depth) {
  >= 0.75 => 'deep roots',
  >= 0.5 => 'established roots',
  >= 0.3 => 'taking root',
  > 0 => 'shallow roots',
  _ => 'no roots yet',
};

/// The whole plant in one sentence, for the semantics layer.
///
/// [isShallowRooted] is called out explicitly rather than left to be inferred
/// from the two labels, because it is the state the visual design gives its own
/// treatment — tall and shallow-rooted reads as precarious, and a screen reader
/// user should hear that rather than assemble it.
String plantSemanticLabel({
  required String habitName,
  required Stage stage,
  required double vitality,
  required double rootDepth,
  required bool isShallowRooted,
  required bool isPaused,
}) {
  final parts = <String>[
    habitName,
    stageLabel(stage).toLowerCase(),
    if (isPaused) 'paused' else vitalityLabel(vitality),
    rootDepthLabel(rootDepth),
    if (isShallowRooted) 'growing faster than its roots',
  ];
  return parts.join(', ');
}

/// What the watering control announces.
///
/// An action, deliberately: the plant's state belongs to the card that holds
/// it, and putting it here too makes a screen reader read the whole thing
/// twice before offering the one thing there is to do.
String waterActionLabel(String habitName, {required bool again}) =>
    again ? 'Water $habitName again' : 'Water $habitName';
