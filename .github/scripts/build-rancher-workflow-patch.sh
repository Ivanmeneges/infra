#!/usr/bin/env bash
#
# build-rancher-workflow-patch.sh - Build Rancher grant patch from GitHub Actions workflow inputs.
#
# Outputs a JSON array on stdout to merge (highest priority) into rancher-access-grants.json.
#
# Environment (set by terraform.yml from workflow_dispatch inputs):
#   WORKFLOW_DEVOPS_GROUP         DEVOPS group name (default: DEVOPS)
#   WORKFLOW_DEVOPS_ROLE          cluster-owner | cluster-member (default: cluster-owner)
#   WORKFLOW_GRANT_DEVOPS         true | false (default: true)
#   WORKFLOW_GRANT_GROUPS         Comma-separated non-DEVOPS groups from catalog to enable
#   WORKFLOW_CLUSTER_OWNER_GROUPS Comma-separated groups to grant cluster-owner this run
#   WORKFLOW_GRANTS_CATALOG       Path to rancher-access-grants.json (optional)

set -euo pipefail

DEVOPS_GROUP="${WORKFLOW_DEVOPS_GROUP:-DEVOPS}"
DEVOPS_ROLE="${WORKFLOW_DEVOPS_ROLE:-cluster-owner}"
GRANT_DEVOPS="${WORKFLOW_GRANT_DEVOPS:-true}"
GRANT_GROUPS="${WORKFLOW_GRANT_GROUPS:-}"
CLUSTER_OWNER_GROUPS="${WORKFLOW_CLUSTER_OWNER_GROUPS:-}"
CATALOG_FILE="${WORKFLOW_GRANTS_CATALOG:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "$CATALOG_FILE" ]]; then
  CATALOG_FILE="${SCRIPT_DIR%/scripts}/config/rancher-access-grants.json"
fi

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
[[ -f "$CATALOG_FILE" ]] || { echo "Missing grants catalog: $CATALOG_FILE" >&2; exit 1; }

patch='[]'

add_entry() {
  local group="$1" role="$2" enabled="$3" fix="${4:-false}"
  local extra='{}'
  if [[ "$fix" == "true" ]]; then
    extra='{"fix_misbound_user":true}'
  fi
  patch="$(jq -c \
    --arg g "$group" --arg r "$role" --argjson e "$enabled" --argjson x "$extra" \
    '. + [({group:$g, role:$r, enabled:$e} + $x)]' <<<"$patch")"
}

bool_enabled() {
  case "${1,,}" in
    true|1|yes) echo true ;;
    *) echo false ;;
  esac
}

group_in_list() {
  local target="$1" list="$2"
  [[ -n "${list// }" ]] || return 1
  IFS=',' read -ra ITEMS <<<"$list"
  for raw in "${ITEMS[@]}"; do
    g="${raw// /}"
    [[ "$g" == "$target" ]] && return 0
  done
  return 1
}

catalog_role_for() {
  local group="$1"
  jq -r --arg g "$group" '
    .[] | select(.group == $g) | .role // empty
  ' "$CATALOG_FILE" | head -n1
}

# DEVOPS — default cluster-owner; can be toggled or overridden via CLUSTER_OWNER_GROUPS
if [[ "$(bool_enabled "$GRANT_DEVOPS")" == "true" ]]; then
  add_entry "$DEVOPS_GROUP" "$DEVOPS_ROLE" true true
else
  add_entry "$DEVOPS_GROUP" "$DEVOPS_ROLE" false false
fi

# Non-DEVOPS teams from catalog: enable only when listed in WORKFLOW_GRANT_GROUPS
while IFS= read -r group; do
  [[ -n "$group" ]] || continue
  [[ "$group" == "$DEVOPS_GROUP" ]] && continue
  role="$(catalog_role_for "$group")"
  [[ -n "$role" ]] || role="cluster-member"
  if group_in_list "$group" "$GRANT_GROUPS"; then
    add_entry "$group" "$role" true false
  else
    add_entry "$group" "$role" false false
  fi
done < <(jq -r '.[].group' "$CATALOG_FILE")

# Cluster-owner overrides for any group (DEVOPS, QA, teams from JSON, etc.)
if [[ -n "${CLUSTER_OWNER_GROUPS// }" ]]; then
  IFS=',' read -ra OWNERS <<<"$CLUSTER_OWNER_GROUPS"
  for raw in "${OWNERS[@]}"; do
    g="${raw// /}"
    [[ -n "$g" ]] || continue
    if jq -e --arg g "$g" 'map(select(.group == $g)) | length > 0' <<<"$patch" >/dev/null; then
      patch="$(jq -c --arg g "$g" \
        'map(if .group == $g then .role = "cluster-owner" | .enabled = true else . end)' <<<"$patch")"
    else
      fix="false"
      [[ "$g" == "$DEVOPS_GROUP" ]] && fix="true"
      add_entry "$g" "cluster-owner" true "$fix"
    fi
  done
fi

printf '%s' "$patch"
