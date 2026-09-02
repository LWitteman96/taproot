import 'package:meta/meta.dart';

import 'dart:math' as math;

import 'package:taproot/core/engine/constants.dart';
import 'package:taproot/core/engine/inputs.dart';
import 'package:taproot/core/engine/pauses.dart';
import 'package:taproot/core/utils/local_dates.dart';

/// Adherence over one window (growth spec §2).
///
/// The window is defined in *expected repetitions* and converted to days. A
/// fixed calendar window breaks immediately: 14 days holds 6 expected runs at
/// f = 3 but only 2 at f = 1, so the weekly-habit user's score would swing 50%
/// on a single miss.
@immutable
class AdherenceWindow {
  const AdherenceWindow({
    required this.windowReps,
    required this.windowDays,
    required this.windowStart,
    required this.expectedCompletions,
    required this.completions,
    required this.adherence,
    required this.ceilingBinds,
  });

  /// W_reps.
  final int windowReps;

  /// W_days = clamp(⌈W_reps × 7 / f⌉, 14, 42), counted in *active* days.
  final int windowDays;

  /// The oldest active local date in the window. Earlier in wall-clock time
  /// than `windowDays` back whenever the window spans a pause.
  final LocalDate windowStart;

  /// Expected = f × W_days / 7.
  final double expectedCompletions;

  final int completions;

  /// A = min(completions / expected, 1.0). Capped: overperformance doesn't buy
  /// slack, it's a signal to renegotiate identity upward.
  final double adherence;

  /// Whether the 42-day ceiling clamped this window. When it does, adjacent
  /// stage thresholds round to the same integer and the taper disappears.
  final bool ceilingBinds;

  @override
  String toString() =>
      'AdherenceWindow(reps: $windowReps, days: $windowDays, '
      'expected: $expectedCompletions, completions: $completions, '
      'A: $adherence)';
}

/// W_days for a window of [windowReps] expected repetitions.
///
/// Rounded up to a whole calendar day: a window is a set of local dates, and
/// this is what makes the spec's Young window read as 19 days expecting 8.1
/// runs rather than 18.67 expecting 8.
int windowDaysForReps({
  required int windowReps,
  required int targetFrequency,
}) => _rawWindowDays(
  windowReps,
  targetFrequency,
).clamp(EngineConstants.minimumWindowDays, EngineConstants.maximumWindowDays);

/// Whether the 42-day ceiling binds for this window — the clamp-collapse
/// condition. Binds for Bloom below f ~ 3.3 and for Mature below f = 2.
bool windowCeilingBinds({
  required int windowReps,
  required int targetFrequency,
}) =>
    _rawWindowDays(windowReps, targetFrequency) >
    EngineConstants.maximumWindowDays;

/// Adherence over the window of [windowReps] repetitions ending at [at].
AdherenceWindow computeAdherence({
  required HabitInputs inputs,
  required int windowReps,
  required DateTime at,
}) {
  final windowDays = windowDaysForReps(
    windowReps: windowReps,
    targetFrequency: inputs.targetFrequency,
  );
  final dates = activeWindowDates(
    at: at,
    windowDays: windowDays,
    pauses: inputs.pauses,
  );
  final window = dates.toSet();

  var completions = 0;
  for (final completion in inputs.completions) {
    if (completion.completedAt.isAfter(at)) continue;
    if (window.contains(LocalDate.from(completion.completedAt))) completions++;
  }

  final expected = inputs.targetFrequency * windowDays / 7;
  return AdherenceWindow(
    windowReps: windowReps,
    windowDays: windowDays,
    windowStart: dates.isEmpty ? LocalDate.from(at) : dates.first,
    expectedCompletions: expected,
    completions: completions,
    adherence: expected <= 0 ? 0 : math.min(completions / expected, 1.0),
    ceilingBinds: windowCeilingBinds(
      windowReps: windowReps,
      targetFrequency: inputs.targetFrequency,
    ),
  );
}

int _rawWindowDays(int windowReps, int targetFrequency) =>
    (windowReps * 7 / targetFrequency).ceil();
