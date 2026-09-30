# Taproot — status

*Where the project stands right now. One table, kept current.*

This is the **mutable** half of the project record. [progress-log.md](progress-log.md) is the
append-only half — what was built, in order, and what each piece decided. They are separate files on
purpose: every branch flips a row here *and* inserts an entry there, and when both lived in one file
those two edits collided on every single merge.

Update this file in the same commit as the work it describes.

---

## Where the project stands

| Area | State |
|---|---|
| Flavors (dev / stg / prod) | Built — entry points, resolver, native config |
| CI, lint, pre-commit hook | Built |
| **Growth engine** (`lib/core/engine/`) | **Built and reviewed — stage, vitality, roots, autonomy, adherence, renegotiation** |
| **Local SQLite store + repositories** | **Built — schema, four repositories, engine inputs loader** |
| **App skeleton** (`lib/app/`) | **Built — startup, logging, theme, router** |
| **Completion tap** (`lib/features/garden/`) | **Built — garden controller, press-and-hold watering, undo** |
| **Habit creation** (`lib/features/habits/`) | **Built — the design flow, the tracking opt-out, plant choice, and a live entry gate** |
| **Supabase backend** (`supabase/`) | **Built — config, schema, RLS, new-user trigger, delete-account; local only, no remote project** |
| **Supabase sync** (`lib/app/sync/`) | **Built — connectivity trigger, paged pull with an overlap cursor, push, last-write-wins** |
| **Notification scheduling + nudge ledger** | **Built — occasion calendar, nudge fading, scheduling, notification actions** |
| **Notification permission** | **Built and reviewed — the invitation after the first habit, denial as a mode, resume-aware, restore-aware** |
| **Reflection check-in and chips** (`lib/features/reflection/`) | **Built — priority scoring, the five framings, the authored chip library and its surfacing rule, the question on the evening notification, and the check-in itself as a sheet over the garden with the roots payoff** |
| **Garden home screen** (`lib/features/garden/`) | **Built — one garden scene: sky, ground, scrolling plants, selection, detail card, and generated art for four of the six species. The watering choreography and time-of-day are not wired yet** |
| Insight surfacing | Not started |

Build order from the infrastructure guide (§16): engine → local store and repositories → completion
tap → Supabase sync → notifications and the nudge ledger → reflection check-in → garden → insights.
The first four are done, and four stages have landed on top of them: habit creation — a prerequisite
the build order does not name, since every stage after it needs habits a user actually made — plus
notifications, the reflection check-in and Supabase sync. That completes the build order up to its
last two entries, so what remains is **insight surfacing**, which now has reflection data to
surface. Garden rendering is no longer blocked on the external illustrator and is largely built —
see below. The notification-permission invitation has landed, which leaves the check-in composer
seam below as the one follow-up.

One thing the check-in **says** is narrower than the data behind it. An un-nudged occasion is
autonomy's whole measurement, but `sent: false` is written for four different reasons — the fade
rule choosing silence, an evening already past when the backfill ran, no notification permission,
and the pending-notification cap — and the ledger does not keep which. So the autonomy framing, the
one that tells the user *"you did this without us asking"*, is gated on separate evidence that the
app was actually nudging that habit at the time. The engine's autonomy denominator still counts all
four, as it has since it was written. A `suppression_reason` column on `nudges` closes both at once
and is the next thing to do to that table.

The check-in is reachable from the garden **and from the evening notification**. The two halves of
that message — *how did today go*, *and tomorrow, then?* — are composed by the same functions the
screen uses, so the app cannot ask one user the same question in two voices. The question is written
when the notification is queued, which can be up to seven days early, so two rules hold it honest:
detection never runs later than *now*, however far out the delivery is, and a queued notification is
re-composed once it is within a day of firing. A third rule makes the one-question-an-evening
promise survive a pass that sees only one habit: a single-habit re-plan seeds itself from the
evenings the other habits' pending notifications already speak for, so watering one plant in the
afternoon cannot put a second question into an evening another plant has taken.

What is deliberately *not* built yet: Sentry is still uninitialised, no remote Supabase project is
provisioned — `.env.dev` points at the local stack and stg and prod are placeholders, so those two
flavors start without a backend and say so as `SyncStatus.unavailable` — nothing signs a user in, so
sync has nobody to sync for, and two of the six species still render as words rather than art.

**The garden is drawn.** The home screen is no longer a list of cards: it is one vertical
cross-section — sky, a ground line, soil — with every habit standing on the same ground at one world
scale, a floating detail card, and a horizontal scroll. `docs/garden-design.md` governs it, and
build steps 1–3 of its §10 have landed.

**The plant art is no longer blocked on the external illustrator.** Each of `fern/`, `oak/`,
`sunflower/` and `lavender/` is a Rive CLI project that *generates* its species from Python — six
stage artboards plus a roots artboard, a looping sway, and a droop, colour fade and root-depth lean
bound to the `vitality` and `roots` numbers the engine already computes. All four `.riv` files ship
in `assets/rive/`, all four are named in `plantArts`, and the garden draws them.

The roots are wired too: the roots artboard stacks under the stage artboard sharing **one**
`ViewModelInstance`, which is what keeps a plant from leaning as though it were shallow while the
roots drawn beneath it are deep. The check-in sheet pins the depth on the way in and releases it at
the done state, so the growth lands with the payoff rather than before it.

What is **not** wired yet, from garden-design §10: **the watering choreography** (step 5 — the drop,
the damp patch, the ripple, the landing-time vitality write), **time of day** (step 6 — the modes
cross-fade but nothing re-checks the hour, and there is no plant-light filter), and the **art pass**
(step 7 — outline widths and root recolour for the 0.15 scale, now due once in `plantgen/` for all
four plants rather than per species).

**Four of six species now have generated art.** The generator's shared half lives in `plantgen/` —
the geometry model, both writers, the sway / droop / lean / roots wiring, and the checks every plant
runs — and each species directory is just a palette, a set of parts, and a table of tuning. Every
plant's output stayed byte-identical across each move into the shared half. The **lotus** and the
**pine** have no art and still draw as placeholder silhouettes; adding one is `plantArts` plus the
asset, and nothing else in the app changes.

So the first of the two open questions has an answer: **the generator approach does work for a
tree.** The oak built, verified and rendered correctly on the first attempt with the rive CLI, and
its Rive output matches the reviewed SVG art to antialiasing alone. It needed four additions to the
shared half — pivots, nested parts, motion twins, and per-part droop directions — all inert for the
fern. Two caveats: an oak is **3× the fern's render cost**, which puts `OakMature` and `OakBloom`
over the per-artboard budget `oak/NOTES.md` set, and the `.riv` is 544 KB against the fern's 171 KB.
Neither has been addressed, because every way to slim it changes art that has been reviewed.

The second question — **whether six generated species can look like one garden** — stays open, but
narrows: **four of the six species now have art and draw**, and only the lotus and the pine still
render as placeholder silhouettes.

**The sunflower and the lavender are built and shipped.** `assets/rive/` carries all four `.riv`
files, `plantArts` names all four, and the garden draws them. Both were built on the first attempt
with nothing fixed along the way, and both matched their handoff's type-count table exactly — 91
counts each. Against the SVG art each build came from, every stage and every root level shows **zero
strongly-differing pixels**. The per-plant detail is in `sunflower/NOTES.md` and `lavender/NOTES.md`,
"Step 2 — built".

Three results worth carrying forward:

- **The render budget is not about shape count.** `oak/NOTES.md` concluded that render cost follows
  shapes and paths, and the lavender's handoff predicted from that its 60-shape `LavenderBloom`
  would fail the bench as `OakMature`'s 62 did. It does not. Benched in one session,
  `LavenderMature` renders in 0.181 ms against `OakMature`'s 0.309 ms at near-identical shape
  counts, because the oak's shapes are many-vertex paths and the lavender's are ellipses. Cost
  follows **path complexity**. What 597 ellipses do cost is *advance* — 0.066 ms, the highest of the
  four plants, and still two-thirds of budget.
- **Only the oak is over budget.** The sunflower and the lavender pass everywhere, with the worst
  render at 60 % of budget. `OakMature` and `OakBloom` remain over, unchanged and still Luuk's call.
- **A `Dots` shape can fade.** No plant had keyed a `Dots` colour before. On `LavenderBloom` the
  healthy floret colours go to exactly zero pixels between vitality 1 and 0 and the dry ones arrive
  at almost identical counts, which is the colour changing rather than the spikes moving.

`plantgen/species.py`'s per-part stated droop, added for the lavender, stayed inert for the other
three: all four plants regenerate byte-identically.

**Four shared checks now live in `plantgen/`** rather than being re-derived per plant:
`check_rml.py`, `check_built.py` and `check_render.py` (the oak's, made generic over the species and
proven by reproducing all 21 of its recorded results to the pixel), plus `check_svg_render.py` and
`measure.py`, which the oak's run did by hand. `crop_joints.py` makes the joint crops and is
deliberately *not* a pass/fail check — two automated formulations were tried and both are wrong, and
its docstring records why so the next run does not walk into them.

**The evening check-in is a sheet over the garden.** `docs/check-in-design.md` governs it, and all six
build steps of its §10 have landed: the copy functions the notification shares, the sheet and its
camera move, the look-back step, the commit step, the done state with the roots payoff, and the
engine's `confirmationChangedCueCredit`. Priority scoring, framing selection and chip surfacing are
unchanged — this was presentation, not policy.

**Later features, named rather than half-built:**

- **The day picker.** `Different day` records `declined` and nothing else. The prototype opens a
  `Which day?` picker over the next four scheduled days; it needs a one-off reschedule of the next
  occasion in `lib/features/notifications/` and a ledger field for the chosen day
  (check-in-design §4.3). Whether `declined` alone feels like being heard is an open question — if
  not, this moves up.
- **Insight surfacing.** Exactly one insight fires today: the autonomy milestone, on a habit's first
  un-nudged completion. Cue lock-in, cue unreliability, conditional failure, friction concentration,
  the awareness gap and nudge dependence are all specified in reflection-logic §6 and none are
  built, because §0.4 forbids an insight without an action and the actions do not exist.
- **The action editors.** Cue, slot, routine and reward editors are the actions those insights would
  offer. None are designed. check-in-design §7.3 records the friction-route copy and button labels
  the prototype supplies, so the wording is ready when the editors are.

The router's gate is no longer stubbed — it reads the habit count, so a user with nothing planted is
sent to plant something and only then gets a garden. The debug-only dev-flavor seed button that used
to stand on the empty garden has been **removed**: the real flow supersedes it, and with the gate
live the screen it sat on is only transiently reachable.

The notification permission prompt is now placed: it is offered once, on the beat after the first
habit is planted, and never again. Occasions are still recorded when it is declined, so the engine
keeps its inputs either way — but only for days that have already passed, so a later change of mind
in system settings finds the coming week still open.

What the **backend** does not include, deliberately: any Dart that talks to it. There is no
`supabaseClientProvider`, no remote service behind the repository interfaces and no sync — that is
the Supabase-sync branch. Nor is a hosted project provisioned: `.env.dev` points at the local stack,
`.env.stg` and `.env.prod` are placeholders, and the project refs in `scripts/supabase-push.sh` are
still empty. Apple and Google sign-in are wired in `config.toml` and disabled, because the
credentials do not exist yet.

---

## The three gates

`flutter analyze` · `dart format --output=none --set-exit-if-changed .` · `flutter test`

All three are green, and stay green in every commit. The backend has a fourth, run only when
`supabase/` changes: `scripts/supabase-verify.sh` — migrations apply from scratch, re-apply cleanly,
the pgTAP suite passes, and an account can delete itself. The infrastructure guide (§17) notes that
inkBlox let `flutter analyze` lapse in CI and it was far harder to restore than to maintain.
