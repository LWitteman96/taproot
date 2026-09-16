import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/theme/app_spacing.dart';
import 'package:taproot/features/reflection/controllers/check_in_controller.dart';
import 'package:taproot/features/reflection/domain/starter_chip.dart';

/// The ways to answer a Diagnosis.
///
/// Five chips plus `Something else` (§6.3), and deliberately **no
/// `Can't remember`**: it is a first-class answer about a *cue*, where honest
/// non-recall is real evidence of autopilot. Asked why something did not
/// happen, "can't remember" is not the same kind of answer, and offering it
/// would collect noise rather than the forgot/reluctance split the whole
/// framing exists for.
class FrictionAnswers extends ConsumerStatefulWidget {
  const FrictionAnswers({required this.chips, super.key});

  final List<FrictionChip> chips;

  static const String somethingElseLabel = 'Something else';
  static const String typedFieldLabel = 'What got in the way?';
  static const String submitLabel = 'That was it';

  @override
  ConsumerState<FrictionAnswers> createState() => _FrictionAnswersState();
}

class _FrictionAnswersState extends ConsumerState<FrictionAnswers> {
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
                    : () => controller.answerWithFriction(chip),
              ),
            ActionChip(
              label: const Text(FrictionAnswers.somethingElseLabel),
              onPressed: isSaving
                  ? null
                  : () => setState(() => _isTyping = true),
            ),
          ],
        ),
        if (_isTyping) ...[
          const SizedBox(height: AppSpacing.large),
          TextField(
            controller: _typed,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: FrictionAnswers.typedFieldLabel,
              border: OutlineInputBorder(),
            ),
            onSubmitted: controller.answerWithTypedFriction,
          ),
          const SizedBox(height: AppSpacing.medium),
          FilledButton(
            onPressed: isSaving
                ? null
                : () => controller.answerWithTypedFriction(_typed.text),
            child: const Text(FrictionAnswers.submitLabel),
          ),
        ],
      ],
    );
  }
}
