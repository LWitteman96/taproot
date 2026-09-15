#!/usr/bin/env bash
# scripts/supabase-verify.sh
#
# The backend's equivalent of the three gates. Resets the local database from
# the migrations, re-applies every migration a second time, runs the pgTAP
# suite against the result, and deletes an account through the edge function.
#
# WHY the second application: the house rule is that migrations are idempotent
# and re-runnable, which is what lets the same file land cleanly on local,
# staging and production at different points in their history. That rule is
# free to write and easy to break — `create table` without `if not exists`,
# `create policy` without a preceding drop — and it only fails much later, on
# the environment you least want it to fail on. So it is checked here, and in
# CI, on every change.
#
# Usage:
#   scripts/supabase-verify.sh            # reset, re-apply, test
#   scripts/supabase-verify.sh --no-reset # skip the reset (faster; assumes a
#                                         # database already at head)
set -euo pipefail

cd "$(dirname "$0")/.."

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${GREEN}[info]${RESET} $*"; }
error()   { echo -e "${RED}[error]${RESET} $*" >&2; }
heading() { echo -e "\n${BOLD}$*${RESET}"; }

RESET_DB=1
if [[ "${1:-}" == "--no-reset" ]]; then
  RESET_DB=0
elif [[ $# -gt 0 ]]; then
  error "Usage: scripts/supabase-verify.sh [--no-reset]"
  exit 1
fi

# An explicit template, not `mktemp -t taproot-verify`: BSD mktemp appends
# the random suffix itself, GNU mktemp rejects a template without XXXXXX.
TMP_SQL="$(mktemp "${TMPDIR:-/tmp}/taproot-verify.XXXXXX")"
trap 'rm -f "$TMP_SQL"' EXIT

if ! command -v supabase &>/dev/null; then
  error "Supabase CLI not found. Install it: https://supabase.com/docs/guides/cli"
  exit 1
fi

# Preflighted like the CLI above rather than discovered in step 4, which is
# several minutes of green output later. jq is preinstalled on GitHub runners.
if ! command -v jq &>/dev/null; then
  error "jq not found. Install it: https://jqlang.github.io/jq/download/"
  exit 1
fi

if ! supabase status &>/dev/null; then
  error "The local stack is not running. Start it with: supabase start"
  exit 1
fi

# Read the local stack's URLs and keys once. `supabase status` also prints
# service and CLI-update chatter, so it is filtered to KEY=VALUE lines rather
# than eval'd wholesale.
STATUS_ENV="$(supabase status -o env 2>/dev/null | grep -E '^[A-Z_]+=' || true)"
status_value() { printf '%s\n' "$STATUS_ENV" | sed -n "s/^$1=\"\{0,1\}\([^\"]*\)\"\{0,1\}$/\\1/p"; }

DB_URL="$(status_value DB_URL)"
API_URL="$(status_value API_URL)"
ANON_KEY="$(status_value ANON_KEY)"
SERVICE_ROLE_KEY="$(status_value SERVICE_ROLE_KEY)"

# Prefer a psql on PATH; fall back to the one inside the database container so
# this works on a machine with no libpq installed.
if command -v psql &>/dev/null && [[ -n "$DB_URL" ]]; then
  run_sql() { psql "$DB_URL" -v ON_ERROR_STOP=1 --quiet --no-psqlrc -f "$1" >/dev/null; }
else
  run_sql() {
    docker exec -i supabase_db_taproot \
      psql -U postgres -d postgres -v ON_ERROR_STOP=1 --quiet --no-psqlrc \
      < "$1" >/dev/null
  }
fi

if [[ "$RESET_DB" == "1" ]]; then
  heading "Step 1/5 — Resetting the local database from migrations"
  supabase db reset
  info "Migrations applied from scratch"
else
  heading "Step 1/5 — Skipped (--no-reset)"
fi

heading "Step 2/5 — Re-applying every migration, to prove it is re-runnable"
for migration in supabase/migrations/*.sql; do
  if run_sql "$migration"; then
    info "re-applied $(basename "$migration")"
  else
    error "$(basename "$migration") is not re-runnable — see the error above."
    error "Migrations must be idempotent: create ... if not exists, drop policy"
    error "if exists before create policy, create or replace function."
    exit 1
  fi
done

heading "Step 3/5 — pgTAP suite"
supabase test db

# ── Step 4: the one thing pgTAP cannot reach ────────────────────────────────
# delete-account is the App Store Review Guideline 5.1.1(v) requirement, and
# the thing it has to get right — resolve the caller from the JWT, never the
# request body — only exists above the database. So it is exercised the way the
# app will: sign up, plant a row, POST with the session token, and check that
# the cascade took everything with it.
heading "Step 4/5 — delete-account, end to end"

# jq rather than a python3 one-liner, for two reasons that both bit. Under
# `set -euo pipefail` a JSONDecodeError on a non-JSON body — Kong answering 502
# in HTML while the stack warms up, or an empty response — killed the whole
# script with a traceback, so the `error "Response was:"` diagnostics written
# below for exactly that case were unreachable. And python3 was the one
# dependency never preflighted. `// empty` makes a missing key an empty string
# rather than the literal "null", which is what the `-z` checks below expect.
#
# The `|| true` matters as much as the tool does: jq exits non-zero on a parse
# error, and under `set -e` a failing command substitution in an assignment
# aborts the script just as the traceback did. Swallowing it leaves an empty
# value, so the `-z` checks fire and print the body that could not be parsed —
# which is the diagnostic worth having.
json_field() { jq -r "(.$1 // .user.$1) // empty" 2>/dev/null || true; }

# The user is created through the admin API rather than /signup, because email
# confirmations are on (see config.toml) and /signup therefore returns no
# session — the confirmation link would have to be fished out of the local mail
# catcher first. This is a test fixture, not the app's path; what is under test
# is what happens *after* a session exists.
EMAIL="verify-$(date +%s)@example.com"
PASSWORD="correct-horse-battery"

CREATED="$(curl -sS -X POST "$API_URL/auth/v1/admin/users" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"email_confirm\":true}")"
ACCOUNT="$(printf '%s' "$CREATED" | json_field id)"

SESSION="$(curl -sS -X POST "$API_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")"
TOKEN="$(printf '%s' "$SESSION" | json_field access_token)"

if [[ -z "$ACCOUNT" ]]; then
  error "Could not create the test user. Response was:"
  error "$CREATED"
  exit 1
fi
if [[ -z "$TOKEN" ]]; then
  error "Sign-in did not return a session. Response was:"
  error "$SESSION"
  exit 1
fi

cat >"$TMP_SQL" <<SQL
insert into public.habits
  (id, user_id, name, plant_type, target_frequency, created_at, updated_at)
values (gen_random_uuid(), '$ACCOUNT', 'Verify', 'fern', 3, now(), now());
SQL
run_sql "$TMP_SQL"

STATUS="$(curl -sS -o /dev/null -w '%{http_code}' -X POST \
  "$API_URL/functions/v1/delete-account" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $TOKEN")"

if [[ "$STATUS" != "200" ]]; then
  error "delete-account returned $STATUS, expected 200"
  exit 1
fi
info "delete-account returned 200"

cat >"$TMP_SQL" <<SQL
do \$\$
declare
  remaining int;
begin
  select (select count(*) from auth.users where id = '$ACCOUNT')
       + (select count(*) from public.profiles where id = '$ACCOUNT')
       + (select count(*) from public.habits where user_id = '$ACCOUNT')
    into remaining;
  if remaining <> 0 then
    raise exception 'delete-account left % rows behind for %', remaining, '$ACCOUNT';
  end if;
end
\$\$;
SQL
run_sql "$TMP_SQL"
info "the auth user, its profile and its habits are gone"

# The same token again, now that the user behind it is gone. It is still
# well-formed and unexpired, so the gateway's verify_jwt lets it through and
# the function's own getUser() is what rejects it — which is the only way to
# reach that branch from outside, and the branch that has to answer 401 rather
# than the 503 reserved for "we could not check". auth-js hands transient
# failures back in the result rather than throwing, so the two live one `if`
# apart and a refactor can swap them without anything else noticing.
ORPHAN_STATUS="$(curl -sS -o /dev/null -w '%{http_code}' -X POST \
  "$API_URL/functions/v1/delete-account" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $TOKEN")"

if [[ "$ORPHAN_STATUS" != "401" ]]; then
  error "a token whose user is gone returned $ORPHAN_STATUS, expected 401"
  error "503 there would mean the transient-failure branch is swallowing a "
  error "genuinely invalid session; 500 means it threw."
  exit 1
fi
info "a token whose user no longer exists is 401, not 503"

# ── Step 5: the grant the sync push depends on ──────────────────────────────
# The device pushes with two different conflict resolutions, and which one goes
# where is a *permission* rather than a preference. A merging upsert is
# `ON CONFLICT DO UPDATE`, so PostgREST asks for the UPDATE privilege — and the
# append-only ledgers deliberately have none, because an edit to a past event is
# a different event. Send `merge-duplicates` at `completions` and every
# completion the device has ever recorded is a flat 403.
#
# pgTAP pins the grants themselves; this pins what PostgREST *does* with them,
# which is the half a Dart test against a fake cannot see. It was a real bug,
# found by probing the running stack rather than by reasoning about it.
heading "Step 5/5 — the conflict resolutions the sync push relies on"

SYNC_EMAIL="verify-sync-$(date +%s)@example.com"
SYNC_USER="$(curl -sS -X POST "$API_URL/auth/v1/admin/users" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$SYNC_EMAIL\",\"password\":\"$PASSWORD\",\"email_confirm\":true}" \
  | json_field id)"
SYNC_TOKEN="$(curl -sS -X POST "$API_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
  -d "{\"email\":\"$SYNC_EMAIL\",\"password\":\"$PASSWORD\"}" | json_field access_token)"

if [[ -z "$SYNC_USER" || -z "$SYNC_TOKEN" ]]; then
  error "Could not create the sync test user."
  exit 1
fi

HABIT_ID="aaaaaaaa-9999-9999-9999-999999999999"
COMPLETION_ID="cccccccc-9999-9999-9999-999999999999"

rest_post() {
  curl -sS -o /dev/null -w '%{http_code}' -X POST "$API_URL/rest/v1/$1" \
    -H "apikey: $ANON_KEY" -H "Authorization: Bearer $SYNC_TOKEN" \
    -H "Content-Type: application/json" -H "Prefer: $3" -d "$2"
}

HABIT_ROW="{\"id\":\"$HABIT_ID\",\"user_id\":\"$SYNC_USER\",\"name\":\"Verify\",\"plant_type\":\"fern\",\"target_frequency\":3,\"journey\":\"design\",\"designed_cue\":\"kettle\",\"designed_cue_type\":\"event\",\"created_at\":\"2026-03-01T00:00:00Z\",\"updated_at\":\"2026-03-05T00:00:00Z\"}"
# was_nudged as an integer on purpose: SQLite has no boolean type, so this is
# the shape the device's rows actually arrive in.
COMPLETION_ROW="{\"habit_id\":\"$HABIT_ID\",\"id\":\"$COMPLETION_ID\",\"user_id\":\"$SYNC_USER\",\"completed_at\":\"2026-03-05T09:00:00Z\",\"was_nudged\":0,\"source\":\"tap\"}"

STATUS="$(rest_post "habits?on_conflict=id" "$HABIT_ROW" 'resolution=merge-duplicates')"
[[ "$STATUS" == "201" ]] || { error "a mutable table rejected a merging upsert: $STATUS"; exit 1; }
STATUS="$(rest_post "habits?on_conflict=id" "$HABIT_ROW" 'resolution=merge-duplicates')"
[[ "$STATUS" == "200" ]] || { error "re-upserting a habit was not idempotent: $STATUS"; exit 1; }
info "a mutable table takes a merging upsert, twice"

STATUS="$(rest_post "completions?on_conflict=habit_id,id" "$COMPLETION_ROW" 'resolution=merge-duplicates')"
[[ "$STATUS" == "403" ]] || {
  error "an append-only ledger accepted a merging upsert ($STATUS), which it"
  error "should not: that needs UPDATE, and these tables grant none. If this"
  error "changed deliberately, RemoteSyncStore.push can stop special-casing"
  error "them — but it must not keep relying on a grant that moved."
  exit 1
}
info "an append-only ledger refuses a merging upsert — it grants no UPDATE"

STATUS="$(rest_post "completions?on_conflict=habit_id,id" "$COMPLETION_ROW" 'resolution=ignore-duplicates')"
[[ "$STATUS" == "201" ]] || { error "an append-only insert was refused: $STATUS"; exit 1; }
STATUS="$(rest_post "completions?on_conflict=habit_id,id" "$COMPLETION_ROW" 'resolution=ignore-duplicates')"
[[ "$STATUS" == "201" ]] || { error "replaying an event was not accepted: $STATUS"; exit 1; }

STORED="$(curl -sS "$API_URL/rest/v1/completions?select=was_nudged&habit_id=eq.$HABIT_ID" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $SYNC_TOKEN" | jq -r 'length')"
[[ "$STORED" == "1" ]] || { error "a replayed event was stored twice ($STORED rows)"; exit 1; }
info "and takes an ignoring one, where a replay is a union rather than a row"

echo ""
echo -e "${GREEN}${BOLD}✓ Backend green.${RESET} Migrations apply from scratch, re-apply cleanly, the tests pass, and an account can delete itself."
