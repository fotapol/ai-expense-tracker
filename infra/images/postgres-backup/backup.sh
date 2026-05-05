#!/bin/sh
set -eu

require_env() {
  value="$1"
  name="$2"
  if [ -z "$value" ]; then
    echo "${name} is required for PostgreSQL backups" >&2
    exit 1
  fi
}

normalize_database_url() {
  value="$1"
  case "$value" in
    postgresql+*://*)
      remainder="${value#postgresql+}"
      remainder="${remainder#*://}"
      printf 'postgresql://%s' "$remainder"
      ;;
    *)
      printf '%s' "$value"
      ;;
  esac
}

run_pg_dump() {
  if [ -n "${DATABASE_URL:-}" ]; then
    normalized_database_url="$(normalize_database_url "${DATABASE_URL}")"
    pg_dump \
      --no-password \
      --dbname="${normalized_database_url}" \
      --format=custom \
      --compress=6 \
      --file="${archive}"
    return
  fi

  require_env "${POSTGRES_HOST:-}" "POSTGRES_HOST"
  require_env "${POSTGRES_PORT:-}" "POSTGRES_PORT"
  require_env "${POSTGRES_DB:-}" "POSTGRES_DB"
  require_env "${POSTGRES_USER:-}" "POSTGRES_USER"
  require_env "${POSTGRES_PASSWORD:-}" "POSTGRES_PASSWORD"

  export PGPASSWORD="${POSTGRES_PASSWORD}"
  pg_dump \
    --no-password \
    --host="${POSTGRES_HOST}" \
    --port="${POSTGRES_PORT}" \
    --username="${POSTGRES_USER}" \
    --dbname="${POSTGRES_DB}" \
    --format=custom \
    --compress=6 \
    --file="${archive}"
}

umask 077
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
day_prefix="$(date -u +%Y/%m/%d)"
bucket_prefix="${POSTGRES_BACKUP_PREFIX:-postgres}"
archive_prefix="$(printf '%s' "${bucket_prefix}" | tr '/ ' '__')"
retention_days="${POSTGRES_BACKUP_RETENTION_DAYS:-30}"
archive="/tmp/${archive_prefix}-${timestamp}-$$.dump"
s3_access_key="${S3_ACCESS_KEY:-${MINIO_ROOT_USER:-}}"
s3_secret_key="${S3_SECRET_KEY:-${MINIO_ROOT_PASSWORD:-}}"

trap 'rm -f "$archive"' EXIT

require_env "${S3_ENDPOINT:-}" "S3_ENDPOINT"
require_env "${s3_access_key:-}" "S3_ACCESS_KEY or MINIO_ROOT_USER"
require_env "${s3_secret_key:-}" "S3_SECRET_KEY or MINIO_ROOT_PASSWORD"
require_env "${S3_BUCKET_BACKUPS:-}" "S3_BUCKET_BACKUPS"
require_env "${bucket_prefix}" "POSTGRES_BACKUP_PREFIX"

case "${retention_days}" in
  ''|*[!0-9]*)
    echo "POSTGRES_BACKUP_RETENTION_DAYS must be a non-negative integer" >&2
    exit 1
    ;;
esac

if [ -z "${DATABASE_URL:-}" ] && [ -z "${POSTGRES_HOST:-}" ]; then
  echo "DATABASE_URL or POSTGRES_* values are required for PostgreSQL backups" >&2
  exit 1
fi

remote_prefix="backup/${S3_BUCKET_BACKUPS}/${bucket_prefix}"
remote_object="${remote_prefix}/${day_prefix}/$(basename "$archive")"

run_pg_dump

mc alias set backup "${S3_ENDPOINT}" "${s3_access_key}" "${s3_secret_key}"
mc mb --ignore-existing "backup/${S3_BUCKET_BACKUPS}"
mc cp "${archive}" "${remote_object}"
mc rm --recursive --force --older-than "${retention_days}d" "backup/${S3_BUCKET_BACKUPS}/${bucket_prefix}" || true

echo "Uploaded ${remote_object}"
