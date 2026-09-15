import 'package:flutter/material.dart';

import 'package:taproot/app/theme/app_spacing.dart';

/// The chrome every creation step shares: a question, an optional line under
/// it, and the controls.
///
/// The question is a heading rather than a form label because the app's voice
/// is a conversation — design-spec §6 asks for "journal, not spreadsheet", and
/// a screen that opens with `Name *` is the spreadsheet.
class CreationStep extends StatelessWidget {
  const CreationStep({
    required this.question,
    required this.children,
    this.note,
    super.key,
  });

  final String question;

  /// The quieter line under the question. Explains, never instructs.
  final String? note;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question,
          style: theme.textTheme.headlineSmall,
          // The question is the screen's heading for a screen reader too, so
          // moving between steps announces where you have arrived.
          semanticsLabel: question,
        ),
        if (note != null) ...[
          const SizedBox(height: AppSpacing.small),
          Text(
            note!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.large),
        ...children,
      ],
    );
  }
}
