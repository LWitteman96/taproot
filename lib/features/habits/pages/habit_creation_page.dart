import 'package:flutter/material.dart';

import 'package:taproot/app/theme/app_dimensions.dart';
import 'package:taproot/app/theme/app_spacing.dart';

/// Habit creation — a placeholder shell.
///
/// It exists because the router's fail-safe gate has to have somewhere real to
/// send a user (guide §7), and a redirect target that 404s is not fail-safe.
/// The flow itself — the two journeys, the plant-type identity moment, the
/// cue/routine/reward design — is a later branch.
class HabitCreationPage extends StatelessWidget {
  const HabitCreationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Plant something')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppDimensions.maximumContentWidth,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pageHorizontal,
              ),
              child: Text(
                'Designing a habit goes here.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
