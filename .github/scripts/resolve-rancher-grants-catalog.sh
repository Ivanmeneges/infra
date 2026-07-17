#!/usr/bin/env bash
#
# resolve-rancher-grants-catalog.sh - Locate or materialize rancher-access-grants.json
#
# Prints the absolute path to use on stdout. Never fails if a built-in default can be used.
#
# Environment:
#   GITHUB_WORKSPACE  Repo root (default: current directory)
#   REF_NAME          Branch/env name for log messages (optional)

set -euo pipefail

ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
REF="${REF_NAME:-unknown}"

CANDIDATES=(
  "$ROOT/.github/config/rancher-access-grants.json"
  "$ROOT/.github/scripts/rancher-access-grants.default.json"
)

log() { echo "[resolve-rancher-grants] $*" >&2; }

write_builtin_default() {
  local dest="$1"
  mkdir -p "$(dirname "$dest")"
  cat >"$dest" <<'EOF'
[
  {
    "group": "DEVOPS",
    "role": "cluster-owner",
    "enabled": true,
    "principal_id": "keycloak_group://DEVOPS",
    "fix_misbound_user": true
  },
  {
    "group": "QA",
    "role": "cluster-member",
    "enabled": false,
    "principal_id": "keycloak_group://QA"
  },
  {
    "group": "DEVELOPERS",
    "role": "cluster-member",
    "enabled": false,
    "principal_id": "keycloak_group://DEVELOPERS"
  }
]
EOF
  log "Wrote built-in default catalog to $dest"
  printf '%s' "$dest"
}

log "Resolving grants catalog (branch/ref=$REF, workspace=$ROOT)"

if command -v git >/dev/null 2>&1 && [[ -d "$ROOT/.git" ]]; then
  log "Git HEAD: $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown) on $(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
fi

if [[ -d "$ROOT/.github/config" ]]; then
  log "Contents of .github/config/:"
  ls -la "$ROOT/.github/config/" >&2 || true
else
  log "Directory missing: $ROOT/.github/config/"
fi

for path in "${CANDIDATES[@]}"; do
  if [[ -f "$path" ]]; then
    log "Using catalog: $path"
    printf '%s' "$path"
    exit 0
  fi
  log "Not found: $path"
done

# Last resort: materialize under RUNNER_TEMP or /tmp
dest="${RUNNER_TEMP:-/tmp}/rancher-access-grants.${REF}.json"
log "No catalog file on branch '$REF' — using embedded default (commit .github/config/rancher-access-grants.json to customize)"
write_builtin_default "$dest"
