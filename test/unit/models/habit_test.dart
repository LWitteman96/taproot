import 'package:flutter_test/flutter_test.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/habit.dart';
import 'package:taproot/core/models/habit_category.dart';
import 'package:taproot/core/models/habit_journey.dart';

void main() {
  final createdAt = DateTime(2026, 1, 5, 9);

  Habit habit({
    DateTime? pausedAt,
    DateTime? graduatedAt,
    CueType? designedCueType = CueType.event,
    HabitJourney journey = HabitJourney.design,
    HabitCategory? category = HabitCategory.exercise,
  }) => Habit(
    id: 'habit-1',
    name: 'Morning run',
    plantType: 'oak',
    targetFrequency: 3,
    journey: journey,
    category: category,
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
      expect(restored.journey, original.journey);
      expect(restored.category, original.category);
      expect(restored.designedCue, original.designedCue);
      expect(restored.designedCueType, original.designedCueType);
      expect(restored.routine, original.routine);
      expect(restored.reward, original.reward);
      expect(restored.createdAt.isAtSameMomentAs(original.createdAt), isTrue);
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
        journey: HabitJourney.track,
        createdAt: createdAt,
      );

      final restored = Habit.fromJson(sparse.toJson());

      expect(restored.identityStatement, isNull);
      expect(restored.category, isNull);
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
          'journey',
          'category',
          'designed_cue',
          'designed_cue_type',
          'routine',
          'reward',
          'created_at',
          'graduated_at',
        ]),
      );
    });

    test('does not serialise pausedAt — the pause ledger owns it', () {
      // toJson is what a write is built from, so emitting paused_at would let
      // a stale habit contradict the ledger. fromJson still reads it, because
      // that is how the repository hands the derived value back.
      final paused = habit(pausedAt: DateTime(2026, 2, 1, 8));

      expect(paused.toJson().keys, isNot(contains('paused_at')));
      expect(
        Habit.fromJson(<String, Object?>{
          ...paused.toJson(),
          'paused_at': DateTime.utc(2026, 2, 1, 7).toIso8601String(),
        }).pausedAt,
        isNotNull,
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
        journey: HabitJourney.track,
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

    test('a designed habit cannot exist without the cue it designed', () {
      // Journey B *is* the act of writing the loop down. A design-journey
      // habit with no cue would be a Journey A habit wearing the wrong label,
      // and every metric that splits the two populations would count it wrong.
      expect(
        () => Habit(
          id: 'habit-1',
          name: 'Run',
          plantType: 'oak',
          targetFrequency: 3,
          journey: HabitJourney.design,
          createdAt: createdAt,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('a tracked habit may be handed a cue it discovered later', () {
      // The asymmetry is the point: reflection can lock in an official cue for
      // a habit that arrived without one (design-spec §3), and that habit is
      // still Journey A. Inferring the route from "has a cue" would lose it.
      final discovered = habit(
        journey: HabitJourney.track,
      ).copyWith(designedCue: () => 'after coffee');

      expect(discovered.journey, HabitJourney.track);
      expect(discovered.hasDesignedLoop, isTrue);
    });
  });

  group('the journey of a row written before the column existed', () {
    Map<String, Object?> rowWithoutJourney({String? designedCue}) {
      final json = habit(journey: HabitJourney.track).toJson()
        ..remove('journey');
      return <String, Object?>{
        ...json,
        'designed_cue': designedCue,
        'designed_cue_type': designedCue == null ? null : CueType.event.name,
      };
    }

    test('falls back to the inference the column replaced', () {
      // The schema-version-2 upgrade backfills exactly this, so in practice
      // the fallback only fires for a row that skipped the migration. It is
      // still the one defensible reading of such a row.
      expect(
        Habit.fromJson(rowWithoutJourney(designedCue: 'after breakfast')).journey,
        HabitJourney.design,
      );
      expect(
        Habit.fromJson(rowWithoutJourney()).journey,
        HabitJourney.track,
      );
    });

    test('an explicit journey always wins over the inference', () {
      final tracked = <String, Object?>{
        ...rowWithoutJourney(designedCue: 'after breakfast'),
        'journey': HabitJourney.track.name,
      };

      expect(Habit.fromJson(tracked).journey, HabitJourney.track);
    });

    test('an unrecognised journey is a FormatException, not a default', () {
      final broken = <String, Object?>{
        ...rowWithoutJourney(),
        'journey': 'improvised',
      };

      expect(() => Habit.fromJson(broken), throwsFormatException);
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

    test('clears the category without clearing anything else', () {
      final uncategorised = habit().copyWith(category: () => null);

      expect(uncategorised.category, isNull);
      expect(uncategorised.journey, HabitJourney.design);
      expect(uncategorised.name, 'Morning run');
    });
  });
}
