-- Two conflicts that both answer PT409, and the OR that the nudge exemption
-- was premised on but never had.
--
-- ── Why the conflicts need naming ───────────────────────────────────────────
--
-- PostgREST reads the three digits after `PT` in a SQLSTATE as the HTTP status
-- to answer with, so every 409 this schema raises has to spell it `PT409`.
-- Two triggers do, and a caller cannot tell them apart from the code alone:
--
--   * reject_stale_update  — "a newer write beat you". The winner is ahead of
--     your pull cursor, so the recovery is to do nothing: the next pull brings
--     it.
--
--   * pin_soft_delete      — "this row is dead". The winner is *behind* the
--     cursor. It was written before the pull, was read by that pull, and lost
--     the `updated_at` comparison on the way in. The next pull brings nothing,
--     because the cursor is already past it.
--
-- Treating the second like the first is how a habit deleted on one device comes
-- back to life on another, permanently: the push is counted as a loser, the row
-- is taken off the queue, and the only row that would have corrected it is
-- already behind the cursor. So `detail` carries a stable token the client
-- matches on. It is a contract with lib/app/sync/remote_sync_store.dart —
-- see `softDeletePinnedDetail` and `staleUpdateDetail` there.
--
-- Only the DETAIL changes here. The condition, the message and the SQLSTATE are
-- all exactly as 20260909090000_initial_schema.sql wrote them.

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
          detail = 'sync_conflict=soft_delete_pinned',
          hint = 'Pull rather than retrying. Undeleting needs a sanctioned '
                 'RPC, not a whole-row push carrying a null deleted_at.';
end;
$$;

comment on function public.pin_soft_delete() is
  'Makes habits.deleted_at one-way and first-write-wins. Clearing a set stamp '
  'raises PT409 rather than being ignored: a blocked write that reports '
  'success is how an undelete looks fixed and then vanishes on the next pull. '
  'Its DETAIL carries sync_conflict=soft_delete_pinned, because the client''s '
  'recovery differs from reject_stale_update''s and the SQLSTATE is shared.';

-- ── The nudge ledger's actual merge rule ────────────────────────────────────
--
-- 20260915100000_pin_last_write_wins.sql exempts `nudges` from
-- reject_stale_update, and gives a reason: its cross-device story is OR'd flags
-- with a read-time collapse, not whole-row last-write-wins. The reason is
-- sound. The problem was that the OR did not exist for the case the trigger
-- would have covered.
--
-- `collapseDuplicateOccasions` merges rows with *different ids* that account
-- for one occasion — two devices that each planned the same evening and each
-- minted a UUID. Nothing merged *two versions of one id*, which is the ordinary
-- case: one row, pushed by two devices that hold different flags for it.
--
-- So the exemption removed the guard without putting the rule in its place, and
-- `nudges` is `isMutable: true`, which means an unconditional
-- `ON CONFLICT DO UPDATE` with nothing to reject it:
--
--   1. Phone A: the user confirms nudge N from the shade. confirmed = 1,
--      updated_at = t2. A pushes; the server holds confirmed = 1.
--   2. Tablet B still holds N from before: confirmed = 0, updated_at = t1 < t2,
--      pending because it marked `sent` when it re-queued the notification.
--   3. B pushes. The server takes confirmed = 0.
--   4. Every device pulls confirmed = 0 back. On A it loses the client-side
--      comparison and is ignored — but A's row is no longer pending, so A never
--      re-pushes the truth. The server stays wrong forever, and a reinstall
--      pulls the user's answer as never given.
--
-- The same path walks `sent` backwards, which is worse than a lost answer:
-- autonomy's denominator is the un-nudged occasions, so an occasion that *was*
-- nudged moving back into it depresses the graduation gate.
--
-- THE INVARIANT: sent, confirmed and declined are monotonic. Once true, never
-- false. Each records that something happened — a notification was queued, an
-- answer was given — and nothing that happened can un-happen. A row arriving
-- with a flag cleared is not a retraction, it is a device that has not heard
-- yet, and this is where that is decided rather than trusted to a caller.
--
-- `declined` and `confirmed` are both kept, deliberately, even though a user
-- cannot both confirm and decline one notification: two devices disagreeing
-- about that is a real event worth keeping both halves of, and the reflection
-- side already treats them as answers-to-a-notification rather than facts about
-- the habit.
--
-- WHY NOT JUST GATE IT with reject_stale_update after all? Because the flag
-- write from the device that did not create the row is legitimate and would be
-- rejected whenever that device's clock lags — and a rejected `sent` is the
-- same corrupted denominator by a different route. Merging keeps the write and
-- keeps the truth. `updated_at` still may not go backwards, so the row's clock
-- stays monotonic for the client-side comparison and the pull cursor, but it is
-- clamped rather than raised as a conflict.

create or replace function public.merge_nudge_flags()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.sent := new.sent or old.sent;
  new.confirmed := new.confirmed or old.confirmed;
  new.declined := new.declined or old.declined;

  -- Clamped, not rejected. A stale writer keeps its flag contribution; what it
  -- does not get is to wind back the timestamp every other device compares
  -- against and pages on.
  new.updated_at := greatest(new.updated_at, old.updated_at);

  return new;
end;
$$;

comment on function public.merge_nudge_flags() is
  'ORs the nudge ledger''s monotonic flags (sent, confirmed, declined) on '
  'update and clamps updated_at forward. This is the rule that makes the '
  'nudges exemption from reject_stale_update safe: the exemption exists '
  'because a flag write from the device that did not create the row is '
  'legitimate, and this is what stops that write also clearing a flag another '
  'device has already set.';

drop trigger if exists merge_nudge_flags on public.nudges;
create trigger merge_nudge_flags before update on public.nudges
  for each row execute function public.merge_nudge_flags();
