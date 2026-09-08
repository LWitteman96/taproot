import 'package:flutter/material.dart';

import 'package:taproot/app/theme/app_colors.dart';
import 'package:taproot/app/theme/app_dimensions.dart';
import 'package:taproot/app/theme/app_radius.dart';
import 'package:taproot/app/theme/app_spacing.dart';

/// The app's two themes.
///
/// Both are built by [_themeFor] from a [ColorScheme], so light and dark can
/// only ever differ in colour — a component styled in one is styled in the
/// other. Dark mode is a design-spec §6 commitment, not an afterthought, and
/// this is what keeps it from drifting.
abstract final class AppTheme {
  static final ThemeData light = _themeFor(AppColors.lightScheme);
  static final ThemeData dark = _themeFor(AppColors.darkScheme);
}

ThemeData _themeFor(ColorScheme colors) {
  final base = ThemeData(colorScheme: colors, useMaterial3: true);
  final text = _textThemeFor(base.textTheme, colors);

  return base.copyWith(
    scaffoldBackgroundColor: colors.surface,
    textTheme: text,
    // Nothing in the garden snaps. Splash and ripple stay, but the surfaces
    // they land on are flat and unshadowed — depth comes from warmth, not from
    // elevation stacking.
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surface,
      foregroundColor: colors.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: colors.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.large),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: colors.outlineVariant,
      thickness: AppDimensions.dividerThickness,
      space: AppSpacing.large,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(
          AppDimensions.minimumTouchTarget,
          AppDimensions.minimumTouchTarget,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.large,
          vertical: AppSpacing.medium,
        ),
        shape: const StadiumBorder(),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(
          AppDimensions.minimumTouchTarget,
          AppDimensions.minimumTouchTarget,
        ),
        shape: const StadiumBorder(),
        textStyle: text.labelLarge,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.primary,
      circularTrackColor: colors.surfaceContainerHighest,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: colors.onInverseSurface,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
    ),
  );
}

/// Loosens Material's default type.
///
/// No custom font is bundled yet — the plant art and the typeface are both with
/// the designer — so the warmth has to come from the metrics: a little more
/// line height, a little less letter-spacing tightness on headlines, and body
/// copy at a size that reads as a journal rather than as a dashboard.
TextTheme _textThemeFor(TextTheme base, ColorScheme colors) => base.copyWith(
  headlineLarge: base.headlineLarge?.copyWith(
    height: 1.2,
    letterSpacing: -0.4,
    fontWeight: FontWeight.w600,
    color: colors.onSurface,
  ),
  headlineMedium: base.headlineMedium?.copyWith(
    height: 1.2,
    letterSpacing: -0.3,
    fontWeight: FontWeight.w600,
    color: colors.onSurface,
  ),
  titleLarge: base.titleLarge?.copyWith(
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: colors.onSurface,
  ),
  bodyLarge: base.bodyLarge?.copyWith(height: 1.5, color: colors.onSurface),
  bodyMedium: base.bodyMedium?.copyWith(
    height: 1.5,
    color: colors.onSurfaceVariant,
  ),
  labelLarge: base.labelLarge?.copyWith(letterSpacing: 0.1),
);
