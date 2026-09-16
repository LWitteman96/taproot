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
  // habit's own category is consulted first, so a label that two categories
  // share resolves to the family *that* category means by it.
  final withinCategory = _familiesByLabel[category];
  if (withinCategory != null) {
    final family = withinCategory[normalised];
    if (family != null) return family;
  }
  final anywhere = _familiesByLabel[null]?[normalised];
  if (anywhere != null) return anywhere;

  for (final entry in _familyKeywords.entries) {
    for (final keyword in entry.value) {
      if (normalised.contains(keyword)) return entry.key;
    }
  }
  return null;
}

/// Lowercased label → family, built once per category and kept.
///
/// **The lookup used to be a rebuild.** Every call materialised the category's
/// chips, the global pool and a spread of every category's cues — some three
/// hundred entries, with the category and global chips appearing twice — and
/// then walked it lowercasing labels one at a time to answer a single
/// question. A first reflection asks it once; §3's conditional unlock will ask
/// it per typed answer. The map is the same data with the work done once.
///
/// The `null` key holds the fallback order — global chips, then every
/// category's — so a label the habit's own category does not know still
/// resolves to whatever the library calls it elsewhere. Category maps are
/// populated last-wins per category and consulted first, which keeps the
/// "shared label, category decides" rule the eager version had.
final Map<HabitCategory?, Map<String, String>> _familiesByLabel =
    _buildFamiliesByLabel();

Map<HabitCategory?, Map<String, String>> _buildFamiliesByLabel() {
  final byLabel = <HabitCategory?, Map<String, String>>{};

  void add(HabitCategory? key, Iterable<StarterChip> chips) {
    final target = byLabel.putIfAbsent(key, () => <String, String>{});
    for (final chip in chips) {
      target.putIfAbsent(chip.label.toLowerCase(), () => chip.family);
    }
  }

  for (final category in HabitCategory.values) {
    add(category, cueChipsFor(category));
  }

  // The fallback: the global pool first, then every category's cues, which is
  // the order the eager list searched in.
  add(null, globalCueChips);
  for (final entry in starterChipLibrary.values) {
    add(null, entry.cues);
  }

  return byLabel;
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
