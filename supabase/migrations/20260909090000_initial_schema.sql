-- Taproot — initial schema.
--
-- This is the durable-backup and cross-device-sync mirror of the device's
-- SQLite store (lib/app/database/app_database.dart), which is the *primary*
-- store. Read that file first: the shapes here are its shapes, and the reasons
-- they are load-bearing are written out there in full. The short version:
--
--   * `completions` is keyed by (habit_id, id) with the UUID generated
--     client-side, so merging two devices is a union rather than a merge.
--   * `completion_retractions` is the undo ledger — an undo is an insert, never
--     a DELETE — and deliberately has no foreign key to `completions`, because
--     a retraction can sync ahead of the completion it retracts.
--   * `nudges` holds a row for every expected occasion including the ones the
--     engine deliberately stayed silent on. Those rows are autonomy's
--     denominator and cannot be inferred from the absence of a notification.
--   * `habits` has no `paused_at`: a habit is paused iff it has an open row in
--     `habit_pauses`, so that fact lives in exactly one place.
--   * No table stores a derived engine value. Stage, vitality, roots and
--     autonomy are computed from these rows, so tuning an engine constant is
--     never a data migration.
--
-- Two columns that exist here and not on the device:
--
--   * `user_id`, on every table, because RLS is `user_id = auth.uid()` and a
--     join back to `habits` on every row read is not.
--   * `synced_at`, the pull cursor. `updated_at` comes off the *client's*
--     clock and is what the app compares; `synced_at` comes off the server's
--     and is what an incremental pull ranges over. Conflating them means a
--     device with a skewed clock can write rows a later pull never sees.
--
-- READ THIS BEFORE BUILDING THE PULL. `synced_at` is stamped when the row is
-- written, and the row becomes visible when its transaction commits — which is
-- later, by however long the rest of that transaction took. A pull that reads
-- at T and stores `cursor = T` can therefore miss a row stamped before T that
-- commits after it, permanently. Two ways out, and the sync branch has to pick
-- one: overlap the window (pull from `cursor - slack`, and rely on the upsert
-- being idempotent, which every table here is), or move the cursor off the
-- clock entirely onto `xid8`/`pg_current_snapshot()`. What does *not* work is
-- `synced_at > cursor` with the cursor set to the read time.
--
-- Two columns the client must supply that nothing here defaults: `user_id`,
-- and `updated_at` on the mutable tables. `updated_at` deliberately has no
-- `default now()` — it is the client's clock and the app compares it, so a
-- server default would quietly invent a value the app then treats as the
-- device's. A push that omits either gets a 23502, which is the intended
-- failure: the local row has both.
--
-- House rule: migrations are idempotent and re-runnable, so the same file
-- applies cleanly to local, staging and production at different points in
-- their history. Everything below is `IF NOT EXISTS` / `CREATE OR REPLACE`.
-- CI re-applies every migration a second time and re-runs the tests.

-- Text enum columns carry the Dart `Enum.name` verbatim — `encodeEnum` in
-- lib/core/utils/json_codec.dart is `value.name`, so the wire format is
-- camelCase ('nudgeConfirmation', 'autonomyCompletion', 'cantRemember') and
-- not snake_case. The CHECK lists below must stay in step with the Dart enums
-- they mirror, which live in lib/core/engine/domain.dart *and*
-- lib/core/models/completion.dart (`CompletionSource`). A value added there
-- and not here is a sync failure at insert time, which is the failure mode we
-- want over a silently accepted string the app can no longer decode.
--
-- HOW TO WIDEN ONE, because the obvious way does not work. Editing a CHECK
-- below changes nothing on a database that has already run this file: the
-- constraints are inside `create table if not exists`, so a second apply skips
-- the whole statement, and `supabase db push` only ever applies migrations it
-- has not seen. `supabase db reset` and CI rebuild from scratch and therefore
-- go green either way — the drift shows up only as a 23514 on the first push
-- carrying the new value, in the one environment nobody can reset.
--
-- Widening is a NEW migration, and this is the whole pattern:
--
--   alter table public.completions
--     drop constraint if exists completions_source_known;
--   alter table public.completions
--     add constraint completions_source_known
--       check (source in ('tap', 'nudgeConfirmation', 'backfill', 'import'));
--
-- Edit the list below in the same commit as well, so a from-scratch build and
-- a migrated one end up identical. `test/unit/backend/enum_checks_test.dart`
-- is the gate: it reads these CHECK lists and fails if they and the Dart enums
-- have drifted. It runs in the Flutter suite, which — unlike the Supabase
-- workflow — is not path-filtered away by a change under lib/.

-- ── Sync cursor ─────────────────────────────────────────────────────────────

create or replace function public.set_synced_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- clock_timestamp(), not now(): now() is transaction_timestamp(), so every
  -- row in a batched push would carry the moment the transaction *opened*.
  -- See the warning on the column below — this narrows that window, it does
  -- not close it.
  new.synced_at := clock_timestamp();
  return new;
end;
$$;

comment on function public.set_synced_at() is
  'Stamps the server-clock pull cursor. Clients never set synced_at; a client '
  'clock is not ordered against the server''s and a pull ranges over this.';

-- ── profiles ────────────────────────────────────────────────────────────────

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  synced_at timestamptz not null default now()
);

comment on table public.profiles is
  'One row per auth user, created by the handle_new_user trigger. Deliberately '
  'near-empty: there is no social graph, and app settings live on-device until '
  'something needs them server-side.';

drop trigger if exists set_synced_at on public.profiles;
create trigger set_synced_at before insert or update on public.profiles
  for each row execute function public.set_synced_at();

-- ── habits ──────────────────────────────────────────────────────────────────

create table if not exists public.habits (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  identity_statement text,
  plant_type text not null,
  target_frequency integer not null
    constraint habits_target_frequency_weekly_count
      check (target_frequency between 1 and 7),
  designed_cue text,
  designed_cue_type text
    constraint habits_designed_cue_type_schedulable
      check (designed_cue_type in ('event', 'time', 'location', 'social')),
  routine text,
  reward text,
  created_at timestamptz not null,
  graduated_at timestamptz,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  synced_at timestamptz not null default now(),
  -- Redundant against the primary key, and that is the point: it is what lets
  -- every child table carry a composite (habit_id, user_id) foreign key.
  constraint habits_id_user_id_key unique (id, user_id)
);

comment on constraint habits_target_frequency_weekly_count on public.habits is
  'f is a weekly count in 1..7. Checked in the schema because the matching '
  'asserts in Habit and HabitInputs are stripped from release builds, and a '
  'target of 0 divides through the whole engine as Infinity.';

comment on constraint habits_designed_cue_type_schedulable on public.habits is
  'Only externally schedulable cue types may anchor a *designed* cue — the '
  'engine cannot schedule, nudge or fairly measure a habit hung on a mood. '
  'internal and unknown remain valid as cues discovered through reflection, '
  'which is why reflections.cue_type admits all six.';

comment on column public.habits.deleted_at is
  'Soft delete. Rows are never removed by the client, so a device that has not '
  'yet heard about a deletion cannot resurrect one by re-pushing its copy — '
  'see pin_soft_delete(), which is what actually enforces that.';

-- Revoking DELETE is only half of "a deletion cannot be undone by a device
-- that never heard about it". The other half is this: without it, an offline
-- device pushing its stale copy of the row sets deleted_at back to null and
-- the habit reappears, on every device, with all of its children still live.
--
-- The *first* deletion wins, so a second device pushing a later stamp cannot
-- move it either. graduated_at is deliberately not pinned: graduation is
-- derived from autonomy, which can fall, and whether it is one-way is the
-- engine's question to answer rather than something to freeze here by
-- analogy.
-- It raises rather than quietly coalescing, which it used to do. Silently
-- dropping the deleted_at half of an UPDATE while applying every other column
-- and answering 200 has two bad ends. A stale device that never heard about
-- the deletion pushes its whole row, is told the push landed, and has in fact
-- had only some of its columns written. And a sanctioned undelete — a "Deleted
-- — Undo" affordance, or support restoring a habit — looks like it worked,
-- reappears locally, and vanishes again on the next pull with no error
-- anywhere to debug from. Triggers are not bypassed by service_role the way
-- RLS is, so that second one is not hypothetical.
--
-- If an undelete is ever wanted it needs a sanctioned path that clears the
-- stamp deliberately — a `security definer` RPC that this trigger exempts —
-- rather than a whole-row push that happens to carry a null.
--
-- PT409 is PostgREST's convention for choosing the HTTP status: the push comes
-- back 409 Conflict, which is what it is. The sync branch should read a 409 on
-- a habit push as "this habit is deleted upstream — pull, do not retry".
create or replace function public.pin_soft_delete()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- A live habit, including the update that performs the deletion.
  if old.deleted_at is null then
    return new;
  end if;

  -- The same deletion again, which sync replays constantly.
  if new.deleted_at is not distinct from old.deleted_at then
    return new;
  end if;

  -- A second device deleting a habit already deleted: first deletion wins, and
  -- nothing is being resurrected, so this stays a quiet no-op on that column.
  if new.deleted_at is not null then
    new.deleted_at := old.deleted_at;
    return new;
  end if;

  raise exception
    'habit % is deleted (deleted_at = %); deleted_at is one-way',
    old.id, old.deleted_at
    using errcode = 'PT409',
          hint = 'Pull rather than retrying. Undeleting needs a sanctioned '
                 'RPC, not a whole-row push carrying a null deleted_at.';
end;
$$;

comment on function public.pin_soft_delete() is
  'Makes habits.deleted_at one-way and first-write-wins. Clearing a set stamp '
  'raises PT409 rather than being ignored: a blocked write that reports '
  'success is how an undelete looks fixed and then vanishes on the next pull.';

create index if not exists idx_habits_user_synced_at
  on public.habits (user_id, synced_at);

drop trigger if exists set_synced_at on public.habits;
create trigger set_synced_at before insert or update on public.habits
  for each row execute function public.set_synced_at();

drop trigger if exists pin_soft_delete on public.habits;
create trigger pin_soft_delete before update on public.habits
  for each row execute function public.pin_soft_delete();

-- ── completions ─────────────────────────────────────────────────────────────

-- Append-only events: no updated_at, no deleted_at, and a composite primary key
-- so replaying the same client UUID for the same habit is a union.
create table if not exists public.completions (
  habit_id uuid not null,
  id uuid not null,
  user_id uuid not null,
  completed_at timestamptz not null,
  was_nudged boolean not null default false,
  -- No default, matching the device (app_database.dart: `source TEXT NOT
  -- NULL`). A push that omits it gets a 23502, per the header rule above: a
  -- serializer bug that drops the column must fail rather than have the server
  -- record a nudgeConfirmation as a tap and miscount autonomy on every device
  -- that later pulls it.
  source text not null
    constraint completions_source_known
      check (source in ('tap', 'nudgeConfirmation', 'backfill')),
  synced_at timestamptz not null default now(),
  primary key (habit_id, id),
  foreign key (habit_id, user_id)
    references public.habits (id, user_id) on delete cascade
);

comment on constraint completions_habit_id_user_id_fkey on public.completions is
  'Composite on purpose: it makes "this completion belongs to the same user as '
  'its habit" a foreign key rather than a policy the RLS check has to be '
  'trusted to have got right.';

-- No (habit_id, completed_at) index here, deliberately, though the sibling
-- tables below all have their habit_id-leading one. Those serve the ON DELETE
-- CASCADE from habits; completions gets that for free from its primary key,
-- whose leading column is already habit_id. A second index on the same leading
-- column would be pure write cost on the hottest insert path in the schema —
-- and nothing server-side orders completions by completed_at, because every
-- engine read runs against the device's SQLite.
create index if not exists idx_completions_user_synced_at
  on public.completions (user_id, synced_at);

drop trigger if exists set_synced_at on public.completions;
create trigger set_synced_at before insert or update on public.completions
  for each row execute function public.set_synced_at();

-- ── completion_retractions ──────────────────────────────────────────────────

-- The undo ledger. No foreign key to completions: on a multi-device sync the
-- retraction can arrive before the completion it retracts, and it has to be
-- storable when it does.
create table if not exists public.completion_retractions (
  habit_id uuid not null,
  completion_id uuid not null,
  user_id uuid not null,
  retracted_at timestamptz not null,
  synced_at timestamptz not null default now(),
  primary key (habit_id, completion_id),
  foreign key (habit_id, user_id)
    references public.habits (id, user_id) on delete cascade
);

create index if not exists idx_completion_retractions_user_synced_at
  on public.completion_retractions (user_id, synced_at);

drop trigger if exists set_synced_at on public.completion_retractions;
create trigger set_synced_at before insert or update on public.completion_retractions
  for each row execute function public.set_synced_at();

-- ── reflections ─────────────────────────────────────────────────────────────

create table if not exists public.reflections (
  id uuid primary key,
  habit_id uuid not null,
  user_id uuid not null,
  created_at timestamptz not null,
  occasion text not null
    constraint reflections_occasion_known
      check (occasion in ('completion', 'miss', 'autonomyCompletion')),
  framing text not null
    constraint reflections_framing_known
      check (framing in ('validation', 'discovery', 'confirmation',
                         'diagnosis', 'autonomy')),
  input_mode text not null
    constraint reflections_input_mode_known
      check (input_mode in ('chip', 'typed', 'cantRemember', 'skipped')),
  cue_reported text,
  -- No default, for the reason given on completions.source: 'unknown' is a
  -- real CueType the engine treats specially, not a safe filler.
  cue_type text not null
    constraint reflections_cue_type_known
      check (cue_type in ('event', 'time', 'location', 'internal',
                          'social', 'unknown')),
  matched_designed_cue boolean,
  friction_reported text,
  friction_type text
    constraint reflections_friction_type_known
      check (friction_type in ('forgot', 'time', 'energy', 'competing',
                               'environment', 'motivation')),
  was_nudged boolean not null default false,
  updated_at timestamptz not null,
  synced_at timestamptz not null default now(),
  foreign key (habit_id, user_id)
    references public.habits (id, user_id) on delete cascade
);

comment on table public.reflections is
  'reflection-logic §5 verbatim, minus root_credit and counts_toward_c: both '
  'are derived (rootCreditFor / countsTowardConvergence in '
  'lib/core/engine/roots.dart) and derived values are computed, never stored.';

comment on column public.reflections.matched_designed_cue is
  'Null when not applicable. The share of true across validations is the '
  'cue-reliability number the cue-testing phase displays.';

create index if not exists idx_reflections_habit_created_at
  on public.reflections (habit_id, created_at);
create index if not exists idx_reflections_user_synced_at
  on public.reflections (user_id, synced_at);

drop trigger if exists set_synced_at on public.reflections;
create trigger set_synced_at before insert or update on public.reflections
  for each row execute function public.set_synced_at();

-- ── nudges ──────────────────────────────────────────────────────────────────

create table if not exists public.nudges (
  id uuid primary key,
  habit_id uuid not null,
  user_id uuid not null,
  expected_occasion_at timestamptz not null,
  scheduled_for timestamptz,
  sent boolean not null default false,
  confirmed boolean not null default false,
  declined boolean not null default false,
  updated_at timestamptz not null,
  synced_at timestamptz not null default now(),
  foreign key (habit_id, user_id)
    references public.habits (id, user_id) on delete cascade
);

comment on table public.nudges is
  'One row per expected occasion, INCLUDING the occasions the engine chose to '
  'stay silent on (sent = false). Those are autonomy''s denominator. There is '
  'deliberately no unique constraint on (habit_id, expected_occasion_at): the '
  'device does not have one either, so adding it here would turn a duplicate '
  'into a failed sync push rather than a row the sync branch can reconcile.';

create index if not exists idx_nudges_habit_occasion_at
  on public.nudges (habit_id, expected_occasion_at);
create index if not exists idx_nudges_user_synced_at
  on public.nudges (user_id, synced_at);

drop trigger if exists set_synced_at on public.nudges;
create trigger set_synced_at before insert or update on public.nudges
  for each row execute function public.set_synced_at();

-- ── habit_pauses ────────────────────────────────────────────────────────────

create table if not exists public.habit_pauses (
  id uuid primary key,
  habit_id uuid not null,
  user_id uuid not null,
  started_at timestamptz not null,
  ended_at timestamptz,
  updated_at timestamptz not null,
  synced_at timestamptz not null default now(),
  foreign key (habit_id, user_id)
    references public.habits (id, user_id) on delete cascade
);

comment on table public.habit_pauses is
  'The pause ledger, and the only place "is this habit paused" lives. An open '
  'row (ended_at is null) is the pause. Paused days are excluded from every '
  'engine window — they are not misses (growth spec §7).';

create index if not exists idx_habit_pauses_habit_started_at
  on public.habit_pauses (habit_id, started_at);
create index if not exists idx_habit_pauses_user_synced_at
  on public.habit_pauses (user_id, synced_at);

drop trigger if exists set_synced_at on public.habit_pauses;
create trigger set_synced_at before insert or update on public.habit_pauses
  for each row execute function public.set_synced_at();
