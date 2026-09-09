-- Taproot — row level security, from the client's seat.
--
-- The policies are trivial, which is exactly why they are worth testing: a
-- schema with one rule and no exceptions fails silently when the rule is missed
-- on one table. Every test below runs as the `authenticated` role with a
-- request JWT, the same way PostgREST runs a request.

begin;

create extension if not exists pgtap with schema extensions;

select plan(11);

-- ── Two users, one habit each ───────────────────────────────────────────────

insert into auth.users (id, email) values
  ('11111111-0000-0000-0000-000000000001', 'ana@example.com'),
  ('22222222-0000-0000-0000-000000000002', 'ben@example.com');

insert into public.habits
  (id, user_id, name, plant_type, target_frequency, created_at, updated_at)
values
  ('aaaa1111-0000-0000-0000-000000000001',
   '11111111-0000-0000-0000-000000000001', 'Ana runs', 'fern', 3, now(), now()),
  ('bbbb2222-0000-0000-0000-000000000002',
   '22222222-0000-0000-0000-000000000002', 'Ben reads', 'ivy', 5, now(), now());

insert into public.completions (habit_id, id, user_id, completed_at)
values
  ('bbbb2222-0000-0000-0000-000000000002',
   'cccc2222-0000-0000-0000-000000000002',
   '22222222-0000-0000-0000-000000000002', now());

-- ── anon ────────────────────────────────────────────────────────────────────

set local role anon;

select throws_ok(
  'select count(*) from public.habits',
  '42501',
  null,
  'anon cannot read habits at all — the grant is revoked, not just policed'
);

reset role;

-- ── Ana ─────────────────────────────────────────────────────────────────────

set local request.jwt.claims = '{"sub":"11111111-0000-0000-0000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (select count(*)::int from public.habits),
  1,
  'Ana sees exactly her own habit'
);

select is(
  (select count(*)::int from public.completions),
  0,
  'and none of Ben''s completions'
);

select throws_ok(
  $$insert into public.habits
      (id, user_id, name, plant_type, target_frequency, created_at, updated_at)
    values ('aaaa1111-0000-0000-0000-000000000009',
            '22222222-0000-0000-0000-000000000002',
            'Planted in Ben''s garden', 'fern', 3, now(), now())$$,
  '42501',
  null,
  'Ana cannot create a habit owned by Ben'
);

select throws_ok(
  $$update public.habits
      set user_id = '22222222-0000-0000-0000-000000000002'
    where id = 'aaaa1111-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'Ana cannot hand her habit to Ben — the WITH CHECK is what stops an update '
  'moving a row out of ownership'
);

select is(
  (select count(*)::int from public.habits
     where id = 'bbbb2222-0000-0000-0000-000000000002'),
  0,
  'Ben''s habit is not merely unwritable, it is invisible'
);

-- A completion Ana owns, hung on a habit Ben owns. RLS is satisfied — the row
-- carries her user_id — and the composite foreign key is what catches it.
select throws_ok(
  $$insert into public.completions (habit_id, id, user_id, completed_at)
    values ('bbbb2222-0000-0000-0000-000000000002',
            'cccc1111-0000-0000-0000-000000000009',
            '11111111-0000-0000-0000-000000000001', now())$$,
  '23503',
  null,
  'a completion cannot be attached to another user''s habit: the (habit_id, '
  'user_id) foreign key catches what an ownership check on user_id alone '
  'cannot see'
);

select lives_ok(
  $$insert into public.completions (habit_id, id, user_id, completed_at)
    values ('aaaa1111-0000-0000-0000-000000000001',
            'cccc1111-0000-0000-0000-000000000001',
            '11111111-0000-0000-0000-000000000001', now())$$,
  'Ana can water her own plant'
);

select throws_ok(
  $$update public.completions set was_nudged = true
    where id = 'cccc1111-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'and cannot then rewrite it — completions are an append-only ledger'
);

select throws_ok(
  $$delete from public.completions
    where id = 'cccc1111-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'nor delete it: an undo is a row in completion_retractions, which is what '
  'stops a device that never heard about the undo from resurrecting it'
);

select throws_ok(
  $$delete from public.habits
    where id = 'aaaa1111-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'deleting a habit is deleted_at, not DELETE'
);

select * from finish();

rollback;
