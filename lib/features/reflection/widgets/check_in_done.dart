import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/theme/garden_colors.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/features/garden/domain/garden_ticker.dart';
import 'package:taproot/features/garden/domain/plant_descriptions.dart';
import 'package:taproot/features/garden/providers/garden_selectors.dart';
import 'package:taproot/features/reflection/domain/check_in_question.dart';

/// The done state: words only.
///
/// **No credit values and no reflection count, in any state**
/// (check-in-design §7.1). Credit is an internal weighting, and showing
/// "+½ credit · 3.50 reflections" turns a moment of being understood into a
/// scoreboard — which is the thing the whole design is trying not to be.
class CheckInDone extends ConsumerWidget {
  const CheckInDone({
    required this.habitId,
    required this.framing,
    required this.inputMode,
    required this.ticker,
    required this.onBack,
    this.commitDay,
    this.declined = false,
    this.showAutonomyInsight = false,
    super.key,
  });

  final String habitId;
  final Framing framing;
  final InputMode inputMode;
  final GardenTicker ticker;
  final VoidCallback onBack;

  /// `Tomorrow` or the weekday of the occasion committed to. Null when step 2
  /// was skipped, and then the sub line simply does not mention a day.
  final String? commitDay;

  final bool declined;

  /// reflection-logic §6 lets exactly one insight fire in v1: the autonomy
  /// milestone, on the habit's **first** un-nudged completion. Everything else
  /// needs an action editor that does not exist, and §0.4 forbids an insight
  /// without an action.
  final bool showAutonomyInsight;

  static const String backLabel = 'Back to the garden';
  static const String rootsTitle = 'Roots deepened.';
  static const String diagnosisTitle = 'Thanks — that helps.';
  static const String blankTitle = 'Noted.';
  static const String blankSub = 'An honest blank still counts.';
  static const String differentDaySub = "We'll check in before the next one.";
  static const String autonomyInsight =
      "You did this without us asking. That's the whole idea.";

  String get title => switch (inputMode) {
    InputMode.cantRemember => blankTitle,
    _ when framing == Framing.diagnosis => diagnosisTitle,
    _ => rootsTitle,
  };

  /// The sub line, assembled from the parts that apply.
  ///
  /// The root-depth words are `rootDepthLabel`'s, capitalised — the bands used
  /// everywhere else in the app (0.30 / 0.50 / 0.75). The prototype has its own
  /// and they are not adopted: one vocabulary for roots, or the card and the
  /// sheet describe the same plant differently.
  String subLine(double rootDepth) {
    final parts = <String>[
      if (inputMode == InputMode.cantRemember)
        blankSub
      else
        _capitalise(rootDepthLabel(rootDepth)),
      if (declined)
        differentDaySub
      else if (commitDay != null)
        '$commitDay is set',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Read from the selector rather than passed in: the engine recomputes after
    // the local write, and whatever it says now is what the garden behind the
    // sheet is already drawing (check-in-design §8).
    final rootDepth = ref.watch(habitRootDepthProvider(habitId)) ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Newsreader',
            fontSize: 30,
            height: 1.15,
            color: GardenColors.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subLine(rootDepth),
          style: TextStyle(
            fontFamily: 'Karla',
            fontSize: 15,
            color: GardenColors.ink.withValues(alpha: 0.75),
          ),
        ),
        if (showAutonomyInsight) ...[
          const SizedBox(height: 16),
          _InsightCard(ticker: ticker, text: autonomyInsight),
        ],
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onBack,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: GardenColors.accent,
              foregroundColor: GardenColors.onAccent,
            ),
            child: const Text(backLabel),
          ),
        ),
      ],
    );
  }

  static String _capitalise(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
}

/// At most one, and only above its evidence threshold.
class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.ticker, required this.text});

  final GardenTicker ticker;
  final String text;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x0DFFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x17FFFFFF)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Newsreader',
          fontStyle: FontStyle.italic,
          fontSize: 17,
          color: GardenColors.inkHint.withValues(alpha: 0.95),
        ),
      ),
    );

    if (ticker.isStill) return card;
    // Fades in after the title, so it reads as a second thought rather than as
    // part of the headline.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: ticker.durationFor(const Duration(milliseconds: 220)),
      builder: (context, value, child) => Opacity(opacity: value, child: child),
      child: card,
    );
  }
}

/// `Tomorrow` or the weekday, for the done sub line.
String commitDayLabel({required DateTime occasionAt, required DateTime now}) =>
    commitFact(nextOccasionAt: occasionAt, now: now) == 'Tomorrow, then.'
    ? 'Tomorrow'
    : weekdayName(occasionAt.toLocal().weekday);
