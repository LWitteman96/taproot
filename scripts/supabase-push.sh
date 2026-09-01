#!/usr/bin/env bash
# scripts/supabase-push.sh
#
# Safely push Supabase config and secrets to a remote environment.
#
# WHY this script exists:
#   config.toml uses env() references (e.g. SUPABASE_AUTH_EXTERNAL_APPLE_SECRET).
#   Pushing config to the wrong environment with the wrong secrets would silently
#   break auth on that environment. This script makes the target explicit,
#   requires confirmation for production, and always restores .env to dev
#   afterwards so prod secrets are never left as the active local environment.
#
# Usage:
#   bash scripts/supabase-push.sh stg
#   bash scripts/supabase-push.sh prod
set -euo pipefail

# ── Project refs ────────────────────────────────────────────────────────────
# NOT YET PROVISIONED. Fill these in once the staging and production Supabase
# projects exist; find them with `supabase projects list`. The guard below fails
# loudly rather than letting the script link to an empty ref.
STAGING_PROJECT_REF=""
PRODUCTION_PROJECT_REF=""

# ── Helpers ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${GREEN}[info]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[warn]${RESET} $*"; }
error()   { echo -e "${RED}[error]${RESET} $*" >&2; }
heading() { echo -e "\n${BOLD}$*${RESET}"; }

restore_dev_env() {
  if [[ -f ".env.dev" ]]; then
    cp .env.dev .env
    info ".env restored to dev"
  fi
}

# Always restore .env to dev on exit, success or failure.
trap restore_dev_env EXIT

# ── Argument validation ──────────────────────────────────────────────────────
if [[ $# -ne 1 ]] || [[ "$1" != "stg" && "$1" != "prod" ]]; then
  error "Usage: bash scripts/supabase-push.sh <stg|prod>"
  echo ""
  echo "  stg   Push config and secrets to the staging environment"
  echo "  prod  Push config and secrets to the production environment"
  echo ""
  echo "Dev (local Docker) is managed via supabase start — this script does not touch it."
  exit 1
fi

ENV="$1"

case "$ENV" in
  stg)
    ENV_LABEL="STAGING"
    ENV_FILE=".env.stg"
    PROJECT_REF="$STAGING_PROJECT_REF"
    ;;
  prod)
    ENV_LABEL="PRODUCTION"
    ENV_FILE=".env.prod"
    PROJECT_REF="$PRODUCTION_PROJECT_REF"
    ;;
esac

# ── Pre-flight checks ────────────────────────────────────────────────────────
if [[ -z "$PROJECT_REF" ]]; then
  error "No project ref configured for $ENV_LABEL."
  error "Create the Supabase project, then set the ref at the top of this script."
  error "Find it with: supabase projects list"
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  error "Environment file '$ENV_FILE' not found."
  exit 1
fi

if ! command -v supabase &>/dev/null; then
  error "Supabase CLI not found. Install it: https://supabase.com/docs/guides/cli"
  exit 1
fi

# ── Banner ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║           supabase-push — Taproot                ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  Target environment : ${BOLD}${ENV_LABEL}${RESET}"
echo -e "  Project ref        : ${BOLD}${PROJECT_REF}${RESET}"
echo -e "  Secrets source     : ${BOLD}${ENV_FILE}${RESET}"
echo ""

# ── Production confirmation ──────────────────────────────────────────────────
if [[ "$ENV" == "prod" ]]; then
  warn "You are about to push config and secrets to PRODUCTION."
  warn "This will immediately affect all production users."
  echo ""
  echo -n "  Type \"production\" to confirm: "
  read -r CONFIRM
  echo ""
  if [[ "$CONFIRM" != "production" ]]; then
    error "Confirmation failed. Aborting."
    exit 1
  fi
fi

# ── Step 1: make config.toml env() references resolve ────────────────────────
heading "Step 1/3 — Loading $ENV_FILE as active .env"
cp "$ENV_FILE" .env
info "Copied $ENV_FILE → .env"

# ── Step 2: link the CLI to the target project ───────────────────────────────
heading "Step 2/3 — Linking Supabase CLI to $ENV_LABEL ($PROJECT_REF)"
supabase link --project-ref "$PROJECT_REF"
info "Linked to $PROJECT_REF"

# ── Step 3a: push secrets ────────────────────────────────────────────────────
heading "Step 3/3a — Pushing secrets from $ENV_FILE"
supabase secrets set --env-file "$ENV_FILE"
info "Secrets pushed"

# ── Step 3b: push config ─────────────────────────────────────────────────────
heading "Step 3/3b — Pushing config.toml to $ENV_LABEL"
# NOTE: `supabase config push` is interactive — it shows a diff and asks for
# confirmation, and it exits 0 even when you decline. Success therefore cannot
# be inferred from its exit code, so this script does not claim the config was
# applied.
supabase config push
info "config push step complete — review the CLI output above to confirm what was applied"

echo ""
echo -e "${GREEN}${BOLD}✓ Done.${RESET} Secrets pushed and config push step complete for ${ENV_LABEL} (${PROJECT_REF})."
warn "'supabase config push' is interactive: if you declined its prompt, the config was NOT updated — verify in the dashboard."
echo ""
# .env is restored to .env.dev by the EXIT trap
