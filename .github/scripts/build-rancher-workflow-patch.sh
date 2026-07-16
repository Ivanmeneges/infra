#!/usr/bin/env bash
#
# build-rancher-workflow-patch.sh - Build Rancher grant patch from GitHub Actions workflow inputs.
#
# Outputs a JSON array on stdout to merge (highest priority) into rancher-access-grants.json.
#
# Environment (set by terraform.yml from workflow_dispatch inputs):
#   WORKFLOW_DEVOPS_ROLE          cluster-owner | cluster-member (default: cluster-owner)
#   WORKFLOW_GRANT_DEVOPS         true | false (default: true)
#   WORKFLOW_GRANT_QA             true | false (default: false)
#   WORKFLOW_GRANT_DEVELOPERS     true | false (default: false)
#   WORKFLOW_EXTRA_GROUPS         Comma-separated extra groups from JSON to enable
#   WORKFLOW_CLUSTER_OWNER_GROUPS Comma-separated groups to grant cluster-owner this run

set -euo pipefail

DEVOPS_GROUP="${WORKFLOW_DEVOPS_GROUP:-DEVOPS}"
DEVOPS_ROLE="${WORKFLOW_DEVOPS_ROLE:-cluster-owner}"
GRANT_DEVOPS="${WORKFLOW_GRANT_DEVOPS:-true}"
GRANT_QA="${WORKFLOW_GRANT_QA:-false}"
GRANT_DEVELOPERS="${WORKFLOW_GRANT_DEVELOPERS:-false}"
EXTRA_GROUPS="${WORKFLOW_EXTRA_GROUPS:-}"
CLUSTER_OWNER_GROUPS="${WORKFLOW_CLUSTER_OWNER_GROUPS:-}"

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

# DEVOPS — always configured; default cluster-owner
if [[ "$(bool_enabled "$GRANT_DEVOPS")" == "true" ]]; then
  add_entry "$DEVOPS_GROUP" "$DEVOPS_ROLE" true true
else
  add_entry "$DEVOPS_GROUP" "$DEVOPS_ROLE" false false
fi

# Known teams from rancher-access-grants.json (toggle in workflow UI)
add_entry "QA" "cluster-member" "$(bool_enabled "$GRANT_QA")" false
add_entry "DEVELOPERS" "cluster-member" "$(bool_enabled "$GRANT_DEVELOPERS")" false

# Extra groups from JSON (comma-separated)
if [[ -n "${EXTRA_GROUPS// }" ]]; then
  IFS=',' read -ra EXTRAS <<<"$EXTRA_GROUPS"
  for raw in "${EXTRAS[@]}"; do
    g="${raw// /}"
    [[ -n "$g" ]] || continue
    add_entry "$g" "cluster-member" true false
  done
fi

# Cluster-owner overrides for any group (DEVOPS, QA, custom, etc.)
if [[ -n "${CLUSTER_OWNER_GROUPS// }" ]]; then
  IFS=',' read -ra OWNERS <<<"$CLUSTER_OWNER_GROUPS"
  for raw in "${OWNERS[@]}"; do
    g="${raw// /}"
    [[ -n "$g" ]] || continue
    # Upsert: enable + cluster-owner (overrides member role from above)
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
