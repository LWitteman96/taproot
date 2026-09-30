import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:taproot/app/theme/garden_colors.dart';
import 'package:taproot/features/garden/domain/garden_ticker.dart';

/// The check-in, as a sheet over the live garden.
///
/// It is a sheet rather than a page for one reason, and it is the whole point:
/// reflection is the only thing that deepens roots, so the user should watch
/// the roots of the habit they just reflected on grow behind it
/// (check-in-design §1). A full-screen page cannot show that.
class CheckInSheet extends StatelessWidget {
  const CheckInSheet({
    required this.habitName,
    required this.step,
    required this.child,
    required this.ticker,
    super.key,
  });

  final String habitName;

  /// `1 of 2`, `2 of 2`, `1 of 1` or `done`.
  final String step;

  final Widget child;
  final GardenTicker ticker;

  static const String title = 'EVENING CHECK-IN';

  /// The handoff's entry: 520ms, translateY 40 plus a fade. The camera move
  /// behind runs on the same curve and duration, so they read as one movement
  /// rather than two things happening at once.
  static const Duration entryDuration = Duration(milliseconds: 520);
  static const Curve entryCurve = Cubic(0.2, 0.8, 0.2, 1);

  @override
  Widget build(BuildContext context) {
    final mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 11,
      letterSpacing: 0.44,
      color: GardenColors.monoLabel.withValues(alpha: 0.65),
    );

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: GardenColors.card.withValues(alpha: 0.96),
            border: const Border(top: BorderSide(color: Color(0x1AFFFFFF))),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 60,
                offset: Offset(0, -20),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 44),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0x2EFFFFFF),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Text(title, style: mono),
                      const Spacer(),
                      // The habit is named on every step. The sheet covers the
                      // garden's own detail card, so without it there is
                      // nothing on screen saying which plant this is about.
                      Flexible(
                        child: Text(
                          '$habitName · $step',
                          style: mono,
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // Internal scrolling rather than a taller sheet: §3 keeps the
                  // sheet's top edge clear of the roots, and the typing
                  // sub-step with a keyboard up is the case that tests it.
                  Flexible(
                    child: SingleChildScrollView(
                      // Not wrapped at all when motion is off. `AnimatedSize`
                      // with a zero duration re-dirties itself inside its own
                      // `performLayout` and throws; and with nothing to
                      // animate, the wrapper has no job left to do.
                      child: ticker.isStill
                          ? child
                          : AnimatedSize(
                              duration: ticker.durationFor(entryDuration),
                              curve: entryCurve,
                              alignment: Alignment.topCenter,
                              child: child,
                            ),
                    ),
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

/// A message where the sheet's question would be: nothing to ask, or a failure.
///
/// Both keep the copy they already had. The states are not new — only where
/// they are drawn is (check-in-design §4.5).
class CheckInMessage extends StatelessWidget {
  const CheckInMessage({
    required this.headline,
    required this.body,
    required this.actionLabel,
    required this.onAction,
    super.key,
  });

  final String headline;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        headline,
        style: const TextStyle(
          fontFamily: 'Newsreader',
          fontSize: 27,
          height: 1.15,
          color: GardenColors.ink,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        body,
        style: TextStyle(
          fontFamily: 'Karla',
          fontSize: 15,
          color: GardenColors.ink.withValues(alpha: 0.7),
        ),
      ),
      const SizedBox(height: 22),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: onAction,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            backgroundColor: GardenColors.accent,
            foregroundColor: GardenColors.onAccent,
          ),
          child: Text(actionLabel),
        ),
      ),
    ],
  );
}
