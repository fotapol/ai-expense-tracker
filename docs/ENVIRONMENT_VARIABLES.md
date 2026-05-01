# Environment Variables

`.env.example` is the canonical local/development template.
`.env.production.example` is the canonical production/operator template.

For Kubernetes, the operator workflow is:

1. Copy `.env.production.example` to `.env.production`.
2. Fill real values.
3. Run `python infra/k8s/scripts/render_k8s_env.py --env-file .env.production`.
4. Apply `kubectl apply -k infra/k8s/overlays/production`.

The render script writes:

- `infra/k8s/overlays/production/generated/config.env`
- `infra/k8s/overlays/production/generated/secret.env`
- `infra/k8s/overlays/production/generated/postgres-backup-schedule-patch.yaml`
- `infra/k8s/overlays/production/generated/prometheus.yml`
- `infra/k8s/overlays/production/generated/image-overrides-patch.yaml`

Those generated files are the only inputs the production Kustomize overlay uses for `ConfigMap` and `Secret` generation.

## Core App And Routing

| Name | Purpose | Required | Dev Example | Production Notes | Secret |
| --- | --- | --- | --- | --- | --- |
| `APP_ENV` | Backend runtime mode. | Required | `development` | Set to `production` on the cluster. | No |
| `PUBLIC_API_BASE_URL` | Canonical public API URL. | Required | `http://localhost:8000` | Must be the Cloudflare-fronted API origin such as `https://api.nexavend.store:8443`. | No |
| `PUBLIC_APP_BASE_URL` | Canonical public app/site URL for invite links and the public website hostname. | Required when deploying the public site | `http://localhost:3000` | Set this to the real public site URL such as `https://nexavend.store`. | No |
| `APP_ADMIN_EMAILS` | Comma-separated backend admin allowlist. | Optional | `admin@example.com` | Keep tight for single-user launch; rendered into a Kubernetes Secret even though it is not a credential. | Yes |
| `MAX_RECEIPT_FILE_BYTES` | Backend hard cap for uploaded receipt size. | Required | `15728640` | Keep aligned with mobile UX and ingress/storage limits. | No |
| `LOG_LEVEL` | Default backend log level. | Required | `INFO` | Use `INFO` for launch; raise to `DEBUG` only temporarily. | No |
| `LOG_JSON` | Toggle structured JSON logging. | Required | `false` | Use `true` in production if your log pipeline prefers JSON. | No |
| `PROXY_DIAGNOSTICS_ENABLED` | Temporarily log safe proxy/Host diagnostics for Cloudflare/F5 verification. | Required | `false` | Enable only during proxy trust validation, then turn it off. | No |
| `UVICORN_FORWARDED_ALLOW_IPS` | Uvicorn proxy-header trust setting. | Required | `*` | Set deliberately for proxy usage; current k8s path expects a maintained NGINX-based controller in front. | No |
| `INGRESS_CLASS_NAME` | Kubernetes ingress class name. | Required | `nginx` | The production overlay injects this into the API `Ingress`. | No |
| `INGRESS_TLS_SECRET_NAME` | Kubernetes TLS secret name used by the API ingress. | Required | `expense-tracker-origin-tls` | Store the Cloudflare Origin CA certificate/key in this secret. | No |

## Postgres, Redis, And RabbitMQ

| Name | Purpose | Required | Dev Example | Production Notes | Secret |
| --- | --- | --- | --- | --- | --- |
| `POSTGRES_HOST` | PostgreSQL hostname. | Required | `postgres` | Internal Kubernetes service name for the in-cluster database. | No |
| `POSTGRES_PORT` | PostgreSQL port. | Required | `5432` | Keep default unless you intentionally change the service port. | No |
| `POSTGRES_DB` | PostgreSQL database name. | Required | `expense_tracker` | Used by both the database pod and app connection-string generation. | No |
| `POSTGRES_USER` | PostgreSQL application username. | Required | `expense_user` | Stored in the Kubernetes Secret. | Yes |
| `POSTGRES_PASSWORD` | PostgreSQL application password. | Required | `expense_pass` | Use a strong unique value in production. | Yes |
| `DATABASE_URL` | Explicit SQLAlchemy DSN override. | Optional | blank | Leave blank to derive from `POSTGRES_*`; if set, it overrides the derived DSN and is stored as a secret. | Yes |
| `REDIS_HOST` | Redis hostname. | Required | `redis` | Internal service name for the cache/rate-limit store. | No |
| `REDIS_PORT` | Redis port. | Required | `6379` | Keep default unless you intentionally reconfigure Redis. | No |
| `REDIS_DB` | Redis logical database index. | Required | `0` | Used when deriving `REDIS_URL`. | No |
| `REDIS_URL` | Explicit Redis URL override. | Optional | blank | Leave blank to derive from `REDIS_HOST`, `REDIS_PORT`, and `REDIS_DB`. | Yes |
| `RABBITMQ_HOST` | RabbitMQ hostname. | Required | `rabbitmq` | Internal Kubernetes service name for the broker. | No |
| `RABBITMQ_PORT` | RabbitMQ AMQP port. | Required | `5672` | Keep aligned with the broker manifest. | No |
| `RABBITMQ_MANAGEMENT_PORT` | RabbitMQ management UI port. | Required | `15672` | Internal-only; do not expose publicly. | No |
| `RABBITMQ_VHOST` | RabbitMQ virtual host. | Required | `/` | Used when deriving `RABBITMQ_URL`. | No |
| `RABBITMQ_USER` | RabbitMQ username. | Required | `expense_worker` | Stored in the Kubernetes Secret. | Yes |
| `RABBITMQ_PASSWORD` | RabbitMQ password. | Required | `expense_worker_pass` | Must not use `guest/guest` in production. | Yes |
| `RABBITMQ_ERLANG_COOKIE` | RabbitMQ cluster cookie. | Required | `change-me-local-cookie` | Required for stable stateful RabbitMQ operation. | Yes |
| `RABBITMQ_URL` | Explicit RabbitMQ AMQP URL override. | Optional | blank | Leave blank to derive from the component vars; stored as a secret because it contains credentials. | Yes |
| `RECEIPT_EXTRACTION_QUEUE_NAME` | Queue name used by the receipt pipeline. | Required | `receipt_extraction` | Keep consistent between API and worker. | No |

## Storage, Firebase, And AI

| Name | Purpose | Required | Dev Example | Production Notes | Secret |
| --- | --- | --- | --- | --- | --- |
| `MINIO_ROOT_USER` | MinIO root username. | Required | `minioadmin` | Stored as a secret; in the single-node setup it also seeds app S3 credentials when explicit S3 keys are omitted. | Yes |
| `MINIO_ROOT_PASSWORD` | MinIO root password. | Required | `minioadmin123` | Use a strong production value and rotate carefully. | Yes |
| `S3_ENDPOINT` | Internal MinIO/S3 endpoint used by backend and worker. | Required | `http://minio:9000` | Should remain the in-cluster/internal endpoint. | No |
| `S3_EXTERNAL_ENDPOINT` | Publicly reachable S3-compatible endpoint for presigned receipt URLs. | Required | `http://localhost:9000` | Use the canonical production endpoint `https://storage.nexavend.store:8443` unless a clean-host Cloudflare Origin Rule has been deliberately added and tested. | No |
| `S3_ACCESS_KEY` | Explicit S3 access key override. | Optional | blank | Leave blank to reuse `MINIO_ROOT_USER`; stored as a secret. | Yes |
| `S3_SECRET_KEY` | Explicit S3 secret key override. | Optional | blank | Leave blank to reuse `MINIO_ROOT_PASSWORD`; stored as a secret. | Yes |
| `S3_REGION` | S3 region value used by the client. | Required | `eu-central-1` | Keep stable once objects exist. | No |
| `S3_BUCKET_RECEIPTS` | Private bucket for uploaded receipt objects. | Required | `receipts` | Do not make public; access should stay presigned only. | No |
| `S3_BUCKET_BACKUPS` | Private bucket for PostgreSQL backups. | Required | `postgres-backups` | Used by the backup CronJob in production. | No |
| `S3_PRESIGNED_PUT_EXPIRY_SECONDS` | Receipt upload URL TTL. | Required | `600` | Keep short; mobile flow should upload immediately after creation. | No |
| `S3_PRESIGNED_GET_EXPIRY_SECONDS` | Receipt preview URL TTL. | Required | `600` | Keep short because receipts are sensitive. | No |
| `FIREBASE_SERVICE_ACCOUNT_PATH` | File path to the Firebase Admin service account JSON. | Required | `/run/secrets/firebase_sa.json` | The Kubernetes startup command writes the decoded service-account file to this path before the app starts. | No |
| `FIREBASE_SERVICE_ACCOUNT_JSON_B64` | Base64-encoded Firebase Admin service account JSON. | Required for the env-driven Kubernetes path | blank | The production container commands decode this into `FIREBASE_SERVICE_ACCOUNT_PATH` before startup. | Yes |
| `LLM_PROVIDER` | Logical LLM provider name. | Required | `google` | Currently the receipt path supports Google Gemini. | No |
| `GOOGLE_API_KEY` | Gemini/Google AI API key for receipt extraction. | Required | blank | Required for the launch-critical receipt pipeline. | Yes |
| `LLM_MODEL_NAME` | Gemini model name used by receipt extraction. | Required | `gemini-2.5-flash` | Keep explicit so production changes are deliberate. | No |
| `RECEIPT_PROCESSING_STALE_AFTER_MINUTES` | Threshold after which a stuck `PROCESSING` receipt is considered stale. | Required | `15` | Tune conservatively to avoid duplicate work. | No |
| `RECEIPT_PROCESSING_MAX_RETRIES` | Max worker retry count for receipt jobs. | Required | `3` | Keep modest to avoid retry storms. | No |
| `RECEIPT_PROCESSING_RETRY_BACKOFF_SECONDS` | Sleep/backoff before requeue-driven retry. | Required | `5` | Keep short but non-zero so redelivery is not immediate. | No |

## FX, Metrics, And LangSmith

| Name | Purpose | Required | Dev Example | Production Notes | Secret |
| --- | --- | --- | --- | --- | --- |
| `FRANKFURTER_BASE_URL` | Primary FX provider base URL. | Required | `https://api.frankfurter.app` | Keep default unless the provider changes. | No |
| `CURRENCY_API_CDN_BASE_URL` | Fallback FX provider base URL. | Required | `https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api` | Keep default unless you intentionally swap providers. | No |
| `FX_HTTP_TIMEOUT_SECONDS` | Outbound FX provider timeout. | Required | `8` | Avoid setting this too high on a single VPS. | No |
| `METRICS_ENABLED` | Toggle internal metrics exposure. | Required | `true` | Leave enabled in production for Prometheus scraping. | No |
| `METRICS_API_PATH` | API metrics path. | Required | `/metrics` | Keep internal-only at the ingress layer. | No |
| `WORKER_METRICS_PORT` | Worker metrics bind port. | Required | `9101` | Scraped internally by Prometheus; do not expose publicly. | No |
| `LANGSMITH_TRACING` | Toggle LangSmith tracing. | Required | `false` | Enable in production only when the LangSmith project and API key are configured. | No |
| `LANGSMITH_API_KEY` | LangSmith API key. | Optional | blank | Required whenever `LANGSMITH_TRACING=true`. | Yes |
| `LANGSMITH_PROJECT` | LangSmith project/environment identifier. | Required | `ai-expense-tracker-dev` | Use a distinct production project name to separate traces cleanly. | No |
| `LANGSMITH_ENDPOINT` | LangSmith API endpoint. | Required | `https://api.smith.langchain.com` | Override only for self-hosted or regional setups. | No |
| `LANGSMITH_HIDE_INPUTS` | Hide raw trace inputs from LangSmith by default. | Required | `true` | Keep enabled for receipt privacy. | No |
| `LANGSMITH_HIDE_OUTPUTS` | Hide raw trace outputs from LangSmith by default. | Required | `true` | Keep enabled for receipt privacy. | No |
| `BACKEND_IMAGE` | Pullable container image for the API and worker workloads. | Required | `ghcr.io/fotapol/ai-expense-tracker-backend:prod-1` | The render script rejects placeholder `ghcr.io/example/...` images and `:latest` in production. | No |
| `SITE_IMAGE` | Pullable container image for the public static site workload. | Required when deploying the public site | `ghcr.io/fotapol/ai-expense-tracker-site:prod-1` | Build from `site/Dockerfile` and publish it before applying the production overlay. | No |
| `POSTGRES_BACKUP_IMAGE` | Pullable container image for the PostgreSQL backup CronJob. | Required | `ghcr.io/fotapol/ai-expense-tracker-postgres-backup:prod-1` | Build from `infra/images/postgres-backup/Dockerfile` and publish it before applying the production overlay. | No |
| `PROMETHEUS_RETENTION_TIME` | Prometheus local retention window. | Required | `7d` | Tune for VPS disk budget. | No |
| `PROMETHEUS_RETENTION_SIZE` | Prometheus max local retention size. | Required | `2GB` | Tune for VPS disk budget. | No |
| `PROMETHEUS_SCRAPE_INTERVAL` | Prometheus scrape interval for API/worker/internal targets. | Required | `15s` | Rendered into the generated Prometheus config file. | No |
| `PROMETHEUS_EVALUATION_INTERVAL` | Prometheus rule evaluation interval. | Required | `15s` | Keep aligned with scrape interval unless you have a specific reason to diverge. | No |
| `GRAFANA_ADMIN_USER` | Grafana admin username. | Required | `admin` | Stored as a secret to avoid casual disclosure. | Yes |
| `GRAFANA_ADMIN_PASSWORD` | Grafana admin password. | Required | `admin-change-me` | Use a strong unique value in production. | Yes |
| `GRAFANA_ROOT_URL` | Canonical Grafana base URL. | Required | `http://grafana.local` | If Grafana stays internal, use the internal operator URL you intend to access. | No |
| `POSTGRES_BACKUP_SCHEDULE` | Cron expression for PostgreSQL backups. | Required | `0 3 * * *` | Injected into the Kubernetes `CronJob` schedule. | No |
| `POSTGRES_BACKUP_RETENTION_DAYS` | Backup retention window in days. | Required | `30` | Used by the backup job when pruning old objects from MinIO. | No |
| `POSTGRES_BACKUP_PREFIX` | Key prefix used inside the backup bucket. | Required | `postgres` | Helps keep backup objects grouped and restore-friendly. | No |

## Billing, Webhooks, And Dev Guards

| Name | Purpose | Required | Dev Example | Production Notes | Secret |
| --- | --- | --- | --- | --- | --- |
| `REVENUECAT_SECRET_API_KEY` | RevenueCat server-side API key. | Optional | blank | Required for server-initiated subscriber sync. | Yes |
| `REVENUECAT_API_BASE_URL` | RevenueCat API base URL. | Required | `https://api.revenuecat.com` | Keep default unless RevenueCat changes their API domain. | No |
| `REVENUECAT_HTTP_TIMEOUT_SECONDS` | RevenueCat HTTP timeout. | Required | `8` | Avoid long waits on subscription sync calls. | No |
| `REVENUECAT_PERSONAL_PREMIUM_ENTITLEMENT_ID` | Personal premium entitlement ID. | Required | `personal_premium` | Must match RevenueCat dashboard config. | No |
| `REVENUECAT_FAMILY_PREMIUM_ENTITLEMENT_ID` | Family premium entitlement ID. | Required | `family_premium` | Kept for compatibility even though family is not launch scope. | No |
| `REVENUECAT_PERSONAL_PRODUCT_IDS` | Comma-separated personal product IDs. | Required | `personal_premium,individual_plan_monthly,individual_plan_yearly` | Must match RevenueCat product mapping. | No |
| `REVENUECAT_FAMILY_PRODUCT_IDS` | Comma-separated family product IDs. | Required | `family_premium,family_plan_monthly,family_plan_yearly` | Keep explicit for compatibility with existing billing code. | No |
| `REVENUECAT_WEBHOOK_AUTH_HEADER` | Header name expected on RevenueCat webhook calls. | Required | `Authorization` | Used to validate webhook authenticity. | No |
| `REVENUECAT_WEBHOOK_AUTH_SECRET` | Shared secret/token for RevenueCat webhook auth. | Optional | blank | Required once webhook processing is enabled. | Yes |
| `ENABLE_DEV_BILLING_ENDPOINTS` | Toggle dev-only billing mutation routes. | Required | `false` | Must remain `false` in production. | No |
| `DEV_BILLING_INTERNAL_SECRET` | Shared secret for dev billing routes. | Optional | blank | Only set for local/dev workflows. | Yes |
| `DEV_BILLING_ADMIN_EMAILS` | Additional comma-separated admin emails for dev billing flows. | Optional | blank | Useful only in local/dev. | No |

## Mobile App And Site Metadata

These values are part of the overall operator-facing config. They are used by the Flutter build and, when the public static site is deployed, are also exposed to the site container through the rendered ConfigMap.

| Name | Purpose | Required | Dev Example | Production Notes | Secret |
| --- | --- | --- | --- | --- | --- |
| `APP_WEBSITE_URL` | Canonical website link shown in the app and used by the static site header/footer links. | Optional | `http://localhost:3000` | Keep aligned with the real public website. If omitted in production rendering, it falls back to `PUBLIC_APP_BASE_URL`. | No |
| `APP_PRIVACY_URL` | Privacy-policy link shown in the app and used by the static site legal navigation. | Optional | `http://localhost:3000/privacy` | Keep aligned with the real public policy page. If omitted in production rendering, it falls back to `APP_WEBSITE_URL + /privacy`. | No |
| `APP_TERMS_URL` | Terms-of-service link shown in the app and used by the static site legal navigation. | Optional | `http://localhost:3000/terms` | Keep aligned with the real public terms page. If omitted in production rendering, it falls back to `APP_WEBSITE_URL + /terms`. | No |
| `APP_DELETE_ACCOUNT_URL` | Account-deletion instruction link shown in app/legal surfaces. | Required for production mobile builds | `http://localhost:3000/delete-account` | Production Android builds require `https://nexavend.store/delete-account`. If omitted in production rendering, it falls back to `APP_WEBSITE_URL + /delete-account`. | No |
| `APP_PLAY_SUBSCRIPTIONS_URL` | Google Play subscription management link opened for active Android subscribers. | Optional | `https://play.google.com/store/account/subscriptions?package=com.nexavend.expense_tracker_app` | Override only if the package-specific Play management URL changes. | No |
| `APP_GITHUB_URL` | Repository/support code link shown in the app. | Optional | `https://github.com/expense-tracker/ai-expense-tracker` | Adjust if the public repo URL changes. | No |
| `APP_SUPPORT_EMAIL` | Support email displayed in the app and rendered into the public site support CTA. | Optional | `support@example.com` | Use the real operator support mailbox. | No |
| `APP_SUPPORT_SUBJECT` | Default support email subject for mailto links. | Optional | `Expense Tracker Support` | Keep human-friendly. | No |
| `SITE_APP_STORE_URL` | Optional App Store button target on the public site. | Optional | blank | When blank, the App Store button is hidden. | No |
| `SITE_GOOGLE_PLAY_URL` | Optional Google Play button target on the public site. | Optional | blank | When blank, the Google Play button is hidden. | No |
| `SITE_OPEN_APP_URL` | Optional direct open-app button target on the public site. | Optional | blank | Use this for a web app, deep link, or other primary destination if you have one. | No |
| `API_BASE_URL` | Flutter build-time backend URL define. | Required for real mobile builds | `http://10.0.2.2:8000` | Set to the same public API URL as `PUBLIC_API_BASE_URL` in production mobile builds, for example `https://api.nexavend.store:8443`. | No |
| `REVENUECAT_ANDROID_API_KEY` | RevenueCat Android public SDK key. | Optional | blank | Required for Android subscription UI flows. | No |
| `REVENUECAT_IOS_API_KEY` | RevenueCat iOS public SDK key. | Optional | blank | Required only if an iOS client is built. | No |
| `REVENUECAT_PREMIUM_ENTITLEMENT_ID` | Flutter-side default premium entitlement ID. | Optional | `personal_premium` | Keep aligned with the backend entitlement mapping. | No |
