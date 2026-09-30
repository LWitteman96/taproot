import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:taproot/app/theme/garden_layout.dart';
import 'package:taproot/app/theme/garden_colors.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/features/garden/domain/plant_descriptions.dart';

/// A plant with no art yet: dashed outline, hatched fill, species and stage in
/// mono underneath.
///
/// garden-design §5 keeps this deliberately honest rather than dressing it up.
/// Five of six species have no art, and a placeholder that tried to look like a
/// plant would be a worse lie than one that says "not drawn yet". It is sized
/// to the fern stage of the same number at world scale, so the garden stays one
/// world and one scale even where it is undrawn.
class PlantSilhouette extends StatelessWidget {
  const PlantSilhouette({
    required this.species,
    required this.stage,
    required this.vitality,
    super.key,
  });

  final String species;
  final Stage stage;
  final double vitality;

  /// Roughly the drawn height of each fern stage at world scale, so an undrawn
  /// oak still stands at the height its growth has earned. Approximations of
  /// the art, not measurements of it — the silhouette is a stand-in and does
  /// not deserve a coupling to the generator.
  static Size sizeFor(Stage stage) => switch (stage) {
    Stage.seed => const Size(11, 9),
    Stage.sprout => const Size(26, 34),
    Stage.seedling => const Size(44, 52),
    Stage.young => const Size(74, 86),
    Stage.mature => const Size(110, 115),
    Stage.bloom => const Size(116, 120),
  };

  bool get _thirsty => vitality < 0.95;

  @override
  Widget build(BuildContext context) {
    final size = sizeFor(stage);
    final fill = _thirsty
        ? GardenColors.plantThirsty
        : GardenColors.plantHealthy;
    final stroke = _thirsty
        ? GardenColors.plantThirstyStroke
        : GardenColors.plantHealthyStroke;

    return CustomPaint(
      size: size,
      painter: _SilhouettePainter(fill: fill, stroke: stroke),
    );
  }
}

/// The mono species/stage caption that goes under a placeholder.
///
/// Separate from the silhouette so the plant's *base* can sit exactly on the
/// ground line: with the caption in the same column, the column's bottom is the
/// caption's bottom and the plant floats a caption's height above the soil.
class PlantSilhouetteLabel extends StatelessWidget {
  const PlantSilhouetteLabel({
    required this.species,
    required this.stage,
    super.key,
  });

  final String species;
  final Stage stage;

  /// The seed is 11pt wide; a two-line caption under it would be wider than the
  /// plant and read as a label for the whole slot.
  bool get isVisible => stage != Stage.seed;

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();
    return Text(
      '$species\n${stageLabel(stage).toLowerCase()}',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 9.5,
        height: 1.25,
        color: GardenColors.monoLabel.withValues(alpha: 0.75),
      ),
    );
  }
}

class _SilhouettePainter extends CustomPainter {
  const _SilhouettePainter({required this.fill, required this.stroke});

  final Color fill;
  final Color stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));

    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(rect, Paint()..color = fill.withValues(alpha: 0.32));

    // Diagonal hatch, so the shape reads as "unfilled" rather than as a solid
    // blob that might be the art.
    final hatch = Paint()
      ..color = stroke.withValues(alpha: 0.22)
      ..strokeWidth = 1;
    for (double x = -size.height; x < size.width; x += 7) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        hatch,
      );
    }
    canvas.restore();

    _dashedRRect(
      canvas,
      rrect,
      Paint()
        ..color = stroke.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  /// Flutter has no dashed stroke, so the outline is walked in 4-on/3-off steps.
  void _dashedRRect(Canvas canvas, RRect rrect, Paint paint) {
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + 4, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + 3;
      }
    }
  }

  @override
  bool shouldRepaint(_SilhouettePainter oldDelegate) =>
      oldDelegate.fill != fill || oldDelegate.stroke != stroke;
}

/// The drawn height of a plant at [stage], whether it has art or not. Used to
/// size the hit column and to place the selection glow.
double plantHeightFor(Stage stage, {required bool hasArt}) =>
    hasArt ? GardenLayout.stageSize : PlantSilhouette.sizeFor(stage).height;
