import 'package:taproot/core/engine/domain.dart';

/// The cue types a habit may be *designed* around.
///
/// Four, not five. The taxonomy has five (reflection-logic §4) and all five are
/// valid for a cue the user *discovers* through reflection — but an internal
/// state cannot anchor a designed cue, because the engine cannot schedule,
/// nudge or fairly measure a habit hung on a mood (growth-engine §1). The
/// taxonomy is used two different ways at two different moments: creation
/// accepts external types only, reflection accepts all five.
///
/// Derived from [CueType.isSchedulable] rather than listed by hand, so the two
/// cannot drift apart and the `Habit` assert can never fire on something this
/// screen offered.
final List<CueType> designableCueTypes = CueType.values
    .where((type) => type.isSchedulable)
    .toList(growable: false);

/// What the user sees for a cue type.
String cueTypeLabel(CueType type) => switch (type) {
  CueType.event => 'After something',
  CueType.time => 'At a time',
  CueType.location => 'Somewhere',
  CueType.social => 'With someone',
  CueType.internal => 'When I feel',
  CueType.unknown => 'Not sure yet',
};

/// The one line under the label, explaining what the type is for.
String cueTypeHint(CueType type) => switch (type) {
  CueType.event =>
    'Stacked onto something you already do. The most reliable anchor there is.',
  CueType.time => 'A point in the day you can name.',
  CueType.location => 'Somewhere you reliably end up.',
  CueType.social => 'Another person is part of the trigger.',
  CueType.internal => 'A feeling or a state — discovered, never designed.',
  CueType.unknown => 'Unclassified.',
};

/// Example phrasings, straight from the taxonomy table in reflection-logic §4.
///
/// These are examples to tap rather than a library to rank: the starter chip
/// library (§5) is the ranked one, and it runs at the *first reflection*, where
/// there is a completion and a time of day to rank against. There is neither
/// here. Offering them keeps creation inside the app's tap-don't-type default
/// without pretending to a relevance it cannot compute yet.
List<String> cueExamplesFor(CueType type) => switch (type) {
  CueType.event => const <String>[
    'after breakfast',
    'after my morning coffee',
    'got home from work',
    'once the kids are asleep',
  ],
  CueType.time => const <String>[
    'just woke up',
    'lunchtime',
    'before bed',
  ],
  CueType.location => const <String>[
    'walked past the gym',
    'sat down at my desk',
    'got in the car',
  ],
  CueType.social => const <String>[
    'my partner was going',
    'a friend texted',
  ],
  CueType.internal || CueType.unknown => const <String>[],
};
