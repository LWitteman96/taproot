-- Last-write-wins, enforced rather than relied upon.
--
-- The sync drain pulls before it pushes precisely so that a row which has
-- already lost the `updated_at` comparison is replaced locally and taken off
-- the queue before any push can send it. That ordering is correct and tested,
-- and it is also a convention: nothing here stopped a caller upserting a stale
-- row, because a PostgREST upsert is unconditional and takes whatever it is
-- last sent.
--
-- The failure that buys is the worst class there is. A device holding a stale
-- edit overwrites a newer one made on another device, both devices then agree
-- on the stale value, and nothing anywhere records that an edit was lost. No
-- error, no conflict, no way to notice after the fact. "The only caller does it
-- in the right order" is true exactly until a second caller exists — a later
-- app version, an edge function, a support script run at three in the morning.
--
-- So the rule moves into the database, where a caller cannot forget it.
--
-- WHERE THIS APPLIES, and why it is not simply every table:
--
--   * habits, reflections, habit_pauses — yes. Whole-row last-write-wins on
--     `updated_at` is genuinely the reconciliation rule for these, and it is
--     what `LocalSyncStore.applyPulled` implements on the device.
--
--   * nudges — deliberately NOT, but see merge_nudge_flags() in
--     20260916090000_merge_nudge_flags.sql, which is what makes the exemption
--     safe rather than merely stated. Its cross-device story is not
--     last-write-wins: two devices can hold rows for the same expected occasion
--     and a strict `updated_at` gate would reject a legitimate flag write from
--     whichever device did not create the row. The OR that justifies the
--     exemption has to actually exist for same-id rows, and until that
--     migration it did not — collapseDuplicateOccasions() merges *different*
--     ids for one occasion, which is a different problem.
--
--   * completions, completion_retractions — nothing to apply. They are
--     append-only event ledgers with no `updated_at` and no UPDATE grant: a
--     replay is ignored on its key, so there is no stale write to reject.
--
-- Equal timestamps pass. An idempotent replay of a row the server already has
-- is not an anomaly, it is what sync does all day: the overlap window re-reads
-- ground it has covered, and a retried push resends a batch verbatim. Only a
-- strictly older `updated_at` is rejected.
--
-- A device with a clock running behind will find its edits rejected. That is
-- not a new failure this introduces — such a device already loses every
-- last-write-wins comparison it takes part in. The difference is that it now
-- loses loudly, at the write, instead of silently on the next pull.

create or replace function public.reject_stale_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- Strictly older only. See the note on equality above.
  if new.updated_at < old.updated_at then
    raise exception
      'stale write to %.%: updated_at % is older than the stored %',
      tg_table_schema, tg_table_name, new.updated_at, old.updated_at
      using errcode = 'PT409',
            -- Machine-readable, because the caller's two recoveries are
            -- different and PT409 cannot tell them apart on its own: PostgREST
            -- reads the three digits after `PT` as the HTTP status, so every
            -- 409 this schema raises must share the SQLSTATE. See
            -- `staleUpdateDetail` in remote_sync_store.dart.
            detail = 'sync_conflict=stale_update',
            hint = 'Pull before pushing. This row has been changed more '
                   'recently somewhere else, and that version wins.';
  end if;
  return new;
end;
$$;

comment on function public.reject_stale_update() is
  'Rejects an update whose client-clock updated_at is older than the stored '
  'row. Makes last-write-wins a property of the database rather than a '
  'convention the caller is trusted to follow, because the failure it guards '
  'against — a stale push overwriting a newer edit from another device — is '
  'silent on both devices.';

drop trigger if exists reject_stale_update on public.habits;
create trigger reject_stale_update before update on public.habits
  for each row execute function public.reject_stale_update();

drop trigger if exists reject_stale_update on public.reflections;
create trigger reject_stale_update before update on public.reflections
  for each row execute function public.reject_stale_update();

drop trigger if exists reject_stale_update on public.habit_pauses;
create trigger reject_stale_update before update on public.habit_pauses
  for each row execute function public.reject_stale_update();
