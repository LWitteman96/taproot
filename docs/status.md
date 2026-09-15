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
| Supabase project, migrations, RLS | Not started |
| Notification scheduling + nudge ledger | Not started |
| Reflection check-in and chips | Not started |
| Garden rendering | Not started (blocked on external illustrator) |
| Insight surfacing | Not started |

Build order from the infrastructure guide (§16): engine → local store and repositories → completion
tap → Supabase sync → notifications and the nudge ledger → reflection check-in → garden → insights.
The first four are done, and habit creation — a prerequisite the build order does not name, since
every stage after it needs habits that a user actually made — has landed on top of them. So
**Supabase sync is next**: a pusher over the `pending_sync` column the schema already carries.

What is deliberately *not* built yet: Supabase and Sentry are still uninitialised (the `.env` files
hold no credentials, and `Supabase.initialize` on an empty URL throws at launch), and the garden
renders its plants as words rather than art, which is waiting on the external illustrator.

The router's gate is no longer stubbed — it reads the habit count, so a user with nothing planted is
sent to plant something and only then gets a garden. The **debug-only dev-flavor seed button** on the
empty garden is therefore superseded by the real flow and kept only for convenience while testing
the watering; it is a deletion waiting for someone to want it.

---

## The three gates

`flutter analyze` · `dart format --output=none --set-exit-if-changed .` · `flutter test`

All three are green, and stay green in every commit. The infrastructure guide (§17) notes that
inkBlox let `flutter analyze` lapse in CI and it was far harder to restore than to maintain.
