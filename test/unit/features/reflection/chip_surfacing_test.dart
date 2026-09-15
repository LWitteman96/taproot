import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/habit_category.dart';
import 'package:taproot/features/reflection/domain/chip_surfacing.dart';
import 'package:taproot/features/reflection/domain/daypart.dart';
import 'package:taproot/features/reflection/domain/starter_chip.dart';
import 'package:taproot/features/reflection/domain/starter_chip_library.dart';

/// What the 24 worked examples do not reach: the bucket boundaries, the
/// filters' individual behaviour, and the properties the rule has to hold for
/// every category at every hour.
void main() {
  group('dayparts', () {
    test('the boundaries fall where §4 puts them', () {
      expect(daypartFor(DateTime(2026, 3, 2, 3, 59)), Daypart.night);
      expect(daypartFor(DateTime(2026, 3, 2, 4)), Daypart.early);
      expect(daypartFor(DateTime(2026, 3, 2, 7, 59)), Daypart.early);
      expect(daypartFor(DateTime(2026, 3, 2, 8)), Daypart.morning);
      expect(daypartFor(DateTime(2026, 3, 2, 10, 59)), Daypart.morning);
      expect(daypartFor(DateTime(2026, 3, 2, 11)), Daypart.midday);
      expect(daypartFor(DateTime(2026, 3, 2, 13, 59)), Daypart.midday);
      expect(daypartFor(DateTime(2026, 3, 2, 14)), Daypart.afternoon);
      expect(daypartFor(DateTime(2026, 3, 2, 17, 59)), Daypart.afternoon);
      expect(daypartFor(DateTime(2026, 3, 2, 18)), Daypart.evening);
      expect(daypartFor(DateTime(2026, 3, 2, 21, 29)), Daypart.evening);
      expect(daypartFor(DateTime(2026, 3, 2, 21, 30)), Daypart.night);
      expect(daypartFor(DateTime(2026, 3, 2, 0, 30)), Daypart.night);
    });

    test('adjacency is linear and does not wrap', () {
      // The wrap is tempting — 02:00 and 05:00 really are neighbours — but the
      // night bucket spans 6.5 hours and wrapping mostly leaked morning cues
      // into 21:50 sets.
      expect(Daypart.night.isAdjacentTo(Daypart.evening), isTrue);
      expect(Daypart.night.isAdjacentTo(Daypart.early), isFalse);
      expect(Daypart.early.isAdjacentTo(Daypart.night), isFalse);
      expect(Daypart.early.isAdjacentTo(Daypart.morning), isTrue);
      expect(Daypart.early.isAdjacentTo(Daypart.midday), isFalse);
    });

    test('a daypart is not adjacent to itself', () {
      expect(Daypart.midday.isAdjacentTo(Daypart.midday), isFalse);
    });

    test('a mismatched daypart zeroes the prior, leaving only the bonus', () {
      // This is what makes mismatched chips self-eliminate: the type bonus is
      // at most 0.30 and the floor is 0.35, so no special rule is needed.
      const strandedInTheEvening = StarterChip(
        'after dinner',
        CueType.event,
        0.90,
        'dinner',
        dayparts: <Daypart>{Daypart.evening},
      );

      expect(
        scoreChip(chip: strandedInTheEvening, logged: Daypart.early),
        closeTo(0.30, 1e-9),
      );
    });
  });

  group('the hard filters', () {
    test('a conditional chip stays out until it is unlocked', () {
      // `the dog needed out` is an excellent cue for the people it fits and a
      // small insult to everyone else.
      final locked = surfaceStarterChips(
        category: HabitCategory.walking,
        logged: Daypart.afternoon,
      );
      expect(locked.labels, isNot(contains('the dog needed out')));

      final unlocked = surfaceStarterChips(
        category: HabitCategory.walking,
        logged: Daypart.afternoon,
        unlockedConditionalFamilies: const <String>{'dog'},
      );
      expect(unlocked.labels, contains('the dog needed out'));
    });

    test('a strict chip is dropped outright on a daypart miss', () {
      // `got into bed` must never appear against an 07:10 completion, whatever
      // adjacency would give it. Its neighbour `before bed` is not strict, so
      // this is not just the floor doing the work.
      final morning = surfaceStarterChips(
        category: HabitCategory.reading,
        logged: Daypart.evening,
      );

      expect(morning.labels, isNot(contains('got into bed')));
    });

    test('the designed cue family is left out, and only that family', () {
      final surfaced = surfaceStarterChips(
        category: HabitCategory.exercise,
        logged: Daypart.early,
        designedCueFamily: 'gear',
      );

      expect(surfaced.labels, isNot(contains('put my shoes on')));
      expect(surfaced.labels, isNot(contains('changed into my kit')));
      expect(surfaced.labels, contains('after coffee'));
    });
  });

  group('the guards', () {
    test('at most one chip per family, ever', () {
      for (final category in HabitCategory.values) {
        for (final logged in Daypart.values) {
          final surfaced = surfaceStarterChips(
            category: category,
            logged: logged,
          );
          final families = surfaced.chips
              .map((scored) => scored.chip.family)
              .toList();

          expect(
            families.toSet(),
            hasLength(families.length),
            reason: '${category.name} at ${logged.name}: $families',
          );
        }
      }
    });

    test('never more than three chips of one cue type, unless relaxed', () {
      // The ceiling is the second thing §5.3 gives up, after the global
      // backfill — so it may be exceeded, but only when lifting it is what
      // stopped the set being short.
      for (final category in HabitCategory.values) {
        for (final logged in Daypart.values) {
          final surfaced = surfaceStarterChips(
            category: category,
            logged: logged,
          );
          if (surfaced.relaxedTypeCeiling) continue;

          final counts = <CueType, int>{};
          for (final scored in surfaced.chips) {
            counts.update(
              scored.chip.cueType,
              (count) => count + 1,
              ifAbsent: () => 1,
            );
          }

          for (final entry in counts.entries) {
            expect(
              entry.value,
              lessThanOrEqualTo(3),
              reason: '${category.name} at ${logged.name}: ${entry.key.name}',
            );
          }
        }
      }
    });

    test('a lifted ceiling is only ever reported when it was lifted', () {
      // Lifting a guard for nothing is worse than a short set, so the flag has
      // to mean something: a relaxed set must actually exceed the ceiling
      // somewhere. Without this the flag could be set on a set the ceiling
      // never bound, and the ceiling assertion above would skip a case it
      // should have checked.
      var everRelaxed = false;
      for (final category in HabitCategory.values) {
        for (final logged in Daypart.values) {
          final surfaced = surfaceStarterChips(
            category: category,
            logged: logged,
          );
          if (!surfaced.relaxedTypeCeiling) continue;
          everRelaxed = true;

          final counts = <CueType, int>{};
          for (final scored in surfaced.chips) {
            counts.update(
              scored.chip.cueType,
              (count) => count + 1,
              ifAbsent: () => 1,
            );
          }

          expect(
            counts.values.any((count) => count > 3),
            isTrue,
            reason:
                '${category.name} at ${logged.name} reported a relaxed '
                'ceiling but stayed within it: ${surfaced.labels}',
          );
        }
      }

      // And the relaxation path is reached at all — otherwise the assertion
      // above is an empty loop dressed up as a test.
      expect(everRelaxed, isTrue);
    });

    test('a set is never padded past what it was asked for', () {
      for (final category in HabitCategory.values) {
        for (final logged in Daypart.values) {
          expect(
            surfaceStarterChips(category: category, logged: logged),
            hasLength(lessThanOrEqualTo(5)),
          );
          expect(
            surfaceStarterChips(
              category: category,
              logged: logged,
              designedCueFamily: 'nothing-matches-this',
            ),
            hasLength(lessThanOrEqualTo(4)),
          );
        }
      }
    });

    test('nothing below the score floor is ever offered', () {
      for (final category in HabitCategory.values) {
        for (final logged in Daypart.values) {
          final surfaced = surfaceStarterChips(
            category: category,
            logged: logged,
          );
          for (final scored in surfaced.chips) {
            expect(
              scored.score,
              greaterThanOrEqualTo(0.35 - 1e-9),
              reason: '${category.name} at ${logged.name}: $scored',
            );
          }
        }
      }
    });

    test(
      'Journey A reaches its raised non-event floor, or says it could not',
      () {
        // Its job is discovering a cue *type* the user has not named, so an
        // event-heavy set biases the discovery toward the answer the app already
        // prefers. The floor is a guarantee about the *rule*, not about the
        // library: §8 is explicit that the multiplicative daypart term can leave
        // a category short at a particular hour, and names reading logged
        // mid-morning as the clearest case. What must never happen is the rule
        // falling short quietly.
        for (final category in HabitCategory.values) {
          for (final logged in Daypart.values) {
            final surfaced = surfaceStarterChips(
              category: category,
              logged: logged,
            );
            final nonEvent = surfaced.chips
                .where((scored) => scored.chip.cueType != CueType.event)
                .length;

            expect(
              nonEvent >= 2 || surfaced.nonEventFloorUnmet,
              isTrue,
              reason: '${category.name} at ${logged.name}: ${surfaced.labels}',
            );
          }
        }
      },
    );

    test('the hours the library cannot cover are the ones §8 names', () {
      // Pinned so that authoring more chips into a thin daypart shows up here
      // as a deliberate change rather than passing unnoticed.
      final thin = <String>[];
      for (final category in HabitCategory.values) {
        for (final logged in Daypart.values) {
          final surfaced = surfaceStarterChips(
            category: category,
            logged: logged,
          );
          if (surfaced.nonEventFloorUnmet) {
            thin.add('${category.name}/${logged.name}');
          }
        }
      }

      expect(thin, contains('reading/morning'));
    });
  });

  group('a habit with no category', () {
    test('is served from the global pool rather than failing', () {
      // `Habit.category` is nullable by design: the pool exists so that such a
      // habit still gets a plausible first reflection, just a weaker one.
      final surfaced = surfaceStarterChips(
        category: null,
        logged: Daypart.early,
      );

      expect(surfaced.chips, isNotEmpty);
      expect(
        surfaced.chips.every((scored) => globalCueChips.contains(scored.chip)),
        isTrue,
      );
    });

    test('an unknown category resolves the same way', () {
      expect(cueChipsFor(null), same(globalCueChips));
      expect(frictionChipsFor(null), same(globalFrictionChips));
    });
  });

  group('the library itself', () {
    test('carries twelve chips in each of the twelve categories', () {
      expect(starterChipLibrary, hasLength(HabitCategory.values.length));
      for (final entry in starterChipLibrary.entries) {
        expect(entry.value.cues, hasLength(12), reason: entry.key.name);
      }
    });

    test('every category offers event, time, location and internal', () {
      // §8's coverage claim, pinned. It is a property of the library, not a
      // guarantee at run time — the multiplicative daypart term can still leave
      // a category short at a particular hour.
      for (final entry in starterChipLibrary.entries) {
        final types = entry.value.cues.map((chip) => chip.cueType).toSet();
        expect(
          types,
          containsAll(<CueType>[
            CueType.event,
            CueType.time,
            CueType.location,
            CueType.internal,
          ]),
          reason: entry.key.name,
        );
      }
    });

    test('every category can diagnose both forgetting and reluctance', () {
      // reflection-logic §4 stakes a claim on this split: forgetting is a cue
      // failure, reluctance is a reward failure, they have opposite fixes, and
      // the claim only pays off if both are always available.
      for (final entry in starterChipLibrary.entries) {
        final types = entry.value.frictions
            .map((chip) => chip.frictionType)
            .toSet();
        expect(types, contains(FrictionType.forgot), reason: entry.key.name);
        expect(
          types,
          contains(FrictionType.motivation),
          reason: entry.key.name,
        );
      }
    });

    test('no chip offers the app itself as a cue', () {
      // The product thesis is that the app is *not* the cue (growth-engine §6).
      // Offering "the app told me" would measure the failure mode and file it
      // as a cue. `wind-down alarm` is the one permitted exception — the user's
      // own alarm, external to this app.
      const bannedWords = <String>['notification', 'reminder', 'the app'];
      for (final entry in starterChipLibrary.entries) {
        for (final chip in entry.value.cues) {
          for (final banned in bannedWords) {
            expect(
              chip.label.toLowerCase(),
              isNot(contains(banned)),
              reason: '${entry.key.name}: ${chip.label}',
            );
          }
        }
      }
    });

    test('every chip label is tap-readable', () {
      // §2: 24 characters is the binding constraint on a chip.
      for (final entry in starterChipLibrary.entries) {
        for (final chip in entry.value.cues) {
          expect(
            chip.label.length,
            lessThanOrEqualTo(24),
            reason: '${entry.key.name}: ${chip.label}',
          );
        }
        for (final chip in entry.value.frictions) {
          expect(
            chip.label.length,
            lessThanOrEqualTo(24),
            reason: '${entry.key.name}: ${chip.label}',
          );
        }
      }
    });
  });
}
