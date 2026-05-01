# Deployment

This repository now targets a single-VPS Kubernetes deployment with:

- K3s as the chosen cluster bootstrap path
- F5 NGINX Ingress Controller as the maintained NGINX-based edge layer
- Cloudflare in front of the public site, API, and storage hostnames
- PostgreSQL, Redis, RabbitMQ, MinIO, Prometheus, and Grafana running in-cluster

## Cluster Bootstrap Decision

### Compared Options

1. `kubeadm`
   - best when the primary goal is upstream Kubernetes learning and maximum control
   - highest operator overhead on a single VPS
   - more setup work for networking, addons, and upgrades

2. `K3s`
   - easiest day-2 path for a solo operator on one VPS
   - still Kubernetes-native, so the repo manifests stay portable
   - simple install, simple upgrades, and easy to disable the default Traefik ingress

3. another distribution such as MicroK8s
   - workable, but more opinionated packaging for this repo than necessary
   - less attractive than K3s for this specific single-node, solo-operator setup

### Chosen Path

Choose `K3s`.

Reason:

- it fits the single-VPS reality best
- it keeps the repo Kubernetes-native
- it avoids locking the application manifests to a distro-specific layout
- it keeps learning value without making cluster operations the hardest part of launch

## Required Open Ports

- `22/tcp` for SSH
- `80/tcp` optionally, if you want HTTP redirect / edge handling
- `8443/tcp` for public HTTPS because `443` is already occupied on this VPS
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
- keep the committed `hostPort`, `containerPort`, and `defaultHTTPSListenerPort` values on `8443`
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

- `nexavend.store` -> VPS public IP
- `api.nexavend.store` -> VPS public IP
- `storage.nexavend.store` -> VPS public IP

Use:

- SSL/TLS mode: `Full (strict)`
- proxied orange-cloud DNS records
- free-plan assumptions only
- an Origin Rule for `nexavend.store` that rewrites the destination port to
  `8443`, so public users can open `https://nexavend.store` without typing the
  origin port
- API public URL with the explicit alternate HTTPS port:
  `https://api.nexavend.store:8443`
- Storage public URL with the explicit alternate HTTPS port:
  `https://storage.nexavend.store:8443`
- the public site URL you set in `PUBLIC_APP_BASE_URL`, for example
  `https://nexavend.store`

Cloudflare supports proxied HTTPS traffic on `8443`, and Origin Rules can route
clean edge URLs on port `443` to a non-standard origin port. Keep API and
storage presigned URLs on the explicit `:8443` host unless you deliberately add
and test a Cloudflare Origin Rule for the clean storage hostname.

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
  --docker-username=fotapol \
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
production app images tagged `:latest`. The current public site image value is:

```bash
SITE_IMAGE=ghcr.io/fotapol/ai-expense-tracker-site:prod-1
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

### 8. Render Kubernetes Inputs

```bash
python infra/k8s/scripts/render_k8s_env.py --env-file .env.production
```

### 9. Run Database Migrations

When `RUN_STARTUP_MIGRATIONS=false`, run the repo-defined migration job before
the API rollout:

```bash
bash scripts/run_k8s_migrations.sh
```

The script creates a temporary Kubernetes `Job` from the currently deployed API
image, injects the same generated ConfigMap/Secret, runs `alembic upgrade head`,
waits for completion, and prints the migration logs. Do not point migration
commands at a production database outside this namespace workflow.

### 10. Apply The Production Overlay

```bash
kubectl apply -k infra/k8s/overlays/production
```

The production API, site, and storage routes use F5 NGINX `VirtualServer`
resources with the `https-8443` listener. Do not reintroduce ordinary
Kubernetes `Ingress` objects for these public routes unless the custom HTTPS
listener strategy is deliberately migrated.

The F5 NGINX controller values pin the public HTTPS listener to:

- `containerPort: 8443`
- `hostPort: 8443`
- `defaultHTTPSListenerPort: 8443`

Do not change those listener values unless you also move the public HTTPS listener back off `8443`.

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
curl -I https://nexavend.store/
curl -I https://nexavend.store/privacy
curl -I https://nexavend.store/terms
```

Expected:

- the public site returns `200`
- `/privacy` and `/terms` return `200`
- support/download links reflect the values rendered from your production env

### API

```bash
curl -I https://api.nexavend.store:8443/
curl -I https://api.nexavend.store:8443/v1/billing/revenuecat/webhook
```

Expected:

- HTTPS succeeds
- `/metrics`, `/health/live`, and `/health/ready` return `404` from the public host

### Storage

Verify presigned upload and download URLs from the app or backend.

Do not expose the MinIO console publicly.

The storage `VirtualServer` must preserve the original `Host` header, including
`:8443`, when proxying presigned S3 requests to MinIO. S3 signatures include the
request host, so removing the non-default port can cause direct receipt uploads
to fail with a generic app upload error.

The NGINX controller must also allow receipt bodies larger than the default
upload ceiling. The committed controller values set `client-max-body-size` to
`16m`, which stays above the mobile 10 MB receipt limit and the backend
`MAX_RECEIPT_FILE_BYTES` value.

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

- `docs/ENVIRONMENT_VARIABLES.md`
- `docs/MONITORING.md`
- `docs/BACKUPS.md`
- `docs/WEBHOOKS.md`
- `docs/SECURITY_EXPOSURE.md`
- `docs/OPS_RUNBOOK.md`
