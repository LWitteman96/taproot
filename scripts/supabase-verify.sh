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

TMP_SQL="$(mktemp -t taproot-verify)"
trap 'rm -f "$TMP_SQL"' EXIT

if ! command -v supabase &>/dev/null; then
  error "Supabase CLI not found. Install it: https://supabase.com/docs/guides/cli"
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
  heading "Step 1/4 — Resetting the local database from migrations"
  supabase db reset
  info "Migrations applied from scratch"
else
  heading "Step 1/4 — Skipped (--no-reset)"
fi

heading "Step 2/4 — Re-applying every migration, to prove it is re-runnable"
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

heading "Step 3/4 — pgTAP suite"
supabase test db

# ── Step 4: the one thing pgTAP cannot reach ────────────────────────────────
# delete-account is the App Store Review Guideline 5.1.1(v) requirement, and
# the thing it has to get right — resolve the caller from the JWT, never the
# request body — only exists above the database. So it is exercised the way the
# app will: sign up, plant a row, POST with the session token, and check that
# the cascade took everything with it.
heading "Step 4/4 — delete-account, end to end"

json_field() { python3 -c 'import sys, json; d = json.load(sys.stdin); print(d.get(sys.argv[1]) or (d.get("user") or {}).get(sys.argv[1]) or "")' "$1"; }

EMAIL="verify-$(date +%s)@example.com"
SIGNUP="$(curl -sS -X POST "$API_URL/auth/v1/signup" \
  -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"correct-horse-battery\"}")"

TOKEN="$(printf '%s' "$SIGNUP" | json_field access_token)"
ACCOUNT="$(printf '%s' "$SIGNUP" | json_field id)"

if [[ -z "$TOKEN" || -z "$ACCOUNT" ]]; then
  error "Sign-up did not return a session. Response was:"
  error "$SIGNUP"
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

echo ""
echo -e "${GREEN}${BOLD}✓ Backend green.${RESET} Migrations apply from scratch, re-apply cleanly, the tests pass, and an account can delete itself."
