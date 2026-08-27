#!/usr/bin/env bash
#
# setup-environment-protection.sh - Configure GitHub Environment deployment protection.
#
# Enables required reviewers (DevOps team/users) before workflow jobs tied to an
# environment can run. Anyone with write access can still *start* a workflow, but
# jobs referencing a protected environment pause until a reviewer approves.
#
# Usage:
#   setup-environment-protection.sh --env qajava11 --config .github/config/environment-protection.json
#
# Config JSON fields:
#   reviewer_teams      array of GitHub team slugs (org teams)
#   reviewer_users      array of GitHub usernames
#   deployment_branches array of branch names allowed to deploy (empty = all branches)
#   prevent_self_review boolean (default false)
#   wait_timer_minutes  number (default 0)

set -euo pipefail

REPO="${REPO:-}"
ENV_NAME="${ENV_NAME:-}"
CONFIG_FILE="${CONFIG_FILE:-}"
DRY_RUN="${DRY_RUN:-false}"

usage() {
  cat <<'EOF'
Usage: setup-environment-protection.sh --env <name> [options]

Required:
  --env <name>              GitHub environment name (same as deployment branch)

Optional:
  --repo <owner/repo>       Target repo (default: gh repo view)
  --config <path>           JSON config (default: .github/config/environment-protection.json)
  --reviewer-teams <list>   Comma-separated team slugs (overrides config)
  --reviewer-users <list>   Comma-separated GitHub usernames (overrides config)
  --deployment-branches <list>  Comma-separated branch names (overrides config)
  --dry-run                 Print actions without calling GitHub API
  -h, --help

Requires: gh (authenticated with admin:repo or manage_runners:enterprise + repo admin)
EOF
}

err() { echo "[env-protection][ERROR] $*" >&2; }
log() { echo "[env-protection] $*" >&2; }
die() { err "$*"; exit 1; }

require_arg() {
  local flag="$1"
  [[ $# -ge 2 && -n "${2:-}" && "$2" != --* ]] || die "$flag requires a value"
}

REVIEWER_TEAMS_CSV=""
REVIEWER_USERS_CSV=""
DEPLOYMENT_BRANCHES_CSV=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)                 require_arg --env "${2-}"; ENV_NAME="$2"; shift 2 ;;
    --repo)                require_arg --repo "${2-}"; REPO="$2"; shift 2 ;;
    --config)              require_arg --config "${2-}"; CONFIG_FILE="$2"; shift 2 ;;
    --reviewer-teams)      require_arg --reviewer-teams "${2-}"; REVIEWER_TEAMS_CSV="$2"; shift 2 ;;
    --reviewer-users)      require_arg --reviewer-users "${2-}"; REVIEWER_USERS_CSV="$2"; shift 2 ;;
    --deployment-branches) require_arg --deployment-branches "${2-}"; DEPLOYMENT_BRANCHES_CSV="$2"; shift 2 ;;
    --dry-run)             DRY_RUN="true"; shift ;;
    -h|--help)             usage; exit 0 ;;
    *)                     die "Unknown argument: $1" ;;
  esac
done

[[ -n "$ENV_NAME" ]] || die "--env is required"
command -v gh >/dev/null 2>&1 || die "gh CLI is required"
command -v jq >/dev/null 2>&1 || die "jq is required"

if [[ -z "$REPO" ]]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
  [[ -n "$REPO" ]] || die "Could not infer repo; pass --repo owner/repo"
fi

OWNER="${REPO%%/*}"

if [[ -z "$CONFIG_FILE" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  CONFIG_FILE="${SCRIPT_DIR%/scripts}/config/environment-protection.json"
fi

PREVENT_SELF_REVIEW="false"
WAIT_TIMER=0

if [[ -f "$CONFIG_FILE" ]]; then
  mapfile -t TEAMS_FROM_CFG < <(jq -r '.reviewer_teams[]? // empty' "$CONFIG_FILE")
  mapfile -t USERS_FROM_CFG < <(jq -r '.reviewer_users[]? // empty' "$CONFIG_FILE")
  mapfile -t BRANCHES_FROM_CFG < <(jq -r '.deployment_branches[]? // empty' "$CONFIG_FILE")
  PREVENT_SELF_REVIEW="$(jq -r '.prevent_self_review // false' "$CONFIG_FILE")"
  WAIT_TIMER="$(jq -r '.wait_timer_minutes // 0' "$CONFIG_FILE")"
fi

if [[ -n "$REVIEWER_TEAMS_CSV" ]]; then
  IFS=',' read -r -a TEAMS_FROM_CFG <<<"$REVIEWER_TEAMS_CSV"
fi
if [[ -n "$REVIEWER_USERS_CSV" ]]; then
  IFS=',' read -r -a USERS_FROM_CFG <<<"$REVIEWER_USERS_CSV"
fi
if [[ -n "$DEPLOYMENT_BRANCHES_CSV" ]]; then
  IFS=',' read -r -a BRANCHES_FROM_CFG <<<"$DEPLOYMENT_BRANCHES_CSV"
fi

REVIEWERS_JSON='[]'

for team in "${TEAMS_FROM_CFG[@]:-}"; do
  team="${team// /}"
  [[ -n "$team" ]] || continue
  TEAM_ID="$(gh api "orgs/${OWNER}/teams/${team}" --jq .id 2>/dev/null || true)"
  [[ -n "$TEAM_ID" ]] || die "Could not resolve team slug '$team' in org '$OWNER'"
  REVIEWERS_JSON="$(jq -c --argjson id "$TEAM_ID" '. + [{"type":"Team","id":$id}]' <<<"$REVIEWERS_JSON")"
  log "Reviewer team: $team (id=$TEAM_ID)"
done

for user in "${USERS_FROM_CFG[@]:-}"; do
  user="${user// /}"
  [[ -n "$user" ]] || continue
  USER_ID="$(gh api "users/${user}" --jq .id 2>/dev/null || true)"
  [[ -n "$USER_ID" ]] || die "Could not resolve GitHub user '$user'"
  REVIEWERS_JSON="$(jq -c --argjson id "$USER_ID" '. + [{"type":"User","id":$id}]' <<<"$REVIEWERS_JSON")"
  log "Reviewer user: $user (id=$USER_ID)"
done

REVIEWER_COUNT="$(jq 'length' <<<"$REVIEWERS_JSON")"
[[ "$REVIEWER_COUNT" -gt 0 ]] || die "At least one reviewer team or user is required"

ENV_ENC="$(printf '%s' "$ENV_NAME" | jq -sRr @uri)"
API_BASE="repos/${REPO}/environments/${ENV_ENC}"

BODY="$(jq -n \
  --argjson reviewers "$REVIEWERS_JSON" \
  --argjson wait_timer "$WAIT_TIMER" \
  --argjson prevent_self_review "$PREVENT_SELF_REVIEW" \
  '{
    reviewers: $reviewers,
    wait_timer: $wait_timer,
    prevent_self_review: $prevent_self_review,
    deployment_branch_policy: {
      protected_branches: false,
      custom_branch_policies: true
    }
  }')"

if [[ "$DRY_RUN" == "true" ]]; then
  log "DRY RUN - would PUT $API_BASE with:"
  jq . <<<"$BODY"
  log "DRY RUN - would set deployment branch policies: ${BRANCHES_FROM_CFG[*]:-<all branches>}"
  exit 0
fi

log "Creating/updating environment '$ENV_NAME' protection in $REPO ..."
gh api --method PUT -H "Accept: application/vnd.github+json" "$API_BASE" --input - <<<"$BODY" >/dev/null

# Replace branch policies when a list is provided; otherwise allow all branches.
EXISTING_POLICIES="$(gh api "$API_BASE/deployment-branch-policies" --jq '.branch_policies[].id' 2>/dev/null || true)"
if [[ -n "$EXISTING_POLICIES" ]]; then
  while read -r policy_id; do
    [[ -n "$policy_id" ]] || continue
    gh api --method DELETE "$API_BASE/deployment-branch-policies/${policy_id}" >/dev/null 2>&1 || true
  done <<<"$EXISTING_POLICIES"
fi

if [[ ${#BRANCHES_FROM_CFG[@]} -gt 0 ]]; then
  for branch in "${BRANCHES_FROM_CFG[@]}"; do
    branch="${branch// /}"
    [[ -n "$branch" ]] || continue
    gh api --method POST "$API_BASE/deployment-branch-policies" \
      -f name="$branch" >/dev/null
    log "Allowed deployment branch: $branch"
  done
else
  log "No deployment_branches configured — all branches may target environment '$ENV_NAME' (reviewers still required)."
fi

log "Environment '$ENV_NAME' is protected with $REVIEWER_COUNT required reviewer(s)."
