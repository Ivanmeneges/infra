#!/usr/bin/env bash
#
# wg-offboard.sh - Revoke WireGuard access for an environment and free peers for reuse.
#
# Unlike only clearing assigned.txt, this script:
#   1. Removes each peer from the live WireGuard interface (wg set wg0 peer ... remove)
#   2. Removes the peer stanza from persistent wg0.conf on the jumpserver
#   3. Deletes client key material under config/peerN/ (old .conf becomes useless)
#   4. Clears assigned.txt lines for the environment
#   5. Deletes GitHub environment secrets TF_WG_CONFIG / CLUSTER_WIREGUARD_WG0/WG1
#   6. Updates .github/scripts/wg-peer-allocation.tsv in the repo tracker
#
# After offboard, wg-onboard.sh can allocate the same peer numbers again with fresh keys.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALLOCATION_FILE="${ALLOCATION_FILE:-$SCRIPT_DIR/wg-peer-allocation.tsv}"

SSH_USER="${SSH_USER:-ubuntu}"
SSH_KEY="${SSH_KEY:-}"
JUMPSERVER_HOST="${JUMPSERVER_HOST:-}"
ENV_NAME="${ENV_NAME:-}"
REPO="${REPO:-}"
WG_DIR="${WG_DIR:-/home/ubuntu/wireguard_env_2026}"
DRY_RUN="false"
DELETE_ENVIRONMENT="false"
REGENERATE_PEERS="false"

SECRET_NAMES=(TF_WG_CONFIG CLUSTER_WIREGUARD_WG0 CLUSTER_WIREGUARD_WG1)

usage() {
  cat <<'EOF'
Usage: wg-offboard.sh --env <name> --host <jumpserver_ip> --ssh-key <path> [options]

Required:
  --env <name>          Environment / branch name to offboard
  --host <ip|dns>       Jumpserver public IP or DNS
  --ssh-key <path>      SSH private key for ubuntu@jumpserver

Optional:
  --repo <owner/repo>   GitHub repo (default: inferred via gh)
  --wg-dir <path>       WireGuard env dir on VM (default: /home/ubuntu/wireguard_env_2026)
  --delete-environment  Delete the GitHub environment after removing secrets
  --regenerate-peers    After revoke, immediately recreate peer dirs with new keys (ready for reuse)
  --dry-run             Show planned actions only
  -h, --help

Requires: gh, ssh, jq
EOF
}

log()  { echo "[wg-offboard] $*" >&2; }
err()  { echo "[wg-offboard][ERROR] $*" >&2; }
die()  { err "$*"; exit 1; }

require_arg() {
  local flag="$1"
  [[ $# -ge 2 && -n "${2:-}" && "$2" != --* ]] || die "$flag requires a value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)                require_arg --env "${2-}";                ENV_NAME="$2"; shift 2 ;;
    --host)               require_arg --host "${2-}";               JUMPSERVER_HOST="$2"; shift 2 ;;
    --ssh-key)            require_arg --ssh-key "${2-}";            SSH_KEY="$2"; shift 2 ;;
    --repo)               require_arg --repo "${2-}";               REPO="$2"; shift 2 ;;
    --wg-dir)             require_arg --wg-dir "${2-}";             WG_DIR="$2"; shift 2 ;;
    --delete-environment) DELETE_ENVIRONMENT="true"; shift ;;
    --regenerate-peers)   REGENERATE_PEERS="true"; shift ;;
    --dry-run)            DRY_RUN="true"; shift ;;
    -h|--help)            usage; exit 0 ;;
    *)                    die "Unknown argument: $1" ;;
  esac
done

[[ -n "$ENV_NAME" ]]        || die "--env is required"
[[ -n "$JUMPSERVER_HOST" ]] || die "--host is required"
[[ -n "$SSH_KEY" ]]         || die "--ssh-key is required"
[[ -f "$SSH_KEY" ]]         || die "ssh key not found: $SSH_KEY"
command -v gh  >/dev/null 2>&1 || die "gh CLI is required"
command -v ssh >/dev/null 2>&1 || die "ssh is required"

if [[ -z "$REPO" ]]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
  [[ -n "$REPO" ]] || die "Could not infer repo; pass --repo owner/repo"
fi

CONFIG_DIR="$WG_DIR/config"
ASSIGNED_FILE="$WG_DIR/assigned.txt"
ASSIGN_LOCK_FILE="/tmp/wg-offboard-$(printf '%s' "$ASSIGNED_FILE" | cksum | awk '{print $1}').lock"

SSH_KNOWN_HOSTS="${SSH_KNOWN_HOSTS:-$HOME/.ssh/known_hosts}"
SSH_KNOWN_HOSTS_IS_TEMP="false"
if [[ ! -f "$SSH_KNOWN_HOSTS" ]]; then
  SSH_KNOWN_HOSTS="$(mktemp)"
  SSH_KNOWN_HOSTS_IS_TEMP="true"
fi
wg_offboard_cleanup() {
  [[ "$SSH_KNOWN_HOSTS_IS_TEMP" == "true" ]] && rm -f "$SSH_KNOWN_HOSTS"
}
trap wg_offboard_cleanup EXIT

ssh_cmd() {
  ssh -i "$SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$SSH_KNOWN_HOSTS" \
    "${SSH_USER}@${JUMPSERVER_HOST}" "$@"
}

ssh_bash_stdin() {
  ssh -i "$SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$SSH_KNOWN_HOSTS" \
    "${SSH_USER}@${JUMPSERVER_HOST}" "bash -s" -- "$@"
}

log "Offboarding environment: $ENV_NAME"
log "WireGuard dir: $WG_DIR"

# ---- Resolve peers + revoke on jumpserver (under flock) --------------------
REVOKE_RESULT="$(ssh_bash_stdin \
  "$ASSIGNED_FILE" \
  "$ASSIGN_LOCK_FILE" \
  "$CONFIG_DIR" \
  "$ENV_NAME" \
  "$DRY_RUN" \
  "$REGENERATE_PEERS" \
  <<'REMOTE_OFFBOARD'
set -euo pipefail

ASSIGNED_FILE="$1"
LOCK_FILE="$2"
CONFIG_DIR="$3"
ENV_NAME="$4"
DRY_RUN="${5:-false}"
REGENERATE="${6:-false}"

PARSED_PEER=""
PARSED_LABEL=""

normalize_peer_token() {
  local token="${1//$'\r'/}"
  token="${token%%:*}"
  printf '%s' "$token"
}

parse_assigned_line() {
  local line="${1//$'\r'/}"
  local peer rest
  PARSED_PEER=""
  PARSED_LABEL=""
  [[ -z "${line//[[:space:]]/}" ]] && return 1
  peer="$(normalize_peer_token "$(awk '{print $1}' <<<"$line")")"
  [[ "$peer" =~ ^peer[0-9]+$ ]] || return 1
  if [[ "$line" =~ ^peer[0-9]+[[:space:]]*:[[:space:]]*(.*)$ ]]; then
    rest="${BASH_REMATCH[1]}"
  else
    rest="$(awk '{$1=""; sub(/^ +/,""); print}' <<<"$line")"
  fi
  rest="${rest//$'\r'/}"
  rest="$(awk '{$1=$1; print}' <<<"$rest")"
  PARSED_PEER="$peer"
  PARSED_LABEL="$rest"
  return 0
}

mosip_peer_for_secret() {
  local secret="$1" content="$2"
  awk -v env="$ENV_NAME" -v secret="$secret" '
    $1 ~ /^peer[0-9]+:?$/ {
      peer=$1; sub(/:$/, "", peer)
      desc=$0; sub(/^[[:space:]]*peer[0-9]+[[:space:]]*:?[[:space:]]*/, "", desc)
      suffix="(" secret ")"
      if (length(desc) < length(suffix)) next
      if (substr(desc, length(desc) - length(suffix) + 1) != suffix) next
      label=substr(desc, 1, length(desc) - length(suffix))
      if (label == env || index(label, env "(") == 1) { print peer; exit }
    }' <<<"$content"
}

find_env_peers() {
  local assigned_content="$1" format="mosip"
  local -a peers=()
  if grep -qE '^peer[0-9]+[[:space:]]*:' <<<"$assigned_content"; then
    format="colon"
    while IFS= read -r line; do
      parse_assigned_line "$line" || continue
      [[ "$PARSED_LABEL" == "$ENV_NAME" ]] && peers+=("$PARSED_PEER")
    done <<<"$assigned_content"
  else
    local tf wg0 wg1
    tf="$(mosip_peer_for_secret TF_WG_CONFIG "$assigned_content")"
    wg0="$(mosip_peer_for_secret CLUSTER_WIREGUARD_WG0 "$assigned_content")"
    wg1="$(mosip_peer_for_secret CLUSTER_WIREGUARD_WG1 "$assigned_content")"
    [[ -n "$tf" ]] && peers+=("$tf")
    [[ -n "$wg0" && "$wg0" != "$tf" ]] && peers+=("$wg0")
    [[ -n "$wg1" && "$wg1" != "$tf" && "$wg1" != "$wg0" ]] && peers+=("$wg1")
  fi
  printf '%s\n' "${peers[@]}"
}

wg_container() {
  docker ps --format '{{.Names}}' | grep -iE 'wireguard|wg' | head -1
}

wg_conf_paths() {
  local paths=()
  [[ -f "$CONFIG_DIR/wg_confs/wg0.conf" ]] && paths+=("$CONFIG_DIR/wg_confs/wg0.conf")
  [[ -f "$CONFIG_DIR/wg0.conf" ]] && paths+=("$CONFIG_DIR/wg0.conf")
  printf '%s\n' "${paths[@]}"
}

remove_peer_from_conf() {
  local conf="$1" peer="$2" tmp
  [[ -f "$conf" ]] || return 0
  tmp="$(mktemp "$(dirname "$conf")/.wg0.XXXXXX")"
  awk -v peer="$peer" '
    BEGIN { drop=0; buf="" }
    /^\[Peer\]/ {
      if (buf != "" && drop == 0) printf "%s", buf
      buf=$0 ORS
      drop=0
      next
    }
    buf != "" {
      buf=buf $0 ORS
      if ($0 ~ ("^# " peer "$")) drop=1
      if ($0 ~ /^$/ || /^\[/) {
        if (drop == 0) printf "%s", buf
        buf=""
        drop=0
        if ($0 !~ /^\[Peer\]/) print $0
      }
      next
    }
    { print }
    END { if (buf != "" && drop == 0) printf "%s", buf }
  ' "$conf" > "$tmp"
  if [[ "$DRY_RUN" == "true" ]]; then
    rm -f "$tmp"
    echo "DRY: would update $conf (remove peer $peer)"
    return 0
  fi
  mv -f "$tmp" "$conf"
}

revoke_peer_runtime() {
  local peer="$1" pubkey_file="$CONFIG_DIR/$peer/publickey-$peer" pub C
  [[ -f "$pubkey_file" ]] || return 0
  pub="$(cat "$pubkey_file")"
  C="$(wg_container)"
  [[ -n "$C" ]] || { echo "ERROR: WireGuard docker container not running" >&2; return 1; }
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "DRY: wg set wg0 peer $pub remove"
    return 0
  fi
  docker exec "$C" wg set wg0 peer "$pub" remove \
    || echo "WARN: peer $pub not present on live wg0 (already removed?)" >&2
}

wipe_peer_dir() {
  local peer="$1" dir="$CONFIG_DIR/$peer"
  [[ -d "$dir" ]] || return 0
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "DRY: wipe $dir"
    return 0
  fi
  rm -f "$dir"/*.conf "$dir"/privatekey-* "$dir"/publickey-* "$dir"/presharedkey-* 2>/dev/null || true
}

regenerate_peer() {
  local peer_num="$1"
  local PEER_ID="peer${peer_num}"
  local REF_CONF REF_DIRS C INTERFACE ENDPOINT SERVER_PUBKEY PEERDNS CLIENT_IP PRIV PSK PUB WG_CONF
  [[ "$REGENERATE" == "true" ]] || return 0
  [[ "$DRY_RUN" == "true" ]] && { echo "DRY: regenerate $PEER_ID"; return 0; }

  mapfile -t REF_DIRS < <(ls -d "$CONFIG_DIR"/peer[0-9]* 2>/dev/null | sort -t r -k2 -n)
  [[ ${#REF_DIRS[@]} -gt 0 ]] || return 1
  REF_CONF="${REF_DIRS[0]}/$(basename "${REF_DIRS[0]}").conf"
  [[ -f "$REF_CONF" ]] || return 1

  INTERFACE="$(grep -m1 '^Address' "$REF_CONF" | awk '{print $NF}' | awk -F. '{print $1"."$2"."$3}')"
  ENDPOINT="$(grep -m1 '^Endpoint' "$REF_CONF" | awk '{print $NF}')"
  SERVER_PUBKEY="$(grep -m1 '^PublicKey' "$REF_CONF" | awk '{print $NF}')"
  PEERDNS="$(grep -m1 '^DNS' "$REF_CONF" | awk '{print $NF}')"
  [[ -n "$INTERFACE" && -n "$ENDPOINT" && -n "$SERVER_PUBKEY" ]] || return 1
  [[ -n "$PEERDNS" ]] || PEERDNS="${INTERFACE}.1"

  C="$(wg_container)"
  [[ -n "$C" ]] || return 1

  mkdir -p "$CONFIG_DIR/$PEER_ID"
  umask 077
  docker exec "$C" wg genkey | tee "$CONFIG_DIR/$PEER_ID/privatekey-$PEER_ID" \
    | docker exec -i "$C" wg pubkey > "$CONFIG_DIR/$PEER_ID/publickey-$PEER_ID"
  docker exec "$C" wg genpsk > "$CONFIG_DIR/$PEER_ID/presharedkey-$PEER_ID"

  CLIENT_IP=""
  for idx in $(seq 2 254); do
    if ! grep -qR "${INTERFACE}.${idx}" "$CONFIG_DIR"/peer*/*.conf 2>/dev/null; then
      CLIENT_IP="${INTERFACE}.${idx}"
      break
    fi
  done
  [[ -n "$CLIENT_IP" ]] || return 1

  PRIV="$(cat "$CONFIG_DIR/$PEER_ID/privatekey-$PEER_ID")"
  PSK="$(cat "$CONFIG_DIR/$PEER_ID/presharedkey-$PEER_ID")"
  PUB="$(cat "$CONFIG_DIR/$PEER_ID/publickey-$PEER_ID")"

  cat > "$CONFIG_DIR/$PEER_ID/$PEER_ID.conf" <<EOF
[Interface]
Address = ${CLIENT_IP}
PrivateKey = ${PRIV}
ListenPort = 51820
DNS = ${PEERDNS}

[Peer]
PublicKey = ${SERVER_PUBKEY}
PresharedKey = ${PSK}
Endpoint = ${ENDPOINT}
AllowedIPs = 0.0.0.0/0, ::/0
EOF

  if [[ -f "$CONFIG_DIR/wg_confs/wg0.conf" ]]; then
    WG_CONF="$CONFIG_DIR/wg_confs/wg0.conf"
  else
    WG_CONF="$CONFIG_DIR/wg0.conf"
  fi

  cat >> "$WG_CONF" <<EOF

[Peer]
# ${PEER_ID}
PublicKey = ${PUB}
PresharedKey = ${PSK}
AllowedIPs = ${CLIENT_IP}/32

EOF

  echo "$PSK" | docker exec -i "$C" sh -c 'cat > /tmp/psk.tmp && wg set wg0 peer "'"$PUB"'" preshared-key /tmp/psk.tmp allowed-ips "'"${CLIENT_IP}/32"'" && rm -f /tmp/psk.tmp'
}

remove_peer_line() {
  local peer="$1" file="$2" dir tmp
  dir="$(dirname "$file")"
  tmp="$(mktemp "$dir/.assigned.XXXXXX")"
  awk -v p="$peer" '$1 !~ ("^" p ":?$")' "$file" > "$tmp"
  if [[ "$DRY_RUN" == "true" ]]; then
    rm -f "$tmp"
    echo "DRY: remove $peer from $file"
    return 0
  fi
  mv -f "$tmp" "$file"
}

exec 9>"$LOCK_FILE"
if ! flock -w 120 9; then
  echo "ERROR: timed out waiting for lock ($LOCK_FILE)" >&2
  exit 1
fi

assigned_content="$(cat "$ASSIGNED_FILE" 2>/dev/null || true)"
assigned_content="${assigned_content//$'\r'/}"
mapfile -t PEERS < <(find_env_peers "$assigned_content")

if [[ ${#PEERS[@]} -eq 0 ]]; then
  echo "WARN: no peers found for environment $ENV_NAME in $ASSIGNED_FILE" >&2
  printf 'PEERS=\n'
  exit 0
fi

for peer in "${PEERS[@]}"; do
  echo "Revoking $peer for $ENV_NAME ..."
  revoke_peer_runtime "$peer"
  while IFS= read -r conf; do
    [[ -n "$conf" ]] && remove_peer_from_conf "$conf" "$peer"
  done < <(wg_conf_paths)
  wipe_peer_dir "$peer"
  n="${peer#peer}"
  regenerate_peer "$n"
  remove_peer_line "$peer" "$ASSIGNED_FILE"
done

printf 'PEERS=%s\n' "$(IFS=,; echo "${PEERS[*]}")"
REMOTE_OFFBOARD
)" || die "Remote offboard failed on jumpserver"

PEERS_CSV=""
while IFS= read -r line; do
  [[ "$line" == PEERS=* ]] && PEERS_CSV="${line#PEERS=}"
done <<<"$REVOKE_RESULT"

if [[ -z "$PEERS_CSV" ]]; then
  log "No WireGuard peers were assigned to $ENV_NAME on jumpserver."
else
  log "Revoked peers on jumpserver: $PEERS_CSV"
fi

if [[ "$DRY_RUN" == "true" ]]; then
  log "DRY RUN - would delete GitHub secrets for environment $ENV_NAME"
  [[ "$DELETE_ENVIRONMENT" == "true" ]] && log "DRY RUN - would delete GitHub environment $ENV_NAME"
  exit 0
fi

# ---- Delete GitHub environment secrets -------------------------------------
for secret in "${SECRET_NAMES[@]}"; do
  if gh secret delete "$secret" --env "$ENV_NAME" --repo "$REPO" 2>/dev/null; then
    log "Deleted secret $secret"
  else
    log "Secret $secret not present or could not be deleted (may already be removed)"
  fi
done

if [[ "$DELETE_ENVIRONMENT" == "true" ]]; then
  ENV_ENC="$(printf '%s' "$ENV_NAME" | python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip(), safe=""))')"
  if gh api --method DELETE "repos/${REPO}/environments/${ENV_ENC}" >/dev/null 2>&1; then
    log "Deleted GitHub environment $ENV_NAME"
  else
    err "Could not delete GitHub environment $ENV_NAME (secrets were still removed)"
  fi
fi

# ---- Update repo tracker ---------------------------------------------------
if [[ -f "$ALLOCATION_FILE" ]]; then
  exec 8>"${ALLOCATION_FILE}.lock"
  if flock -w 30 8; then
    TRACKER_TMP="$(mktemp "$(dirname "$ALLOCATION_FILE")/.wg-peer-allocation.XXXXXX")"
    awk -F '\t' -v env="$ENV_NAME" 'NR == 1 || $1 != env' "$ALLOCATION_FILE" > "$TRACKER_TMP"
    mv "$TRACKER_TMP" "$ALLOCATION_FILE"
    log "Removed $ENV_NAME from $ALLOCATION_FILE"
  else
    err "Could not update tracker file (lock timeout)"
  fi
fi

log "Offboard complete for $ENV_NAME. Peers can be reallocated via wg-onboard.sh with fresh keys."
