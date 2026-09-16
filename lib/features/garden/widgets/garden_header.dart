import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/theme/app_spacing.dart';
import 'package:taproot/app/theme/garden_colors.dart';
import 'package:taproot/features/garden/providers/garden_scene_providers.dart';

/// Greeting, status line and the check-in chip: scene layer 11. Fixed.
///
/// design-spec §6 and garden-design §2: this says how the garden *is*, never
/// what is due. There is no count of what is done, no progress bar and nothing
/// red, and the wording of the status line is fixed by the handoff.
class GardenHeader extends ConsumerWidget {
  const GardenHeader({required this.checkInChip, super.key});

  /// The check-in invitation, when there is an offer. Passed in rather than
  /// read here so the header does not depend on reflection.
  final Widget? checkInChip;

  static const String allWatered = 'Everything’s watered. Just visiting?';

  /// The handoff spells small counts and leaves the rest as digits.
  static String thirstyLine(int count) => switch (count) {
    0 => allWatered,
    1 => 'One plant could use a drink.',
    2 => 'Two plants could use a drink.',
    3 => 'Three plants could use a drink.',
    4 => 'Four plants could use a drink.',
    _ => '$count plants could use a drink.',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(timeOfDayModeProvider);
    final thirsty = ref.watch(thirstyCountProvider);

    // One shadow on both lines: the header sits over a gradient sky whose
    // lightness changes with the time of day, and at dawn the ink is nearly the
    // same value as the sky behind it.
    const shadow = [
      Shadow(color: Color(0x40000000), blurRadius: 12, offset: Offset(0, 1)),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 66, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            mode.greeting,
            style: const TextStyle(
              fontFamily: 'Newsreader',
              fontSize: 32,
              height: 1.1,
              letterSpacing: -0.32,
              color: GardenColors.ink,
              shadows: shadow,
            ),
          ),
          const SizedBox(height: AppSpacing.extraSmall),
          Text(
            thirstyLine(thirsty),
            style: TextStyle(
              fontFamily: 'Karla',
              fontSize: 15,
              color: GardenColors.ink.withValues(alpha: 0.78),
              shadows: shadow,
            ),
          ),
          if (checkInChip case final chip?) ...[
            const SizedBox(height: AppSpacing.small),
            chip,
          ],
        ],
      ),
    );
  }
}
