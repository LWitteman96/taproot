# Habit App — Design Spec

*A living document capturing the concept, decisions, and open questions from the initial brainstorm.*

---

## 1. Concept & Positioning

A habit app that doesn't just **track** habits but helps users **design** them, built on two well-known behavioral frameworks:

- **The Power of Habit** (Charles Duhigg) — the **cue → routine → reward** loop.
- **Atomic Habits** (James Clear) — the **Four Laws** (make it obvious, attractive, easy, satisfying) and **identity-based** habits.

**The differentiator.** Most habit apps treat the cue and the reward as invisible app defaults — the notification *is* the cue, the checkmark/streak *is* the reward — so the user never consciously architects their own loop. This app makes the loop a **first-class, explicit design object**: the user actively decides what triggers a habit and what reward follows it, and keeps that design alive over time.

### Competitive landscape (from research)

- **Minimalist trackers** (Loop, Streaks, Habitica) — check off habits, build streaks, get reminders. Habit loop used passively, never designed by the user.
- **Atoms** (official Atomic Habits app, by Tiny Ltd. with James Clear) — closest competitor. Guided, identity-based habit creation plus bite-sized lessons and exclusive James Clear content. More a coaching/content app than a structured loop-design tool.
- **Griply** — most structurally interesting. Implements the Four Laws and nests every habit in Life Area → Vision → Goal → Subgoal → Habit. But it's goal-management-first, not habit-loop-first.
- **Habit Rewards** — lets users set up a reward system, but the cue/reward pairing isn't structured around the loop framework.

**The gap:** no app makes the user explicitly architect each habit as a Cue → Routine → Reward triple and then keep refining it. That's the opening.

---

## 2. Core Architecture — Two Journeys, One Engine

There are two ways a user arrives at a habit, but they're powered by a **single reflection engine** that's simply *framed* differently depending on the habit's maturity.

### The two journeys

- **Journey A — Track an existing habit.** The habit already has a loop; the user just isn't conscious of it. After completing the habit, the app occasionally asks what cued it and how they rewarded themselves, **reverse-engineering** the loop to make it explicit and reinforceable.
- **Journey B — Design a new habit from scratch.** The user writes down the intended cue, routine, and reward up front, then enters a **validation / cue-testing** phase where the app checks whether the designed loop actually fires in practice.

### One engine, three framings

The same lightweight reflection moment shifts its question based on habit state:

| Habit state | Framing | Example prompt |
|---|---|---|
| New / early | **Validation** | "Did your cue fire? Did you follow through?" |
| Established | **Discovery** | "What triggered you today?" |
| Struggling | **Diagnosis** | "What got in the way?" |

This keeps the whole app conceptually simple: it's always asking about the relationship between the cue and the behavior — only the intent changes.

---

## 3. The Reflection Loop (the "design stays alive" mechanic)

The point of designing a habit is that it should be **useful over time**, not filled in once and forgotten. So reflection is an ongoing, lightweight ritual rather than a setup form.

Key design principles:

- **Tap, don't type.** The first reflection on a habit may be typed. After that, the app remembers past cue/reward answers and offers them as **one-tap chips** ("finished breakfast," "got home from work," "felt stressed"). Typing is the exception; tapping is the default. This is what makes frequent reflection sustainable.
- **Don't ask every time.** Prompt roughly **2–3× per week**, not on every completion. Over-prompting kills the ritual.
- **Confidence over streaks (during cue-testing).** Instead of a streak counter, show a **cue-reliability** signal ("your cue worked 6 of 8 times"). Reframes the early period as calibration, not performance. A miss is a data point, not a failure.
- **The "aha" surfacing.** The payoff for reflecting is the app noticing patterns the user can't — e.g. *"You almost always meditate after your morning coffee — want to lock that in as your official cue?"* or *"Your workout cue is unreliable on days you skip breakfast."* Being told something true about yourself is the hook that makes people open the app.
- **Graduation.** When a habit becomes automatic, reflection becomes unnecessary. The app should **recognize this and back off** ("This one seems locked in — we'll stop asking"). Knowing when to stop is what separates a thoughtful app from a nagging one, and it's a celebrated milestone in itself.

---

## 4. The Central Metaphor — An Organic Garden

Each habit is its own **plant**, growing from **seed → seedling → mature plant/tree**. The whole app is a garden that visibly flourishes as habits become ingrained.

- **Plant type varies by habit.** Meditation might be a lotus, strength training an oak, reading a fern. **Choosing your plant at creation is a quiet identity moment** — "I'm growing an oak" carries more meaning than "habit #3," tying directly to identity-based habits.
- **Plant art will be produced by a paid external designer.** Until then, plant visuals are a placeholder slot.

### The two-part plant model (behavior + awareness)

A plant has two halves, mapping the app's two core features onto one image:

- **Watering = the completion tap (the behavior).** Grows the plant **above** ground. This is the emotional core interaction.
- **Roots = the reflection / awareness work.** Grows the plant **below** ground. Every time you reflect on what cued you, the roots deepen.

A habit with many completions but little reflection is a **tall plant on shallow roots** — visibly a little precarious. That's a gentle nudge to reflect, without ever nagging. It also maps to real habit science: a mindlessly-performed habit can look impressive but topple in a bad week, while one where you understand your triggers is anchored. This makes tracking and reflection **visually inseparable**.

### The resilience model (stakes without guilt)

Fragility scales with growth stage — which is both good UX and psychologically true (new habits are fragile, old ones robust):

- **Seedlings wilt/droop fast** when neglected → creates the "my garden needs me" pull.
- **Mature trees shrug off** a missed day → no disproportionate punishment for an established habit.
- **Droop is always instantly recoverable** the moment you water.
- **Earned growth stages are banked and never lost.** Progress compounds; a bad day doesn't erase what you built.
- The neglect signal is an **invitation** ("your garden's looking a little thirsty"), **never an accusation** ("streak broken"). This deliberately avoids fragile streak mechanics.

---

## 5. Growth Engine (how a plant advances)

Advancement from seed to full bloom is **not** a raw streak. It's based on:

- **A rolling window of consistency** measured against a **user-specified target frequency**. The user states how often they *intend* to perform the habit — an **identity-based** commitment ("I'm someone who runs 3× a week"), not an app-imposed daily quota.
- **Forgiving early on.** You can't expect a new runner to run every day, so the early window is lenient and tightens as the habit matures.
- **Bloom requires both halves.** Full bloom needs **both** consistency (watering) **and** root depth (reflection). A habit **cannot fully bloom on autopilot** — the awareness work is required to reach the final stage. This is what makes the two core features genuinely interdependent rather than parallel.

### Open — needs to be worked out
The engine is decided *in principle* but the **actual formula is not yet nailed down**:
- Rolling window length (and whether it varies by stage).
- How forgiveness tapers as the habit matures.
- What root-depth thresholds gate each growth stage.

*This is the meatiest task for the "engine" workstream.*

---

## 6. Visual & UX Direction

**Emotional job of the home screen:** *"look how far you've come,"* not *"here's what you still owe."*

- **Home screen leads with accumulated progress** — the current state of your garden — **not** a list of pending tasks. This avoids the to-do-list dread most habit apps create and produces a "my garden could use some growth" pull toward doing the behavior.
- **The garden is alive even when there's nothing to do.** Gentle sway, light that shifts with the real time of day, soft weather. You open the app to *visit*, not to be reminded of work.
- **Visual tone:** warm, calm, tactile, organic — "journal, not spreadsheet." A restrained **2–3 color palette plus an accent**. Dark mode. Away from the clinical productivity look (stark white, hard grids, red/green).
- **The watering / completion tap earns real craft** — a water drop, soil darkening, the plant perking upright, a subtle haptic. **Not confetti** (overused, childish); something that feels physically gratifying, like the *thunk* of a well-made switch.
- **Reflection has its own softer, more conversational visual language**, distinct from the quick tracking UI — so the app has two moods: the satisfying *tap* of tracking, and the slower, thoughtful *check-in* of reflection.

### Open — for the "design" workstream
Because plant art is going to a paid designer, the design work should focus on **everything around the plants**: overall layout, palette, the watering animation, ambient garden behavior (sway / light / weather), and the reflection UI. Treat the plant illustrations as placeholder slots for now.

---

## 7. Summary of Major Decisions

1. Habit **designer**, not just a tracker — the cue → routine → reward loop is explicit and user-owned.
2. **Two journeys** (track existing / design new), **one reflection engine** with three framings (validation / discovery / diagnosis).
3. Reflection = **tap-not-type chips**, ~2–3×/week, payoff is **"aha" pattern surfacing**, and the app **graduates** automatic habits by backing off.
4. **Organic garden** metaphor; **one plant per habit**, plant type chosen at creation as an **identity moment**.
5. **Watering = behavior (above ground); roots = reflection (below ground).** Tall + shallow-rooted = precarious.
6. **Resilience scales with growth stage**; droop is recoverable, stages are banked; signals are invitations, not accusations. No fragile streaks.
7. **Growth engine** = rolling window vs. user's target frequency, forgiving early; **bloom needs both watering and roots**.
8. **Home screen leads with the garden** (accumulated progress); garden is **ambient/alive**; warm, calm, tactile visual tone; **crafted watering moment**, not confetti.

---

## 8. Next Steps / Open Threads

- **Engine workstream:** nail down the growth-engine formula (window length, forgiveness taper, root-depth thresholds per stage).
- **Design workstream:** layout, palette, watering animation, ambient garden behavior, reflection UI — with plant art as a placeholder pending the external designer.
- **Plant art:** commission the paid external designer for the per-habit plant set (seed → seedling → mature, across plant types).
