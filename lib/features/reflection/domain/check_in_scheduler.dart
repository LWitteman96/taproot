import 'package:meta/meta.dart';

import 'package:taproot/core/engine/constants.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/features/reflection/domain/framing_selection.dart';
import 'package:taproot/features/reflection/domain/reflection_priority.dart';

/// What the scheduler needs to know about one habit to score its occasion.
///
/// Assembled by the caller from the repositories — deliberately, so that this
/// whole file stays a pure function of values. **Nothing here may be cached
/// across a check-in session.** Notification answers are written by a
/// background isolate, so a `confirmed` nudge row can appear in the store
/// without the main isolate ever seeing the write; the ledger has to be re-read
/// at the moment of scoring, not remembered from the last time the app looked.
@immutable
class HabitCheckInContext {
  const HabitCheckInContext({
    required this.habitId,
    required this.stage,
    required this.convergence,
    required this.reflectionCount,
    required this.promptsThisWeek,
    this.occasion,
    this.lastPromptedAt,
  });

  final String habitId;
  final Stage stage;

  /// c — the engine's convergence for this habit.
  final double convergence;

  /// How many reflections this habit already has. Raw count.
  final int reflectionCount;

  /// Check-ins already spent on this habit in the last seven local days.
  final int promptsThisWeek;

  /// The occasion worth asking about, if there is one. Null means nothing has
  /// happened for this habit that is worth a question.
  final CheckInOccasion? occasion;

  final DateTime? lastPromptedAt;

  /// Max check-ins a week at this stage — the same fading logic as nudges.
  int get weeklyBudget => EngineConstants.weeklyReflectionBudget[stage]!;

  bool get hasBudgetLeft => promptsThisWeek < weeklyBudget;
}

/// A check-in the app is willing to offer.
@immutable
class CheckInCandidate {
  const CheckInCandidate({
    required this.occasion,
    required this.framing,
    required this.priority,
  });

  final CheckInOccasion occasion;
  final Framing framing;
  final double priority;

  String get habitId => occasion.habitId;

  @override
  String toString() =>
      'CheckInCandidate(${occasion.habitId}, ${framing.name}, '
      '${priority.toStringAsFixed(2)})';
}

/// The one check-in to offer now, or null for the usual answer — nothing.
///
/// Most days there is no check-in at all, and that is the design rather than a
/// failure to find one: over-prompting is what kills the ritual (design-spec
/// §3).
///
/// Three gates, and they are deliberately at different scopes — a reconciliation
/// worth naming, because §1 and §2 state them in different places:
///
/// - **Once a day, app-wide.** §1 gives the app "one consistent conversational
///   slot instead of two competing interruptions", which is a statement about
///   the user's day, not about one plant. Two habits both clearing threshold on
///   the same evening is one check-in, not two.
/// - **The weekly budget is per habit.** §2's table fades it by *stage*, and
///   stage is a property of a habit, so it cannot be anything else.
/// - **The 48h recency penalty is per habit**, and it is a score term rather
///   than a gate: it makes a recently-asked habit lose to a quieter one instead
///   of silencing it outright.
CheckInCandidate? selectCheckIn({
  required List<HabitCheckInContext> habits,
  required DateTime now,
  DateTime? lastCheckInAnywhere,
}) {
  if (lastCheckInAnywhere != null &&
      now.difference(lastCheckInAnywhere) <
          EngineConstants.reflectionCooldown) {
    return null;
  }

  final candidates = <CheckInCandidate>[];
  for (final habit in habits) {
    final occasion = habit.occasion;
    if (occasion == null) continue;
    if (!habit.hasBudgetLeft) continue;

    final priority = reflectionPriority(
      occasion: occasion,
      convergence: habit.convergence,
      reflectionCount: habit.reflectionCount,
      lastPromptedAt: habit.lastPromptedAt,
      now: now,
    );
    if (priority < EngineConstants.reflectionPriorityThreshold) continue;

    candidates.add(
      CheckInCandidate(
        occasion: occasion,
        framing: framingFor(
          occasion: occasion.occasion,
          stage: habit.stage,
          convergence: habit.convergence,
        ),
        priority: priority,
      ),
    );
  }

  if (candidates.isEmpty) return null;

  // Highest priority wins; habit id breaks ties so that the same inputs always
  // produce the same question rather than whichever the store listed first.
  candidates.sort((a, b) {
    final byPriority = b.priority.compareTo(a.priority);
    return byPriority != 0 ? byPriority : a.habitId.compareTo(b.habitId);
  });
  return candidates.first;
}
