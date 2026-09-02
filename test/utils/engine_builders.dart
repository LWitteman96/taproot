import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/engine/inputs.dart';
import 'package:taproot/core/models/completion.dart';
import 'package:taproot/core/models/nudge.dart';
import 'package:taproot/core/models/pause_interval.dart';
import 'package:taproot/core/models/reflection.dart';

/// Fixture builders for engine tests.
///
/// Every fixture is expressed in *days since the habit was created*, because
/// every number in the specs is. [day] converts.
const String testHabitId = 'habit-1';

/// The habit's creation instant. A fixed local wall-clock time, mid-morning,
/// far from a midnight boundary so a fixture that adds fractional days doesn't
/// silently cross a local date.
final DateTime habitCreatedAt = DateTime(2026, 1, 5, 9);

/// [days] after creation, on the local clock. Fractional days are allowed —
/// the droop curve is continuous.
DateTime day(num days) => habitCreatedAt.add(
  Duration(milliseconds: (days * Duration.millisecondsPerDay).round()),
);

int _sequence = 0;

String _nextId(String prefix) => '$prefix-${_sequence++}';

/// Resets id generation so failure messages stay readable across tests.
void resetFixtureIds() => _sequence = 0;

Completion completionOn(num days, {bool wasNudged = false}) => Completion(
  id: _nextId('completion'),
  habitId: testHabitId,
  completedAt: day(days),
  wasNudged: wasNudged,
);

List<Completion> completionsOn(Iterable<num> days, {bool wasNudged = false}) =>
    days.map((d) => completionOn(d, wasNudged: wasNudged)).toList();

/// [count] completions spaced [every] days apart, starting at [from].
List<Completion> completionsEvery({
  required num every,
  required int count,
  num from = 0,
  bool wasNudged = false,
}) => List<Completion>.generate(
  count,
  (index) => completionOn(from + index * every, wasNudged: wasNudged),
);

/// Completions on the given weekdays-of-the-cycle, repeated for [weeks].
///
/// `offsetsInWeek: [0, 2, 4]` with `weeks: 3` gives a steady 3×/week history.
List<Completion> completionsWeekly({
  required List<num> offsetsInWeek,
  required int weeks,
  num from = 0,
  bool wasNudged = false,
}) => <Completion>[
  for (var week = 0; week < weeks; week++)
    for (final offset in offsetsInWeek)
      completionOn(from + week * 7 + offset, wasNudged: wasNudged),
];

Reflection reflectionOn(
  num days, {
  Framing framing = Framing.discovery,
  InputMode inputMode = InputMode.chip,
  String? cueReported = 'after breakfast',
  CueType cueType = CueType.event,
  bool? matchedDesignedCue,
  Occasion occasion = Occasion.completion,
  FrictionType? frictionType,
  bool wasNudged = false,
}) => Reflection(
  id: _nextId('reflection'),
  habitId: testHabitId,
  createdAt: day(days),
  occasion: occasion,
  framing: framing,
  inputMode: inputMode,
  cueReported:
      inputMode == InputMode.cantRemember || inputMode == InputMode.skipped
      ? null
      : cueReported,
  cueType: inputMode == InputMode.cantRemember || inputMode == InputMode.skipped
      ? CueType.unknown
      : cueType,
  matchedDesignedCue: matchedDesignedCue,
  frictionType: frictionType,
  wasNudged: wasNudged,
);

/// [count] reflections, one per day, starting at [from].
List<Reflection> reflectionsDaily({
  required int count,
  num from = 0,
  num every = 1,
  Framing framing = Framing.discovery,
  InputMode inputMode = InputMode.chip,
  String? cueReported = 'after breakfast',
  CueType cueType = CueType.event,
  bool? matchedDesignedCue,
}) => List<Reflection>.generate(
  count,
  (index) => reflectionOn(
    from + index * every,
    framing: framing,
    inputMode: inputMode,
    cueReported: cueReported,
    cueType: cueType,
    matchedDesignedCue: matchedDesignedCue,
  ),
);

NudgeRecord nudgeOn(num days, {required bool sent}) => NudgeRecord(
  id: _nextId('nudge'),
  habitId: testHabitId,
  expectedOccasionAt: day(days),
  sent: sent,
);

List<NudgeRecord> nudgesOn(Iterable<num> days, {required bool sent}) =>
    days.map((d) => nudgeOn(d, sent: sent)).toList();

PauseInterval pauseFrom(num startDay, {num? endDay}) => PauseInterval(
  startedAt: day(startDay),
  endedAt: endDay == null ? null : day(endDay),
);

HabitInputs inputs({
  int targetFrequency = 3,
  List<Completion> completions = const <Completion>[],
  List<Reflection> reflections = const <Reflection>[],
  List<NudgeRecord> nudges = const <NudgeRecord>[],
  List<PauseInterval> pauses = const <PauseInterval>[],
}) => HabitInputs(
  habitId: testHabitId,
  targetFrequency: targetFrequency,
  createdAt: habitCreatedAt,
  completions: completions,
  reflections: reflections,
  nudges: nudges,
  pauses: pauses,
);
