#!/usr/bin/env bash
# Run the full DMP internship backup suite for qajava21 (+ collab schema-only).
#
# Prerequisites:
#   1. WireGuard connected to the target environment(s)
#   2. Tools: psql/pg_dump, mc (MinIO client), optional kubectl
#   3. Credentials via env or config.env (see config.env.example)
#
# Usage:
#   cp config.env.example config.env   # edit secrets
#   ./run-all.sh
#
# Selective:
#   ./run-all.sh postgres
#   ./run-all.sh minio
#   ./run-all.sh schema
#   ./run-all.sh traces
#   ./run-all.sh rids
#   ./run-all.sh postgres minio traces rids
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

load_config

TARGETS=("$@")
if [[ ${#TARGETS[@]} -eq 0 ]]; then
  TARGETS=(postgres schema traces rids minio)
fi

log "DMP internship backup starting"
log "BACKUP_DIR=$BACKUP_DIR"
log "Targets: ${TARGETS[*]}"

run_one() {
  local name="$1"
  local script="$2"
  log "======== BEGIN $name ========"
  bash "$script"
  log "======== END $name ========"
}

for t in "${TARGETS[@]}"; do
  case "$t" in
    postgres) run_one postgres "$SCRIPT_DIR/backup-postgres.sh" ;;
    schema)   run_one schema   "$SCRIPT_DIR/backup-self-registration-schema.sh" ;;
    traces)   run_one traces   "$SCRIPT_DIR/export-uin-vid-handle.sh" ;;
    rids)     run_one rids     "$SCRIPT_DIR/export-rids-uin-vid.sh" ;;
    minio)    run_one minio    "$SCRIPT_DIR/backup-minio.sh" ;;
    *) die "Unknown target: $t (use postgres|schema|traces|rids|minio)" ;;
  esac
done

# Package archive for hand-off
ARCHIVE="$BACKUP_ROOT/dmp-qajava21-backup-${BACKUP_STAMP}.tar.gz"
log "Creating archive $ARCHIVE"
tar -C "$BACKUP_ROOT" -czf "$ARCHIVE" "$BACKUP_STAMP"
sha256sum "$ARCHIVE" | tee "$ARCHIVE.sha256"

cat >"$BACKUP_DIR/SUMMARY.md" <<EOF
# DMP internship backup summary

- Stamp: \`$BACKUP_STAMP\`
- Archive: \`$ARCHIVE\`
- Targets: ${TARGETS[*]}

## Contents

| Path | Description |
|------|-------------|
| postgres/qajava21/ | Full dumps: mosip_regprc, mosip_credential, mosip_idmap, mosip_idrepo, mosip_ida, mosip_resident |
| postgres/collab/ | Schema-only CREATE script for inji_certify_tan.self_registration (no data) |
| traces/ | UIN / VID / Handle CSV + query output |
| traces/rids-13july/ | Targeted traces for RIDs_13July.xlsx (RID/UIN/VID correlation) |
| minio/ | Selected buckets (prefer last ${MINIO_NEWER_THAN} objects) |

## MinIO restore

See \`docs/DMP_INTERNSHIP_BACKUP_GUIDE.md\` or run:

\`\`\`bash
export RESTORE_MINIO_URL='http://minio.target:9000'
export RESTORE_MINIO_ACCESS_KEY='...'
export RESTORE_MINIO_SECRET_KEY='...'
export RESTORE_BACKUP_DIR='$BACKUP_DIR/minio'
$SCRIPT_DIR/restore-minio.sh
\`\`\`
EOF

log "All done. Summary: $BACKUP_DIR/SUMMARY.md"
log "Archive: $ARCHIVE"
