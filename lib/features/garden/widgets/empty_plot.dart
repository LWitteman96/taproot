import 'package:flutter/material.dart';

import 'package:taproot/app/theme/garden_colors.dart';
import 'package:taproot/app/theme/garden_layout.dart';

/// The slot after the last plant: a dip in the soil and a small marker.
///
/// garden-design §4.5 replaces the floating "Plant another" button with this,
/// so a new habit appears where the offer was rather than arriving from a
/// button that floats over the garden. It is always the last slot, so an empty
/// garden is this and nothing else.
class EmptyPlot extends StatelessWidget {
  const EmptyPlot({required this.groundLine, required this.onTap, super.key});

  final double groundLine;
  final VoidCallback onTap;

  static const String label = 'Plant something';

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The dip, drawn just under the grass so the ground reads as broken
          // ready rather than as a hole.
          Positioned(
            left: 0,
            right: 0,
            top: groundLine,
            height: 18,
            child: CustomPaint(painter: _DipPainter()),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: groundLine - 44,
            child: Center(child: _Marker(label: label)),
          ),
        ],
      ),
    ),
  );
}

class _Marker extends StatelessWidget {
  const _Marker({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      // A sign on a stake, not a button: the garden has no chrome in it, and
      // the one thing that invites a tap should still look like it is planted.
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: GardenColors.pebble.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: GardenColors.monoLabel.withValues(alpha: 0.22),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Karla',
            fontSize: 10,
            color: GardenColors.ink.withValues(alpha: 0.85),
          ),
        ),
      ),
      Container(
        width: 2,
        height: 22,
        color: GardenColors.pebble.withValues(alpha: 0.7),
      ),
    ],
  );
}

class _DipPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.22, 0)
      ..quadraticBezierTo(size.width * 0.5, size.height, size.width * 0.78, 0)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = GardenColors.soil2.withValues(alpha: 0.85),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = GardenColors.soil0.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_DipPainter oldDelegate) => false;
}

/// The hit column for one slot: the whole 128pt width, from the top of the
/// plant's drawn bounds to the bottom of its roots.
///
/// garden-design §4.3 makes the *column* the target rather than the plant,
/// because a seed is 11pt wide and a precise tap on one would be a worse
/// interaction than a generous one. Tapping the soil between columns does
/// nothing, which is what keeps a selection from being lost by a stray tap.
class PlantHitColumn extends StatelessWidget {
  const PlantHitColumn({
    required this.groundLine,
    required this.plantHeight,
    required this.onTap,
    required this.child,
    super.key,
  });

  final double groundLine;
  final double plantHeight;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Positioned.fill(child: child),
      Positioned(
        left: 0,
        right: 0,
        top: groundLine - plantHeight,
        height: plantHeight + GardenLayout.rootsDepth,
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap),
      ),
    ],
  );
}
