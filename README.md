# Taproot

**A habit app that helps you *design* habits, not just tick them off.**

Most habit trackers treat the cue and the reward as invisible app defaults — the notification *is*
the cue, the streak counter *is* the reward. The user never consciously architects anything. Taproot
makes the **cue → routine → reward** loop a first-class object the user owns, tests, and refines
over time.

---

## The garden

Every habit is a plant, and the plant has two halves:

- **Watering — the completion tap.** Grows the plant *above* ground. The behavior.
- **Roots — the reflection.** Grows the plant *below* ground. The awareness.

A habit with many completions but little reflection renders as a **tall plant on shallow roots** —
visibly top-heavy, a little precarious. That's not decoration; it's the data model made visible. A
mindlessly-performed habit really can look impressive and topple in a bad week, while one whose
triggers you understand is anchored.

It also means the two halves of the product are *interdependent rather than parallel*: **a habit
cannot reach full bloom on autopilot.** Consistency alone gets you to Mature. Understanding is what
blooms it.

Fragility scales with growth stage, the way it does in life — seedlings wilt fast and mature trees
shrug off a missed day. Earned stages are banked and never lost, droop is always instantly
recoverable, and the neglect signal is an invitation ("your garden's looking thirsty"), never an
accusation ("streak broken").

---

## The engine

Four state variables per habit, deliberately kept separate so the app can be demanding about growth
and forgiving about setbacks at the same time:

| Variable | Meaning | Behavior |
|---|---|---|
| **Stage** | How big the plant is | Monotonic — earned, never lost |
| **Vitality** | How healthy it looks right now | Fluctuates daily, snaps to full on watering |
| **Roots** | How well the loop is understood | Grows with reflection, saturating |
| **Autonomy** | Does the habit fire *without* the app? | The bloom gate and graduation trigger |

> Stage is the reward. Vitality is the pull. Roots are the gate. Autonomy is the point.

### The idea I'm most interested in: the app fades itself out

The evening notification rehearses the user's own cue — *"tomorrow, after breakfast, we're running,
right?"* — which strengthens the breakfast→run association rather than the app→run association.

But the failure mode sits right next to it: **if the app nudges every time, the notification becomes
the cue**, and you've built the exact product you set out to differentiate from, with more ceremony.

So the engine **deliberately withholds its own nudges** at a rate that rises with stage (100% at
Seedling, 40% at Mature, ~0% at Bloom) and measures what happens on the occasions it stayed quiet:

```
Autonomy = completions on un-nudged expected occasions / un-nudged expected occasions
```

The skipped nudges aren't restraint — they're **the measurement instrument**. You cannot know
whether a habit stands on its own until you stop holding it up. Bloom requires `Autonomy ≥ 0.5`, so
a habit that only fires when prompted can never fully bloom, however perfect its completion record.

Graduation is the endpoint: when a habit is genuinely automatic, the app notices and **backs off** —
*"this one seems locked in, we'll stop asking."* Knowing when to stop is what separates a thoughtful
app from a nagging one.

---

## Status

**The loop is closed.** You can design a habit, water it, get asked about it in the evening, answer,
and have all of it survive a reinstall. Everything in the build order is built except the last two
entries.

What runs today:

- **Habit creation** — the cue → routine → reward flow, with *"I already do this, just track it"* as
  a deliberate opt-out rather than an equal choice at the front door
- **The completion tap** — press-and-hold to water, with an undo window and a non-gestural path
- **The engine** — stage, vitality, roots and autonomy, derived from the ledgers on every read, never
  stored
- **The evening check-in** — scheduled on-device, with the nudge fading actually implemented: the
  ledger records the occasions the app *chose to stay quiet on*, because those are autonomy's
  denominator
- **Reflection** — priority scoring, the five framings, and the authored chip library's surfacing rule
- **Offline-first storage** — SQLite as the primary store, with Supabase sync (paged pull over an
  overlap cursor, last-write-wins enforced by a trigger rather than by convention)

What's left: **garden rendering** — plants currently render as words, since the art was blocked on an
external illustrator; procedural generation is being explored on a branch — and **insight
surfacing**. Also unbuilt: auth screens, a provisioned remote Supabase project, and Sentry
initialisation.

[`docs/status.md`](docs/status.md) is the current state, area by area.
[`docs/progress-log.md`](docs/progress-log.md) is the append-only record of how it got here — what
each stage decided, and what it left open.

---

## Documentation

The specs came first and still lead the code. All seven documents live in [`docs/`](docs):

| Document | What it covers |
|---|---|
| [design-spec.md](docs/design-spec.md) | Concept, positioning, competitive landscape, the garden metaphor, visual direction |
| [growth-engine.md](docs/growth-engine.md) | The formulas — adherence, the stage ladder, vitality/droop, roots, autonomy, pressure valves |
| [reflection-logic.md](docs/reflection-logic.md) | When to prompt, what to ask, the cue and friction taxonomies, insight detection rules |
| [starter-chip-library.md](docs/starter-chip-library.md) | 144 cue chips and 94 friction chips across 12 categories, plus the surfacing rule |
| [infrastructure-guide.md](docs/infrastructure-guide.md) | Every stack decision, with rationale and the traps worth not repeating |
| [status.md](docs/status.md) | Where every area stands right now — the mutable half of the record |
| [progress-log.md](docs/progress-log.md) | Append-only, newest first: what each stage landed, decided, and left open |

Each spec ends with its **open calibration questions** stated plainly rather than papered over. The
numbers throughout are calibrated defaults meant to be tuned against real data — not laws.

---

## Stack

Flutter + Supabase, chosen to match an existing production app so the proven patterns transfer.

- **Flutter** (Dart ≥ 3.10) targeting iOS and Android
- **Riverpod 3**, hand-written — no code generation, no `freezed`, no `build_runner`
- **go_router** for declarative routing with a redirect gate
- **Supabase** — auth, Postgres with explicit RLS, edge functions
- **sqflite** — offline-first local store. A completion tap must never fail, never spin, and never be
  lost; it happens in gyms, on trails, and on airplanes
- **flutter_local_notifications** + **timezone** — the evening check-in, scheduled on-device because
  the decision of *whether* to nudge depends on engine state that already lives there
- **Sentry** for error reporting

---

## Running it

```bash
flutter pub get
flutter run --flavor dev
```

Per-flavor entry points are wired up — `--flavor dev|stg|prod`, each with its own entry point, bundle
id and `.env`. `.env.dev` points at a local Supabase stack; stg and prod are placeholders, since no
hosted project is provisioned yet.

`flutter analyze`, `dart format --set-exit-if-changed .` and `flutter test` are the three gates, and
stay green in every commit — **923 tests** at the time of writing. The backend has gates of its own,
run only when `supabase/` changes: `scripts/supabase-verify.sh` applies every migration from scratch,
re-applies them to prove they are re-runnable, runs a **48-assertion pgTAP suite** over the schema and
the RLS policies, and deletes an account end to end through the edge function.

Two CI gates exist because a check that cannot fail is worse than no check: one asserts every source
file is text (a NUL byte makes git treat a file as binary, so its contents appear in no diff), and
the credential scan now plants a fake key inside a binary blob and fails the build if it *doesn't*
find it.

---

## A note on scope

This is a portfolio project, built in the open. The specs went first on purpose — I wanted the hard
product thinking settled, and the failure modes found, before writing the engine that depends on
them. The code has caught up; the specs still lead it, and their open calibration questions are still
open.

Every stage was reviewed before it merged, and the reviews are in the progress log alongside the work.
The one practice worth stealing came out of them: several tests were found that could not fail — one
asserted a state the fixture already had, one asserted something the type system guaranteed, one
asserted a relation that held for a reason other than the one under test, and one was a self-test
*about* that very problem. So the standard here is not "does a test exist" but **"does a test exist
that could fail"** — revert the fix, and watch the named test go red.
