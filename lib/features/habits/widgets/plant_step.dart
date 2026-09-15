import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/theme/app_radius.dart';
import 'package:taproot/app/theme/app_spacing.dart';
import 'package:taproot/features/habits/controllers/habit_creation_controller.dart';
import 'package:taproot/features/habits/domain/plant_choices.dart';
import 'package:taproot/features/habits/widgets/creation_step.dart';

/// Step two: which plant this habit grows as.
///
/// design-spec §4 calls this "a quiet identity moment" — "I'm growing an oak"
/// carries more meaning than "habit #3" — so each option is offered with a line
/// of character rather than as a bare label. The art itself is a placeholder
/// slot until the external illustrator delivers.
class PlantStep extends ConsumerWidget {
  const PlantStep({super.key});

  static const String question = 'Which plant is it?';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(habitCreationControllerProvider.notifier);
    final chosen = ref.watch(
      habitCreationControllerProvider.select((draft) => draft.plantType),
    );

    return CreationStep(
      question: question,
      note: 'Pick the one that sounds like the habit you want this to become.',
      children: [
        for (final plant in plantChoices) ...[
          _PlantOption(
            plant: plant,
            isChosen: chosen == plant.id,
            onChosen: () => controller.plantChosen(plant.id),
          ),
          const SizedBox(height: AppSpacing.small),
        ],
      ],
    );
  }
}

class _PlantOption extends StatelessWidget {
  const _PlantOption({
    required this.plant,
    required this.isChosen,
    required this.onChosen,
  });

  final PlantChoice plant;
  final bool isChosen;
  final VoidCallback onChosen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      selected: isChosen,
      label: '${plant.label}. ${plant.character}',
      child: ExcludeSemantics(
        child: Material(
          color: isChosen
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.medium),
          child: InkWell(
            onTap: onChosen,
            borderRadius: BorderRadius.circular(AppRadius.medium),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.medium),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plant.label, style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.extraSmall),
                  Text(
                    plant.character,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
