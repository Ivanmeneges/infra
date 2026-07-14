#!/usr/bin/env bash
# Shared helpers for DMP internship backup scripts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
die()  { log "ERROR: $*"; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

load_config() {
  local cfg="${CONFIG_FILE:-$SCRIPT_DIR/config.env}"
  if [[ -f "$cfg" ]]; then
    # shellcheck disable=SC1090
    set -a; source "$cfg"; set +a
    log "Loaded config: $cfg"
  elif [[ -f "$SCRIPT_DIR/config.env.example" ]]; then
    log "No config.env found; using defaults from environment / example values"
  fi

  BACKUP_ROOT="${BACKUP_ROOT:-$SCRIPT_DIR/backups}"
  BACKUP_STAMP="${BACKUP_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"
  BACKUP_DIR="${BACKUP_DIR:-$BACKUP_ROOT/$BACKUP_STAMP}"
  mkdir -p "$BACKUP_DIR"

  QAJAVA21_PG_HOST="${QAJAVA21_PG_HOST:-postgres.qajava21.mosip.net}"
  QAJAVA21_PG_PORT="${QAJAVA21_PG_PORT:-5433}"
  QAJAVA21_PG_USER="${QAJAVA21_PG_USER:-postgres}"
  QAJAVA21_DATABASES="${QAJAVA21_DATABASES:-mosip_regprc mosip_credential mosip_idmap mosip_idrepo mosip_ida mosip_resident}"

  COLLAB_PG_HOST="${COLLAB_PG_HOST:-postgres.collab.mosip.net}"
  COLLAB_PG_PORT="${COLLAB_PG_PORT:-5433}"
  COLLAB_PG_USER="${COLLAB_PG_USER:-postgres}"
  COLLAB_DB_NAME="${COLLAB_DB_NAME:-inji_certify_tan}"
  COLLAB_SCHEMA_NAME="${COLLAB_SCHEMA_NAME:-self_registration}"
  COLLAB_TABLE_NAME="${COLLAB_TABLE_NAME:-}"

  QAJAVA21_MINIO_API="${QAJAVA21_MINIO_API:-http://minio.qajava21.mosip.net:9000}"
  MINIO_ALIAS="${MINIO_ALIAS:-qajava21}"
  MINIO_NEWER_THAN="${MINIO_NEWER_THAN:-3d}"
  MINIO_BUCKETS="${MINIO_BUCKETS:-landing-zone packet-manager idrepo mpolicy-default-abis mpolicy-default-auth mpolicy-default-digitalcard mpolicy-default-euin mpolicy-default-pdfcard mpolicy-default-qrcode mpolicy-default-reprint mpolicy-default-resident}"
}

kube_available() {
  [[ -n "${KUBECONFIG:-}" ]] && command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1
}

resolve_qajava21_pg_password() {
  if [[ -n "${QAJAVA21_PG_PASSWORD:-}" ]]; then
    return 0
  fi
  if kube_available; then
    # Bitnami / MOSIP postgres secret patterns
    for ns_secret_key in \
      "postgres:postgres-postgresql:postgres-password" \
      "postgres:postgres-postgresql:password" \
      "postgres:postgres:postgres-password"; do
      IFS=':' read -r ns secret key <<<"$ns_secret_key"
      if kubectl -n "$ns" get secret "$secret" >/dev/null 2>&1; then
        local val
        val="$(kubectl -n "$ns" get secret "$secret" -o "jsonpath={.data.$key}" 2>/dev/null | base64 -d || true)"
        if [[ -n "$val" ]]; then
          QAJAVA21_PG_PASSWORD="$val"
          log "Resolved QAJAVA21_PG_PASSWORD from secret $ns/$secret ($key)"
          return 0
        fi
      fi
    done
  fi
  die "QAJAVA21_PG_PASSWORD is not set and could not be read from Kubernetes secrets"
}

resolve_collab_pg_password() {
  if [[ -n "${COLLAB_PG_PASSWORD:-}" ]]; then
    return 0
  fi
  die "COLLAB_PG_PASSWORD is not set (required for schema-only dump from collab)"
}

resolve_minio_creds() {
  if [[ -n "${QAJAVA21_MINIO_ACCESS_KEY:-}" && -n "${QAJAVA21_MINIO_SECRET_KEY:-}" ]]; then
    return 0
  fi
  if kube_available; then
    local user pass
    user="$(kubectl -n minio get secret minio -o jsonpath='{.data.root-user}' 2>/dev/null | base64 -d || true)"
    pass="$(kubectl -n minio get secret minio -o jsonpath='{.data.root-password}' 2>/dev/null | base64 -d || true)"
    if [[ -n "$user" && -n "$pass" ]]; then
      QAJAVA21_MINIO_ACCESS_KEY="$user"
      QAJAVA21_MINIO_SECRET_KEY="$pass"
      log "Resolved MinIO credentials from secret minio/minio"
      return 0
    fi
  fi
  die "QAJAVA21_MINIO_ACCESS_KEY / QAJAVA21_MINIO_SECRET_KEY not set and could not be read from Kubernetes"
}

write_manifest() {
  local name="$1"
  local manifest="$BACKUP_DIR/MANIFEST.txt"
  {
    echo "=== $name ==="
    echo "stamp=$BACKUP_STAMP"
    echo "utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "host=$(hostname 2>/dev/null || echo unknown)"
    echo "user=${USER:-unknown}"
    shift || true
    for line in "$@"; do
      echo "$line"
    done
    echo
  } >>"$manifest"
}
