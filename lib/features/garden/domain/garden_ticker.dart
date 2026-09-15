import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How much the garden is allowed to move.
///
/// The garden's whole feedback language is visual and it is meant to be alive
/// even when there is nothing to do, which means something in it is always
/// animating. That is three problems at once — a reduced-motion preference, a
/// battery cost, and a widget test that can never settle because the sway loop
/// never ends — and they are all the same problem: nothing owns the decision to
/// animate. This owns it.
///
/// Two dials, because ambient and transient motion fail differently:
///
/// - [ambientEnabled] governs the endless loops — sway, shifting light,
///   weather. This is the one that hangs `pumpAndSettle`, so tests run with it
///   off.
/// - [motionScale] governs finite, caused animation — the pour, a card settling
///   into a new stage. At `0` those resolve instantly to their end state rather
///   than being skipped, so nothing is lost, only the travel.
///
/// What it deliberately does **not** govern is the watering hold duration. That
/// is a gesture requirement, not decoration; scaling it would make the accident
/// the hold exists to prevent easier the moment someone turns motion down.
@immutable
class GardenTicker {
  const GardenTicker({required this.ambientEnabled, required this.motionScale})
    : assert(motionScale >= 0, 'motionScale is a multiplier, never negative');

  /// Everything moves.
  static const GardenTicker lively = GardenTicker(
    ambientEnabled: true,
    motionScale: 1,
  );

  /// Nothing moves. Reduced motion, and the default in widget tests.
  static const GardenTicker still = GardenTicker(
    ambientEnabled: false,
    motionScale: 0,
  );

  /// Caused motion still plays; the endless loops do not. The battery setting's
  /// shape — the app stops idling without going flat.
  static const GardenTicker calm = GardenTicker(
    ambientEnabled: false,
    motionScale: 1,
  );

  final bool ambientEnabled;

  /// A multiplier on transient durations. 1 is nominal, 0 is instant.
  final double motionScale;

  bool get isStill => motionScale == 0;

  /// [nominal] scaled. Zero means "already at the end", which every
  /// `AnimationController` here handles as a jump rather than a division.
  Duration durationFor(Duration nominal) => isStill
      ? Duration.zero
      : Duration(microseconds: (nominal.inMicroseconds * motionScale).round());

  @override
  bool operator ==(Object other) =>
      other is GardenTicker &&
      other.ambientEnabled == ambientEnabled &&
      other.motionScale == motionScale;

  @override
  int get hashCode => Object.hash(ambientEnabled, motionScale);

  @override
  String toString() =>
      'GardenTicker(ambient: $ambientEnabled, scale: $motionScale)';
}

/// The app-wide motion setting.
///
/// Separate from the platform's reduced-motion flag on purpose: this is the
/// half the app controls (a settings toggle, a battery-saver response), and the
/// platform preference is folded in at the point of use by [gardenTickerOf],
/// which is the only place that has a `BuildContext` to read it from.
final gardenTickerProvider =
    NotifierProvider<GardenTickerController, GardenTicker>(
      GardenTickerController.new,
    );

class GardenTickerController extends Notifier<GardenTicker> {
  @override
  GardenTicker build() => GardenTicker.lively;

  void set(GardenTicker ticker) => state = ticker;
}

/// The ticker to actually animate with here.
///
/// A platform reduced-motion preference wins over the app's setting and is
/// never merely advisory — `MediaQuery.disableAnimationsOf` is the accessibility
/// answer, and an app that treats it as a hint is the reason people turn it on.
GardenTicker gardenTickerOf(BuildContext context, WidgetRef ref) =>
    MediaQuery.disableAnimationsOf(context)
    ? GardenTicker.still
    : ref.watch(gardenTickerProvider);
