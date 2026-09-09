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
-- House rule: migrations are idempotent and re-runnable, so the same file
-- applies cleanly to local, staging and production at different points in
-- their history. Everything below is `IF NOT EXISTS` / `CREATE OR REPLACE`.
-- CI re-applies every migration a second time and re-runs the tests.

-- Text enum columns carry the Dart `Enum.name` verbatim — `encodeEnum` in
-- lib/core/utils/json_codec.dart is `value.name`, so the wire format is
-- camelCase ('nudgeConfirmation', 'autonomyCompletion', 'cantRemember') and
-- not snake_case. The CHECK lists below must stay in step with
-- lib/core/engine/domain.dart; a value added there and not here is a sync
-- failure at insert time, which is the failure mode we want over a silently
-- accepted string the app can no longer decode.

-- ── Sync cursor ─────────────────────────────────────────────────────────────

create or replace function public.set_synced_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.synced_at := now();
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
  'yet heard about a deletion cannot resurrect one by re-pushing its copy.';

create index if not exists idx_habits_user_synced_at
  on public.habits (user_id, synced_at);

drop trigger if exists set_synced_at on public.habits;
create trigger set_synced_at before insert or update on public.habits
  for each row execute function public.set_synced_at();

-- ── completions ─────────────────────────────────────────────────────────────

-- Append-only events: no updated_at, no deleted_at, and a composite primary key
-- so replaying the same client UUID for the same habit is a union.
create table if not exists public.completions (
  habit_id uuid not null,
  id uuid not null,
  user_id uuid not null,
  completed_at timestamptz not null,
  was_nudged boolean not null default false,
  source text not null default 'tap'
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

create index if not exists idx_completions_habit_completed_at
  on public.completions (habit_id, completed_at);
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
  cue_type text not null default 'unknown'
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
