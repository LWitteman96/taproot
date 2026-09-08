/// The spacing scale.
///
/// One scale, used everywhere, so vertical rhythm is a decision made once
/// rather than re-guessed per screen. Steps are roughly 1.5×, which reads as
/// calm rather than as a grid.
abstract final class AppSpacing {
  static const double extraSmall = 4;
  static const double small = 8;
  static const double medium = 16;
  static const double large = 24;
  static const double extraLarge = 32;
  static const double huge = 48;

  /// The horizontal inset of a normal page. Generous, because the garden wants
  /// air around it more than it wants width.
  static const double pageHorizontal = large;

  /// The vertical inset at the top and bottom of a page.
  static const double pageVertical = large;
}
