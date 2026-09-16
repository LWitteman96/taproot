import 'package:taproot/core/engine/constants.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/habit_category.dart';
import 'package:taproot/features/reflection/domain/starter_chip.dart';
import 'package:taproot/features/reflection/domain/starter_chip_library.dart';

/// The friction chips a Diagnosis offers (starter-chip-library.md §6.3).
///
/// Simpler than the cue rule — friction has no meaningful daypart preference
/// and no stacking equivalent — but with one hard guarantee: **always at least
/// one `forgot` chip and at least one `motivation` chip.**
///
/// That guarantee is the spec's whole claim about diagnosis. reflection-logic
/// §4 stakes it out: forgetting is a cue failure, reluctance is a reward
/// failure, they have opposite fixes, and most apps cannot tell them apart
/// because they never ask. The claim only pays off if both are always tappable
/// — if a category's top five happened to be four environment chips and a time
/// chip, the app would have quietly lost the distinction it says is its edge.
///
/// Ranking is by **authored order** within the category. Friction chips carry
/// no prior in §7's tables — unlike cue chips — so the order they are written
/// in is the only ranking the library expresses, and the tables are visibly
/// ordered most-likely-first.
List<FrictionChip> surfaceFrictionChips(HabitCategory? category) {
  final authored = frictionChipsFor(category);

  final chosen = <FrictionChip>[];
  final typeCounts = <FrictionType, int>{};

  bool admits(FrictionChip chip) =>
      (typeCounts[chip.frictionType] ?? 0) < EngineConstants.frictionTypeCap;

  void take(FrictionChip chip) {
    chosen.add(chip);
    typeCounts.update(
      chip.frictionType,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }

  // The two guaranteed types go in first, so that a category whose authored
  // order happens to bury one of them cannot push it out of the set.
  for (final guaranteed in <FrictionType>[
    FrictionType.forgot,
    FrictionType.motivation,
  ]) {
    final chip = authored
        .where((candidate) => candidate.frictionType == guaranteed)
        .firstOrNull;
    if (chip != null) take(chip);
  }

  for (final chip in authored) {
    if (chosen.length >= EngineConstants.frictionChipCount) break;
    if (chosen.contains(chip)) continue;
    if (!admits(chip)) continue;
    take(chip);
  }

  // Backfill from the global pool if the category is thin, under the same cap.
  for (final chip in globalFrictionChips) {
    if (chosen.length >= EngineConstants.frictionChipCount) break;
    if (chosen.any((taken) => taken.label == chip.label)) continue;
    if (!admits(chip)) continue;
    take(chip);
  }

  // Back into authored order, so the set reads the way the library was written
  // rather than leading with whichever two types were guaranteed.
  final order = <String, int>{
    for (final (index, chip) in authored.indexed) chip.label: index,
  };
  chosen.sort(
    (a, b) => (order[a.label] ?? 1 << 20).compareTo(order[b.label] ?? 1 << 20),
  );
  return chosen;
}
