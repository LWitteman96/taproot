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
| **Reflection check-in and chips** (`lib/features/reflection/`) | **Built — priority scoring, the five framings, the authored chip library and its surfacing rule** |
| Garden rendering | Not started (blocked on external illustrator) |
| Insight surfacing | Not started |

Build order from the infrastructure guide (§16): engine → local store and repositories → completion
tap → Supabase sync → notifications and the nudge ledger → reflection check-in → garden → insights.
The first four are done, and four stages have landed on top of them: habit creation — a prerequisite
the build order does not name, since every stage after it needs habits a user actually made — plus
notifications, the reflection check-in and Supabase sync. That completes the build order up to its
last two entries, so what remains is **garden rendering**, which is blocked on the external
illustrator, and **insight surfacing**, which now has reflection data to surface. One follow-up sits
alongside them: the check-in composer seam below.

What is deliberately *not* built yet: Sentry is still uninitialised, no remote Supabase project is
provisioned — `.env.dev` points at the local stack and stg and prod are placeholders, so those two
flavors start without a backend and say so as `SyncStatus.unavailable` — nothing signs a user in, so
sync has nobody to sync for, and the garden renders its plants as words rather than art, which is
waiting on the external illustrator.

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
