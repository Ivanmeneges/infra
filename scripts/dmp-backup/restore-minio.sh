#!/usr/bin/env bash
# Restore MinIO buckets from a local DMP backup directory into a target MinIO.
#
# This is the standard MOSIP / MinIO Client restore process:
#   1) mc alias set <target>
#   2) for each bucket: mc mb --ignore-existing; mc mirror <local>/<bucket> <target>/<bucket>
#
# Usage:
#   export RESTORE_MINIO_URL='http://minio.target:9000'
#   export RESTORE_MINIO_ACCESS_KEY='admin'
#   export RESTORE_MINIO_SECRET_KEY='...'
#   export RESTORE_BACKUP_DIR='./backups/<stamp>/minio'
#   ./restore-minio.sh
#
# Dry-run (list only):
#   DRY_RUN=1 ./restore-minio.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

load_config
need mc

RESTORE_MINIO_ALIAS="${RESTORE_MINIO_ALIAS:-restore-target}"
RESTORE_MINIO_URL="${RESTORE_MINIO_URL:-}"
RESTORE_MINIO_ACCESS_KEY="${RESTORE_MINIO_ACCESS_KEY:-}"
RESTORE_MINIO_SECRET_KEY="${RESTORE_MINIO_SECRET_KEY:-}"
RESTORE_BACKUP_DIR="${RESTORE_BACKUP_DIR:-}"
DRY_RUN="${DRY_RUN:-0}"

[[ -n "$RESTORE_MINIO_URL" ]] || die "RESTORE_MINIO_URL is required"
[[ -n "$RESTORE_MINIO_ACCESS_KEY" ]] || die "RESTORE_MINIO_ACCESS_KEY is required"
[[ -n "$RESTORE_MINIO_SECRET_KEY" ]] || die "RESTORE_MINIO_SECRET_KEY is required"
[[ -n "$RESTORE_BACKUP_DIR" ]] || die "RESTORE_BACKUP_DIR is required (path to .../minio backup folder)"
[[ -d "$RESTORE_BACKUP_DIR" ]] || die "RESTORE_BACKUP_DIR does not exist: $RESTORE_BACKUP_DIR"

log "Setting mc alias '$RESTORE_MINIO_ALIAS' -> $RESTORE_MINIO_URL"
mc alias set "$RESTORE_MINIO_ALIAS" "$RESTORE_MINIO_URL" \
  "$RESTORE_MINIO_ACCESS_KEY" "$RESTORE_MINIO_SECRET_KEY" --api S3v4 >/dev/null

log "Target buckets currently:"
mc ls "$RESTORE_MINIO_ALIAS" || true

# Prefer bucket directories that look like backups (skip log/status files)
mapfile -t buckets < <(find "$RESTORE_BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)

if [[ ${#buckets[@]} -eq 0 ]]; then
  die "No bucket directories found under $RESTORE_BACKUP_DIR"
fi

log "Will restore ${#buckets[@]} bucket(s): ${buckets[*]}"

for bucket in "${buckets[@]}"; do
  src="$RESTORE_BACKUP_DIR/$bucket"
  dst="$RESTORE_MINIO_ALIAS/$bucket"
  log "---- Restore $bucket ----"
  log "  source: $src"
  log "  target: $dst"

  if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY_RUN: would run: mc mb --ignore-existing $dst"
    log "DRY_RUN: would run: mc mirror --preserve $src $dst"
    continue
  fi

  mc mb --ignore-existing "$dst"
  mc mirror --preserve "$src" "$dst" | tee "$RESTORE_BACKUP_DIR/${bucket}.restore.log"
  mc ls --recursive "$dst" | tee "$RESTORE_BACKUP_DIR/${bucket}.restored-listing.txt" >/dev/null
  log "Restored bucket: $bucket"
done

log "MinIO restore complete."
log ""
log "Manual one-liner equivalent (official MOSIP pattern):"
log "  MINIO_SERVER=$RESTORE_MINIO_ALIAS"
log "  MINIO_BACKUP_DIR=$RESTORE_BACKUP_DIR"
log '  for bucket in $(ls "$MINIO_BACKUP_DIR"); do'
log '    [[ -d "$MINIO_BACKUP_DIR/$bucket" ]] || continue'
log '    mc mb --ignore-existing "$MINIO_SERVER/$bucket"'
log '    mc mirror "$MINIO_BACKUP_DIR/$bucket" "$MINIO_SERVER/$bucket"'
log '  done'
