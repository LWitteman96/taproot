import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/app/theme/app_colors.dart';
import 'package:taproot/app/theme/app_dimensions.dart';
import 'package:taproot/app/theme/app_radius.dart';
import 'package:taproot/app/theme/app_spacing.dart';
import 'package:taproot/app/theme/themedata.dart';

void main() {
  group('AppTheme', () {
    test('ships a light and a dark theme, both Material 3', () {
      expect(AppTheme.light.brightness, Brightness.light);
      expect(AppTheme.dark.brightness, Brightness.dark);
      expect(AppTheme.light.useMaterial3, isTrue);
      expect(AppTheme.dark.useMaterial3, isTrue);
    });

    test('uses the app palette rather than a Material default', () {
      expect(AppTheme.light.colorScheme, AppColors.lightScheme);
      expect(AppTheme.dark.colorScheme, AppColors.darkScheme);
      expect(
        AppTheme.light.scaffoldBackgroundColor,
        AppColors.lightScheme.surface,
      );
      expect(
        AppTheme.dark.scaffoldBackgroundColor,
        AppColors.darkScheme.surface,
      );
    });

    test('keeps the ground warm rather than clinical white or black', () {
      // "Journal, not spreadsheet" (design-spec §6). A stark #FFFFFF page or a
      // pure #000000 one is the look the spec is steering away from, so this
      // asserts the surfaces carry warmth: red above blue in both themes.
      final light = AppColors.lightScheme.surface;
      final dark = AppColors.darkScheme.surface;

      expect(light, isNot(const Color(0xFFFFFFFF)));
      expect(dark, isNot(const Color(0xFF000000)));
      expect(light.r, greaterThan(light.b));
      expect(dark.r, greaterThan(dark.b));
    });

    test('stays restrained — the palette is a small, shared set', () {
      // A restrained 2–3 colours plus an accent. If a fourth hue creeps in it
      // should be a deliberate edit here, not an accident at a call site.
      expect(AppColors.lightScheme.primary, AppColors.moss);
      expect(AppColors.lightScheme.secondary, AppColors.bark);
      expect(AppColors.lightScheme.tertiary, AppColors.amber);
    });
  });

  group('the scales', () {
    test('spacing steps upward', () {
      const steps = <double>[
        AppSpacing.extraSmall,
        AppSpacing.small,
        AppSpacing.medium,
        AppSpacing.large,
        AppSpacing.extraLarge,
        AppSpacing.huge,
      ];
      expect(steps, orderedEquals(<double>[...steps]..sort()));
      expect(steps.toSet(), hasLength(steps.length));
    });

    test('radii are generous enough to read as organic', () {
      expect(AppRadius.small, greaterThanOrEqualTo(6));
      expect(AppRadius.large, greaterThan(AppRadius.medium));
      expect(AppRadius.medium, greaterThan(AppRadius.small));
    });

    test('the touch target meets the accessibility minimum', () {
      expect(AppDimensions.minimumTouchTarget, greaterThanOrEqualTo(48));
    });
  });
}
