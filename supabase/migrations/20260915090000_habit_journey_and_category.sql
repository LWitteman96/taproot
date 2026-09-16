-- habits.journey and habits.category — the server half of device schema
-- version 2 (lib/app/database/app_database.dart).
--
-- Written as ALTER TABLE rather than by editing the initial schema, which is
-- the pattern that migration's own header sets out: its `create table if not
-- exists` body is skipped entirely on a database that has already run it, so
-- an edit there reaches a from-scratch build and nothing else. This file is
-- the first use of that pattern; `test/unit/backend/enum_checks_test.dart`
-- reads the migrations in order and takes the last definition of each CHECK,
-- so a widening here is what counts.
--
-- Idempotent and re-runnable like every other migration: `add column if not
-- exists`, and the constraint dropped before it is recreated.

alter table public.habits add column if not exists journey text;
alter table public.habits add column if not exists category text;

-- ── journey ─────────────────────────────────────────────────────────────────
--
-- Nullable here while the device makes it NOT NULL on a fresh create, and the
-- asymmetry is deliberate. The device's upgrade adds the column nullable and
-- backfills it (`designed_cue is not null` → design, else track), so a device
-- that has upgraded always pushes a value. What nullable buys is the shape of
-- the failure if one ever does not: a NOT NULL column turns that row into a
-- 23502 the device retries forever — a wedged queue, on the one table every
-- other table's foreign key hangs off. Nullable turns it into a row that lands
-- and is reconciled on the way back, by the same inference the device already
-- applies: `Habit.fromJson` reads a missing journey as the cue-presence guess
-- rather than throwing.
--
-- No server default, for the reason `completions.source` has none: 'design' is
-- a real value the engine treats differently, not a safe filler, and a
-- serializer that dropped the column would have it silently invented.
--
-- The CHECK permits null by ordinary SQL semantics — `null in (...)` is null,
-- which a CHECK treats as satisfied — so it is written plainly rather than with
-- an `is null or` arm. That also keeps it in the shape the drift gate parses.
alter table public.habits drop constraint if exists habits_journey_known;
alter table public.habits add constraint habits_journey_known
  check (journey in ('design', 'track'));

comment on column public.habits.journey is
  'Which route the habit took into the garden. Recorded, not inferred: a '
  'tracked habit that locks in a discovered cue becomes indistinguishable from '
  'a designed one by its other columns, and the two populations behave '
  'differently under every engine metric.';

-- ── category ────────────────────────────────────────────────────────────────
--
-- **Deliberately no CHECK**, matching the device, which has none either. The
-- twelve values are authored against the starter chip library and that set
-- widens as the library grows — a CHECK here would make the next authored
-- category a failed sync push on every device running the newer build, which
-- is a worse failure than an unrecognised string.
--
-- The device reads it leniently to match (`readOpenEnum`: a value this build
-- does not know becomes null rather than throwing), and that leniency is why
-- the sync reconciliation must not treat a null category as the user clearing
-- one — see the pull.
--
-- camelCase is load-bearing: `languagePractice` and `sleepRoutine` are
-- `Enum.name` written verbatim, because `encodeEnum` is `value.name`. Spelling
-- either snake_case here is a FormatException on pull, not a tidy-up.
comment on column public.habits.category is
  'One of the starter chip library''s categories, as the Dart Enum.name. No '
  'CHECK on purpose: the set widens with the chip library, and the device '
  'reads it leniently. Optional — a habit that fits none of them still gets a '
  'first reflection from the global cue pools.';
