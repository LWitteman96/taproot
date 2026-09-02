import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/habit.dart';

void main() {
  final createdAt = DateTime(2026, 1, 5, 9);

  Habit habit({
    DateTime? pausedAt,
    DateTime? graduatedAt,
    CueType? designedCueType = CueType.event,
  }) => Habit(
    id: 'habit-1',
    name: 'Morning run',
    plantType: 'oak',
    targetFrequency: 3,
    createdAt: createdAt,
    identityStatement: 'I am someone who runs',
    designedCue: 'after breakfast',
    designedCueType: designedCueType,
    routine: 'a 20 minute loop',
    reward: 'coffee on the porch',
    pausedAt: pausedAt,
    graduatedAt: graduatedAt,
  );

  group('json', () {
    test('round-trips every field', () {
      final original = habit(
        pausedAt: DateTime(2026, 2, 1, 8),
        graduatedAt: DateTime(2026, 4, 1, 8),
      );

      final restored = Habit.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.identityStatement, original.identityStatement);
      expect(restored.plantType, original.plantType);
      expect(restored.targetFrequency, original.targetFrequency);
      expect(restored.designedCue, original.designedCue);
      expect(restored.designedCueType, original.designedCueType);
      expect(restored.routine, original.routine);
      expect(restored.reward, original.reward);
      expect(restored.createdAt.isAtSameMomentAs(original.createdAt), isTrue);
      expect(restored.pausedAt!.isAtSameMomentAs(original.pausedAt!), isTrue);
      expect(
        restored.graduatedAt!.isAtSameMomentAs(original.graduatedAt!),
        isTrue,
      );
    });

    test('round-trips the nulls', () {
      final sparse = Habit(
        id: 'habit-2',
        name: 'Read',
        plantType: 'fern',
        targetFrequency: 7,
        createdAt: createdAt,
      );

      final restored = Habit.fromJson(sparse.toJson());

      expect(restored.identityStatement, isNull);
      expect(restored.designedCue, isNull);
      expect(restored.designedCueType, isNull);
      expect(restored.routine, isNull);
      expect(restored.reward, isNull);
      expect(restored.pausedAt, isNull);
      expect(restored.graduatedAt, isNull);
    });

    test('uses the snake_case column names the schema declares', () {
      expect(
        habit().toJson().keys,
        containsAll(<String>[
          'id',
          'name',
          'identity_statement',
          'plant_type',
          'target_frequency',
          'designed_cue',
          'designed_cue_type',
          'routine',
          'reward',
          'created_at',
          'paused_at',
          'graduated_at',
        ]),
      );
    });

    test('carries no derived engine value', () {
      // Stage, vitality, roots and autonomy are derivations, never columns.
      expect(
        habit().toJson().keys,
        isNot(
          anyOf(
            contains('stage'),
            contains('vitality'),
            contains('roots'),
            contains('autonomy'),
          ),
        ),
      );
    });
  });

  group('invariants', () {
    test('isPaused and hasGraduated read off the timestamps', () {
      expect(habit().isPaused, isFalse);
      expect(habit(pausedAt: DateTime(2026, 2, 1)).isPaused, isTrue);
      expect(habit().hasGraduated, isFalse);
      expect(habit(graduatedAt: DateTime(2026, 4, 1)).hasGraduated, isTrue);
    });

    test('the weekly target is held to the range the engine accepts', () {
      // HabitInputs asserts the same bounds. Catching a bad persisted row here
      // means it fails at construction rather than inside the window
      // arithmetic, where f = 0 gives NaN.ceil() and f > 7 is meaningless.
      Habit withFrequency(int frequency) => Habit(
        id: 'habit-1',
        name: 'Run',
        plantType: 'oak',
        targetFrequency: frequency,
        createdAt: createdAt,
      );

      expect(() => withFrequency(0), throwsA(isA<AssertionError>()));
      expect(() => withFrequency(8), throwsA(isA<AssertionError>()));
      expect(() => withFrequency(1), returnsNormally);
      expect(() => withFrequency(7), returnsNormally);
    });

    test('a designed cue may only be an externally schedulable type', () {
      // The engine cannot schedule, nudge, or fairly measure a habit hung on
      // a mood (growth spec §1). Internal cues are still valid as *discovered*
      // cues, which is why the constraint lives on Habit and not on Reflection.
      expect(
        () => habit(designedCueType: CueType.internal),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => habit(designedCueType: CueType.unknown),
        throwsA(isA<AssertionError>()),
      );
      expect(() => habit(designedCueType: null), returnsNormally);
      expect(() => habit(designedCueType: CueType.time), returnsNormally);
    });
  });

  group('copyWith', () {
    test('replaces only what is named', () {
      final renamed = habit().copyWith(name: 'Evening run');

      expect(renamed.name, 'Evening run');
      expect(renamed.targetFrequency, 3);
      expect(renamed.designedCue, 'after breakfast');
    });

    test('distinguishes an unset nullable from one cleared to null', () {
      final paused = habit(pausedAt: DateTime(2026, 2, 1, 8));

      expect(paused.copyWith(name: 'Run').pausedAt, isNotNull);
      expect(paused.copyWith(pausedAt: () => null).pausedAt, isNull);
    });
  });
}
