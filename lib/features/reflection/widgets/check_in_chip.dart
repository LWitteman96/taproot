import 'package:flutter/material.dart';

import 'package:taproot/app/theme/garden_colors.dart';
import 'package:taproot/features/garden/domain/garden_ticker.dart';

/// One answer, as a pill.
///
/// Three states (check-in-design §6). **Pinned** means *suggested* — the
/// designed cue, and the Yes chips — and it announces itself that way, because
/// a dot and a tint mean nothing to a screen reader. **Selected** is held for a
/// beat before the sheet moves on, so the tap is visibly registered rather than
/// the screen just changing.
class CheckInChip extends StatefulWidget {
  const CheckInChip({
    required this.label,
    required this.onPressed,
    required this.ticker,
    this.isPinned = false,
    this.isSelected = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final GardenTicker ticker;
  final bool isPinned;
  final bool isSelected;

  /// Announced after the label on a pinned chip.
  static const String pinnedHint = 'suggested';

  /// How long the selection is visible before the sheet advances.
  ///
  /// OPEN — fast enough to feel like one gesture, slow enough to see the
  /// selection? Untested (check-in-design §10, question 3).
  static const Duration selectionHold = Duration(milliseconds: 420);

  static const Duration pressDuration = Duration(milliseconds: 120);

  @override
  State<CheckInChip> createState() => _CheckInChipState();
}

class _CheckInChipState extends State<CheckInChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final (background, border, text) = switch ((
      widget.isSelected,
      widget.isPinned,
    )) {
      (true, _) => (
        GardenColors.accent,
        GardenColors.accent,
        GardenColors.onAccent,
      ),
      (false, true) => (
        GardenColors.accent.withValues(alpha: 0.14),
        GardenColors.accent.withValues(alpha: 0.45),
        GardenColors.ink,
      ),
      (false, false) => (
        const Color(0x0FFFFFFF),
        const Color(0x1FFFFFFF),
        GardenColors.ink,
      ),
    };

    return Semantics(
      // A toggle rather than a button: only one can be selected, and a screen
      // reader should say which one is.
      toggled: widget.isSelected,
      label: widget.isPinned
          ? '${widget.label}, ${CheckInChip.pinnedHint}'
          : widget.label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: _pressed ? 0.96 : 1,
            duration: widget.ticker.durationFor(CheckInChip.pressDuration),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.isPinned && !widget.isSelected) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: GardenColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontFamily: 'Karla',
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: text,
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

/// A secondary action under the chips: `Something else`, `Can't remember`,
/// `Skip`.
///
/// Links rather than chips, deliberately (check-in-design §6). They are ways
/// out, not answers, and giving them a chip's weight would put them on the same
/// footing as the thing being asked.
class CheckInFooterLink extends StatelessWidget {
  const CheckInFooterLink({
    required this.label,
    required this.onPressed,
    this.isQuiet = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  /// `Skip` sits quieter than the rest: it is the way out that records nothing.
  final bool isQuiet;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      minimumSize: const Size(0, 44),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    child: Text(
      label,
      style: TextStyle(
        fontFamily: 'Karla',
        fontSize: 14,
        color: GardenColors.ink.withValues(alpha: isQuiet ? 0.4 : 0.6),
      ),
    ),
  );
}
