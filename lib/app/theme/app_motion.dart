/// Durations, as design tokens.
///
/// These sit here rather than in `lib/core/engine/constants.dart` for one
/// reason: that file carries a version stamp, and everything under it is an
/// input to a derivation that may be cached against that version. Bumping the
/// engine's version because someone shortened an animation would invalidate
/// every cached stage and vitality in the app for a change that cannot affect
/// either. Interaction timing is a design token, so it lives with the other
/// design tokens.
abstract final class AppMotion {
  /// How long the watering gesture must be held before it counts.
  ///
  /// design-spec §6 makes the hold the point: a bare tap "both feels like
  /// nothing and gets hit by accident on a screen built for idle browsing", so
  /// this number is the accident guard, not decoration. It is **never scaled by
  /// [GardenTicker]** — throttling motion must not quietly make the gesture
  /// easier to trigger.
  ///
  /// OPEN — a calibration question, not a law. The spec asks for "long enough
  /// not to trigger by accident, short enough not to feel like a chore several
  /// times a week" and says the balance is untested. 600ms is comfortably past
  /// the platform long-press threshold (500ms) without reading as a wait.
  static const Duration waterHoldDuration = Duration(milliseconds: 600);

  /// How long the pour keeps running after the hold completes, so the gesture
  /// resolves rather than snapping.
  static const Duration waterSettleDuration = Duration(milliseconds: 320);

  /// How fast the fill retreats when a hold is released early. Faster than it
  /// filled: an abandoned gesture should feel abandoned.
  static const Duration waterReleaseDuration = Duration(milliseconds: 180);

  /// How long the undo affordance stays on screen after a watering.
  ///
  /// This is the *offer*, not the window. The window is the rest of the local
  /// calendar day and lives in `isRetractable`; this only decides how long the
  /// shortcut sits in front of the user.
  static const Duration undoOfferDuration = Duration(seconds: 6);

  /// A plain state change — a card settling into its new stage.
  static const Duration stateChangeDuration = Duration(milliseconds: 240);

  /// The cross-fade between two stages of plant art.
  ///
  /// Longer than [stateChangeDuration] on purpose. That one is a card settling;
  /// this one is the plant becoming a visibly different plant, and at 240ms a
  /// dissolve between two different silhouettes reads as a glitch rather than
  /// as growth. It is also rare — a handful of times in a habit's life — so it
  /// can afford to be seen.
  ///
  /// OPEN — a calibration question. A stage advance is an earned moment and
  /// design-spec §4 does not say what it should feel like; a cross-fade is the
  /// least it can be, not necessarily the right amount.
  static const Duration stageAdvanceDuration = Duration(milliseconds: 700);
}
