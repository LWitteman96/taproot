import 'package:flutter/widgets.dart';

import 'package:taproot/features/garden/domain/time_of_day_mode.dart';

/// Sky, sun and horizon haze: scene layers 1–3.
///
/// Fixed while the garden scrolls (garden-design §3). That is the whole reason
/// this is a separate widget from the ground — it makes the sky a backdrop and
/// the ground a place you move along, rather than a single scrolling image.
class GardenSky extends StatelessWidget {
  const GardenSky({required this.mode, required this.groundLine, super.key});

  final TimeOfDayMode mode;

  /// Distance from the top of this widget to the ground line, in points. The
  /// sky ends here and the haze is measured up from it.
  final double groundLine;

  @override
  Widget build(BuildContext context) {
    final stops = mode.sky;
    final sun = mode.sunPosition;

    return SizedBox(
      height: groundLine,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [for (final (color, _) in stops) color],
                stops: [for (final (_, stop) in stops) stop],
              ),
            ),
          ),
          // Positioned rather than aligned: `Alignment` distributes the *slack*
          // around a child, so a 180pt glow lands well short of the fraction it
          // was given. These are centre points, so they are computed as such.
          LayoutBuilder(
            builder: (context, constraints) {
              const glowFactor = 3.0;
              final glow = sun.diameter * glowFactor;
              return Stack(
                children: [
                  Positioned(
                    left: constraints.maxWidth * sun.x - glow / 2,
                    top: constraints.maxHeight * sun.y - glow / 2,
                    width: glow,
                    height: glow,
                    child: _SunOrMoon(colour: mode.sun, diameter: sun.diameter),
                  ),
                ],
              );
            },
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: IgnorePointer(
              child: SizedBox(
                height: 140,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        mode.haze.withValues(alpha: 0),
                        mode.haze.withValues(alpha: mode.hazeOpacity),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SunOrMoon extends StatelessWidget {
  const _SunOrMoon({required this.colour, required this.diameter});

  final Color colour;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    // The glow box is three times the disc, so the falloff finishes well before
    // its own edge and never shows the gradient's boundary.
    return SizedBox.expand(
      child: Stack(
        alignment: Alignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  colour.withValues(alpha: 0.38),
                  colour.withValues(alpha: 0),
                ],
                stops: const [0.18, 1],
              ),
            ),
          ),
          Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}
