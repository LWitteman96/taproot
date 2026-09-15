import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/theme/app_spacing.dart';
import 'package:taproot/features/habits/controllers/habit_creation_controller.dart';
import 'package:taproot/features/habits/widgets/creation_step.dart';
import 'package:taproot/features/habits/widgets/draft_text_field.dart';

/// Step five: the routine and the reward.
///
/// Both are required on this path, and that is the product rather than a strict
/// form. design-spec §2 defines Journey B as writing down the intended cue,
/// routine *and* reward up front; a design flow that lets two thirds of the
/// loop go blank is the "tracker with a designer bolted on" §2 argues against.
/// The way out is the opt-out on the previous step, not a half-filled loop.
class LoopStep extends ConsumerWidget {
  const LoopStep({super.key});

  static const String question = 'Then what happens?';
  static const String routineLabel = 'The routine';
  static const String routineHint = 'a 20 minute loop round the park';
  static const String rewardLabel = 'The reward';
  static const String rewardHint = 'coffee on the porch, sitting down';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(habitCreationControllerProvider.notifier);
    final draft = ref.watch(habitCreationControllerProvider);
    final theme = Theme.of(context);

    return CreationStep(
      question: question,
      note: 'The thing you do, and the thing that follows it.',
      children: [
        DraftTextField(
          label: routineLabel,
          hint: routineHint,
          initialValue: draft.routine,
          maxLines: 2,
          onChanged: controller.routineChanged,
        ),
        const SizedBox(height: AppSpacing.large),
        DraftTextField(
          label: rewardLabel,
          hint: rewardHint,
          initialValue: draft.reward,
          maxLines: 2,
          onChanged: controller.rewardChanged,
        ),
        const SizedBox(height: AppSpacing.small),
        Text(
          'Something you actually give yourself, not something you have earned '
          'in the abstract. This is the half most people leave out.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
