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

## 2026-09-16 — the question on the notification

Branch: `feature/check-in-composer`, off develop with the check-in merged.

### Landed

The reflection half of the evening notification. `NoReflectionPrompt` is replaced by
`CheckInPromptComposer`, which answers the same question the check-in screen answers, through the
same functions — `occasionFor`, `selectCheckIn`, `checkInQuestion`. One message, two halves: look
back at today, commit to tomorrow (reflection spec §1).

```
lib/features/reflection/services/  check_in_prompt_composer
lib/features/notifications/        nudge_scheduler — one question an evening, and the refresh
lib/core/engine/constants.dart     nudgeQuestionRefreshWindow
```

11 new tests — 776 in total. Three gates green.

### Decided

- **Two clocks, and they are not interchangeable.** A nudge for day D is delivered on the evening of
  D − 1, and composed when it is queued — up to seven days before that. So detection runs at
  `min(now, deliverAt)` and never later, while the *wording* is rendered at `deliverAt`. The first
  is a correctness rule: the ledger holds rows for occasions that have not happened, which is the
  scheduler's whole job, and detecting at a future `deliverAt` would read every one of them as a day
  the user failed and queue *"No morning run on Thursday — what got in the way?"* about a Thursday
  nobody has lived. The second is a wording rule: a question composed tonight and read tomorrow has
  to say `yesterday` where the screen would have said `today`.
- **One question an evening, across every habit, and the pass is the only place that can enforce
  it.** §1 buys "one consistent conversational slot instead of two competing interruptions", which
  is a claim about the user's evening rather than about one plant. The composer is asked about one
  habit at a time and would say yes to all three; the planning pass sees them all, so it carries the
  set of evenings already spoken for. Habits are planned in creation order, so the older habit keeps
  the question — the same tie-break the pending-notification cap uses, and stable across passes.
- **A queued notification is re-composed once it is within a day of firing.** The note on
  `ReflectionPromptComposer` already said re-planning on every launch and after every completion is
  what keeps the question from going stale. It was not true: the pass re-queued a notification only
  when the OS had *lost* it, so the first pass's guess — written against a day that had not happened
  — was what the user read a week later. The window is 24 hours because the question is about today,
  and it is also what bounds the cost: at one occasion a day only the next evening's notification is
  ever in range, so a pass re-queues at most one per habit. That matters because a pass now runs on
  every launch, every completion *and* every resume.
- **The seam is tested at the wire, not only at both ends.** The composer's own tests construct it
  directly and the scheduler's tests inject a fake, which covers both sides and leaves the join
  uncovered: swapping the provider back to `NoReflectionPrompt` left the whole suite green while
  every notification lost its question. That is the same defect this branch fixes in the refresh
  path, and the same one the review of PR #10 found twice — **a property that holds by default in
  every scenario the tests create, so nothing can fail when it stops being true**. `NoReflectionPrompt`
  answering null is the default; a test that never reads the real provider never disturbs it. The
  useful question about a guard is not whether a test exists but whether a test exists that *could
  fail*, which for a default-valued seam means exercising a non-default value. One test now reads
  the real provider graph and asserts a real sentence.
- **The question is scored, not attached.** Most evenings carry no question at all, and that is the
  design: §2's priority threshold, the per-habit weekly budget and the 24-hour cooldown all gate it,
  and most days nothing has happened that is worth asking about. The budget is counted at the
  evening the message *arrives*, not the evening it was written, so a question queued on Monday for
  Thursday is Thursday's spend.

### Left open

- **A question is composed per pass, not per delivery.** Inside the refresh window that distinction
  does not matter; outside it, a notification the user reads without the app having been opened that
  day carries the last answer the app could compute. There is no way around that without a
  background task, and a background task to refine the wording of a notification is not worth what
  it costs.
- **The invitation preview on `feature/notification-onboarding` still composes with two arguments
  where the scheduler passes three** — so it shows the nudge half only. Harmless until this branch
  lands, and owned by that branch (PR #10), which is binding the preview to the composed sentence
  and correcting the copy that promises a question on every message. Coordinated rather than fixed
  from here, so the widget keeps one owner.
- **Nothing reads the answer differently for having been asked by a notification.**
  `Reflection.wasNudged` still records it faithfully and still nothing consumes it.

### Next

Supabase sync, per the build order, unless the settings surface #10's two Left-opens point at lands
first.

---

## 2026-09-15 — the reflection check-in

Branch: `feature/reflection`, on top of notifications.

### Landed

The evening check-in, end to end — which question, about what, with what to tap, and where the
answer goes:

```
lib/features/reflection/
  domain/     daypart · starter_chip · starter_chip_library · chip_surfacing
              friction_surfacing · framing_selection · reflection_priority
              check_in_scheduler · occasion_detection · remembered_chips
              cue_families · check_in_question
  services/   check_in_assembler
  controllers/check_in_controller
  pages/      check_in_page
  widgets/    cue_answers · friction_answers
```

The authored library from starter-chip-library.md §6–§7 is in as data: 144 cue chips, 94 friction
chips, twelve categories. Everything that decides anything is a pure function over values, so the
only part that touches a repository is the assembler.

135 new tests — 765 in total, with the review round below. **The spec's 24 worked examples are a
test file**, for the same reason the engine has
one: they were computed by hand from the rule, so they are a specification and a test suite at once,
and every guard in §5.3 is exercised by at least one of them.

### Decided

**Chip scores are compared at the precision the library is authored to, not as raw doubles.** Every
prior and bonus in §5.1 is given to two decimals and exact ties are common — `packed my bag` and
`first thing up` both reach 0.65, `10pm hit` and `eyes got heavy` both reach 0.60. In binary those
pairs land a few ulps apart, so comparing raw doubles resolves a *documented* tie by representation
error and the authored tie-break never runs. Four of the worked examples come out in the wrong order
without the tolerance. **This is not a rounding nicety to be cleaned up later** — deleting it
silently changes which chips users are offered.

**§5.3's two degradations have different triggers, and reading both the same way breaks the type
ceiling.** Backfill fires "if fewer than *n* chips **clear the floor**" — a statement about the
*pool*. Relaxation fires "if still short" — a statement about the *selection*. Reading both off the
selection is the obvious simplification and it is wrong: any time the ceiling binds, the set is
short, so a backfill fires and pulls in another chip of the very type the ceiling was limiting.
Reading logged in the afternoon is the worked case — five chips clear the floor, the ceiling holds
three events, and the backfill would add `got home`, a fourth. The ceiling becomes a no-op that
looks like it is working.

Because both degradations are permitted, the result object reports **which** fired
(`backfilledFromGlobalPool`, `relaxedTypeCeiling`, `nonEventFloorUnmet`). §9 says the floors
"currently produce sensible behavior on the 24 worked examples, which is not the same as being
right", so whoever tunes them needs to see which step ran — and a test needs to tell "the ceiling
held" from "the ceiling was lifted".

**`cue_families.dart` closes half of an open question, and only half.** §9 says conditional unlock
"needs a text→family mapping ... a small keyword table per family is probably enough to start; it
does not need to be a model." This is that table. It was needed here for a second reason §9 does not
mention: without a family for the *designed* cue, filter §5.2.2 never fires and a first reflection
can offer the pinned cue twice — which the spec itself calls a wasted slot that looks like a bug.
The table is **deliberately partial** — exact label matches first, then keywords for the families a
user is most likely to phrase themselves — and the unlock half of §9's question stays open: nothing
yet *uses* a typed answer to unlock a conditional chip. A wrong match costs one chip slot.

**Three reconciliations where the specs name two shapes.** The early bonus is "+0.4 while n < 5,
decaying", which is both a flat step and a taper; implemented as a linear taper, because a flat step
drops the whole bonus at once and can silence a habit exactly when the user has started answering.
"First completion after droop" is not a third anomaly beside "unusual gap" — a droop is what a long
gap produces, so counting both double-counts one event. And the once-a-day rule is **app-wide** while
the weekly budget is **per habit**: §1 gives the app "one consistent conversational slot" in the
user's day, and §2 fades the budget by *stage*, which is a property of a habit.

**Remembered chips decay with a half-life of eight reflections.** §4 asks for "recency-weighted
frequency" without giving a decay. Eight is the window convergence already measures over, so
"recent" means the same span in both places. Frequency still counts: a cue named a dozen times
outranks something said once last night, which is correct — that *is* the user's cue.

### Left open

- **There are no reward-side chips, and that stays true here.** §9 names it: the design spec makes
  reward an explicit half of the loop, reflection-logic only ever asks about cues and friction, and
  the `motivation` friction routing — "revisit what follows the routine" — has nothing to offer when
  it fires. Not built, deliberately. That routing is an **insight-surfacing** concern (§6), which is
  its own build-order stage; building a reward-revisit affordance here would front-run it the way a
  stand-in creation form would have front-run habit creation. What this stage contributes instead is
  recording `frictionType` faithfully, including the authored mappings that only make sense as
  routing signals — `didn't feel thirsty` → motivation, `skipped my workout` → forgot.
- ~~**The check-in is not wired to the evening notification.**~~ Done on
  `feature/check-in-composer`; see the entry above.
- **Two authoring gaps in the library are now visible at run time.** Reading logged mid-morning
  cannot meet the non-event floor — §8 names it — and early-morning journaling has one event anchor.
  The rule reports falling short rather than falling short quietly; the fix is authoring 2–3 more
  chips into each, not ranking.
- **Insight surfacing (§6) is untouched.** Every detection rule there reads reflections this stage
  writes, so the data is now there; nothing reads it yet.
- **The nudge ledger cannot say *why* a nudge was not sent, and that is the column this stage wants
  most.** `NudgeScheduler._decide` distinguishes `withheld`, `deliveryPassed`, `noPermission` and
  `overCap`; `NudgeRecord` persists `sent` and `scheduledFor`, and the reason is lost. Autonomy's
  denominator has inherited that ambiguity since the engine was written (`autonomy.dart`), but this
  is the first consumer that both scores it at the top weight *and* says it out loud to the user, so
  the gate above is a stand-in, not a fix: it reads "was the app nudging this habit that week" as a
  proxy for "was this silence chosen". A `suppression_reason` column on `nudges`, written from the
  decision the scheduler already computes, closes it here and in the engine at once. It needs a
  migration and a backfill decision for existing rows, which is why it is not in this branch.
- `Reflection.wasNudged` is recorded faithfully but nothing consumes it. Kept honest because the
  question it answers later — do people reflect differently when asked? — cannot be reconstructed
  once the rows are written.

### Then, the review round

Two reviews on PR #9 — eight correctness findings and six efficiency ones — and the fixes for all of
them are in this branch.

The three that changed behaviour rather than shape:

- **Today read as a miss from one minute past midnight.** The scheduler stores
  `expectedOccasionAt` as `startOfDay`, so today's row is in the past all day: a 19:00 runner
  opening the app at 08:00 got `Occasion.miss` → `Framing.diagnosis` → *"No running today — what got
  in the way?"*, eleven hours early. An occasion is now missable only once its day is over **or** its
  own evening check-in slot has passed, which is the moment reflection spec §1 says the app looks
  back at today. The unit helpers built rows at 07:00 — a shape that does not exist on disk — which
  is what hid it; they build `startOfDay` rows now, and the suite reads real ledger data.
- **`sent: false` is four states, and only one of them is autonomy.** The fade rule choosing silence,
  an evening already past when the backfill ran, no permission, and the pending cap all persist
  identically, because `_decide`'s reason is dropped before the row is written. A user who declined
  notifications had *every* completion scored at autonomy's top weight and answered with *"You did
  this without us asking"* — an app claiming a restraint it was never allowed to exercise. The claim
  is now gated on evidence that the app was demonstrably nudging that habit around the occasion: a
  sent row within a horizon either side. The storage is unchanged deliberately; see Left open.
- **One skip left every later check-in with nothing to tap.** "First reflection" meant *no rows at
  all* while the remembered pool counts only cue-bearing answers, so a single `skip` — or a first
  `Can't remember`, which §4 calls a first-class answer — moved a habit into the returning branch
  with an empty pool and no pinned cue, permanently, because only a typed answer could seed the pool
  again. `isFirstReflection` now asks the same question the pool does, and the pinned cue leads the
  returning branch too unless the user has already said it back.

And the rest, briefly: an unresolvable cue family no longer switches the habit into Journey A
(`hasDesignedCue` is passed separately from the family — the keyword table is deliberately partial,
so a miss is the expected case); a retry after an unclassifiable save failure reuses the id it
already minted, so the upsert contract does its job instead of writing a second reflection; the
garden's invitation is invalidated when the question is answered, so it stops advertising a check-in
that now lands on "nothing to ask"; an uncategorised habit no longer reports a backfill that
appended the global pool to itself; and `_applyEventFloor` checks the non-event floor its comment
already promised.

The efficiency round: `loadFor` instead of `load` for habits already in hand, the per-habit loads
awaited together rather than in sequence, one fold for both reflection maxima, a built-once
label→family map instead of rebuilding ~300 chips per lookup, the chip ranking hoisted out of
`_select` so the relaxation step does not redo it, and — the largest — the garden's offer handed
through the route so the screen re-verifies **one** habit instead of re-running the whole assembly
seconds after the garden ran it.

One test lands with them: `chip_library_matches_spec_test.dart` parses
`docs/starter-chip-library.md` and asserts the hand-transcribed library agrees with it in both
directions. The parser is strict and the row counts are asserted, so a row it cannot read is a
failure rather than a silent skip.

### Next

Supabase sync, per the build order. The reflection rows this stage writes carry `pending_sync` like
everything else and need no special handling; the enum `CHECK` lists in the backend already cover
every `Framing`, `Occasion`, `InputMode`, `CueType` and `FrictionType` value used here, because none
were added.

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
  **For whoever builds that screen:** `notificationAccessProvider` is a one-shot read, and
  permission can be revoked in system settings while the app is backgrounded — so the screen needs
  to invalidate it on lifecycle resume rather than trust what it read on the way in. Scheduling
  itself is unaffected: every planning pass asks the gateway for access afresh.
- **A stage change takes up to a week to reach the notifications.** Rows inside the horizon are
  decided when they are planned and never re-decided, so a habit that climbs a rung today keeps the
  old rate on occasions already planned. Shortening the horizon trades that against how much of a
  quiet week survives a phone being off.
- **The backfill catches up its own rate.** Occasions nobody was around to nudge are recorded
  un-nudged, which leaves the fade rule in debt and makes it nudge the next several occasions in a
  row. Defensible as re-engagement after the phone was off for a fortnight; it is also not a
  decision anyone made on purpose, and it is the other thing worth instrumenting alongside the fade
  rates themselves.

### Then, before review

Three things landed after the branch was first pushed, in one follow-up.

- **`planHabit` is wired.** `GardenController` re-plans after a watering and after an undo. Awaited
  rather than fired and forgotten — the plant has already reacted by then, so what it delays is the
  undo affordance, not the reward — and it can never fail a watering: a completion that was stored
  is stored, and surfacing a scheduling problem as a failed tap would take back growth the user
  earned. `nudgeSchedulerProvider` now takes its clock and id generator from `clockProvider` and
  `newIdProvider`, so the scheduler runs on the same fake clock as the rest of the garden.
- **The fade counters advance across the planning window, not just its past.** They were seeded from
  rows before *now* and only advanced on occasions already in the past, so every occasion in one
  horizon decided against the same numbers — a pass handed out seven sends or seven silences in a
  row, and the rate was honoured between passes rather than across occasions. They are now seeded
  from rows before the *window* and advanced occasion by occasion through it. **CI caught this and
  local runs did not**: the test asserting that some coming occasions are silent passed in
  Europe/Amsterdam only because a `DateTime.add(Duration(days: 60))` crossed a DST boundary and put
  the fake clock at exactly 20:00 — the check-in slot — which suppressed one occasion for having
  missed its evening. On a UTC runner it was 19:00, nothing was suppressed, and the assertion found
  no silent rows. The test now builds every instant from calendar fields rather than by adding
  durations, and forces the withhold through a seeded ledger instead of an accident of the clock.
- **The cross-feature read contract is on the repository interface.** Reflection's priority scoring
  reads these rows directly (repositories are per-aggregate and shared for reads); notifications
  stays the only writer. Documented there because a raw read can misinterpret all three of: rows
  that exist for occasions a week away, `sent` meaning *queued* rather than *seen*, and `confirmed`
  being an answer to a notification rather than a fact about the habit.

### Then, the background answer

Found while auditing the feature's providers against the paused-provider trap the sync branch hit
(a Riverpod 3 provider nobody listens to is paused, so it never hears the event it was built to
hear). **No provider here has that shape** — the feature holds no subscriptions at all, and the one
live callback belongs to the gateway, which the startup chain keeps listened for the app's
lifetime. But looking for it surfaced a worse bug one layer down.

**Shade answers were being dropped whenever the app was not in the foreground** — which, for a
notification that arrives at 20:00, is nearly always. Both actions are declared
`showsUserInterface: false` so that answering costs nothing, and that is exactly the flag that makes
the platform deliver the response to a *background isolate*. Only `onDidReceiveNotificationResponse`
was registered, so the answer went to an isolate nobody was listening on. Silent: no error, the
ledger simply never recorded a confirm. Confirmed against the plugin's `callback_dispatcher.dart`
rather than inferred from its README.

- `backgroundNudgeResponseHandler` is now registered as the background callback. It is annotated
  `@pragma('vm:entry-point')` — load-bearing, because the compiler strips a function nothing appears
  to call, and the failure would show up only in release builds.
- The isolate has no `ProviderContainer`, so it opens its own database handle, writes through the
  same repository, and closes. **On two isolates writing one store:** SQLite serialises the writes,
  so the row is safe; what is not shared is memory. The main isolate's `GardenController` will not
  see the write until it next reads. That costs nothing today — `confirmed` feeds the insight
  surfaces, which read the store — but it is now written on `NudgeRepository` alongside the other
  misread risks, because anything that starts caching nudge rows has to re-read on resume.
- A body tap opens no database at all. Opening the store to record that a notification was tapped,
  and then doing nothing with it, would be the most expensive no-op in the app.
- **The cold-start path is covered too.** An answer given to a notification that *launches* the app
  reaches neither callback; it is only readable from `getNotificationAppLaunchDetails()`. Startup
  now asks once, before planning, so the pass that follows sees the ledger the user just changed.
- Tested over a real database **file** rather than the in-memory fixture. Every in-memory open
  returns a private store, so a handler writing to one handle and a test reading from another would
  both pass and prove nothing. Two isolates share a file, so the test does too.

### Then, merging develop (habit creation and the backend)

- **A habit is planned the moment it is planted.** `HabitCreationController` re-plans on a successful
  save. Without it the ledger stayed empty until the next cold start, so a habit designed this
  morning got no check-in tonight — the evening when the first one matters most, because it is the
  first rehearsal of the cue the user has just finished writing.
- **Both re-plan hooks resolve the scheduler lazily, inside the guard.** Reading it in `build()`
  made every construction of the garden *and* the creation flow depend on the notification stack
  being buildable — which took twenty habit-creation tests down the moment the hook landed, and on a
  device would have meant a notification problem breaking the completion tap. That is the one thing
  that must never happen, so the promise is now structural rather than a comment.
- **A cue-less habit is a *tracked* habit.** The merge's `journey` assert caught the notification
  copy building a Habit that could not exist: no designed cue means Journey A (design-spec §2). The
  plain form — "Tomorrow, then — Morning run?" — is right for that user precisely because he
  declined to design a loop, and the test now says so instead of reading as an oversight.
- The planner assembles `HabitInputs` from all four repositories, so any test that reaches it needs
  all four as fakes. Worth knowing before it presents as an empty ledger: the guard that stops a
  scheduling failure from failing a save also swallows a half-wired test harness.

### Then, the review of PR #7

Nine inline findings, all fixed. The three worth recording beyond "fixed":

- **The cap was consumed by history** (the serious one). `planAll` recounted each habit's decisions
  afterwards — but the known-row branch reports `send` for every *historical* sent row, so a few
  weeks of ledger exhausted the 60-notification ceiling on its own and every real future nudge was
  suppressed as `overCap` and written to the ledger as un-nudged. Silent, and it corrupts the
  measurement rather than just losing a reminder. There is now one counter, incremented only when
  the OS actually took a notification, returned out of the per-habit pass instead of recounted.
  **The regression test needed three habits to reproduce it** — the miscount compounds across
  habits rather than within one, so the running total only passed the ceiling by the third — and
  writing it surfaced a second bug in the test seeding itself: a shared row id meant each habit's
  seeded history *updated* the previous habit's row and moved it across, so every caller but the
  last silently had no history at all. Both versions of the accounting were run against the test to
  confirm it fails on the old one; the first two attempts passed under both and were not regression
  tests at all.
- **`planAll` and `planHabit` had diverged** in how they seeded the cap. One `_plan` now serves
  both, so the accounting cannot fork again and the next pass-wide step cannot land on one path
  only.
- **Two latency findings, same shape.** The first frame was blocking on a full re-plan, and the
  permission screen was waiting on one after the dialog had already closed. Both now run unawaited
  with their own failure logging. The launch pass stays inside the startup chain so it still sees a
  cold-start answer already recorded. One consequence written down where it happens: a startup retry
  closes the database handle and can land mid-pass, which surfaces as a logged failure and costs
  nothing, because the ledger is rebuilt from the calendar on every pass.

Also from the review: one access snapshot per pass rather than two platform round trips per
notification (which had a split-snapshot hazard — the scheduler deciding `canPost` from one reading
while the gateway scheduled against another); `requestAccess` now prompts and then re-reads rather
than keeping a second copy of the mapping that had already drifted on iOS provisional grants; one
`NudgeResponse.from` shared by the foreground callback, the background isolate and the cold-start
path; `saveNudges` batching the silent majority into one transaction, with the write-then-queue
ordering kept only for rows actually headed to the OS; a `loadFor(Habit)` entry point so the planner
stops re-fetching habits it is already holding; and a write-only `isNew` field deleted.

### Next

Supabase sync — a pusher over the `pending_sync` column, which the `nudges` table already carries
along with the other three.
## 2026-09-15 — backend review and fixes

Branch: `feature/supabase-backend`, on top of the entry below. PR [#4](https://github.com/LWitteman96/taproot/pull/4).

### Corrected

**The entry below says "same seven tables". The device has six.** `habits`, `completions`,
`completion_retractions`, `reflections`, `nudges` and `habit_pauses` exist on both sides; the
server's seventh, `profiles`, has no device counterpart at all. It is created by the
`handle_new_user` trigger, keyed by the auth user id, and is **not drained through `pending_sync`**.
Recorded here rather than by editing that line, per this file's append-only rule — and recorded at
all because the sync branch is the reader it would have misled: table-symmetric drain-and-pull code
written from "same seven tables, same keys" would try to sync a table the device does not have.

### Found

Ten things from the review. Two are latent correctness bugs, four are guarantees that were weaker
than the prose around them claimed, and the rest are cost and accuracy.

| Finding | Why it matters |
|---|---|
| The documented enum-widening process is a no-op on a deployed database | The CHECK lists live inside `create table if not exists`, and `db push` only applies *new* migrations. Editing the file goes green on every gate — `db reset` and CI both rebuild from scratch — and drifts only in the one environment nobody can reset |
| `pin_soft_delete` coalesced `deleted_at` and reported success | A stale whole-row push half-applied (200, `deleted_at` kept, `name` and `updated_at` overwritten); a sanctioned undelete was a silent no-op with nothing to debug from, since triggers are not bypassed by `service_role` the way RLS is |
| `default 'tap'` and `default 'unknown'` invented client-owned values | Contradicted the migration's own header rule. A serializer bug dropping `source` would have filed a `nudgeConfirmation` as a tap and miscounted autonomy on every device that later pulled it |
| `delete-account`'s 503 branch was dead | auth-js does not throw on a transient failure — it returns `AuthRetryableFetchError` in the result — so an auth-server blip answered 401 "Invalid session" on the one screen App Store review checks |
| The "moves it on update" pgTAP assertion was vacuous | It passes against a `before insert`-only trigger, so a pull cursor frozen at insert time would have shipped certified by the suite |
| `json_field`'s `JSONDecodeError` outran its own diagnostics | Under `set -e` a non-JSON body killed the script before the `error "Response was:"` lines written for exactly that case, and `python3` was the one dependency never preflighted |
| CLAUDE.md keyed the enum rule to `engine/domain.dart` only | `CompletionSource` lives in `models/completion.dart`, so a fourth source value got no prompt to widen its CHECK |
| "same seven tables" | Corrected above |
| CI applied every migration twice and booted Studio + inbucket | `supabase start` already applies them; the script's reset then did it again. Nothing opens either container — the test user is created pre-confirmed through the admin API |
| Two indexes with no possible reader | `idx_profiles_synced_at` (every `profiles` statement is an RLS-scoped PK lookup) and `idx_completions_habit_completed_at` (duplicates the PK's leading column on the hottest write path) |

### Fixed

All ten. pgTAP went from 30 assertions to 35, and `scripts/supabase-verify.sh` gained a fourth
end-to-end check. Both `supabase-verify.sh` and `supabase-verify.sh --no-reset` are green locally,
as is `flutter test`.

Three of the fixes are worth knowing about before touching this code:

- **`pin_soft_delete` raises `PT409` rather than coalescing.** Clearing a set `deleted_at` is now a
  visible failure, so the whole statement rolls back instead of half-applying, and the push comes
  back 409 Conflict (`PT`-prefixed SQLSTATEs are how PostgREST is told the status). The benign race
  is deliberately untouched: a second device deleting an already-deleted habit still succeeds, and
  the first stamp still wins. **The sync branch should read a 409 on a habit push as "deleted
  upstream — pull, do not retry."** An undelete, if it is ever wanted, needs a sanctioned RPC that
  the trigger exempts — not a whole-row push that happens to carry a null.
- **The enum drift gate is a Dart test**, `test/unit/backend/enum_checks_test.dart`. It reads every
  migration in order, takes the *last* definition of each named CHECK — so a widening
  `ALTER TABLE ... DROP CONSTRAINT / ADD CONSTRAINT` counts, exactly as it does in Postgres — and
  compares against the Dart enums. It lives in the Flutter suite on purpose: the Supabase workflow
  is path-filtered to `supabase/**` and never runs on the commit that adds an enum value. Verified
  both ways before landing — it fails on a Dart-only widening, and passes once the migration exists.
- **Dropping the two server defaults moved four test fixtures.** `NOT NULL` is checked before
  `CHECK`, so inserts that omitted `source` or `cue_type` started failing 23502 *before* reaching
  the 23505 and 23514 they were written to assert. Worth remembering when adding a fixture: the
  column list has to be complete now.

### Left open

- **No remote project is provisioned**, unchanged. Nothing here has been deployed, which is what
  made editing the migration in place the right fix for the indexes and the defaults rather than a
  follow-up migration.
- **The 503 branch still has no test.** The 401 half now does — the verify script re-POSTs the
  token whose user it just deleted, which is the only way to reach the function's own `getUser`
  rejection from outside, since `verify_jwt = true` means the gateway turns away anything
  malformed. Reaching the 503 half needs the auth server to fail mid-request, which nothing local
  can stage; it rests on the auth-js reading in the comment rather than on a green light.
- **`nudges` still has no unique constraint on `(habit_id, expected_occasion_at)`**, unchanged, and
  still the sync branch's question rather than this one's.

---

## 2026-09-09 — the Supabase backend

Branch: `feature/supabase-backend`. Backend only — nothing under `lib/` changed.

### Landed

```
supabase/config.toml                        local + remote configuration
supabase/migrations/  20260909090000_initial_schema
                      20260909090100_rls
                      20260909090200_new_user_trigger
supabase/functions/   _shared/cors · delete-account
supabase/tests/       schema.test · rls.test        (pgTAP, 27 assertions)
supabase/seed.sql                           deliberately empty
scripts/supabase-verify.sh                  the backend's gate
.github/workflows/supabase.yml              runs it, path-filtered on supabase/**
supabase/README.md                          how to run and verify it
```

The schema is the device's SQLite schema (`lib/app/database/app_database.dart`) plus `user_id` and
`synced_at` — same seven tables, same keys, same append-only ledgers, same absence of any stored
engine value. `scripts/supabase-verify.sh` resets from the migrations, **re-applies every migration a
second time**, runs pgTAP, and deletes an account through the edge function. All four steps are green
locally and the same script is what CI runs.

`delete-account` was written now rather than at submission time, and verified end to end against the
local stack: sign up → plant a habit → POST with the session token → 200, and the auth user, its
profile and its habits are gone. Guideline 5.1.1(v) is the most common cause of a first-review
rejection and it is not a thing to discover late.

### Decided

- **No `DELETE` is granted to any client role, on any table.** Deleting a habit is `deleted_at`,
  undoing a completion is a row in `completion_retractions`, and erasing an account is the edge
  function running as `service_role`. Without this a device that has not yet heard about a row could
  delete it and a second device could re-push it — sync stops being a union the moment rows can go
  backwards. `completions` and `completion_retractions` have no `UPDATE` grant either: they are event
  ledgers, and an edit to a past event is a different event.
- **Child rows carry a composite `(habit_id, user_id)` foreign key** into
  `habits (id, user_id)`, which is why `habits` has a redundant unique constraint on that pair. It
  makes "this completion belongs to the same user as its habit" a foreign key rather than something
  the RLS check has to be trusted to have got right. A test inserts a completion Ana owns onto a
  habit Ben owns: RLS passes, the foreign key catches it.
- **`synced_at` is a new column with no counterpart on the device** — the pull cursor, stamped by a
  trigger off the *server's* clock. `updated_at` comes off the client's and is what the app compares.
  Conflating them means a device with a skewed clock can write a row a later incremental pull never
  sees. This is the one piece of schema here that the sync branch needs and the guide's schema sketch
  does not have.
- **Text enum columns carry the Dart `Enum.name` verbatim** — camelCase (`nudgeConfirmation`,
  `autonomyCompletion`, `cantRemember`), because `encodeEnum` is `value.name`. `CHECK` lists spell
  them out so a value the app could not decode fails at insert rather than sitting in the table.
- **`DROP POLICY IF EXISTS` rather than the guide's `DO $$ ... EXECUTE 'DROP POLICY' ... $$`.** Same
  idempotency guarantee, a third of the lines; the block form predates `DROP POLICY IF EXISTS`.
- **Realtime and storage are off.** Realtime would be a second, unordered path into rows that sync
  drains one way; storage has nothing to hold, since plant art ships in the bundle. The storage purge
  step stays in `delete-account` as a comment, in the position it belongs in, for the day a bucket
  exists.
- **Email confirmations are on**, which the magic-link flow does not itself need. Enabling email
  sign-up enables the password grant with it and there is no switch separating the two, so with
  confirmations off anyone could sign up as someone else's address, get a session immediately, and
  keep a working password on the row that address's real owner later signs into with a magic link.
  One extra round trip is not worth a stranger's foothold in someone's habits. The auth branch can
  revisit it if it removes the password grant.
- **`habits.deleted_at` is pinned one-way by a trigger** (`pin_soft_delete`). Revoking `DELETE` is
  only half of "a device that never heard about a deletion cannot undo it" — the other half is that
  a stale whole-row push must not be able to set `deleted_at` back to null. First deletion wins, so
  a second device cannot move the stamp either. `graduated_at` is deliberately *not* pinned:
  graduation derives from autonomy, which can fall, and whether it is one-way is the engine's
  question.
- **Taproot runs on the 5433x port block, not the CLI defaults.** inkBlox holds 5432x, and "stop your
  other project" is exactly the thing the bare+worktree layout exists to avoid. `.env.dev` now points
  at `http://127.0.0.1:54331`.

### Left open

- **No remote project is provisioned.** The refs at the top of `scripts/supabase-push.sh` are still
  empty and the script fails loudly on them. `.env.stg` and `.env.prod` are placeholders.
- **Apple and Google sign-in are wired and disabled**, because the credentials do not exist. The
  `env()` names are in `config.toml` and the empty keys are in `.secrets/.env.*`; enabling a provider
  is one commit that flips `enabled` and fills its pair. The deep-link scheme
  `io.supabase.taproot://login-callback/` is *declared* but not registered in `Info.plist` or
  `AndroidManifest.xml` — the native half is untested.
- **No SMTP provider is chosen**, so `[auth.email.smtp]` is commented out. Local mail goes to the
  catcher on port 54334; staging and production would send nothing.
- **`nudges` has no unique constraint on `(habit_id, expected_occasion_at)`**, matching the device.
  Two devices can therefore each create a row for the same expected occasion and double-count
  autonomy's denominator. Adding the constraint here would turn that into a failed sync push rather
  than something the sync branch can reconcile, so it is a question for that branch, not this one.
- **`delete-account` does not revoke the Apple grant.** Apple's `/auth/revoke` needs a token issued
  for that user at sign-in, and nothing captures one yet. The function logs that it skipped rather
  than pretending; the step keeps its slot, and it stays best-effort — nothing it does may block the
  deletion.
- **The pull cursor has a commit-time gap, and the sync branch has to close it.** `synced_at` is
  stamped when a row is written; the row becomes visible when its transaction commits, which is
  later. A pull that reads at T and stores `cursor = T` can miss a row stamped before T that commits
  after it — permanently. `clock_timestamp()` narrows the window to the write itself rather than the
  transaction's start, but does not close it. The two real fixes are an overlap window
  (`synced_at > cursor - slack`, safe because every upsert here is idempotent) or an `xid8` cursor.
  The warning is written out at the top of the schema migration, where the branch that builds the
  pull will read it.
- **PostgREST's `max_rows = 1000` truncates silently.** A first-install pull of a year of
  completions gets exactly one page and no signal that there is more, so the pull must page rather
  than treat one response as the whole answer. Noted in `config.toml` next to the setting.
- **Whether a habit should be hard-deletable** at all. Soft delete is what protects the union, but a
  user asking to erase one habit's history currently keeps its rows. If that changes it is an RPC, or
  a second edge function — not a `DELETE` grant.

### Reviewed

A review pass over the branch found eight things; six were fixed here and two became the "left open"
notes above. The six: `profiles` carried a `synced_at` column with no trigger to move it (a cursor
frozen at its default, which is worse than no cursor — there is now a test asserting *every* table
with the column has the trigger); email confirmations; the `deleted_at` pin; `delete-account` had no
`try`/`catch`, so the "best-effort" contract on the Apple revoke was a comment rather than a
guarantee and an exception would have escaped as a CORS failure on the one screen App Store review
checks; `now()` → `clock_timestamp()`; and the CI job had no `permissions:` block. The pgTAP suite
went from 27 assertions to 30.

### Next

Sync, and it is the completion tap's branch that unblocks it, not this one. What that branch needs
from here: a three-line `supabaseClientProvider`, remote services behind the existing repository
interfaces, and a `SyncService` that drains `pending_sync` on a false → true connectivity edge —
treating a `null` previous value as "was offline", so the first `true` emission is not swallowed.
`main()` also still has no `Supabase.initialize`; the `.env.dev` credentials now exist for it.

---
## 2026-09-15 — habit creation

Branch: `feature/habit-creation`, on top of the completion tap.

### Landed

The placeholder shell is gone. Creation is a six-step flow over the repositories that already
existed — no new store code, one schema migration:

```
lib/core/models/      habit_journey · habit_category   (+ two fields on habit)
lib/features/habits/  controllers/habit_creation_controller
                      domain/plant_choices · cue_suggestions
                      pages/habit_creation_page
                      widgets/creation_step · draft_text_field
                              name_step · plant_step · rhythm_step
                              cue_step · loop_step · review_step
```

name → plant → rhythm → cue → loop → review, with the cue and loop steps dropped for a tracked
habit. The entry gate is no longer stubbed: it reads the habit count, so a user with nothing planted
is sent to plant something, and the garden gained a way to plant another.

`plantDemoHabit` went with it. Its own doc named habit creation as the trigger for deleting it, and
with the gate live the empty garden it sat on is only transiently reachable — a dev-only button that
almost nobody can now reach, standing next to a real one that does the same job properly.

36 new tests on balance — the controller over a `ProviderContainer`, the flow driven end to end
through the real app so that planting a habit is shown to land back on the garden, and the migration
exercised against a hand-built version-1 database; less the five that went with the demo seed. The
suite reports 505 passing, all three gates green.

### Decided

**There is no journey picker at the front door.** design-spec §2 is explicit that an app offering
designing and tracking as equal-weight choices on the first screen "is a tracker with a designer
bolted on", and that the opt-out must not be the path of least resistance. So the flow simply *is*
the design flow, and *"I already do this — just track it"* is a text button on the cue step — the
first step that asks for something a tracker would not, and the first place the user has seen what
they would be opting out of. It stays reversible on the review step.

**The journey is recorded, not inferred** — the open question §2 raises for this work. The inference
("was a designed cue present at creation") is wrong the moment it matters: a Journey A habit that
discovers a reliable cue and locks it in is exactly the graduation the spec wants to see, and by
then its columns are indistinguishable from a designed habit's. Recording it costs one column.
The inference survives once, as the version-2 backfill, which is the only place it is still the best
available evidence.

**`Habit.category` was added in the same migration**, which is a small scope call worth naming. The
starter chip library filters the first reflection's chips by habit category (§0, §5.2), creation is
the only moment that can state one, and the alternative was a second migration and a second pass
over the same six screens later. It is nullable — the library backfills from its global pools (§6.1)
— so a habit that fits none of the twelve is not forced into one.

### The two new columns, precisely

Written out in full because the server side of these does not exist yet: the Supabase schema in
PR [#4](https://github.com/LWitteman96/taproot/pull/4) predates both columns, so a sync push of a
habits row would fail against the server table until a migration adds them. That migration belongs
to the sync branch; this is its specification.

| Column | Local (SQLite) | Nullable | Allowed values |
|---|---|---|---|
| `journey` | `TEXT NOT NULL CHECK (journey IN ('design', 'track'))` | no | `design`, `track` |
| `category` | `TEXT` | **yes** | the twelve below, or NULL |

`category` carries **no** `CHECK` locally and should not gain one server-side without the same list
on both, because the value set widens as the chip library does — it is the twelve authored
categories in starter-chip-library.md §7 and nothing else:

```
exercise · meditation · reading · journaling · hydration · tidying
languagePractice · instrument · stretching · supplements · walking · sleepRoutine
```

**An unknown `category` reads as null on device, and does not fail the row.** `Habit.fromJson` uses
`readOpenEnum` for this column: a value outside the twelve decodes to null rather than throwing, so
a habit synced down from a build that knows a category this one does not still opens. The
alternative was disproportionate — a `FormatException` here fails `allHabits()`, which puts the
entire garden into its unreadable state over one optional field whose spec says null is a supported
answer. **Sync reconciliation should assume the device may hand back null for a category the server
still holds**, and must not treat that as the user clearing it. `journey` is strict and stays
strict: closed set, CHECKed on both sides, and an unknown value there really does mean the row
cannot be trusted.

**Two of those are camelCase, and that is load-bearing.** `languagePractice` and `sleepRoutine` are
`Enum.name` values written verbatim by `encodeEnum`, so a server column that snake_cases them by
convention will not round-trip — `readEnum` throws a `FormatException` naming the column rather than
silently defaulting, which is the behaviour that makes the mismatch findable, not a reason to relax
it.

On upgrade rather than create, `journey` arrives nullable and is backfilled; `ALTER TABLE ... ADD
COLUMN ... NOT NULL` needs a default, and a default here would be the silent guess the column exists
to stop making.

**Journey B requires all three of cue, routine and reward.** §2 defines the journey as writing the
loop down; a design flow that lets two thirds of it go blank is the bolted-on tracker again. The way
out is the opt-out, not a half-filled loop.

**The gate waits on startup.** `habitServiceProvider` reads the database synchronously and throws
until the store is open, so a gate resolved before then would report "no habits" on every cold start
and send a user with a full garden into habit creation. `appGateResolverProvider` watches the
startup future and awaits it inside the closure — watching so that a retried startup asks the gate
again instead of serving the fail-safe it cached.

### Left open

- **The default weekly target is 3**, and it is a calibration question rather than a settled number:
  `f` anchors every window in the engine, and an over-ambitious default is the front door to the
  mismatched-target death spiral renegotiation exists to rescue (growth-engine §7). It lives in
  `habit_creation_controller.dart`, deliberately *not* in `EngineConstants` — nothing in the engine
  reads it, and bumping the constants version to change a form default would invalidate every cached
  derivation for nothing.
- **The plant catalogue is six placeholder ids.** design-spec §4 sends the art to a paid external
  illustrator and says to treat the visuals as a slot until it lands, so `plant_choices.dart` is
  plausible names and the words around them, and `Habit.plantType` stays a free string.
- **The cue step offers examples, not ranked chips.** The starter chip library's surfacing rule (§5)
  needs a completion and a time of day to rank against, and there is neither at creation. The
  examples come straight from the taxonomy table in reflection-logic §4.
- Editing a habit after creation does not exist. `saveHabit` is an upsert, so the store is ready for
  it; the screen is not.

### Next

Supabase sync, per the build order — a pusher over the `pending_sync` column every table carries.
Notifications and the nudge ledger are the stage after, and are unblocked now that habits have real
cue types and target frequencies to schedule against.

---

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
