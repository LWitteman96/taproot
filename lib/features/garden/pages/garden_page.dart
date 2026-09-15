import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:taproot/app/router/app_router.dart';
import 'package:taproot/app/theme/app_dimensions.dart';
import 'package:taproot/app/theme/app_motion.dart';
import 'package:taproot/app/theme/app_spacing.dart';
import 'package:taproot/core/utils/flavor.dart';
import 'package:taproot/features/garden/controllers/garden_controller.dart';
import 'package:taproot/features/garden/providers/garden_selectors.dart';
import 'package:taproot/features/garden/widgets/plant_card.dart';

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
      'A garden starts with one habit — the thing you do, what sets it off, '
      'and what you get out of it.';
  static const String plantLabel = 'Plant something';
  static const String addLabel = 'Plant another';
  static const String wateredMessage = 'Watered';
  static const String unreadableHeadline = 'Your garden could not be read';
  static const String unreadableBody =
      'Nothing has been lost. This device could not open its store just now — '
      'trying again usually gets it.';
  static const String retryLabel = 'Try again';

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
      // Deferred to the next microtask, not called here. Clearing inside the
      // listener writes the controller's state during the frame the listener is
      // running in, so `gardenErrorProvider` rebuilds twice in one frame and the
      // debug scheduler throws `StateError: Tried to rebuild ... multiple times
      // in the same frame` — on every error path, in every debug build.
      Future<void>.microtask(() {
        if (!context.mounted) return;
        ref.read(gardenControllerProvider.notifier).clearError();
      });
    });

    final isLoading = ref.watch(gardenIsLoadingProvider);
    final loadFailed = ref.watch(gardenLoadFailedProvider);
    final habitIds = ref.watch(plantIdsProvider);

    return Scaffold(
      // Only once there is a garden to add to. The empty state makes the same
      // offer as its primary action, and a floating button over a spinner or
      // over "we could not read your garden" is an invitation to make the
      // problem worse.
      floatingActionButton: (isLoading || habitIds.isEmpty)
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push(AppRoutes.habitCreation),
              icon: const Icon(Icons.add),
              label: const Text(addLabel),
            ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppDimensions.maximumContentWidth,
            ),
            // A garden that could not be read is not an empty garden, and
            // saying "nothing planted yet" to someone whose store failed is the
            // app telling them their work is gone. A failed *refresh* with
            // plants already on screen keeps the plants — the snack bar is
            // enough there.
            child: switch ((isLoading, loadFailed, habitIds.isEmpty)) {
              (true, _, _) => const Center(child: CircularProgressIndicator()),
              (false, true, true) => const _UnreadableGarden(),
              (false, _, true) => const _EmptyGarden(),
              (false, _, false) => _PlantList(habitIds: habitIds),
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
  Widget build(BuildContext context, WidgetRef ref) {
    // Both resolved in `build`, not in the callback. `onWatered` runs after the
    // write, by which point this element may have been scrolled out of the
    // `ListView.builder` or dropped from `order` — and `ScaffoldMessenger.of`
    // on a defunct element throws, as does `ref.read` on a disposed ref.
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(gardenControllerProvider.notifier);

    return PlantCard(
      habitId: habitId,
      onWatered: (completionId) {
        if (completionId == null) return;
        messenger
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
                onPressed: () => controller.undo(habitId, completionId),
              ),
            ),
          );
      },
    );
  }
}

/// What the app looks like when the store could not be read.
///
/// Deliberately not the empty state: the difference between "you have not
/// planted anything" and "we could not look" is the whole message. The retry is
/// real — `couldNotReadGardenMessage` used to promise a pull-to-refresh that
/// did not exist anywhere in the app.
class _UnreadableGarden extends ConsumerWidget {
  const _UnreadableGarden();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

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
            GardenPage.unreadableHeadline,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.small),
          Text(
            GardenPage.unreadableBody,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.large),
          FilledButton(
            onPressed: () =>
                ref.read(gardenControllerProvider.notifier).refresh(),
            child: const Text(GardenPage.retryLabel),
          ),
        ],
      ),
    );
  }
}

/// What the app looks like before anything is planted.
///
/// Mostly transient, now that the entry gate is real: a user with no habits is
/// redirected into habit creation, so this is what shows in the frame before
/// the gate resolves, and what a user would find if they ever got back here
/// with nothing planted.

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
          const SizedBox(height: AppSpacing.large),
          FilledButton(
            onPressed: () => context.push(AppRoutes.habitCreation),
            child: const Text(GardenPage.plantLabel),
          ),
          const SizedBox(height: AppSpacing.extraLarge),
          Text('flavor: ${flavor.name}', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
