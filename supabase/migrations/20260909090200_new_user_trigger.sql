-- Taproot — profile row on sign-up.
--
-- A profile cannot be created by the client at sign-up time: the row has to
-- exist before the session that would insert it is usable, and RLS cannot see
-- into auth.users. So it is a security definer trigger, which is the one place
-- in this schema that runs with elevated rights.
--
-- Two guards that come with that, both required rather than stylistic:
--
--   * `set search_path = ''` — a security definer function with a mutable
--     search_path can be redirected at a shadowed function or table by anyone
--     who can set search_path. Every name below is therefore schema-qualified.
--   * `on conflict (id) do nothing` — the trigger must be re-runnable against a
--     user who already has a profile (a backfill, a re-run of this migration,
--     a future auth provider linking flow), and a failure here fails the whole
--     sign-up.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id)
  values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

comment on function public.handle_new_user() is
  'Creates the public.profiles row for a new auth user. security definer: RLS '
  'cannot see auth.users and the row must exist before the new session does.';

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Backfill any user who signed up before this trigger existed. Idempotent by
-- construction, and a no-op on a fresh project.
insert into public.profiles (id)
select id from auth.users
on conflict (id) do nothing;
