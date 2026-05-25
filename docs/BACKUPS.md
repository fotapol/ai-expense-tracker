# Backups

PostgreSQL backups run through the in-cluster `postgres-backup` CronJob.

## How It Works

- schedule comes from `POSTGRES_BACKUP_SCHEDULE`
- dumps use `pg_dump --format=custom --compress=6`
- backups are uploaded to MinIO bucket `S3_BUCKET_BACKUPS`
- object keys are grouped under `POSTGRES_BACKUP_PREFIX`
- retention pruning uses `POSTGRES_BACKUP_RETENTION_DAYS`

## What Must Exist

- a pullable `POSTGRES_BACKUP_IMAGE`
- valid database credentials in `.env.production`
- valid MinIO endpoint and credentials in `.env.production`
- the backup bucket configured by `S3_BUCKET_BACKUPS`

The API startup path creates the backup bucket if it does not already exist.

## Build And Publish The Image

Build the dedicated backup image from `infra/images/postgres-backup/Dockerfile`:

```bash
docker build -f infra/images/postgres-backup/Dockerfile -t ghcr.io/your-org/ai-expense-tracker-postgres-backup:2026-04-15 .
docker push ghcr.io/your-org/ai-expense-tracker-postgres-backup:2026-04-15
```

Then set:

```bash
POSTGRES_BACKUP_IMAGE=ghcr.io/your-org/ai-expense-tracker-postgres-backup:2026-04-15
```

The runtime accepts either:

- `DATABASE_URL`
- or `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`

If `DATABASE_URL` uses the repo's SQLAlchemy-style `postgresql+psycopg://...` format, the backup container normalizes it before invoking `pg_dump`.

## Inspect Backup Runs

```bash
kubectl -n expense-tracker get cronjob postgres-backup
kubectl -n expense-tracker get jobs --sort-by=.metadata.creationTimestamp
kubectl -n expense-tracker logs job/<latest-backup-job>
kubectl -n expense-tracker create job --from=cronjob/postgres-backup postgres-backup-manual-$(date +%s)
```

## Restore Workflow

1. Download the desired dump from the MinIO backup bucket.
2. Copy it to a workstation or operator pod with PostgreSQL client tools.
3. Restore into a clean target database:

```bash
pg_restore \
  --clean \
  --if-exists \
  --no-owner \
  --dbname "postgresql://USER:PASSWORD@HOST:5432/DATABASE" \
  backup.dump
```

## Honest Limitations

- backups stay in the same MinIO cluster unless the operator replicates that bucket elsewhere
- this phase does not add PITR or WAL archiving
- restore must still be run manually by the operator
