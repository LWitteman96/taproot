/// The authored starter chip library (starter-chip-library.md §6, §7).
///
/// Twelve categories, twelve cue chips each, plus friction chips for Diagnosis
/// and the global pools that backfill a thin set. This file is **content**, not
/// logic — the rule that ranks it lives in `chip_surfacing.dart`.
///
/// Every prior here is a judgement call, authored rather than measured (§9).
/// They are meant to be replaced per category by observed first-reflection tap
/// frequencies once there is data, at which point this becomes a genuine prior
/// rather than a set of opinions. **The chip text should outlive the numbers.**
library;

import 'package:taproot/core/engine/domain.dart';
import 'package:taproot/core/models/habit_category.dart';
import 'package:taproot/features/reflection/domain/daypart.dart';
import 'package:taproot/features/reflection/domain/starter_chip.dart';

// Recurring daypart sets, named once. An empty set is `any` in the spec's
// tables — daypart-neutral, not "nowhere".
const Set<Daypart> _earlyAndMorning = <Daypart>{Daypart.early, Daypart.morning};
const Set<Daypart> _afternoonAndEvening = <Daypart>{
  Daypart.afternoon,
  Daypart.evening,
};
const Set<Daypart> _eveningAndNight = <Daypart>{Daypart.evening, Daypart.night};
const Set<Daypart> _earlyAndNight = <Daypart>{Daypart.early, Daypart.night};
const Set<Daypart> _middayAndAfternoon = <Daypart>{
  Daypart.midday,
  Daypart.afternoon,
};
const Set<Daypart> _morningAndEvening = <Daypart>{
  Daypart.morning,
  Daypart.evening,
};
const Set<Daypart> _workingHours = <Daypart>{
  Daypart.morning,
  Daypart.midday,
  Daypart.afternoon,
};
const Set<Daypart> _justEarly = <Daypart>{Daypart.early};
const Set<Daypart> _justMorning = <Daypart>{Daypart.morning};
const Set<Daypart> _justMidday = <Daypart>{Daypart.midday};
const Set<Daypart> _justEvening = <Daypart>{Daypart.evening};
const Set<Daypart> _justNight = <Daypart>{Daypart.night};

/// Backfill for any category (§6.1).
///
/// `felt like it` sits deliberately near the floor: it is the honest answer
/// often enough to be worth having, but it is low-information, and a set that
/// leads with it teaches the engine nothing.
const List<StarterChip> globalCueChips = <StarterChip>[
  StarterChip(
    'after breakfast',
    CueType.event,
    0.55,
    'breakfast',
    dayparts: _earlyAndMorning,
  ),
  StarterChip(
    'after coffee',
    CueType.event,
    0.50,
    'coffee',
    dayparts: _earlyAndMorning,
  ),
  StarterChip(
    'got home',
    CueType.event,
    0.50,
    'got-home',
    dayparts: _afternoonAndEvening,
  ),
  StarterChip(
    'after dinner',
    CueType.event,
    0.50,
    'dinner',
    dayparts: _justEvening,
  ),
  StarterChip('just woke up', CueType.time, 0.45, 'woke', dayparts: _justEarly),
  StarterChip('before bed', CueType.time, 0.45, 'bed', dayparts: _justNight),
  StarterChip(
    'lunch break',
    CueType.time,
    0.40,
    'lunch',
    dayparts: _justMidday,
  ),
  StarterChip('felt like it', CueType.internal, 0.30, 'felt-like'),
  StarterChip('had a free moment', CueType.internal, 0.25, 'free-moment'),
];

/// Friction chips available to every category (§6.2).
const List<FrictionChip> globalFrictionChips = <FrictionChip>[
  FrictionChip('just forgot', FrictionType.forgot),
  FrictionChip('no time', FrictionType.time),
  FrictionChip('too tired', FrictionType.energy),
  FrictionChip('something came up', FrictionType.competing),
  FrictionChip("didn't feel like it", FrictionType.motivation),
  FrictionChip("wasn't set up", FrictionType.environment),
];

/// The twelve category libraries (§7).
const Map<HabitCategory, CategoryChips>
starterChipLibrary = <HabitCategory, CategoryChips>{
  // 7.1 — best-served category: workouts stack cleanly onto meals, arrivals
  // and getting changed. `put my shoes on` and `changed into my kit` share the
  // `gear` family deliberately: they are the same insight — the preparation
  // step is the real trigger — and should never take two of four slots.
  HabitCategory.exercise: CategoryChips(
    cues: <StarterChip>[
      StarterChip(
        'after breakfast',
        CueType.event,
        0.70,
        'breakfast',
        dayparts: _earlyAndMorning,
      ),
      StarterChip(
        'got home',
        CueType.event,
        0.70,
        'got-home',
        dayparts: _afternoonAndEvening,
      ),
      StarterChip('put my shoes on', CueType.event, 0.65, 'gear'),
      StarterChip('changed into my kit', CueType.event, 0.60, 'gear'),
      StarterChip(
        'after coffee',
        CueType.event,
        0.55,
        'coffee',
        dayparts: _earlyAndMorning,
      ),
      StarterChip(
        'before dinner',
        CueType.event,
        0.50,
        'dinner',
        dayparts: _justEvening,
      ),
      StarterChip(
        'first thing up',
        CueType.time,
        0.60,
        'woke',
        dayparts: _justEarly,
      ),
      StarterChip(
        'lunch break',
        CueType.time,
        0.55,
        'lunch',
        dayparts: _justMidday,
      ),
      StarterChip('walked past the gym', CueType.location, 0.45, 'gym-sight'),
      StarterChip('felt restless', CueType.internal, 0.50, 'restless'),
      StarterChip('had energy', CueType.internal, 0.40, 'energy'),
      StarterChip(
        'partner was going',
        CueType.social,
        0.35,
        'social',
        conditional: true,
      ),
    ],
    frictions: <FrictionChip>[
      FrictionChip('just forgot', FrictionType.forgot),
      FrictionChip('ran out of time', FrictionType.time),
      FrictionChip('too tired', FrictionType.energy),
      FrictionChip('was too sore', FrictionType.energy),
      FrictionChip('something came up', FrictionType.competing),
      FrictionChip("gear wasn't ready", FrictionType.environment),
      FrictionChip('weather was bad', FrictionType.environment),
      FrictionChip("didn't feel like it", FrictionType.motivation),
    ],
  ),

  // 7.2 — where internal cues are most often the true answer. growth-engine §5
  // exempts internal cues from the convergence penalty explicitly, so internal
  // priors here are the highest in the library and the non-event floor does
  // real work rather than acting as a formality.
  HabitCategory.meditation: CategoryChips(
    cues: <StarterChip>[
      StarterChip(
        'after morning coffee',
        CueType.event,
        0.65,
        'coffee',
        dayparts: _earlyAndMorning,
      ),
      StarterChip(
        'got out of bed',
        CueType.event,
        0.60,
        'woke',
        dayparts: _justEarly,
        strict: true,
      ),
      StarterChip(
        'before starting work',
        CueType.event,
        0.55,
        'work-start',
        dayparts: _justMorning,
      ),
      StarterChip(
        'closed my laptop',
        CueType.event,
        0.55,
        'work-end',
        dayparts: _justEvening,
      ),
      StarterChip(
        'after brushing teeth',
        CueType.event,
        0.50,
        'teeth',
        dayparts: _earlyAndNight,
      ),
      StarterChip('felt stressed', CueType.internal, 0.60, 'stressed'),
      StarterChip('felt scattered', CueType.internal, 0.45, 'scattered'),
      StarterChip("couldn't settle", CueType.internal, 0.40, 'settle'),
      StarterChip(
        'before bed',
        CueType.time,
        0.55,
        'bed',
        dayparts: _justNight,
      ),
      StarterChip(
        'first thing up',
        CueType.time,
        0.55,
        'woke',
        dayparts: _justEarly,
      ),
      StarterChip('cushion was out', CueType.location, 0.45, 'cushion'),
      StarterChip(
        'partner was sitting',
        CueType.social,
        0.30,
        'social',
        conditional: true,
      ),
    ],
    frictions: <FrictionChip>[
      FrictionChip('just forgot', FrictionType.forgot),
      FrictionChip('ran out of time', FrictionType.time),
      FrictionChip('nowhere quiet', FrictionType.environment),
      FrictionChip('too tired', FrictionType.energy),
      FrictionChip("couldn't sit still", FrictionType.energy),
      FrictionChip('something came up', FrictionType.competing),
      FrictionChip("didn't feel like it", FrictionType.motivation),
      FrictionChip('felt pointless', FrictionType.motivation),
    ],
  ),

  // 7.3 — strongly night-loaded, so the daypart term is unusually decisive: an
  // 08:00 reading log and a 23:00 one produce almost disjoint sets. The honest
  // competitor is the phone, which shows up on the friction side.
  HabitCategory.reading: CategoryChips(
    cues: <StarterChip>[
      StarterChip(
        'got into bed',
        CueType.event,
        0.75,
        'bed-in',
        dayparts: _justNight,
        strict: true,
      ),
      StarterChip(
        'after dinner',
        CueType.event,
        0.55,
        'dinner',
        dayparts: _justEvening,
      ),
      StarterChip(
        'put my phone down',
        CueType.event,
        0.50,
        'phone',
        dayparts: _eveningAndNight,
      ),
      StarterChip(
        'with morning coffee',
        CueType.event,
        0.50,
        'coffee',
        dayparts: _earlyAndMorning,
      ),
      StarterChip(
        'finished the dishes',
        CueType.event,
        0.40,
        'chores',
        dayparts: _justEvening,
      ),
      StarterChip('stuck waiting', CueType.event, 0.35, 'waiting'),
      StarterChip(
        'before bed',
        CueType.time,
        0.60,
        'bed',
        dayparts: _justNight,
      ),
      StarterChip(
        'lunch break',
        CueType.time,
        0.40,
        'lunch',
        dayparts: _justMidday,
      ),
      StarterChip('book was out', CueType.location, 0.45, 'book-sight'),
      StarterChip(
        'sat in my chair',
        CueType.location,
        0.40,
        'chair',
        dayparts: _eveningAndNight,
      ),
      StarterChip(
        'wanted to wind down',
        CueType.internal,
        0.50,
        'wind-down',
        dayparts: _eveningAndNight,
      ),
      StarterChip(
        'on my commute',
        CueType.location,
        0.50,
        'commute',
        dayparts: _morningAndEvening,
        conditional: true,
      ),
    ],
    frictions: <FrictionChip>[
      FrictionChip('just forgot', FrictionType.forgot),
      FrictionChip('no time', FrictionType.time),
      FrictionChip('too tired', FrictionType.energy),
      FrictionChip('fell asleep first', FrictionType.energy),
      FrictionChip('scrolled instead', FrictionType.competing),
      FrictionChip('watched TV instead', FrictionType.competing),
      FrictionChip("book wasn't nearby", FrictionType.environment),
      FrictionChip("didn't feel like it", FrictionType.motivation),
    ],
  ),

  // 7.4 — the one category where an internal cue is arguably the *ideal*
  // design rather than a tolerated one. `after meditating` unlocks from habit
  // metadata rather than typing: cross-habit stacking is the most valuable cue
  // the app can propose, because no generic advice can make it.
  HabitCategory.journaling: CategoryChips(
    cues: <StarterChip>[
      StarterChip(
        'after morning coffee',
        CueType.event,
        0.60,
        'coffee',
        dayparts: _earlyAndMorning,
      ),
      StarterChip(
        'got into bed',
        CueType.event,
        0.55,
        'bed-in',
        dayparts: _justNight,
        strict: true,
      ),
      StarterChip(
        'closed my laptop',
        CueType.event,
        0.50,
        'work-end',
        dayparts: _justEvening,
      ),
      StarterChip('sat down with tea', CueType.event, 0.45, 'tea'),
      StarterChip(
        'before bed',
        CueType.time,
        0.55,
        'bed',
        dayparts: _justNight,
      ),
      StarterChip(
        'end of the day',
        CueType.time,
        0.45,
        'eod',
        dayparts: _eveningAndNight,
      ),
      StarterChip('notebook was out', CueType.location, 0.45, 'book-sight'),
      StarterChip('something felt off', CueType.internal, 0.55, 'off'),
      StarterChip('felt overwhelmed', CueType.internal, 0.50, 'overwhelmed'),
      StarterChip(
        'after a hard day',
        CueType.internal,
        0.50,
        'hard-day',
        dayparts: _eveningAndNight,
      ),
      StarterChip(
        'after meditating',
        CueType.event,
        0.40,
        'after-meditate',
        conditional: true,
      ),
      StarterChip(
        'wrote my to-do list',
        CueType.event,
        0.35,
        'todo',
        dayparts: _earlyAndMorning,
        conditional: true,
      ),
    ],
    frictions: <FrictionChip>[
      FrictionChip('just forgot', FrictionType.forgot),
      FrictionChip('ran out of time', FrictionType.time),
      FrictionChip('too tired', FrictionType.energy),
      FrictionChip('something came up', FrictionType.competing),
      FrictionChip("notebook wasn't out", FrictionType.environment),
      FrictionChip('nothing to say', FrictionType.motivation),
      FrictionChip("didn't feel like it", FrictionType.motivation),
    ],
  ),

  // 7.5 — where the "not the routine" rule bites hardest: `refilled my bottle`
  // feels like a cue and is actually the behavior. Also the most
  // daypart-neutral category, so priors and type do nearly all the work.
  //
  // `felt thirsty` is the honest answer and must be tappable, even though a
  // hydration habit cued by thirst is arguably the habit failing — the app
  // should not editorialise in the chip set. A converged `thirsty` cue is
  // instead a good candidate for an insight proposing an earlier anchor.
  HabitCategory.hydration: CategoryChips(
    cues: <StarterChip>[
      StarterChip('before each meal', CueType.event, 0.65, 'meal'),
      StarterChip('after a bathroom trip', CueType.event, 0.60, 'bathroom'),
      StarterChip(
        'with my coffee',
        CueType.event,
        0.50,
        'coffee',
        dayparts: _earlyAndMorning,
      ),
      StarterChip(
        'after lunch',
        CueType.event,
        0.45,
        'lunch',
        dayparts: _middayAndAfternoon,
      ),
      StarterChip(
        'finished a call',
        CueType.event,
        0.40,
        'call',
        dayparts: _workingHours,
      ),
      StarterChip('sat at my desk', CueType.location, 0.60, 'desk'),
      StarterChip('saw my bottle', CueType.location, 0.55, 'bottle-sight'),
      StarterChip('walked into the kitchen', CueType.location, 0.45, 'kitchen'),
      StarterChip(
        'first thing up',
        CueType.time,
        0.50,
        'woke',
        dayparts: _justEarly,
      ),
      StarterChip('after a workout', CueType.event, 0.40, 'post-workout'),
      StarterChip('felt thirsty', CueType.internal, 0.55, 'thirsty'),
      StarterChip('mouth felt dry', CueType.internal, 0.40, 'thirsty'),
    ],
    frictions: <FrictionChip>[
      FrictionChip('just forgot', FrictionType.forgot),
      FrictionChip('lost track of it', FrictionType.forgot),
      FrictionChip('too busy', FrictionType.time),
      FrictionChip('too tired', FrictionType.energy),
      FrictionChip('out all day', FrictionType.competing),
      FrictionChip('bottle was empty', FrictionType.environment),
      FrictionChip("bottle wasn't with me", FrictionType.environment),
      // Deliberately motivation rather than a valid reason: for a deliberate
      // hydration habit, waiting for thirst is the loop failing, and routing it
      // to the reward-problem intervention is more useful than accepting it.
      FrictionChip("didn't feel thirsty", FrictionType.motivation),
    ],
  ),

  // 7.6 — unusually well served by location cues. `saw the pile` is the most
  // concrete chip in the library and the one most likely to be literally true.
  HabitCategory.tidying: CategoryChips(
    cues: <StarterChip>[
      StarterChip(
        'after dinner',
        CueType.event,
        0.60,
        'dinner',
        dayparts: _justEvening,
      ),
      StarterChip(
        'got home',
        CueType.event,
        0.55,
        'got-home',
        dayparts: _afternoonAndEvening,
      ),
      StarterChip(
        'while the coffee brews',
        CueType.event,
        0.50,
        'hot-drink',
        dayparts: _earlyAndMorning,
      ),
      StarterChip('waiting for the kettle', CueType.event, 0.40, 'hot-drink'),
      StarterChip(
        'finished the dishes',
        CueType.event,
        0.40,
        'dishes',
        dayparts: _justEvening,
      ),
      StarterChip(
        'before bed',
        CueType.time,
        0.50,
        'bed',
        dayparts: _justNight,
      ),
      StarterChip(
        'sunday morning',
        CueType.time,
        0.35,
        'weekly',
        dayparts: _justMorning,
      ),
      StarterChip('saw the pile', CueType.location, 0.55, 'pile'),
      StarterChip('walked into the room', CueType.location, 0.40, 'room'),
      StarterChip('felt cluttered', CueType.internal, 0.50, 'cluttered'),
      StarterChip("couldn't focus", CueType.internal, 0.45, 'focus'),
      StarterChip(
        'before people come over',
        CueType.event,
        0.40,
        'guests',
        conditional: true,
      ),
    ],
    frictions: <FrictionChip>[
      FrictionChip('just forgot', FrictionType.forgot),
      FrictionChip('ran out of time', FrictionType.time),
      FrictionChip('ran late', FrictionType.time),
      FrictionChip('too tired', FrictionType.energy),
      FrictionChip('something came up', FrictionType.competing),
      FrictionChip('nowhere to put things', FrictionType.environment),
      FrictionChip('too much to face', FrictionType.motivation),
      FrictionChip("didn't feel like it", FrictionType.motivation),
    ],
  ),

  // 7.7 — phone-mediated for most users, which makes `picked up my phone` an
  // honest and unusually actionable cue, and makes the phone the main
  // competitor. `on my commute` carries a high prior and is still conditional:
  // the best chip in the set for the people it fits, pure noise for everyone
  // else.
  HabitCategory.languagePractice: CategoryChips(
    cues: <StarterChip>[
      StarterChip(
        'with morning coffee',
        CueType.event,
        0.55,
        'coffee',
        dayparts: _earlyAndMorning,
      ),
      StarterChip(
        'after dinner',
        CueType.event,
        0.50,
        'dinner',
        dayparts: _justEvening,
      ),
      StarterChip('picked up my phone', CueType.event, 0.45, 'phone'),
      StarterChip(
        'got into bed',
        CueType.event,
        0.45,
        'bed-in',
        dayparts: _justNight,
        strict: true,
      ),
      StarterChip('waiting in line', CueType.event, 0.40, 'waiting'),
      StarterChip(
        'after brushing teeth',
        CueType.event,
        0.35,
        'teeth',
        dayparts: _earlyAndNight,
      ),
      StarterChip(
        'lunch break',
        CueType.time,
        0.55,
        'lunch',
        dayparts: _justMidday,
      ),
      StarterChip(
        'before bed',
        CueType.time,
        0.50,
        'bed',
        dayparts: _justNight,
      ),
      StarterChip(
        'sat at my desk',
        CueType.location,
        0.45,
        'desk',
        dayparts: _workingHours,
      ),
      StarterChip('wanted a break', CueType.internal, 0.45, 'break'),
      StarterChip(
        'on my commute',
        CueType.location,
        0.55,
        'commute',
        dayparts: _morningAndEvening,
        conditional: true,
      ),
      StarterChip(
        'lesson coming up',
        CueType.event,
        0.35,
        'lesson',
        conditional: true,
      ),
    ],
    frictions: <FrictionChip>[
      FrictionChip('just forgot', FrictionType.forgot),
      FrictionChip('no time', FrictionType.time),
      FrictionChip('too tired', FrictionType.energy),
      FrictionChip('something came up', FrictionType.competing),
      FrictionChip('phone was dead', FrictionType.environment),
      FrictionChip("didn't feel like it", FrictionType.motivation),
      FrictionChip('felt like a chore', FrictionType.motivation),
    ],
  ),

  // 7.8 — the one category where a location cue plausibly outranks everything:
  // an instrument left visible rather than in its case is the canonical "make
  // it obvious" intervention. `heard a song` is filed as `event` under the §5.5
  // convention — something happened in the world, not in the user's head. Filed
  // as `internal` it would wrongly earn the convergence exemption.
  HabitCategory.instrument: CategoryChips(
    cues: <StarterChip>[
      StarterChip('it was left out', CueType.location, 0.60, 'sight'),
      StarterChip(
        'after dinner',
        CueType.event,
        0.55,
        'dinner',
        dayparts: _justEvening,
      ),
      StarterChip(
        'got home',
        CueType.event,
        0.55,
        'got-home',
        dayparts: _afternoonAndEvening,
      ),
      StarterChip('case was open', CueType.location, 0.45, 'sight'),
      StarterChip(
        'with morning coffee',
        CueType.event,
        0.40,
        'coffee',
        dayparts: _earlyAndMorning,
      ),
      StarterChip('heard a song', CueType.event, 0.40, 'song'),
      StarterChip('finished my chores', CueType.event, 0.35, 'chores'),
      StarterChip(
        'end of the day',
        CueType.time,
        0.45,
        'eod',
        dayparts: _eveningAndNight,
      ),
      StarterChip(
        'lunch break',
        CueType.time,
        0.35,
        'lunch',
        dayparts: _justMidday,
      ),
      StarterChip('felt like playing', CueType.internal, 0.50, 'felt-like'),
      StarterChip(
        'kids were asleep',
        CueType.event,
        0.40,
        'kids',
        dayparts: _justNight,
        conditional: true,
      ),
      StarterChip(
        'lesson coming up',
        CueType.event,
        0.35,
        'lesson',
        conditional: true,
      ),
    ],
    frictions: <FrictionChip>[
      FrictionChip('just forgot', FrictionType.forgot),
      FrictionChip('no time', FrictionType.time),
      FrictionChip('too tired', FrictionType.energy),
      FrictionChip('fingers were sore', FrictionType.energy),
      FrictionChip('something came up', FrictionType.competing),
      FrictionChip('it was put away', FrictionType.environment),
      FrictionChip('too late for noise', FrictionType.environment),
      FrictionChip("didn't feel like it", FrictionType.motivation),
    ],
  ),

  // 7.9 — the most event-dominated category, and the one where a cue failure
  // is usually an *upstream* failure. `after a workout` leads almost every set,
  // which is correct but carries the risk named on `skipped my workout` below.
  HabitCategory.stretching: CategoryChips(
    cues: <StarterChip>[
      StarterChip('after a workout', CueType.event, 0.75, 'post-workout'),
      StarterChip(
        'got out of bed',
        CueType.event,
        0.60,
        'woke',
        dayparts: _justEarly,
        strict: true,
      ),
      StarterChip('after a shower', CueType.event, 0.50, 'shower'),
      StarterChip(
        'left my desk',
        CueType.event,
        0.50,
        'desk-up',
        dayparts: _workingHours,
      ),
      StarterChip(
        'while watching TV',
        CueType.event,
        0.45,
        'tv',
        dayparts: _eveningAndNight,
      ),
      StarterChip('after a walk', CueType.event, 0.40, 'post-walk'),
      StarterChip(
        'before bed',
        CueType.time,
        0.55,
        'bed',
        dayparts: _justNight,
      ),
      StarterChip(
        'first thing up',
        CueType.time,
        0.50,
        'woke',
        dayparts: _justEarly,
      ),
      StarterChip('mat was out', CueType.location, 0.45, 'mat'),
      StarterChip('felt stiff', CueType.internal, 0.60, 'stiff'),
      StarterChip('back was aching', CueType.internal, 0.45, 'ache'),
      StarterChip(
        'between meetings',
        CueType.event,
        0.35,
        'meetings',
        dayparts: _workingHours,
        conditional: true,
      ),
    ],
    frictions: <FrictionChip>[
      FrictionChip('just forgot', FrictionType.forgot),
      // Deliberately forgot, not competing: the anchor habit never fired, so
      // the cue never fired. The fix belongs upstream on the workout, and a
      // friction-concentration insight should say so rather than proposing a
      // new stretching cue.
      FrictionChip('skipped my workout', FrictionType.forgot),
      FrictionChip('no time', FrictionType.time),
      FrictionChip('too tired', FrictionType.energy),
      FrictionChip('something came up', FrictionType.competing),
      FrictionChip('no room for it', FrictionType.environment),
      FrictionChip("didn't feel like it", FrictionType.motivation),
      FrictionChip('felt fine today', FrictionType.motivation),
    ],
  ),

  // 7.10 — cue and routine are nearly simultaneous, so essentially every real
  // cue is an event stack and the type ceiling binds in most sets. `before bed`
  // is authored `evening · night` rather than night-only for exactly that
  // reason: without it, evening sets have only one non-event chip available and
  // the diversity guard has nothing to reach for.
  HabitCategory.supplements: CategoryChips(
    cues: <StarterChip>[
      StarterChip(
        'with breakfast',
        CueType.event,
        0.75,
        'breakfast',
        dayparts: _earlyAndMorning,
      ),
      StarterChip(
        'with my coffee',
        CueType.event,
        0.55,
        'coffee',
        dayparts: _earlyAndMorning,
      ),
      StarterChip(
        'with dinner',
        CueType.event,
        0.55,
        'dinner',
        dayparts: _justEvening,
      ),
      StarterChip(
        'after brushing teeth',
        CueType.event,
        0.50,
        'teeth',
        dayparts: _earlyAndNight,
      ),
      StarterChip(
        'after lunch',
        CueType.event,
        0.45,
        'lunch',
        dayparts: _justMidday,
      ),
      StarterChip('sat down to eat', CueType.event, 0.40, 'dinner'),
      StarterChip(
        'packed my bag',
        CueType.event,
        0.35,
        'bag',
        dayparts: _earlyAndMorning,
      ),
      StarterChip('filled my water', CueType.event, 0.35, 'water'),
      StarterChip('saw the bottle', CueType.location, 0.55, 'sight'),
      StarterChip(
        'first thing up',
        CueType.time,
        0.55,
        'woke',
        dayparts: _justEarly,
      ),
      StarterChip(
        'before bed',
        CueType.time,
        0.45,
        'bed',
        dayparts: _eveningAndNight,
      ),
      StarterChip('felt run down', CueType.internal, 0.35, 'run-down'),
    ],
    frictions: <FrictionChip>[
      FrictionChip('just forgot', FrictionType.forgot),
      FrictionChip('out of routine', FrictionType.forgot),
      FrictionChip('ran out the door', FrictionType.time),
      FrictionChip('too tired', FrictionType.energy),
      FrictionChip('something came up', FrictionType.competing),
      FrictionChip("wasn't home", FrictionType.environment),
      FrictionChip('bottle was empty', FrictionType.environment),
      FrictionChip('not sure they help', FrictionType.motivation),
    ],
  ),

  // 7.11 — the most flexible category, which sounds like an advantage and is
  // actually the problem: with no natural anchor, walking habits drift, so the
  // library leans hard on meal and arrival stacks. `sun was out` is the
  // clearest §5.5 ambient case — filed as `event` with a low prior so it rarely
  // leads.
  HabitCategory.walking: CategoryChips(
    cues: <StarterChip>[
      StarterChip(
        'after lunch',
        CueType.event,
        0.65,
        'lunch',
        dayparts: _middayAndAfternoon,
      ),
      StarterChip(
        'got home',
        CueType.event,
        0.60,
        'got-home',
        dayparts: _afternoonAndEvening,
      ),
      StarterChip(
        'after dinner',
        CueType.event,
        0.60,
        'dinner',
        dayparts: _justEvening,
      ),
      StarterChip('put my shoes on', CueType.event, 0.45, 'shoes'),
      StarterChip('started a podcast', CueType.event, 0.40, 'podcast'),
      StarterChip(
        'sun was out',
        CueType.event,
        0.35,
        'weather',
        dayparts: _workingHours,
      ),
      StarterChip('shoes by the door', CueType.location, 0.40, 'shoes'),
      StarterChip(
        'lunch break',
        CueType.time,
        0.45,
        'lunch',
        dayparts: _justMidday,
      ),
      StarterChip('needed fresh air', CueType.internal, 0.55, 'air'),
      StarterChip('felt stuck', CueType.internal, 0.50, 'stuck'),
      StarterChip(
        'the dog needed out',
        CueType.event,
        0.55,
        'dog',
        conditional: true,
      ),
      StarterChip(
        'partner suggested it',
        CueType.social,
        0.35,
        'social',
        conditional: true,
      ),
    ],
    frictions: <FrictionChip>[
      FrictionChip('just forgot', FrictionType.forgot),
      FrictionChip('no time', FrictionType.time),
      FrictionChip('too tired', FrictionType.energy),
      FrictionChip('something came up', FrictionType.competing),
      FrictionChip('stayed at my desk', FrictionType.competing),
      FrictionChip('weather was bad', FrictionType.environment),
      FrictionChip("shoes weren't handy", FrictionType.environment),
      FrictionChip("didn't feel like it", FrictionType.motivation),
    ],
  ),

  // 7.12 — nearly everything is night, so the daypart term barely
  // discriminates and a set is effectively determined by priors alone. The
  // interesting axis is event vs internal: a sleep routine cued by `eyes got
  // heavy` is not a designed routine at all, it is going to bed when tired.
  //
  // `wind-down alarm` is the one permitted exception to the no-app-as-cue rule
  // (§2): it is the user's own alarm, external to this app. A habit cued by
  // their alarm is autonomous; one cued by our nudge is not, and growth-engine
  // §6 depends on telling them apart.
  HabitCategory.sleepRoutine: CategoryChips(
    cues: <StarterChip>[
      StarterChip(
        'put my phone down',
        CueType.event,
        0.60,
        'phone',
        dayparts: _eveningAndNight,
      ),
      StarterChip(
        'brushed my teeth',
        CueType.event,
        0.55,
        'teeth',
        dayparts: _justNight,
      ),
      StarterChip(
        'got into bed',
        CueType.event,
        0.55,
        'bed-in',
        dayparts: _justNight,
        strict: true,
      ),
      StarterChip(
        'finished the episode',
        CueType.event,
        0.50,
        'tv',
        dayparts: _eveningAndNight,
      ),
      StarterChip(
        'finished the dishes',
        CueType.event,
        0.40,
        'dishes',
        dayparts: _justEvening,
      ),
      StarterChip(
        '10pm hit',
        CueType.time,
        0.50,
        'clock',
        dayparts: _justNight,
      ),
      StarterChip(
        'wind-down alarm',
        CueType.time,
        0.45,
        'alarm',
        dayparts: _justNight,
      ),
      StarterChip(
        'lights went low',
        CueType.event,
        0.35,
        'lights',
        dayparts: _justNight,
      ),
      StarterChip(
        'left the living room',
        CueType.location,
        0.40,
        'room',
        dayparts: _justNight,
      ),
      StarterChip(
        'eyes got heavy',
        CueType.internal,
        0.55,
        'tired',
        dayparts: _eveningAndNight,
      ),
      StarterChip(
        'felt wired',
        CueType.internal,
        0.35,
        'wired',
        dayparts: _justNight,
      ),
      StarterChip(
        'after my evening walk',
        CueType.event,
        0.35,
        'walk',
        dayparts: _justEvening,
        conditional: true,
      ),
    ],
    frictions: <FrictionChip>[
      FrictionChip('just forgot', FrictionType.forgot),
      FrictionChip('lost track of time', FrictionType.time),
      FrictionChip("wasn't tired yet", FrictionType.energy),
      FrictionChip('too wired', FrictionType.energy),
      // Both competing, but pointing at very different fixes — one is a
      // protected-slot problem, the other a target-frequency problem. Worth
      // splitting if the diagnosis data justifies it.
      FrictionChip('kept scrolling', FrictionType.competing),
      FrictionChip('was out late', FrictionType.competing),
      FrictionChip('TV was still on', FrictionType.environment),
      FrictionChip("didn't feel like it", FrictionType.motivation),
    ],
  ),
};

/// The cue chips for [category], falling back to the global pool.
///
/// A habit with no category is not an error — `Habit.category` is nullable by
/// design, and the global pool exists precisely so that such a habit still gets
/// a plausible first reflection, just a slightly weaker one.
List<StarterChip> cueChipsFor(HabitCategory? category) =>
    starterChipLibrary[category]?.cues ?? globalCueChips;

/// The friction chips for [category], falling back to the global pool.
List<FrictionChip> frictionChipsFor(HabitCategory? category) =>
    starterChipLibrary[category]?.frictions ?? globalFrictionChips;
