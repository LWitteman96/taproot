import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/features/garden/controllers/garden_controller.dart';
import 'package:taproot/features/garden/domain/garden_state.dart';

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
