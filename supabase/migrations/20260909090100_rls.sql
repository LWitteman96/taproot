-- Taproot — row level security.
--
-- The access matrix is trivial and has no exceptions: every row belongs to
-- exactly one user, and `user_id = auth.uid()` is the whole of it. There is no
-- social graph, so none of the recursion that RLS on a shared-visibility schema
-- attracts applies here. Keep it that way.
--
-- Three conventions, all deliberate:
--
--   * `(SELECT auth.uid())` rather than `auth.uid()`. The subquery form lets
--     Postgres evaluate the call once per statement instead of once per row.
--   * REVOKE before GRANT, even where a policy would already block the caller.
--     A policy protects rows; the grant protects the table. Belt and braces —
--     and it means a future table created without a policy fails closed.
--   * `TO authenticated`, never `TO public`. `anon` has no business here at all.
--
-- What is *not* granted is as load-bearing as what is:
--
--   * No DELETE, on any table, to any client role. Deleting a habit is
--     `deleted_at`, undoing a completion is a row in `completion_retractions`,
--     and erasing an account is the `delete-account` edge function running as
--     service_role. Without this, a device that has not yet heard about a row
--     could delete it and a second device could re-push it — sync stops being
--     a union the moment rows can go backwards.
--   * No UPDATE on `completions` or `completion_retractions`. They are
--     append-only event ledgers; an edit to a past event is a different event.
--
-- Idempotent and re-runnable: DROP POLICY IF EXISTS before every CREATE.
-- (The DO $$ ... EXECUTE 'DROP POLICY' ... $$ dance the older projects use
-- predates DROP POLICY IF EXISTS and buys nothing over it.)

-- ── profiles ────────────────────────────────────────────────────────────────

alter table public.profiles enable row level security;

revoke all on public.profiles from anon, authenticated;
grant select, insert, update on public.profiles to authenticated;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select to authenticated
  using ((select auth.uid()) = id);

-- The handle_new_user trigger normally creates this row; the insert policy is
-- what lets a client heal a missing one rather than being permanently
-- profile-less if that trigger was ever not there.
drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
  for insert to authenticated
  with check ((select auth.uid()) = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- ── habits ──────────────────────────────────────────────────────────────────

alter table public.habits enable row level security;

revoke all on public.habits from anon, authenticated;
grant select, insert, update on public.habits to authenticated;

drop policy if exists "habits_select_own" on public.habits;
create policy "habits_select_own" on public.habits
  for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "habits_insert_own" on public.habits;
create policy "habits_insert_own" on public.habits
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

-- The WITH CHECK repeats the USING clause so a row cannot be updated *out of*
-- ownership: without it, "set user_id = <someone else>" passes.
drop policy if exists "habits_update_own" on public.habits;
create policy "habits_update_own" on public.habits
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- ── completions (append-only) ───────────────────────────────────────────────

alter table public.completions enable row level security;

revoke all on public.completions from anon, authenticated;
grant select, insert on public.completions to authenticated;

drop policy if exists "completions_select_own" on public.completions;
create policy "completions_select_own" on public.completions
  for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "completions_insert_own" on public.completions;
create policy "completions_insert_own" on public.completions
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

-- ── completion_retractions (append-only) ────────────────────────────────────

alter table public.completion_retractions enable row level security;

revoke all on public.completion_retractions from anon, authenticated;
grant select, insert on public.completion_retractions to authenticated;

drop policy if exists "completion_retractions_select_own" on public.completion_retractions;
create policy "completion_retractions_select_own" on public.completion_retractions
  for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "completion_retractions_insert_own" on public.completion_retractions;
create policy "completion_retractions_insert_own" on public.completion_retractions
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

-- ── reflections ─────────────────────────────────────────────────────────────

alter table public.reflections enable row level security;

revoke all on public.reflections from anon, authenticated;
grant select, insert, update on public.reflections to authenticated;

drop policy if exists "reflections_select_own" on public.reflections;
create policy "reflections_select_own" on public.reflections
  for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "reflections_insert_own" on public.reflections;
create policy "reflections_insert_own" on public.reflections
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "reflections_update_own" on public.reflections;
create policy "reflections_update_own" on public.reflections
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- ── nudges ──────────────────────────────────────────────────────────────────

alter table public.nudges enable row level security;

revoke all on public.nudges from anon, authenticated;
grant select, insert, update on public.nudges to authenticated;

drop policy if exists "nudges_select_own" on public.nudges;
create policy "nudges_select_own" on public.nudges
  for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "nudges_insert_own" on public.nudges;
create policy "nudges_insert_own" on public.nudges
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "nudges_update_own" on public.nudges;
create policy "nudges_update_own" on public.nudges
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- ── habit_pauses ────────────────────────────────────────────────────────────

alter table public.habit_pauses enable row level security;

revoke all on public.habit_pauses from anon, authenticated;
grant select, insert, update on public.habit_pauses to authenticated;

drop policy if exists "habit_pauses_select_own" on public.habit_pauses;
create policy "habit_pauses_select_own" on public.habit_pauses
  for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "habit_pauses_insert_own" on public.habit_pauses;
create policy "habit_pauses_insert_own" on public.habit_pauses
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "habit_pauses_update_own" on public.habit_pauses;
create policy "habit_pauses_update_own" on public.habit_pauses
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
