import 'package:taproot/core/engine/engine.dart';
import 'package:taproot/core/models/habit.dart';
import 'package:taproot/features/habits/services/habit_inputs_loader.dart';
import 'package:taproot/features/notifications/domain/evening_check_in.dart';
import 'package:taproot/features/notifications/domain/expected_occasions.dart';
import 'package:taproot/features/reflection/domain/check_in_question.dart';
import 'package:taproot/features/reflection/domain/check_in_scheduler.dart';
import 'package:taproot/features/reflection/domain/occasion_detection.dart';

/// The reflection question that rides along on the evening notification.
///
/// **One notification, two halves** (reflection spec §1): look back at today,
/// commit to tomorrow. They are deliberately one message rather than two,
/// because two would be two interruptions competing for the same evening — and
/// because the adjacency is load-bearing: you learn what cued you, then you
/// deploy it on tomorrow, and the cue phrase gets rehearsed twice in one glance.
///
/// This is the half that looks back. It answers the same question the check-in
/// screen answers, through the same functions — `occasionFor`, `selectCheckIn`,
/// `checkInQuestion` — so the notification and the screen cannot ask the same
/// user two different things in two different voices.
///
/// ## The two clocks
///
/// A nudge for the occasion on day D is delivered on the **evening of D − 1**
/// ([nudgeDeliveryTime]), so the question it carries looks back at D − 1, not
/// at D. And it is composed when the notification is queued, which can be up to
/// `nudgeHorizonDays` earlier. So there are two instants in play and they are
/// not interchangeable:
///
/// - **What the app knows** is what it knows *now*. Detection therefore runs at
///   `min(now, deliverAt)` and never later. Running it at a future `deliverAt`
///   would read the ledger's own forward rows — occasions written before they
///   happen — as days the user failed to complete, and compose *"No running on
///   Thursday — what got in the way?"* about a Thursday that has not arrived.
///   That is the whole hazard of composing early, and it is the one thing this
///   file must not do.
/// - **What the sentence says** is read at `deliverAt`, so the wording is
///   composed against that: `checkInQuestion` renders `today` / `yesterday` /
///   a weekday from it, and a question composed this evening for tomorrow
///   evening has to say `yesterday` where the screen would say `today`.
///
/// ## What stops it going stale
///
/// Nothing here, and that is deliberate — staleness is the scheduler's problem
/// to solve, because the scheduler owns the queue. It re-composes a queued
/// notification once its delivery is close enough for the answer to be worth
/// anything (`EngineConstants.nudgeQuestionRefreshWindow`). What this class
/// guarantees is only that the answer is never *invented*: composed early, it
/// speaks from the last day it actually has data for.
class CheckInPromptComposer implements ReflectionPromptComposer {
  const CheckInPromptComposer({
    required HabitInputsLoader loader,
    required DateTime Function() clock,
  }) : _loader = loader,
       _clock = clock;

  final HabitInputsLoader _loader;
  final DateTime Function() _clock;

  @override
  Future<String?> promptFor({
    required Habit habit,
    required ExpectedOccasion occasion,
    required DateTime deliverAt,
  }) async {
    // A paused habit expects nothing and is asked nothing. The scheduler
    // already skips it, so this is the second lock on the same door — but this
    // one is reachable directly, and a diagnosis for a day the user told us
    // about would be the app not listening.
    if (habit.isPaused) return null;

    final now = _clock();
    final asOf = deliverAt.isBefore(now) ? deliverAt : now;

    final inputs = await _loader.loadFor(habit);
    final reflections = inputs.reflections;
    final growth = evaluateGrowth(inputs: inputs, at: asOf);

    DateTime? lastPromptedAt;
    for (final reflection in reflections) {
      if (lastPromptedAt == null ||
          reflection.createdAt.isAfter(lastPromptedAt)) {
        lastPromptedAt = reflection.createdAt;
      }
    }

    final candidate = selectCheckIn(
      habits: <HabitCheckInContext>[
        HabitCheckInContext(
          habitId: habit.id,
          stage: growth.stage,
          convergence: growth.roots.convergence,
          reflectionCount: reflections.length,
          // The budget is spent by the evening this arrives, not by the
          // evening it was composed on — a question queued on Monday for
          // Thursday is Thursday's spend. Counting at `deliverAt` is what lets
          // the weekly budget mean the same thing in both places.
          promptsThisWeek: promptsInTheLastWeek(
            reflections: reflections,
            at: deliverAt,
          ),
          occasion: occasionFor(
            habitId: habit.id,
            completions: inputs.completions,
            nudges: inputs.nudgesUpTo(asOf),
            reflections: reflections,
            targetFrequency: habit.targetFrequency,
            at: asOf,
          ),
          lastPromptedAt: lastPromptedAt,
        ),
      ],
      now: deliverAt,
      // The app-wide daily gate, read at the evening the question arrives. A
      // reflection *already written* within 24 hours of that evening is the
      // only part of it knowable in advance; a second habit's question landing
      // the same evening is the pass's business, not this function's, because
      // only the pass can see the other habits. `NudgeScheduler` holds that
      // rule.
      lastCheckInAnywhere: lastPromptedAt,
    );
    if (candidate == null) return null;

    return checkInQuestion(
      framing: candidate.framing,
      habit: habit,
      occasionAt: candidate.occasion.at,
      now: deliverAt,
    );
  }
}
