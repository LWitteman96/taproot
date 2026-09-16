import 'package:meta/meta.dart';

import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/features/reflection/domain/daypart.dart';

/// One authored cue chip (starter-chip-library.md §1).
///
/// The positional arguments are the four every chip has — label, type, prior,
/// family — kept positional so that 144 authored chips read as a table rather
/// than as 144 paragraphs. Everything optional is named.
@immutable
class StarterChip {
  const StarterChip(
    this.label,
    this.cueType,
    this.prior,
    this.family, {
    this.dayparts = const <Daypart>{},
    this.strict = false,
    this.conditional = false,
  });

  /// What the user sees. At most 24 characters, lowercase, in their voice —
  /// `after breakfast`, never `Following morning meal` (§2).
  final String label;

  final CueType cueType;

  /// How commonly this cues this category. 0.0–1.0.
  ///
  /// **Authored, not measured** (§9). Every one is a judgement call, and they
  /// should be replaced per category by observed first-reflection tap
  /// frequencies as soon as there is data. The chip *text* should outlive the
  /// numbers.
  final double prior;

  /// Near-duplicate group. At most one chip per family reaches a set, which is
  /// what stops `after breakfast` and `with breakfast` taking two of four
  /// slots.
  final String family;

  /// Where this cue plausibly lives. **Empty means daypart-neutral** (`any` in
  /// the spec's tables) rather than "nowhere".
  final Set<Daypart> dayparts;

  /// Whether [dayparts] is physically required rather than merely typical.
  ///
  /// A strict chip is dropped outright when the daypart does not match, before
  /// scoring: `got into bed` must never appear against an 07:10 completion,
  /// whatever adjacency would give it.
  final bool strict;

  /// Whether this chip presupposes a life circumstance (§3).
  ///
  /// `after dropping the kids off` is an excellent cue for the people it fits
  /// and a small insult to everyone else. Conditional chips are authored but
  /// held out of the default set until something unlocks them for this user.
  final bool conditional;

  @override
  String toString() => 'StarterChip($label, ${cueType.name}, $prior)';
}

/// One authored friction chip, for the Diagnosis framing (§6.2, §7).
@immutable
class FrictionChip {
  const FrictionChip(this.label, this.frictionType);

  final String label;
  final FrictionType frictionType;

  @override
  String toString() => 'FrictionChip($label, ${frictionType.name})';
}

/// What one category of the library holds.
@immutable
class CategoryChips {
  const CategoryChips({required this.cues, required this.frictions});

  final List<StarterChip> cues;
  final List<FrictionChip> frictions;
}
