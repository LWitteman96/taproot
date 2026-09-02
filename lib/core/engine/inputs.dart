import 'package:meta/meta.dart';

import 'package:taproot/core/engine/constants.dart';
import 'package:taproot/core/models/completion.dart';
import 'package:taproot/core/models/nudge.dart';
import 'package:taproot/core/models/pause_interval.dart';
import 'package:taproot/core/models/reflection.dart';

/// Everything the engine is allowed to look at for one habit.
///
/// The engine is pure Dart with no Flutter dependency and no I/O: inputs are
/// completions, reflections, nudge records and pauses; outputs are stage,
/// vitality, roots and autonomy.
@immutable
class HabitInputs {
  const HabitInputs({
    required this.habitId,
    required this.targetFrequency,
    required this.createdAt,
    this.completions = const <Completion>[],
    this.reflections = const <Reflection>[],
    this.nudges = const <NudgeRecord>[],
    this.pauses = const <PauseInterval>[],
  }) : assert(
         targetFrequency >= EngineConstants.minimumTargetFrequency &&
             targetFrequency <= EngineConstants.maximumTargetFrequency,
         'targetFrequency is a weekly count in 1..7',
       );

  final String habitId;

  /// f — target frequency in times per week. User-declared at creation; this
  /// is the identity commitment and the engine's anchor.
  ///
  /// Asserted in range because zero is not a graceful failure: the window
  /// arithmetic divides by it, giving `NaN.ceil()` or `Infinity.ceil()` — both
  /// throw — and `paceExemptionThreshold(0)` returns 0, which pins vitality at
  /// 1.0 forever. Better to catch a bad persisted row here than downstream.
  final int targetFrequency;

  final DateTime createdAt;

  final List<Completion> completions;
  final List<Reflection> reflections;
  final List<NudgeRecord> nudges;
  final List<PauseInterval> pauses;

  /// G = 7 / f — the expected gap in days. For f = 3, G = 2.33.
  double get expectedGapDays => 7 / targetFrequency;

  /// Completions at or before [at], oldest first.
  List<Completion> completionsUpTo(DateTime at) {
    final selected =
        completions
            .where((completion) => !completion.completedAt.isAfter(at))
            .toList()
          ..sort((a, b) => a.completedAt.compareTo(b.completedAt));
    return selected;
  }

  /// Reflections at or before [at], oldest first.
  List<Reflection> reflectionsUpTo(DateTime at) {
    final selected =
        reflections
            .where((reflection) => !reflection.createdAt.isAfter(at))
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return selected;
  }

  /// Nudge ledger rows whose expected occasion is at or before [at], oldest
  /// first.
  List<NudgeRecord> nudgesUpTo(DateTime at) {
    final selected =
        nudges.where((nudge) => !nudge.expectedOccasionAt.isAfter(at)).toList()
          ..sort(
            (a, b) => a.expectedOccasionAt.compareTo(b.expectedOccasionAt),
          );
    return selected;
  }

  HabitInputs copyWith({
    String? habitId,
    int? targetFrequency,
    DateTime? createdAt,
    List<Completion>? completions,
    List<Reflection>? reflections,
    List<NudgeRecord>? nudges,
    List<PauseInterval>? pauses,
  }) => HabitInputs(
    habitId: habitId ?? this.habitId,
    targetFrequency: targetFrequency ?? this.targetFrequency,
    createdAt: createdAt ?? this.createdAt,
    completions: completions ?? this.completions,
    reflections: reflections ?? this.reflections,
    nudges: nudges ?? this.nudges,
    pauses: pauses ?? this.pauses,
  );
}
