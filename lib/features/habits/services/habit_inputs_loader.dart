import 'package:taproot/core/engine/inputs.dart';
import 'package:taproot/features/habits/domain/completion_repository.dart';
import 'package:taproot/features/habits/domain/habit_repository.dart';
import 'package:taproot/features/notifications/domain/nudge_repository.dart';
import 'package:taproot/features/reflection/domain/reflection_repository.dart';

/// Assembles one habit's [HabitInputs] from the four repositories.
///
/// This is the only seam between the store and the engine. The engine stays
/// pure — no Flutter, no I/O — by taking everything it is allowed to look at as
/// one value, and this is what fills that value in.
///
/// It deliberately loads **whole** histories rather than pre-windowed slices.
/// The windows are the engine's business: the ladder replays a habit's history
/// from the start, and handing it a truncated list would silently change the
/// answer rather than fail.
class HabitInputsLoader {
  const HabitInputsLoader({
    required HabitRepository habits,
    required CompletionRepository completions,
    required ReflectionRepository reflections,
    required NudgeRepository nudges,
  }) : _habits = habits,
       _completions = completions,
       _reflections = reflections,
       _nudges = nudges;

  final HabitRepository _habits;
  final CompletionRepository _completions;
  final ReflectionRepository _reflections;
  final NudgeRepository _nudges;

  /// Null when the habit is unknown or deleted.
  Future<HabitInputs?> load(String habitId) async {
    final habit = await _habits.habitById(habitId);
    if (habit == null) return null;

    final completions = _completions.completionsFor(habitId);
    final reflections = _reflections.reflectionsFor(habitId);
    // Including the occasions the engine stayed silent on — they are
    // autonomy's denominator, not optional bookkeeping.
    final nudges = _nudges.nudgesFor(habitId);
    final pauses = _habits.pausesFor(habitId);

    return HabitInputs(
      habitId: habit.id,
      targetFrequency: habit.targetFrequency,
      createdAt: habit.createdAt,
      completions: await completions,
      reflections: await reflections,
      nudges: await nudges,
      pauses: await pauses,
    );
  }
}
