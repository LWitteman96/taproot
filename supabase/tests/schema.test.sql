-- Taproot — schema invariants.
--
-- These are the constraints that exist *because* the client cannot be trusted
-- to hold them: the Dart asserts that mirror them are stripped from release
-- builds, and a second device running an older build is a client too.
--
-- Run with `supabase test db` (or scripts/supabase-verify.sh, which also
-- re-applies every migration first to prove it is re-runnable).

begin;

create extension if not exists pgtap with schema extensions;

select plan(16);

-- ── RLS is on, everywhere, with nothing reachable by anon ───────────────────

select is(
  (select count(*)::int from pg_tables
     where schemaname = 'public' and not rowsecurity),
  0,
  'every table in public has row level security enabled'
);

select is(
  (select count(*)::int from information_schema.role_table_grants
     where table_schema = 'public' and grantee = 'anon'),
  0,
  'anon has no grants in public — there is nothing public about this schema'
);

select is(
  (select count(*)::int from information_schema.role_table_grants
     where table_schema = 'public'
       and grantee = 'authenticated'
       and privilege_type = 'DELETE'),
  0,
  'no DELETE is granted to any client role: sync is a union, so rows never '
  'go backwards. Erasure is delete-account running as service_role.'
);

select is(
  (select count(*)::int from information_schema.role_table_grants
     where table_schema = 'public'
       and grantee = 'authenticated'
       and privilege_type = 'UPDATE'
       and table_name in ('completions', 'completion_retractions')),
  0,
  'the two event ledgers are append-only — an edit to a past event is a '
  'different event'
);

-- ── Fixtures ────────────────────────────────────────────────────────────────

insert into auth.users (id, email)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'schema@example.com');

select is(
  (select count(*)::int from public.profiles
     where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  1,
  'handle_new_user created the profile row on sign-up'
);

-- ── The weekly target is 1..7 ───────────────────────────────────────────────

select throws_ok(
  $$insert into public.habits
      (id, user_id, name, plant_type, target_frequency, created_at, updated_at)
    values ('bbbbbbbb-0000-0000-0000-000000000001',
            'aaaaaaaa-0000-0000-0000-000000000001',
            'Run', 'fern', 0, now(), now())$$,
  '23514',
  null,
  'f = 0 is rejected: it divides through the whole engine as Infinity'
);

select throws_ok(
  $$insert into public.habits
      (id, user_id, name, plant_type, target_frequency, created_at, updated_at)
    values ('bbbbbbbb-0000-0000-0000-000000000002',
            'aaaaaaaa-0000-0000-0000-000000000001',
            'Run', 'fern', 8, now(), now())$$,
  '23514',
  null,
  'f = 8 is rejected: a weekly count cannot exceed seven days'
);

-- ── A designed cue must be externally schedulable ───────────────────────────

select throws_ok(
  $$insert into public.habits
      (id, user_id, name, plant_type, target_frequency, designed_cue_type,
       created_at, updated_at)
    values ('bbbbbbbb-0000-0000-0000-000000000003',
            'aaaaaaaa-0000-0000-0000-000000000001',
            'Run', 'fern', 3, 'internal', now(), now())$$,
  '23514',
  null,
  'an internal cue cannot be a *designed* cue — the engine cannot schedule, '
  'nudge or fairly measure a habit hung on a mood'
);

select lives_ok(
  $$insert into public.habits
      (id, user_id, name, plant_type, target_frequency, designed_cue_type,
       created_at, updated_at)
    values ('bbbbbbbb-0000-0000-0000-000000000004',
            'aaaaaaaa-0000-0000-0000-000000000001',
            'Run', 'fern', 3, 'event', now(), now())$$,
  'an event cue is admissible as a designed cue'
);

-- ── Enum columns carry the Dart Enum.name verbatim ──────────────────────────

select lives_ok(
  $$insert into public.completions
      (habit_id, id, user_id, completed_at, source)
    values ('bbbbbbbb-0000-0000-0000-000000000004',
            'cccccccc-0000-0000-0000-000000000001',
            'aaaaaaaa-0000-0000-0000-000000000001', now(), 'nudgeConfirmation')$$,
  'source accepts the camelCase wire value encodeEnum() produces'
);

select throws_ok(
  $$insert into public.completions
      (habit_id, id, user_id, completed_at, source)
    values ('bbbbbbbb-0000-0000-0000-000000000004',
            'cccccccc-0000-0000-0000-000000000002',
            'aaaaaaaa-0000-0000-0000-000000000001', now(), 'nudge_confirmation')$$,
  '23514',
  null,
  'source rejects the snake_case spelling — a value the app could not decode '
  'must fail at insert, not sit in the table'
);

select throws_ok(
  $$insert into public.reflections
      (id, habit_id, user_id, created_at, occasion, framing, input_mode,
       updated_at)
    values ('dddddddd-0000-0000-0000-000000000001',
            'bbbbbbbb-0000-0000-0000-000000000004',
            'aaaaaaaa-0000-0000-0000-000000000001',
            now(), 'completion', 'reassurance', 'chip', now())$$,
  '23514',
  null,
  'framing rejects a value that is not in reflection-logic §3'
);

-- ── The append-only completion key is (habit_id, id) ────────────────────────

select throws_ok(
  $$insert into public.completions
      (habit_id, id, user_id, completed_at)
    values ('bbbbbbbb-0000-0000-0000-000000000004',
            'cccccccc-0000-0000-0000-000000000001',
            'aaaaaaaa-0000-0000-0000-000000000001', now())$$,
  '23505',
  null,
  'replaying the same client UUID for the same habit is a union, not a '
  'duplicate row'
);

-- ── synced_at is the server''s clock, not the client''s ─────────────────────

insert into public.nudges
  (id, habit_id, user_id, expected_occasion_at, updated_at, synced_at)
values ('eeeeeeee-0000-0000-0000-000000000001',
        'bbbbbbbb-0000-0000-0000-000000000004',
        'aaaaaaaa-0000-0000-0000-000000000001',
        now(), now(), '1999-01-01T00:00:00Z');

select ok(
  (select synced_at from public.nudges
     where id = 'eeeeeeee-0000-0000-0000-000000000001') > '2020-01-01T00:00:00Z',
  'a client-supplied synced_at is overwritten with the server clock — a skewed '
  'device must not be able to write a row a later pull will never see'
);

-- ── Deleting the auth user is the whole deletion ────────────────────────────

delete from auth.users where id = 'aaaaaaaa-0000-0000-0000-000000000001';

select is(
  (select count(*)::int from public.habits
     where user_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  0,
  'deleting the auth user cascades to habits — what delete-account relies on'
);

select is(
  (select count(*)::int from public.completions
     where user_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  0,
  'and on through the child tables, so nothing is left orphaned'
);

select * from finish();

rollback;
