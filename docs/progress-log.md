# Taproot — progress log

*What has actually been built, in the order it was built, and what each piece decided along the way.*

The five specs describe the **target**. This file describes how the code got where it is, so that
picking the work up in a fresh worktree doesn't start with an archaeology session. For where things
stand *right now*, read [status.md](status.md) — this file is history, that one is state.

**Append-only.** Add a new entry at the top; don't rewrite old ones. When something recorded here
turns out to be wrong, add the correction as a new entry rather than editing history. A stale
"Next" inside an old entry is not a mistake — it is what was true at the time.

**One entry per meaningful chunk of work.** Keep each to: what landed, what it decided, what it left
open, and what comes next. Design *rationale* belongs in the governing spec (see
[growth-engine.md §10](growth-engine.md#10-implementation-reconciliations) for the pattern) — this
file points at it rather than repeating it.

Because entries are independent, this file is declared `merge=union` in `.gitattributes`: when two
branches each add an entry, both survive instead of conflicting. The one thing to check after a
merge is that the entries are still newest-first — union keeps both blocks but does not order them.

---

## 2026-09-02 — the app skeleton

Branch: `feature/app-skeleton`, stacked on `feature/local-store-and-repositories`.

### Landed

The wiring between `main()` and a screen. Nothing product-facing — the point of the branch is that
the database now opens **on a device**, which nothing had ever done outside an in-memory FFI test.

```
lib/app/startup/    app_startup (appStartupProvider, retryAppStartup)
                    app_startup_widget (loading · error-with-retry · through)
lib/app/logging/    logging (setupLogging, stopLogging)
lib/app/theme/      app_colors · app_spacing · app_radius · app_dimensions · themedata
lib/app/router/     app_router (goRouterProvider, the gate, AppRoutes)
lib/app/database/   database_provider — rewritten, see below
lib/features/garden/pages/           garden_page (placeholder shell)
lib/features/habits/pages/           habit_creation_page (placeholder shell)
```

One native fix came along for the ride, because without it the branch could not meet its own point:
`flutter run --flavor dev` did not build at all. `flutter_flavorizr`'s `ios:buildTargets` processor
points every flavor's build configuration at `AppIcon-$(ASSET_PREFIX)`, but `pubspec.yaml`
deliberately excludes its icon processor while the app art is with the designer — so `AppIcon-dev`
did not exist and Xcode refused the build. `ios/Runner/Assets.xcassets/` now carries `AppIcon-dev`,
`AppIcon-stg` and `AppIcon-prod` as copies of the default set. Fixing it there rather than by editing
`ASSETCATALOG_COMPILER_APPICON_NAME` keeps the generated build settings intact, so re-running
flavorizr does not undo it. They are placeholders; real per-flavor icons replace them.

36 new tests — 394 in total. Widget tests for `lib/app/` go in `test/app/`, mirroring `lib/app/` the way
`test/features/` mirrors `lib/features/`; the `ProviderContainer`-only ones stay in `test/unit/app/`.

### Decided

- **`appDatabaseProvider` no longer throws until overridden.** It is now derived —
  `databaseOpenerProvider` → `openedDatabaseProvider` (a `FutureProvider<Database>`) →
  `appDatabaseProvider` (`requireValue`). The old shape worked from `main()` but left a failed open
  with nowhere to land, and "a completion tap must never fail" means a database that will not open
  needs a screen, not a crash. Existing `appDatabaseProvider.overrideWithValue(database)` test
  overrides are untouched by the change.
- **The retry invalidates `openedDatabaseProvider`, not `appStartupProvider`.** This is the whole
  trap of the pattern: invalidating the startup provider alone re-runs its body, which awaits an
  `openedDatabaseProvider` still holding its cached error — so the button re-reads the old failure
  and does nothing, convincingly. `retryAppStartup(container)` is the single copy of that list, taken
  by `ProviderContainer` rather than `WidgetRef` so the button and the test run the same code, and
  there is a test asserting that the narrow version *would* fail.
- **Startup gates the whole app, inside `MaterialApp`.** `AppStartupWidget` sits in the router's
  `builder`, so its loading and error screens get the theme, directionality and media query like any
  other screen, and no route can be reached before the store is open.
- **The palette is written out, not seeded.** `ColorScheme.fromSeed` spreads one hue across
  Material's full tonal range and produces exactly the even, synthetic look design-spec §6 steers
  away from. Three hues — moss, bark, amber — plus warm neutrals; nothing is `#FFFFFF` or `#000000`,
  and the error tone is fired clay rather than alarm red. Light and dark are built by one function
  from a `ColorScheme`, so they can only differ in colour.
- **The gate is stubbed open, but its failure path is real and tested.** `resolveAppGate` returns
  the open gate because there is no auth, no profile row and no habit creation to read — reporting
  "no habits" today would strand every launch on a placeholder. The half that is easy to get wrong
  later is the `catch`, so that is written now: any error resolves to `failSafeAppGate`, which sends
  a user *onward* into habit creation rather than locking them out (guide §7), and the redirect only
  evaluates on the root path so it does not re-run per push.
- **`redirectFor` is a plain function.** Testing a guard by driving a navigator tests the navigator;
  the two rules worth protecting — root-path-only, and never guess while unresolved — are assertions
  about a function.
- **Logging takes an injectable sink.** `setupLogging` routes `package:logging` into
  `dart:developer`, at `Level.ALL` on dev/stg and `Level.WARNING` on prod. The sink parameter is what
  makes the level rules testable; before this branch every `Logger` in the services wrote to a root
  with no listener and was discarded.

### Left open

- **Supabase and Sentry are still not initialised.** The `.env` files hold no credentials and
  `Supabase.initialize` on an empty URL throws at launch; `lib/main.dart` documents the missing §4
  steps in place. They arrive with the first real backend call.
- **`AppGate` has one field.** `hasProfile` joins it when auth lands, `notificationsDecided` when the
  permission flow does — the latter matters, because a denied permission is a designed app mode and
  not an error.
- **The two pages are placeholder shells.** `GardenPage` carries the flavor readout and the "lead
  with accumulated progress" shape but no garden; `HabitCreationPage` exists so the fail-safe gate
  has a real destination rather than a 404.
- **No custom typeface.** The warmth comes from metrics — line height, letter spacing, body size —
  because the typeface is with the same designer as the plant art.
- **`GardenTicker` does not exist yet.** Ambient animation, reduced motion and the throttle that
  keeps widget tests out of a running animation arrive with the garden.

### Next

The completion tap: controllers over the four repositories, the press-and-hold watering gesture with
its non-gestural accessible path, and the undo window — the first feature code with a real screen.

---

## 2026-09-02 — local store and repositories

Branch: `feature/local-store-and-repositories`.

### Landed

The SQLite store and the four repositories that sit on it, plus the seam that lets the store drive
the engine:

```
lib/app/database/       app_database (schema, migrations, row encoding) · database_provider
                        store_exceptions · store_logging
lib/core/models/        habit (new) · toJson/fromJson on all five models
lib/core/utils/         json_codec
lib/features/habits/    domain: habit_repository, completion_repository,
                                completion_retraction
                        services: local_habit_service, local_completion_service,
                                  habit_inputs_loader
                        providers: habit_providers
lib/features/reflection/    domain + services + providers: reflections
lib/features/notifications/ domain + services + providers: the nudge ledger
```

166 new tests, written before the code. The two that matter most:

- **`test/utils/store_contract.dart`** is one behavioural contract run twice — against the SQLite
  services and against the in-memory fakes in `test/utils/fake_repositories.dart`. A fake that
  quietly disagrees with the real store is worse than no fake, because it makes feature tests pass
  against behaviour the app does not have.
- **`habit_inputs_loader_test.dart`** replays the spec's Young worked example *through the store* —
  writing rows and reading them back — and asserts the same stage the engine's own test asserts. A
  wrong column, a lost timezone or a dropped ledger row shows up as a different stage rather than as
  a green suite.

All three gates green.

### Decided

- **`ConflictAlgorithm.replace` is banned on `habits`.** sqflite implements it as DELETE + INSERT,
  which fires `ON DELETE CASCADE` and takes every completion, reflection and nudge with it. Upserts
  go update-then-insert inside a transaction.
- **Timestamps encode at millisecond precision.** `DateTime.toIso8601String` prints six fractional
  digits when microseconds are non-zero and three when they are not, and `"…00.000Z"` sorts *after*
  `"…00.000123Z"` as a string. Every range scan in the store — including the local-day window —
  depends on fixed width, so `encodeDateTime` truncates.
- **Sync plumbing lands now, before Supabase exists.** `pending_sync`, `updated_at` and a
  `deleted_at` tombstone are in v1 of the schema. Adding them on the sync branch would mean a
  migration over live local data.
- **No `user_id` in the local schema.** The local database belongs to whoever is signed in on the
  device; the sync layer stamps `auth.uid()` on push and the remote schema keeps it for RLS. This
  also makes a guest → account upgrade a no-op rather than a re-attribution pass. Switching accounts
  on one device would need a local wipe.
- **Every child write checks the habit itself** rather than leaning on the foreign key, so callers
  get a typed `UnknownHabitException` instead of a generic `DatabaseException` — and so a
  *soft-deleted* habit is rejected too, which the foreign key cannot see. That exception and
  `UnknownNudgeException` are expected-but-abnormal and deliberately never reach Sentry.
- **`recentReflections` does not filter.** Convergence is measured over the last 8 reflections and
  *then* narrowed to cue-bearing ones (§10). Filtering in the repository would hand the engine eight
  cue-bearing reflections and silently delete the "fewer than three ⇒ c = 0" rule.
- **`plantType` is a free string, not an enum.** The plant set is still with the external
  illustrator; closing the type now would be inventing a list the design spec does not have.
- **A completion tap can be undone, and an undo is its own append-only event.** An accidental tap
  while browsing the garden makes people feel they cheated, which is worse for motivation than the
  missed rep it fakes. `completion_retractions` is keyed by `(habit_id, completion_id)` and inserted
  into, never updated — so both ledgers merge as a union in either order and a stale replay of the
  completion cannot resurrect it. A `retracted_at` column on `completions` would have been simpler
  and would have made an append-only event mutable, dragging back the last-write-wins conflict
  handling that decision exists to avoid. The table has no foreign key to `completions`, because on
  sync the retraction can arrive first.
- **The undo window is the rest of the completion's local day, and stage may regress inside it.**
  Stage is a replay over history, so shrinking the history replays a lower rung — the window is what
  keeps that from reaching back into a plant grown weeks ago. The reasoning, and the two alternatives
  rejected (a stored stage floor; refusing the undo), are in
  [growth-engine.md §10](growth-engine.md#stage-is-monotonic-in-time-but-not-under-an-undo).

### Left open

- **The undo window's midnight edge.** A tap at 23:58 noticed at 00:03 cannot be undone. Added to
  growth-engine.md §9 as an open calibration question rather than patched with a second boundary.
- **A backfilled completion is not undoable**, because the window is judged on the day the completion
  records, not the day it was entered. `CompletionSource.backfill` exists but nothing creates one
  yet; revisit when the backfill UI does.
- **Undo does not clear a nudge's `confirmed` flag.** Autonomy self-corrects — it matches completions
  against occasions, so an undone completion drops out on its own — but the ledger column is left
  saying a nudge was confirmed by a completion that no longer counts. Cross-aggregate cascade belongs
  with the notifications branch, not in `CompletionRepository`.
- **Startup wiring does not exist yet.** `appDatabaseProvider` throws until overridden and
  `openLocalDatabase()` has no caller — `lib/app/startup/` arrives with the completion tap.
- **`onUpgrade` has no steps yet**, only the idempotent `ensureColumn` mechanism and a worked comment
  showing the shape. It is tested directly rather than through a v1 → v2 migration that does not
  exist.
- Nothing reads `pending_sync` yet. The pusher arrives with Supabase.

### Next

The completion tap: `lib/features/garden/` and `lib/features/habits/` controllers over these
repositories, `lib/app/startup/` opening the database, and the tap writing locally with no spinner
and no failure path — plus the undo affordance on top of `retractCompletion`. Worth settling there:
the *gesture*. A bare tap is what makes the accident possible in the first place, and design-spec
§ "the watering interaction" already asks for something with more craft than a tap — press-and-hold
or a drag makes the mis-tap structurally unlikely instead of merely recoverable. Then Supabase, whose migrations should mirror this schema column for column —
the model `toJson` keys are already the intended Postgres column names.

---

## 2026-09-02 — engine review and fixes

Branch: `feature/growth-engine`, on top of the entry below. PR [#1](https://github.com/LWitteman96/taproot/pull/1).

### Found

A review of the engine turned up **four correctness bugs, all invisible to the test suite for the same reason**: every fixture samples at whole days, 09:00, and every one of these needs either a sub-day sample or a non-default field to show itself. Worth internalising before writing the next batch of tests — a suite built entirely from tidy fixtures tests the tidy path.

| Bug | Symptom |
|---|---|
| Replay grid anchored to the evaluation instant's clock time | Stage regressed a rung between two openings of the garden screen on one evening |
| Whole paused days subtracted from a fractional elapsed | A paused plant drooped through the afternoon and sprang back at midnight, daily |
| `CueType.unknown` keyed on its type, and it is the default | Eight different cues read as perfect convergence, inflating the least self-aware user through Bloom's hard root gate |
| First-un-nudged-completion milestone read the last-10 autonomy sample | The milestone retracted itself, so it would have fired twice |

Plus two small ones — a phantom adherence window for Seed-stage habits, and an unvalidated `targetFrequency` where 0 throws inside the window arithmetic.

### Fixed

All six, with a regression test each, and the monotonicity property test widened to quarter-day sampling. That widened test was verified to *fail* against the old replay grid before the fix was restored — a property test that has never been seen to fail is an assumption, not evidence.

192 tests, all three gates green.

The durable lessons are written up as [growth-engine.md §10 — four invariants](growth-engine.md#four-invariants-the-implementation-has-to-hold), since they constrain future code rather than just recording history.

### Left open

The **clamp-collapse two-window rule** is now an open calibration question in §9 rather than a defect. Both readings satisfy §3 as written; the stricter one costs a weekly habit about six more weeks to bloom. It needs a product decision, and the review thread on PR #1 was deliberately left unresolved as the marker.

`pausedDaysBetween` has no caller in `lib/` since the pause fix — kept with a doc note warning against elapsed-time use, pending a call on whether to delete it.

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
