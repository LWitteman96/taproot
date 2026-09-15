import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:taproot/app/router/app_router.dart';
import 'package:taproot/app/theme/app_dimensions.dart';
import 'package:taproot/app/theme/app_spacing.dart';
import 'package:taproot/features/garden/controllers/garden_controller.dart';
import 'package:taproot/features/habits/controllers/habit_creation_controller.dart';
import 'package:taproot/features/habits/widgets/cue_step.dart';
import 'package:taproot/features/habits/widgets/loop_step.dart';
import 'package:taproot/features/habits/widgets/name_step.dart';
import 'package:taproot/features/habits/widgets/plant_step.dart';
import 'package:taproot/features/habits/widgets/review_step.dart';
import 'package:taproot/features/habits/widgets/rhythm_step.dart';

/// Designing a habit.
///
/// The flow *is* the design flow — cue, routine and reward as things the user
/// writes down — with tracking an existing habit offered as an explicit opt-out
/// part-way in rather than as an equal choice at the door (design-spec §2).
/// What it collects and what it refuses lives in [HabitCreationController]; this
/// is the chrome around it.
class HabitCreationPage extends ConsumerWidget {
  const HabitCreationPage({super.key});

  static const String title = 'Plant something';
  static const String nextLabel = 'Next';
  static const String backLabel = 'Back';
  static const String plantLabel = 'Plant it';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<String?>(
      habitCreationControllerProvider.select((draft) => draft.createdHabitId),
      (previous, next) {
        if (next == null) return;
        _leaveForTheGarden(context, ref);
      },
    );

    final draft = ref.watch(habitCreationControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(AppDimensions.dividerThickness),
          child: Semantics(
            label: 'Step ${draft.stepIndex + 1} of ${draft.steps.length}',
            child: LinearProgressIndicator(
              value: (draft.stepIndex + 1) / draft.steps.length,
              minHeight: AppDimensions.dividerThickness,
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppDimensions.maximumContentWidth,
            ),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.pageHorizontal,
                      vertical: AppSpacing.pageVertical,
                    ),
                    child: switch (draft.step) {
                      HabitCreationStep.name => const NameStep(),
                      HabitCreationStep.plant => const PlantStep(),
                      HabitCreationStep.rhythm => const RhythmStep(),
                      HabitCreationStep.cue => const CueStep(),
                      HabitCreationStep.loop => const LoopStep(),
                      HabitCreationStep.review => const ReviewStep(),
                    },
                  ),
                ),
                _StepControls(draft: draft),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Leaves for the garden once the habit is in the store.
  ///
  /// Both invalidations matter. The entry gate decides whether the garden is
  /// reachable at all and has just been answered on stale information, and the
  /// garden holds its own evaluated copy of the habit list — which is why
  /// `GardenController.refresh` is public.
  static Future<void> _leaveForTheGarden(
    BuildContext context,
    WidgetRef ref,
  ) async {
    ref.invalidate(appGateProvider);
    await ref.read(gardenControllerProvider.notifier).refresh();
    if (!context.mounted) return;
    context.go(AppRoutes.garden);
  }
}

/// Back, next, and — on the last step — the one that plants it.
class _StepControls extends ConsumerWidget {
  const _StepControls({required this.draft});

  final HabitCreationState draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(habitCreationControllerProvider.notifier);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageHorizontal,
        AppSpacing.small,
        AppSpacing.pageHorizontal,
        AppSpacing.pageVertical,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (draft.errorMessage != null) ...[
            Text(
              draft.errorMessage!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: AppSpacing.medium),
          ],
          Row(
            children: [
              if (!draft.isFirstStep) ...[
                TextButton(
                  onPressed: draft.isSaving ? null : controller.back,
                  child: const Text(HabitCreationPage.backLabel),
                ),
                const SizedBox(width: AppSpacing.medium),
              ],
              Expanded(
                child: draft.isLastStep
                    ? FilledButton(
                        onPressed: draft.canSubmit ? controller.submit : null,
                        child: draft.isSaving
                            ? const SizedBox.square(
                                dimension: AppDimensions.progressIndicatorSize,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(HabitCreationPage.plantLabel),
                      )
                    : FilledButton(
                        onPressed: draft.canAdvance ? controller.next : null,
                        child: const Text(HabitCreationPage.nextLabel),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
