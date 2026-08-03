#!/usr/bin/env bash
#
# rancher-apply-cluster-import.sh - Mint a fresh Rancher import URL and apply it on the cluster.
#
# Called from the terraform apply workflow after Terraform Apply succeeds so the import
# manifest is applied with a current registration token (Ansible Play 3 may run 30+ min
# after the URL was minted). Does not modify Ansible; manual/local imports still use
# rancher_import_url in tfvars and the existing playbook path.
#
# Requires: bash 4+, curl, jq, ssh

set -euo pipefail

RANCHER_URL="${RANCHER_URL:-}"
RANCHER_TOKEN="${RANCHER_TOKEN:-}"
CLUSTER_NAME="${CLUSTER_NAME:-}"
SSH_KEY=""
SSH_HOST=""
SSH_USER="${SSH_USER:-ubuntu}"
KUBECONFIG_REMOTE=""
REGISTER_SCRIPT=""
MAX_AGENT_WAIT="${MAX_AGENT_WAIT:-30}"
AGENT_SLEEP="${AGENT_SLEEP:-10}"

usage() {
  cat <<'EOF'
Usage: rancher-apply-cluster-import.sh \
  --rancher-url <url> --token <token> --cluster-name <name> \
  --ssh-key <path> --ssh-host <ip> [--ssh-user ubuntu] [--kubeconfig-remote <path>]

Mints a fresh Rancher import command, applies it on the primary control plane via SSH,
and waits for cattle-cluster-agent to reach Running when possible.
EOF
}

err() { echo "[rancher-apply-import][ERROR] $*" >&2; }
die() { err "$*"; exit 1; }
log() { echo "[rancher-apply-import] $*" >&2; }

require_arg() {
  local flag="$1"
  [[ $# -ge 2 && -n "${2:-}" && "$2" != --* ]] || die "$flag requires a value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rancher-url)       require_arg --rancher-url "${2-}";       RANCHER_URL="$2"; shift 2 ;;
    --token)             require_arg --token "${2-}";             RANCHER_TOKEN="$2"; shift 2 ;;
    --cluster-name)      require_arg --cluster-name "${2-}";      CLUSTER_NAME="$2"; shift 2 ;;
    --ssh-key)           require_arg --ssh-key "${2-}";           SSH_KEY="$2"; shift 2 ;;
    --ssh-host)          require_arg --ssh-host "${2-}";          SSH_HOST="$2"; shift 2 ;;
    --ssh-user)          require_arg --ssh-user "${2-}";          SSH_USER="$2"; shift 2 ;;
    --kubeconfig-remote) require_arg --kubeconfig-remote "${2-}"; KUBECONFIG_REMOTE="$2"; shift 2 ;;
    --register-script)   require_arg --register-script "${2-}";   REGISTER_SCRIPT="$2"; shift 2 ;;
    -h|--help)           usage; exit 0 ;;
    *)                   die "Unknown argument: $1 (use --help)" ;;
  esac
done

[[ -n "$RANCHER_URL" && -n "$RANCHER_TOKEN" && -n "$CLUSTER_NAME" ]] \
  || die "--rancher-url, --token, and --cluster-name are required"
[[ -n "$SSH_KEY" && -n "$SSH_HOST" ]] || die "--ssh-key and --ssh-host are required"
[[ -f "$SSH_KEY" ]] || die "SSH key not found: $SSH_KEY"

if [[ -z "$REGISTER_SCRIPT" ]]; then
  if [[ -n "${GITHUB_WORKSPACE:-}" && -f "$GITHUB_WORKSPACE/.github/scripts/rancher-register-cluster.sh" ]]; then
    REGISTER_SCRIPT="$GITHUB_WORKSPACE/.github/scripts/rancher-register-cluster.sh"
  else
    die "Could not locate rancher-register-cluster.sh (pass --register-script or set GITHUB_WORKSPACE)"
  fi
fi
[[ -x "$REGISTER_SCRIPT" ]] || chmod +x "$REGISTER_SCRIPT"

ssh_cmd() {
  ssh -i "$SSH_KEY" \
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=15 \
    "${SSH_USER}@${SSH_HOST}" "$@"
}

remote_kubectl() {
  local remote_cmd="kubectl $*"
  if [[ -n "$KUBECONFIG_REMOTE" ]]; then
    remote_cmd="KUBECONFIG=$KUBECONFIG_REMOTE $remote_cmd"
  fi
  ssh_cmd "bash -lc $(printf '%q' "$remote_cmd")"
}

remote_shell() {
  ssh_cmd "bash -lc $(printf '%q' "$1")"
}

strip_hcl_quotes() {
  local value="$1"
  value="${value#\"}"
  value="${value%\"}"
  printf '%s' "$value"
}

mint_import_cmd() {
  local quoted inner
  quoted="$("$REGISTER_SCRIPT" \
    --rancher-url "$RANCHER_URL" \
    --token "$RANCHER_TOKEN" \
    --cluster-name "$CLUSTER_NAME" | tail -n1)"
  [[ -n "$quoted" ]] || die "Rancher registration returned empty import command"
  inner="$(strip_hcl_quotes "$quoted")"
  [[ "$inner" =~ ^kubectl[[:space:]]+apply[[:space:]]+-f[[:space:]]+https:// ]] \
    || die "Unexpected import command form: $inner"
  printf '%s' "$inner"
}

cattle_agent_phase() {
  remote_kubectl get pods -n cattle-system -l app=cattle-cluster-agent \
    -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true
}

cattle_system_exists() {
  remote_kubectl get namespace cattle-system >/dev/null 2>&1
}

wait_for_cattle_agent() {
  local attempt phase
  for ((attempt = 1; attempt <= MAX_AGENT_WAIT; attempt++)); do
    phase="$(cattle_agent_phase)"
    if [[ "$phase" == "Running" ]]; then
      log "cattle-cluster-agent is Running"
      return 0
    fi
    log "Waiting for cattle-cluster-agent (phase=${phase:-missing}, attempt ${attempt}/${MAX_AGENT_WAIT}) ..."
    sleep "$AGENT_SLEEP"
  done
  err "cattle-cluster-agent did not reach Running within $((MAX_AGENT_WAIT * AGENT_SLEEP)) seconds"
  return 1
}

log "Minting fresh Rancher import URL for cluster '${CLUSTER_NAME}' ..."
IMPORT_CMD="$(mint_import_cmd)"
log "Applying Rancher import on ${SSH_HOST} ..."

if cattle_system_exists; then
  phase="$(cattle_agent_phase)"
  if [[ "$phase" == "Running" ]]; then
    log "cattle-system exists and cattle-cluster-agent is Running — skipping import apply"
    exit 0
  fi
  log "cattle-system exists but agent is not healthy (phase=${phase:-missing}) — resetting namespace before re-import"
  remote_kubectl delete namespace cattle-system --ignore-not-found --wait=true || true
fi

remote_shell "$IMPORT_CMD"
log "Rancher import manifest applied"

if ! wait_for_cattle_agent; then
  err "Import manifest applied but cattle-cluster-agent is not Running yet"
  remote_kubectl get pods -n cattle-system -o wide 2>/dev/null || true
  exit 1
fi

log "Rancher cluster import completed successfully on ${SSH_HOST}"
