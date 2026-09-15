import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/theme/app_spacing.dart';
import 'package:taproot/core/models/habit_journey.dart';
import 'package:taproot/features/habits/controllers/habit_creation_controller.dart';
import 'package:taproot/features/habits/domain/cue_suggestions.dart';
import 'package:taproot/features/habits/domain/plant_choices.dart';
import 'package:taproot/features/habits/widgets/creation_step.dart';
import 'package:taproot/features/habits/widgets/rhythm_step.dart';

/// The last step: read it back before planting it.
class ReviewStep extends ConsumerWidget {
  const ReviewStep({super.key});

  static const String question = 'Ready to plant?';
  static const String trackingNote =
      'No cue designed. We will ask what set it off as you go, and lock one in '
      'once it is clear.';
  static const String designInsteadLabel = 'Actually, let me design the loop';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(habitCreationControllerProvider.notifier);
    final draft = ref.watch(habitCreationControllerProvider);
    final theme = Theme.of(context);
    final plant = plantChoiceById(draft.plantType);

    return CreationStep(
      question: question,
      children: [
        _Line(label: 'Habit', value: draft.name.trim()),
        if (draft.category != null)
          _Line(label: 'Kind', value: draft.category!.label),
        if (plant != null) _Line(label: 'Plant', value: plant.label),
        _Line(
          label: 'Rhythm',
          value: RhythmStep.timesAWeek(draft.targetFrequency),
        ),
        if (draft.identityStatement.trim().isNotEmpty)
          _Line(
            label: 'Identity',
            value: 'I am someone who ${draft.identityStatement.trim()}',
          ),
        if (draft.journey.designsTheLoop) ...[
          _Line(
            label: 'Cue',
            value: cueSentence(draft.designedCue.trim(), draft.designedCueType),
          ),
          _Line(label: 'Routine', value: draft.routine.trim()),
          _Line(label: 'Reward', value: draft.reward.trim()),
        ] else ...[
          const SizedBox(height: AppSpacing.medium),
          Text(
            trackingNote,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.small),
          // The opt-out is reversible right up to the moment it is planted.
          TextButton(
            onPressed: () => controller.journeyChosen(HabitJourney.design),
            child: const Text(designInsteadLabel),
          ),
        ],
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.medium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.extraSmall),
          Text(value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}
