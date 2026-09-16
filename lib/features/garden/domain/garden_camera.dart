import 'package:flutter/widgets.dart';

import 'package:taproot/app/theme/garden_layout.dart';

/// Where the garden's camera is pointing.
///
/// The check-in sheet needs the reflected plant centred, larger, and with room
/// below it for full roots — check-in-design §3. That is a move of the *scene*,
/// not a change to any plant: it transforms the scrolling layers as one, so
/// garden-design §2's "one world, one scale" still holds. Every plant is still
/// drawn at world scale; the camera is just closer.
@immutable
class GardenCamera {
  const GardenCamera({
    required this.scale,
    required this.focusSceneX,
    required this.groundLineFraction,
  });

  /// The garden as you normally see it.
  static const GardenCamera home = GardenCamera(
    scale: 1,
    focusSceneX: null,
    groundLineFraction: GardenLayout.groundLineFraction,
  );

  /// Pulled in on one plant, with the ground line raised to make room for its
  /// roots.
  ///
  /// OPEN — 2.2x and 38% were chosen from a 402x874 mock-up (check-in-design
  /// §10, question 1). Unverified on the smallest phone with the tallest sheet
  /// content, which is the typing sub-step with a keyboard up.
  static const double sheetScale = 2.2;
  static const double sheetGroundLineFraction = 0.38;

  factory GardenCamera.onPlant(int slotIndex) => GardenCamera(
    scale: sheetScale,
    focusSceneX: GardenLayout.slotCentre(slotIndex),
    groundLineFraction: sheetGroundLineFraction,
  );

  final double scale;

  /// The scene x the camera centres on, or null to leave the scroll alone.
  final double? focusSceneX;

  final double groundLineFraction;

  bool get isHome => focusSceneX == null && scale == 1;

  /// How far full roots reach below the ground line at this scale.
  double get rootsReach => GardenLayout.rootsDepth * scale;

  /// The transform that puts [focusSceneX] at the horizontal centre of
  /// [viewport], scaled about the ground line so the ground does not slide.
  Matrix4 transformFor({required Size viewport, required double groundLine}) {
    final focus = focusSceneX;
    if (focus == null) return Matrix4.identity();
    return Matrix4.identity()
      ..translateByDouble(viewport.width / 2, groundLine, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-focus, -groundLine, 0, 1);
  }

  /// Interpolated for the camera move, which runs with the sheet's entry.
  static GardenCamera lerp(GardenCamera from, GardenCamera to, double t) =>
      GardenCamera(
        scale: from.scale + (to.scale - from.scale) * t,
        // The focus is whichever end actually has one: a move to or from home
        // still has to know which plant it is moving around.
        focusSceneX: to.focusSceneX ?? from.focusSceneX,
        groundLineFraction:
            from.groundLineFraction +
            (to.groundLineFraction - from.groundLineFraction) * t,
      );

  @override
  bool operator ==(Object other) =>
      other is GardenCamera &&
      other.scale == scale &&
      other.focusSceneX == focusSceneX &&
      other.groundLineFraction == groundLineFraction;

  @override
  int get hashCode => Object.hash(scale, focusSceneX, groundLineFraction);
}
