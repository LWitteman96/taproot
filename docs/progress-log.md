# Taproot — progress log

*What has actually been built, in the order it was built, and what each piece decided along the way.*

The five specs describe the **target**. This file describes the **state**, so that picking the work up
in a fresh worktree doesn't start with an archaeology session. It is append-only: add a new entry at
the top, don't rewrite old ones. When something recorded here turns out to be wrong, add the
correction as a new entry rather than editing history.

**One entry per meaningful chunk of work.** Keep each to: what landed, what it decided, what it left
open, and what comes next. Design *rationale* belongs in the governing spec (see
[growth-engine.md §10](growth-engine.md#10-implementation-reconciliations) for the pattern) — this
file points at it rather than repeating it.

---

## Where the project stands

| Area | State |
|---|---|
| Flavors (dev / stg / prod) | Built — entry points, resolver, native config |
| CI, lint, pre-commit hook | Built |
| **Growth engine** (`lib/core/engine/`) | **Built — stage, vitality, roots, autonomy, adherence, renegotiation** |
| Local SQLite store + repositories | Not started |
| Supabase project, migrations, RLS | Not started |
| Notification scheduling + nudge ledger | Not started |
| Reflection check-in and chips | Not started |
| Garden rendering | Not started (blocked on external illustrator) |
| Insight surfacing | Not started |

Build order from the infrastructure guide (§16): engine → local store and repositories → completion
tap → Supabase sync → notifications and the nudge ledger → reflection check-in → garden → insights.
The engine is done, so **the local store is next**.

---

## 2026-09-02 — growth engine core

Branch: `feature/growth-engine`.

### Landed

Pure-Dart engine under `lib/core/engine/`, no Flutter imports and no I/O, with the models and the
local-date helper it needs:

```
lib/core/engine/    domain · constants · inputs · pauses · adherence
                    vitality · roots · autonomy · ladder · renegotiation · engine
lib/core/models/    completion · reflection · nudge · pause_interval
lib/core/utils/     local_dates
```

`evaluateGrowth(inputs:at:)` is the facade: it returns stage, vitality, roots, autonomy, the current
adherence window, the shallow-rooted flag, the renegotiation trigger, graduation, and the constants
version in one object.

180 tests across 9 files, written **before** the engine existed. The spec's worked examples are in
`test/unit/engine/worked_examples_test.dart` and are the highest-signal file in the suite — f=3
reaching Young at 5 completions in a 19-day window, a seedling drooping at 2.8 days and wilting at
5.8, `N/(N+4)` giving 0.50 at 4 and 0.83 at 20, the f=1 clamp collapse, the pace exemption at 6 of 7.
Stage monotonicity is covered by a property test over random input sequences.

All three gates green.

### Decided

Six reconciliations where the spec's prose and its formulas disagreed, written up in full in
[growth-engine.md §10](growth-engine.md#10-implementation-reconciliations). The two with the widest
blast radius:

- **The ladder is sequential.** A stage's qualifying window may not open before the previous stage was
  earned. This is what produces the spec's ~96-day floor for bloom; without it a flawless user blooms
  in six weeks. It also makes stage a *replay over history* rather than a stored maximum.
- **Convergence is measured over the last 8 reflections, then filtered to cue-bearing ones** — not
  over the last 8 cue-bearing reflections. Only this reading gives the `< 3 ⇒ c = 0` rule any teeth.

Two decisions that are worth knowing before touching the code: `ceil(0.8 × f)` needs a floating-point
guard, and every window is local-calendar arithmetic via `local_dates.dart`.

### Left open

- **The wilt freeze** has two defensible readings and the literal one is implemented. Added to
  growth-engine.md §9 as an open calibration question. It is one constant to change
  (`EngineConstants.wiltFreezeFloor`) if the other reading wins.
- The spec's existing open questions (θ at bloom, autonomy ≥ 0.5, nudge-fade rates, wilt duration at
  Sprout, advisory root thresholds) are untouched — implemented at their defaults, all in
  `constants.dart` under `version = 1`.
- Models have `copyWith` but **no `toJson`/`fromJson` yet**. Hand-write them with the SQLite layer,
  where the column names are decided.

### Next

Local SQLite store and the split repositories (`HabitRepository`, `CompletionRepository`,
`ReflectionRepository`), then the completion tap writing locally. Derived engine values are computed,
never stored — if they get cached, the cache key includes `EngineConstants.version`.

Two things the engine assumes that the store must deliver: a `nudges` row for **every** expected
occasion including the ones deliberately not sent (it is the autonomy denominator, and cannot be
inferred from the absence of a notification), and completions as append-only events keyed by
`(habit_id, local_uuid)` with the UUID generated client-side.
