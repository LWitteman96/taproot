import 'package:meta/meta.dart';

import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/habit.dart';
import 'package:taproot/features/notifications/domain/expected_occasions.dart';
import 'package:taproot/features/reflection/domain/check_in_question.dart';

/// The text of one evening notification.
@immutable
class EveningCheckIn {
  const EveningCheckIn({
    required this.title,
    required this.body,
    this.confirmLabel = 'Yes',
    this.declineLabel = 'Different day',
  });

  final String title;
  final String body;

  /// The two answers offered on the notification itself. Answerable without
  /// opening the app on both platforms (guide §14) — that is what keeps the
  /// median check-in inside the ~5 seconds reflection spec §0 budgets.
  final String confirmLabel;
  final String declineLabel;

  @override
  String toString() => 'EveningCheckIn($title / $body)';
}

/// The backward-looking half of the evening notification.
///
/// **This is the seam the reflection stage attaches to.** Reflection and the
/// next-day nudge are deliberately *one* notification (reflection spec §1):
/// look back at today, commit to tomorrow. Two notifications would be two
/// interruptions competing for the same evening, and the adjacency is load
/// bearing — you learn what cued you, then you deploy it on tomorrow, and the
/// cue phrase gets rehearsed twice on one screen.
///
/// So the nudge scheduler does not own the reflection question and does not
/// fake one. It asks this, and composes whatever comes back onto the front of
/// the body it was going to send anyway. Until the reflection feature lands,
/// [NoReflectionPrompt] answers null and the notification is the nudge alone.
///
/// The question is composed *at scheduling time*, which is a real constraint
/// on the reflection stage: the priority score, budget and cooldown
/// (reflection spec §2) are evaluated when the notification is queued — up to
/// [EngineConstants.nudgeHorizonDays] before it fires — not when it appears.
/// Re-planning on every launch and after every completion is what keeps that
/// from going stale.
abstract class ReflectionPromptComposer {
  /// The reflection question for [habit] on the evening before [occasion], or
  /// null when nothing clears the threshold — which reflection spec §2 expects
  /// to be the common case, most days, for most habits.
  Future<String?> promptFor({
    required Habit habit,
    required ExpectedOccasion occasion,
    required DateTime deliverAt,
  });
}

/// The stand-in until the reflection feature lands. Never asks anything.
class NoReflectionPrompt implements ReflectionPromptComposer {
  const NoReflectionPrompt();

  @override
  Future<String?> promptFor({
    required Habit habit,
    required ExpectedOccasion occasion,
    required DateTime deliverAt,
  }) async => null;
}

/// Builds the notification for one occasion.
///
/// The forward half **rehearses the designed cue rather than naming the app**
/// — *"tomorrow, after breakfast?"*, not *"don't forget to run"*. That is the
/// single strongest idea in the flow (growth spec §6): every cycle strengthens
/// the breakfast→run association instead of the app→run one. A habit with no
/// designed cue yet gets the plain form; it never gets an invented cue.
EveningCheckIn composeEveningCheckIn({
  required Habit habit,
  required ExpectedOccasion occasion,
  String? reflectionPrompt,
  Framing framing = Framing.discovery,
  DateTime? now,
}) {
  // Composed from the same functions the sheet uses, so the notification and
  // the screen it opens can never ask the same thing two different ways
  // (check-in-design §5). The framing only changes the wording for diagnosis,
  // and the scheduler knows it by the time it queues the notification.
  final forward = commitLine(
    habit: habit,
    framing: framing,
    nextOccasionAt: occasion.date.startOfDay,
    // The notification is composed for the evening *before* the occasion,
    // so that is the 'now' the wording is relative to unless told otherwise.
    now: now ?? occasion.date.addDays(-1).startOfDay,
  );

  return EveningCheckIn(
    title: habit.name,
    body: reflectionPrompt == null ? forward : '$reflectionPrompt\n$forward',
  );
}
