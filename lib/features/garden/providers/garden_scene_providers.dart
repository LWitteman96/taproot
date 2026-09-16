/// Screen-local state for the garden scene.
///
/// Separate from `garden_selectors.dart`, which is narrow views onto the
/// controller. Nothing here is persisted or derived from the engine: it is what
/// the *screen* is doing, and it is thrown away when the screen is.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/runtime/runtime_providers.dart';
import 'package:taproot/features/garden/controllers/garden_controller.dart';
import 'package:taproot/features/garden/domain/time_of_day_mode.dart';

/// Which plant the detail card is showing.
///
/// There is always a selected habit once there is one to select — the handoff
/// is explicit that tapping the soil does not deselect, because an empty card
/// would be a worse state than a stale one. Null only means "nothing planted",
/// or the first frame before the garden has loaded.
final selectedHabitIdProvider =
    NotifierProvider<SelectedHabitController, String?>(
      SelectedHabitController.new,
    );

class SelectedHabitController extends Notifier<String?> {
  @override
  String? build() {
    // Follow the garden rather than holding an id that no longer exists: a
    // habit can be deleted on another device while its card is on screen.
    final order = ref.watch(
      gardenControllerProvider.select((state) => state.order),
    );
    final current = _chosen;
    if (current != null && order.contains(current)) return current;
    return order.isEmpty ? null : order.first;
  }

  /// What the user last picked. Held separately because `state` is not readable
  /// during [build], and [build] re-runs whenever the garden's order changes.
  String? _chosen;

  void select(String habitId) {
    _chosen = habitId;
    state = habitId;
  }
}

/// How many plants are not thriving.
///
/// "Thirsty" is the complement of `vitalityLabel`'s top band rather than a new
/// threshold, so the header's count and the card's words can never disagree
/// about the same plant.
final thirstyCountProvider = Provider<int>(
  (ref) => ref.watch(
    gardenControllerProvider.select(
      (state) => state.plants.values
          .where((plant) => plant.growth.vitality < thirstyBelowVitality)
          .length,
    ),
  ),
);

const double thirstyBelowVitality = 0.95;

/// What time it looks like in the garden.
///
/// Reads the injected clock, so a test can set the scene's time of day the same
/// way it sets everything else. garden-design §7 asks for a re-check once a
/// minute while ambient motion is on; that belongs with the cross-fade in build
/// step 6, and until then this is evaluated when the screen builds.
final timeOfDayModeProvider = Provider<TimeOfDayMode>(
  (ref) => TimeOfDayMode.forHour(ref.watch(clockProvider)().hour),
);
