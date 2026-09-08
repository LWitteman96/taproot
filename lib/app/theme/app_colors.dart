import 'package:flutter/material.dart';

/// Taproot's palette.
///
/// design-spec §6 asks for "journal, not spreadsheet": warm, calm, tactile,
/// organic, and a **restrained 2–3 colours plus an accent**. That restraint is
/// the point, so the palette is three hues and no more —
///
/// - **[moss]**, the living green of a healthy plant, carries primary actions;
/// - **[bark]**, a warm earth brown, carries the ground and secondary surfaces;
/// - **[amber]**, low afternoon light, is the one accent.
///
/// Everything else is a neutral pulled toward those hues rather than a fourth
/// colour: the light ground is warm paper, the dark ground is warm near-black,
/// and the error tone is fired clay rather than the alarm red the spec steers
/// away from. Nothing is pure `#FFFFFF` or `#000000`, because a neutral ground
/// is what makes the app read as clinical.
///
/// Adding a hue here should be a deliberate edit with a reason, not a colour
/// invented at a call site.
abstract final class AppColors {
  // ---- The three hues -------------------------------------------------------

  /// Growth. Primary actions, the healthy plant, the watering affordance.
  static const Color moss = Color(0xFF4F6F52);

  /// Earth. Soil, containers, the secondary voice.
  static const Color bark = Color(0xFF7A5C43);

  /// Late light. The single accent — used sparingly, for what has just changed.
  static const Color amber = Color(0xFFC68A3E);

  // Lifted variants, for the dark theme. The same three hues, raised until they
  // hold their contrast against a dark ground rather than sinking into it.
  static const Color mossLifted = Color(0xFF9DBF9F);
  static const Color barkLifted = Color(0xFFC8A483);
  static const Color amberLifted = Color(0xFFE0AC63);

  // ---- Warm neutrals --------------------------------------------------------

  /// Warm paper — the light ground.
  static const Color parchment = Color(0xFFF7F2E8);
  static const Color parchmentSunk = Color(0xFFEFE7D8);
  static const Color parchmentRaised = Color(0xFFFBF7EF);

  /// Warm near-black — the dark ground. Not `#000000`: a true black ground
  /// makes the plant art read as a cut-out rather than as something growing.
  static const Color loam = Color(0xFF161311);
  static const Color loamRaised = Color(0xFF211D19);
  static const Color loamSunk = Color(0xFF0F0D0B);

  /// Ink, and its quieter voice, for text on a light ground.
  static const Color ink = Color(0xFF2E2A24);
  static const Color inkMuted = Color(0xFF6B6152);
  static const Color inkOutline = Color(0xFFCFC3AC);

  /// The same, inverted, for a dark ground.
  static const Color chalk = Color(0xFFEFE7D8);
  static const Color chalkMuted = Color(0xFFB5A995);
  static const Color chalkOutline = Color(0xFF4A4239);

  /// Fired clay. The app's error tone — visible, but not an alarm.
  static const Color clay = Color(0xFFA4553F);
  static const Color clayLifted = Color(0xFFE08C74);

  // ---- Schemes --------------------------------------------------------------

  /// Written out rather than derived from `ColorScheme.fromSeed`, which spreads
  /// one seed across Material's full tonal range and produces exactly the
  /// even, synthetic palette §6 is steering away from.
  static const ColorScheme lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: moss,
    onPrimary: parchment,
    primaryContainer: Color(0xFFD9E4D6),
    onPrimaryContainer: Color(0xFF20301F),
    secondary: bark,
    onSecondary: parchment,
    secondaryContainer: Color(0xFFE8DBC9),
    onSecondaryContainer: Color(0xFF3A2A1C),
    tertiary: amber,
    onTertiary: Color(0xFF2E2A24),
    tertiaryContainer: Color(0xFFF3E1C2),
    onTertiaryContainer: Color(0xFF3D2C0E),
    error: clay,
    onError: parchment,
    errorContainer: Color(0xFFF2D9D1),
    onErrorContainer: Color(0xFF41180F),
    surface: parchment,
    onSurface: ink,
    surfaceContainerLowest: parchmentRaised,
    surfaceContainer: parchmentSunk,
    surfaceContainerHighest: Color(0xFFE7DDCA),
    onSurfaceVariant: inkMuted,
    outline: inkOutline,
    outlineVariant: Color(0xFFE2D7C2),
    inverseSurface: loamRaised,
    onInverseSurface: chalk,
    inversePrimary: mossLifted,
    shadow: Color(0xFF2E2A24),
    scrim: Color(0xFF2E2A24),
  );

  static const ColorScheme darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: mossLifted,
    onPrimary: Color(0xFF16281A),
    primaryContainer: Color(0xFF32492F),
    onPrimaryContainer: Color(0xFFD9E4D6),
    secondary: barkLifted,
    onSecondary: Color(0xFF2E1F13),
    secondaryContainer: Color(0xFF4A3626),
    onSecondaryContainer: Color(0xFFE8DBC9),
    tertiary: amberLifted,
    onTertiary: Color(0xFF3D2C0E),
    tertiaryContainer: Color(0xFF5C4318),
    onTertiaryContainer: Color(0xFFF3E1C2),
    error: clayLifted,
    onError: Color(0xFF41180F),
    errorContainer: Color(0xFF6B2C1D),
    onErrorContainer: Color(0xFFF2D9D1),
    surface: loam,
    onSurface: chalk,
    surfaceContainerLowest: loamSunk,
    surfaceContainer: loamRaised,
    surfaceContainerHighest: Color(0xFF2C2721),
    onSurfaceVariant: chalkMuted,
    outline: chalkOutline,
    outlineVariant: Color(0xFF332E28),
    inverseSurface: parchmentSunk,
    onInverseSurface: ink,
    inversePrimary: moss,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );
}
