import 'package:flutter/material.dart';

import 'package:taproot/app/theme/garden_colors.dart';
import 'package:taproot/app/theme/garden_layout.dart';
import 'package:taproot/features/garden/domain/time_of_day_mode.dart';
import 'package:taproot/features/garden/widgets/garden_ground.dart';
import 'package:taproot/features/garden/widgets/garden_sky.dart';

/// The world: sky above a ground line, soil below, and whatever stands on it.
///
/// Owns the one geometric decision the rest of the screen hangs off — where the
/// ground line is — and hands it to its children rather than letting each work
/// it out. garden-design §3 fixes the sky and floats the header and card over
/// it; only [ground] scrolls.
class GardenScene extends StatelessWidget {
  const GardenScene({
    required this.mode,
    required this.ground,
    this.header,
    this.detailCard,
    this.sheet,
    this.scrimOpacity = 0,
    this.groundLineFraction = GardenLayout.groundLineFraction,
    super.key,
  });

  final TimeOfDayMode mode;

  /// Everything at or below the ground line, given the scene's size and where
  /// the ground line falls in it.
  final Widget Function(BuildContext context, double groundLine, Size viewport)
  ground;

  final Widget? header;
  final Widget? detailCard;

  /// The check-in, over everything. When it is up the detail card is not.
  final Widget? sheet;

  /// One uniform layer over the scene while the sheet is open. 25% while
  /// asking, 10% on done — the prototype's 35→55% gradient dims the roots too
  /// much for the payoff to read (check-in-design §3).
  final double scrimOpacity;

  /// Animated by the caller: the camera raises the ground line to make room for
  /// roots while the sheet is up.
  final double groundLineFraction;

  /// The card's inset and how far it floats off the bottom, from the handoff.
  static const double cardInset = 16;
  static const double cardBottom = 50;

  /// The scrim's colour, from check-in-design §3: `oklch(0.10 0.02 50)`.
  static const Color scrimColour = Color(0xFF130C08);

  /// Used only to keep the ground line high enough that the card cannot cover a
  /// plant's roots. A real measurement would need a layout pass and would move
  /// the whole scene on the frame after the card changed height; the clamp only
  /// bites on short screens, so an estimate is the right trade.
  static const double estimatedCardHeight = 210;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final viewport = constraints.biggest;
      final groundLine = GardenLayout.groundLine(
        viewport,
        cardTop: viewport.height - cardBottom - estimatedCardHeight,
        fraction: groundLineFraction,
      );

      return ColoredBox(
        color: GardenColors.bgApp,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: GardenSky(mode: mode, groundLine: groundLine),
            ),
            ground(context, groundLine, viewport),
            if (header case final header?)
              Align(alignment: Alignment.topLeft, child: header),
            if (scrimOpacity > 0)
              IgnorePointer(
                ignoring: sheet == null,
                child: ColoredBox(
                  color: scrimColour.withValues(alpha: scrimOpacity),
                ),
              ),
            if (detailCard case final card?)
              Positioned(
                left: cardInset,
                right: cardInset,
                bottom: cardBottom,
                child: card,
              ),
            if (sheet case final sheet?)
              Positioned(left: 0, right: 0, bottom: 0, child: sheet),
          ],
        ),
      );
    },
  );
}

/// The ground, plus whatever stands on it, as one scrollable surface.
///
/// Separate from [GardenScene] because these are the layers that move: grass,
/// soil, pebbles and plants travel together, which is what makes the sky read
/// as a backdrop rather than as part of the same image.
class GardenGroundLayer extends StatelessWidget {
  const GardenGroundLayer({
    required this.groundLine,
    required this.viewport,
    required this.sceneWidth,
    required this.plants,
    super.key,
  });

  final double groundLine;
  final Size viewport;
  final double sceneWidth;

  /// Positioned in the scene's coordinate space, where x is distance from the
  /// scene's left edge and the ground line is at [groundLine].
  final List<Widget> plants;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: sceneWidth,
    height: viewport.height,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        GardenGround(
          width: sceneWidth,
          height: viewport.height,
          groundLine: groundLine,
        ),
        ...plants,
      ],
    ),
  );
}
