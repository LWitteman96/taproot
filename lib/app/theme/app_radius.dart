/// Corner radii.
///
/// Organic, not boxy: nothing in the garden has a hard 90° corner, so the
/// smallest radius here is already soft and the largest is nearly a pebble.
abstract final class AppRadius {
  static const double small = 8;
  static const double medium = 14;
  static const double large = 22;

  /// Fully rounded — pills, chips, the watering control.
  static const double pill = 999;
}
