#!/usr/bin/env bash
#
# mint-rancher-import-tfvars.sh - Mint Rancher import URL and write rancher-override.tfvars
#
# Shared by workflow steps that need enable_rancher_import + rancher_import_url for Terraform.
# Requires: bash 4+, python3, rancher-register-cluster.sh
#
# Environment:
#   RANCHER_URL, RANCHER_TOKEN  - Rancher API credentials (required)
#   GITHUB_WORKSPACE            - Repo root (for register script path)
#   GITHUB_ENV                  - When set, exports RANCHER_TFVARS_FILE for later steps
#   REF_NAME                    - Used in error messages / cluster name fallback

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-}"
MESSAGE="minted"

usage() {
  cat <<'EOF'
Usage: mint-rancher-import-tfvars.sh [--cluster-name NAME] [--message LABEL]

Writes rancher-override.tfvars in the current directory and optionally appends
RANCHER_TFVARS_FILE to GITHUB_ENV.

Requires environment variables RANCHER_URL and RANCHER_TOKEN.
EOF
}

require_arg() {
  local flag="$1"
  [[ $# -ge 2 && -n "${2:-}" && "$2" != --* ]] || {
    echo "[mint-rancher-import][ERROR] $flag requires a value" >&2
    exit 1
  }
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster-name) require_arg --cluster-name "${2-}"; CLUSTER_NAME="$2"; shift 2 ;;
    --message)      require_arg --message "${2-}";      MESSAGE="$2";      shift 2 ;;
    -h|--help)      usage; exit 0 ;;
    *)              echo "[mint-rancher-import][ERROR] Unknown argument: $1" >&2; exit 1 ;;
  esac
done

REF_NAME="${REF_NAME:-unknown}"

if [[ -z "${RANCHER_URL:-}" || -z "${RANCHER_TOKEN:-}" ]]; then
  echo "[mint-rancher-import][ERROR] RANCHER_URL and RANCHER_TOKEN must be set for environment '$REF_NAME'" >&2
  exit 1
fi

if [[ -z "$CLUSTER_NAME" ]]; then
  CLUSTER_NAME="${RANCHER_CLUSTER_NAME_INPUT:-${REF_NAME}}"
fi

if [[ -z "$CLUSTER_NAME" ]]; then
  echo "[mint-rancher-import][ERROR] cluster name is required (--cluster-name or CLUSTER_NAME)" >&2
  exit 1
fi

REGISTER_SCRIPT="${GITHUB_WORKSPACE:-}/.github/scripts/rancher-register-cluster.sh"
if [[ ! -f "$REGISTER_SCRIPT" ]]; then
  echo "[mint-rancher-import][ERROR] Register script not found: $REGISTER_SCRIPT" >&2
  exit 1
fi
chmod +x "$REGISTER_SCRIPT" 2>/dev/null || true

echo "Registering cluster '$CLUSTER_NAME' in Rancher ($MESSAGE)..."
IMPORT_CMD="$("$REGISTER_SCRIPT" \
  --rancher-url "$RANCHER_URL" \
  --token "$RANCHER_TOKEN" \
  --cluster-name "$CLUSTER_NAME" | tail -n1)"

IMPORT_INNER="${IMPORT_CMD#\"}"
IMPORT_INNER="${IMPORT_INNER%\"}"
export IMPORT_INNER

python3 <<'PY' > rancher-override.tfvars
import os

inner = os.environ["IMPORT_INNER"]
quoted = '"' + inner + '"'
hcl = '"' + quoted.replace('"', '\\"') + '"'
print("enable_rancher_import = true")
print(f"rancher_import_url    = {hcl}")
PY

echo "Generated rancher-override.tfvars ($MESSAGE):"
cat rancher-override.tfvars

if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "RANCHER_TFVARS_FILE=rancher-override.tfvars" >> "$GITHUB_ENV"
fi

echo "Rancher import URL $MESSAGE for: $CLUSTER_NAME"
