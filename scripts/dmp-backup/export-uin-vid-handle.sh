#!/usr/bin/env bash
# Export UIN, VID and Handle details with database traces from qajava21.
#
# Usage:
#   export QAJAVA21_PG_PASSWORD='...'
#   ./export-uin-vid-handle.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

load_config
need psql
resolve_qajava21_pg_password

OUT_DIR="$BACKUP_DIR/traces"
mkdir -p "$OUT_DIR"

export PGPASSWORD="$QAJAVA21_PG_PASSWORD"
export PGHOST="$QAJAVA21_PG_HOST"
export PGPORT="$QAJAVA21_PG_PORT"
export PGUSER="$QAJAVA21_PG_USER"

run_sql() {
  local db="$1"
  local sql_file="$2"
  local out_base="$3"
  log "Running $(basename "$sql_file") against $db ..."
  psql -d "$db" -v ON_ERROR_STOP=1 \
    -f "$sql_file" \
    >"$OUT_DIR/${out_base}.txt" \
    2>"$OUT_DIR/${out_base}.err" || {
      log "WARN: query against $db failed; see $OUT_DIR/${out_base}.err"
      return 0
    }

  # Also CSV for key tables where possible
  case "$db" in
    mosip_idrepo)
      psql -d "$db" -v ON_ERROR_STOP=1 -c "\copy (
        SELECT uin_ref_id, uin, uin_hash, reg_id, bio_ref_id, status_code, cr_dtimes, upd_dtimes, is_deleted
        FROM idrepo.uin WHERE COALESCE(is_deleted,false)=false
      ) TO STDOUT WITH CSV HEADER" >"$OUT_DIR/idrepo_uin.csv" || true
      psql -d "$db" -v ON_ERROR_STOP=1 -c "\copy (
        SELECT id, uin_hash, handle, handle_hash, cr_by, cr_dtimes
        FROM idrepo.handle
      ) TO STDOUT WITH CSV HEADER" >"$OUT_DIR/idrepo_handle.csv" || true
      ;;
    mosip_idmap)
      psql -d "$db" -v ON_ERROR_STOP=1 -c "\copy (
        SELECT id, vid, uin_hash, uin, vidtyp_code, generated_dtimes, expiry_dtimes, status_code, cr_dtimes, is_deleted
        FROM idmap.vid WHERE COALESCE(is_deleted,false)=false
      ) TO STDOUT WITH CSV HEADER" >"$OUT_DIR/idmap_vid.csv" || true
      ;;
  esac
}

run_sql mosip_idrepo "$SCRIPT_DIR/sql/uin-vid-handle-traces.sql" "uin-handle-traces"
run_sql mosip_idmap  "$SCRIPT_DIR/sql/vid-traces.sql" "vid-traces"

# Per-module table discovery for correlation
for db in mosip_regprc mosip_credential mosip_ida mosip_resident; do
  log "Discovering identity-related tables in $db ..."
  psql -d "$db" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/sql/related-module-traces.sql" \
    >"$OUT_DIR/${db}-tables.txt" 2>"$OUT_DIR/${db}-tables.err" || \
    log "WARN: discovery against $db failed"
done

# Cross-db summary (UIN hash -> VID count + handle count) written as a readable report
cat >"$OUT_DIR/README-traces.md" <<EOF
# UIN / VID / Handle traces

Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Host: $QAJAVA21_PG_HOST:$QAJAVA21_PG_PORT

## Primary tables

| Identity | Database | Schema.table | Notes |
|----------|----------|--------------|-------|
| UIN | mosip_idrepo | idrepo.uin | Demographic JSON in uin_data; uin/uin_hash columns |
| Handle | mosip_idrepo | idrepo.handle | handle + handle_hash mapped to uin_hash |
| VID | mosip_idmap | idmap.vid | vid mapped to uin_hash / encrypted uin |

## Files

- \`uin-handle-traces.txt\` — formatted UIN + Handle query output
- \`vid-traces.txt\` — formatted VID query output
- \`idrepo_uin.csv\` / \`idrepo_handle.csv\` / \`idmap_vid.csv\` — CSV extracts
- \`mosip_*-tables.txt\` — related table discovery in regprc/credential/ida/resident

## Correlation key

Join on \`uin_hash\` across \`idrepo.uin\`, \`idrepo.handle\`, and \`idmap.vid\`.
EOF

write_manifest "uin-vid-handle-traces" \
  "host=$QAJAVA21_PG_HOST:$QAJAVA21_PG_PORT" \
  "out=$OUT_DIR"

log "UIN/VID/Handle export complete: $OUT_DIR"
