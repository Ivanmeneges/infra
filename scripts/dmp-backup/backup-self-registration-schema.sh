#!/usr/bin/env bash
# Obtain CREATE script for collab: inji_certify_tan.self_registration (NO DATA).
#
# Usage:
#   export COLLAB_PG_PASSWORD='...'
#   ./backup-self-registration-schema.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

load_config
need pg_dump
need psql
resolve_collab_pg_password

OUT_DIR="$BACKUP_DIR/postgres/collab"
mkdir -p "$OUT_DIR"

export PGPASSWORD="$COLLAB_PG_PASSWORD"
export PGHOST="$COLLAB_PG_HOST"
export PGPORT="$COLLAB_PG_PORT"
export PGUSER="$COLLAB_PG_USER"

log "Testing collab Postgres connectivity to $PGHOST:$PGPORT db=$COLLAB_DB_NAME ..."
psql -d "$COLLAB_DB_NAME" -v ON_ERROR_STOP=1 -c 'SELECT current_database(), current_user;' \
  >"$OUT_DIR/connectivity.txt"

# Discover whether self_registration is a schema, a table, or schema.table
log "Discovering object type for self_registration in $COLLAB_DB_NAME ..."
psql -d "$COLLAB_DB_NAME" -v ON_ERROR_STOP=1 -At <<'SQL' >"$OUT_DIR/object-discovery.txt"
SELECT 'schema|' || nspname
FROM pg_namespace
WHERE nspname = 'self_registration'
UNION ALL
SELECT 'table|' || schemaname || '.' || tablename
FROM pg_tables
WHERE tablename = 'self_registration'
   OR schemaname = 'self_registration'
ORDER BY 1;
SQL

cat "$OUT_DIR/object-discovery.txt"

SCHEMA_ONLY_FILE="$OUT_DIR/inji_certify_tan.self_registration.schema-only.sql"

if [[ -n "${COLLAB_TABLE_NAME}" ]]; then
  log "Dumping schema-only for table ${COLLAB_SCHEMA_NAME}.${COLLAB_TABLE_NAME} (no data)"
  pg_dump \
    --dbname="$COLLAB_DB_NAME" \
    --schema-only \
    --no-owner \
    --no-privileges \
    --table="${COLLAB_SCHEMA_NAME}.${COLLAB_TABLE_NAME}" \
    --file="$SCHEMA_ONLY_FILE"
elif psql -d "$COLLAB_DB_NAME" -Atc "SELECT 1 FROM pg_namespace WHERE nspname='self_registration'" | grep -q 1; then
  log "Dumping schema-only for schema self_registration (no data)"
  pg_dump \
    --dbname="$COLLAB_DB_NAME" \
    --schema-only \
    --no-owner \
    --no-privileges \
    --schema=self_registration \
    --file="$SCHEMA_ONLY_FILE"
elif psql -d "$COLLAB_DB_NAME" -Atc "SELECT 1 FROM pg_tables WHERE tablename='self_registration' LIMIT 1" | grep -q 1; then
  fq="$(psql -d "$COLLAB_DB_NAME" -Atc "SELECT schemaname||'.'||tablename FROM pg_tables WHERE tablename='self_registration' LIMIT 1")"
  log "Dumping schema-only for table $fq (no data)"
  pg_dump \
    --dbname="$COLLAB_DB_NAME" \
    --schema-only \
    --no-owner \
    --no-privileges \
    --table="$fq" \
    --file="$SCHEMA_ONLY_FILE"
else
  die "Could not find self_registration as schema or table in database $COLLAB_DB_NAME. See $OUT_DIR/object-discovery.txt"
fi

# Ensure the dump contains no COPY/INSERT data lines (defense in depth)
if grep -Eiq '^(COPY |INSERT INTO )' "$SCHEMA_ONLY_FILE"; then
  die "Schema-only dump unexpectedly contains data statements: $SCHEMA_ONLY_FILE"
fi

sha256sum "$SCHEMA_ONLY_FILE" >"$OUT_DIR/SHA256SUMS"

write_manifest "postgres-collab-schema-only" \
  "host=$COLLAB_PG_HOST:$COLLAB_PG_PORT" \
  "database=$COLLAB_DB_NAME" \
  "object=self_registration" \
  "mode=schema-only (no data)" \
  "out=$SCHEMA_ONLY_FILE"

log "Collab schema-only dump complete: $SCHEMA_ONLY_FILE"
