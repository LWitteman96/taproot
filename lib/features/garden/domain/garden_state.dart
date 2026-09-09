import 'package:meta/meta.dart';

import 'package:taproot/core/engine/engine.dart';
import 'package:taproot/core/engine/inputs.dart';
import 'package:taproot/core/models/completion.dart';
import 'package:taproot/core/models/habit.dart';

/// One plant: the habit, the history the engine is allowed to see, and what the
/// engine made of it.
///
/// [inputs] is held in state rather than re-read per tap on purpose. A watering
/// has to change the plant in the same frame it is performed — no spinner, no
/// await before the payoff — and that is only possible if the engine can be
/// re-run against the history already in memory with the new completion
/// appended. Re-reading four repositories first would put a database round trip
/// between the gesture and the reward it exists to deliver.
@immutable
class PlantState {
  const PlantState({
    required this.habit,
    required this.inputs,
    required this.growth,
    this.undoableCompletion,
  });

  final Habit habit;
  final HabitInputs inputs;
  final HabitGrowth growth;

  /// The most recent completion that could still be undone when this plant was
  /// last evaluated, if any.
  ///
  /// Evaluated rather than live, which means it can go stale across midnight —
  /// a garden left open overnight still offers undo on yesterday's watering.
  /// That is covered rather than ignored: the repository re-judges the window
  /// and throws `CompletionNotRetractableException`, which the controller turns
  /// into a sentence explaining the window closed. The affordance is optimistic;
  /// the boundary is not.
  final Completion? undoableCompletion;

  bool get canUndo => undoableCompletion != null;

  PlantState copyWith({
    Habit? habit,
    HabitInputs? inputs,
    HabitGrowth? growth,
    Completion? Function()? undoableCompletion,
  }) => PlantState(
    habit: habit ?? this.habit,
    inputs: inputs ?? this.inputs,
    growth: growth ?? this.growth,
    undoableCompletion: undoableCompletion != null
        ? undoableCompletion()
        : this.undoableCompletion,
  );

  @override
  String toString() => 'PlantState(${habit.name}, ${growth.stage})';
}

/// The garden.
///
/// [order] is kept as its own list, and kept as the *same* list across a
/// watering, so the selector that drives the garden's children does not see a
/// new value every time one plant changes. Without that, watering one plant
/// rebuilds every plant — which CLAUDE.md calls out as the thing the selector
/// providers exist to prevent.
@immutable
class GardenState {
  const GardenState({
    this.plants = const <String, PlantState>{},
    this.order = const <String>[],
    this.isLoading = true,
    this.errorMessage,
  });

  final Map<String, PlantState> plants;

  /// Habit ids, oldest first.
  final List<String> order;

  /// True only while the first load is in flight. A watering never sets it —
  /// the tap must never spin.
  final bool isLoading;

  /// A sentence for the user about something that did not work. Errors reach
  /// the UI as state rather than as an exception, so no screen has to decide
  /// what a failure means mid-gesture.
  final String? errorMessage;

  bool get isEmpty => order.isEmpty;

  GardenState copyWith({
    Map<String, PlantState>? plants,
    List<String>? order,
    bool? isLoading,
    String? Function()? errorMessage,
  }) => GardenState(
    plants: plants ?? this.plants,
    order: order ?? this.order,
    isLoading: isLoading ?? this.isLoading,
    errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
  );

  @override
  String toString() =>
      'GardenState(${order.length} plants, loading: $isLoading)';
}
