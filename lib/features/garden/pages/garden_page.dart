import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/theme/app_dimensions.dart';
import 'package:taproot/app/theme/app_motion.dart';
import 'package:taproot/app/theme/app_spacing.dart';
import 'package:taproot/core/utils/flavor.dart';
import 'package:taproot/features/garden/controllers/garden_controller.dart';
import 'package:taproot/features/garden/providers/garden_selectors.dart';
import 'package:taproot/features/garden/widgets/plant_card.dart';
import 'package:taproot/features/habits/services/demo_habit_seed.dart';

/// The home screen.
///
/// design-spec §6: the emotional job here is *"look how far you've come,"* not
/// *"here's what you still owe."* So it leads with the garden's accumulated
/// state and there is no "0 of 3 done" header — there will not be one.
///
/// The garden itself is still words rather than plants; the art is with an
/// external illustrator and the rendering is a later branch. What is real is
/// the loop: hold to water, the plant changes in the same frame, and the
/// watering can be taken back.
class GardenPage extends ConsumerWidget {
  const GardenPage({super.key});

  static const String title = 'Taproot';
  static const String emptyHeadline = 'Nothing planted yet';
  static const String emptyBody =
      'A garden starts with one habit. Designing one is the next thing this '
      'app will learn to do.';
  static const String seedLabel = 'Plant a habit (dev)';
  static const String wateredMessage = 'Watered';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Failures reach the user here rather than at the gesture. The controller
    // turns every one of them into a sentence, so this only has to show it and
    // then forget it — a message that outlives its snack bar comes back on the
    // next rebuild.
    ref.listen<String?>(gardenErrorProvider, (previous, next) {
      if (next == null) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(next)));
      ref.read(gardenControllerProvider.notifier).clearError();
    });

    final isLoading = ref.watch(gardenIsLoadingProvider);
    final habitIds = ref.watch(plantIdsProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppDimensions.maximumContentWidth,
            ),
            child: switch ((isLoading, habitIds.isEmpty)) {
              (true, _) => const Center(child: CircularProgressIndicator()),
              (false, true) => const _EmptyGarden(),
              (false, false) => _PlantList(habitIds: habitIds),
            },
          ),
        ),
      ),
    );
  }
}

class _PlantList extends StatelessWidget {
  const _PlantList({required this.habitIds});

  final List<String> habitIds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pageHorizontal,
        vertical: AppSpacing.pageVertical,
      ),
      // One header plus one card per plant, in one scrollable, so the garden
      // scrolls as a whole rather than under a fixed title.
      itemCount: habitIds.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.large),
            child: Text(GardenPage.title, style: theme.textTheme.headlineLarge),
          );
        }
        final habitId = habitIds[index - 1];
        return _WateringCard(habitId: habitId);
      },
    );
  }
}

/// A card plus the undo offer that follows a watering on it.
class _WateringCard extends ConsumerWidget {
  const _WateringCard({required this.habitId});

  final String habitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PlantCard(
    habitId: habitId,
    onWatered: (completionId) {
      if (completionId == null) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: const Text(GardenPage.wateredMessage),
            duration: AppMotion.undoOfferDuration,
            // Explicit, because the default is not what it looks like:
            // `SnackBar.persist` defaults to `action != null`, so adding the
            // undo action silently turns `duration` off and the bar sits over
            // the garden until something else replaces it. The offer is meant
            // to be brief — the standing correction is the button on the card.
            persist: false,
            action: SnackBarAction(
              label: PlantCard.undoLabel,
              onPressed: () => ref
                  .read(gardenControllerProvider.notifier)
                  .undo(habitId, completionId),
            ),
          ),
        );
    },
  );
}

/// What the app looks like before anything is planted.
///
/// The seed button is dev-only scaffolding — see [plantDemoHabit]. On stg and
/// prod this is a plain empty state, which is the honest thing to show while
/// habit creation is still a placeholder.
class _EmptyGarden extends ConsumerWidget {
  const _EmptyGarden();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final flavor = getFlavor();

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pageHorizontal,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(GardenPage.title, style: theme.textTheme.headlineLarge),
          const SizedBox(height: AppSpacing.large),
          Text(
            GardenPage.emptyHeadline,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.small),
          Text(
            GardenPage.emptyBody,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          if (flavor == Flavor.dev) ...[
            const SizedBox(height: AppSpacing.large),
            FilledButton(
              onPressed: () async {
                await ref.read(demoHabitSeedProvider)();
                await ref.read(gardenControllerProvider.notifier).refresh();
              },
              child: const Text(GardenPage.seedLabel),
            ),
          ],
          const SizedBox(height: AppSpacing.extraLarge),
          Text('flavor: ${flavor.name}', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
