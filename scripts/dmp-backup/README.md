# DMP internship backup scripts (qajava21)

Automates Postgres + MinIO backup for DMP internship work, collab schema-only dump, UIN/VID/Handle traces, and MinIO restore.

Full guide: [`docs/DMP_INTERNSHIP_BACKUP_GUIDE.md`](../../docs/DMP_INTERNSHIP_BACKUP_GUIDE.md)

## Scripts

| Script | Purpose |
|--------|---------|
| `run-all.sh` | Orchestrate selected targets and create a tarball |
| `backup-postgres.sh` | Dump qajava21 DBs listed in the request |
| `backup-self-registration-schema.sh` | Schema-only dump of `inji_certify_tan.self_registration` from collab |
| `backup-minio.sh` | Mirror selected buckets (prefer last 3 days) |
| `export-uin-vid-handle.sh` | Export UIN / VID / Handle traces + CSVs |
| `restore-minio.sh` | Restore local MinIO backup into a target MinIO |

## Minimal usage

```bash
cp config.env.example config.env
export QAJAVA21_PG_PASSWORD='...'
export COLLAB_PG_PASSWORD='...'
export QAJAVA21_MINIO_ACCESS_KEY='admin'
export QAJAVA21_MINIO_SECRET_KEY='...'
./run-all.sh
```
