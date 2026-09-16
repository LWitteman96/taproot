import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/theme/app_spacing.dart';
import 'package:taproot/features/reflection/controllers/check_in_controller.dart';
import 'package:taproot/features/reflection/domain/starter_chip.dart';

/// The ways to answer a cue question.
///
/// **Tap, don't type.** design-spec §3 makes this the whole reason reflection
/// is sustainable: the app remembers past answers and offers them back, and
/// typing is the exception. So the chips come first and `Something else` opens
/// a field only when asked for.
class CueAnswers extends ConsumerStatefulWidget {
  const CueAnswers({required this.chips, super.key});

  final List<StarterChip> chips;

  static const String somethingElseLabel = 'Something else';
  static const String cantRememberLabel = "Can't remember";
  static const String typedFieldLabel = 'What was it?';
  static const String submitLabel = 'That was it';

  @override
  ConsumerState<CueAnswers> createState() => _CueAnswersState();
}

class _CueAnswersState extends ConsumerState<CueAnswers> {
  final TextEditingController _typed = TextEditingController();
  bool _isTyping = false;

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(checkInControllerProvider.notifier);
    final isSaving = ref.watch(
      checkInControllerProvider.select((state) => state.isSaving),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.small,
          runSpacing: AppSpacing.small,
          children: [
            for (final chip in widget.chips)
              ActionChip(
                label: Text(chip.label),
                onPressed: isSaving
                    ? null
                    : () => controller.answerWithCue(chip),
              ),
            ActionChip(
              label: const Text(CueAnswers.somethingElseLabel),
              onPressed: isSaving
                  ? null
                  : () => setState(() => _isTyping = true),
            ),
            // A first-class answer, not a gap. A rising can't-remember rate is
            // itself the signal that a habit is running on autopilot without
            // awareness — a tall plant on shallow roots.
            ActionChip(
              label: const Text(CueAnswers.cantRememberLabel),
              onPressed: isSaving ? null : controller.cantRemember,
            ),
          ],
        ),
        if (_isTyping) ...[
          const SizedBox(height: AppSpacing.large),
          TextField(
            controller: _typed,
            autofocus: true,
            textCapitalization: TextCapitalization.none,
            decoration: const InputDecoration(
              labelText: CueAnswers.typedFieldLabel,
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) => controller.answerWithTypedCue(value),
          ),
          const SizedBox(height: AppSpacing.medium),
          FilledButton(
            onPressed: isSaving
                ? null
                : () => controller.answerWithTypedCue(_typed.text),
            child: const Text(CueAnswers.submitLabel),
          ),
        ],
      ],
    );
  }
}
