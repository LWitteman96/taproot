import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/runtime/runtime_providers.dart';
import 'package:taproot/app/theme/app_dimensions.dart';
import 'package:taproot/app/theme/app_spacing.dart';
import 'package:taproot/features/reflection/controllers/check_in_controller.dart';
import 'package:taproot/features/reflection/domain/check_in_question.dart';
import 'package:taproot/features/reflection/services/check_in_assembler.dart';
import 'package:taproot/features/reflection/widgets/cue_answers.dart';
import 'package:taproot/features/reflection/widgets/friction_answers.dart';

/// The evening check-in.
///
/// design-spec §6 asks reflection to have "its own softer, more conversational
/// visual language, distinct from the quick tracking UI — so the app has two
/// moods: the satisfying *tap* of tracking, and the slower, thoughtful
/// *check-in* of reflection". That is what the extra air, the sentence-shaped
/// heading and the absence of a progress bar are doing here. This screen should
/// not feel like the watering control, and it should not feel like a form.
class CheckInPage extends ConsumerStatefulWidget {
  const CheckInPage({this.offered, super.key});

  /// The offer the garden already assembled, handed over through the route.
  ///
  /// Re-verified rather than trusted — see [CheckInController.load] — but it
  /// saves electing a winner among every habit a second time, seconds after
  /// the garden did it, with the user watching the spinner for the repeat.
  final CheckInOffer? offered;

  static const String title = 'Check in';
  static const String nothingHeadline = 'Nothing to ask today';
  static const String nothingBody =
      'Most days there is no check-in. We only ask when the answer would '
      'teach us something.';
  static const String failedHeadline = 'We could not put a question together';
  static const String retryLabel = 'Try again';
  static const String doneHeadline = 'Noted';
  static const String doneBody = 'That goes into the roots.';
  static const String closeLabel = 'Close';
  static const String skipLabel = 'Not now';

  @override
  ConsumerState<CheckInPage> createState() => _CheckInPageState();
}

class _CheckInPageState extends ConsumerState<CheckInPage> {
  @override
  void initState() {
    super.initState();
    // The first load starts here rather than in the controller's `build`,
    // because this is the layer that knows whether an offer came through the
    // route with it.
    Future<void>.microtask(
      () => ref
          .read(checkInControllerProvider.notifier)
          .load(offered: widget.offered),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(checkInControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(CheckInPage.title),
        actions: [
          if (state.status == CheckInStatus.asking)
            TextButton(
              // Skipping is recorded, not discarded. `InputMode.skipped` earns
              // no root credit, but a habit the user keeps declining to talk
              // about is a signal the engine should be able to see.
              onPressed: state.isSaving
                  ? null
                  : () => ref.read(checkInControllerProvider.notifier).skip(),
              child: const Text(CheckInPage.skipLabel),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppDimensions.maximumContentWidth,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pageHorizontal,
                vertical: AppSpacing.pageVertical,
              ),
              child: switch (state.status) {
                CheckInStatus.looking => const Center(
                  child: CircularProgressIndicator(),
                ),
                CheckInStatus.nothingToAsk => const _Quiet(
                  headline: CheckInPage.nothingHeadline,
                  body: CheckInPage.nothingBody,
                ),
                CheckInStatus.answered => const _Quiet(
                  headline: CheckInPage.doneHeadline,
                  body: CheckInPage.doneBody,
                ),
                CheckInStatus.failed => _Failed(
                  message: state.errorMessage ?? CheckInPage.failedHeadline,
                ),
                CheckInStatus.asking => _Question(offer: state.offer!),
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// The question, and the ways to answer it.
class _Question extends ConsumerWidget {
  const _Question({required this.offer});

  final CheckInOffer offer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(checkInControllerProvider);
    final now = ref.watch(clockProvider)();

    final question = checkInQuestion(
      framing: offer.framing,
      habit: offer.habit,
      occasionAt: offer.candidate.occasion.at,
      now: now,
    );
    final preamble = checkInPreamble(offer.framing);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            offer.habit.name,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.small),
          Text(question, style: theme.textTheme.headlineSmall),
          if (preamble != null) ...[
            const SizedBox(height: AppSpacing.small),
            Text(
              preamble,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.extraLarge),
          if (offer.isDiagnosis)
            FrictionAnswers(chips: offer.frictionChips)
          else
            CueAnswers(chips: offer.cueChips),
          if (state.errorMessage != null) ...[
            const SizedBox(height: AppSpacing.large),
            Text(
              state.errorMessage!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// What the screen says when there is nothing to ask, or when the answer has
/// landed. Both are calm on purpose — neither is a failure.
class _Quiet extends StatelessWidget {
  const _Quiet({required this.headline, required this.body});

  final String headline;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            headline,
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.small),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Failed extends ConsumerWidget {
  const _Failed({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.large),
          FilledButton(
            onPressed: () =>
                ref.read(checkInControllerProvider.notifier).load(),
            child: const Text(CheckInPage.retryLabel),
          ),
        ],
      ),
    );
  }
}
