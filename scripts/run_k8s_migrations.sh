#!/usr/bin/env bash
set -euo pipefail

namespace="${NAMESPACE:-expense-tracker}"
source_deployment="${MIGRATION_SOURCE_DEPLOYMENT:-expense-tracker-api}"
job_name="${MIGRATION_JOB_NAME:-expense-tracker-migrate-$(date -u +%Y%m%d%H%M%S)}"

image="$(
  kubectl -n "${namespace}" get deployment "${source_deployment}" \
    -o jsonpath='{.spec.template.spec.containers[?(@.name=="api")].image}'
)"

if [[ -z "${image}" ]]; then
  echo "Could not determine API image from deployment/${source_deployment}" >&2
  exit 1
fi

cat <<EOF | kubectl -n "${namespace}" apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${job_name}
  labels:
    app.kubernetes.io/name: expense-tracker-migrate
    app.kubernetes.io/component: migrations
    app.kubernetes.io/part-of: ai-expense-tracker
spec:
  backoffLimit: 1
  ttlSecondsAfterFinished: 86400
  template:
    metadata:
      labels:
        app.kubernetes.io/name: expense-tracker-migrate
        app.kubernetes.io/component: migrations
        app.kubernetes.io/part-of: ai-expense-tracker
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: ${image}
          imagePullPolicy: IfNotPresent
          command:
            - sh
            - -c
            - exec uv run alembic upgrade head
          envFrom:
            - configMapRef:
                name: expense-tracker-config
            - secretRef:
                name: expense-tracker-secrets
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
EOF

kubectl -n "${namespace}" wait --for=condition=complete "job/${job_name}" --timeout="${MIGRATION_TIMEOUT:-180s}"
kubectl -n "${namespace}" logs "job/${job_name}"
