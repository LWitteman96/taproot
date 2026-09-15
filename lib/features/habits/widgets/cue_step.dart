import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/theme/app_spacing.dart';
import 'package:taproot/core/models/habit_journey.dart';
import 'package:taproot/features/habits/controllers/habit_creation_controller.dart';
import 'package:taproot/features/habits/domain/cue_suggestions.dart';
import 'package:taproot/features/habits/widgets/creation_step.dart';
import 'package:taproot/features/habits/widgets/draft_text_field.dart';

/// Step four: the cue — and the only place the opt-out is offered.
///
/// This is the first step that asks for something a tracker would not, so it is
/// where "I already do this" becomes a fair thing to say. It is deliberately
/// *not* offered at the front door: design-spec §2 says an app that presents
/// designing and tracking as equal-weight choices on the first screen "is a
/// tracker with a designer bolted on", and that the opt-out must not be the
/// path of least resistance. Offered here, the user has already seen what
/// designing involves before deciding it is not for this habit.
class CueStep extends ConsumerStatefulWidget {
  const CueStep({super.key});

  static const String question = 'What sets it off?';
  static const String cueLabel = 'The cue';
  static const String cueHint = 'after breakfast';
  static const String examplesLabel = 'Or start from one of these';
  static const String optOutLabel = 'I already do this — just track it';
  static const String optOutNote =
      'We will work out what cues it from how it actually goes, instead of '
      'designing one now.';

  @override
  ConsumerState<CueStep> createState() => _CueStepState();
}

class _CueStepState extends ConsumerState<CueStep> {
  /// Owned here rather than inside the field, because tapping an example writes
  /// into it from outside.
  late final TextEditingController _cue = TextEditingController(
    text: ref.read(habitCreationControllerProvider).designedCue,
  );

  @override
  void dispose() {
    _cue.dispose();
    super.dispose();
  }

  void _useExample(String example) {
    _cue.value = TextEditingValue(
      text: example,
      selection: TextSelection.collapsed(offset: example.length),
    );
    ref.read(habitCreationControllerProvider.notifier).cueChanged(example);
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(habitCreationControllerProvider.notifier);
    final draft = ref.watch(habitCreationControllerProvider);
    final theme = Theme.of(context);
    final chosenType = draft.designedCueType;
    final examples = chosenType == null
        ? const <String>[]
        : cueExamplesFor(chosenType);

    return CreationStep(
      question: CueStep.question,
      note: 'The thing that reliably comes just before it.',
      children: [
        Wrap(
          spacing: AppSpacing.small,
          runSpacing: AppSpacing.small,
          children: [
            for (final type in designableCueTypes)
              ChoiceChip(
                label: Text(cueTypeLabel(type)),
                selected: chosenType == type,
                onSelected: (selected) =>
                    controller.cueTypeChosen(selected ? type : null),
              ),
          ],
        ),
        if (chosenType != null) ...[
          const SizedBox(height: AppSpacing.small),
          Text(
            cueTypeHint(chosenType),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.large),
        DraftTextField(
          label: CueStep.cueLabel,
          hint: CueStep.cueHint,
          controller: _cue,
          initialValue: draft.designedCue,
          onChanged: controller.cueChanged,
        ),
        if (examples.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.medium),
          Text(CueStep.examplesLabel, style: theme.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.small),
          Wrap(
            spacing: AppSpacing.small,
            runSpacing: AppSpacing.small,
            children: [
              for (final example in examples)
                ActionChip(
                  label: Text(example),
                  onPressed: () => _useExample(example),
                ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.huge),
        const Divider(),
        const SizedBox(height: AppSpacing.medium),
        // A text button, not a second primary action: the opt-out is available
        // without competing with the path the app believes in.
        TextButton(
          onPressed: () => controller.journeyChosen(HabitJourney.track),
          child: const Text(CueStep.optOutLabel),
        ),
        Text(
          CueStep.optOutNote,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
