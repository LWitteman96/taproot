import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:taproot/core/engine/constants.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/habit.dart';
import 'package:taproot/core/models/habit_category.dart';
import 'package:taproot/core/models/habit_journey.dart';
import 'package:taproot/features/habits/domain/habit_repository.dart';
import 'package:taproot/features/habits/providers/habit_providers.dart';

/// The weekly target a habit starts on before the user says otherwise.
///
/// Deliberately **not** in `EngineConstants`. Nothing in the engine reads it —
/// it is the number a form is pre-filled with — and putting it there would mean
/// bumping the engine constants version, and so invalidating every cached
/// derivation, to change a default on a screen.
///
/// It is still a real calibration question rather than an arbitrary pick. `f`
/// anchors every window in the engine, and an over-ambitious default is the
/// front door to the mismatched-target death spiral that renegotiation exists
/// to rescue (growth-engine §7). Three is the spec's own worked example, it is
/// the lowest target that still reads as "a few times a week", and it leaves
/// room to be revised in both directions.
const int defaultTargetFrequency = 3;

/// The screens of the creation flow, in order.
///
/// There is no journey-picker step at the front, and that is the design, not an
/// omission. design-spec §2: Journey B is the default and Journey A is an
/// explicit opt-out, because "an app that offers designing and tracking as
/// equal-weight choices at the front door is a tracker with a designer bolted
/// on". So the flow simply *is* the design flow, and the opt-out is offered at
/// [cue] — the first step that asks the user for something a tracker would not.
enum HabitCreationStep {
  /// What are you growing, and what kind of thing is it.
  name,

  /// Which plant. The quiet identity moment (design-spec §4).
  plant,

  /// How often, and who that makes you.
  rhythm,

  /// The cue. Journey B only.
  cue,

  /// Routine and reward. Journey B only.
  loop,

  /// Read it back, then plant it.
  review;

  /// Whether this step is part of designing the loop, and so skipped by a
  /// habit that is only being tracked.
  bool get designsTheLoop =>
      this == HabitCreationStep.cue || this == HabitCreationStep.loop;
}

/// Everything the creation flow has been told so far.
@immutable
class HabitCreationState {
  const HabitCreationState({
    this.journey = HabitJourney.design,
    this.stepIndex = 0,
    this.name = '',
    this.identityStatement = '',
    this.category,
    this.plantType,
    this.targetFrequency = defaultTargetFrequency,
    this.designedCue = '',
    this.designedCueType,
    this.routine = '',
    this.reward = '',
    this.isSaving = false,
    this.errorMessage,
    this.createdHabitId,
  });

  final HabitJourney journey;

  /// An index into [steps], not into [HabitCreationStep.values] — the two are
  /// different lists for a tracked habit.
  final int stepIndex;

  final String name;
  final String identityStatement;
  final HabitCategory? category;
  final String? plantType;
  final int targetFrequency;
  final String designedCue;
  final CueType? designedCueType;
  final String routine;
  final String reward;

  final bool isSaving;

  /// Set when the save failed. The draft is untouched, so the user can retry
  /// without re-entering anything.
  final String? errorMessage;

  /// Set once the habit is in the store. The page watches this to leave.
  final String? createdHabitId;

  /// The steps this journey actually walks.
  List<HabitCreationStep> get steps => journey.designsTheLoop
      ? HabitCreationStep.values
      : HabitCreationStep.values
            .where((step) => !step.designsTheLoop)
            .toList(growable: false);

  HabitCreationStep get step => steps[stepIndex.clamp(0, steps.length - 1)];

  bool get isFirstStep => stepIndex == 0;

  bool get isLastStep => stepIndex >= steps.length - 1;

  /// Whether [step] has been answered well enough to move on.
  bool get canAdvance => isComplete(step);

  /// Whether every step this journey walks has been answered.
  bool get canSubmit => !isSaving && steps.every(isComplete);

  bool isComplete(HabitCreationStep step) => switch (step) {
    HabitCreationStep.name => name.trim().isNotEmpty,
    HabitCreationStep.plant => plantType != null,
    // The frequency always holds a value, and the identity statement is
    // optional — "I am someone who runs" is an invitation, not a required
    // field.
    HabitCreationStep.rhythm => true,
    HabitCreationStep.cue =>
      designedCue.trim().isNotEmpty && designedCueType != null,
    // design-spec §2: Journey B is writing down the cue, the routine *and* the
    // reward. A design flow that lets two thirds of the loop go blank is the
    // tracker-with-a-designer-bolted-on the spec argues against, and the whole
    // claim is that the full design takes two minutes and pays for months.
    HabitCreationStep.loop =>
      routine.trim().isNotEmpty && reward.trim().isNotEmpty,
    HabitCreationStep.review => true,
  };

  /// The draft as a habit, ready to save.
  ///
  /// [id] is generated by the caller *before* the insert, the same way a
  /// completion's is: it makes multi-device sync a union rather than a merge.
  Habit toHabit({required String id, required DateTime createdAt}) {
    final designing = journey.designsTheLoop;
    return Habit(
      id: id,
      name: name.trim(),
      plantType: plantType!,
      targetFrequency: targetFrequency,
      journey: journey,
      category: category,
      createdAt: createdAt,
      identityStatement: _orNull(identityStatement),
      // A tracked habit has no designed loop by definition — reverse-
      // engineering one through reflection is the point of Journey A. Anything
      // typed before the opt-out is dropped rather than quietly persisted.
      designedCue: designing ? _orNull(designedCue) : null,
      designedCueType: designing ? designedCueType : null,
      routine: designing ? _orNull(routine) : null,
      reward: designing ? _orNull(reward) : null,
    );
  }

  static String? _orNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  HabitCreationState copyWith({
    HabitJourney? journey,
    int? stepIndex,
    String? name,
    String? identityStatement,
    HabitCategory? Function()? category,
    String? Function()? plantType,
    int? targetFrequency,
    String? designedCue,
    CueType? Function()? designedCueType,
    String? routine,
    String? reward,
    bool? isSaving,
    String? Function()? errorMessage,
    String? Function()? createdHabitId,
  }) => HabitCreationState(
    journey: journey ?? this.journey,
    stepIndex: stepIndex ?? this.stepIndex,
    name: name ?? this.name,
    identityStatement: identityStatement ?? this.identityStatement,
    category: category != null ? category() : this.category,
    plantType: plantType != null ? plantType() : this.plantType,
    targetFrequency: targetFrequency ?? this.targetFrequency,
    designedCue: designedCue ?? this.designedCue,
    designedCueType: designedCueType != null
        ? designedCueType()
        : this.designedCueType,
    routine: routine ?? this.routine,
    reward: reward ?? this.reward,
    isSaving: isSaving ?? this.isSaving,
    errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
    createdHabitId: createdHabitId != null
        ? createdHabitId()
        : this.createdHabitId,
  );
}

/// Drives habit creation: holds the draft, validates it a step at a time, and
/// writes it once through [HabitRepository].
class HabitCreationController extends Notifier<HabitCreationState> {
  late final HabitRepository _habits;
  late final String Function() _newHabitId;
  late final DateTime Function() _clock;

  @override
  HabitCreationState build() {
    _habits = ref.read(habitServiceProvider);
    _newHabitId = ref.read(habitIdGeneratorProvider);
    _clock = ref.read(creationClockProvider);
    return const HabitCreationState();
  }

  void nameChanged(String value) => state = state.copyWith(name: value);

  void identityStatementChanged(String value) =>
      state = state.copyWith(identityStatement: value);

  void categoryChosen(HabitCategory? value) =>
      state = state.copyWith(category: () => value);

  void plantChosen(String plantType) =>
      state = state.copyWith(plantType: () => plantType);

  void targetFrequencyChosen(int value) {
    if (value < EngineConstants.minimumTargetFrequency ||
        value > EngineConstants.maximumTargetFrequency) {
      return;
    }
    state = state.copyWith(targetFrequency: value);
  }

  void cueChanged(String value) => state = state.copyWith(designedCue: value);

  /// Sets the designed cue's type.
  ///
  /// Refuses anything the engine cannot schedule against. The `Habit` assert
  /// says the same thing, but an assert is stripped from release builds and
  /// this is reached from a screen.
  void cueTypeChosen(CueType? value) {
    if (value != null && !value.isSchedulable) return;
    state = state.copyWith(designedCueType: () => value);
  }

  void routineChanged(String value) => state = state.copyWith(routine: value);

  void rewardChanged(String value) => state = state.copyWith(reward: value);

  /// Switches between designing the loop and only tracking the habit.
  ///
  /// Opting out jumps to the review rather than dropping the user back into a
  /// flow whose remaining steps no longer exist, and clears anything already
  /// typed into the loop — a tracked habit that silently kept a half-written
  /// cue would be a Journey A habit the engine treats as designed.
  void journeyChosen(HabitJourney journey) {
    if (state.journey == journey) return;

    final switched = switch (journey) {
      HabitJourney.track => state.copyWith(
        journey: journey,
        designedCue: '',
        designedCueType: () => null,
        routine: '',
        reward: '',
      ),
      HabitJourney.design => state.copyWith(journey: journey),
    };

    state = switched.copyWith(
      stepIndex: switched.steps.indexOf(
        journey.designsTheLoop
            ? HabitCreationStep.cue
            : HabitCreationStep.review,
      ),
    );
  }

  /// Moves to the next step, if the current one is answered.
  void next() {
    if (!state.canAdvance || state.isLastStep) return;
    state = state.copyWith(stepIndex: state.stepIndex + 1);
  }

  void back() {
    if (state.isFirstStep) return;
    state = state.copyWith(stepIndex: state.stepIndex - 1);
  }

  /// Writes the habit. Sets `createdHabitId` on success.
  ///
  /// Idempotent against a double tap: a save already in flight, or one that has
  /// already produced a habit, is ignored rather than planting a second plant.
  Future<void> submit() async {
    if (state.isSaving || state.createdHabitId != null) return;
    if (!state.canSubmit) return;

    state = state.copyWith(isSaving: true, errorMessage: () => null);

    final habit = state.toHabit(id: _newHabitId(), createdAt: _clock());

    try {
      await _habits.saveHabit(habit);
      _log('submit', 'planted ${habit.id} (${habit.journey.name})');
      state = state.copyWith(
        isSaving: false,
        createdHabitId: () => habit.id,
      );
    } catch (error, stackTrace) {
      _log('submit', 'failed: $error');
      // A no-op until Sentry is initialised (docs/status.md), which is why the
      // developer log above is not conditional on it.
      await Sentry.captureException(error, stackTrace: stackTrace);
      state = state.copyWith(
        isSaving: false,
        errorMessage: () =>
            'That did not save. Nothing has been lost — try again.',
      );
    }
  }

  void _log(String action, String message) =>
      dev.log(message, name: 'HabitCreationController.$action');
}

final habitCreationControllerProvider = NotifierProvider.autoDispose<
  HabitCreationController,
  HabitCreationState
>(HabitCreationController.new);
