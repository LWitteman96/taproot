import 'package:flutter/material.dart';

import 'package:taproot/app/theme/app_dimensions.dart';
import 'package:taproot/app/theme/app_spacing.dart';
import 'package:taproot/core/utils/flavor.dart';

/// The home screen — a placeholder shell.
///
/// The garden itself is a later branch, and is blocked on the plant art. What
/// this holds today is the shape design-spec §6 asks for and the flavor readout
/// that makes the native flavor configuration verifiable end to end: the app
/// leads with the garden, not with a task list, so there is no "0 of 3 done"
/// header here and there will not be one.
class GardenPage extends StatelessWidget {
  const GardenPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final flavor = getFlavor();

    return Scaffold(
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Taproot', style: theme.textTheme.headlineLarge),
                  const SizedBox(height: AppSpacing.small),
                  Text(
                    'Your garden goes here.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.extraLarge),
                  Text(
                    'flavor: ${flavor.name}',
                    style: theme.textTheme.bodySmall,
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
