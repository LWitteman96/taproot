import 'package:taproot/app/database/store_exceptions.dart';
import 'package:taproot/core/models/completion.dart';
import 'package:taproot/core/models/habit.dart';
import 'package:taproot/core/models/nudge.dart';
import 'package:taproot/core/models/pause_interval.dart';
import 'package:taproot/core/models/reflection.dart';
import 'package:taproot/core/utils/local_dates.dart';
import 'package:taproot/features/habits/domain/completion_repository.dart';
import 'package:taproot/features/habits/domain/completion_retraction.dart';
import 'package:taproot/features/habits/domain/habit_repository.dart';
import 'package:taproot/features/notifications/domain/nudge_repository.dart';
import 'package:taproot/features/reflection/domain/reflection_repository.dart';

import 'store_contract.dart';
import 'store_fixtures.dart';

/// In-memory repositories for tests that need a store but not a database.
///
/// They are run through the same `storeContract` as the SQLite services, so
/// what they do here is what the app does — including the parts that are easy
/// to forget in a fake: soft deletes hide rows, a replayed completion is a
/// no-op rather than an overwrite, and writes against a missing habit throw
/// [UnknownHabitException].

class FakeHabitService implements HabitRepository {
  FakeHabitService({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  final Map<String, Habit> _habits = <String, Habit>{};
  final Set<String> _deleted = <String>{};
  final Map<String, List<PauseInterval>> _pauses =
      <String, List<PauseInterval>>{};

  /// Throws unless the habit is present and not deleted. The child fakes call
  /// this so they reject the same writes the SQLite services reject.
  void requireLive(String habitId) {
    if (!_habits.containsKey(habitId) || _deleted.contains(habitId)) {
      throw UnknownHabitException(habitId);
    }
  }

  bool isLive(String habitId) =>
      _habits.containsKey(habitId) && !_deleted.contains(habitId);

  @override
  Future<List<Habit>> allHabits() async =>
      _habits.values.where((habit) => !_deleted.contains(habit.id)).toList()
        ..sort((a, b) {
          final byCreation = a.createdAt.compareTo(b.createdAt);
          return byCreation != 0 ? byCreation : a.id.compareTo(b.id);
        });

  @override
  Future<Habit?> habitById(String habitId) async =>
      _deleted.contains(habitId) ? null : _habits[habitId];

  @override
  Future<void> saveHabit(Habit habit) async => _habits[habit.id] = habit;

  @override
  Future<void> deleteHabit(String habitId) async {
    if (_habits.containsKey(habitId)) _deleted.add(habitId);
  }

  @override
  Future<void> pauseHabit(String habitId) async {
    requireLive(habitId);
    final intervals = _pauses.putIfAbsent(habitId, () => <PauseInterval>[]);
    if (intervals.any((interval) => interval.isOpen)) return;

    final now = _clock();
    intervals.add(PauseInterval(startedAt: now));
    _habits[habitId] = _habits[habitId]!.copyWith(pausedAt: () => now);
  }

  @override
  Future<void> resumeHabit(String habitId) async {
    requireLive(habitId);
    final intervals = _pauses[habitId] ?? <PauseInterval>[];
    final openIndex = intervals.indexWhere((interval) => interval.isOpen);
    if (openIndex < 0) return;

    final now = _clock();
    intervals[openIndex] = intervals[openIndex].copyWith(endedAt: () => now);
    _habits[habitId] = _habits[habitId]!.copyWith(pausedAt: () => null);
  }

  @override
  Future<List<PauseInterval>> pausesFor(String habitId) async =>
      List<PauseInterval>.of(_pauses[habitId] ?? const <PauseInterval>[])
        ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
}

class FakeCompletionService implements CompletionRepository {
  FakeCompletionService({
    required FakeHabitService habits,
    DateTime Function()? clock,
  }) : _habits = habits,
       _clock = clock ?? DateTime.now;

  final FakeHabitService _habits;
  final DateTime Function() _clock;

  /// Keyed by (habitId, id) — the same union key the schema uses.
  final Map<String, Completion> _completions = <String, Completion>{};

  /// The undo ledger, on the same key. Kept separate from [_completions] for
  /// the same reason the schema keeps it in its own table: retracted wins
  /// regardless of the order the two events are seen in.
  final Set<String> _retracted = <String>{};

  static String _key(Completion completion) =>
      '${completion.habitId}/${completion.id}';

  static String _keyOf(String habitId, String completionId) =>
      '$habitId/$completionId';

  @override
  Future<void> recordCompletion(Completion completion) async {
    _habits.requireLive(completion.habitId);
    // First write wins: a completion is an event that already happened.
    _completions.putIfAbsent(_key(completion), () => completion);
  }

  @override
  Future<void> retractCompletion(String habitId, String completionId) async {
    _habits.requireLive(habitId);
    final key = _keyOf(habitId, completionId);
    // Checked before the window, so idempotence does not expire at midnight.
    if (_retracted.contains(key)) return;

    final completion = _completions[key];
    if (completion == null) {
      throw UnknownCompletionException(habitId, completionId);
    }
    if (!isRetractable(completion, at: _clock())) {
      throw CompletionNotRetractableException(habitId, completionId);
    }
    _retracted.add(key);
  }

  @override
  Future<List<Completion>> completionsFor(String habitId) async =>
      _completions.values
          .where(
            (completion) =>
                completion.habitId == habitId &&
                !_retracted.contains(_key(completion)),
          )
          .toList()
        ..sort((a, b) {
          final byTime = a.completedAt.compareTo(b.completedAt);
          return byTime != 0 ? byTime : a.id.compareTo(b.id);
        });

  @override
  Future<List<Completion>> completionsOnLocalDate(
    String habitId,
    LocalDate date,
  ) async {
    final all = await completionsFor(habitId);
    return all
        .where((completion) => LocalDate.from(completion.completedAt) == date)
        .toList();
  }

  @override
  Future<Completion?> latestCompletion(String habitId) async {
    final all = await completionsFor(habitId);
    return all.isEmpty ? null : all.last;
  }
}

class FakeReflectionService implements ReflectionRepository {
  FakeReflectionService({
    required FakeHabitService habits,
    DateTime Function()? clock,
  }) : _habits = habits;

  final FakeHabitService _habits;
  final Map<String, Reflection> _reflections = <String, Reflection>{};

  @override
  Future<void> saveReflection(Reflection reflection) async {
    _habits.requireLive(reflection.habitId);
    _reflections[reflection.id] = reflection;
  }

  @override
  Future<List<Reflection>> reflectionsFor(String habitId) async =>
      _reflections.values
          .where((reflection) => reflection.habitId == habitId)
          .toList()
        ..sort((a, b) {
          final byTime = a.createdAt.compareTo(b.createdAt);
          return byTime != 0 ? byTime : a.id.compareTo(b.id);
        });

  @override
  Future<List<Reflection>> recentReflections(
    String habitId, {
    int limit = 8,
  }) async {
    final all = await reflectionsFor(habitId);
    // Unfiltered — see the interface. Convergence narrows to cue-bearing
    // reflections *after* the last N are taken.
    return all.length <= limit ? all : all.sublist(all.length - limit);
  }
}

class FakeNudgeService implements NudgeRepository {
  FakeNudgeService({
    required FakeHabitService habits,
    DateTime Function()? clock,
  }) : _habits = habits;

  final FakeHabitService _habits;
  final Map<String, NudgeRecord> _nudges = <String, NudgeRecord>{};

  @override
  Future<void> saveNudge(NudgeRecord nudge) async {
    _habits.requireLive(nudge.habitId);
    _nudges[nudge.id] = nudge;
  }

  @override
  Future<List<NudgeRecord>> nudgesFor(String habitId) async =>
      _nudges.values.where((nudge) => nudge.habitId == habitId).toList()
        ..sort((a, b) {
          final byTime = a.expectedOccasionAt.compareTo(b.expectedOccasionAt);
          return byTime != 0 ? byTime : a.id.compareTo(b.id);
        });

  @override
  Future<void> markSent(String nudgeId) async =>
      _update(nudgeId, (nudge) => nudge.copyWith(sent: true));

  @override
  Future<void> markConfirmed(String nudgeId) async =>
      _update(nudgeId, (nudge) => nudge.copyWith(confirmed: true));

  @override
  Future<void> markDeclined(String nudgeId) async =>
      _update(nudgeId, (nudge) => nudge.copyWith(declined: true));

  void _update(String nudgeId, NudgeRecord Function(NudgeRecord) change) {
    final existing = _nudges[nudgeId];
    if (existing == null) throw UnknownNudgeException(nudgeId);
    _nudges[nudgeId] = change(existing);
  }
}

/// Wires the fakes into the shape `storeContract` expects.
Future<TestStore> openFakeStore(TestClock clock) async {
  final habits = FakeHabitService(clock: clock.call);
  return TestStore(
    habits: habits,
    completions: FakeCompletionService(habits: habits, clock: clock.call),
    reflections: FakeReflectionService(habits: habits, clock: clock.call),
    nudges: FakeNudgeService(habits: habits, clock: clock.call),
    clock: clock,
    dispose: () async {},
  );
}
