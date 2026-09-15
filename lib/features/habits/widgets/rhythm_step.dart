import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/theme/app_spacing.dart';
import 'package:taproot/core/engine/constants.dart';
import 'package:taproot/features/habits/controllers/habit_creation_controller.dart';
import 'package:taproot/features/habits/widgets/creation_step.dart';
import 'package:taproot/features/habits/widgets/draft_text_field.dart';

/// Step three: how often, and who that makes you.
///
/// The two belong on one screen. growth-engine §5 is explicit that the weekly
/// target is "an **identity-based** commitment ('I'm someone who runs 3× a
/// week'), not an app-imposed daily quota" — so the number and the sentence it
/// implies are asked together, not in separate places.
class RhythmStep extends ConsumerWidget {
  const RhythmStep({super.key});

  static const String question = 'How often?';
  static const String identityLabel = 'I am someone who…';
  static const String identityHint = 'runs';
  static const String reassurance =
      'This can change. If it turns out to be the wrong number, the app will '
      'say so and offer to move it rather than let the plant die.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(habitCreationControllerProvider.notifier);
    final draft = ref.watch(habitCreationControllerProvider);
    final theme = Theme.of(context);

    return CreationStep(
      question: question,
      note: 'Times a week. Say what you intend, not what you hope.',
      children: [
        Wrap(
          spacing: AppSpacing.small,
          runSpacing: AppSpacing.small,
          children: [
            for (
              var frequency = EngineConstants.minimumTargetFrequency;
              frequency <= EngineConstants.maximumTargetFrequency;
              frequency++
            )
              ChoiceChip(
                label: Text('$frequency'),
                selected: draft.targetFrequency == frequency,
                onSelected: (_) => controller.targetFrequencyChosen(frequency),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.medium),
        Text(
          timesAWeek(draft.targetFrequency),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.small),
        Text(
          reassurance,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.extraLarge),
        DraftTextField(
          label: identityLabel,
          hint: identityHint,
          initialValue: draft.identityStatement,
          onChanged: controller.identityStatementChanged,
        ),
        const SizedBox(height: AppSpacing.small),
        Text(
          'Optional, and worth a moment. The habit is the evidence for it.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// The chosen target, read back as a sentence rather than a number.
  static String timesAWeek(int frequency) =>
      frequency == 1 ? 'Once a week.' : '$frequency times a week.';
}
