import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/database/store_exceptions.dart';
import 'package:taproot/app/runtime/runtime_providers.dart';
import 'package:taproot/core/engine/engine.dart';
import 'package:taproot/core/engine/inputs.dart';
import 'package:taproot/core/models/completion.dart';
import 'package:taproot/core/models/habit.dart';
import 'package:taproot/core/utils/local_dates.dart';
import 'package:taproot/features/garden/domain/garden_state.dart';
import 'package:taproot/features/habits/domain/completion_repository.dart';
import 'package:taproot/features/habits/domain/completion_retraction.dart';
import 'package:taproot/features/habits/domain/habit_repository.dart';
import 'package:taproot/features/habits/providers/habit_providers.dart';
import 'package:taproot/features/habits/services/habit_inputs_loader.dart';

/// The garden: every habit, and what the engine derives for it.
///
/// The engine is a pure function of history, so nothing here is stored — the
/// controller holds each habit's history and re-runs `evaluateGrowth` against
/// it. That is what lets a watering land in the same frame as the gesture.
final gardenControllerProvider =
    NotifierProvider<GardenController, GardenState>(GardenController.new);

class GardenController extends Notifier<GardenState> {
  late final HabitRepository _habits;
  late final CompletionRepository _completions;
  late final HabitInputsLoader _loader;
  late final DateTime Function() _clock;
  late final String Function() _newId;

  @override
  GardenState build() {
    _habits = ref.read(habitServiceProvider);
    _completions = ref.read(completionServiceProvider);
    _loader = ref.read(habitInputsLoaderProvider);
    _clock = ref.read(clockProvider);
    _newId = ref.read(newIdProvider);

    // Kicked off rather than awaited: `build` is synchronous, and the garden is
    // the first screen, so it renders its loading state and fills in.
    Future<void>.microtask(_load);

    return const GardenState();
  }

  void _log(String action, String message) =>
      dev.log('$action: $message', name: 'GardenController');

  /// Reads every habit and evaluates it.
  ///
  /// Public so the demo seed and, later, habit creation can bring the garden
  /// back in step after writing a habit behind its back.
  Future<void> refresh() => _load();

  Future<void> _load() async {
    try {
      final habits = await _habits.allHabits();
      final at = _clock();

      final plants = <String, PlantState>{};
      final order = <String>[];
      for (final habit in habits) {
        final inputs = await _loader.load(habit.id);
        // Null means the habit was deleted between the list and the load — a
        // race with another device, not a fault. It simply is not in the garden.
        if (inputs == null) continue;
        order.add(habit.id);
        plants[habit.id] = _evaluate(habit: habit, inputs: inputs, at: at);
      }

      if (!ref.mounted) return;
      state = GardenState(plants: plants, order: order, isLoading: false);
    } catch (error, stackTrace) {
      _log('load', 'the garden could not be read: $error');
      dev.log('$stackTrace', name: 'GardenController');
      if (!ref.mounted) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: () => couldNotReadGardenMessage,
      );
    }
  }

  /// Runs the engine and works out whether the last watering is still undoable.
  PlantState _evaluate({
    required Habit habit,
    required HabitInputs inputs,
    required DateTime at,
  }) {
    final growth = evaluateGrowth(inputs: inputs, at: at);
    return PlantState(
      habit: habit,
      inputs: inputs,
      growth: growth,
      undoableCompletion: _lastUndoable(inputs, at),
    );
  }

  Completion? _lastUndoable(HabitInputs inputs, DateTime at) {
    Completion? latest;
    for (final completion in inputs.completions) {
      if (completion.completedAt.isAfter(at)) continue;
      if (!isRetractable(completion, at: at)) continue;
      if (latest == null ||
          completion.completedAt.isAfter(latest.completedAt)) {
        latest = completion;
      }
    }
    return latest;
  }

  /// Replaces one plant, keeping every other [PlantState] and [GardenState.order]
  /// as the same instances so the selector providers do not fire for plants
  /// that did not change.
  void _put(PlantState plant) {
    state = state.copyWith(
      plants: <String, PlantState>{...state.plants, plant.habit.id: plant},
    );
  }

  /// Waters a plant.
  ///
  /// The order is the feature. State changes first, synchronously, and only
  /// then does the write go out — a completion tap must never fail, never spin
  /// and never be lost, and awaiting a database before the plant reacts breaks
  /// the first two of those on a cold page cache.
  ///
  /// Returns the recorded completion so the caller can offer undo on it, or
  /// null when nothing was recorded.
  Future<Completion?> water(String habitId) async {
    final plant = state.plants[habitId];
    if (plant == null) return null;

    final at = _clock();
    final completion = Completion(
      id: _newId(),
      habitId: habitId,
      completedAt: at,
      wasNudged: _wasNudgedToday(plant.inputs, at),
    );

    final watered = _withCompletions(plant, <Completion>[
      ...plant.inputs.completions,
      completion,
    ], at);
    _put(watered);

    try {
      await _completions.recordCompletion(completion);
      return completion;
    } on UnknownHabitException {
      // The habit was deleted on another device. Expected but abnormal — a
      // designed state, deliberately not an error report.
      _log('water', 'habit $habitId is gone; dropping it from the garden');
      if (!ref.mounted) return null;
      _remove(habitId);
      state = state.copyWith(
        errorMessage: () => habitGoneMessage(plant.habit.name),
      );
      return null;
    } catch (error, stackTrace) {
      _log('water', 'the completion could not be stored: $error');
      dev.log('$stackTrace', name: 'GardenController');
      if (!ref.mounted) return null;
      // Put the plant back the way it was. Showing growth that was not stored
      // is worse than showing the failure: the next launch would take it away
      // again with no explanation.
      _put(plant);
      state = state.copyWith(errorMessage: () => couldNotWaterMessage);
      return null;
    }
  }

  /// Undoes a watering — the correction, not the primary defence.
  Future<void> undo(String habitId, String completionId) async {
    final plant = state.plants[habitId];
    if (plant == null) return;

    final at = _clock();
    final remaining = plant.inputs.completions
        .where((completion) => completion.id != completionId)
        .toList();
    if (remaining.length == plant.inputs.completions.length) return;

    _put(_withCompletions(plant, remaining, at));

    try {
      await _completions.retractCompletion(habitId, completionId);
    } on CompletionNotRetractableException {
      if (!ref.mounted) return;
      // Normal: the garden was left open across midnight and the offer went
      // stale. The window closed, so the completion stands.
      _log('undo', 'the window closed on $completionId');
      _put(plant);
      state = state.copyWith(errorMessage: () => undoWindowClosedMessage);
    } on UnknownCompletionException {
      // Already retracted, here or on another device. The optimistic removal
      // was right, so there is nothing to say and nothing to put back.
      _log('undo', '$completionId was already gone');
    } on UnknownHabitException {
      _log('undo', 'habit $habitId is gone; dropping it from the garden');
      if (!ref.mounted) return;
      _remove(habitId);
      state = state.copyWith(
        errorMessage: () => habitGoneMessage(plant.habit.name),
      );
    } catch (error, stackTrace) {
      _log('undo', 'the retraction could not be stored: $error');
      dev.log('$stackTrace', name: 'GardenController');
      if (!ref.mounted) return;
      _put(plant);
      state = state.copyWith(errorMessage: () => couldNotUndoMessage);
    }
  }

  /// Dismisses whatever the last message was, once it has been shown.
  void clearError() {
    if (state.errorMessage == null) return;
    state = state.copyWith(errorMessage: () => null);
  }

  PlantState _withCompletions(
    PlantState plant,
    List<Completion> completions,
    DateTime at,
  ) => _evaluate(
    habit: plant.habit,
    inputs: plant.inputs.copyWith(completions: completions),
    at: at,
  );

  void _remove(String habitId) {
    state = state.copyWith(
      plants: <String, PlantState>{...state.plants}..remove(habitId),
      order: state.order.where((id) => id != habitId).toList(),
    );
  }

  /// Whether a nudge for today's occasion was actually sent.
  ///
  /// Autonomy does not read this — it matches the ledger against completions
  /// itself, so that a completion the user never reported still counts. This
  /// flag is for the reflection layer, which weights an un-nudged completion
  /// differently when it decides what to ask about.
  ///
  /// It is false everywhere today, because nothing writes the ledger until the
  /// notifications branch. That is honest rather than provisional: no nudge was
  /// sent, so none was.
  bool _wasNudgedToday(HabitInputs inputs, DateTime at) {
    final today = LocalDate.from(at);
    return inputs.nudges.any(
      (nudge) =>
          nudge.sent && LocalDate.from(nudge.expectedOccasionAt) == today,
    );
  }
}

/// The app's voice for the states above. Kept out of the widgets so a test can
/// name them without matching a string literal twice.
const String couldNotReadGardenMessage =
    'Your garden could not be read just now. Nothing has been lost — pull down '
    'to try again.';

const String couldNotWaterMessage =
    'That watering could not be saved to this device, so it has been undone. '
    'Try once more.';

const String couldNotUndoMessage =
    'That could not be undone just now. Try once more.';

const String undoWindowClosedMessage =
    'This one can no longer be undone — a watering can only be taken back on '
    'the day it happened.';

String habitGoneMessage(String habitName) =>
    '$habitName was removed on another device, so it is no longer in your '
    'garden.';
