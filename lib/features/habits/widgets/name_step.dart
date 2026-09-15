import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/theme/app_spacing.dart';
import 'package:taproot/core/models/habit_category.dart';
import 'package:taproot/features/habits/controllers/habit_creation_controller.dart';
import 'package:taproot/features/habits/widgets/creation_step.dart';
import 'package:taproot/features/habits/widgets/draft_text_field.dart';

/// Step one: what the habit is, and what kind of thing it is.
class NameStep extends ConsumerWidget {
  const NameStep({super.key});

  static const String question = 'What are you growing?';
  static const String nameLabel = 'The habit';
  static const String nameHint = 'Morning run';
  static const String categoryQuestion = 'What kind of thing is it?';
  static const String uncategorisedLabel = 'Something else';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(habitCreationControllerProvider.notifier);
    final draft = ref.watch(habitCreationControllerProvider);
    final theme = Theme.of(context);

    return CreationStep(
      question: question,
      note: 'Name it the way you would say it out loud.',
      children: [
        DraftTextField(
          label: nameLabel,
          hint: nameHint,
          initialValue: draft.name,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onChanged: controller.nameChanged,
        ),
        const SizedBox(height: AppSpacing.extraLarge),
        Text(categoryQuestion, style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.small),
        Text(
          // Honest about what it is for, and honest that it is optional. The
          // category only ever feeds the first reflection's starter chips
          // (starter-chip-library.md §0), and there is a global pool behind it.
          'It only helps us ask a better question later. Skip it if none fit.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.medium),
        Wrap(
          spacing: AppSpacing.small,
          runSpacing: AppSpacing.small,
          children: [
            for (final category in HabitCategory.values)
              ChoiceChip(
                label: Text(category.label),
                selected: draft.category == category,
                onSelected: (selected) =>
                    controller.categoryChosen(selected ? category : null),
              ),
            ChoiceChip(
              label: const Text(uncategorisedLabel),
              selected: draft.category == null,
              onSelected: (_) => controller.categoryChosen(null),
            ),
          ],
        ),
      ],
    );
  }
}
