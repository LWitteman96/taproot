import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Where things sit in the garden scene, as design tokens.
///
/// Alongside `AppMotion` and for the same reason: these are design values, not
/// engine inputs, so they must not live in `lib/core/engine/constants.dart`
/// where a change would bump the version stamp and invalidate every cached
/// derivation. garden-design §4.2 asks for `worldScale` specifically to be a
/// token here and never inlined.
abstract final class GardenLayout {
  /// One art pixel, in logical points. garden-design §4.2.
  ///
  /// Every plant is drawn at this scale on the same ground line, so size
  /// differences between plants are growth and never layout. A 1024-square
  /// stage artboard becomes 153.6pt; a mature fern is about 115pt tall and a
  /// seed about 11pt wide.
  ///
  /// OPEN — chosen from a mock-up at 402pt width (garden-design §10, question
  /// 1). Unverified on the smallest supported phone, and it is an open question
  /// whether a tablet should show more plants or bigger ones.
  static const double worldScale = 0.15;

  /// Distance between plant centres. garden-design §4.3.
  static const double slotPitch = 128;

  /// The first plant's centre, from the scene's left edge: 16pt inset plus half
  /// a pitch. Plant *n* sits at `slotCentre(n)`.
  static const double firstSlotCentre = 16 + slotPitch / 2;

  static double slotCentre(int index) => firstSlotCentre + slotPitch * index;

  /// The ground line, as a fraction of the full screen height.
  ///
  /// garden-design §4.1: everything below is placed relative to it, so the
  /// layout scales with the viewport rather than pinning to the 402x874
  /// reference frame.
  static const double groundLineFraction = 0.53;

  /// Soil that must stay visible between the ground line and the top of the
  /// detail card, so full-depth roots are never covered. On a short screen the
  /// ground line moves up rather than the card covering roots.
  static const double minimumSoilBelowGround = 90;

  /// The stage artboards are 1024 square, and the plant stands on canvas
  /// y = 900 rather than on the bottom edge. garden-design §4.2.
  static const double stageCanvasSize = 1024;
  static const double stageCanvasGroundY = 900;

  /// The drawn size of a stage artboard, and how far its ground line sits above
  /// its own bottom edge once scaled.
  static const double stageSize = stageCanvasSize * worldScale;
  static const double stageGroundOffset =
      (stageCanvasSize - stageCanvasGroundY) * worldScale;

  /// `FernRoots` is 1024 x 520 with its ground line at its **top** edge, so at
  /// world scale full roots reach this far below the ground line.
  ///
  /// Used already, before the roots are drawn (build step 4): the hit column
  /// runs from the top of a plant to the bottom of its roots, and sizing that
  /// correctly now means the target does not move when the art arrives.
  static const double rootsCanvasHeight = 520;
  static const double rootsDepth = rootsCanvasHeight * worldScale;

  /// The grass band. Its **top** edge is the ground line.
  static const double grassBandHeight = 7;

  /// The horizon haze: a band ending at the ground line.
  static const double horizonHazeHeight = 140;

  /// The ground line for a viewport of [height], in logical points from the top.
  ///
  /// Clamped so the card never eats the roots: on a screen too short to give
  /// [minimumSoilBelowGround] below the fraction, the ground line moves up.
  static double groundLine(Size viewport, {required double cardTop}) {
    final preferred = viewport.height * groundLineFraction;
    final latest = cardTop - minimumSoilBelowGround;
    return math.min(preferred, math.max(0, latest));
  }

  /// The scene's total width for [plantCount] plants, including the empty plot
  /// that always follows them, with a trailing margin symmetric to the inset.
  ///
  /// Never narrower than the viewport: the ground is the floor of the world, so
  /// a garden with one plant in it still has soil all the way to both edges.
  static double sceneWidth(int plantCount, {double viewportWidth = 0}) =>
      math.max(viewportWidth, slotCentre(plantCount) + slotPitch / 2 + 16);
}
