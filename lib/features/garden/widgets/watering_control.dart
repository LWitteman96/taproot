import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'package:taproot/app/theme/app_dimensions.dart';
import 'package:taproot/app/theme/app_motion.dart';
import 'package:taproot/app/theme/app_radius.dart';
import 'package:taproot/app/theme/app_spacing.dart';
import 'package:taproot/features/garden/domain/garden_ticker.dart';

/// The watering gesture: press and hold, never a bare tap.
///
/// design-spec §6 decided this, for two reasons that both land here. A hold has
/// duration, so the pour, the soil darkening and the haptic are one continuous
/// act rather than an animation played over a state change. And the home screen
/// is somewhere you open to *visit* — a tap target on a screen built for idle
/// browsing gets hit by accident, and an accidental completion costs more
/// motivation than the rep it fakes.
///
/// The hold length is [AppMotion.waterHoldDuration] and is deliberately not
/// scaled by [GardenTicker]: turning motion down must not make the accident
/// easier. What the ticker governs is the pour — with motion off the fill does
/// not travel, and the control says so in words instead.
///
/// The accessible path is not a fallback bolted on the side. A sustained press
/// is exactly what switch-control and motor-impaired users cannot perform, so
/// the control carries a semantics action that waters on a plain activate, and
/// when the platform reports assistive navigation it renders as an ordinary
/// button whose label does not tell anyone to hold something they cannot.
class WateringControl extends StatefulWidget {
  const WateringControl({
    required this.semanticLabel,
    required this.onWatered,
    required this.ticker,
    this.wateredToday = false,
    this.holdDuration = AppMotion.waterHoldDuration,
    super.key,
  });

  /// What a screen reader hears. The plant's whole state belongs in here, since
  /// none of it is available any other way.
  final String semanticLabel;

  final VoidCallback onWatered;

  final GardenTicker ticker;

  /// Only changes the wording — watering twice in a day is allowed, and the
  /// engine counts both.
  final bool wateredToday;

  final Duration holdDuration;

  static const String holdLabel = 'Hold to water';
  static const String holdAgainLabel = 'Hold to water again';
  static const String holdingLabel = 'Keep holding';
  static const String accessibleLabel = 'Water';
  static const String accessibleAgainLabel = 'Water again';

  @override
  State<WateringControl> createState() => _WateringControlState();
}

class _WateringControlState extends State<WateringControl>
    with SingleTickerProviderStateMixin {
  /// Paints the pour. It runs alongside the recognizer's own timer rather than
  /// driving it — the gesture is decided by the recognizer, and the fill is
  /// only ever a picture of how far along it is. Two clocks would be a bug if
  /// either could complete the watering; only one of them can.
  ///
  /// Built in [initState] rather than lazily: the assistive path never touches
  /// it, so a lazy field would be constructed for the first time inside
  /// [dispose], which looks up `TickerMode` on an element that is already
  /// deactivated.
  late final AnimationController _pour;

  bool _isHeld = false;

  @override
  void initState() {
    super.initState();
    _pour = AnimationController(
      vsync: this,
      duration: widget.holdDuration,
      reverseDuration: AppMotion.waterReleaseDuration,
    );
  }

  @override
  void dispose() {
    _pour.dispose();
    super.dispose();
  }

  void _water() {
    // The haptic is the thunk. It fires when the hold completes, not when the
    // write returns — the payoff belongs to the gesture, and the write is local
    // and may not have finished yet.
    HapticFeedback.mediumImpact();
    widget.onWatered();
  }

  /// The finger landed. No haptic here on purpose: this fires on contact,
  /// including on the touch that turns into a scroll, and a garden that buzzes
  /// every time a thumb crosses a plant is worse than one that never does.
  void _beginHold() {
    if (_isHeld) return;
    setState(() => _isHeld = true);
    // `from: 0`, not a bare `forward()`. Plain `forward()` resumes from
    // wherever the fill got to, and an `AnimationController` scales its travel
    // by the distance left — so a hold begun while an aborted one was still
    // retreating would fill in a fraction of the hold duration and sit there
    // looking finished while the recognizer still had most of the gesture to
    // run. The two clocks have to start together or the picture lies.
    _pour.forward(from: 0);
  }

  /// The hold made it. The finger is usually still down; [_releaseHold] follows
  /// when it lifts and finds nothing left to do.
  void _completeHold() {
    setState(() => _isHeld = false);
    _water();
    // The fill falls back over the settle rather than snapping — the gesture
    // resolves, it does not disappear.
    _pour.reverseDuration = AppMotion.waterSettleDuration;
    _pour.reverse();
  }

  /// The finger left, or the gesture was lost to something else — a scroll,
  /// most often, which is exactly the accident the hold exists to prevent.
  ///
  /// The retreat is faster than the fill was: an abandoned gesture should feel
  /// abandoned.
  void _releaseHold() {
    if (!_isHeld) return;
    setState(() => _isHeld = false);
    if (_pour.status == AnimationStatus.forward) {
      _pour.reverseDuration = AppMotion.waterReleaseDuration;
      _pour.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAssistive = MediaQuery.accessibleNavigationOf(context);

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      // The non-gestural completion path. Every assistive activate — a screen
      // reader double tap, a switch, a keyboard — arrives here and waters
      // without holding anything.
      onTap: _water,
      excludeSemantics: true,
      child: isAssistive ? _assistiveButton(theme) : _holdTarget(theme),
    );
  }

  /// An ordinary button, when the platform says assistive navigation is on.
  ///
  /// Not a duplicate of the semantics action above: this one changes what is
  /// *written* on the control. Telling a switch-control user to hold something
  /// they cannot hold is worse than not offering the gesture at all.
  Widget _assistiveButton(ThemeData theme) => SizedBox(
    height: AppDimensions.minimumTouchTarget,
    child: FilledButton.icon(
      onPressed: _water,
      icon: const Icon(
        Icons.water_drop_outlined,
        size: AppDimensions.iconSmall,
      ),
      label: Text(
        widget.wateredToday
            ? WateringControl.accessibleAgainLabel
            : WateringControl.accessibleLabel,
      ),
    ),
  );

  /// The press-and-hold target.
  ///
  /// A long-press recognizer rather than a tap plus a timer, for two reasons
  /// that both bite. Its down callback fires on contact, so the pour starts
  /// when the finger lands instead of after the tap arena's 100ms deadline. And
  /// it is in the arena, so a finger that starts moving hands the pointer to
  /// the surrounding scrollable and the hold is cancelled — a slow scroll with
  /// a finger resting on a plant must not water it.
  Widget _holdGestures({required Widget child}) => RawGestureDetector(
    behavior: HitTestBehavior.opaque,
    gestures: <Type, GestureRecognizerFactory>{
      LongPressGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(duration: widget.holdDuration),
            (instance) {
              instance.onLongPressDown = (_) => _beginHold();
              instance.onLongPressCancel = _releaseHold;
              instance.onLongPressStart = (_) => _completeHold();
              instance.onLongPressEnd = (_) => _releaseHold();
            },
          ),
    },
    child: child,
  );

  Widget _holdTarget(ThemeData theme) {
    final label = _isHeld && widget.ticker.isStill
        ? WateringControl.holdingLabel
        : widget.wateredToday
        ? WateringControl.holdAgainLabel
        : WateringControl.holdLabel;

    return _holdGestures(
      child: SizedBox(
        height: AppDimensions.minimumTouchTarget,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The pour. Held behind the ticker: with motion off it simply
                // is not built, and the label carries the feedback instead.
                if (!widget.ticker.isStill)
                  AnimatedBuilder(
                    animation: _pour,
                    builder: (context, _) => FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: _pour.value,
                      child: ColoredBox(
                        color: theme.colorScheme.primaryContainer,
                      ),
                    ),
                  ),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.water_drop_outlined,
                        size: AppDimensions.iconSmall,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.small),
                      Text(label, style: theme.textTheme.labelLarge),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
