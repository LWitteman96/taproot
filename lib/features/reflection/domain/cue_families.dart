import 'package:taproot/core/models/habit_category.dart';
import 'package:taproot/features/reflection/domain/starter_chip.dart';
import 'package:taproot/features/reflection/domain/starter_chip_library.dart';

/// Which chip family a piece of free text belongs to.
///
/// **A partial answer to an open question, and honest about it.** §9 says
/// "conditional unlock needs a text→family mapping. §3 says a typed answer
/// unlocks the matching conditional chip, which presumes a mapping from free
/// text to `family` that doesn't exist yet. A small keyword table per family is
/// probably enough to start; it does not need to be a model."
///
/// This is that small table, and it does two jobs:
///
/// - **Filter §5.2.2** — dropping starter chips that duplicate the designed
///   cue. Without a family for the designed cue that filter never fires, and
///   every first reflection can show the pinned cue twice, which the spec calls
///   a wasted slot that looks like a bug.
/// - **Conditional unlock (§3)** — a user who types `walked the dog` should
///   stop being a stranger to the `dog` family.
///
/// Exact label matches are tried first, because the creation flow offers the
/// library's own phrasings as examples and most designed cues will be one of
/// them verbatim. The keyword table is the fallback.
String? familyForCueText(String? text, {HabitCategory? category}) {
  if (text == null) return null;
  final normalised = text.trim().toLowerCase();
  if (normalised.isEmpty) return null;

  // An exact match against what the library already calls this cue. The
  // habit's own category is searched first, so a label that two categories
  // share resolves to the family that category means by it.
  for (final chip in <StarterChip>[
    ...cueChipsFor(category),
    ...globalCueChips,
    for (final entry in starterChipLibrary.values) ...entry.cues,
  ]) {
    if (chip.label.toLowerCase() == normalised) return chip.family;
  }

  for (final entry in _familyKeywords.entries) {
    for (final keyword in entry.value) {
      if (normalised.contains(keyword)) return entry.key;
    }
  }
  return null;
}

/// Keyword per family, for the families a user is most likely to type their own
/// words for. Deliberately small — the point is to be better than nothing, not
/// to be complete, and a wrong match here costs one chip slot.
const Map<String, List<String>> _familyKeywords = <String, List<String>>{
  'breakfast': <String>['breakfast'],
  'coffee': <String>['coffee', 'espresso'],
  'dinner': <String>['dinner', 'supper'],
  'lunch': <String>['lunch'],
  'teeth': <String>['teeth', 'brush'],
  'bed-in': <String>['got into bed', 'into bed', 'climbed into bed'],
  'bed': <String>['bed time', 'bedtime', 'before bed'],
  'woke': <String>['woke', 'got up', 'out of bed', 'first thing'],
  'got-home': <String>['got home', 'get home', 'came home'],
  'commute': <String>['commute', 'train', 'bus', 'on the way to work'],
  'dog': <String>['dog'],
  'kids': <String>['kids', 'children'],
  'desk': <String>['desk'],
  'shower': <String>['shower'],
  'post-workout': <String>['workout', 'gym', 'training', 'exercise'],
  'post-walk': <String>['walk'],
  'phone': <String>['phone'],
  'work-start': <String>['start work', 'starting work'],
  'work-end': <String>['finished work', 'closed my laptop', 'logged off'],
};
