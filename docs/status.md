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
| **Notification scheduling + nudge ledger** | **Built — occasion calendar, nudge fading, scheduling, notification actions** |
| **Reflection check-in and chips** (`lib/features/reflection/`) | **Built — priority scoring, the five framings, the authored chip library and its surfacing rule** |
| Garden rendering | Not started (blocked on external illustrator) |
| Insight surfacing | Not started |

Build order from the infrastructure guide (§16): engine → local store and repositories → completion
tap → Supabase sync → notifications and the nudge ledger → reflection check-in → garden → insights.
The first four are done, and three stages have landed on top of them: habit creation — a
prerequisite the build order does not name, since every stage after it needs habits a user actually
made — and notifications and the reflection check-in, both taken ahead of Supabase sync because none
of the three share code. So **Supabase sync is next**: a pusher over the `pending_sync` column the
schema already carries. The backend now exists ahead of that order, but only as a schema: nothing in
`lib/` talks to it yet.

One thing the check-in **says** is narrower than the data behind it. An un-nudged occasion is
autonomy's whole measurement, but `sent: false` is written for four different reasons — the fade
rule choosing silence, an evening already past when the backfill ran, no notification permission,
and the pending-notification cap — and the ledger does not keep which. So the autonomy framing, the
one that tells the user *"you did this without us asking"*, is gated on separate evidence that the
app was actually nudging that habit at the time. The engine's autonomy denominator still counts all
four, as it has since it was written. A `suppression_reason` column on `nudges` closes both at once
and is the next thing to do to that table.

The check-in is reachable from the garden but **not yet from the evening notification**. Scheduling
composes its question through `ReflectionPromptComposer`, and the stand-in `NoReflectionPrompt` is
still the one installed — so the notification fires without a question attached. That seam is a
follow-up, deliberately kept out of the reflection branch.

What is deliberately *not* built yet: Supabase and Sentry are still uninitialised (the `.env` files
hold no credentials, and `Supabase.initialize` on an empty URL throws at launch), and the garden
renders its plants as words rather than art, which is waiting on the external illustrator.

The router's gate is no longer stubbed — it reads the habit count, so a user with nothing planted is
sent to plant something and only then gets a garden. The debug-only dev-flavor seed button that used
to stand on the empty garden has been **removed**: the real flow supersedes it, and with the gate
live the screen it sat on is only transiently reachable.

The notification permission prompt is wired but not *placed* — nothing calls
`requestNotificationAccess` yet, because onboarding is where it belongs and onboarding does not
exist, so a real device runs in the denied mode until it does. Occasions are still recorded in that
mode, so the engine keeps its inputs either way.

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
