import 'dart:ui';

import 'package:taproot/app/theme/garden_colors.dart';

/// What time it looks like in the garden.
///
/// garden-design §7 takes the cuts from the prototype's code rather than its
/// README, which omits the 06:00 boundary: night before 06:00, dawn before
/// 09:00, day before 17:00, dusk before 20:00, then night again.
enum TimeOfDayMode {
  dawn,
  day,
  dusk,
  night;

  static TimeOfDayMode forHour(int hour) {
    if (hour < 6) return TimeOfDayMode.night;
    if (hour < 9) return TimeOfDayMode.dawn;
    if (hour < 17) return TimeOfDayMode.day;
    if (hour < 20) return TimeOfDayMode.dusk;
    return TimeOfDayMode.night;
  }

  /// The greeting, exactly as the handoff specifies it.
  String get greeting => switch (this) {
    TimeOfDayMode.dawn => 'Good morning.',
    TimeOfDayMode.day => 'Good afternoon.',
    TimeOfDayMode.dusk => 'Good evening.',
    TimeOfDayMode.night => 'Good night.',
  };

  /// Sky gradient stops, top to bottom, with their positions.
  ///
  /// Day and night have three stops where dusk has four, so the colours and
  /// their stops travel together rather than being two lists to keep in step.
  List<(Color, double)> get sky => switch (this) {
    TimeOfDayMode.dusk => [
      (GardenColors.dusk0, 0),
      (GardenColors.dusk1, 0.45),
      (GardenColors.dusk2, 0.82),
      (GardenColors.dusk3, 1),
    ],
    TimeOfDayMode.dawn => [
      (GardenColors.dawn0, 0),
      (GardenColors.dawn1, 0.45),
      (GardenColors.dawn2, 1),
    ],
    TimeOfDayMode.day => [
      (GardenColors.day0, 0),
      (GardenColors.day1, 0.55),
      (GardenColors.day2, 1),
    ],
    TimeOfDayMode.night => [
      (GardenColors.night0, 0),
      (GardenColors.night1, 0.60),
      (GardenColors.night2, 1),
    ],
  };

  Color get sun => switch (this) {
    TimeOfDayMode.dawn => GardenColors.dawnSun,
    TimeOfDayMode.day => GardenColors.daySun,
    TimeOfDayMode.dusk => GardenColors.duskSun,
    TimeOfDayMode.night => GardenColors.nightMoon,
  };

  Color get haze => switch (this) {
    TimeOfDayMode.dawn => GardenColors.dawnHaze,
    TimeOfDayMode.day => GardenColors.dayHaze,
    TimeOfDayMode.dusk => GardenColors.duskHaze,
    TimeOfDayMode.night => GardenColors.nightHaze,
  };

  /// How strongly the haze reads, per the handoff's per-mode alphas.
  double get hazeOpacity => switch (this) {
    TimeOfDayMode.day => 0.50,
    TimeOfDayMode.night => 0.60,
    _ => 0.55,
  };

  /// Where the sun or moon sits, as a fraction of the sky box, and how wide it
  /// is in points. The handoff gives these as absolute positions on a 402x874
  /// frame; they are fractions here so they hold on other sizes.
  ({double x, double y, double diameter}) get sunPosition => switch (this) {
    TimeOfDayMode.dawn => (x: 52 / 402, y: 392 / 470, diameter: 60),
    TimeOfDayMode.day => (x: 318 / 402, y: 88 / 470, diameter: 60),
    TimeOfDayMode.dusk => (x: 296 / 402, y: 386 / 470, diameter: 60),
    TimeOfDayMode.night => (x: 312 / 402, y: 112 / 470, diameter: 34),
  };
}
