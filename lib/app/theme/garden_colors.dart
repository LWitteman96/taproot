import 'dart:ui';

/// The garden scene's colours, from the design handoff.
///
/// Generated from `docs/design/garden-home-handoff/tokens.json`; the hex values
/// there are sRGB conversions of oklch, which is the canonical source. Do not
/// hand-edit — regenerate from the tokens if the design changes.
///
/// These are **scene** colours: sky, soil, grass, water, roots. garden-design §8
/// exempts them from `AppColors`' three-hue rule on the grounds that they are a
/// depiction rather than an interface. Chrome on this screen — card, buttons,
/// text — still comes from the dark [ColorScheme], not from here.
abstract final class GardenColors {
  // The app background, behind everything.
  /// `oklch(0.19 0.02 50)`
  static const Color bgApp = Color(0xFF1B110C);

  // Soil, and what sits in it.
  /// `oklch(0.33 0.04 55)`
  static const Color soil0 = Color(0xFF463021);

  /// `oklch(0.27 0.03 52)`
  static const Color soil1 = Color(0xFF322219);

  /// `oklch(0.21 0.02 50)`
  static const Color soil2 = Color(0xFF201610);

  /// `oklch(0.18 0.015 50)`
  static const Color soil3 = Color(0xFF17100C);

  /// `oklch(0.15 0.02 50)`
  static const Color damp = Color(0xFF120905);

  /// `oklch(0.38 0.03 62)`
  static const Color pebble = Color(0xFF4E3F32);

  // The grass band at the ground line.
  /// `oklch(0.46 0.07 130)`
  static const Color grassTop = Color(0xFF4B6035);

  /// `oklch(0.36 0.05 110)`
  static const Color grassBottom = Color(0xFF3F3F1F);

  // Text on the scene.
  /// `oklch(0.94 0.015 80)`
  static const Color ink = Color(0xFFF0EAE0);

  /// `oklch(0.86 0.06 80)`
  static const Color inkHint = Color(0xFFE6CDA5);

  /// `oklch(0.90 0.03 145)`
  static const Color monoLabel = Color(0xFFD2E4D2);

  // Chrome: the card, the toast, the accent and the selection.
  /// `oklch(0.74 0.09 145)`
  static const Color accent = Color(0xFF87BA88);

  /// `oklch(0.18 0.03 145)`
  static const Color onAccent = Color(0xFF091509);

  /// `oklch(0.24 0.025 55)`
  static const Color card = Color(0xFF291C14);

  /// `oklch(0.28 0.03 55)`
  static const Color toast = Color(0xFF35251B);

  /// `oklch(0.78 0.10 145)`
  static const Color selectionGlow = Color(0xFF8FC990);

  // Roots. Used by the art pass in `fern/`, not drawn by Flutter.
  /// `oklch(0.62 0.07 75)`
  static const Color root = Color(0xFF9F8056);

  /// `oklch(0.58 0.06 72)`
  static const Color rootFade = Color(0xFF917552);

  // Placeholder silhouettes, for the five species with no art.
  /// `oklch(0.48 0.08 145)`
  static const Color plantHealthy = Color(0xFF3F6A41);

  /// `oklch(0.80 0.07 145)`
  static const Color plantHealthyStroke = Color(0xFFA2CAA2);

  /// `oklch(0.46 0.04 105)`
  static const Color plantThirsty = Color(0xFF5B5A3F);

  /// `oklch(0.72 0.05 100)`
  static const Color plantThirstyStroke = Color(0xFFACA682);

  // The watering drop and its ripple.
  /// `oklch(0.88 0.05 230)`
  static const Color water0 = Color(0xFFB7DEF3);

  /// `oklch(0.72 0.09 235)`
  static const Color water1 = Color(0xFF69AED5);

  // Dusk.
  /// `oklch(0.26 0.05 290)`
  static const Color dusk0 = Color(0xFF241F3A);

  /// `oklch(0.42 0.09 330)`
  static const Color dusk1 = Color(0xFF683964);

  /// `oklch(0.60 0.13 45)`
  static const Color dusk2 = Color(0xFFBE6438);

  /// `oklch(0.70 0.11 65)`
  static const Color dusk3 = Color(0xFFCD8F50);

  /// `oklch(0.88 0.13 60)`
  static const Color duskSun = Color(0xFFFFC27C);

  /// `oklch(0.70 0.11 60)`
  static const Color duskHaze = Color(0xFFD08D54);

  // Dawn.
  /// `oklch(0.32 0.05 290)`
  static const Color dawn0 = Color(0xFF322E4B);

  /// `oklch(0.50 0.08 330)`
  static const Color dawn1 = Color(0xFF7D5279);

  /// `oklch(0.70 0.10 55)`
  static const Color dawn2 = Color(0xFFCF8D60);

  /// `oklch(0.92 0.10 75)`
  static const Color dawnSun = Color(0xFFFFDC98);

  /// `oklch(0.72 0.09 60)`
  static const Color dawnHaze = Color(0xFFCE976A);

  // Day.
  /// `oklch(0.52 0.07 235)`
  static const Color day0 = Color(0xFF3D6F8C);

  /// `oklch(0.66 0.06 220)`
  static const Color day1 = Color(0xFF689BAC);

  /// `oklch(0.78 0.05 100)`
  static const Color day2 = Color(0xFFBEB994);

  /// `oklch(0.97 0.05 95)`
  static const Color daySun = Color(0xFFFFF6D0);

  /// `oklch(0.80 0.05 100)`
  static const Color dayHaze = Color(0xFFC5BF9A);

  // Night.
  /// `oklch(0.15 0.03 280)`
  static const Color night0 = Color(0xFF090917);

  /// `oklch(0.21 0.035 295)`
  static const Color night1 = Color(0xFF191527);

  /// `oklch(0.27 0.03 320)`
  static const Color night2 = Color(0xFF2D2230);

  /// `oklch(0.93 0.02 95)`
  static const Color nightMoon = Color(0xFFECE8D9);

  /// `oklch(0.30 0.03 320)`
  static const Color nightHaze = Color(0xFF352937);
}
