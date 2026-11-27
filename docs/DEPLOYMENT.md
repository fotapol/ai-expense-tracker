# Deployment

This guide deploys AI Expense Tracker to a single VPS with K3s, F5 NGINX
Ingress Controller, and Cloudflare in front of the public hostnames. PostgreSQL,
Redis, RabbitMQ, MinIO, Prometheus, and Grafana run inside the cluster.

## Required Open Ports

- `22/tcp` for SSH
- `80/tcp` optionally, if you want HTTP redirect / edge handling
- `2053/tcp` for HTTPS connections from Cloudflare to the ingress controller
- `6443/tcp` only if you need remote Kubernetes API access
  Restrict this to operator IPs or a VPN. Do not expose it broadly.

Do not open PostgreSQL, Redis, RabbitMQ, MinIO, Grafana, or Prometheus to the public internet.

## Bootstrap Steps

### 1. Install K3s

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable traefik --write-kubeconfig-mode 600" sh -
```

### 2. Install Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### 3. Install The Maintained NGINX Controller

Edit `infra/k8s/addons/nginx-ingress-values.yaml` first:

- replace `REPLACE_WITH_TRUSTED_PROXY_CIDRS` with Cloudflare IPv4 and IPv6 CIDRs
- keep the ingress class as `nginx`
- keep the committed `hostPort`, `containerPort`, and `defaultHTTPSListenerPort` values on `2053`
- keep `client-max-body-size` at least as large as the backend receipt upload limit

Install the controller:

```bash
helm upgrade --install nginx-ingress \
  oci://ghcr.io/nginx/charts/nginx-ingress \
  --version 2.4.4 \
  --namespace nginx-ingress \
  --create-namespace \
  -f infra/k8s/addons/nginx-ingress-values.yaml
```

### 4. Configure Cloudflare

Create proxied DNS records:

- `example.com` -> VPS public IP
- `api.example.com` -> VPS public IP
- `storage.example.com` -> VPS public IP

Use:

- SSL/TLS mode: `Full (strict)`
- proxied orange-cloud DNS records
- an Origin Rule matching `example.com`, `api.example.com`, and
  `storage.example.com` that sends requests to destination port `2053` while
  preserving the public hostnames
- API public URL `https://api.example.com`
- Storage public URL `https://storage.example.com`
- the public site URL you set in `PUBLIC_APP_BASE_URL`, for example
  `https://example.com`

Clients use the default HTTPS port `443`. Cloudflare connects to the ingress
controller on `2053` using the matching Origin Rule.

### 5. Create The Origin TLS Secret

Generate a Cloudflare Origin CA certificate for the public hostnames, then load it into Kubernetes:

```bash
kubectl create namespace expense-tracker --dry-run=client -o yaml | kubectl apply -f -
kubectl -n expense-tracker create secret tls expense-tracker-origin-tls \
  --cert=origin.crt \
  --key=origin.key
```

### 6. Create The GHCR Image Pull Secret

The production overlay attaches the canonical private-registry pull secret
`ghcr-creds` to the default ServiceAccount in the `expense-tracker` namespace.
Create the secret before applying workloads:

```bash
kubectl -n expense-tracker create secret docker-registry ghcr-creds \
  --docker-server=ghcr.io \
  --docker-username=your-github-org \
  --docker-password="$GHCR_READ_PACKAGES_TOKEN"
```

The token in `GHCR_READ_PACKAGES_TOKEN` needs the `read:packages` permission for
GHCR private image pulls. Do not commit the token.

Preflight:

```bash
kubectl -n expense-tracker get secret ghcr-creds
kubectl -n expense-tracker get serviceaccount default -o yaml
```

Expected ServiceAccount output includes:

```yaml
imagePullSecrets:
- name: ghcr-creds
```

If dedicated ServiceAccounts are introduced later for API, worker, site, or
backup jobs, keep using the same image pull secret name: `ghcr-creds`.

### 7. Prepare `.env.production`

Copy `.env.production.example` to `.env.production` and fill:

- all service credentials
- `BACKEND_IMAGE`
- `SITE_IMAGE`
- `POSTGRES_BACKUP_IMAGE`
- `FIREBASE_SERVICE_ACCOUNT_JSON_B64`
- LangSmith values
- RevenueCat values if used

The image values must point to pullable registry images before you deploy.
The render script rejects placeholder `ghcr.io/example/...` images and
production app images tagged `:latest`. A site image can use a release tag.

```bash
SITE_IMAGE=ghcr.io/your-github-org/ai-expense-tracker-site:prod-1
```

Build and publish the backup image from:

```bash
docker build -f infra/images/postgres-backup/Dockerfile -t ghcr.io/your-org/ai-expense-tracker-postgres-backup:2026-04-15 .
docker push ghcr.io/your-org/ai-expense-tracker-postgres-backup:2026-04-15
```

Build and publish the public site image from:

```bash
docker build -f site/Dockerfile -t ghcr.io/your-org/ai-expense-tracker-site:2026-04-23 .
docker push ghcr.io/your-org/ai-expense-tracker-site:2026-04-23
```

Backups default to a 30-day retention window through
`POSTGRES_BACKUP_RETENTION_DAYS=30`. After the first successful backup, verify
that the newest dump can be restored into disposable infrastructure:

```bash
bash scripts/verify_postgres_backup_restore.sh
```

This script creates a temporary Kubernetes `Job`, downloads the newest backup
from MinIO, restores it into an ephemeral PostgreSQL data directory inside that
job, prints the result, and deletes the job unless `KEEP_JOB=true` is set. It
must not be pointed at production Postgres.

Use fully qualified image names with a tag or digest for each of the three
image variables. The API and worker share `BACKEND_IMAGE`. Confirm that the
cluster can pull the configured images before rolling out.

### 8. Render Kubernetes Inputs

```bash
python infra/k8s/scripts/render_k8s_env.py --env-file .env.production
```

`UVICORN_FORWARDED_ALLOW_IPS` must not be `*` in production. To discover the
right value using proxy diagnostics, temporarily set:

```env
PROXY_DIAGNOSTICS_ENABLED=true
UVICORN_FORWARDED_ALLOW_IPS=127.0.0.1
```

Apply the overlay, make one public request, then inspect the safe proxy
diagnostic fields:

```bash
curl -sS https://api.example.com/ >/dev/null
kubectl -n expense-tracker logs deploy/expense-tracker-api --tail=200 | \
  grep proxy_socket_client_host
```

Set `UVICORN_FORWARDED_ALLOW_IPS` to the observed F5 NGINX source IP or CIDR,
set `PROXY_DIAGNOSTICS_ENABLED=false`, render again, and redeploy. Verify that
the request retains the public host, such as `api.example.com`.

### 9. Run Database Migrations

When `RUN_STARTUP_MIGRATIONS=false`, run migrations using the new backend image
before upgrading an existing deployment. Use the same image reference you set
for `BACKEND_IMAGE`.

```bash
MIGRATION_IMAGE=ghcr.io/your-github-org/ai-expense-tracker-backend:prod-1 \
  bash scripts/run_k8s_migrations.sh
```

The script creates a Kubernetes Job that reads the API ConfigMap and Secret,
runs `alembic upgrade head`, and prints the migration logs. If you omit
`MIGRATION_IMAGE`, it uses the image from the current API deployment.

For a new cluster, apply the overlay in the next step to create the required
resources, wait for PostgreSQL to become ready, then run the migration job
before verifying the API and worker.

### 10. Apply The Production Overlay

```bash
kubectl apply -k infra/k8s/overlays/production
```

The production API, site, and storage routes use F5 NGINX `VirtualServer`
resources with the `https-2053` listener. Do not reintroduce ordinary
Kubernetes `Ingress` objects for these public routes unless the custom HTTPS
listener strategy is deliberately migrated.

The F5 NGINX controller values pin the public HTTPS listener to:

- `containerPort: 2053`
- `hostPort: 2053`
- `defaultHTTPSListenerPort: 2053`

Keep the controller values, the three `VirtualServer` listener references,
and the Cloudflare Origin Rule in sync when changing the origin port.
The controller reserves HTTP port `80`, so `GlobalConfiguration` declares
only the custom HTTPS listener.

## Traffic Path

Public request flow:

1. client
2. Cloudflare
3. F5 NGINX Ingress Controller on the VPS
4. Kubernetes service
5. site pod, API pod, or MinIO S3 API

Internal services remain cluster-only and are not routed through the public hostnames.

## Post-Deploy Verification

### Site

```bash
curl -I https://example.com/
curl -I https://example.com/delete-account
```

Expected:

- the public site returns `200`
- `/delete-account` returns `200`
- support/download links reflect the values rendered from your production env

### API

```bash
curl -I https://api.example.com/
curl -I https://api.example.com/v1/billing/revenuecat/webhook
```

Expected:

- HTTPS succeeds
- `/metrics`, `/health/live`, and `/health/ready` return `404` from the public host

### Storage

Verify presigned upload and download URLs from the app or backend.

Do not expose the MinIO console publicly.

The storage `VirtualServer` must preserve the public `Host` header when proxying
presigned S3 requests to MinIO. S3 signatures include the request host. For
`https://storage.example.com`, preserve `storage.example.com` without appending
the origin port.

The NGINX controller must also allow receipt bodies larger than the default
upload ceiling. The committed controller values set `client-max-body-size` to
`16m`, which stays above the mobile 10 MB receipt limit and the backend
`MAX_RECEIPT_FILE_BYTES` value.

### Storage Lifecycle And Retention

Receipt objects do not have automatic expiry. This is deliberate for launch:
the application deletes receipt objects when a user deletes a receipt, and
account deletion removes that user's receipt objects before local account data
is committed as deleted. Do not add a MinIO lifecycle rule that expires the
`receipts` bucket unless product policy, legal copy, and account deletion
behavior are updated together.

PostgreSQL backups are different. The backup CronJob uploads dumps under
`POSTGRES_BACKUP_PREFIX` in `S3_BUCKET_BACKUPS` and prunes old dumps with the
configured `POSTGRES_BACKUP_RETENTION_DAYS` value, which defaults to `30`.

Use the operator `mc` client from a trusted machine to verify lifecycle state
without printing secrets:

```bash
mc alias set prod-storage "$S3_ENDPOINT" "$S3_ACCESS_KEY" "$S3_SECRET_KEY"
mc ilm ls prod-storage/receipts
mc ilm ls prod-storage/postgres-backups
mc ls --recursive prod-storage/postgres-backups/postgres | tail
```

Expected launch state:

- `prod-storage/receipts` has no automatic expiry lifecycle rule.
- old database backup objects are pruned by the backup job after
  `POSTGRES_BACKUP_RETENTION_DAYS`, not by a bucket-wide receipt expiry rule.
- `S3_EXTERNAL_ENDPOINT` is the canonical public storage endpoint, for example
  `https://storage.example.com`, covered by the Cloudflare Origin Rule.

### Monitoring

Use port-forward for operator access:

```bash
kubectl -n expense-tracker port-forward svc/prometheus 9090:9090
kubectl -n expense-tracker port-forward svc/grafana 3000:3000
```

### VPS Log Retention

Keep node logs bounded so backups, PVCs, and container logs do not compete for
disk. On K3s, configure journald and kubelet/container log rotation on the VPS:

```bash
sudo mkdir -p /etc/systemd/journald.conf.d
printf "[Journal]\nSystemMaxUse=1G\nMaxRetentionSec=90day\n" | \
  sudo tee /etc/systemd/journald.conf.d/retention.conf
sudo systemctl restart systemd-journald
```

For K3s, add kubelet log rotation args to `/etc/rancher/k3s/config.yaml` and
restart K3s during a maintenance window:

```yaml
kubelet-arg:
  - container-log-max-size=10Mi
  - container-log-max-files=5
```

Check disk and log usage regularly:

```bash
df -h
journalctl --disk-usage
sudo du -h -d1 /var/lib/rancher/k3s /var/log 2>/dev/null
```

### Worker

```bash
kubectl -n expense-tracker logs deploy/expense-tracker-worker --tail=200
```

The worker must show startup, RabbitMQ connection, and receipt job logs.

## Related Docs

- [Environment variables](ENVIRONMENT_VARIABLES.md)
- [Monitoring](MONITORING.md)
- [Backups](BACKUPS.md)
- [Webhooks](WEBHOOKS.md)
- [Operations runbook](OPS_RUNBOOK.md)
