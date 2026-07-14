#!/usr/bin/env bash
# Backup selected MinIO buckets from qajava21 (prefer objects newer than MINIO_NEWER_THAN).
#
# Usage:
#   export QAJAVA21_MINIO_ACCESS_KEY=admin
#   export QAJAVA21_MINIO_SECRET_KEY='...'
#   # or KUBECONFIG with access to minio/minio secret
#   ./backup-minio.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

load_config
need mc
resolve_minio_creds

OUT_DIR="$BACKUP_DIR/minio"
mkdir -p "$OUT_DIR"

# Prefer S3 API endpoint; fall back to HTTPS console host if needed
MINIO_ENDPOINT="${QAJAVA21_MINIO_API}"
log "Configuring mc alias '$MINIO_ALIAS' -> $MINIO_ENDPOINT"
if ! mc alias set "$MINIO_ALIAS" "$MINIO_ENDPOINT" \
    "$QAJAVA21_MINIO_ACCESS_KEY" "$QAJAVA21_MINIO_SECRET_KEY" --api S3v4 >/dev/null; then
  MINIO_ENDPOINT="${QAJAVA21_MINIO_URL:-https://minio.qajava21.mosip.net}"
  log "Retrying alias with $MINIO_ENDPOINT"
  mc alias set "$MINIO_ALIAS" "$MINIO_ENDPOINT" \
    "$QAJAVA21_MINIO_ACCESS_KEY" "$QAJAVA21_MINIO_SECRET_KEY" --api S3v4 >/dev/null
fi

mc alias list "$MINIO_ALIAS" | tee "$OUT_DIR/alias.txt"
mc ls "$MINIO_ALIAS" | tee "$OUT_DIR/bucket-list.txt" || true

backup_bucket() {
  local bucket="$1"
  local dest="$OUT_DIR/$bucket"
  mkdir -p "$dest"

  if ! mc ls "$MINIO_ALIAS/$bucket" >/dev/null 2>&1; then
    log "WARN: bucket not found or inaccessible: $bucket (skipping)"
    echo "$bucket SKIPPED" >>"$OUT_DIR/bucket-status.txt"
    return 0
  fi

  log "Backing up bucket '$bucket' (objects newer than $MINIO_NEWER_THAN when supported)"

  # mc mirror --newer-than is available on recent mc clients; fall back to full mirror.
  if mc mirror --help 2>&1 | grep -q -- '--newer-than'; then
    mc mirror --newer-than "$MINIO_NEWER_THAN" --preserve \
      "$MINIO_ALIAS/$bucket" "$dest" \
      2>&1 | tee "$OUT_DIR/${bucket}.mirror.log"
  else
    log "WARN: mc mirror --newer-than unsupported; using mc find + cp for last $MINIO_NEWER_THAN"
    # List and copy objects newer than window
    mapfile -t objects < <(mc find "$MINIO_ALIAS/$bucket" --newer-than "$MINIO_NEWER_THAN" 2>/dev/null || true)
    if [[ ${#objects[@]} -eq 0 ]]; then
      log "No objects newer than $MINIO_NEWER_THAN in $bucket; taking full mirror as fallback"
      mc mirror --preserve "$MINIO_ALIAS/$bucket" "$dest" \
        2>&1 | tee "$OUT_DIR/${bucket}.mirror.log"
    else
      for obj in "${objects[@]}"; do
        # Strip alias/bucket prefix to preserve relative key path
        rel="${obj#${MINIO_ALIAS}/${bucket}/}"
        mkdir -p "$dest/$(dirname "$rel")"
        mc cp "$obj" "$dest/$rel" >/dev/null
      done
      printf '%s\n' "${objects[@]}" >"$OUT_DIR/${bucket}.objects.txt"
    fi
  fi

  # Inventory
  mc ls --recursive "$MINIO_ALIAS/$bucket" >"$OUT_DIR/${bucket}.remote-listing.txt" || true
  find "$dest" -type f | wc -l | awk -v b="$bucket" '{print b, "local_files="$1}' >>"$OUT_DIR/bucket-status.txt"
  du -sh "$dest" >>"$OUT_DIR/sizes.txt"
  echo "$bucket OK" >>"$OUT_DIR/bucket-status.txt"
}

for bucket in $MINIO_BUCKETS; do
  backup_bucket "$bucket"
done

(
  cd "$OUT_DIR"
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum >SHA256SUMS 2>/dev/null || true
)

write_manifest "minio-qajava21" \
  "endpoint=$MINIO_ENDPOINT" \
  "newer_than=$MINIO_NEWER_THAN" \
  "buckets=$MINIO_BUCKETS" \
  "out=$OUT_DIR"

log "MinIO backup complete: $OUT_DIR"
log "See restore-minio.sh for restore commands."
