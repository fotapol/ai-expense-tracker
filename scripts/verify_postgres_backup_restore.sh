#!/usr/bin/env bash
set -euo pipefail

namespace="${NAMESPACE:-expense-tracker}"
job_name="${JOB_NAME:-postgres-restore-verify-$(date -u +%Y%m%d%H%M%S)}"
timeout="${TIMEOUT:-600s}"
keep_job="${KEEP_JOB:-false}"
image="${POSTGRES_BACKUP_IMAGE:-}"

if [[ -z "${image}" ]]; then
  image="$(
    kubectl -n "${namespace}" get cronjob postgres-backup \
      -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}'
  )"
fi

if [[ -z "${image}" ]]; then
  echo "POSTGRES_BACKUP_IMAGE is required and postgres-backup CronJob image could not be detected." >&2
  exit 1
fi

cat <<YAML | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${job_name}
  namespace: ${namespace}
  labels:
    app.kubernetes.io/name: postgres-restore-verify
    app.kubernetes.io/component: backups
    app.kubernetes.io/part-of: ai-expense-tracker
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 3600
  template:
    metadata:
      labels:
        app.kubernetes.io/name: postgres-restore-verify
        app.kubernetes.io/component: backups
        app.kubernetes.io/part-of: ai-expense-tracker
    spec:
      restartPolicy: Never
      containers:
        - name: restore-verify
          image: ${image}
          imagePullPolicy: IfNotPresent
          envFrom:
            - configMapRef:
                name: expense-tracker-config
            - secretRef:
                name: expense-tracker-secrets
          command:
            - /bin/sh
            - -ec
            - |
              require_env() {
                value="\$1"
                name="\$2"
                if [ -z "\${value}" ]; then
                  echo "\${name} is required for restore verification" >&2
                  exit 1
                fi
              }

              s3_access_key="\${S3_ACCESS_KEY:-\${MINIO_ROOT_USER:-}}"
              s3_secret_key="\${S3_SECRET_KEY:-\${MINIO_ROOT_PASSWORD:-}}"
              backup_prefix="\${POSTGRES_BACKUP_PREFIX:-postgres}"

              require_env "\${S3_ENDPOINT:-}" "S3_ENDPOINT"
              require_env "\${s3_access_key:-}" "S3_ACCESS_KEY or MINIO_ROOT_USER"
              require_env "\${s3_secret_key:-}" "S3_SECRET_KEY or MINIO_ROOT_PASSWORD"
              require_env "\${S3_BUCKET_BACKUPS:-}" "S3_BUCKET_BACKUPS"

              remote_root="backup/\${S3_BUCKET_BACKUPS}/\${backup_prefix}"
              archive="/tmp/restore-verify.dump"
              pgdata="/tmp/restore-verify-db"
              s3_endpoint="\${S3_ENDPOINT%/}"

              for attempt in \$(seq 1 30); do
                if wget -q -O /dev/null "\${s3_endpoint}/minio/health/live"; then
                  break
                fi
                if [ "\${attempt}" -eq 30 ]; then
                  echo "MinIO did not become reachable at \${s3_endpoint}" >&2
                  exit 1
                fi
                echo "Waiting for MinIO at \${s3_endpoint} (attempt \${attempt}/30)..."
                sleep 2
              done

              for attempt in \$(seq 1 10); do
                if mc alias set backup "\${s3_endpoint}" "\${s3_access_key}" "\${s3_secret_key}" >/dev/null; then
                  break
                fi
                if [ "\${attempt}" -eq 10 ]; then
                  echo "Could not initialize MinIO client alias for restore verification." >&2
                  exit 1
                fi
                echo "Retrying MinIO client initialization (attempt \${attempt}/10)..."
                sleep 2
              done
              latest="\$(mc find "\${remote_root}" --name '*.dump' | sort | tail -n 1)"
              if [ -z "\${latest}" ]; then
                echo "No backup dump found under \${remote_root}" >&2
                exit 1
              fi

              echo "Verifying latest backup object: \${latest}"
              mc cp "\${latest}" "\${archive}" >/dev/null
              pg_restore --list "\${archive}" >/tmp/restore-verify.list

              initdb -D "\${pgdata}" --username=restore >/tmp/restore-verify-initdb.log
              pg_ctl -D "\${pgdata}" -o "-k /tmp -p 55432 -c listen_addresses=''" -w start
              trap 'pg_ctl -D "\${pgdata}" -m fast -w stop >/dev/null 2>&1 || true' EXIT

              createdb -h /tmp -p 55432 -U restore restore_verify
              pg_restore --no-owner --no-acl -h /tmp -p 55432 -U restore -d restore_verify "\${archive}"
              table_count="\$(psql -h /tmp -p 55432 -U restore -d restore_verify -Atc "select count(*) from information_schema.tables;")"
              echo "Disposable restore verification succeeded; restored table count: \${table_count}"
YAML

if ! kubectl -n "${namespace}" wait --for=condition=complete "job/${job_name}" --timeout="${timeout}"; then
  kubectl -n "${namespace}" logs "job/${job_name}" --all-containers=true || true
  exit 1
fi

kubectl -n "${namespace}" logs "job/${job_name}" --all-containers=true

if [ "${keep_job}" != "true" ]; then
  kubectl -n "${namespace}" delete job "${job_name}" --ignore-not-found=true
fi
