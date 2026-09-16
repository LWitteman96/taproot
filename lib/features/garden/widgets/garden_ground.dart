import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:taproot/app/theme/garden_colors.dart';
import 'package:taproot/app/theme/garden_layout.dart';

/// Grass, soil, strata and pebbles: scene layers 4–5.
///
/// Painted rather than composed from widgets because it is one continuous
/// surface the width of the whole scrollable scene, and because the strata and
/// pebbles are generated from the width rather than being a fixed set. The
/// handoff fixes seven pebbles on a 402pt frame; garden-design §3 says to seed
/// them per scene width instead, so a long garden does not run out of them.
class GardenGround extends StatelessWidget {
  const GardenGround({
    required this.width,
    required this.height,
    required this.groundLine,
    super.key,
  });

  final double width;
  final double height;

  /// Distance from the top of this widget to the ground line — the top edge of
  /// the grass band.
  final double groundLine;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size(width, height),
      painter: _GroundPainter(groundLine: groundLine),
      isComplex: true,
      willChange: false,
    ),
  );
}

class _GroundPainter extends CustomPainter {
  const _GroundPainter({required this.groundLine});

  final double groundLine;

  /// One pebble every ~57pt of scene, which reproduces the handoff's seven on a
  /// 402pt frame and keeps the density even as the garden grows.
  static const double _pebbleSpacing = 57;

  /// Fixed, so the ground does not reshuffle its pebbles on every repaint. The
  /// scene is a place; it should look the same when you scroll back.
  static const int _seed = 0x7A9C;

  @override
  void paint(Canvas canvas, Size size) {
    final soilTop = groundLine + GardenLayout.grassBandHeight;
    _paintSoil(canvas, size, soilTop);
    _paintStrata(canvas, size, soilTop);
    _paintPebbles(canvas, size, soilTop);
    _paintGrass(canvas, size);
  }

  void _paintSoil(Canvas canvas, Size size, double soilTop) {
    final rect = Rect.fromLTRB(0, soilTop, size.width, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            GardenColors.soil0,
            GardenColors.soil1,
            GardenColors.soil2,
            GardenColors.soil3,
          ],
          stops: [0, 0.35, 0.75, 1],
        ).createShader(rect),
    );
  }

  /// Faint horizontal banding, angled 2°, at 50% opacity over the soil.
  void _paintStrata(Canvas canvas, Size size, double soilTop) {
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, soilTop, size.width, size.height));
    // Rotating about the left edge would lift the right end off the bottom of
    // the scene on a wide garden, so the rotation is about the centre and the
    // lines are drawn overwide to cover the corners it opens up.
    canvas.translate(size.width / 2, soilTop);
    canvas.rotate(2 * math.pi / 180);
    canvas.translate(-size.width / 2, -soilTop);

    final overhang = size.width * math.tan(2 * math.pi / 180);
    final light = Paint()
      ..color = GardenColors.soil0.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    final dark = Paint()
      ..color = GardenColors.soil3.withValues(alpha: 0.5)
      ..strokeWidth = 1;

    for (double y = soilTop; y < size.height + overhang; y += 41) {
      canvas.drawLine(
        Offset(-overhang, y),
        Offset(size.width + overhang, y),
        light,
      );
      canvas.drawLine(
        Offset(-overhang, y + 3),
        Offset(size.width + overhang, y + 3),
        dark,
      );
    }
    canvas.restore();
  }

  void _paintPebbles(Canvas canvas, Size size, double soilTop) {
    final random = math.Random(_seed);
    final count = math.max(3, (size.width / _pebbleSpacing).round());
    final depth = size.height - soilTop;
    if (depth <= 0) return;

    for (var i = 0; i < count; i++) {
      // Spread across the width by index rather than at random, so pebbles
      // never clump or leave a bare stretch; the jitter within the band is what
      // stops it reading as a row.
      final x = size.width * (i + 0.5) / count + random.nextDouble() * 24 - 12;
      final y = soilTop + 12 + random.nextDouble() * (depth - 16).clamp(0, 400);
      final width = 5 + random.nextDouble() * 4;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x, y),
          width: width,
          height: width * 0.62,
        ),
        Paint()
          ..color = GardenColors.pebble.withValues(
            alpha: 0.55 + random.nextDouble() * 0.35,
          ),
      );
    }
  }

  /// The grass band. Its **top** edge is the ground line, which is what every
  /// plant stands on.
  void _paintGrass(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      0,
      groundLine,
      size.width,
      GardenLayout.grassBandHeight,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        rect,
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      ),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [GardenColors.grassTop, GardenColors.grassBottom],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GroundPainter oldDelegate) =>
      oldDelegate.groundLine != groundLine;
}
