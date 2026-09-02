import 'package:taproot/core/engine/adherence.dart';
import 'package:taproot/core/engine/constants.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/engine/inputs.dart';
import 'package:taproot/core/engine/ladder.dart';
import 'package:taproot/core/engine/pauses.dart';
import 'package:taproot/core/engine/vitality.dart';
import 'package:taproot/core/utils/local_dates.dart';

/// Target renegotiation (growth spec §7).
///
/// The app doesn't let a plant die — it questions the target. Lowering f is an
/// identity update, not a failure, and it rescues the system from the
/// mismatched-target death spiral. The same mechanic runs upward.
enum RenegotiationTrigger {
  /// Adherence < 0.4 across two consecutive windows.
  sustainedLowAdherence,

  /// Fully wilted for 7 consecutive days. This exists because the first
  /// trigger is far too slow: it offers the over-ambitious starter help on day
  /// 28, and he churns around day 10.
  prolongedWilt,

  /// Sustained A = 1.0 with overflow — "you're running 5×, is that who you
  /// are now?"
  sustainedOverperformance,
}

/// Whichever trigger fired first, or null if the habit is fine.
RenegotiationTrigger? renegotiationTrigger({
  required HabitInputs inputs,
  required Stage stage,
  required DateTime at,
}) {
  // Pause already says "not now". Proposing a lower target on top of it
  // punishes exactly the honesty the mechanic exists to protect.
  if (isPausedOn(LocalDate.from(at), inputs.pauses)) return null;

  if (_isProlongedWilt(inputs: inputs, stage: stage, at: at)) {
    return RenegotiationTrigger.prolongedWilt;
  }

  // Measured over the window of the gate the habit is working toward.
  final gate = gateInProgress(stage);
  final current = computeAdherence(
    inputs: inputs,
    windowReps: gate.windowReps,
    at: at,
  );
  final previous = computeAdherence(
    inputs: inputs,
    windowReps: gate.windowReps,
    at: activeDaysBefore(
      at: at,
      activeDays: current.windowDays,
      pauses: inputs.pauses,
    ),
  );

  // The earlier window must lie wholly inside the habit's life. Without this
  // an empty pre-creation window reads as a failing one, and every new habit
  // is flagged on day one.
  final hasTwoWindows = previous.windowStart.isAfter(
    LocalDate.from(inputs.createdAt),
  );
  if (!hasTwoWindows) return null;

  if (current.adherence < EngineConstants.renegotiationAdherence &&
      previous.adherence < EngineConstants.renegotiationAdherence) {
    return RenegotiationTrigger.sustainedLowAdherence;
  }

  if (current.adherence >= 1.0 && previous.adherence >= 1.0) {
    final suggested = suggestedTargetFrequency(inputs: inputs, at: at);
    if (suggested != null && suggested > inputs.targetFrequency) {
      return RenegotiationTrigger.sustainedOverperformance;
    }
  }

  return null;
}

bool isRenegotiationCandidate({
  required HabitInputs inputs,
  required Stage stage,
  required DateTime at,
}) => renegotiationTrigger(inputs: inputs, stage: stage, at: at) != null;

/// The frequency the app should propose, from observed pace. Null when there
/// is nothing to propose.
int? suggestedTargetFrequency({
  required HabitInputs inputs,
  required DateTime at,
}) {
  final dates = activeWindowDates(
    at: at,
    windowDays: _observationDays,
    pauses: inputs.pauses,
  );
  if (dates.isEmpty) return null;
  // Nothing to say before there is a month of the habit's own history.
  if (dates.first.isBefore(LocalDate.from(inputs.createdAt))) return null;

  final window = dates.toSet();
  var completions = 0;
  for (final completion in inputs.completions) {
    if (completion.completedAt.isAfter(at)) continue;
    if (window.contains(LocalDate.from(completion.completedAt))) completions++;
  }

  final weekly = (completions / (_observationDays / 7)).round().clamp(
    _minimumFrequency,
    _maximumFrequency,
  );
  return weekly == inputs.targetFrequency ? null : weekly;
}

/// Fully wilted on each of the last seven active days.
///
/// Read off the *raw* curve: the wilt freeze this trigger switches on would
/// otherwise erase the evidence that switched it on.
bool _isProlongedWilt({
  required HabitInputs inputs,
  required Stage stage,
  required DateTime at,
}) {
  var cursor = at;
  for (
    var sample = 0;
    sample < EngineConstants.renegotiationWiltDays;
    sample++
  ) {
    if (rawVitality(inputs: inputs, stage: stage, at: cursor) > 0) return false;
    cursor = activeDaysBefore(at: cursor, activeDays: 1, pauses: inputs.pauses);
  }
  return true;
}

/// Four weeks is the shortest stretch that reads as a pace rather than a spell.
const int _observationDays = 28;
const int _minimumFrequency = 1;
const int _maximumFrequency = 7;
