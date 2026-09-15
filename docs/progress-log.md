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

## 2026-09-15 — notification scheduling and the nudge ledger

Branch: `feature/notifications`, off `develop`, with the completion tap (PR #5) merged in.

### Landed

The evening check-in, and the ledger that makes autonomy measurable.

```
lib/core/engine/constants.dart          + the notification block; version → 2
lib/features/notifications/domain/      expected_occasions · nudge_decision ·
                                        evening_check_in · notification_access ·
                                        notification_gateway · nudge_payload
lib/features/notifications/services/    nudge_scheduler · local_notification_gateway ·
                                        disabled_notification_gateway ·
                                        nudge_response_recorder
lib/features/notifications/providers/   nudge_providers — gateway, scheduler, access,
                                        and the startup pass
lib/app/startup/app_startup.dart        step two: initialise the platform, then re-plan
android/…/AndroidManifest.xml           POST_NOTIFICATIONS, boot + action receivers
ios/Runner/AppDelegate.swift            the UNUserNotificationCenter delegate
```

58 new tests — 531 in total. Three gates green.

### Decided

- **A silent occasion is a row, and that is the invariant the whole branch is built around.**
  `NudgeScheduler` writes the ledger row *before* it queues anything, for every expected occasion,
  whatever it decided. The failure it is arranged against is the undetectable one: a missing row is
  indistinguishable from a habit that had no occasion that day, so autonomy would keep returning a
  confident answer computed over the wrong denominator. Tested as a row count that does not move
  when the fade rate does.
- **Occasion n falls on the creation date + `round(n × 7 / f)` days.** A habit carries `f` and
  nothing else — no weekday set — but autonomy counts *occasions*, so something had to name the
  days. Even spreading yields exactly `f` per rolling week at every `f`, never drifts over a year,
  and needs no stored schedule, so two devices replaying one habit derive the same dates. **This is
  an open calibration question, not a settled one** (see below).
- **Fading is a deficit rule, not a coin flip:** send unless `priorSent ≥ rate × (priorOccasions + 1)`.
  It makes Young's 0.70 exactly 7 in 10 rather than 7 on average, it is deterministic so a synced
  ledger replays identically, it front-loads (a new habit is never silent first), and it absorbs a
  stage change by withholding until the share falls to the new rate instead of restarting a counter.
  A random draw at Bloom's 0.10 can go 30 occasions silent, which the user experiences as the app
  having forgotten him.
- **Exact alarms are not requested, and neither permission is declared.** Guide §14 asks for the
  decision early: below Android 12 the app schedules exactly because nothing gates it; on 12+
  `canScheduleExactNotifications()` reports false and it schedules `inexactAllowWhileIdle`. An
  evening ritual slot does not need second-accuracy, `USE_EXACT_ALARM` would claim an
  alarm-clock-class use Play does not grant this app, and `SCHEDULE_EXACT_ALARM` would spend a
  full-screen settings trip on a few minutes of precision.
- **Denied permission records occasions anyway**, and reports the silence as `noPermission` rather
  than as a withhold. The rows are honest — no notification reached the user — and the plan
  distinguishes *the engine choosing* silence from *the app failing* to nudge, because only the
  first is a measurement.
- **The fade decision is made before the permission check**, so a user who declines notifications
  and later grants them does not resume mid-pattern at the wrong rate.
- **Startup never fails on notifications.** Step two is wrapped: a platform that will not initialise
  is a degraded mode, not an error screen in front of the garden. Off Android and iOS the gateway
  resolves to `DisabledNotificationGateway`, so the desktop test host runs the real startup path in
  the app's real denied mode rather than being a special case.
- **Reflection attaches to the notification through `ReflectionPromptComposer`.** Reflection and the
  next-day nudge are deliberately one notification (reflection spec §1) — look back at today, commit
  to tomorrow — so the scheduler asks for the backward-looking half and composes it onto the front
  of the body. `NoReflectionPrompt` answers null until that stage lands. The seam carries one real
  constraint for it: the question is composed when the notification is *queued*, up to
  `nudgeHorizonDays` before it fires.
- **`EngineConstants.version` → 2.** The notification block is not decoration: the occasion cadence
  decides which local dates autonomy is counted over, so it is a derivation input like any θ.
- **Notification ids are `nudgeId.hashCode & 0x7fffffff`.** The platforms key by `int`, the ledger
  by UUID, and re-planning has to replace a pending notification rather than duplicate it — so the
  mapping is a pure function of the row id rather than a counter.
- **A pending notification the OS lost is queued again.** A row that claims a nudge, for an occasion
  still ahead, with nothing pending at its id, is a reinstall or a restore. Left alone it is a nudge
  the ledger claims and the user never gets — the direction that corrupts the measurement rather
  than just missing a reminder.

### Left open

- **The occasion calendar is a default, not a resolved question.** Neither spec picks one. Letting
  the user choose weekdays at creation is better UX and worse measurement — someone who picks
  Mon/Wed/Fri and runs on Tuesday reads as a miss *and* an un-nudged occasion he never had. Worth
  instrumenting alongside the nudge-fade rates, which growth spec §9 already calls the single most
  important thing to measure.
- **Undo does not clear a nudge's `confirmed` flag.** Carried forward from the store branch and
  deliberately not built against the completion-tap branch while it was in flight. Autonomy
  self-corrects, but the column is stale and the insight surfaces that read confirms and declines
  directly (growth spec §8) would read it. `TODO(notifications)` sits on `markConfirmed`.
- **A schedule the platform refuses is not retried.** The occasion is recorded un-nudged, which is
  honest, but a transient failure permanently converts a nudge into something that looks like a
  deliberate withhold. Distinguishing the two needs a column the schema does not have — the same
  column that would let denied-permission occasions be excluded from the denominator.
- **Nothing calls `requestNotificationAccess` yet.** The permission prompt is a designed onboarding
  moment and onboarding does not exist, so a real device runs in the denied mode until it does.
- **A stage change takes up to a week to reach the notifications.** Rows inside the horizon are
  decided when they are planned and never re-decided, so a habit that climbs a rung today keeps the
  old rate on occasions already planned. Shortening the horizon trades that against how much of a
  quiet week survives a phone being off.
- **`planHabit` has no caller.** It exists for "re-plan after a completion" and is tested, but
  wiring it into the garden controller would have meant editing the completion-tap branch's code
  while it was still moving.

### Next

Supabase sync — a pusher over the `pending_sync` column, which the `nudges` table already carries
along with the other three.

## 2026-09-15 — completion tap review and fixes

Branch: `feature/completion-tap`, on top of the entry below. PR [#5](https://github.com/LWitteman96/taproot/pull/5).

### Found

Six defects from the review of the completion tap. Two are correctness, and both hide behind the same
gap: **the error paths had no widget-level test at all**, so the suite could not see either of them.

| Defect | Symptom |
|---|---|
| `clearError()` called synchronously inside `ref.listen` | `gardenErrorProvider` rebuilds twice in one frame; the debug scheduler throws `StateError: Tried to rebuild ... multiple times in the same frame` on *every* error path, in every dev run and every widget test |
| Rollbacks restore a `PlantState` snapshot taken before the await | Two quick holds, the first write stalls and fails: the rollback puts back the pre-first-tap plant and discards the second watering, which is on disk. The plant falls back to Seed and only recovers on the next cold start. Same shape on both undo rollbacks |
| `_pour.forward()` resumes instead of restarting | After an aborted hold, the fill reaches full 368ms into a 600ms gesture — the control looks finished while nothing has happened, and a release in that window waters nothing |
| A failed load falls through to the empty state | Someone whose store read failed is told "Nothing planted yet" as soon as the snack bar times out, and the copy promised a pull-to-refresh that existed nowhere in `lib/` |
| `ref` and the page's `BuildContext` used after the write's await | A card disposed mid-write — scrolled out of the `ListView.builder`, or dropped from `order` — throws from both `ScaffoldMessenger.of` and `ref.read` |
| The demo seed's flavor guard is inert | `getFlavor()` falls back to `Flavor.dev` whenever `appFlavor` is unset, so "dev" meant "nobody said" and a release build without `--flavor` would have shipped the seed button |

### Fixed

All six, with a test each — 469 tests, all three gates green. Three of the new tests were verified to
*fail* against the old code before the fix went back in: the `StateError` reproduces on three separate
error-path widget tests, and both rollback tests show the lost watering.

Two of the fixes are structural rather than local:

- **Rollback is surgical, not a restore.** `_dropCompletion` and `_restoreCompletion` work by
  completion id against *current* state. The rule generalises past this branch: any optimistic write
  that awaits must undo itself by identity, because a snapshot taken before an await is a claim that
  nothing else happened during it, and on the garden that claim is false by design — the tap is
  meant to be re-enterable.
- **"Could not read" is now a state, not just a message.** `GardenState.loadFailed` persists where
  `errorMessage` is transient by design, because an empty `order` after a failed read means "we could
  not look", not "there is nothing there". The page renders a distinct `_UnreadableGarden` with a real
  retry, and `couldNotReadGardenMessage` no longer promises a gesture that does not exist. A failed
  *refresh* with plants already on screen keeps the plants — the snack bar is enough there.

The seed guard is now `kDebugMode && flavor == Flavor.dev`. `kDebugMode` is the half that cannot be
got wrong by a forgotten flag — a compile-time constant that tree-shakes the seed out of a release
binary — and the flavor check stays alongside it so a *debug* stg or prod build is excluded once the
flavors are genuinely wired.

### Left open

The undo offer can still go stale across midnight; that is unchanged and still deliberate, and the
rollback fix makes the stale path more precise rather than removing it — a closed window now puts back
only the watering it could not retract.

The seed button itself is still scaffolding waiting on the designed habit-creation flow.

---

## 2026-09-09 — the completion tap

Branch: `feature/completion-tap`, on top of the app skeleton.

### Landed

The first product loop: open the app, hold a plant, watch it grow, take it back if that was a
mistake. It is also the first code that puts the engine, the store and a screen in the same sentence.

```
lib/app/runtime/            runtime_providers (clockProvider, newIdProvider)
lib/app/theme/              app_motion — durations as design tokens
lib/features/garden/
  controllers/              garden_controller (water, undo, refresh)
  domain/                   garden_state · garden_ticker · plant_descriptions
  providers/                garden_selectors
  widgets/                  watering_control · plant_card
  pages/                    garden_page — rewritten from the placeholder
lib/features/habits/services/  demo_habit_seed (dev flavor only)
```

42 new tests — 455 in total, all three gates green.

### Decided

- **The tap is optimistic, and the ordering is the feature.** `water()` re-runs `evaluateGrowth`
  against the history already in memory with the new completion appended, sets state, and only then
  writes. A completion tap must never fail, never spin and never be lost; awaiting a database before
  the plant reacts breaks the first two of those. That is why `PlantState` holds each habit's
  `HabitInputs` rather than re-reading four repositories per tap.

- **A failed write is rolled back, not swallowed.** Showing growth that was not stored is worse than
  showing the failure — the next launch would take it away again with no explanation. The two
  expected-but-abnormal cases are separated out: `UnknownHabitException` (deleted on another device)
  drops the plant from the garden with a sentence, and `CompletionNotRetractableException` (the undo
  offer went stale across midnight) says the window closed. Neither is an error report.

- **The gesture is a long-press recognizer, not a tap plus a timer.** Two reasons that both bite. Its
  down callback fires on contact, so the pour starts when the finger lands rather than after the tap
  arena's 100 ms deadline — a tap-based hold is silently 100 ms longer than its constant says. And it
  is in the gesture arena, so a slow scroll with a finger resting on a plant hands the pointer to the
  scrollable and cancels the hold, which is the accidental completion the whole decision exists to
  prevent. There is a test for exactly that.

- **`AppMotion.waterHoldDuration` is a design token, not an engine constant.** design-spec §6 says the
  hold duration belongs "in constants.dart with everything else", but `EngineConstants` carries a
  version stamp that cached derivations key off. Shortening an animation must not invalidate every
  stored stage in the app, so interaction timing lives in `lib/app/theme/app_motion.dart` with the
  other tokens. It is deliberately **not** scaled by `GardenTicker`: turning motion down must not make
  the accident easier.

- **`GardenTicker` has two dials, because ambient and transient motion fail differently.**
  `ambientEnabled` governs the endless loops that hang `pumpAndSettle`; `motionScale` governs finite,
  caused animation, and at 0 those resolve to their end state rather than being skipped. A platform
  reduced-motion preference wins over the app's setting, folded in by `gardenTickerOf`.

- **The accessible path changes the words, not just the wiring.** The control carries a semantics
  action that waters on a plain activate, *and* renders as an ordinary button when the platform
  reports assistive navigation — because telling a switch-control user to "hold to water" is worse
  than not offering the gesture at all.

- **Plant state is written out in words.** `plant_descriptions.dart` turns stage, vitality and root
  depth into labels. That is the semantics layer the illustration will still need once it exists —
  it hangs on the card, which is exactly where the art will go — and it is also what lets a widget
  test assert on a plant at all. The watering button gets an *action* label instead, because a
  control that repeats the description makes a screen reader read the plant twice before offering
  the one thing there is to do.

### Found

**`SnackBar.persist` defaults to `action != null`.** Adding the undo action to the watering
confirmation silently turned its `duration` off, so the offer sat over the garden until something
else replaced it. `persist: false` is now passed explicitly, with a comment, and a test watches the
offer expire. Worth remembering generally: a Flutter default that depends on another argument is not
visible at the call site.

**A `late final` `AnimationController` is a disposal bug waiting for the right branch.** The assistive
path never touches the pour, so `dispose()` was the first thing to reach the field — constructing an
`AnimationController` on an element that is already deactivated. It is built in `initState` now. The
accessibility test is what found it, which is the argument for writing that test first rather than
last.

**A card that describes itself will swallow its own buttons.** Running the app on the simulator and
reading the accessibility tree — not the widget tests — showed the plant's state announced twice,
once as card text and once as the watering button's label. Fixing that by moving the description onto
the card and giving the button an action label ("Water Morning walk") then exposed the real defect
underneath: `Semantics(container: true)` merges its descendants by default, so after a watering the
card was **one node carrying two tap actions**, of which a screen reader can only reach one — the
undo would have been unreachable. `explicitChildNodes: true` keeps them separate, and a test now taps
undo through the semantics tree rather than through the widget tree.

The general lesson: a widget test can assert a label is present, but only the real accessibility tree
shows what a screen reader actually *hears*. Run the app for this.

### Left open

- **Habit creation is still a placeholder**, so the only way to get a habit into the store is
  `plantDemoHabit`, a dev-flavor button on the empty garden. It is scaffolding and is meant to be
  deleted: writing a stand-in form now would front-run the designed flow — the two journeys, the
  plant-type identity moment, the cue/routine/reward triple. Its flavor check is inside the function,
  not only at the call site, so it cannot write to a production store from somewhere else later.
- **The router's gate stays stubbed open.** `hasFirstHabit` could be read from the habit count now,
  but sending a first launch to a placeholder creation page would strand it. The gate becomes real
  with habit creation.
- **The press-and-*swipe* is not built.** design-spec §6 asks for a hold "ideally a press-and-swipe
  that tips a watering can"; what ships is the hold, with the pour as a fill. The watering can is part
  of the same illustration work the plants are.
- **`completion.wasNudged` is false everywhere**, because nothing writes the nudge ledger until the
  notifications branch. That is honest rather than provisional — no nudge was sent, so none was. The
  controller already reads the ledger for today's occasion, so it starts telling the truth the moment
  rows exist. Autonomy does not depend on this flag; it matches the ledger against completions itself.
- **Undo does not clear a nudge's `confirmed` flag** — unchanged from the store branch, and still
  cross-aggregate work that belongs with notifications.
- **The undo offer on a card can go stale across midnight.** `PlantState.undoableCompletion` is
  evaluated, not live, so a garden left open overnight still shows the button. The repository
  re-judges the window and the controller explains it — the affordance is optimistic, the boundary is
  not.
- **No `GardenTicker` consumer sways yet.** The abstraction exists and the pour sits behind it; the
  ambient garden it was built for arrives with the rendering.

### Verified on device

Built and run on the simulator under the dev flavor, because the point of the hold is how it behaves
and no widget test can report that: the seed plants a habit, the hold moves the plant Seed → Sprout in
place, the control relabels to "Hold to water again", the card grows its standing Undo and the
transient offer appears. The accessibility-tree read that found the merged-node bug above came from
the same run.

### Next

Supabase sync: the project, the migrations mirroring this schema column for column, RLS, and a pusher
over the `pending_sync` column the store already writes. The model `toJson` keys are already the
intended Postgres column names.

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
## 2026-09-02 — store review and fixes

Branch: `feature/local-store-and-repositories`, after review of PR #2.

### Landed

Nine findings, seven fixed, two answered. 377 tests, all three gates green.

**Two findings were the same bug twice: a whole-row upsert writing columns the model does
not own.**

- `saveHabit` wrote `paused_at` straight from the model. A stale `Habit` — an edit form
  holding a copy loaded before the pause — cleared the stamp while leaving the interval open.
  The habit then read as *unpaused* (so nothing offered Resume) while the engine saw
  `ended_at IS NULL` and treated every following day as paused: vitality frozen, with no way
  back through the public API.

  Fixed by deleting the column. **Paused state is the existence of an open `habit_pauses`
  row**, and the repository joins it back on when reading — one home for one fact, so the two
  cannot disagree. `Habit.toJson()` no longer emits `paused_at` while `fromJson` still reads
  it, which is what lets the repository hand the derived value back. This is the same rule the
  engine values follow; it just took a bug to notice `paused_at` was on the wrong side of it.

- `saveNudge` overwrote `sent`, `confirmed` and `declined`. A scheduler re-saving an occasion
  after `markSent` flipped `sent` back to 0, moving an occasion that *was* nudged into
  autonomy's un-nudged denominator and quietly depressing the graduation gate. A save now
  restates the schedule; the outcome belongs to the `mark*` methods once the row exists.

**The rest:**

- **`UNIQUE (habit_id, expected_occasion_at)` was the wrong grain both ways.** `computeAutonomy`
  matches occasions to completions by *local date*, so two occasions hours apart on one day
  both counted; and a genuine duplicate raised an untyped `DatabaseException` that `guardStore`
  logs at `severe`, defeating the typed non-reportable policy. The constraint is gone;
  `LocalNudgeService` enforces one occasion per habit per local day and reports
  `DuplicateOccasionException`. A local date cannot be expressed as a SQL constraint over a UTC
  timestamp, which is why this could not stay in the schema.
- **`target_frequency` now has a `CHECK (BETWEEN 1 AND 7)`.** `Habit` and `HabitInputs` both
  assert it and release builds strip asserts; a stored 0 divides through the engine as
  `Infinity` and throws in `.ceil()`, in production only.
- **`saveHabit` no longer matches tombstones.** It used to report success on a soft-deleted
  habit while `habitById` returned null and every child write threw. Now a typed
  `UnknownHabitException`, like every other write against a deleted habit.
- **`recordRetraction` added** for the sync path. `retractCompletion` is the user's undo and
  checks existence and the window; ingestion checks neither, because a retraction can arrive
  before the completion it retracts (which is why that table has no foreign key) and the window
  was already judged on the device where undo was pressed. Re-judging it here against another
  clock in another timezone would drop legitimate undos. The schema test that proved the insert
  was *possible* now has a repository path that makes it reachable.
- **`FakeNudgeService` gained the same local-date rule**, and all of the above went into
  `store_contract.dart` first — so both implementations are held to it rather than only the
  real one.

### Answered, not fixed

- **`openLocalDatabase()` has no caller.** Correct, and it is the whole job of
  `feature/app-skeleton`, which is already branched off this one.
- **`HabitInputsLoader` does four unbounded scans per habit.** The deliberate trade recorded in
  the entry below: the ladder replays from the start, so a windowed read would silently change
  the answer rather than fail. It becomes real work when the garden renders many plants —
  a batch path and a cache keyed by `EngineConstants.version`, not a narrower query.

### Left open

- The undo window edge cases from the entry below are untouched.
- Nothing enforces "one occasion per local day" across a *sync merge* — two devices can each
  write a row for the same day and the union keeps both. The pusher will need to reconcile.

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
