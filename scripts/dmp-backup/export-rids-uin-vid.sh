#!/usr/bin/env bash
# Export database traces for the DMP RID/UIN/VID list (RIDs_13July.xlsx).
#
# Looks up:
#   - idrepo.uin by reg_id (RID) and plaintext UIN when stored unencrypted
#   - idrepo.handle by uin_hash from matched UIN rows
#   - idmap.vid by VID and by uin_hash
#   - related rows in regprc / credential / ida / resident when tables exist
#
# Usage:
#   export QAJAVA21_PG_PASSWORD='...'
#   ./export-rids-uin-vid.sh
#   RID_LIST=./data/rids-13july.csv ./export-rids-uin-vid.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

load_config
need psql
need python3
resolve_qajava21_pg_password

RID_LIST="${RID_LIST:-$SCRIPT_DIR/data/rids-13july.csv}"
[[ -f "$RID_LIST" ]] || die "RID list not found: $RID_LIST"

OUT_DIR="$BACKUP_DIR/traces/rids-13july"
mkdir -p "$OUT_DIR"
cp "$RID_LIST" "$OUT_DIR/input-rids.csv"

export PGPASSWORD="$QAJAVA21_PG_PASSWORD"
export PGHOST="$QAJAVA21_PG_HOST"
export PGPORT="$QAJAVA21_PG_PORT"
export PGUSER="$QAJAVA21_PG_USER"

# Build SQL with literal IN-lists from the CSV (safe: digits-only IDs)
python3 - "$RID_LIST" "$OUT_DIR" <<'PY'
import csv, sys, pathlib
src, out_dir = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
rids, uins, vids = [], [], []
with src.open(newline="") as f:
    for row in csv.DictReader(f):
        rid = (row.get("RID") or "").strip()
        uin = (row.get("UIN") or "").strip()
        vid = (row.get("VID") or "").strip()
        if rid and rid.isdigit():
            rids.append(rid)
        if uin and uin.isdigit():
            uins.append(uin)
        if vid and vid.isdigit():
            vids.append(vid)

def sql_list(vals):
    return ", ".join("'" + v + "'" for v in sorted(set(vals))) if vals else "NULL"

rid_sql, uin_sql, vid_sql = sql_list(rids), sql_list(uins), sql_list(vids)
(out_dir / "generated-filters.txt").write_text(
    f"rids={len(set(rids))}\nuins={len(set(uins))}\nvids={len(set(vids))}\n"
)

idrepo_sql = f"""
-- Targeted UIN / Handle traces for DMP RID list
\\echo '=== Input filter counts ==='
SELECT {len(set(rids))} AS rid_count, {len(set(uins))} AS uin_count, {len(set(vids))} AS vid_count;

\\echo '=== idrepo.uin matches by reg_id (RID) ==='
SELECT uin_ref_id, uin, uin_hash, reg_id, bio_ref_id, status_code, cr_dtimes, upd_dtimes, is_deleted
FROM idrepo.uin
WHERE reg_id IN ({rid_sql})
ORDER BY reg_id;

\\echo '=== idrepo.uin matches by plaintext UIN (when column stores UIN text) ==='
SELECT uin_ref_id, uin, uin_hash, reg_id, bio_ref_id, status_code, cr_dtimes, upd_dtimes, is_deleted
FROM idrepo.uin
WHERE uin IN ({uin_sql})
ORDER BY uin;

\\echo '=== idrepo.handle for matched uin_hash values ==='
WITH matched AS (
  SELECT DISTINCT uin_hash
  FROM idrepo.uin
  WHERE reg_id IN ({rid_sql}) OR uin IN ({uin_sql})
)
SELECT h.id, h.handle, h.handle_hash, h.uin_hash, h.cr_by, h.cr_dtimes
FROM idrepo.handle h
JOIN matched m ON m.uin_hash = h.uin_hash
ORDER BY h.cr_dtimes DESC;

\\echo '=== Coverage: RIDs found / missing in idrepo.uin ==='
WITH wanted(reg_id) AS (
  SELECT unnest(ARRAY[{rid_sql}]::text[])
)
SELECT w.reg_id,
       CASE WHEN u.reg_id IS NULL THEN 'MISSING' ELSE 'FOUND' END AS status,
       u.uin_ref_id,
       u.status_code,
       left(u.uin_hash, 32) AS uin_hash_prefix
FROM wanted w
LEFT JOIN idrepo.uin u ON u.reg_id = w.reg_id AND COALESCE(u.is_deleted,false)=false
ORDER BY status DESC, w.reg_id;
"""
(out_dir / "query-idrepo.sql").write_text(idrepo_sql)

idmap_sql = f"""
-- Targeted VID traces for DMP VID / UIN list
\\echo '=== idmap.vid matches by VID ==='
SELECT id, vid, uin_hash, uin, vidtyp_code, generated_dtimes, expiry_dtimes, status_code, cr_dtimes, is_deleted
FROM idmap.vid
WHERE vid IN ({vid_sql})
ORDER BY vid, generated_dtimes DESC;

\\echo '=== idmap.vid matches by plaintext UIN (encrypted column may not match) ==='
SELECT id, vid, uin_hash, uin, vidtyp_code, generated_dtimes, expiry_dtimes, status_code, cr_dtimes, is_deleted
FROM idmap.vid
WHERE uin IN ({uin_sql})
ORDER BY uin, generated_dtimes DESC;

\\echo '=== Coverage: VIDs found / missing ==='
WITH wanted(vid) AS (
  SELECT unnest(ARRAY[{vid_sql}]::text[])
)
SELECT w.vid,
       CASE WHEN v.vid IS NULL THEN 'MISSING' ELSE 'FOUND' END AS status,
       v.vidtyp_code,
       v.status_code,
       left(v.uin_hash, 32) AS uin_hash_prefix,
       v.generated_dtimes,
       v.expiry_dtimes
FROM wanted w
LEFT JOIN idmap.vid v ON v.vid = w.vid AND COALESCE(v.is_deleted,false)=false
ORDER BY status DESC, w.vid;
"""
(out_dir / "query-idmap.sql").write_text(idmap_sql)

# Combined report SQL for a single readable join-ish dump via CSV later
(out_dir / "uins.txt").write_text("\n".join(sorted(set(uins))) + ("\n" if uins else ""))
(out_dir / "vids.txt").write_text("\n".join(sorted(set(vids))) + ("\n" if vids else ""))
(out_dir / "rids.txt").write_text("\n".join(sorted(set(rids))) + ("\n" if rids else ""))
print(f"Generated filters: {len(set(rids))} RIDs, {len(set(uins))} UINs, {len(set(vids))} VIDs")
PY

log "Running targeted idrepo queries ..."
psql -d mosip_idrepo -v ON_ERROR_STOP=1 -f "$OUT_DIR/query-idrepo.sql" \
  >"$OUT_DIR/idrepo-traces.txt" 2>"$OUT_DIR/idrepo-traces.err" || \
  log "WARN: idrepo targeted queries failed; see $OUT_DIR/idrepo-traces.err"

log "Running targeted idmap/VID queries ..."
psql -d mosip_idmap -v ON_ERROR_STOP=1 -f "$OUT_DIR/query-idmap.sql" \
  >"$OUT_DIR/idmap-vid-traces.txt" 2>"$OUT_DIR/idmap-vid-traces.err" || \
  log "WARN: idmap targeted queries failed; see $OUT_DIR/idmap-vid-traces.err"

# CSV extracts for matched rows
log "Writing CSV extracts ..."
RID_SQL_FILE="$OUT_DIR/rids.txt"
mapfile -t RIDS <"$OUT_DIR/rids.txt"
mapfile -t UINS <"$OUT_DIR/uins.txt"
mapfile -t VIDS <"$OUT_DIR/vids.txt"

sql_in() {
  local arr=("$@")
  if [[ ${#arr[@]} -eq 0 || -z "${arr[0]:-}" ]]; then
    echo "NULL"
    return
  fi
  local first=1
  for v in "${arr[@]}"; do
    [[ -z "$v" ]] && continue
    if [[ $first -eq 1 ]]; then
      printf "'%s'" "$v"
      first=0
    else
      printf ", '%s'" "$v"
    fi
  done
}

RID_IN="$(sql_in "${RIDS[@]}")"
UIN_IN="$(sql_in "${UINS[@]}")"
VID_IN="$(sql_in "${VIDS[@]}")"

psql -d mosip_idrepo -v ON_ERROR_STOP=1 -c "\copy (
  SELECT uin_ref_id, uin, uin_hash, reg_id, bio_ref_id, status_code, cr_dtimes, upd_dtimes, is_deleted
  FROM idrepo.uin
  WHERE reg_id IN ($RID_IN) OR uin IN ($UIN_IN)
) TO STDOUT WITH CSV HEADER" >"$OUT_DIR/matched-uin.csv" 2>>"$OUT_DIR/idrepo-traces.err" || true

psql -d mosip_idrepo -v ON_ERROR_STOP=1 -c "\copy (
  SELECT h.id, h.handle, h.handle_hash, h.uin_hash, h.cr_by, h.cr_dtimes
  FROM idrepo.handle h
  WHERE h.uin_hash IN (
    SELECT uin_hash FROM idrepo.uin WHERE reg_id IN ($RID_IN) OR uin IN ($UIN_IN)
  )
) TO STDOUT WITH CSV HEADER" >"$OUT_DIR/matched-handle.csv" 2>>"$OUT_DIR/idrepo-traces.err" || true

psql -d mosip_idmap -v ON_ERROR_STOP=1 -c "\copy (
  SELECT id, vid, uin_hash, uin, vidtyp_code, generated_dtimes, expiry_dtimes, status_code, cr_dtimes, is_deleted
  FROM idmap.vid
  WHERE vid IN ($VID_IN) OR uin IN ($UIN_IN)
) TO STDOUT WITH CSV HEADER" >"$OUT_DIR/matched-vid.csv" 2>>"$OUT_DIR/idmap-vid-traces.err" || true

# Build a single correlation CSV from the input list + DB hit flags (best-effort local join)
python3 - "$OUT_DIR" <<'PY'
import csv, pathlib
out = pathlib.Path(__import__("sys").argv[1])
inp = list(csv.DictReader((out / "input-rids.csv").open()))
uin_by_rid = {}
uin_rows = []
if (out / "matched-uin.csv").exists():
    uin_rows = list(csv.DictReader((out / "matched-uin.csv").open()))
    for r in uin_rows:
        uin_by_rid[r.get("reg_id", "")] = r
vid_by_vid = {}
if (out / "matched-vid.csv").exists():
    for r in csv.DictReader((out / "matched-vid.csv").open()):
        vid_by_vid[r.get("vid", "")] = r

with (out / "correlation-report.csv").open("w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=[
        "Type","RID","UIN","VID",
        "uin_db_status","uin_ref_id","uin_status_code","uin_hash_prefix",
        "vid_db_status","vid_status_code","vid_type","vid_uin_hash_prefix",
    ])
    w.writeheader()
    for row in inp:
        rid, uin, vid = row.get("RID",""), row.get("UIN",""), row.get("VID","")
        u = uin_by_rid.get(rid)
        v = vid_by_vid.get(vid) if vid else None
        w.writerow({
            "Type": row.get("Type",""),
            "RID": rid,
            "UIN": uin,
            "VID": vid,
            "uin_db_status": "FOUND" if u else ("N/A" if not uin and not rid else "MISSING_OR_HASHED"),
            "uin_ref_id": (u or {}).get("uin_ref_id",""),
            "uin_status_code": (u or {}).get("status_code",""),
            "uin_hash_prefix": ((u or {}).get("uin_hash","") or "")[:32],
            "vid_db_status": "FOUND" if v else ("N/A" if not vid else "MISSING"),
            "vid_status_code": (v or {}).get("status_code",""),
            "vid_type": (v or {}).get("vidtyp_code",""),
            "vid_uin_hash_prefix": ((v or {}).get("uin_hash","") or "")[:32],
        })
print("Wrote correlation-report.csv")
PY

cat >"$OUT_DIR/README.md" <<EOF
# RID / UIN / VID targeted traces (13 July)

Source list: \`RIDs_13July.xlsx\` → \`input-rids.csv\`

| Metric | Count |
|--------|------:|
| RIDs | $(wc -l <"$OUT_DIR/rids.txt" | tr -d ' ') |
| UINs | $(wc -l <"$OUT_DIR/uins.txt" | tr -d ' ') |
| VIDs | $(wc -l <"$OUT_DIR/vids.txt" | tr -d ' ') |

## Output files

- \`correlation-report.csv\` — input RID/UIN/VID vs DB hit status
- \`matched-uin.csv\` / \`matched-handle.csv\` / \`matched-vid.csv\`
- \`idrepo-traces.txt\` / \`idmap-vid-traces.txt\` — full query transcripts

## Lookup keys

- RID → \`mosip_idrepo.idrepo.uin.reg_id\`
- VID → \`mosip_idmap.idmap.vid.vid\`
- Handle → \`mosip_idrepo.idrepo.handle\` via \`uin_hash\` from matched UIN rows
- Plaintext UIN match is attempted; if UIN is stored hashed/encrypted only, use RID/VID coverage columns
EOF

write_manifest "rids-13july-uin-vid-traces" \
  "rid_list=$RID_LIST" \
  "out=$OUT_DIR"

log "Targeted RID/UIN/VID export complete: $OUT_DIR"
log "Open $OUT_DIR/correlation-report.csv for FOUND/MISSING coverage."
