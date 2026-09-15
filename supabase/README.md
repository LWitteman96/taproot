# supabase/

The backend. Hand-written SQL, no ORM and no schema diffing — the same rule the
Dart side follows about code generation, for the same reason.

Read [`../lib/app/database/app_database.dart`](../lib/app/database/app_database.dart)
first. **SQLite on the device is the primary store**; this is the durable backup
and the cross-device sync target. The shapes here are that file's shapes, and
the header comment in `migrations/20260909090000_initial_schema.sql` says which
of them are load-bearing and why.

```
config.toml     local + remote configuration, pushed with scripts/supabase-push.sh
migrations/     timestamped, hand-written, idempotent SQL
functions/      Deno edge functions (one: delete-account)
tests/          pgTAP — schema invariants and RLS, run with `supabase test db`
seed.sql        deliberately empty; see the file
```

## Running it locally

**Taproot uses the 5433x port block, not the CLI defaults**, so it can run
alongside another local Supabase project without either having to be stopped.

```bash
supabase start          # API http://127.0.0.1:54331 · Studio http://127.0.0.1:54333
supabase stop           # add --no-backup to discard local data
supabase db reset       # re-apply every migration from scratch, then seed.sql
supabase test db        # pgTAP suite
supabase status         # URLs and local keys
```

Local mail — magic links, OTPs — is caught at <http://127.0.0.1:54334>; nothing
is actually sent.

## Verifying it

```bash
scripts/supabase-verify.sh
```

Reset from migrations → re-apply every migration a second time → pgTAP →
delete an account through the edge function. The second application is the point
of the script: migrations here must be **idempotent and re-runnable**, because
the same file has to land cleanly on local, staging and production at different
points in their history, and that rule fails silently until the environment you
least want it to fail on. CI (`.github/workflows/supabase.yml`) runs the same
script on every change under `supabase/`.

## Pushing to staging or production

```bash
scripts/supabase-push.sh stg
scripts/supabase-push.sh prod    # requires typing "production"
```

**Neither project exists yet.** The script fails loudly on the empty project
refs at the top of it rather than linking to nothing; fill them in from
`supabase projects list` when the projects are created.

## What is deliberately not here

| Not here | Why |
|---|---|
| Realtime | The device's store is primary and sync drains `pending_sync` one way. A subscription would be a second, unordered path into the same rows. |
| Storage | Plant art ships in the app bundle. `delete-account` keeps the purge step commented in place for the day a bucket exists. |
| A remote project | Nothing is provisioned. `.env.dev` points at the local stack; `.env.stg` / `.env.prod` are placeholders. |
| SMTP | No provider chosen. Local mail goes to the catcher above; staging and production will send nothing until `[auth.email.smtp]` in `config.toml` is filled in and pushed. |
| Apple / Google sign-in | Wired in `config.toml` and disabled — the credentials do not exist yet. Enabling a provider and adding its secret to `.secrets/` is one commit, not two. |
| Any stored engine value | Stage, vitality, roots and autonomy are derivations. Storing them would make tuning a constant a data migration. |
