#!/usr/bin/env bash
# Dump qajava21 Postgres databases required for DMP internship work.
#
# Usage:
#   export QAJAVA21_PG_PASSWORD='...'
#   # optional: export KUBECONFIG=...
#   ./backup-postgres.sh
#
# Or with config file:
#   CONFIG_FILE=./config.env ./backup-postgres.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

load_config
need pg_dump
need pg_dumpall
resolve_qajava21_pg_password

OUT_DIR="$BACKUP_DIR/postgres/qajava21"
mkdir -p "$OUT_DIR"

export PGPASSWORD="$QAJAVA21_PG_PASSWORD"
export PGHOST="$QAJAVA21_PG_HOST"
export PGPORT="$QAJAVA21_PG_PORT"
export PGUSER="$QAJAVA21_PG_USER"

log "Testing Postgres connectivity to $PGHOST:$PGPORT ..."
psql -d postgres -v ON_ERROR_STOP=1 -c 'SELECT current_database(), current_user, version();' \
  >"$OUT_DIR/connectivity.txt"

# Roles/globals (no passwords) help restore into a fresh instance
log "Dumping global roles (no passwords) ..."
pg_dumpall --globals-only --no-role-passwords >"$OUT_DIR/globals-roles.sql" || \
  log "WARN: globals dump failed (continuing with database dumps)"

for db in $QAJAVA21_DATABASES; do
  log "Dumping database: $db"
  pg_dump \
    --dbname="$db" \
    --format=custom \
    --blobs \
    --verbose \
    --file="$OUT_DIR/${db}.dump" \
    2>"$OUT_DIR/${db}.pg_dump.log"

  # Also keep a plain SQL dump for easier inspection of UIN/VID/Handle traces
  pg_dump \
    --dbname="$db" \
    --format=plain \
    --no-owner \
    --no-privileges \
    --file="$OUT_DIR/${db}.sql" \
    2>>"$OUT_DIR/${db}.pg_dump.log"

  # Size summary
  du -h "$OUT_DIR/${db}.dump" "$OUT_DIR/${db}.sql" >>"$OUT_DIR/sizes.txt"
done

# Convenience checksums
(
  cd "$OUT_DIR"
  sha256sum ./*.dump ./*.sql globals-roles.sql 2>/dev/null >SHA256SUMS || true
)

write_manifest "postgres-qajava21" \
  "host=$QAJAVA21_PG_HOST:$QAJAVA21_PG_PORT" \
  "databases=$QAJAVA21_DATABASES" \
  "out=$OUT_DIR"

log "Postgres backup complete: $OUT_DIR"
log "Restore example: pg_restore -h <host> -p <port> -U postgres -d mosip_idrepo --clean --if-exists $OUT_DIR/mosip_idrepo.dump"
