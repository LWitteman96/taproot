import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/runtime/runtime_providers.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/features/garden/controllers/garden_controller.dart';
import 'package:taproot/features/garden/domain/garden_state.dart';
import 'package:taproot/features/reflection/domain/occasion_detection.dart';

/// Narrow views onto [gardenControllerProvider].
///
/// CLAUDE.md asks for these next to any large state object, and the garden is
/// the case it has in mind: watering one plant must not rebuild the garden. It
/// only works because the controller keeps untouched [PlantState] instances and
/// the order list as the *same* objects across a change — `select` compares with
/// `==`, so a rebuilt-but-equal map entry would defeat every provider here.

/// The habits on screen, oldest first.
final plantIdsProvider = Provider<List<String>>(
  (ref) => ref.watch(gardenControllerProvider.select((state) => state.order)),
);

/// One plant. Null once it has been removed, which a card must tolerate: it can
/// be rebuilt one frame after the habit was dropped.
final plantStateProvider = Provider.family<PlantState?, String>(
  (ref, habitId) => ref.watch(
    gardenControllerProvider.select((state) => state.plants[habitId]),
  ),
);

/// Which plant the habit is. Fixed at creation, so this rebuilds nothing after
/// the first frame — which is the point of reading it through a selector rather
/// than off the whole [PlantState].
final habitPlantTypeProvider = Provider.family<String?, String>(
  (ref, habitId) => ref.watch(
    gardenControllerProvider.select(
      (state) => state.plants[habitId]?.habit.plantType,
    ),
  ),
);

final habitStageProvider = Provider.family<Stage?, String>(
  (ref, habitId) => ref.watch(
    gardenControllerProvider.select(
      (state) => state.plants[habitId]?.growth.stage,
    ),
  ),
);

final habitVitalityProvider = Provider.family<double?, String>(
  (ref, habitId) => ref.watch(
    gardenControllerProvider.select(
      (state) => state.plants[habitId]?.growth.vitality,
    ),
  ),
);

final habitRootDepthProvider = Provider.family<double?, String>(
  (ref, habitId) => ref.watch(
    gardenControllerProvider.select(
      (state) => state.plants[habitId]?.growth.roots.depth,
    ),
  ),
);

final gardenIsLoadingProvider = Provider<bool>(
  (ref) =>
      ref.watch(gardenControllerProvider.select((state) => state.isLoading)),
);

final gardenErrorProvider = Provider<String?>(
  (ref) =>
      ref.watch(gardenControllerProvider.select((state) => state.errorMessage)),
);

/// True when the last read of the store failed. The empty garden and the
/// unreadable garden look nothing alike to a user, so the page has to be able
/// to tell them apart.
final gardenLoadFailedProvider = Provider<bool>(
  (ref) =>
      ref.watch(gardenControllerProvider.select((state) => state.loadFailed)),
);

/// Whether this plant has a watering the user has not yet reflected on.
///
/// The card's Reflect button, and deliberately **not** the same question as
/// `checkInOfferProvider`. That provider answers "is there a check-in the app
/// wants to bring up", which reflection-logic §2 gates hard — once a day
/// app-wide, a weekly budget per habit, a 0.5 priority bar — because those
/// gates exist to stop the app from interrupting. None of them describes
/// someone who just watered a plant and wants to say why. So the affordance is
/// offered whenever there is something to reflect **on**, and the gates keep
/// governing only what the app raises on its own.
///
/// Computed off garden state rather than assembled from the store, which is
/// what makes it appear in the same frame as the watering: [occasionFor] is a
/// pure function of ledgers the garden already holds.
///
/// A **miss** is excluded. It is a real occasion and the scheduler will still
/// raise it, with a Diagnosis framing and its own notification — but putting
/// "Reflect" on a plant the user has not touched turns the card into a standing
/// invitation to explain themselves. The button answers "you did this", not
/// "you didn't".
final canReflectOnProvider = Provider.family<bool, String>((ref, habitId) {
  final plant = ref.watch(plantStateProvider(habitId));
  if (plant == null || plant.habit.isPaused) return false;

  final now = ref.watch(clockProvider)();
  final occasion = occasionFor(
    habitId: habitId,
    completions: plant.inputs.completions,
    nudges: plant.inputs.nudgesUpTo(now),
    reflections: plant.inputs.reflections,
    targetFrequency: plant.habit.targetFrequency,
    at: now,
  );

  // Null once the reflection is written: `occasionFor` counts only events newer
  // than the last reflection, so answering is what takes the button away.
  return occasion != null && occasion.occasion != Occasion.miss;
});
