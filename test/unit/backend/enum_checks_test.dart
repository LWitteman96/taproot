import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/completion.dart';
import 'package:taproot/core/models/habit_journey.dart';

/// The gate on the one piece of drift no other gate can see.
///
/// The server mirrors several Dart enums as `CHECK (col in (...))` lists, and
/// the two can fall out of step in a way every existing gate calls green:
///
/// - The Supabase workflow is path-filtered to `supabase/**`, so a commit that
///   only adds an enum value under `lib/` never runs it.
/// - `supabase db reset` and CI both rebuild from scratch, so even when it does
///   run, an edited CHECK inside `create table if not exists` looks applied.
///
/// The drift therefore surfaces for the first time as a 23514 on the first sync
/// push carrying the new value, in the one environment nobody can reset. This
/// test runs in the Flutter suite, which is not path-filtered, and fails the
/// moment the lists disagree.
///
/// Widening for real is a **new migration** (`ALTER TABLE ... DROP CONSTRAINT
/// IF EXISTS ... / ADD CONSTRAINT ...`), which is why this reads every
/// migration in order and takes the *last* definition of each constraint — the
/// same thing Postgres ends up with.
void main() {
  group('enum CHECK constraints mirror their Dart enums', () {
    late Map<String, Set<String>> checks;

    setUpAll(() {
      checks = _constraintValues(_migrationSql());
    });

    /// Every constraint whose list is exactly one enum's `name`s.
    const Map<String, List<Enum>> exact = <String, List<Enum>>{
      'completions_source_known': CompletionSource.values,
      'habits_journey_known': HabitJourney.values,
      'reflections_occasion_known': Occasion.values,
      'reflections_framing_known': Framing.values,
      'reflections_input_mode_known': InputMode.values,
      'reflections_cue_type_known': CueType.values,
      'reflections_friction_type_known': FrictionType.values,
    };

    for (final entry in exact.entries) {
      test(entry.key, () {
        final expected = entry.value.map((value) => value.name).toSet();
        expect(
          checks[entry.key],
          isNotNull,
          reason:
              '${entry.key} is not in any migration. If it was renamed, rename '
              'it here too; if it was dropped, drop this expectation.',
        );
        expect(
          checks[entry.key],
          expected,
          reason:
              'The ${entry.key} CHECK and its Dart enum have drifted. Widening '
              'needs a NEW migration (ALTER TABLE ... DROP CONSTRAINT IF '
              'EXISTS / ADD CONSTRAINT) — editing the create-table list alone '
              'does nothing to a database that has already run it.',
        );
      });
    }

    test('every enum-shaped CHECK in the migrations is guarded here', () {
      // The reverse direction, and the half a hand-maintained map cannot give
      // you on its own: the checks above only cover constraints someone
      // remembered to list. A new enum-mirroring column added to the schema
      // with no entry here is invisible to them — it drifts from its Dart enum
      // exactly as freely as if this file did not exist.
      //
      // So: anything the parser recognises as `check (col in (...))` must be
      // accounted for. Constraints that are not enum-shaped — a range like
      // `target_frequency between 1 and 7` — do not match the pattern and are
      // not this gate's business.
      //
      // `habits.category` is deliberately absent from the schema rather than
      // from this map. It carries no CHECK on either side, because its set
      // widens with the starter chip library and the device reads it leniently,
      // so there is nothing here for this assertion to find. That is the
      // intended outcome, not a gap.
      final Set<String> guarded = <String>{
        ...exact.keys,
        'habits_designed_cue_type_schedulable',
      };

      expect(
        checks.keys.toSet().difference(guarded),
        isEmpty,
        reason:
            'An enum-shaped CHECK exists in the migrations with nothing '
            'comparing it to a Dart enum. Add it to this test — to `exact` if '
            'its list is exactly one enum, or to `guarded` with its own '
            'assertion if it is a deliberate subset.',
      );
    });

    test('habits_designed_cue_type_schedulable', () {
      // Deliberately a subset, not the whole enum: a designed cue the engine
      // cannot schedule, nudge or fairly measure is not admissible, so
      // `internal` and `unknown` are excluded by CueType.isSchedulable.
      final expected = CueType.values
          .where((type) => type.isSchedulable)
          .map((type) => type.name)
          .toSet();
      expect(checks['habits_designed_cue_type_schedulable'], expected);
    });
  });
}

/// Every migration, oldest first, concatenated — so a later `ALTER TABLE`
/// widening wins over the original `create table` list, as it does in Postgres.
String _migrationSql() {
  final directory = Directory('supabase/migrations');
  expect(
    directory.existsSync(),
    isTrue,
    reason:
        'supabase/migrations is missing. This test is the drift gate between '
        'the Dart enums and the server CHECK lists; it cannot run without it.',
  );

  final files =
      directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.sql'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  return files.map((file) => file.readAsStringSync()).join('\n');
}

/// Pulls `constraint <name> ... check (<column> in ('a', 'b'))` out of [sql].
///
/// Later definitions overwrite earlier ones, which is what makes a widening
/// migration count.
Map<String, Set<String>> _constraintValues(String sql) {
  final pattern = RegExp(
    r"constraint\s+(\w+)\s+check\s*\(\s*\w+\s+in\s*\(([^)]*)\)",
    caseSensitive: false,
    multiLine: true,
  );

  final values = <String, Set<String>>{};
  for (final match in pattern.allMatches(sql)) {
    values[match.group(1)!] = match
        .group(2)!
        .split(',')
        .map((value) => value.trim().replaceAll("'", ''))
        .where((value) => value.isNotEmpty)
        .toSet();
  }
  return values;
}
