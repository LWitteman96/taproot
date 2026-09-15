import 'package:taproot/core/engine/constants.dart';
import 'package:meta/meta.dart';

import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/reflection.dart';
import 'package:taproot/features/reflection/domain/starter_chip.dart';

/// The chips a *returning* reflection offers (reflection-logic §4).
///
/// The starter library answers the first reflection, which has no history to
/// rank. Every reflection after it ranks the user's own past answers by
/// **recency-weighted frequency**, capped at five — which is what makes
/// tap-don't-type sustainable: the app remembers what you said last time.
///
/// **The weighting is a reconciliation.** §4 asks for "recency-weighted
/// frequency" without giving a decay, so an answer's weight halves every
/// [_recencyHalfLife] reflections. Eight is not arbitrary: it is the window
/// convergence already measures over, so "recent" means the same span in both
/// places rather than two different ideas of recent living in one app. The
/// number belongs in §8's calibration list, not in the settled column.
const int _recencyHalfLife = EngineConstants.convergenceWindow;

/// One of the user's own past answers, ready to be offered back.
///
/// Carries the **type they gave it**, not a guess: tapping a remembered chip
/// has to record the same `cue_type` the original answer did, or a habit's
/// convergence history quietly changes meaning the second time the user taps
/// the same words.
@immutable
class RememberedCue {
  const RememberedCue(this.label, this.cueType);

  final String label;
  final CueType cueType;

  @override
  String toString() => 'RememberedCue($label, ${cueType.name})';
}

/// Past answers, most-worth-offering first.
///
/// Only cue-bearing answers count. A `can't remember` is a first-class answer
/// to *give* (§4) but it is not a cue, and offering it back as a chip would
/// turn an honest non-answer into a suggestion.
List<RememberedCue> rememberedCues({
  required List<Reflection> reflections,
  int cap = 5,
}) {
  final cueBearing =
      reflections
          .where(
            (reflection) =>
                reflection.inputMode != InputMode.cantRemember &&
                reflection.inputMode != InputMode.skipped &&
                (reflection.cueReported?.trim().isNotEmpty ?? false),
          )
          .toList()
        ..sort((a, b) {
          // Newest first, with the id breaking exact ties. Two answers can
          // share a timestamp — a backfill, or a device with a coarse clock —
          // and without a second key the input order decides the ranking, so
          // the same history offers different chips on different reads.
          final byRecency = b.createdAt.compareTo(a.createdAt);
          return byRecency != 0 ? byRecency : a.id.compareTo(b.id);
        });

  final weights = <String, double>{};
  final firstSeen = <String, int>{};
  final typeOf = <String, CueType>{};
  for (final (age, reflection) in cueBearing.indexed) {
    final label = reflection.cueReported!.trim();
    final weight = _weightAt(age);
    weights.update(label, (total) => total + weight, ifAbsent: () => weight);
    firstSeen.putIfAbsent(label, () => age);
    // Most recent wins: the list is sorted newest first, so the first type
    // seen for a label is the one the user most recently gave it.
    typeOf.putIfAbsent(label, () => reflection.cueType);
  }

  final ranked = weights.keys.toList()
    ..sort((a, b) {
      final byWeight = weights[b]!.compareTo(weights[a]!);
      if (byWeight != 0) return byWeight;
      // Two labels of equal weight: the one said more recently wins, then the
      // label itself, so the same history always produces the same offer.
      final byRecency = firstSeen[a]!.compareTo(firstSeen[b]!);
      return byRecency != 0 ? byRecency : a.compareTo(b);
    });

  return ranked
      .take(cap)
      .map((label) => RememberedCue(label, typeOf[label]!))
      .toList();
}

double _weightAt(int age) {
  var weight = 1.0;
  for (var halved = 0; halved < age ~/ _recencyHalfLife; halved++) {
    weight /= 2;
  }
  // Within a half-life the decay is linear rather than stepped, so the eighth
  // and ninth answers are not worth wildly different amounts.
  final within = age % _recencyHalfLife;
  return weight * (1 - 0.5 * within / _recencyHalfLife);
}

/// Whether this is the habit's first reflection — the one the starter library
/// exists for.
bool isFirstReflection(List<Reflection> reflections) => reflections.isEmpty;

/// The designed cue, as a chip pinned in slot 0.
///
/// This is what makes Validation a single tap (§0): the question is "did your
/// cue fire?", and the answer should be one press rather than a hunt.
///
/// It carries the habit's own cue type and a prior of 1.0, but neither is used
/// for ranking — the pinned chip is *placed*, not scored. They are set so that
/// anything downstream reading the chip's type (the reflection record's
/// `cue_type`, most importantly) gets the truth rather than a placeholder.
StarterChip? pinnedDesignedCue({
  required String? designedCue,
  required CueType? designedCueType,
  required String family,
}) => designedCue == null || designedCue.trim().isEmpty
    ? null
    : StarterChip(
        designedCue.trim(),
        designedCueType ?? CueType.unknown,
        1,
        family,
      );
