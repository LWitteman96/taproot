import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/theme/app_radius.dart';
import 'package:taproot/app/theme/app_spacing.dart';
import 'package:taproot/features/garden/controllers/garden_controller.dart';
import 'package:taproot/features/garden/domain/garden_ticker.dart';
import 'package:taproot/features/garden/domain/plant_descriptions.dart';
import 'package:taproot/features/garden/providers/garden_selectors.dart';
import 'package:taproot/features/garden/widgets/watering_control.dart';

/// One plant in the garden.
///
/// It watches [plantStateProvider] for its own habit and nothing wider, so a
/// watering repaints the plant that was watered and leaves the rest of the
/// garden alone.
///
/// There is no plant art yet — it is with an external illustrator — so what
/// stands in for it is the state in words. That is not purely a placeholder:
/// the words are the semantics layer the illustration will still need, so they
/// are worth getting right before there is anything to look at.
class PlantCard extends ConsumerWidget {
  const PlantCard({required this.habitId, required this.onWatered, super.key});

  final String habitId;

  /// Called after the watering is recorded, with the completion id when there
  /// is one to undo. The page owns the undo offer, because it owns the
  /// scaffold that shows it.
  final void Function(String? completionId) onWatered;

  static const String undoLabel = 'Undo';
  static const String pausedLabel = 'Paused';
  static const String shallowRootedLabel = 'Growing faster than its roots';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plant = ref.watch(plantStateProvider(habitId));
    // A habit removed on another device can leave a card mounted for a frame.
    if (plant == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final growth = plant.growth;
    final ticker = gardenTickerOf(context, ref);
    final controller = ref.read(gardenControllerProvider.notifier);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.medium),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.large),
      ),
      // The plant is described once, in prose, and the button carries an
      // action. Both halves matter: putting the description on the button too
      // made a screen reader read the whole state twice, and leaving it on the
      // text alone loses it the moment the plant becomes a picture. This
      // wrapper is where the illustration's label will go.
      child: Semantics(
        container: true,
        // Without this the card absorbs its buttons into one node, and once a
        // watering has happened that node has two tap actions on it — the
        // water and the undo — of which a screen reader can only reach one.
        explicitChildNodes: true,
        label: plantSemanticLabel(
          habitName: plant.habit.name,
          stage: growth.stage,
          vitality: growth.vitality,
          rootDepth: growth.roots.depth,
          isShallowRooted: growth.isShallowRooted,
          isPaused: plant.habit.isPaused,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.medium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plant.habit.name, style: theme.textTheme.titleMedium),
                    if (plant.habit.identityStatement
                        case final statement?) ...[
                      const SizedBox(height: AppSpacing.extraSmall),
                      Text(
                        statement,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.small),
                    Text(
                      plant.habit.isPaused
                          ? '${stageLabel(growth.stage)} · $pausedLabel'
                          : '${stageLabel(growth.stage)} · '
                                '${vitalityLabel(growth.vitality)} · '
                                '${rootDepthLabel(growth.roots.depth)}',
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (growth.isShallowRooted) ...[
                      const SizedBox(height: AppSpacing.extraSmall),
                      Text(
                        shallowRootedLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.tertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.medium),
              Row(
                children: [
                  Expanded(
                    child: WateringControl(
                      ticker: ticker,
                      wateredToday: plant.canUndo,
                      // An action, not a description — the description is on
                      // the card above.
                      semanticLabel: waterActionLabel(
                        plant.habit.name,
                        again: plant.canUndo,
                      ),
                      // The notifier is read before the await and the
                      // callback is guarded after it: a card can be disposed
                      // while its write is in flight — scrolled out of the
                      // `ListView.builder`, or dropped from `order` by a
                      // change from another device — and both `ref.read` on a
                      // disposed ref and the page's `ScaffoldMessenger` on a
                      // defunct element throw.
                      onWatered: () async {
                        final completion = await controller.water(habitId);
                        if (!context.mounted) return;
                        onWatered(completion?.id);
                      },
                    ),
                  ),
                  // The standing correction, for the rest of the day the
                  // watering happened on. The transient offer after a tap is
                  // the page's; this is the one still here an hour later.
                  if (plant.undoableCompletion case final completion?) ...[
                    const SizedBox(width: AppSpacing.small),
                    TextButton(
                      onPressed: () => controller.undo(habitId, completion.id),
                      child: Text(
                        undoLabel,
                        semanticsLabel: 'Undo watering ${plant.habit.name}',
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
