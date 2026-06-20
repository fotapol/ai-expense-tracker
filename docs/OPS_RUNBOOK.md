# Ops Runbook

## Core Verification Commands

### Render The Production Inputs

```bash
python infra/k8s/scripts/render_k8s_env.py --env-file .env.production
```

### Apply Or Re-Apply The Stack

```bash
kubectl apply -k infra/k8s/overlays/production
```

## Verify API Health

Internal readiness:

```bash
kubectl -n expense-tracker port-forward svc/expense-tracker-api 8080:80
curl http://127.0.0.1:8080/health/live
curl http://127.0.0.1:8080/health/ready
```

Public-safe root:

```bash
curl https://api.example.com/
```

Public listener sanity check:

```bash
kubectl -n nginx-ingress get pods -o wide
kubectl -n nginx-ingress logs daemonset/nginx-ingress-nginx-ingress --tail=200
```

Confirm the controller started cleanly after binding the HTTPS listener on `8443`.

## Verify Worker Health

```bash
kubectl -n expense-tracker logs deploy/expense-tracker-worker --tail=200
kubectl -n expense-tracker port-forward svc/expense-tracker-worker 9101:9101
curl http://127.0.0.1:9101/metrics
```

## Verify MinIO

```bash
kubectl -n expense-tracker logs statefulset/minio --tail=200
kubectl -n expense-tracker port-forward svc/minio 9001:9001
```

The port-forward above is for the MinIO console only. Keep it operator-only.

For receipt upload failures, also inspect the public storage route:

```bash
kubectl -n expense-tracker describe virtualserver expense-tracker-storage
kubectl -n nginx-ingress logs daemonset/nginx-ingress-nginx-ingress --tail=200
```

The storage route should preserve `Host: storage.example.com` when
forwarding presigned S3 upload requests to MinIO. Do not append the origin
port here when Cloudflare rewrites the public hostname to origin port `8443`;
the S3 presigned signature includes the public `Host` value.

If the app shows the generic receipt upload failure immediately after tapping
`Upload & Extract`, verify that the NGINX controller was upgraded with the
committed `client-max-body-size: 16m` value. Without that setting, the edge can
reject normal camera images before MinIO receives the presigned `PUT`.

## Verify Prometheus And Grafana

```bash
kubectl -n expense-tracker port-forward svc/prometheus 9090:9090
kubectl -n expense-tracker port-forward svc/grafana 3000:3000
```

Expected checks:

- Prometheus target status shows API, worker, and Prometheus itself as `UP`
- Grafana loads the provisioned `AI Expense Tracker Overview` dashboard

## Verify LangSmith

- set `LANGSMITH_TRACING=true`
- set `LANGSMITH_API_KEY`
- upload a test receipt
- confirm a trace appears in the configured `LANGSMITH_PROJECT`
- confirm the trace metadata contains safe identifiers but not raw receipt contents

## Verify RevenueCat Webhook

1. Configure the webhook in RevenueCat.
   Use `https://api.example.com/v1/billing/revenuecat/webhook`.
2. Send a test delivery.
3. Check:

```bash
kubectl -n expense-tracker logs deploy/expense-tracker-api --tail=200
```

Look for:

- `revenuecat_webhook_processed`
- `revenuecat_webhook_ignored`
- `revenuecat_webhook_failed`

## Log Inspection Commands

```bash
kubectl -n expense-tracker logs deploy/expense-tracker-api --tail=200
kubectl -n expense-tracker logs deploy/expense-tracker-worker --tail=200
kubectl -n nginx-ingress logs daemonset/nginx-ingress-nginx-ingress --tail=200
kubectl -n expense-tracker logs deploy/prometheus --tail=200
kubectl -n expense-tracker logs deploy/grafana --tail=200
```

Adjust the ingress controller pod selector if you install it under a different release name.

## Secret Rotation

1. Update `.env.production`.
2. Re-run the render script.
3. Re-apply the production overlay.
4. Restart workloads if required:

```bash
kubectl -n expense-tracker rollout restart deploy/expense-tracker-api
kubectl -n expense-tracker rollout restart deploy/expense-tracker-worker
```

Rotate carefully:

- PostgreSQL credentials
- RabbitMQ credentials and Erlang cookie
- MinIO credentials
- Firebase service account
- LangSmith API key
- RevenueCat secret API key and webhook secret
- Grafana admin password

## What Remains Manual

- VPS provisioning and firewall setup
- K3s installation
- NGINX controller installation
- Cloudflare DNS and Origin CA certificate creation
- publishing `BACKEND_IMAGE` and `POSTGRES_BACKUP_IMAGE`
- setting GitHub Actions secrets for manual deployment

## GitHub Actions Secrets For Manual Deploy

The manual deploy workflow expects:

- `ENV_PRODUCTION`
  - the full `.env.production` file contents
- `KUBE_CONFIG_B64`
  - a base64-encoded kubeconfig

The manual workflow validates and applies the production overlay only when the operator dispatches it explicitly.
