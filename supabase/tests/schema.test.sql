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

select plan(37);

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

-- ── journey is closed, category is open ─────────────────────────────────────
--
-- The asymmetry is the point, and it is not an oversight on either side: the
-- journey's two values are fixed by design-spec §2, while the categories are
-- authored against the starter chip library and that set grows.

select lives_ok(
  $$update public.habits set journey = 'track'
     where id = 'bbbbbbbb-0000-0000-0000-000000000004'$$,
  'journey accepts the camelCase wire values design-spec §2 fixes'
);

select throws_ok(
  $$update public.habits set journey = 'Design'
     where id = 'bbbbbbbb-0000-0000-0000-000000000004'$$,
  '23514',
  null,
  'and rejects anything else — the set is closed, so a value the app could '
  'not decode must fail at write time'
);

select lives_ok(
  $$update public.habits set journey = null
     where id = 'bbbbbbbb-0000-0000-0000-000000000004'$$,
  'journey is nullable, unlike the device''s fresh schema: a row that somehow '
  'arrives without one has to land and be reconciled on the way back, rather '
  'than becoming a 23502 the device retries forever'
);

select lives_ok(
  $$update public.habits set category = 'languagePractice'
     where id = 'bbbbbbbb-0000-0000-0000-000000000004'$$,
  'category carries Enum.name verbatim — camelCase, not snake_case, because '
  'encodeEnum is value.name and a mismatch is a FormatException on pull'
);

select lives_ok(
  $$update public.habits set category = 'aCategoryAuthoredLater'
     where id = 'bbbbbbbb-0000-0000-0000-000000000004'$$,
  'and has no CHECK on purpose: the chip library widens the set, and a '
  'constraint here would make the next authored category a failed push on '
  'every device running the newer build'
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

-- ── Last write wins, enforced rather than trusted ───────────────────────────
--
-- The sync drain pulls before it pushes so a stale row is reconciled away
-- before it can be sent. These pin the same rule in the database, because the
-- failure the ordering guards against — a stale push overwriting a newer edit
-- from another device — is silent on both devices afterwards.

insert into public.habits
  (id, user_id, name, plant_type, target_frequency, created_at, updated_at)
values ('bbbbbbbb-0000-0000-0000-000000000005',
        'aaaaaaaa-0000-0000-0000-000000000001',
        'Stretch', 'fern', 3, now(), '2026-03-05T00:00:00Z');

select throws_ok(
  $$update public.habits
       set name = 'overwritten by a stale device',
           updated_at = '2026-03-04T00:00:00Z'
     where id = 'bbbbbbbb-0000-0000-0000-000000000005'$$,
  'PT409',
  null,
  'an update whose updated_at goes backwards is refused — the caller doing it '
  'in the right order is a convention, and this is the constraint'
);

select is(
  (select name from public.habits
     where id = 'bbbbbbbb-0000-0000-0000-000000000005'),
  'Stretch',
  'and the newer row is still there, whole: the statement rolled back rather '
  'than half-applying'
);

select lives_ok(
  $$update public.habits
       set name = 'an identical replay',
           updated_at = '2026-03-05T00:00:00Z'
     where id = 'bbbbbbbb-0000-0000-0000-000000000005'$$,
  'an equal updated_at is accepted — the overlap window re-reads covered '
  'ground and a retried push resends a batch verbatim, so a replay is what '
  'sync does all day rather than an anomaly'
);

select lives_ok(
  $$update public.habits
       set name = 'a genuinely newer edit',
           updated_at = '2026-03-06T00:00:00Z'
     where id = 'bbbbbbbb-0000-0000-0000-000000000005'$$,
  'and a newer one is what the rule exists to let through'
);

-- ── The nudge ledger: exempt from the gate, but not ungoverned ─────────────
--
-- `nudges` is deliberately exempt from reject_stale_update, because a flag
-- write from the device that did *not* create the row is legitimate and a
-- strict `updated_at` gate would reject it. The exemption is only safe while
-- merge_nudge_flags() supplies the rule it was justified by — OR'd monotonic
-- flags — so these four assertions pin the exemption and the rule together.
--
-- The first one on its own used to be the whole test, and it was vacuous: it
-- set `confirmed = true` on a row where `confirmed` was already true. It
-- asserted that the exemption exists, which nothing threatened, and said
-- nothing about the merge, which did not exist.

update public.nudges
   set sent = true, confirmed = true
 where id = 'eeeeeeee-0000-0000-0000-000000000001';

select lives_ok(
  $$update public.nudges
       set declined = true, updated_at = '1999-01-01T00:00:00Z'
     where id = 'eeeeeeee-0000-0000-0000-000000000001'$$,
  'the nudge ledger is exempt from the stale gate, because a flag write from '
  'the device that did not create the row is legitimate and its merge rule is '
  'not whole-row last-write-wins'
);

-- The write above carried the column defaults for sent and confirmed — false —
-- which is exactly the shape of the failure: a device that has not heard about
-- an answer pushes its whole row, and an unconditional ON CONFLICT DO UPDATE
-- takes the cleared flag. Every device then pulls it back, and the device that
-- holds the truth is no longer pending, so it never re-pushes it.
select is(
  (select confirmed from public.nudges
     where id = 'eeeeeeee-0000-0000-0000-000000000001'),
  true,
  'and a stale write cannot clear an answer the user has already given — '
  'without the merge the server stays wrong forever and a reinstall pulls the '
  'answer as never given'
);

select is(
  (select sent from public.nudges
     where id = 'eeeeeeee-0000-0000-0000-000000000001'),
  true,
  'nor roll `sent` back, which is the worse half: an occasion that WAS nudged '
  'moving into autonomy''s un-nudged denominator depresses the graduation gate'
);

select ok(
  (select updated_at from public.nudges
     where id = 'eeeeeeee-0000-0000-0000-000000000001')
    > '2020-01-01T00:00:00Z',
  'and updated_at is clamped forward rather than wound back — the stale writer '
  'keeps its flag contribution without moving the timestamp every other device '
  'compares against and pages on'
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
