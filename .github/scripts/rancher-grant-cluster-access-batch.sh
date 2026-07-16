#!/usr/bin/env bash
#
# rancher-grant-cluster-access-batch.sh - Apply multiple Rancher cluster RBAC grants.
#
# Grants are read from (first match wins):
#   1. --grants-json '<json array>'
#   2. --grants-file <path>   (default: .github/config/rancher-access-grants.json)
#   3. RANCHER_ACCESS_GRANTS env var (JSON array)
#
# JSON entry fields:
#   group            (required) IdP group name, e.g. DEVOPS
#   role             (required) Rancher role template id, e.g. cluster-owner
#   principal_id     (optional) Full principal id, e.g. keycloak_group://DEVOPS
#   group_auth_prefix (optional) Prefix when building principal id (default: keycloak_group)
#   fix_misbound_user (optional) true/false — repair wrong DEVOPS bindings (default: false)
#
# Example:
#   [
#     {"group":"DEVOPS","role":"cluster-owner","principal_id":"keycloak_group://DEVOPS","fix_misbound_user":true},
#     {"group":"QA","role":"cluster-member","principal_id":"keycloak_group://QA"}
#   ]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GRANT_SCRIPT="${SCRIPT_DIR}/rancher-grant-cluster-access.sh"
GRANTS_FILE="${GRANTS_FILE:-${SCRIPT_DIR%/scripts}/config/rancher-access-grants.json}"
GRANTS_JSON="${GRANTS_JSON:-}"
RANCHER_URL="${RANCHER_URL:-}"
RANCHER_TOKEN="${RANCHER_TOKEN:-}"
CLUSTER_NAME="${CLUSTER_NAME:-}"
CLUSTER_ID="${CLUSTER_ID:-}"
DEFAULT_GROUP_AUTH_PREFIX="${DEFAULT_GROUP_AUTH_PREFIX:-keycloak_group}"

usage() {
  cat <<'EOF'
Usage: rancher-grant-cluster-access-batch.sh --rancher-url <url> --token <token> \
  [--cluster-name <name> | --cluster-id <id>] [options]

Required:
  --rancher-url <url>     Rancher base URL
  --token <token>         Rancher API bearer token

Cluster selector (one required):
  --cluster-name <name>
  --cluster-id <id>

Grant source (one required unless RANCHER_ACCESS_GRANTS is set):
  --grants-json '<json>'  JSON array of grant objects
  --grants-file <path>    Defaults to .github/config/rancher-access-grants.json

Optional:
  --default-group-auth-prefix <prefix>  Default principal prefix (default: keycloak_group)
  -h, --help

Environment:
  RANCHER_ACCESS_GRANTS   JSON array (overrides default file when --grants-* not passed)
EOF
}

err() { echo "[rancher-grant-batch][ERROR] $*" >&2; }
log() { echo "[rancher-grant-batch] $*" >&2; }
die() { err "$*"; exit 1; }

require_arg() {
  local flag="$1"
  [[ $# -ge 2 && -n "${2:-}" && "$2" != --* ]] || die "$flag requires a value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rancher-url)                 require_arg --rancher-url "${2-}"; RANCHER_URL="$2"; shift 2 ;;
    --token)                       require_arg --token "${2-}"; RANCHER_TOKEN="$2"; shift 2 ;;
    --cluster-name)                require_arg --cluster-name "${2-}"; CLUSTER_NAME="$2"; shift 2 ;;
    --cluster-id)                  require_arg --cluster-id "${2-}"; CLUSTER_ID="$2"; shift 2 ;;
    --grants-json)                 require_arg --grants-json "${2-}"; GRANTS_JSON="$2"; shift 2 ;;
    --grants-file)                 require_arg --grants-file "${2-}"; GRANTS_FILE="$2"; shift 2 ;;
    --default-group-auth-prefix)   require_arg --default-group-auth-prefix "${2-}"; DEFAULT_GROUP_AUTH_PREFIX="$2"; shift 2 ;;
    -h|--help)                     usage; exit 0 ;;
    *)                             die "Unknown argument: $1" ;;
  esac
done

[[ -x "$GRANT_SCRIPT" ]] || die "Missing grant script: $GRANT_SCRIPT"
command -v jq >/dev/null 2>&1 || die "jq is required"
[[ -n "$RANCHER_URL" ]] || die "--rancher-url is required"
[[ -n "$RANCHER_TOKEN" ]] || die "--token is required"
[[ -n "$CLUSTER_NAME" || -n "$CLUSTER_ID" ]] || die "--cluster-name or --cluster-id is required"

resolve_grants_json() {
  if [[ -n "$GRANTS_JSON" ]]; then
    printf '%s' "$GRANTS_JSON"
    return 0
  fi
  if [[ -n "${RANCHER_ACCESS_GRANTS:-}" ]]; then
    printf '%s' "$RANCHER_ACCESS_GRANTS"
    return 0
  fi
  [[ -f "$GRANTS_FILE" ]] || die "Grants file not found: $GRANTS_FILE (pass --grants-json or set RANCHER_ACCESS_GRANTS)"
  cat "$GRANTS_FILE"
}

GRANTS="$(resolve_grants_json)"
echo "$GRANTS" | jq -e 'type == "array" and length > 0' >/dev/null \
  || die "Grants must be a non-empty JSON array"

COUNT="$(echo "$GRANTS" | jq 'length')"
log "Applying $COUNT Rancher grant(s) ..."

FAILURES=0
for i in $(seq 0 $((COUNT - 1))); do
  GROUP="$(echo "$GRANTS" | jq -r ".[$i].group // empty")"
  ROLE="$(echo "$GRANTS" | jq -r ".[$i].role // empty")"
  PRINCIPAL_ID="$(echo "$GRANTS" | jq -r ".[$i].principal_id // empty")"
  AUTH_PREFIX="$(echo "$GRANTS" | jq -r ".[$i].group_auth_prefix // empty")"
  FIX_MISBOUND="$(echo "$GRANTS" | jq -r ".[$i].fix_misbound_user // false")"

  [[ -n "$GROUP" && -n "$ROLE" ]] || die "Grant index $i must include group and role"

  ARGS=(
    --rancher-url "$RANCHER_URL"
    --token "$RANCHER_TOKEN"
    --group "$GROUP"
    --role-template "$ROLE"
  )
  [[ -n "$CLUSTER_NAME" ]] && ARGS+=(--cluster-name "$CLUSTER_NAME")
  [[ -n "$CLUSTER_ID" ]] && ARGS+=(--cluster-id "$CLUSTER_ID")
  if [[ -n "$PRINCIPAL_ID" ]]; then
    ARGS+=(--group-principal-id "$PRINCIPAL_ID")
  else
    ARGS+=(--group-auth-prefix "${AUTH_PREFIX:-$DEFAULT_GROUP_AUTH_PREFIX}")
  fi
  [[ "$FIX_MISBOUND" == "true" ]] && ARGS+=(--fix-misbound-user)

  log "[$((i + 1))/$COUNT] group=$GROUP role=$ROLE"
  if ! "$GRANT_SCRIPT" "${ARGS[@]}"; then
    err "Grant failed for group=$GROUP role=$ROLE"
    FAILURES=$((FAILURES + 1))
  fi
done

if [[ "$FAILURES" -gt 0 ]]; then
  die "$FAILURES grant(s) failed"
fi

log "All $COUNT grant(s) applied successfully."
