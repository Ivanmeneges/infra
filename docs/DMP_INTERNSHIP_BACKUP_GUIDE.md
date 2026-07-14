# DMP Internship — qajava21 Postgres & MinIO Backup Guide

This guide covers backing up the databases and object-store buckets needed for DMP internship work on **qajava21**, plus a schema-only create script from **collab**, and how to restore MinIO objects.

Scripts live under [`scripts/dmp-backup/`](../scripts/dmp-backup/).

---

## Scope

### Postgres (qajava21) — full data backup

| Module | Database |
|--------|----------|
| Registration Processor | `mosip_regprc` |
| ID Repository | `mosip_credential`, `mosip_idmap`, `mosip_idrepo` |
| IDA | `mosip_ida` |
| Resident Portal | `mosip_resident` |

Host: `postgres.qajava21.mosip.net:5433`

### Postgres (collab) — schema only (no data)

| Module | Object |
|--------|--------|
| Self-registration | `inji_certify_tan.self_registration` |

Host: `postgres.collab.mosip.net:5433`

### MinIO buckets (qajava21) — prefer last 3 days of objects

| Area | Buckets |
|------|---------|
| Registration Processor | `landing-zone`, `packet-manager` |
| ID Repository | `idrepo` |
| Data Sharing | `mpolicy-default-abis`, `mpolicy-default-auth`, `mpolicy-default-digitalcard`, `mpolicy-default-euin`, `mpolicy-default-pdfcard`, `mpolicy-default-qrcode`, `mpolicy-default-reprint` |
| Resident | `mpolicy-default-resident` |

Endpoint: `http://minio.qajava21.mosip.net:9000` (API) / `https://minio.qajava21.mosip.net` (console)

### UIN / VID / Handle traces

| Identity | Database | Table |
|----------|----------|-------|
| UIN | `mosip_idrepo` | `idrepo.uin` |
| Handle | `mosip_idrepo` | `idrepo.handle` |
| VID | `mosip_idmap` | `idmap.vid` |

Correlate on `uin_hash`.

### Targeted list from `RIDs_13July.xlsx`

Normalized copy: [`scripts/dmp-backup/data/rids-13july.csv`](../scripts/dmp-backup/data/rids-13july.csv)

| Metric | Count |
|--------|------:|
| Total RIDs | 20 |
| With UIN + VID | 17 |
| Validation Failed (no UIN/VID) | 3 |

Lookup keys used by `export-rids-uin-vid.sh`:

- RID → `idrepo.uin.reg_id`
- VID → `idmap.vid.vid`
- Handle → `idrepo.handle` via `uin_hash` from matched UIN rows

```bash
export QAJAVA21_PG_PASSWORD='...'
./export-rids-uin-vid.sh
# outputs backups/<stamp>/traces/rids-13july/correlation-report.csv
```

| Type | RID | UIN | VID |
|------|-----|-----|-----|
| Adult-Bio Correction | 10903108821584220260712231041 | 4891398326 | 2704572915925420 |
| Adult | 10903108821585820260712231239 | 2184092593 | 5780147632083970 |
| Adult | 10903108821572320260712222332 | 2073891729 | 5965725821375240 |
| Adult | 10903108821592020260712232406 | 8913683150 | 6159021379310470 |
| Lost | 10903108821593520260712232627 | 8913683150 | 6159021379310470 |
| Adult | 10903108821593620260712232635 | 9281732635 | 5218429037104850 |
| Adult | 10904108831583420260712230914 | 2154173285 | 3124054897281740 |
| Validation Failed | 10904108831582620260712230809 | — | — |
| Validation Failed | 10903108821581220260712230558 | — | — |
| Validation Failed | 10903108821594620260712232803 | — | — |
| Adult | 10903108821583820260712231019 | 5713724507 | 2940928526508430 |
| Adult | 10903108821605120260712234807 | 7134614816 | 8930864179205380 |
| Adult | 10903108821603620260712234609 | 2086136016 | 2615835634951740 |
| Adult | 10903108821598520260712233356 | 3469841754 | 5410867306156480 |
| Adult | 10903108821594120260712232737 | 4017265860 | 3947817261928590 |
| Adult | 10903108821587520260712231540 | 4524157912 | 3821941506329620 |
| Minor | 10903108821588120260712231632 | 9170651931 | 2816239046183170 |
| Lost | 10903108821588520260712231715 | 9170651931 | 2816239046183170 |
| Adult | 10903108821586820260712231433 | 2358197521 | 7251637497648600 |
| Infant | 10903108821587420260712231530 | 2041035085 | 5231435680597690 |

---

## Prerequisites

1. **WireGuard** connected to the environment (internal hosts resolve to `172.31.x.x`).
2. Tools installed:
   - `postgresql-client` (`psql`, `pg_dump`, `pg_restore`)
   - [MinIO Client `mc`](https://min.io/docs/minio/linux/reference/minio-mc.html)
   - Optional: `kubectl` + `KUBECONFIG` (auto-reads Postgres/MinIO secrets)
3. Credentials:
   - `QAJAVA21_PG_PASSWORD` (or kube secret `postgres/postgres-postgresql`)
   - `COLLAB_PG_PASSWORD`
   - MinIO access/secret (or kube secret `minio/minio`)

```bash
# Example: fetch MinIO creds when kubeconfig is available
kubectl -n minio get secret minio -o jsonpath='{.data.root-user}' | base64 -d; echo
kubectl -n minio get secret minio -o jsonpath='{.data.root-password}' | base64 -d; echo
```

---

## Quick start

```bash
cd scripts/dmp-backup
cp config.env.example config.env
# Edit config.env / export passwords

export QAJAVA21_PG_PASSWORD='...'
export COLLAB_PG_PASSWORD='...'
export QAJAVA21_MINIO_ACCESS_KEY='admin'
export QAJAVA21_MINIO_SECRET_KEY='...'
# optional:
# export KUBECONFIG=/path/to/kubeconfig_qajava21

chmod +x *.sh
./run-all.sh
```

Selective runs:

```bash
./run-all.sh postgres      # DB dumps only
./run-all.sh schema        # collab schema-only
./run-all.sh traces        # UIN/VID/Handle CSV + reports
./run-all.sh minio         # object buckets
```

Output layout:

```text
backups/<UTC-stamp>/
  postgres/qajava21/          # *.dump + *.sql per database
  postgres/collab/            # schema-only CREATE script
  traces/                     # UIN/VID/Handle extracts
  minio/<bucket>/             # mirrored objects
  MANIFEST.txt
  SUMMARY.md
backups/dmp-qajava21-backup-<stamp>.tar.gz
```

---

## Manual commands (if not using scripts)

### Postgres dumps (qajava21)

```bash
export PGHOST=postgres.qajava21.mosip.net
export PGPORT=5433
export PGUSER=postgres
export PGPASSWORD='...'

for db in mosip_regprc mosip_credential mosip_idmap mosip_idrepo mosip_ida mosip_resident; do
  pg_dump -Fc -f "${db}.dump" "$db"
done
```

Restore a database:

```bash
pg_restore -h <host> -p 5433 -U postgres -d mosip_idrepo --clean --if-exists mosip_idrepo.dump
```

### Collab schema-only (no data)

```bash
export PGHOST=postgres.collab.mosip.net
export PGPORT=5433
export PGUSER=postgres
export PGPASSWORD='...'

# If self_registration is a schema:
pg_dump -d inji_certify_tan --schema-only --schema=self_registration \
  -f inji_certify_tan.self_registration.schema-only.sql

# If it is a table in a schema:
# pg_dump -d inji_certify_tan --schema-only -t self_registration.self_registration \
#   -f inji_certify_tan.self_registration.schema-only.sql
```

### UIN / VID / Handle traces

```bash
psql -h postgres.qajava21.mosip.net -p 5433 -U postgres -d mosip_idrepo \
  -f scripts/dmp-backup/sql/uin-vid-handle-traces.sql

psql -h postgres.qajava21.mosip.net -p 5433 -U postgres -d mosip_idmap \
  -f scripts/dmp-backup/sql/vid-traces.sql
```

### MinIO backup (last 3 days)

```bash
mc alias set qajava21 http://minio.qajava21.mosip.net:9000 "$ACCESS" "$SECRET" --api S3v4

BUCKETS="landing-zone packet-manager idrepo \
  mpolicy-default-abis mpolicy-default-auth mpolicy-default-digitalcard \
  mpolicy-default-euin mpolicy-default-pdfcard mpolicy-default-qrcode \
  mpolicy-default-reprint mpolicy-default-resident"

mkdir -p ./minio-backup
for b in $BUCKETS; do
  mc mirror --newer-than 3d --preserve "qajava21/$b" "./minio-backup/$b"
done
```

---

## MinIO restore process

Official MOSIP pattern (from [mosip-infra MinIO README](https://github.com/mosip/mosip-infra/blob/release-1.2.1.x/deployment/v3/external/object-store/minio/README.md)):

### 1. Install / configure `mc`

```bash
mc alias set <dest-alias> <destination-server-url> <minio-root-user> <minio-root-password> --api S3v4
mc alias ls
```

### 2. Restore from a local backup directory

```bash
export MINIO_SERVER=<dest-alias>
export MINIO_BACKUP_DIR=./backups/<stamp>/minio

for bucket in $(ls "$MINIO_BACKUP_DIR"); do
  [[ -d "$MINIO_BACKUP_DIR/$bucket" ]] || continue
  echo "$MINIO_SERVER/$bucket"
  mc mb --ignore-existing "$MINIO_SERVER/$bucket"
  mc mirror "$MINIO_BACKUP_DIR/$bucket" "$MINIO_SERVER/$bucket"
done
```

### 3. Using the helper script

```bash
export RESTORE_MINIO_URL='http://minio.target.example.net:9000'
export RESTORE_MINIO_ACCESS_KEY='admin'
export RESTORE_MINIO_SECRET_KEY='...'
export RESTORE_BACKUP_DIR='./backups/<stamp>/minio'

# Preview:
DRY_RUN=1 ./restore-minio.sh

# Apply:
./restore-minio.sh
```

### 4. Clone between two live MinIO servers

```bash
mc alias set src  http://minio.qajava21.mosip.net:9000 "$SRC_USER" "$SRC_PASS" --api S3v4
mc alias set dest http://minio.target:9000          "$DST_USER" "$DST_PASS" --api S3v4
mc mirror src/landing-zone dest/landing-zone
# repeat per bucket, or: mc mirror src dest
```

### Notes

- `mc mirror` copies the **current** object version; it does not restore full version history.
- Create the bucket first (`mc mb --ignore-existing`) before mirroring.
- If signature errors appear, retry the alias with `--api S3v2` or `S3v4` as appropriate.
- After restore, verify with `mc ls --recursive <alias>/<bucket>` and spot-check packet / idrepo object keys used by regproc and idrepo services.

---

## Security

- Do **not** commit `config.env`, dump files, or MinIO object trees.
- Treat UIN/VID/Handle extracts as PII / sensitive identity data.
- Prefer encrypted transfer (WireGuard) and store archives in a controlled location.
- Collab self-registration dump must remain **schema-only** (no `COPY`/`INSERT` data).
