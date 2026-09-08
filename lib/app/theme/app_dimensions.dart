/// Fixed sizes that are not spacing and not radii.
///
/// The touch target is the one that matters: design-spec §6 commits the app to
/// a press-and-hold watering gesture *and* to a non-gestural accessible path
/// alongside it, and both need a target a thumb can find without looking.
abstract final class AppDimensions {
  /// The smallest interactive box the app ships. Matches the platform
  /// accessibility minimum on both iOS and Android.
  static const double minimumTouchTarget = 48;

  static const double iconSmall = 18;
  static const double iconMedium = 24;
  static const double iconLarge = 32;

  /// Text stops widening here. Long-form reflection copy past roughly this
  /// width stops being comfortable to read on a tablet.
  static const double maximumContentWidth = 560;

  static const double dividerThickness = 1;

  /// The diameter of the startup spinner.
  static const double progressIndicatorSize = 28;
}
