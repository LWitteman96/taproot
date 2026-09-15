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

select plan(24);

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
       cue_type, updated_at)
    values ('dddddddd-0000-0000-0000-000000000001',
            'bbbbbbbb-0000-0000-0000-000000000004',
            'aaaaaaaa-0000-0000-0000-000000000001',
            now(), 'completion', 'reassurance', 'chip', 'unknown', now())$$,
  '23514',
  null,
  'framing rejects a value that is not in reflection-logic §3'
);

-- Client-owned columns have no server default, so a push that drops one fails
-- loudly instead of having a value invented for it. 'tap' and 'unknown' are
-- both real values the engine treats specially — a serializer bug that lost
-- the column would have recorded a nudgeConfirmation as a tap and miscounted
-- autonomy on every device that later pulled it, with nothing to see anywhere.

select throws_ok(
  $$insert into public.completions
      (habit_id, id, user_id, completed_at)
    values ('bbbbbbbb-0000-0000-0000-000000000004',
            'cccccccc-0000-0000-0000-000000000003',
            'aaaaaaaa-0000-0000-0000-000000000001', now())$$,
  '23502',
  null,
  'a completion without a source is rejected rather than defaulted to tap — '
  'the device schema has no default here either'
);

select throws_ok(
  $$insert into public.reflections
      (id, habit_id, user_id, created_at, occasion, framing, input_mode,
       updated_at)
    values ('dddddddd-0000-0000-0000-000000000002',
            'bbbbbbbb-0000-0000-0000-000000000004',
            'aaaaaaaa-0000-0000-0000-000000000001',
            now(), 'completion', 'validation', 'chip', now())$$,
  '23502',
  null,
  'and a reflection without a cue_type is not quietly filed as unknown'
);

-- ── The append-only completion key is (habit_id, id) ────────────────────────

select throws_ok(
  $$insert into public.completions
      (habit_id, id, user_id, completed_at, source)
    values ('bbbbbbbb-0000-0000-0000-000000000004',
            'cccccccc-0000-0000-0000-000000000001',
            'aaaaaaaa-0000-0000-0000-000000000001', now(), 'tap')$$,
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

-- ── Every table with a cursor has a trigger to move it ──────────────────────

select is(
  (select count(*)::int
     from information_schema.columns c
     where c.table_schema = 'public'
       and c.column_name = 'synced_at'
       and not exists (
         select 1 from pg_trigger t
           join pg_class r on r.oid = t.tgrelid
           join pg_namespace n on n.oid = r.relnamespace
          where n.nspname = 'public'
            and r.relname = c.table_name
            and t.tgname = 'set_synced_at'
            and not t.tgisinternal)),
  0,
  'every table carrying synced_at also has the trigger that moves it — a '
  'cursor column frozen at its default is worse than no cursor at all'
);

-- Captured before the update, and compared strictly greater afterwards. The
-- obvious form of this assertion — synced_at >= updated_at — is vacuous: the
-- update below does not touch updated_at, which keeps its insert-time now()
-- (transaction start), and the insert-time synced_at is already a
-- clock_timestamp() at or after that. It passes with a before-insert-only
-- trigger, which is precisely the regression worth catching: a pull cursor
-- frozen at insert time means updated rows never re-enter an incremental pull.
create temporary table nudge_synced_before as
select synced_at
  from public.nudges
 where id = 'eeeeeeee-0000-0000-0000-000000000001';

update public.nudges
   set confirmed = true
 where id = 'eeeeeeee-0000-0000-0000-000000000001';

select ok(
  (select synced_at from public.nudges
     where id = 'eeeeeeee-0000-0000-0000-000000000001')
    > (select synced_at from nudge_synced_before),
  'and moves it on update, not only on insert — an updated row has to re-enter '
  'an incremental pull, so the cursor must advance when the row changes'
);

-- ── A soft delete is one-way ────────────────────────────────────────────────

update public.habits
   set deleted_at = now()
 where id = 'bbbbbbbb-0000-0000-0000-000000000004';

select throws_ok(
  $$update public.habits
       set deleted_at = null, name = 'resurrected'
     where id = 'bbbbbbbb-0000-0000-0000-000000000004'$$,
  'PT409',
  null,
  'a stale push cannot clear deleted_at and resurrect a habit — revoking '
  'DELETE is only half of that guarantee, pin_soft_delete() is the other half'
);

select isnt(
  (select deleted_at from public.habits
     where id = 'bbbbbbbb-0000-0000-0000-000000000004'),
  null,
  'and the habit is still deleted afterwards — the whole statement rolls back, '
  'so the other columns it carried do not half-apply either'
);

select is(
  (select name from public.habits
     where id = 'bbbbbbbb-0000-0000-0000-000000000004'),
  'Run',
  'including the ones that would have gone backwards: a blocked write that '
  'reports success is what this raise exists to stop'
);

-- The benign race the raise must not break: two devices each delete the same
-- habit, so the second push carries a different, later stamp. First deletion
-- wins and the push still succeeds — nothing is being resurrected.
update public.habits
   set deleted_at = now() + interval '1 hour'
 where id = 'bbbbbbbb-0000-0000-0000-000000000004';

select ok(
  (select deleted_at from public.habits
     where id = 'bbbbbbbb-0000-0000-0000-000000000004') < now() + interval '1 hour',
  'a second device deleting an already-deleted habit keeps the first stamp '
  'rather than failing — first deletion wins, and it is still a union'
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
