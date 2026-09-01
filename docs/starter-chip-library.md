# Habit App — Starter Chip Library

*Closes the open item in reflection-logic §8: "starter chip library needs real authoring per habit category." This is the content layer under §4 Chip mechanics, plus the rule deciding which four chips a user actually sees on their first reflection.*

**Contents:** 144 cue chips and 94 friction chips across 12 categories, a surfacing rule, and 24 worked examples generated from that rule.

---

## 0. What this is for

The first reflection is the only one with no history. Every later reflection ranks chips by recency-weighted frequency of the user's own past answers; the first has nothing to rank. So it's assembled from two sources:

1. **The designed cue**, pinned in slot 0 — which makes Validation a single tap (reflection-logic §3).
2. **Four starter chips** from this library, filtered by habit category and the time of day the completion was logged.

On screen: 1 pinned + 4 starter + `Something else` + `Can't remember` = 7 targets. That matches the cap of 5 content chips in §4, counting the designed cue as one of them.

Why this deserves authoring rather than a generic list: the first reflection disproportionately determines whether there's a second one. Two failure modes shape everything below.

- **Forced fit.** If none of the four chips is plausible, the honest user taps `Something else` and types — which the design says should be the exception — or, worse, taps the least-wrong chip and manufactures false data. `Can't remember` exists to absorb genuine non-recall; it should not be absorbing "none of these are me."
- **Event monoculture.** Event cues rank highest because habit stacking is the most reliable anchor, and that preference is right. But if all four visible chips are event-type, a user whose habit is genuinely internally cued has no true answer available — and the engine never learns to apply the internal-cue convergence exemption (growth-engine §5). The rule below guarantees at least one non-event chip in every set.

---

## 1. Chip record

```
StarterChip {
  id
  label:        string          // what the user sees
  category:     habit category  // or "global"
  cue_type:     event | time | location | internal | social
  dayparts:     [daypart] | any // where this cue plausibly lives
  strict:       bool            // daypart is physically required, not merely typical
  prior:        0.0–1.0         // how commonly this cues this category
  family:       string          // near-duplicate group; at most one per set
  conditional:  bool            // presupposes a life circumstance — held back by default
}
```

`family` stops the set from spending two of four slots on `after breakfast` and `with breakfast`. `conditional` is the anti-presupposition mechanism in §3.

---

## 2. Writing rules

| Rule | Test |
|---|---|
| **Tap-readable** | ≤ 24 characters — that's the binding constraint on a chip. Usually 3 words, occasionally 4. |
| **The user's voice, not the app's** | `after breakfast`, never `Following morning meal`. First person and past tense where a verb is needed: `put my shoes on`, `felt restless`. Lowercase throughout. |
| **Concrete over abstract** | `put my shoes on` beats `felt motivated`. A chip names something that observably happened. Internal-state chips are the exception, and are written as plainly as possible: `felt stiff`, not `experienced discomfort`. |
| **No app-as-cue** | Never `the reminder`, `the notification`, `opened the app`. The product thesis is that the app is *not* the cue (growth-engine §6); offering "the app told me" as an answer would measure the failure mode and file it as a cue. One exception: a user's own pre-existing alarm is theirs, not ours — see the sleep-routine note. |
| **No lifestyle presupposition** | See §3. |
| **Not the routine** | `refilled my bottle` is the hydration behavior, not its cue. Easy to write by accident wherever cue and routine sit close together. |

---

## 3. The conditional pool

`after dropping the kids off` is an excellent cue for the people it fits and a small insult to everyone else. A childless user seeing it in their default four learns that the app has a picture of who they are, and it isn't them. Same for `on my commute`, `kids were asleep`, `the dog needed out`, `partner was going`.

So: chips that presuppose a life circumstance are authored into the library, marked `conditional`, and **excluded from the default set**. They unlock per-user on evidence —

- the user typed something mapping to that chip's family via `Something else`, **or**
- habit metadata implies it (the habit is *walk the dog*; the user has an active meditation habit), **or**
- they picked it once while unlocked, after which it lives in the normal recency-weighted pool.

Once unlocked a conditional chip competes on score like any other. Nothing is lost; it's a question of what the app assumes about a stranger.

The bar is lower than "universal." `walked past the gym` presupposes a gym and is still a default in the exercise category, because someone logging a workout plausibly has somewhere they work out. The test is whether the chip reads as *about someone else's life* to a typical user of that category.

**Where the line falls on work.** Paid work of some kind is near-universal among this app's users, so work-adjacent chips — `closed my laptop`, `before starting work`, `sat at my desk`, `finished a call` — are defaults rather than conditionals. What *is* conditional is a chip assuming a particular shape of work: `between meetings` ⚑ presupposes a calendar full of them. The same reasoning retired `got home from work` in favour of the plain `got home`, which costs nothing and assumes nothing. This is a judgement call, and the most likely place for the conditional line to be redrawn once there's data.

Conditional chips are marked ⚑ below.

---

## 4. Dayparts

Six buckets, keyed off the **completion timestamp**, not the check-in time. The evening check-in asking about a 07:00 run must rank against 07:00, or every morning habit gets evening chips.

| Bucket | Window |
|---|---|
| `early` | 04:00 – 07:59 |
| `morning` | 08:00 – 10:59 |
| `midday` | 11:00 – 13:59 |
| `afternoon` | 14:00 – 17:59 |
| `evening` | 18:00 – 21:29 |
| `night` | 21:30 – 03:59 |

**Adjacency is linear and does not wrap.** `night` is adjacent to `evening` only, not to `early`. The wrap is tempting — 02:00 and 05:00 really are neighbours — but `night` spans six and a half hours and most logs in it are closer to 22:00 than to 03:00, so the wrap mostly served to leak `with morning coffee` into 21:50 sets. The 6.5-hour night bucket is the underlying problem and is flagged in §9.

`any` means daypart-neutral.

---

## 5. The surfacing rule

### 5.1 Score

```
score = prior × daypart_factor + type_bonus
```

| Term | Value |
|---|---|
| `prior` | 0.0 – 1.0, authored per chip per category |
| `daypart_factor` | logged daypart in `dayparts` **1.0** · `any` 0.8 · adjacent 0.35 · otherwise **0.0** |
| `type_bonus` | event **+0.30** · location +0.15 · time +0.10 · internal +0.05 · social 0.00 |

**Daypart is multiplicative, not additive, and that's the load-bearing choice.** An additive penalty lets a high-prior chip survive anywhere: `after lunch` in the walking category (prior 0.65) would still rank second in an 18:30 set, because a large prior outruns any fixed penalty. Multiplying zeroes the prior on a mismatch, leaving `score = type_bonus` — at most 0.30, which sits below the score floor by construction. Mismatched chips therefore self-eliminate without a special rule, and the floor does the filtering.

The event bonus at +0.30 is the whole "small ranking preference for habit stacking" from reflection-logic §4, made numeric. It's roughly a third of the prior range: enough that a moderately common event cue beats a very common time cue, not so much that it steamrolls a category where the honest answer is internal.

Max possible score is 1.30. **Score floor: 0.35.**

### 5.2 Hard filters, before scoring

1. Drop `conditional` chips not unlocked for this user (§3).
2. Drop chips whose `family` matches the designed cue's — it's already pinned in slot 0, and a duplicate wastes a slot and looks like a bug.
3. Drop `strict` chips whose daypart doesn't match. `got into bed` must never appear against an 07:10 completion, whatever adjacency would give it.

### 5.3 Selection

Take chips in descending score — ties broken by type bonus, then prior, then authored order — subject to:

| Guard | Rule | Why |
|---|---|---|
| **Family uniqueness** | ≤ 1 chip per `family` | No `after breakfast` + `with breakfast` |
| **Type ceiling** | ≤ 3 chips of any one type | Prevents a monoculture set |
| **Non-event floor** | ≥ 1 non-event chip | Guarantees a true answer for internally-, time- or socially-cued users, and keeps the growth-engine §5 exemption reachable |
| **Event floor** | ≥ 2 event chips — **but only promoting chips scoring ≥ 0.60** | Leads with the most reliable anchor type, without forcing an implausible chip in |

The **promotion floor of 0.60** on the event guard matters more than it looks. Without it the guard will happily push `after dinner` into a 09:00 tidying set to satisfy its own arithmetic. A guard that forces in a chip nobody would tap is worse than the imbalance it was correcting, so the event floor yields when the library has nothing plausible — which happens, legitimately, for early-morning journaling and mid-morning tidying.

**Backfill and relaxation, in order:** if fewer than *n* chips clear the floor, backfill from the global pool (§6.1); if still short, relax the type ceiling. If it's *still* short, surface fewer chips. A short set beats a padded one — the forced-fit failure in §0 is the thing being avoided, and it doesn't stop being a failure because the app filled a slot.

### 5.4 When there is no designed cue

Journey A — tracking an existing habit — has no pinned cue; reverse-engineering one is the point. There, surface **5** starter chips, skip filter 5.2.2, and raise the non-event floor to **2**. Journey A's job is discovering a cue *type* the user hasn't named, and an event-heavy set biases that discovery toward the answer the app already prefers.

### 5.5 Ambient conditions — an authoring edge case

`sun was out`, `heard a song`, `it was raining` don't sit cleanly in the §4 taxonomy: external and observable, but not stacking onto a prior routine, and not a place. They're filed as **`event`**, because the taxonomy's operative split is external vs. internal and these are unambiguously external — which matters, since that split governs the convergence exemption. Filed as `internal` they'd wrongly earn it.

This is a mild abuse of the label. They carry low priors so they rarely lead a set, and a possible sixth cue type is raised in §9.

---

## 6. Global pools

### 6.1 Global cue chips (backfill for any category)

| Chip | Type | Dayparts | Prior | Family |
|---|---|---|---|---|
| after breakfast | event | early · morning | 0.55 | breakfast |
| after coffee | event | early · morning | 0.50 | coffee |
| got home | event | afternoon · evening | 0.50 | got-home |
| after dinner | event | evening | 0.50 | dinner |
| just woke up | time | early | 0.45 | woke |
| before bed | time | night | 0.45 | bed |
| lunch break | time | midday | 0.40 | lunch |
| felt like it | internal | any | 0.30 | felt-like |
| had a free moment | internal | any | 0.25 | free-moment |

`felt like it` sits deliberately near the floor. It's the honest answer often enough to be worth having, but it's low-information, and a set that leads with it teaches the engine nothing.

### 6.2 Global friction chips

`just forgot` · `no time` · `too tired` · `something came up` · `didn't feel like it` · `wasn't set up`

### 6.3 Friction ranking

Diagnosis surfaces **5** friction chips plus `Something else`. Simpler than the cue rule — friction has no meaningful daypart preference and no stacking equivalent — but with one hard guarantee:

> **Always surface at least one `forgot` chip and at least one `motivation` chip.**

Reflection-logic §4 stakes a claim on this split: forgetting is a cue failure, reluctance is a reward failure, they have opposite fixes, and most apps can't tell them apart because they never ask. The claim only pays off if both are always tappable. If a category's top 5 happened to be four environment chips and a time chip, the app would have quietly lost the distinction it says is its edge.

Otherwise: rank by category prior, cap at 2 per friction type, and admit weather chips only for outdoor-capable categories (exercise, walking).

## 7. The category libraries

Twelve categories. Each carries: cue chips with type, plausible dayparts and prior; per-category ranking notes where the general rule needs adjusting; two worked surfacing examples computed from the rule in §5; and friction chips for Diagnosis.

⚑ = conditional (§3), held out of the default set until unlocked.
Ⓢ = `strict` daypart (§5.2), filtered out entirely when the daypart doesn't match.


---

### 7.1 Exercise

Best-served category in the taxonomy: workouts stack cleanly onto meals, arrivals, and getting changed, and the gear-handling step (`put my shoes on`) is a real cue rather than a rationalisation. Priors lean event-heavy for good reason here.

| Chip | Type | Dayparts | Prior | Family |
|---|---|---|---|---|
| after breakfast | event | early · morning | 0.70 | breakfast |
| got home | event | afternoon · evening | 0.70 | got-home |
| put my shoes on | event | any | 0.65 | gear |
| changed into my kit | event | any | 0.60 | gear |
| after coffee | event | early · morning | 0.55 | coffee |
| before dinner | event | evening | 0.50 | dinner |
| first thing up | time | early | 0.60 | woke |
| lunch break | time | midday | 0.55 | lunch |
| walked past the gym | location | any | 0.45 | gym-sight |
| felt restless | internal | any | 0.50 | restless |
| had energy | internal | any | 0.40 | energy |
| partner was going ⚑ | social | any | 0.35 | social |

**Ranking notes.** `put my shoes on` and `changed into my kit` share a family deliberately — they're the same insight (the preparation step is the real trigger) and should never occupy two of four slots. Both are daypart-neutral, so one of them appears in nearly every set, which is desirable: for a struggling exerciser the most actionable cue in the library is the one naming a two-second action.

**Worked example A — logged 07:10 (`early`), designed cue in family `breakfast`.**
→ `after coffee` (0.85) · `put my shoes on` (0.82) · `first thing up` (0.70) · `walked past the gym` (0.51)
Two events, one time, one location — the guards are satisfied without intervention.

**Worked example B — logged 18:40 (`evening`), no designed cue — Journey A, 5 chips, non-event floor 2.**
→ `got home` (1.00) · `put my shoes on` (0.82) · `before dinner` (0.80) · `walked past the gym` (0.51) · `felt restless` (0.45)
Three events hits the type ceiling exactly; the location and internal chips satisfy the raised non-event floor.

**Friction chips**

| Chip | Type |
|---|---|
| just forgot | forgot |
| ran out of time | time |
| too tired | energy |
| was too sore | energy |
| something came up | competing |
| gear wasn't ready | environment |
| weather was bad | environment |
| didn't feel like it | motivation |


---

### 7.2 Meditation

The category where internal cues are most often the true answer, and where suppressing them would do the most damage. `felt stressed` is not a badly-designed loop — growth-engine §5 exempts internal cues from the convergence penalty explicitly — so internal priors here are the highest in the library, and the non-event floor does real work rather than acting as a formality.

| Chip | Type | Dayparts | Prior | Family |
|---|---|---|---|---|
| after morning coffee | event | early · morning | 0.65 | coffee |
| got out of bed Ⓢ | event | early | 0.60 | woke |
| before starting work | event | morning | 0.55 | work-start |
| closed my laptop | event | evening | 0.55 | work-end |
| after brushing teeth | event | early · night | 0.50 | teeth |
| felt stressed | internal | any | 0.60 | stressed |
| felt scattered | internal | any | 0.45 | scattered |
| couldn't settle | internal | any | 0.40 | settle |
| before bed | time | night | 0.55 | bed |
| first thing up | time | early | 0.55 | woke |
| cushion was out | location | any | 0.45 | cushion |
| partner was sitting ⚑ | social | any | 0.30 | social |

**Ranking notes.** `got out of bed` is Ⓢ`early` — at 22:00 it isn't a plausible meditation cue, and letting it through on an adjacency bonus would read as a bug. `first thing up` shares its `woke` family, so the pair contributes at most one chip.

**Worked example A — logged 06:50 (`early`), designed cue in family `coffee`.**
→ `got out of bed` (0.90) · `after brushing teeth` (0.80) · `felt stressed` (0.53) · `cushion was out` (0.51)

**Worked example B — logged 22:10 (`night`), designed cue in family `bed`.**
→ `after brushing teeth` (0.80) · `felt stressed` (0.53) · `cushion was out` (0.51) · `closed my laptop` (0.49)
Two of the four are non-event, which is right for this category. Note that the `woke` family disappears for two different reasons: `got out of bed` is removed by the Ⓢ filter before scoring, while `first thing up` is simply scored out (0.10) because `early` is not adjacent to `night`.

**Friction chips**

| Chip | Type |
|---|---|
| just forgot | forgot |
| ran out of time | time |
| nowhere quiet | environment |
| too tired | energy |
| couldn't sit still | energy |
| something came up | competing |
| didn't feel like it | motivation |
| felt pointless | motivation |


---

### 7.3 Reading

Strongly night-loaded, which makes the daypart term unusually decisive: an 08:00 reading log and a 23:00 one produce almost disjoint sets. The honest competitor is the phone, which shows up on the friction side rather than the cue side.

| Chip | Type | Dayparts | Prior | Family |
|---|---|---|---|---|
| got into bed Ⓢ | event | night | 0.75 | bed-in |
| after dinner | event | evening | 0.55 | dinner |
| put my phone down | event | evening · night | 0.50 | phone |
| with morning coffee | event | early · morning | 0.50 | coffee |
| finished the dishes | event | evening | 0.40 | chores |
| stuck waiting | event | any | 0.35 | waiting |
| before bed | time | night | 0.60 | bed |
| lunch break | time | midday | 0.40 | lunch |
| book was out | location | any | 0.45 | book-sight |
| sat in my chair | location | evening · night | 0.40 | chair |
| wanted to wind down | internal | evening · night | 0.50 | wind-down |
| on my commute ⚑ | location | morning · evening | 0.50 | commute |

**Ranking notes.** `got into bed` is tied for the highest prior in the library (0.75, with `after a workout` and `with breakfast`) and is Ⓢ`night`: it dominates its daypart and is absent outside it. When the designed cue is `before bed` it still survives (different family) and outranks everything — which is a feature, since the two are meaningfully different anchors and separating them is exactly what a first reflection can do.

**Worked example A — logged 22:40 (`night`), designed cue in family `bed`.**
→ `got into bed` (1.05) · `put my phone down` (0.80) · `stuck waiting` (0.58) · `sat in my chair` (0.55)
`with morning coffee` scores 0.30 here and never appears: adjacency does not wrap, so morning cues do not leak into late night.

**Worked example B — logged 12:30 (`midday`), no designed cue — Journey A, 5 chips, non-event floor 2.**
→ `stuck waiting` (0.58) · `book was out` (0.51) · `lunch break` (0.50) · `after breakfast` (0.49) · `with morning coffee` (0.47)
Only four category chips clear the floor at midday, so `after breakfast` is pulled from the global pool (§6.1). Midday reading is a genuine authoring gap — flagged in §9.

**Friction chips**

| Chip | Type |
|---|---|
| just forgot | forgot |
| no time | time |
| too tired | energy |
| fell asleep first | energy |
| scrolled instead | competing |
| watched TV instead | competing |
| book wasn't nearby | environment |
| didn't feel like it | motivation |


---

### 7.4 Journaling

The one category where an internal cue is arguably the *ideal* design rather than a tolerated one — journaling triggered by `something felt off` is the habit working as intended, not a loop that failed to converge.

| Chip | Type | Dayparts | Prior | Family |
|---|---|---|---|---|
| after morning coffee | event | early · morning | 0.60 | coffee |
| got into bed Ⓢ | event | night | 0.55 | bed-in |
| closed my laptop | event | evening | 0.50 | work-end |
| sat down with tea | event | any | 0.45 | tea |
| before bed | time | night | 0.55 | bed |
| end of the day | time | evening · night | 0.45 | eod |
| notebook was out | location | any | 0.45 | book-sight |
| something felt off | internal | any | 0.55 | off |
| felt overwhelmed | internal | any | 0.50 | overwhelmed |
| after a hard day | internal | evening · night | 0.50 | hard-day |
| after meditating ⚑ | event | any | 0.40 | after-meditate |
| wrote my to-do list ⚑ | event | early · morning | 0.35 | todo |

**Ranking notes.** `after meditating` ⚑ unlocks from habit metadata rather than from typing: if the user has an active meditation habit it becomes available immediately. Cross-habit stacking is the most valuable cue the app can propose, because it's the one suggestion no generic advice can make, and it's cheap to detect.

**Worked example A — logged 07:30 (`early`), designed cue in family `coffee`.**
→ `sat down with tea` (0.66) · `notebook was out` (0.51) · `something felt off` (0.49) · `felt overwhelmed` (0.45)
Only one event chip survives at all: `closed my laptop` scores 0.30 — the bare type bonus, because a mismatched daypart zeroes the prior — and falls below the 0.35 floor. The event floor has nothing to promote and yields. Early-morning journaling is thin on event anchors in this library, which is an authoring gap rather than a ranking one.

**Worked example B — logged 22:50 (`night`), designed cue in family `bed`.**
→ `got into bed` (0.85) · `sat down with tea` (0.66) · `end of the day` (0.55) · `after a hard day` (0.55)
`after a hard day` and `end of the day` tie at 0.55 and are separated only by the type tie-break, which puts the time chip first. Note that only two events surface — the ceiling never binds here; `closed my laptop` (0.47) simply ranks seventh.

**Friction chips**

| Chip | Type |
|---|---|
| just forgot | forgot |
| ran out of time | time |
| too tired | energy |
| something came up | competing |
| notebook wasn't out | environment |
| nothing to say | motivation |
| didn't feel like it | motivation |


---

### 7.5 Hydration

Where the “not the routine” rule (§2) bites hardest: `refilled my bottle` and `poured a glass` feel like cues and are actually the behavior. Also the most daypart-neutral category in the library, so priors and type do nearly all the ranking work.

| Chip | Type | Dayparts | Prior | Family |
|---|---|---|---|---|
| before each meal | event | any | 0.65 | meal |
| after a bathroom trip | event | any | 0.60 | bathroom |
| with my coffee | event | early · morning | 0.50 | coffee |
| after lunch | event | midday · afternoon | 0.45 | lunch |
| finished a call | event | morning · midday · afternoon | 0.40 | call |
| sat at my desk | location | any | 0.60 | desk |
| saw my bottle | location | any | 0.55 | bottle-sight |
| walked into the kitchen | location | any | 0.45 | kitchen |
| first thing up | time | early | 0.50 | woke |
| after a workout | event | any | 0.40 | post-workout |
| felt thirsty | internal | any | 0.55 | thirsty |
| mouth felt dry | internal | any | 0.40 | thirsty |

**Ranking notes.** `felt thirsty` deserves a note. For most categories an internal cue is a legitimate design; for hydration, a habit cued by thirst is arguably the habit failing, since the point of a deliberate water habit is usually to drink *before* thirst. The app should not editorialise in the chip set — thirst is the honest answer and must be tappable — but a converged `thirsty` cue is a good candidate for a §6 insight proposing an earlier anchor.

**Worked example A — logged 09:30 (`morning`), designed cue in family `meal`.**
→ `with my coffee` (0.80) · `after a bathroom trip` (0.78) · `finished a call` (0.70) · `sat at my desk` (0.63)

**Worked example B — logged 20:15 (`evening`), no designed cue — Journey A, 5 chips, non-event floor 2.**
→ `before each meal` (0.82) · `after a bathroom trip` (0.78) · `sat at my desk` (0.63) · `after a workout` (0.62) · `saw my bottle` (0.59)
Three location chips — at the ceiling. Defensible for this category, where place genuinely is the cue, but worth watching: `sat at my desk`, `saw my bottle` and `walked into the kitchen` are distinct cues that a user may read as three ways of asking the same thing.

**Friction chips**

| Chip | Type |
|---|---|
| just forgot | forgot |
| lost track of it | forgot |
| too busy | time |
| too tired | energy |
| out all day | competing |
| bottle was empty | environment |
| bottle wasn't with me | environment |
| didn't feel thirsty | motivation |

*`didn't feel thirsty` is mapped to **motivation** rather than treated as a valid reason. That's a deliberate call: for a deliberate hydration habit, waiting for thirst is the loop failing, and routing it to the reward-problem intervention is more useful than accepting it.*


---

### 7.6 Tidying

Unusually well served by location cues — `saw the pile` is the most concrete chip in the library and the one most likely to be literally true. Also the category where the cue is most often a small dead interval (`waiting for the kettle`), which is useful for a first reflection to name because it reframes the habit as something that fits in gaps rather than requiring a block of time.

| Chip | Type | Dayparts | Prior | Family |
|---|---|---|---|---|
| after dinner | event | evening | 0.60 | dinner |
| got home | event | afternoon · evening | 0.55 | got-home |
| while the coffee brews | event | early · morning | 0.50 | hot-drink |
| waiting for the kettle | event | any | 0.40 | hot-drink |
| finished the dishes | event | evening | 0.40 | dishes |
| before bed | time | night | 0.50 | bed |
| sunday morning | time | morning | 0.35 | weekly |
| saw the pile | location | any | 0.55 | pile |
| walked into the room | location | any | 0.40 | room |
| felt cluttered | internal | any | 0.50 | cluttered |
| couldn't focus | internal | any | 0.45 | focus |
| before people come over ⚑ | event | any | 0.40 | guests |

**Ranking notes.** `while the coffee brews` and `waiting for the kettle` share the `hot-drink` family — same cue, different beverage — so exactly one appears, whichever fits the daypart better.

**Worked example A — logged 19:30 (`evening`), designed cue in family `dinner`.**
→ `got home` (0.85) · `finished the dishes` (0.70) · `waiting for the kettle` (0.62) · `saw the pile` (0.59)

**Worked example B — logged 09:00 (`morning`), no designed cue — Journey A, 5 chips, non-event floor 2.**
→ `while the coffee brews` (0.80) · `saw the pile` (0.59) · `walked into the room` (0.47) · `sunday morning` (0.45) · `felt cluttered` (0.45)
Only one event chip. `after dinner` and `got home` both score exactly 0.30 — the multiplicative daypart term zeroes their priors at 09:00, leaving the type bonus alone, which is below the floor by construction. The event floor has nothing plausible to promote and yields rather than pushing an evening cue into a morning set.

**Friction chips**

| Chip | Type |
|---|---|
| just forgot | forgot |
| ran out of time | time |
| ran late | time |
| too tired | energy |
| something came up | competing |
| nowhere to put things | environment |
| too much to face | motivation |
| didn't feel like it | motivation |


---

### 7.7 Language practice

Phone-mediated for most users, which makes `picked up my phone` an honest and unusually actionable cue — and makes the phone the main competitor, which shows up in friction. Heavy conditional load: commuting is one of the most common real anchors here and one of the least universal.

| Chip | Type | Dayparts | Prior | Family |
|---|---|---|---|---|
| with morning coffee | event | early · morning | 0.55 | coffee |
| after dinner | event | evening | 0.50 | dinner |
| picked up my phone | event | any | 0.45 | phone |
| got into bed Ⓢ | event | night | 0.45 | bed-in |
| waiting in line | event | any | 0.40 | waiting |
| after brushing teeth | event | early · night | 0.35 | teeth |
| lunch break | time | midday | 0.55 | lunch |
| before bed | time | night | 0.50 | bed |
| sat at my desk | location | morning · midday · afternoon | 0.45 | desk |
| wanted a break | internal | any | 0.45 | break |
| on my commute ⚑ | location | morning · evening | 0.55 | commute |
| lesson coming up ⚑ | event | any | 0.35 | lesson |

**Ranking notes.** `on my commute` ⚑ carries a high prior and is still conditional: it would be the best chip in the set for the people it fits and pure noise for everyone else. It unlocks readily — any typed answer containing a transit word maps to the `commute` family.

**Worked example A — logged 12:45 (`midday`), designed cue in family `lunch`.**
→ `picked up my phone` (0.66) · `waiting in line` (0.62) · `sat at my desk` (0.60) · `with morning coffee` (0.49)

**Worked example B — logged 21:50 (`night`), designed cue in family `bed`.**
→ `got into bed` (0.75) · `picked up my phone` (0.66) · `after brushing teeth` (0.65) · `wanted a break` (0.41)
Three events fill the top; the type ceiling forces the fourth slot to a non-event, and `wanted a break` is the only one clearing the floor at that hour.

**Friction chips**

| Chip | Type |
|---|---|
| just forgot | forgot |
| no time | time |
| too tired | energy |
| something came up | competing |
| phone was dead | environment |
| didn't feel like it | motivation |
| felt like a chore | motivation |


---

### 7.8 Instrument

The one category where a location cue plausibly outranks everything: an instrument left visible rather than in its case is the canonical “make it obvious” intervention, and users who do it report it as the reason they played. Worth surfacing early because it doubles as an intervention the app can later suggest.

| Chip | Type | Dayparts | Prior | Family |
|---|---|---|---|---|
| it was left out | location | any | 0.60 | sight |
| after dinner | event | evening | 0.55 | dinner |
| got home | event | afternoon · evening | 0.55 | got-home |
| case was open | location | any | 0.45 | sight |
| with morning coffee | event | early · morning | 0.40 | coffee |
| heard a song | event | any | 0.40 | song |
| finished my chores | event | any | 0.35 | chores |
| end of the day | time | evening · night | 0.45 | eod |
| lunch break | time | midday | 0.35 | lunch |
| felt like playing | internal | any | 0.50 | felt-like |
| kids were asleep ⚑ | event | night | 0.40 | kids |
| lesson coming up ⚑ | event | any | 0.35 | lesson |

**Ranking notes.** `heard a song` is an externally-triggered cue filed as `event` under the §5.5 convention: something happened in the world, not in the user's head. The classification matters downstream — filed as `internal` it would wrongly qualify for the convergence exemption.

**Worked example A — logged 19:00 (`evening`), designed cue in family `dinner`.**
→ `got home` (0.85) · `it was left out` (0.63) · `heard a song` (0.62) · `finished my chores` (0.58)

**Worked example B — logged 08:30 (`morning`), no designed cue — Journey A, 5 chips, non-event floor 2.**
→ `with morning coffee` (0.70) · `it was left out` (0.63) · `heard a song` (0.62) · `finished my chores` (0.58) · `felt like playing` (0.45)

**Friction chips**

| Chip | Type |
|---|---|
| just forgot | forgot |
| no time | time |
| too tired | energy |
| fingers were sore | energy |
| something came up | competing |
| it was put away | environment |
| too late for noise | environment |
| didn't feel like it | motivation |


---

### 7.9 Stretching

Almost always stacked on something else — a workout, a shower, getting up from a desk — which makes it the most event-dominated category in the library, and the one where a cue failure is usually an *upstream* failure (see the friction note).

| Chip | Type | Dayparts | Prior | Family |
|---|---|---|---|---|
| after a workout | event | any | 0.75 | post-workout |
| got out of bed Ⓢ | event | early | 0.60 | woke |
| after a shower | event | any | 0.50 | shower |
| left my desk | event | morning · midday · afternoon | 0.50 | desk-up |
| while watching TV | event | evening · night | 0.45 | tv |
| after a walk | event | any | 0.40 | post-walk |
| before bed | time | night | 0.55 | bed |
| first thing up | time | early | 0.50 | woke |
| mat was out | location | any | 0.45 | mat |
| felt stiff | internal | any | 0.60 | stiff |
| back was aching | internal | any | 0.45 | ache |
| between meetings ⚑ | event | morning · midday · afternoon | 0.35 | meetings |

**Ranking notes.** `after a workout` is tied for the highest prior in the library and is daypart-neutral, so it leads almost every set. That's correct but carries a risk worth naming: when the anchor habit doesn't happen, the stretch doesn't either, and the friction chip `skipped my workout` is deliberately mapped to **forgot** rather than competing, because it's an anchor failure — the cue never fired. The intervention is upstream, on the workout, not on the stretch.

**Worked example A — logged 06:40 (`early`), designed cue in family `woke`.**
→ `after a workout` (0.90) · `after a shower` (0.70) · `after a walk` (0.62) · `felt stiff` (0.53)

**Worked example B — logged 21:00 (`evening`), no designed cue — Journey A, 5 chips, non-event floor 2.**
→ `after a workout` (0.90) · `while watching TV` (0.75) · `after a shower` (0.70) · `felt stiff` (0.53) · `mat was out` (0.51)

**Friction chips**

| Chip | Type |
|---|---|
| just forgot | forgot |
| skipped my workout | forgot |
| no time | time |
| too tired | energy |
| something came up | competing |
| no room for it | environment |
| didn't feel like it | motivation |
| felt fine today | motivation |

*`skipped my workout` maps to **forgot**, not competing: the anchor habit never fired, so the cue never fired. The fix belongs upstream on the workout, and the §6 friction-concentration insight should say so rather than proposing a new stretching cue.*


---

### 7.10 Supplements

Cue and routine are nearly simultaneous here, so essentially every real cue is an event stack. This is where the event preference is most obviously correct, and where `forgot` dominates diagnosis more than in any other category.

| Chip | Type | Dayparts | Prior | Family |
|---|---|---|---|---|
| with breakfast | event | early · morning | 0.75 | breakfast |
| with my coffee | event | early · morning | 0.55 | coffee |
| with dinner | event | evening | 0.55 | dinner |
| after brushing teeth | event | early · night | 0.50 | teeth |
| after lunch | event | midday | 0.45 | lunch |
| sat down to eat | event | any | 0.40 | dinner |
| packed my bag | event | early · morning | 0.35 | bag |
| filled my water | event | any | 0.35 | water |
| saw the bottle | location | any | 0.55 | sight |
| first thing up | time | early | 0.55 | woke |
| before bed | time | evening · night | 0.45 | bed |
| felt run down | internal | any | 0.35 | run-down |

**Ranking notes.** Almost every chip is event-type, so the type ceiling of 3 binds in most sets and the fourth slot is effectively reserved for a time or location chip. `before bed` is authored `evening · night` rather than night-only for this reason — without it, evening sets have only one non-event chip available and the diversity guard has nothing to reach for.

**Worked example A — logged 07:45 (`early`), designed cue in family `breakfast`.**
→ `with my coffee` (0.85) · `after brushing teeth` (0.80) · `packed my bag` (0.65) · `first thing up` (0.65)

**Worked example B — logged 19:00 (`evening`), no designed cue — Journey A, 5 chips, non-event floor 2.**
→ `with dinner` (0.85) · `saw the bottle` (0.59) · `filled my water` (0.58) · `before bed` (0.55) · `after brushing teeth` (0.47)
`before bed` at 0.55 is the fifth slot precisely because it was authored `evening · night` — see the ranking note above.

**Friction chips**

| Chip | Type |
|---|---|
| just forgot | forgot |
| out of routine | forgot |
| ran out the door | time |
| too tired | energy |
| something came up | competing |
| wasn't home | environment |
| bottle was empty | environment |
| not sure they help | motivation |

*`forgot` chips tie with `environment` for the most entries here, and the two are closely related — forgetting a supplement is usually a placement problem wearing a memory problem's clothes. A friction concentration on `forgot` routes to the cue-problem intervention (reflection-logic §4), which for supplements almost always means *placement* — move the bottle to where the anchor event happens.*


---

### 7.11 Walking

The most flexible category — a walk fits almost anywhere — which sounds like an advantage and is actually the problem: with no natural anchor, walking habits drift. The library leans hard on meal and arrival stacks for exactly that reason.

| Chip | Type | Dayparts | Prior | Family |
|---|---|---|---|---|
| after lunch | event | midday · afternoon | 0.65 | lunch |
| got home | event | afternoon · evening | 0.60 | got-home |
| after dinner | event | evening | 0.60 | dinner |
| put my shoes on | event | any | 0.45 | shoes |
| started a podcast | event | any | 0.40 | podcast |
| sun was out | event | morning · midday · afternoon | 0.35 | weather |
| shoes by the door | location | any | 0.40 | shoes |
| lunch break | time | midday | 0.45 | lunch |
| needed fresh air | internal | any | 0.55 | air |
| felt stuck | internal | any | 0.50 | stuck |
| the dog needed out ⚑ | event | any | 0.55 | dog |
| partner suggested it ⚑ | social | any | 0.35 | social |

**Ranking notes.** `sun was out` is the clearest instance of the §5.5 ambient-condition problem: externally observable, not habit stacking, filed as `event` with a low prior so it rarely leads. `put my shoes on` and `shoes by the door` share a family — the action and the sight of the object are the same underlying cue at different moments.

**Worked example A — logged 18:30 (`evening`), designed cue in family `dinner`.**
→ `got home` (0.90) · `put my shoes on` (0.66) · `started a podcast` (0.62) · `needed fresh air` (0.49)

**Worked example B — logged 12:40 (`midday`), no designed cue — Journey A, 5 chips, non-event floor 2.**
→ `after lunch` (0.95) · `put my shoes on` (0.66) · `sun was out` (0.65) · `needed fresh air` (0.49) · `felt stuck` (0.45)
`got home from work` scores 0.51 on midday-afternoon adjacency and doesn't make the set, which is right: a lunchtime walk isn't cued by getting home.

**Friction chips**

| Chip | Type |
|---|---|
| just forgot | forgot |
| no time | time |
| too tired | energy |
| something came up | competing |
| stayed at my desk | competing |
| weather was bad | environment |
| shoes weren't handy | environment |
| didn't feel like it | motivation |


---

### 7.12 Sleep routine

Nearly everything is night, so the daypart term barely discriminates within the category: a 22:20 log and a 23:30 log give almost the same set. The interesting axis here is event vs. internal, and for a reason worth stating — a sleep routine cued by `eyes got heavy` isn't a designed routine at all, it's going to bed when tired. Converging on that internal cue is the signal that the habit hasn't been designed yet, and is a good candidate for a §6 insight proposing a fixed anchor.

| Chip | Type | Dayparts | Prior | Family |
|---|---|---|---|---|
| put my phone down | event | evening · night | 0.60 | phone |
| brushed my teeth | event | night | 0.55 | teeth |
| got into bed Ⓢ | event | night | 0.55 | bed-in |
| finished the episode | event | evening · night | 0.50 | tv |
| finished the dishes | event | evening | 0.40 | dishes |
| 10pm hit | time | night | 0.50 | clock |
| wind-down alarm | time | night | 0.45 | alarm |
| lights went low | event | night | 0.35 | lights |
| left the living room | location | night | 0.40 | room |
| eyes got heavy | internal | evening · night | 0.55 | tired |
| felt wired | internal | night | 0.35 | wired |
| after my evening walk ⚑ | event | evening | 0.35 | walk |

**Ranking notes.** `wind-down alarm` is the one permitted exception to the no-app-as-cue rule (§2): it refers to the user's own alarm, set by them and external to this app, not to our notification. The distinction is worth preserving in the data — a habit cued by the user's own alarm is autonomous, one cued by our nudge is not, and growth-engine §6 depends on being able to tell them apart.

**Worked example A — logged 22:20 (`night`), designed cue in family `phone`.**
→ `brushed my teeth` (0.85) · `got into bed` (0.85) · `finished the episode` (0.80) · `10pm hit` (0.60)

**Worked example B — logged 23:30 (`night`), no designed cue — Journey A, 5 chips, non-event floor 2.**
→ `put my phone down` (0.90) · `brushed my teeth` (0.85) · `got into bed` (0.85) · `10pm hit` (0.60) · `eyes got heavy` (0.60)
Compare with example A: same daypart, and three of the chips are identical. The differences are structural rather than temporal — B surfaces five because it is Journey A, and restoring the unpinned `put my phone down` takes the third event slot from `finished the episode` (0.80). That flat daypart profile is why a sleep-routine set is effectively determined by priors alone.

**Friction chips**

| Chip | Type |
|---|---|
| just forgot | forgot |
| lost track of time | time |
| wasn't tired yet | energy |
| too wired | energy |
| kept scrolling | competing |
| was out late | competing |
| TV was still on | environment |
| didn't feel like it | motivation |

*`kept scrolling` and `was out late` are both **competing** but point at very different fixes — one is a protected-slot problem, the other is a target-frequency problem. Worth splitting in a later pass if the diagnosis data justifies it.*

---

## 8. Coverage summary

| | |
|---|---|
| Categories | 12 |
| Cue chips | 144 (12 per category) |
| Friction chips | 94 (7–8 per category) |
| Conditional chips ⚑ | 14 |
| Cue types represented in every category | event, time, location, internal (social in 3) |
| Friction types represented in every category | all 6 |

Every category carries at least one chip of each of event, time, location and internal. That is a property of the library, not a guarantee at run time: because the daypart term is multiplicative, a category can still be short of non-event chips at a particular hour — reading logged mid-morning is the clearest case, where only `book was out` clears the floor. The type-coverage figure says the library is balanced; §5.3's backfill and relaxation steps handle the hours where it isn't, and the authoring-gap item in §9 is the real fix.

Social is the thin type — it appears in exercise, meditation and walking only, and only as conditional. That's honest rather than lazy: for most of these categories a social cue is genuinely rare, and inventing one to fill a column would violate §2.

---

## 9. Open calibration questions

Following the house style of the other specs: numbers here are defaults to tune against real data, not laws.

- **The event bonus (0.30).** The single most consequential number in this document. It trades the app's belief that habit stacking is the most reliable anchor against its ability to discover that a given user's habit is genuinely internally cued. Too high and every first reflection teaches the same lesson; too low and the app stops making its best suggestion. Instrument by comparing the chip-tap distribution against `Something else` typed answers — if typed answers skew internal in a category whose sets skew event, the bonus is too high there.

- **The score floor (0.35) and promotion floor (0.60).** The floor decides when a set gets short or falls back to global chips; the promotion floor decides when the event guard yields. Both currently produce sensible behavior on the 24 worked examples, which is not the same as being right.

- **Adjacency at 0.35.** A guess. It's what stops `after lunch` from leading an 18:30 walking set while still letting `with morning coffee` reach a midday reading set. Worth checking whether adjacency should be asymmetric — a cue is more plausible *later* than its home daypart than earlier, since habits slip late rather than early.

- **The night bucket spans 6.5 hours.** 21:30 and 03:30 land in the same bucket and shouldn't. Splitting `night` (21:30–00:59) from `late` (01:00–03:59) would let adjacency wrap safely at the `late`/`early` boundary, at the cost of a seventh bucket. Deferred because sleep-routine is the only category with meaningful volume in the late half.

- **A sixth cue type for ambient conditions.** `sun was out`, `heard a song`, `it was raining` are currently filed as `event` (§5.5). A dedicated `ambient` type would be more honest and would let the engine treat them correctly for convergence: an ambient cue is external, so the penalty applies, but it's also *outside the user's control*, which is arguably a third case. The reflection record (reflection-logic §5) would need a schema change.

- **Priors are authored, not measured.** Every prior in §7 is a judgement call. They should be replaced, per category, by observed first-reflection tap frequencies as soon as there's data — at which point this library becomes a genuine prior in the Bayesian sense rather than a set of opinions. The chip *text* should outlive the numbers.

- **Two authoring gaps are visible in the worked examples.** Midday reading falls back to a global chip, and early-morning journaling has only one event anchor. Both are real: those daypart/category pairs are less common, but a user in one of them gets the weakest first reflection in the product. Worth authoring 2–3 more chips into each rather than leaving the backfill to cover it.

- **Conditional unlock needs a text→family mapping.** §3 says a typed answer unlocks the matching conditional chip, which presumes a mapping from free text to `family` that doesn't exist yet. A small keyword table per family is probably enough to start; it does not need to be a model.

- **Should `Can't remember` appear on reflection #1?** Reflection-logic §4 makes it a first-class answer, and correctly so. But on the very first reflection — where the completion was likely today and the whole point is to establish the ritual — offering it may teach users that skipping is a normal move before they've ever answered once. Worth testing: present on #1, or from #2 onward.

- **Reward-side chips are out of scope here and shouldn't stay that way.** The design spec makes reward an explicit, user-designed half of the loop, but reflection-logic only ever asks about cues and friction. There is no starter library for *"what did you get out of it?"*, and the §6 friction routing for `motivation` — "revisit what follows the routine" — has nothing to offer the user when it fires. That's a gap in the reflection spec more than in this document, but this document is where it becomes obvious.

- **These chips are culturally loaded.** `after coffee`, `after dinner`, and the assumed timing of both are Western-default. Localisation isn't a translation pass — `before dinner` at 18:00 is a different chip in Madrid than in Amsterdam, and the daypart windows themselves would need to move.
