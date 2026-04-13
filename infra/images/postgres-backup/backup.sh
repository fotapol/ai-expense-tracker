#!/bin/sh
set -eu

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
day_prefix="$(date -u +%Y/%m/%d)"
bucket_prefix="${POSTGRES_BACKUP_PREFIX:-postgres}"
retention_days="${POSTGRES_BACKUP_RETENTION_DAYS:-14}"
archive="/tmp/${bucket_prefix}-${timestamp}.dump"
remote_prefix="backup/${S3_BUCKET_BACKUPS}/${bucket_prefix}"
remote_object="${remote_prefix}/${day_prefix}/$(basename "$archive")"

if [ -z "${DATABASE_URL:-}" ]; then
  echo "DATABASE_URL is required for backups" >&2
  exit 1
fi

if [ -z "${S3_ENDPOINT:-}" ] || [ -z "${S3_ACCESS_KEY:-}" ] || [ -z "${S3_SECRET_KEY:-}" ]; then
  echo "S3 endpoint and credentials are required for backups" >&2
  exit 1
fi

pg_dump \
  --dbname="${DATABASE_URL}" \
  --format=custom \
  --compress=6 \
  --file="${archive}"

mc alias set backup "${S3_ENDPOINT}" "${S3_ACCESS_KEY}" "${S3_SECRET_KEY}"
mc mb --ignore-existing "backup/${S3_BUCKET_BACKUPS}"
mc cp "${archive}" "${remote_object}"
mc rm --recursive --force --older-than "${retention_days}d" "backup/${S3_BUCKET_BACKUPS}/${bucket_prefix}" || true

echo "Uploaded ${remote_object}"
