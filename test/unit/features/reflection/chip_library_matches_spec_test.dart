import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/habit_category.dart';
import 'package:taproot/features/reflection/domain/daypart.dart';
import 'package:taproot/features/reflection/domain/starter_chip.dart';
import 'package:taproot/features/reflection/domain/starter_chip_library.dart';

/// The gate on the one piece of drift no other test can see.
///
/// `starter_chip_library.dart` is 238 rows of **hand-transcribed** content —
/// every label, type, daypart set, prior and family copied out of
/// starter-chip-library.md §6 and §7. Every other test here checks the *rule*
/// that ranks them (the 24 worked examples) or a structural property of the set
/// (twelve per category, four cue types covered, `forgot` and `motivation`
/// always reachable). None of them would notice a mistyped prior, a daypart
/// dropped from a set, or a missing ⚑.
///
/// So this parses the spec at test time and asserts the two agree, in both
/// directions: edit the document without the code, or the code without the
/// document, and the suite says so. Same species as
/// `test/unit/backend/enum_checks_test.dart` — parse the authoritative
/// artifact, assert no drift — and the same trade accepted there: a test
/// coupled to an authored file's format is worth it when the artifact is large,
/// hand-copied, and unverifiable by any other means.
///
/// **The parser is strict on purpose.** A lenient one that skipped rows it
/// could not read would rot into checking fewer chips than it claims while
/// staying green, which is worse than not having the test. Anything
/// unparseable throws, and the row counts are asserted so that a silently
/// dropped row is itself a failure.
void main() {
  /// What the document says a chip is.
  late Map<HabitCategory?, List<StarterChip>> specCues;
  late Map<HabitCategory, List<FrictionChip>> specFrictions;

  setUpAll(() {
    final spec = _readSpec();
    specCues = spec.cues;
    specFrictions = spec.frictions;
  });

  test('the parser read the whole library, not part of it', () {
    // 144 category chips plus the 9 global ones. If the document grows, this
    // number moves with it — deliberately, so that adding chips to the spec
    // without adding them to the code fails here.
    final cueCount = specCues.values.fold(0, (sum, list) => sum + list.length);
    final frictionCount = specFrictions.values.fold(
      0,
      (sum, list) => sum + list.length,
    );

    expect(
      cueCount,
      153,
      reason:
          'Parsed $cueCount cue chips from the spec, expected 153. Either the '
          'document changed or the parser silently skipped a row.',
    );
    expect(frictionCount, 94, reason: 'Parsed $frictionCount friction chips.');
    expect(specCues.keys.whereType<HabitCategory>(), hasLength(12));
  });

  group('every authored cue chip matches the spec', () {
    for (final category in <HabitCategory?>[null, ...HabitCategory.values]) {
      test(category?.name ?? 'the global pool', () {
        final fromSpec = specCues[category];
        expect(
          fromSpec,
          isNotNull,
          reason:
              'No section in the spec for ${category?.name ?? "the global pool"}.',
        );

        final fromCode = category == null
            ? globalCueChips
            : starterChipLibrary[category]!.cues;

        expect(
          fromCode.map(_describe).toSet(),
          fromSpec!.map(_describe).toSet(),
          reason:
              'The authored library and starter-chip-library.md disagree for '
              '${category?.name ?? "the global pool"}. Whichever is right, the '
              'other has to move — this data is copied by hand and nothing '
              'else checks it.',
        );
      });
    }
  });

  group('every authored friction chip matches the spec', () {
    for (final category in HabitCategory.values) {
      test(category.name, () {
        expect(
          starterChipLibrary[category]!.frictions
              .map((chip) => '${chip.label}|${chip.frictionType.name}')
              .toSet(),
          specFrictions[category]!
              .map((chip) => '${chip.label}|${chip.frictionType.name}')
              .toSet(),
          reason: 'Friction chips disagree for ${category.name}.',
        );
      });
    }
  });
}

/// Every field, in one comparable string, so a mismatch names what differs.
String _describe(StarterChip chip) {
  final dayparts = (chip.dayparts.map((part) => part.name).toList()..sort())
      .join('·');
  return '${chip.label} | ${chip.cueType.name} | '
      '${dayparts.isEmpty ? "any" : dayparts} | '
      '${chip.prior.toStringAsFixed(2)} | ${chip.family}'
      '${chip.strict ? " | strict" : ""}'
      '${chip.conditional ? " | conditional" : ""}';
}

typedef _Spec = ({
  Map<HabitCategory?, List<StarterChip>> cues,
  Map<HabitCategory, List<FrictionChip>> frictions,
});

/// Which `### ` heading holds which category. The global pool keys on null,
/// the same way `Habit.category` does.
const Map<String, HabitCategory?> _sections = <String, HabitCategory?>{
  '6.1 Global cue chips (backfill for any category)': null,
  '7.1 Exercise': HabitCategory.exercise,
  '7.2 Meditation': HabitCategory.meditation,
  '7.3 Reading': HabitCategory.reading,
  '7.4 Journaling': HabitCategory.journaling,
  '7.5 Hydration': HabitCategory.hydration,
  '7.6 Tidying': HabitCategory.tidying,
  '7.7 Language practice': HabitCategory.languagePractice,
  '7.8 Instrument': HabitCategory.instrument,
  '7.9 Stretching': HabitCategory.stretching,
  '7.10 Supplements': HabitCategory.supplements,
  '7.11 Walking': HabitCategory.walking,
  '7.12 Sleep routine': HabitCategory.sleepRoutine,
};

_Spec _readSpec() {
  final file = File('docs/starter-chip-library.md');
  if (!file.existsSync()) {
    throw StateError(
      'docs/starter-chip-library.md is missing. This test reads the spec as '
      'its source of truth; without it there is nothing to compare against.',
    );
  }

  final cues = <HabitCategory?, List<StarterChip>>{};
  final frictions = <HabitCategory, List<FrictionChip>>{};

  for (final block in file.readAsStringSync().split('\n### ').skip(1)) {
    final lines = block.split('\n');
    final heading = lines.first.trim();
    if (!_sections.containsKey(heading)) continue;
    final category = _sections[heading];

    // Splitting on `### ` does not stop at a heading of a *different* level, so
    // the last section would otherwise run on into §8 and try to read its
    // coverage-summary table as friction chips. Found by the strictness below
    // rather than by a silent skip, which is the argument for it.
    final body = <String>[];
    for (final line in lines.skip(1)) {
      if (RegExp(r'^#{1,6} ').hasMatch(line)) break;
      body.add(line);
    }

    for (final line in body) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('|') || !trimmed.endsWith('|')) continue;

      final cells = trimmed
          .substring(1, trimmed.length - 1)
          .split('|')
          .map((cell) => cell.trim())
          .toList();

      // Header and separator rows.
      if (cells.first == 'Chip' || cells.first.startsWith('---')) continue;

      switch (cells.length) {
        case 5:
          cues
              .putIfAbsent(category, () => <StarterChip>[])
              .add(_parseCue(cells, heading));
        case 2:
          if (category == null) {
            throw StateError('Unexpected two-column row in $heading: $trimmed');
          }
          frictions
              .putIfAbsent(category, () => <FrictionChip>[])
              .add(_parseFriction(cells, heading));
        default:
          throw StateError(
            'Could not read a ${cells.length}-column row in $heading: $trimmed',
          );
      }
    }
  }

  return (cues: cues, frictions: frictions);
}

StarterChip _parseCue(List<String> cells, String heading) {
  var label = cells[0];
  // Ⓢ marks a strict daypart, ⚑ marks a conditional chip.
  final strict = label.contains('Ⓢ');
  final conditional = label.contains('⚑');
  label = label.replaceAll('Ⓢ', '').replaceAll('⚑', '').trim();

  final cueType = CueType.values
      .where((value) => value.name == cells[1])
      .firstOrNull;
  if (cueType == null) {
    throw StateError('Unknown cue type "${cells[1]}" in $heading: $label');
  }

  final dayparts = <Daypart>{};
  if (cells[2] != 'any') {
    for (final name in cells[2].split('·').map((part) => part.trim())) {
      final daypart = Daypart.values
          .where((value) => value.name == name)
          .firstOrNull;
      if (daypart == null) {
        throw StateError('Unknown daypart "$name" in $heading: $label');
      }
      dayparts.add(daypart);
    }
  }

  final prior = double.tryParse(cells[3]);
  if (prior == null) {
    throw StateError('Unreadable prior "${cells[3]}" in $heading: $label');
  }
  if (cells[4].isEmpty) {
    throw StateError('Missing family in $heading: $label');
  }

  return StarterChip(
    label,
    cueType,
    prior,
    cells[4],
    dayparts: dayparts,
    strict: strict,
    conditional: conditional,
  );
}

FrictionChip _parseFriction(List<String> cells, String heading) {
  final frictionType = FrictionType.values
      .where((value) => value.name == cells[1])
      .firstOrNull;
  if (frictionType == null) {
    throw StateError(
      'Unknown friction type "${cells[1]}" in $heading: ${cells[0]}',
    );
  }
  return FrictionChip(cells[0], frictionType);
}
