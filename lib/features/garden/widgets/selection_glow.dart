import 'package:flutter/widgets.dart';

import 'package:taproot/app/theme/garden_colors.dart';
import 'package:taproot/features/garden/domain/garden_ticker.dart';

/// The mark on the selected plant: scene layer 8.
///
/// A glow on the ground rather than a ring around the plant. garden-design §9
/// settles that against the prototype's 2pt box ring, because the plants are
/// not boxes — a ring would have to bound art that deliberately overflows its
/// slot, and the ground is where every plant agrees on a position.
///
/// The selected plant is **not** raised in the paint order; this is the only
/// thing that marks it.
class SelectionGlow extends StatelessWidget {
  const SelectionGlow({
    required this.centreX,
    required this.groundLine,
    required this.ticker,
    super.key,
  });

  /// Centre of the selected slot, in the scene's coordinate space.
  final double centreX;
  final double groundLine;
  final GardenTicker ticker;

  static const double width = 120;
  static const double height = 28;

  /// The handoff's 500ms slide. Caused motion, so it scales with the ticker and
  /// becomes an instant move when motion is off rather than being skipped.
  static const Duration slideDuration = Duration(milliseconds: 500);

  @override
  Widget build(BuildContext context) => AnimatedPositioned(
    duration: ticker.durationFor(slideDuration),
    curve: Curves.easeOutCubic,
    left: centreX - width / 2,
    top: groundLine - height / 2,
    width: width,
    height: height,
    child: IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [
              GardenColors.selectionGlow.withValues(alpha: 0.45),
              GardenColors.selectionGlow.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    ),
  );
}
