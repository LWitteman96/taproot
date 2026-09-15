import 'package:meta/meta.dart';

import 'package:taproot/core/engine/constants.dart';
import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/habit_category.dart';
import 'package:taproot/features/reflection/domain/daypart.dart';
import 'package:taproot/features/reflection/domain/starter_chip.dart';
import 'package:taproot/features/reflection/domain/starter_chip_library.dart';

/// A chip with the score it earned, so a test — or a later tuning pass — can
/// see why a set looks the way it does.
@immutable
class ScoredChip {
  const ScoredChip(this.chip, this.score);

  final StarterChip chip;
  final double score;

  @override
  String toString() => '${chip.label} (${score.toStringAsFixed(2)})';
}

/// A surfaced set, and which of §5.3's degradations it needed to get there.
///
/// The flags are not diagnostics for their own sake. §9 says the floors
/// "currently produce sensible behavior on the 24 worked examples, which is not
/// the same as being right" — so whoever tunes them needs to see *which* step
/// fired, and a test needs to distinguish "the ceiling held" from "the ceiling
/// was lifted because the set would otherwise have been short".
@immutable
class StarterChipSet {
  const StarterChipSet({
    required this.chips,
    this.backfilledFromGlobalPool = false,
    this.relaxedTypeCeiling = false,
    this.nonEventFloorUnmet = false,
  });

  final List<ScoredChip> chips;

  /// The category pool had fewer chips clearing the score floor than the set
  /// wanted, so §6.1's global pool was folded in.
  final bool backfilledFromGlobalPool;

  /// The pool was big enough but the type ceiling was what kept the set short,
  /// so it was lifted — the second relaxation step.
  final bool relaxedTypeCeiling;

  /// The library could not supply enough non-event chips at this hour.
  ///
  /// Not a bug, and §8 names the clearest case: reading logged mid-morning,
  /// where only `book was out` clears the floor. The multiplicative daypart
  /// term means a category balanced on paper can still be short at a particular
  /// hour. The real fix is authoring, not ranking (§9).
  final bool nonEventFloorUnmet;

  List<String> get labels => chips.map((scored) => scored.chip.label).toList();

  int get length => chips.length;
}

/// The tolerance chip scores are compared at.
///
/// Every prior and bonus in §5.1 is authored to two decimals, and the §5.3
/// tie-break rules exist precisely because exact ties are common — `packed my
/// bag` and `first thing up` both reach 0.65, `10pm hit` and `eyes got heavy`
/// both reach 0.60. In binary those pairs land a few ulps apart
/// (0.6499999999999999 against 0.6500000000000000), so comparing raw doubles
/// resolves a documented tie by representation error and the authored tie-break
/// never runs. Four of the spec's worked examples come out in the wrong order
/// without this.
const double _scoreEpsilon = 1e-9;

/// Descending, with scores the spec calls equal treated as equal.
int _compareScores(double a, double b) =>
    (a - b).abs() < _scoreEpsilon ? 0 : b.compareTo(a);

/// Whether [score] reaches [threshold], at the same tolerance.
bool _reaches(double score, double threshold) =>
    score > threshold - _scoreEpsilon;

/// `score = prior × daypart_factor + type_bonus` (starter-chip-library.md §5.1).
///
/// Max possible is 1.30. A mismatched daypart zeroes the prior and leaves the
/// type bonus alone — at most 0.30, below the floor by construction — so
/// mismatched chips self-eliminate without a special rule.
double scoreChip({required StarterChip chip, required Daypart logged}) =>
    chip.prior * daypartFactor(logged: logged, chipDayparts: chip.dayparts) +
    (EngineConstants.cueTypeBonus[chip.cueType] ?? 0);

/// The starter chips to offer on a first reflection.
///
/// Returns the **starter** set only. The designed cue is pinned in slot 0 by
/// the caller, which is what makes Validation a single tap (§0); passing its
/// [designedCueFamily] here is how this knows to leave a duplicate out.
///
/// A null [designedCueFamily] means Journey A — tracking an existing habit,
/// where reverse-engineering the cue is the point. That surfaces one more chip,
/// skips the family filter, and raises the non-event floor, because Journey A's
/// job is discovering a cue *type* the user has not named and an event-heavy
/// set biases that discovery toward the answer the app already prefers (§5.4).
StarterChipSet surfaceStarterChips({
  required HabitCategory? category,
  required Daypart logged,
  String? designedCueFamily,
  Set<String> unlockedConditionalFamilies = const <String>{},
}) {
  final hasDesignedCue = designedCueFamily != null;
  final wanted = hasDesignedCue
      ? EngineConstants.starterChipCount
      : EngineConstants.starterChipCountWithoutDesignedCue;
  final nonEventFloor = hasDesignedCue
      ? EngineConstants.starterChipNonEventFloor
      : EngineConstants.nonEventFloorWithoutDesignedCue;

  List<ScoredChip> eligible(List<StarterChip> from) => _eligible(
    from: from,
    logged: logged,
    designedCueFamily: designedCueFamily,
    unlockedConditionalFamilies: unlockedConditionalFamilies,
  );

  final fromCategory = eligible(cueChipsFor(category));

  // §5.3's two triggers are different, and the prose is precise about each.
  //
  // **Backfill keys off the pool** — "if fewer than n chips *clear the floor*".
  // The category simply did not have enough material at this hour, which is the
  // midday-reading case, where four category chips clear the floor and
  // `after breakfast` (0.49) is pulled in above `with morning coffee` (0.47).
  //
  // **Relaxation keys off the selection** — "if still short". Here the pool was
  // big enough and a guard is what kept the set short, so lifting the guard is
  // the thing that helps; widening the pool would not.
  //
  // Reading both triggers off the selection — the obvious simplification —
  // quietly makes the type ceiling meaningless, because any time it binds it
  // would also trigger a backfill that pulls in another chip of the type it was
  // trying to limit. Reading afternoon is the worked case: five chips clear the
  // floor, the ceiling holds three events, and backfilling adds `got home` — a
  // fourth event — which is the monoculture the ceiling exists to prevent.
  final backfilled = fromCategory.length < wanted;
  final pool = backfilled
      ? <ScoredChip>[...fromCategory, ...eligible(globalCueChips)]
      : fromCategory;

  var selected = _select(
    candidates: pool,
    wanted: wanted,
    nonEventFloor: nonEventFloor,
    typeCeiling: EngineConstants.starterChipTypeCeiling,
  );

  var relaxed = false;
  if (selected.length < wanted) {
    final lifted = _select(
      candidates: pool,
      wanted: wanted,
      nonEventFloor: nonEventFloor,
      typeCeiling: null,
    );
    // Only if it actually bought something. A short set beats a padded one, and
    // it does not stop being short because a guard was lifted for nothing.
    if (lifted.length > selected.length) {
      selected = lifted;
      relaxed = true;
    }
  }

  return StarterChipSet(
    chips: selected,
    backfilledFromGlobalPool: backfilled,
    relaxedTypeCeiling: relaxed,
    nonEventFloorUnmet:
        selected
            .where((scored) => scored.chip.cueType != CueType.event)
            .length <
        nonEventFloor,
  );
}

/// Hard filters (§5.2), then scoring, then the floor.
List<ScoredChip> _eligible({
  required List<StarterChip> from,
  required Daypart logged,
  required String? designedCueFamily,
  required Set<String> unlockedConditionalFamilies,
}) {
  final scored = <ScoredChip>[];
  for (final chip in from) {
    // 1. Conditional chips presuppose a life circumstance and stay out until
    //    something unlocks them for this user.
    if (chip.conditional &&
        !unlockedConditionalFamilies.contains(chip.family)) {
      continue;
    }
    // 2. The designed cue is already pinned in slot 0; a duplicate wastes a
    //    slot and looks like a bug.
    if (designedCueFamily != null && chip.family == designedCueFamily) continue;
    // 3. A strict chip's daypart is physically required, not merely typical.
    //    `got into bed` must never appear against an 07:10 completion, whatever
    //    adjacency would give it.
    if (chip.strict && !chip.dayparts.contains(logged)) continue;

    final score = scoreChip(chip: chip, logged: logged);
    if (!_reaches(score, EngineConstants.starterChipScoreFloor)) continue;
    scored.add(ScoredChip(chip, score));
  }
  return scored;
}

/// Greedy fill by score, then the two floors.
///
/// [typeCeiling] of null is the relaxation step — the ceiling lifted because
/// the pool could not fill the set with it in place.
List<ScoredChip> _select({
  required List<ScoredChip> candidates,
  required int wanted,
  required int nonEventFloor,
  required int? typeCeiling,
}) {
  final ranked = _ranked(candidates);

  final chosen = <ScoredChip>[];
  final families = <String>{};
  final typeCounts = <CueType, int>{};

  bool admits(ScoredChip scored) {
    if (families.contains(scored.chip.family)) return false;
    if (typeCeiling != null &&
        (typeCounts[scored.chip.cueType] ?? 0) >= typeCeiling) {
      return false;
    }
    return true;
  }

  void take(ScoredChip scored) {
    chosen.add(scored);
    families.add(scored.chip.family);
    typeCounts.update(
      scored.chip.cueType,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }

  for (final scored in ranked) {
    if (chosen.length >= wanted) break;
    if (!admits(scored)) continue;
    take(scored);
  }

  _applyNonEventFloor(
    chosen: chosen,
    ranked: ranked,
    floor: nonEventFloor,
    typeCeiling: typeCeiling,
  );
  _applyEventFloor(chosen: chosen, ranked: ranked);

  // Re-rank: a promotion can leave the set out of score order, and the set is
  // shown in the order it is returned.
  return _ranked(chosen);
}

/// Descending by score, ties broken by type bonus, then prior, then the order
/// the chip was authored in.
///
/// The authored-order tie-break is why this sorts on an index rather than
/// relying on `List.sort`, which is not stable in Dart — without it, two chips
/// identical on every term would order unpredictably between runs.
List<ScoredChip> _ranked(List<ScoredChip> candidates) {
  final indexed = candidates.indexed.toList();
  indexed.sort((a, b) {
    final byScore = _compareScores(a.$2.score, b.$2.score);
    if (byScore != 0) return byScore;

    final bonusA = EngineConstants.cueTypeBonus[a.$2.chip.cueType] ?? 0;
    final bonusB = EngineConstants.cueTypeBonus[b.$2.chip.cueType] ?? 0;
    final byBonus = bonusB.compareTo(bonusA);
    if (byBonus != 0) return byBonus;

    final byPrior = b.$2.chip.prior.compareTo(a.$2.chip.prior);
    if (byPrior != 0) return byPrior;

    return a.$1.compareTo(b.$1);
  });
  return indexed.map((entry) => entry.$2).toList();
}

/// Guarantees a true answer for an internally-, time- or socially-cued user —
/// and keeps the growth-engine §5 internal-cue exemption reachable.
void _applyNonEventFloor({
  required List<ScoredChip> chosen,
  required List<ScoredChip> ranked,
  required int floor,
  required int? typeCeiling,
}) {
  bool isEvent(ScoredChip scored) => scored.chip.cueType == CueType.event;

  while (chosen.where((scored) => !isEvent(scored)).length < floor) {
    final families = chosen.map((scored) => scored.chip.family).toSet();
    final replacement = ranked.firstWhere(
      (scored) => !isEvent(scored) && !families.contains(scored.chip.family),
      orElse: () => const ScoredChip(
        StarterChip('', CueType.unknown, 0, ''),
        double.negativeInfinity,
      ),
    );
    if (replacement.score == double.negativeInfinity) return;

    final droppable = chosen.where(isEvent).toList();
    if (droppable.isEmpty) return;
    // The cheapest event chip goes, not the newest.
    droppable.sort((a, b) => a.score.compareTo(b.score));
    chosen.remove(droppable.first);
    chosen.add(replacement);
    if (typeCeiling != null && chosen.length > ranked.length) return;
  }
}

/// Leads with the most reliable anchor type — without forcing an implausible
/// chip in.
///
/// The promotion floor is the whole subtlety. Without it the guard happily
/// pushes `after dinner` into a 09:00 tidying set to satisfy its own
/// arithmetic; a guard that forces in a chip nobody would tap is worse than the
/// imbalance it was correcting. So it yields when the library has nothing
/// plausible — which happens legitimately for early-morning journaling and
/// mid-morning tidying.
void _applyEventFloor({
  required List<ScoredChip> chosen,
  required List<ScoredChip> ranked,
}) {
  bool isEvent(ScoredChip scored) => scored.chip.cueType == CueType.event;

  while (chosen.where(isEvent).length < EngineConstants.starterChipEventFloor) {
    final families = chosen.map((scored) => scored.chip.family).toSet();
    final promotable = ranked
        .where(
          (scored) =>
              isEvent(scored) &&
              !families.contains(scored.chip.family) &&
              scored.score >= EngineConstants.starterChipEventPromotionFloor,
        )
        .toList();
    if (promotable.isEmpty) return;

    final displaceable = chosen.where((scored) => !isEvent(scored)).toList();
    if (displaceable.isEmpty) return;
    displaceable.sort((a, b) => a.score.compareTo(b.score));

    // Never drop below the non-event floor to satisfy this one; the diversity
    // guard outranks the preference.
    chosen.remove(displaceable.first);
    chosen.add(promotable.first);
  }
}
