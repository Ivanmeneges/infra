#!/usr/bin/env bash
#
# mint-rancher-runtime-tfvars.sh - Mint a Rancher import URL and write runtime tfvars.
#
# Shared by terraform.yml plan-time and pre-apply refresh steps (single implementation).
#
# Requires: bash 4+, rancher-register-cluster.sh, write-rancher-runtime-tfvars.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTER_SCRIPT="${SCRIPT_DIR}/rancher-register-cluster.sh"
WRITE_SCRIPT="${SCRIPT_DIR}/write-rancher-runtime-tfvars.sh"

RANCHER_URL=""
RANCHER_TOKEN=""
CLUSTER_NAME=""
OUT=""
PHASE="plan"
GITHUB_ENV_FILE="${GITHUB_ENV:-}"

usage() {
  cat <<'EOF'
Usage:
  mint-rancher-runtime-tfvars.sh \
    --rancher-url <url> --token <token> --cluster-name <name> \
    --out <path> [--phase plan|apply]

  --phase plan   Log message for plan-time mint (default)
  --phase apply  Log message for pre-apply refresh

When GITHUB_ENV is set, appends RANCHER_RUNTIME_VARS_FILE=<out> to it.
EOF
}

die() { echo "[mint-rancher-runtime][ERROR] $*" >&2; exit 1; }

require_arg() {
  local flag="$1"
  [[ $# -ge 2 && -n "${2:-}" && "$2" != --* ]] || die "$flag requires a value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rancher-url) require_arg --rancher-url "${2-}"; RANCHER_URL="$2"; shift 2 ;;
    --token)       require_arg --token "${2-}";       RANCHER_TOKEN="$2"; shift 2 ;;
    --cluster-name) require_arg --cluster-name "${2-}"; CLUSTER_NAME="$2"; shift 2 ;;
    --out)         require_arg --out "${2-}";         OUT="$2"; shift 2 ;;
    --phase)       require_arg --phase "${2-}";       PHASE="$2"; shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    *)             die "Unknown argument: $1" ;;
  esac
done

[[ -n "$RANCHER_URL" && -n "$RANCHER_TOKEN" && -n "$CLUSTER_NAME" && -n "$OUT" ]] \
  || { usage; exit 1; }
[[ -x "$REGISTER_SCRIPT" ]] || die "Missing or not executable: $REGISTER_SCRIPT"
[[ -x "$WRITE_SCRIPT" ]] || die "Missing or not executable: $WRITE_SCRIPT"
case "$PHASE" in
  plan|apply) ;;
  *) die "--phase must be plan or apply (got: $PHASE)" ;;
esac

if [[ "$PHASE" == "plan" ]]; then
  echo "Registering cluster '${CLUSTER_NAME}' in Rancher (plan-time placeholder)..."
else
  echo "Refreshing Rancher import URL for cluster '${CLUSTER_NAME}' immediately before apply..."
fi

set -o pipefail
IMPORT_CMD="$("$REGISTER_SCRIPT" \
  --rancher-url "$RANCHER_URL" \
  --token "$RANCHER_TOKEN" \
  --cluster-name "$CLUSTER_NAME" | tail -n1)"
[[ -n "$IMPORT_CMD" ]] || die "Rancher registration returned empty import command"

"$WRITE_SCRIPT" \
  --out "$OUT" \
  --enable true \
  --import-cmd "$IMPORT_CMD"

if [[ -n "$GITHUB_ENV_FILE" && -w "$GITHUB_ENV_FILE" ]]; then
  echo "RANCHER_RUNTIME_VARS_FILE=$OUT" >> "$GITHUB_ENV_FILE"
fi

if [[ "$PHASE" == "plan" ]]; then
  echo "Rancher import URL minted for: $CLUSTER_NAME (runtime -var-file; not written to profile aws.tfvars)"
else
  echo "Refreshed Rancher import URL for apply (runtime -var-file)"
fi
