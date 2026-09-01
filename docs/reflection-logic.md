# Habit App — Reflection Prompt Logic

*Specs the mechanic that feeds Roots. This is the differentiator: every other app collects completions, this one collects understanding.*

---

## 0. Governing principles

1. **Prompts are a scarce budget, spent on information — not sprayed on a schedule.** A "what triggered you?" asked for the tenth time when the answer has been "after breakfast" nine times teaches nothing and costs goodwill.
2. **Never interrupt the reward.** The completion tap stays pure — water, soil darkens, haptic, done. Questions come later, in their own moment.
3. **One tap is the common case.** If the median check-in takes more than ~5 seconds, the ritual dies. Typing is the exception, always.
4. **An insight must propose an action, or it isn't surfaced.** "You run more on Tuesdays" is horoscope. "Your cue fails on days you skip breakfast" is a fix.

---

## 1. The Evening Check-in

**Reflection and the next-day nudge are the same moment.** One notification, in the evening: look back at today, commit to tomorrow.

> *"You ran this morning — what got you out the door?"*
> → `after breakfast` · `felt restless` · `something else`
>
> *"Thursday next, then — after breakfast?"*
> → `Yes` · `Different day`

This solves several things at once. It gives the app one consistent conversational slot instead of two competing interruptions. It keeps the completion tap uncontaminated. It puts the backward-looking question and the forward-looking commitment adjacent, which is where they belong — you learn what cued you, then you deploy that knowledge on tomorrow. And it means the cue phrase gets rehearsed twice in one screen.

**Frequency:** at most once per day, and only when the priority score clears the bar (§2). Most days there is no check-in at all.

**Known cost:** asking in the evening about a morning run loses some recall fidelity. `Can't remember` absorbs this honestly (§4), and it's a real signal rather than a gap. Evening-performed habits could check in same-hour instead — flagged in §8 as a calibration question rather than pretended solved.

---

## 2. When to prompt — priority scoring

Every **occasion** — a completion, a missed expected occasion, or an un-nudged completion — gets scored. Prompt when the score clears threshold, subject to budget and cooldown.

```
Priority = uncertainty + early_bonus + occasion_weight + anomaly − recency_penalty
```

| Component | Value | Rationale |
|---|---|---|
| `uncertainty` | `1 − c` (cue convergence) | Unknown cue = high information |
| `early_bonus` | `+0.4` while n < 5, decaying | No prior means everything teaches |
| `occasion_weight` | miss `+0.5`, un-nudged completion `+0.6`, ordinary completion `0` | Misses and autonomy events are the richest data |
| `anomaly` | `+0.3` | Unusual time, unusual gap, first completion after droop |
| `recency_penalty` | `−0.5` if prompted within 48h | Protects the ritual |

**Threshold:** 0.5. **Cooldown:** 24h minimum.

**Weekly budget, fading by stage** — the same logic as nudge fading:

| Stage | Max check-ins / week |
|---|---|
| Sprout · Seedling | 3 |
| Young | 3 |
| Mature | 2 |
| Bloom / graduated | ~1 per month (spot check) |

Budget still clears the root requirement comfortably: ~12 reflections across the Young window, ~12 across Mature, against the ~20 weighted needed for bloom.

---

## 3. What to ask — four framings

The design spec named three. Practice needs a fourth: **Confirmation**, the one-tap degenerate case of Discovery for habits whose cue has already converged. Without it, late-stage reflection is either annoying or abandoned.

Selection is driven by **occasion type × habit state**, not stage alone:

| Occasion | Habit state | Framing | Prompt |
|---|---|---|---|
| Completed | Stage ≤ Seedling | **Validation** | *"Did [designed cue] kick it off?"* → `Yes` · `No, something else` · `Can't remember` |
| Completed | Young+, `c < 0.6` | **Discovery** | *"What got you going today?"* → chips |
| Completed | Young+, `c ≥ 0.6` | **Confirmation** | *"Same as usual — after breakfast?"* → `Yes` · `Actually, no` |
| Completed, un-nudged | any | **Autonomy** | *"You did this without us asking. What reminded you?"* |
| Missed expected occasion | any | **Diagnosis** | *"No run yesterday — what got in the way?"* → friction chips |

**Diagnosis framing rule:** state the fact neutrally, ask with curiosity. *"No run yesterday — what got in the way?"* Never *"You missed your run."* The app is a collaborator investigating a system, not a supervisor noting an absence.

### Root credit is weighted by information content

This refines `n` in the roots formula — it's a **weighted** sum, not a raw count:

Credit is set by **framing × input mode**, not framing alone:

| Framing / mode | Credit |
|---|---|
| Autonomy | 1.5 |
| Validation / Discovery / Diagnosis | 1.0 |
| Confirmation (one tap) | 0.5 |
| **Any framing answered `can't remember`** | **0.25** |
| Skipped | 0 |

So `R_raw = Σcredit / (Σcredit + 4)`. A user coasting on confirmations still deepens roots, but slowly — which is correct, because they're learning slowly.

The `can't remember` row matters: an early draft assigned credit by framing alone, so a Discovery answered "can't remember" earned a full 1.0 despite conveying no cue information whatsoever. It's honest evidence of autopilot — worth something — but it builds no understanding, and it must never be worth what an actual answer is worth.

**It is also excluded from convergence `c` entirely** (engine spec §5). Where fewer than 3 cue-bearing reflections exist in the window, `c = 0`, not 1 — otherwise the modal share of an empty set reads as perfect convergence and roots inflate for the least aware user.

---

## 4. Chip mechanics

**First reflection** has no history, so chips are seeded from the **designed cue** (always pinned first — this makes Validation a single tap) plus starter-library entries filtered by habit category and time of day.

**Thereafter**, chips rank by recency-weighted frequency, capped at 5, always plus:

- `Something else` → opens typing
- `Can't remember` → **a valid, first-class answer**

`Can't remember` matters more than it looks. Forcing a choice manufactures false data. And a rising can't-remember rate is itself the signal that a habit is running on autopilot without awareness — a tall plant on shallow roots, exactly as the metaphor promises. The data model and the visual say the same thing.

### Cue taxonomy — a first-class field

Every cue carries a **type**, not just a label:

| Type | Examples |
|---|---|
| **Event** (habit stacking) | after breakfast · after coffee · got home from work · once the kids are asleep |
| **Time** | just woke up · lunchtime · before bed |
| **Location** | walked past the gym · sat down at my desk |
| **Internal state** | felt stressed · felt restless · had energy |
| **Social** | partner was going · friend texted |

**This resolves the open question from the engine spec.** The convergence penalty `(0.5 + 0.5c)` should apply to *external* cue types only. A habit genuinely anchored to an internal state ("when I feel stressed") is not a badly-designed loop, and shouldn't have its roots halved for varying. For internal-type cues, convergence is measured on **type stability** rather than exact label — consistently reporting internal states counts as converged.

Event-type cues get a small ranking preference in the starter library, since habit stacking onto an existing routine is the most reliable anchor available.

**Discovered vs. designed.** Internal cues are valid here, in reflection, as things the user *notices*. They are **not** permitted as the designed cue at habit creation — the engine can't schedule, nudge, or fairly measure a habit anchored to a mood (engine spec §1, scope constraint). So the taxonomy is used in two different ways at two different moments: creation accepts external types only; reflection accepts all five.

### Friction taxonomy (Diagnosis)

| Type | Chip | Routes to |
|---|---|---|
| Forgot | *"just forgot"* | **Cue problem** — the anchor isn't firing; propose a new one |
| Time | *"no time" / "ran late"* | **Routine too big** — propose shrinking it |
| Energy | *"too tired"* | **Timing problem** — propose moving it earlier |
| Competing | *"something came up"* | **Priority/placement** — propose a more protected slot |
| Environment | *"gear wasn't ready" / "weather"* | **Friction audit** — propose prep the night before |
| Motivation | *"didn't feel like it"* | **Reward problem** — revisit what follows the routine |

The forgot/motivation split is the one most apps can't make, because they never ask. They're opposite problems with opposite fixes: forgetting is a cue failure, reluctance is a reward failure. Treating them the same is why generic habit advice fails people.

---

## 5. Reflection record

```
Reflection {
  habit_id, timestamp
  occasion:        completion | miss | autonomy_completion
  framing:         validation | discovery | confirmation | diagnosis
  cue_reported:    string | null
  cue_type:        event | time | location | internal | social | unknown
  matched_designed_cue: bool | null
  friction_reported: string | null
  friction_type:   forgot | time | energy | competing | environment | motivation | null
  input_mode:      chip | typed | cant_remember | skipped
  was_nudged:      bool
  root_credit:     float        // framing × input_mode, per §3
  counts_toward_c: bool         // false for cant_remember / skipped
}
```

`matched_designed_cue` across validations is the **cue-reliability** number the cue-testing phase displays: *"your cue worked 6 of 8 times."*

---

## 6. Insight surfacing — detection rules

Each pattern has a minimum evidence threshold. **Nothing fires below it**, and **at most one insight per check-in.** Scarcity is what makes an insight feel like a revelation rather than a feed.

| Insight | Trigger | Surfaces as |
|---|---|---|
| **Cue lock-in candidate** | A non-designed cue in ≥60% of last 8 discoveries, ≥5 occurrences | *"You almost always meditate after your morning coffee — want to lock that in as your official cue?"* |
| **Cue unreliable** | Designed cue matched <40% over ≥6 validations | *"Your cue isn't firing reliably. Want to try anchoring to something fixed?"* |
| **Conditional cue failure** | Miss co-occurs with a factor ≥3 times, with a clear base-rate gap | *"Your workout cue is unreliable on days you skip breakfast."* |
| **Friction concentration** | One friction type ≥50% of last 6 diagnoses | Routes to the §4 intervention for that type |
| **Autonomy milestone** | First un-nudged completion | *"You ran without us asking."* — fires at n=1; it's an event, not a pattern |
| **Awareness gap** | `can't remember` ≥50% of last 6 | *"You're doing this on autopilot — worth noticing what sets it off?"* (ties to shallow roots visually) |
| **Nudge dependence** | Autonomy < 0.2 over ≥6 un-nudged occasions | *"You tend to run when we remind you — let's find a trigger that isn't us."* → routes to cue redesign |

**Nudge dependence deserves special weight.** Without it, that user stalls silently: he completes nearly every nudged occasion and almost no un-nudged one, which parks him at ~0.70 adherence — just below the Mature bar — indefinitely, with no explanation. The engine blocks him correctly and tells him nothing. It's also the failure mode that most directly threatens the product's thesis, since a nudge-dependent user has effectively made the notification his cue. Diagnosing it out loud is the intervention least available to any competitor.

A cue lock-in that the user accepts **rewrites the designed cue**, which resets cue-reliability measurement and re-enters a short validation phase. The loop stays alive — that's the whole thesis.

---

## 7. Graduation and re-entry

At Bloom with `c ≥ 0.8` and `Autonomy ≥ 0.6`: *"This one seems locked in — we'll stop asking."* Prompts drop to a monthly Confirmation spot-check.

**Re-entry:** stage never regresses, but *prompting* can resume — on a spot-check revealing the cue changed, or a droop past full wilt. Framing returns to Discovery, not Validation: the user isn't a beginner, their circumstances moved.

---

## 8. Open calibration questions

- **Evening recall fidelity.** Morning habits reflected on at night lose accuracy. Worth testing a same-day-later slot for morning habits against the simplicity of one fixed evening ritual.
- **Priority threshold (0.5).** Directly controls how often people are asked. The most user-visible number in this spec.
- **Confirmation credit (0.5).** If too generous, users coast to bloom on taps alone; too stingy and late-stage roots stall.
- **Starter chip library** needs real authoring per habit category — the first-reflection experience is disproportionately important and currently the thinnest part of this spec. *(Handed to a separate workstream.)*
- **`can't remember` credit (0.25)** — high enough that honest non-answers still feel worth giving, low enough that they can't substitute for understanding. Untested.
- **Nudge-dependence threshold (autonomy < 0.2 over 6)** — fires late by construction, since un-nudged occasions are rare at early stages. May need to key off a smaller sample at Young.
