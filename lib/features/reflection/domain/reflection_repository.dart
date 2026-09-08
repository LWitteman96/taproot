import 'package:taproot/core/models/reflection.dart';

/// Reflections — the awareness work that grows roots.
abstract class ReflectionRepository {
  /// Inserts or updates by id.
  ///
  /// Throws [UnknownHabitException] if the habit is unknown or deleted.
  Future<void> saveReflection(Reflection reflection);

  /// Every reflection for the habit, oldest first.
  Future<List<Reflection>> reflectionsFor(String habitId);

  /// The most recent [limit] reflections, returned oldest first.
  ///
  /// Deliberately **unfiltered**. Convergence is measured over the last eight
  /// reflections and *then* narrowed to the cue-bearing ones; filtering here
  /// would hand the engine eight cue-bearing reflections and quietly delete the
  /// "fewer than three ⇒ c = 0" rule.
  Future<List<Reflection>> recentReflections(String habitId, {int limit});
}
