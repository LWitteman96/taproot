# Habit App — Growth Engine Spec

*Working out the formula left open in §5 of the design spec. Numbers here are calibrated defaults, meant to be tuned against real data, not laws.*

---

## 0. The four state variables

The engine tracks four things per habit. Keeping them separate is what lets the app be demanding about growth and forgiving about setbacks at the same time.

| Variable | What it means | Behavior |
|---|---|---|
| **Stage** | How big the plant is | Monotonic — earned stages are banked, never lost |
| **Vitality** | How healthy it looks right now | Fluctuates daily, snaps to full on watering |
| **Roots** | How well the loop is understood | Grows with reflection, saturating |
| **Autonomy** | Does the habit fire without the app? | The bloom gate and the graduation trigger |

Stage is the reward. Vitality is the pull. Roots are the gate. Autonomy is the point.

---

## 1. Inputs

- **f** — target frequency, times per week. User-declared at creation ("I'm someone who runs 3× a week"). This is the identity commitment and the engine's anchor.
- **Completions** — watering events, timestamped.
- **Reflections** — each carries: did the designed cue fire, what actually cued it, and (on a miss) what got in the way.
- **Nudges** — sent / not sent, confirmed / declined.

Two derived constants:

- **Expected gap** `G = 7 / f` days. For f=3, G = 2.33.
- **Rolling-7 count** `C₇` = completions in the last 7 days.

### Scope constraint — scheduled habits only (v1)

The entire engine assumes a habit that can be **scheduled**. `f` must be meaningful, the nudge must be able to predict a day, and gap-based droop must be fair.

**Responsive habits break all three.** "Meditate when I feel stressed" has no sensible `f`; the evening nudge becomes nonsense (*"tomorrow when you feel stressed, right?"*); and droop punishes the user for having a low-stress week — the plant wilts because life went well.

So: **the designed cue at creation must be external and schedulable** — event, time, location, or social. Internal states remain fully valid as cues *discovered* through reflection (this is what the convergence exemption in §5 protects), but they can't anchor the loop in v1.

Responsive habits are a v2 class needing different mechanics: the user logs cue occurrences, and the measure becomes *when the cue fired, did you follow through* rather than anything gap- or frequency-based.

---

## 2. Adherence — measured in reps, not days

The obvious move is a fixed calendar window. It breaks immediately: a 14-day window holds 6 expected runs for a 3×/week habit but only 2 for a 1×/week habit, so the weekly-habit user's score swings 50% on a single miss. Low-frequency habits would look chaotic for reasons that have nothing to do with the user.

So **the window is defined in expected repetitions and converted to days**:

```
W_days   = clamp( W_reps × 7 / f , 14 , 42 )
Expected = f × W_days / 7
Adherence A = min( completions_in_window / Expected , 1.0 )
```

Capped at 1.0 — overperformance doesn't buy slack. If a user consistently exceeds f, that's not credit to bank, it's a signal to renegotiate identity (§7).

---

## 3. The stage ladder

Advancement is gated on adherence. **Roots hard-gate Bloom only.**

| Stage | Requirement to reach it | W_reps | θ (adherence) | ρ (roots) |
|---|---|---|---|---|
| **0 · Seed** | Habit designed: cue + routine written, plant chosen | — | — | — |
| **1 · Sprout** | First completion | — | — | — |
| **2 · Seedling** | 3 completions | 3 | 0.50 | — |
| **3 · Young** | Sustained early consistency | 8 | 0.60 | 0.30 *advisory* |
| **4 · Mature** | Robust | 12 | 0.75 | 0.50 *advisory* |
| **5 · Bloom** | Runs on its own cue | 20 | 0.80 | **0.75 hard · + Autonomy ≥ 0.5** |

### Why the intermediate gates are advisory

An earlier draft hard-gated every stage on roots. Pressure-testing killed it: a user running 3×/week reliably for six months who taps through reflections lands at R ≈ 0.40 and freezes at **Young** — stage 3 of 5 — despite a flawless completion record. He reads that as the app withholding progress he plainly earned, and leaves.

The original design intent was narrower and better: *bloom* needs both halves. So behavior alone carries a habit to Mature. Below `ρ`, the plant advances but renders **tall and shallow-rooted** — visibly top-heavy, and the awareness-gap insight fires.

This is strictly better than a gate, because **the metaphor already does this job.** A precarious-looking tree communicates "something is missing here" without confiscating anything. The visual was designed to carry exactly this message; the gate was redundant force.

Bloom stays absolute: no amount of consistency blooms a habit the user doesn't understand.

**The forgiveness taper is the θ column** — 0.50 → 0.80. Early on you may miss half your intended runs and still grow; at the top you're held to four in five.

Worked example, f = 3:

- **→ Young:** window 19 days, expected 8.1, need **5 completions** + ~4 reflections.
- **→ Mature:** window 28 days, expected 12, need **9 completions** + ~10 reflections.
- **→ Bloom:** window 42 days, expected 18, need **15 completions** + ~20 reflections + autonomy.

Fastest possible path to bloom ≈ 96 days, realistically 4–6 months. That lands deliberately past the ~66-day median for habit automaticity in Lally et al. (2010) — bloom should mean *actually ingrained*, not *stuck with it for a month*.

### Clamp collapse at low frequency

The 42-day ceiling binds for Bloom at f < 3.3, Mature at f < 2. When it binds, adjacent thresholds **round to the same integer** and the taper silently disappears.

Worked at f = 1 (a Sunday phone call), all top stages share a 42-day window with `Expected = 6`:

- Mature: 0.75 × 6 = 4.5 → **5 calls**
- Bloom: 0.80 × 6 = 4.8 → **5 calls**

Identical. The ladder has no top rung.

**Fix:** when the clamp binds, tighten with *time* instead of a higher threshold — **Bloom requires two consecutive passing windows.** A weekly habit must hold the bar for twelve weeks rather than six. (Young/Mature still separate cleanly at 4 vs. 5, so only Bloom needs the rule.)

---

## 4. Vitality — droop without punishment

Stage never falls. Vitality is the layer that visibly reacts.

```
o = days_since_last_completion − G          (overdue)
V = 1 − clamp( (o − g) / D , 0 , 1 )
```

| Stage | g (grace, days) | D (droop → full wilt) |
|---|---|---|
| Sprout | 0 | 2 |
| Seedling | 0.5 | 3 |
| Young | 1.5 | 6 |
| Mature | 3 | 12 |
| Bloom | 5 | 20 |

At f=3: a **seedling** starts drooping 2.8 days after its last watering and is fully wilted at 5.8. A **mature tree** doesn't visibly react until day 5.3 and takes 17 days to wilt. Miss one run as an oak and nothing happens — which is the promise the resilience model makes.

`V` snaps to 1.0 on completion. Always. That's the watering payoff.

**The pacing trap.** A pure gap formula punishes a user who runs Mon/Tue/Wed and rests — they hit 3×/week exactly, then droop on Saturday for no reason. The user's contract is a weekly frequency, so the plant should answer to the week, not the calendar gap:

```
if C₇ ≥ ⌈0.8 × f⌉:  V = 1.0        // on or near pace, no droop, regardless of gap
else:                V = formula above
```

**The `0.8` matters.** A strict `C₇ ≥ f` demands a perfect 7-of-7 at f=7, so daily habits — the ones that trip the gap formula most often — got no protection at all. Any single missed day dropped them straight into droop.

With the tolerance: f=7 stays healthy at 6 of 7 (⌈5.6⌉=6) and only droops on a second miss. f=3 still requires all 3 (⌈2.4⌉=3), so the Mon/Tue/Wed case is unchanged and low-frequency habits get no undeserved slack — they don't need it, their `G` is long already.

**Wilt freeze.** While a habit is a renegotiation candidate (§7), vitality floors at droop-onset rather than continuing to wilt. Once the app suspects the *target* is wrong, further wilting is punishing the user for the app's bad assumption.

---

## 5. Roots — depth, not volume

Raw reflection count would reward grinding. Root depth should track *how well the loop is actually understood*, which means two components:

```
R_raw = N / (N + 4)                        // N = weighted reflections, diminishing returns
c     = modal-cue share over last 8 reflections   // convergence
R     = R_raw × (0.5 + 0.5c)
```

`N/(N+4)`: 4 → 0.50, 10 → 0.71, 20 → 0.83. Steep early, flat later — the fifth reflection teaches you a lot, the fiftieth almost nothing.

**`N` is weighted, not a raw count** (see reflection-logic spec §3): autonomy reflections 1.5, validation/discovery/diagnosis 1.0, one-tap confirmations 0.5, **`can't remember` 0.25**. Credit tracks information content — an honest non-answer is worth something (it's real evidence of autopilot) but it builds no cue understanding.

**Convergence `c`** is the interesting half. If eight reflections name eight different cues, the loop isn't designed yet — it's still noise — and roots stay shallow. If six of eight say "after breakfast," c = 0.75 and roots deepen. A scattered cue history halves root depth.

**Exemption:** the convergence penalty applies to *external* cue types only — event, time, location, social. A cue genuinely anchored to an internal state ("when I feel stressed") is not a badly-designed loop; for those, `c` is measured on **type stability** rather than exact label.

### `c` must not be vacuously true

`c` is computed **only over cue-bearing reflections** — `can't remember` and skips are excluded from both numerator and denominator.

That creates a degenerate case with teeth. A user whose last 8 reflections are all `can't remember` has no modal cue at all, and a naive modal-share computation returns **1.0** on an empty set. Roots would then *inflate* for precisely the least self-aware user — the exact inversion of what roots are supposed to measure.

**Rule: if fewer than 3 cue-bearing reflections exist in the window, `c = 0.`** Absence of evidence is not convergence. This floors roots at `R_raw × 0.5` for autopilot users, which is the correct reading and the thing the awareness-gap insight responds to.

This must surface as **diagnosis, never as penalty**: *"Your runs don't seem to have a consistent trigger yet — want to try anchoring to something fixed?"* The user reflecting honestly about a variable cue is doing the app's work correctly; the app's job is to notice and help them converge, not to dock them.

Cue reliability — *"your cue worked 6 of 8 times"* — is `c` computed against the **designed** cue specifically, which is also the number the cue-testing phase displays.

---

## 6. Autonomy, nudge fading, and the integrity problem

**This is the part of your flow that needs the most protection.**

Your evening-before notification carries the cue text — *"tomorrow after breakfast we're going for a run right?"* — which is genuinely the strongest idea in the flow. It doesn't just remind, it **rehearses the cue**, and the confirmation tap is an implementation intention (Gollwitzer's work on if-then planning shows a large effect on follow-through). Every cycle strengthens the breakfast→run association rather than the app→run association.

But the failure mode is right next to it: **if the app nudges every time, the notification becomes the cue.** The user runs because the phone asked, "after breakfast" is decoration, and you've quietly built the exact app you set out to differentiate from — except with more ceremony.

The engine defends against this by **fading its own nudges** and measuring what happens.

| Stage | Nudge rate on expected occasions |
|---|---|
| Sprout / Seedling | 100% |
| Young | 70% |
| Mature | 40% |
| Bloom / graduated | 0–10% (spot check) |

```
Autonomy = completions on un-nudged expected occasions / un-nudged expected occasions
           (last 10)
```

The skipped nudges aren't just restraint — they're the **measurement instrument**. You can't know whether the habit stands on its own until you stop holding it up. This makes nudge fading load-bearing rather than a politeness feature.

**Bloom requires Autonomy ≥ 0.5.** A habit that only fires when prompted cannot bloom, no matter how perfect the completion record. That is the cleanest possible definition of the app succeeding.

**Autonomy must also be visible, not just a gate.** A nudge-dependent user completes ~100% of nudged occasions and ~0% of un-nudged ones. At Young (70% nudge rate) that lands him at adherence ≈ 0.70 — just under the 0.75 Mature bar — where he stalls indefinitely, and the engine never tells him why. A silent permanent stall is the worst possible outcome.

So low autonomy triggers an insight, not just a block (reflection-logic §6): *"you tend to run when we remind you — let's find a trigger that isn't us."* It routes to cue redesign, because that's what the problem actually is. This is arguably the single most valuable intervention the app can make, and it was invisible until pressure-testing surfaced it.

**Graduation** (§3 of the design spec — the app backing off) triggers at: Stage = Bloom, `c ≥ 0.8`, `Autonomy ≥ 0.6`. Reflection prompts drop to a monthly spot-check. *"This one seems locked in — we'll stop asking."*

---

## 7. Pressure valves

Two mechanics without which the system quietly turns cruel.

**Pause.** The user can pause a habit (illness, travel, a hard month). Paused days are excluded from every window — they don't count as misses, and vitality freezes. Without this, honesty is punished and users learn to lie to the app or abandon the plant.

**Target renegotiation.** The app doesn't let a plant die — it questions the target: *"You've been running about once a week. Want to make that the goal?"* Lowering f is an identity update, not a failure, and it rescues the system from the mismatched-target death spiral where a plant wilts permanently because the user was ambitious in week one. The same mechanic runs upward: sustained A = 1.0 with overflow prompts *"you're running 5× — is that who you are now?"*

**Trigger — whichever fires first:**

- Adherence < 0.4 across two consecutive windows, **or**
- The plant has been **fully wilted for 7 consecutive days**

The second condition exists because the first is far too slow. Trace the over-ambitious starter: declares gym 5×/week, manages 1×. His windows are 14 days, so the two-window rule offers help on **day 28** — after a month of opening the app to a dead plant. He churns around day 10. Wilt duration catches him in the second week, while he's still there.

**This is also where the resilience model has a genuine internal tension.** Fast seedling wilt is designed to create the "my garden needs me" pull — and it does, *for someone succeeding*. For someone drowning, that same mechanic is a daily failure notification, and it hits hardest at Sprout, where droop settings are harshest and the user is most fragile. The wilt freeze in §4 resolves it: the moment the app suspects the target is wrong, it stops wilting and starts asking.

Both paths re-anchor `f`, which re-anchors everything else.

---

## 8. Cold start — what the app can say in week one

The reflection budget (~2–3×/week) means pattern-surfacing is data-starved exactly when retention is most fragile. What's honestly available early:

- **After 3 reflections:** cue reliability as a raw fraction — *"your cue fired 2 of 3 times."* Small, true, and it's the calibration framing rather than a performance score.
- **From nudge confirms/declines:** day-of-week preference emerges fast, and declines are cheap data. *"Thursdays keep getting pushed — is Wednesday better?"* is available in week two.
- **The first un-nudged completion** is a genuine milestone and should be called out explicitly: *"You ran without us asking."* That's the app's whole thesis landing in week two or three.

Resist synthesizing insight before the data supports it. A fabricated "aha" is worse than none — it burns the mechanic that's supposed to be the hook.

---

## 9. Open calibration questions

- **θ at bloom (0.80)** — missing 3 of 18 in six weeks. Too strict once Pause exists? Possibly loosen to 0.75.
- **Autonomy ≥ 0.5 at bloom** — is a coin flip the right bar for "stands on its own"? Feels low for the app's central claim; 0.6 may be truer.
- **Nudge-fade rates** are guesses. This is the single most important thing to instrument, because it trades retention against the app's integrity — and the tempting direction (nudge more) is the one that hollows the product out.
- **Wilt-duration trigger (7 days)** — should probably be shorter at Sprout, where the user is newest and most likely to leave.
- **Advisory root thresholds** — do they need to exist at all, or is the tall-and-shallow visual sufficient on its own?
- **What the wilt freeze freezes at (§4).** "Vitality floors at droop-onset" reads literally as V = 1.0, since that *is* the value at onset — the plant stops looking unwell the moment the app decides the target is wrong. The alternative reading is that vitality holds at whatever it was when candidacy began, which for the wilted-7-days trigger means holding at 0. Implemented literally and isolated as `EngineConstants.wiltFreezeFloor`; the two readings say different things to a drowning user and this is untested.

**Resolved by pressure-testing (see §1, §3, §4, §5, §6, §7):** convergence penalty on internal cues · root gates over-tightened on intermediate stages · responsive habits out of v1 scope · vacuous `c` on empty cue sets · renegotiation latency · clamp collapse at low `f` · pacing exemption dead at high `f` · nudge dependence invisible.

---

## 10. Implementation reconciliations

*Written while building `lib/core/engine/`. Each entry is a place where this spec's prose and its formulas disagreed, or where a rule was stated qualitatively and the code needed a definition. None of them changes a calibrated number — they record which reading was implemented, and why. The tests in `test/unit/engine/` are the enforcement.*

### The ladder is sequential — a window may not open before the previous stage was earned

§3 states a fastest possible path to bloom of ≈96 days. That number only falls out if the stage windows run *successively*: 19 + 28 + 42 days, each one opening no earlier than the moment the previous stage was earned. Evaluated concurrently — every window measured against the same completion history — a flawless f=3 user satisfies all four gates at once and blooms in about six weeks, which contradicts the spec's own intent that bloom land past the ~66-day Lally median.

So: **Young, Mature and Bloom each require their qualifying window to begin at or after the instant the previous stage was earned.** Seedling is exempt, because its gate is really the "3 completions" milestone and applying the rule would push a seedling out to day 14.

With perfect play at f=3 this puts bloom on day 88 — close enough to the spec's ≈96 that the two readings can be treated as the same claim.

Consequence for storage: stage is a **replay over history**, not a running maximum of an instantaneous check. `computeStageProgress` walks one candidate instant per local day and records when each rung was first cleared. Monotonicity is a property of that replay rather than something the database has to protect.

### Seedling is gated by both of its stated requirements

The stage table gives Seedling a prose requirement ("3 completions") *and* a W_reps/θ row (3, 0.50). They coincide only at f=3: at f=7 the adherence rule asks for 7 runs in 14 days, at f=1 it asks for 2 in 21. Both apply — cumulative completions **and** the adherence gate. Sprout keeps its own cumulative minimum of 1.

### W_days rounds up to a whole calendar day

A window is a set of local dates, so `W_reps × 7 / f` is rounded up before clamping. This is what makes §3's Young window read as *19 days expecting 8.1 runs* rather than 18.67 expecting 8.0. No threshold integer moves either way; the rounding just makes the published numbers reproducible.

### Convergence is measured over the last 8 reflections, then filtered

§5 says `c` is the modal share "over the last 8 reflections" and also that it is computed "only over cue-bearing reflections". Read as *the last 8 cue-bearing reflections*, the `< 3 ⇒ c = 0` rule almost never fires once a user has ever answered three times — which defeats the degenerate case the rule exists for. Implemented as: **take the last 8 reflections, then keep the cue-bearing ones.** A user whose recent check-ins are all `can't remember` therefore has 0 cue-bearing reflections in the window and `c = 0`, which is the reading §5 argues for at length.

### Renegotiation needed two rules the spec gives only qualitatively

**The two-window adherence trigger requires two windows of real history.** The earlier window must begin strictly after `created_at`. Without that guard an empty pre-creation window reads as a failing one and *every* new habit is flagged as a renegotiation candidate on day one. With it, the over-ambitious 5×/week starter of §7 is flagged on exactly day 28, as the spec predicts — and the wilt trigger catches them on day 10, which is the entire reason both triggers exist.

**Observed pace** — the number behind *"you've been running about once a week"* — is completions over the last 28 active days, converted to a weekly rate, rounded, clamped to 1–7. It is also what defines the upward trigger: sustained A = 1.0 across two consecutive windows *plus* an observed pace above the declared `f`. §7 describes the upward mechanic but gives it no threshold; this avoids inventing a second magic number.

**A paused habit is never a renegotiation candidate.** Pause already says "not now"; proposing a lower target on top of it punishes the honesty the mechanic exists to protect.

### Completions are counted, not completion-days

`completions_in_window` counts events, so two waterings in one day count as two reps. The 1.0 cap is what bounds the effect; preventing accidental double-taps is the UI's job, not the engine's.

### A habit that has never been watered measures its gap from creation

The droop formula needs a "last completion" that a fresh seed doesn't have. It runs from `created_at`, so a designed-but-abandoned habit wilts on the same schedule as any other plant rather than sitting at full vitality forever.

### Two arithmetic details worth not rediscovering

`ceil(0.8 × f)` needs a floating-point guard: `0.8` has no exact binary form, so `0.8 × 5` lands a hair above 4.0 and a naive `ceil` demands 5 of 5 from an f=5 habit. The engine subtracts 1e-9 before rounding, which keeps the 0.8 a live tunable instead of hard-coding it as 4/5.

All window arithmetic runs on **local dates**, and elapsed time is measured on the local wall clock (`lib/core/utils/local_dates.dart`). A day is a wall-clock day, not a 24-hour block, so a DST transition never shifts droop onset by an hour.

### What the engine deliberately does not do

Reflection priority scoring (reflection spec §2) and insight detection (§6) are **not** in `lib/core/engine/`. They are feature-layer concerns that consume engine outputs. Their tunables — the 0.5 threshold, the 48h recency penalty, the weekly budgets — already live in `constants.dart` so they have one home when that work starts.
