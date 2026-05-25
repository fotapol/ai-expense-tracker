# AI Expense Tracker Production Readiness Audit

Audit date: 2026-04-29  
Repository: `e:\repositories\internal-repos\ai-expense-tracker`  
Auditor posture: production readiness, security, backend/mobile, DevOps/Kubernetes, Google Play launch review  
Secret handling: all production secret values are redacted; no real secret values are included.

## 1. Executive Summary

AI Expense Tracker has a recognizable MVP architecture: Flutter Android app, FastAPI backend, PostgreSQL, Redis, RabbitMQ, MinIO, receipt worker, Gemini-based extraction, Firebase Auth, RevenueCat, LangSmith, Prometheus/Grafana, and K3s production manifests using F5 NGINX `VirtualServer` resources on HTTPS port `8443`.

The project is not ready for Google Play MVP production launch. Core pieces exist and several local checks pass, but there are launch blockers in mobile release signing/configuration, production deploy reproducibility, RabbitMQ bootstrap, private image pulling, public exposure of API operational endpoints, and paid subscription readiness.

Live public probes confirmed that the legal pages are reachable:

- `https://nexavend.store/` -> `200`
- `https://nexavend.store/privacy` -> `200`
- `https://nexavend.store/terms` -> `200`
- `https://nexavend.store/delete-account` -> `200`

However, live public probes also confirmed that API operational surfaces are exposed:

- `https://api.nexavend.store:8443/metrics` -> `200`
- `https://api.nexavend.store:8443/docs` -> `200`
- `https://api.nexavend.store:8443/openapi.json` -> `200`
- `https://api.nexavend.store:8443/health/live` -> `200`
- `https://api.nexavend.store:8443/health/ready` -> `200`

## 2. Final Readiness Verdict

**NOT READY — BLOCKERS EXIST**

This is evidence-based. The application can build in parts, and the public site/legal pages are live, but production launch cannot be approved while the Android release artifact is unsigned for production, the release API URL is not enforced, production K8s cannot reliably pull private images, RabbitMQ user bootstrap is not repo-defined, and operational endpoints are publicly exposed.

## 3. Top 10 Risks

1. **P0:** Android release build signs with the debug key.
2. **P0:** Production mobile API URL is not enforced; default is emulator-local `http://10.0.2.2:8000`.
3. **P0:** RabbitMQ production user is not bootstrapped declaratively in Kubernetes.
4. **P0:** Private GHCR images have no Kubernetes `imagePullSecrets`.
5. **P0:** Public API exposes `/metrics`, `/health/*`, `/docs`, and `/openapi.json`.
6. **P0:** `.env.production` is missing `SITE_IMAGE`; production render falls back to placeholder `ghcr.io/example/...:latest`.
7. **P1:** Prometheus uses a single PVC but has no `Recreate` deployment strategy.
8. **P1:** Full backend test suite fails collection; full ruff check fails with 95 issues.
9. **P1:** Deleting a receipt removes DB rows but does not delete the underlying MinIO object.
10. **P1:** Subscription cancellation/manage link required by Google Play is not implemented in-app.

## 4. P0 Launch Blockers

### P0-1: Android release signing uses debug key

Evidence:

- `expense_tracker_app/android/app/build.gradle.kts:38-41`
- `release { signingConfig = signingConfigs.getByName("debug") }`

Impact:

- Google Play production release should not be shipped with debug signing.
- Key continuity, Play App Signing setup, and upgrade path are unsafe.

Recommended fix: create a real release signing setup using local/CI secrets and Play App Signing.  
Effort: small task.

### P0-2: Production mobile build can point to local emulator API

Evidence:

- `expense_tracker_app/lib/core/api_client.dart:32-34`
- Default `API_BASE_URL` is `http://10.0.2.2:8000`.
- `flutter build appbundle --release` passed, but the audited build was run without production dart-defines.

Impact:

- A Play-distributed build can fail auth/API/receipt upload if built without `--dart-define=API_BASE_URL=https://api.nexavend.store:8443`.

Recommended fix: add a production release script/workflow that requires `API_BASE_URL`, RevenueCat key, public legal URLs, and support email. Fail if missing.  
Effort: quick fix.

### P0-3: RabbitMQ user bootstrap is not repo-defined

Evidence:

- `infra/k8s/base/rabbitmq-statefulset.yaml:32-36` only injects ConfigMap/Secret environment.
- No `RABBITMQ_DEFAULT_USER`, `RABBITMQ_DEFAULT_PASS`, definitions file, or init job found.
- `render_k8s_env.py` creates `RABBITMQ_URL`, but does not bootstrap the broker user.

Impact:

- Fresh deploy or PVC recreation can require manual `rabbitmqctl add_user expense_tracker`.
- Receipt upload confirmation and worker processing can fail if the app user does not exist.
- Production state is not reproducible from repo.

Recommended fix: configure RabbitMQ with repo-defined `RABBITMQ_DEFAULT_USER`, `RABBITMQ_DEFAULT_PASS`, and vhost, or mount a definitions file/init job.  
Effort: small task.

### P0-4: Private GHCR images lack `imagePullSecrets`

Evidence:

- No `imagePullSecrets` found in base or rendered production manifests.
- Production images reference GHCR, e.g. backend and backup images.
- User context says GHCR images are private and a Kubernetes imagePullSecret is expected.

Impact:

- A clean cluster apply can fail with `ImagePullBackOff`.

Recommended fix: add a namespaced registry secret and reference it via ServiceAccount or pod `imagePullSecrets`.  
Effort: quick fix.

### P0-5: Public API exposes metrics/docs/health

Evidence:

- `backend/app/core/metrics.py:134-143` installs `/metrics` without auth.
- `backend/app/main.py` uses default FastAPI docs/openapi settings.
- `infra/k8s/overlays/production/api-virtualserver.yaml:18-21` routes `/` to API.
- Live probes returned `200` for `/metrics`, `/docs`, `/openapi.json`, `/health/live`, and `/health/ready`.

Impact:

- Monitoring/admin data is public, contrary to the launch requirement.
- `/health/ready` exposes dependency status.
- `/metrics` exposes process/runtime and app metrics.

Recommended fix: block these paths at F5 VirtualServer policy or disable docs/metrics publicly and scrape internally.  
Effort: quick fix.

### P0-6: Production site image is missing in `.env.production`

Evidence:

- Local redacted inventory showed `SITE_IMAGE=missing` in `.env.production`.
- `render_k8s_env.py:175-177` has placeholder defaults.
- Rendered production overlay showed `SITE_IMAGE: ghcr.io/example/ai-expense-tracker-site:latest`.

Impact:

- Clean production deploy can fail to pull the site image.
- Public legal pages may depend on manual cluster drift.

Recommended fix: set `SITE_IMAGE` in production and make placeholder images fail validation.  
Effort: quick fix.

### P0-7: Paid launch is not Google Play subscription-ready

Evidence:

- RevenueCat integration exists, but no direct Google Play subscription management/cancellation link was found in app settings/paywall.
- Google Play Subscriptions policy requires an easy-to-use online method to cancel, satisfied by a Google Play Subscription Center link or direct cancellation process.

Reference:

- Google Play Subscriptions policy: https://support.google.com/googleplay/android-developer/answer/9900533?hl=en

Impact:

- Paid subscription launch can be rejected or users can be misled about cancellation.

Recommended fix: add a visible manage/cancel subscription link in profile/settings/subscription screens.  
Effort: small task.

## 5. P1 Must-Fix Issues

- **Prometheus rollout risk:** `infra/k8s/base/prometheus-deployment.yaml` uses one PVC (`prometheus-data`) but has no `strategy: Recreate`. Effort: quick fix.
- **Full backend tests fail:** `uv run pytest` fails collecting `tests/test_labels_api.py` because `app.schemas.labels` is missing. Effort: small task.
- **Full backend ruff fails:** `uv run ruff check .` reports 95 issues. Effort: small task.
- **Backend dependency vulnerabilities:** `pip-audit` found 20 known vulnerabilities in 10 packages. Effort: small/medium task.
- **Firebase revoked tokens not checked:** `backend/app/auth/firebase_admin.py:45` uses `check_revoked=False`. Effort: quick fix, with performance consideration.
- **Receipt content validation is weak:** server trusts declared MIME/Content-Type; no magic sniffing. Effort: small task.
- **Oversized rejected objects are not deleted:** confirm rejects size but leaves uploaded object. Effort: small task.
- **Receipt delete leaves object storage:** `DELETE /v1/receipts/{id}` deletes DB rows but not MinIO object. Effort: small task.
- **Account deletion cleanup ordering:** DB deletion commits before best-effort storage/Firebase deletion; no retry path. Effort: medium task.
- **In-app legal copy stale:** app includes `privacy@expensetracker.com`, `legal@expensetracker.com`, family-plan copy, and security claims that do not match public docs. Effort: small task.
- **Storage public endpoint mismatch:** `.env.production` has `S3_EXTERNAL_ENDPOINT=https://storage.nexavend.store`; `.env.production.example` expects `https://storage.nexavend.store:8443`. Effort: quick fix or document Cloudflare Origin Rule.
- **No restore proof:** backup path exists, but restore dry run was not executed. Effort: medium task.

## 6. P2 Should-Fix Issues

- Default FastAPI docs/OpenAPI are enabled in production.
- No `TrustedHostMiddleware` found.
- `--forwarded-allow-ips="${UVICORN_FORWARDED_ALLOW_IPS:-*}"` trusts all forwarded headers.
- No explicit CORS policy found.
- Startup migrations run automatically on API startup.
- CI does not run full backend tests, Flutter tests, Android release build, site image build, dependency audit, or image push.
- Dockerfile uses `COPY --from=ghcr.io/astral-sh/uv:latest`.
- No container `securityContext`/non-root hardening found.
- No Kubernetes NetworkPolicies found.
- Flutter dependencies have resolvable upgrades.

## 7. P3 Improvements

- Replace Android app label `expense_tracker_app` with a polished product name.
- Remove or disable household deep link until household feature ships.
- Add release notes/changelog automation.
- Add alerting rules for queue depth, AI failures, backup failures, disk/PVC usage, and public endpoint anomalies.
- Add restore rehearsal automation.
- Add object lifecycle/retention policies for receipts and backups.

## 8. Backend Audit

### Route Inventory

Public/no Firebase auth:

- `GET /`
- `GET /health/live`
- `GET /health/ready`
- `GET /metrics`
- `GET /docs`
- `GET /openapi.json`
- `GET /redoc`
- `POST /v1/billing/revenuecat/webhook` with shared secret validation

Firebase-authenticated:

- `/v1/me` GET/PATCH/DELETE
- `/v1/receipts*`
- `/v1/transactions*`
- `/v1/categories*`
- `/v1/labels*`
- `/v1/item-translations/batch`
- `/v1/data/export`
- `/v1/data/import`
- `/v1/planning/*`
- `/v1/feature-requests*`
- `/v1/billing/revenuecat/sync`
- `/v1/me/subscription`
- `/v1/me/entitlements`

Admin/internal:

- `/internal/feature-requests*` requires Firebase auth and admin access assertion.

Development-only:

- Internal dev billing routes are conditionally mounted outside production.

### Findings

- Startup performs production config validation, migrations, Firebase init, Redis check, RabbitMQ connect, and bucket creation.
- Global exception handler returns generic 500, which is good.
- Rate limiting exists across key routes.
- Request ID middleware exists.
- Metrics middleware exists, but the endpoint is public.
- OpenAPI/docs are public.
- Receipt routes enforce user ownership.
- Transaction visibility appears user-scoped for launch while household sharing is disabled.

Backend verdict: not production-ready until public operational endpoints are blocked and full validation failures are fixed.

## 9. Mobile App Audit

Evidence:

- `flutter analyze` passed.
- `flutter test` passed: 99 tests.
- `flutter build appbundle --release` passed.
- Release signing uses debug key.
- `applicationId = "com.nexavend.expense_tracker_app"`.
- Android namespace remains `com.example.expense_tracker_app`.
- Manifest label is `expense_tracker_app`.
- Manifest includes `RECEIVE_BOOT_COMPLETED`, `POST_NOTIFICATIONS`, and `SCHEDULE_EXACT_ALARM`.
- Manifest has a household invite deep link while household is disabled.

Verdict: not Play production-ready. It can build, but release signing/configuration and policy-facing details must be fixed first.

## 10. Receipt Pipeline Audit

Sequence:

1. Mobile prepares receipt.
2. Mobile calls `POST /v1/receipts`.
3. Backend creates receipt row with status `CREATED`.
4. Backend returns presigned PUT URL.
5. Mobile uploads file to MinIO/S3-compatible endpoint.
6. Mobile calls `POST /v1/receipts/{id}/confirm-upload`.
7. Backend checks object with S3 HEAD, size limit, and usage quota.
8. Backend sets status `UPLOADED`.
9. Backend publishes persistent RabbitMQ message.
10. Worker consumes queue.
11. Worker downloads object.
12. Worker calls Gemini structured extraction.
13. Worker validates structured output with Pydantic schema.
14. Worker stores extraction, transaction, and items.
15. Worker marks receipt `COMPLETED`; failures become `FAILED` after retries.
16. Mobile polls receipt status and shows result/failure.

Strengths:

- User-scoped object key prefix.
- Persistent RabbitMQ messages.
- Worker idempotency checks for completed/existing extraction.
- Stale processing retry logic.
- LangSmith inputs/outputs appear redacted via helper functions.

Risks:

- RabbitMQ bootstrap is a launch blocker.
- No server-side file magic validation.
- Oversized rejected files remain in storage.
- Deleted receipts leave object storage behind.
- No E2E live AI extraction test was executed.

Receipt flow verdict: not production-ready.

## 11. Auth/Account Deletion Audit

Auth model:

- Firebase Admin SDK initializes from a server-side service account path.
- Backend verifies Firebase ID token.
- Local user identity derives from Firebase UID (`auth_subject`).
- User auto-creation requires verified email.
- Admin access is email allowlist based.

Account deletion:

- Backend `DELETE /v1/me` exists and requires Firebase auth.
- In-app account deletion exists in profile settings.
- Public `/delete-account` page exists and is live.
- Deletion covers many local tables, storage best-effort, webhook anonymization, and Firebase user best-effort deletion.

Risks:

- Revoked Firebase tokens are not checked because `check_revoked=False`.
- Account deletion relies on current token but no recent re-authentication.
- DB deletion commits before storage/Firebase deletion; external cleanup has no retry mechanism.

Reference:

- Google Play account deletion requirements: https://support.google.com/googleplay/android-developer/answer/13327111?hl=en

Verdict: account deletion path exists, but cleanup reliability should be fixed before broad release.

## 12. Billing/RevenueCat/Google Play Audit

What exists:

- Mobile RevenueCat SDK wrapper.
- Backend RevenueCat sync endpoint.
- Backend webhook with shared-secret validation.
- Webhook event idempotency storage.
- Subscription/entitlement models and mapping.
- App can run with RevenueCat disabled if public SDK key is absent.

Blocking before paid launch:

- No Google Play Subscription Center/manage-cancel link found in-app.
- Google Play products/base plans/offerings were not verified.
- RevenueCat dashboard offerings/entitlements were not verified.
- Family product/entitlement config still exists while family feature is disabled.
- No sandbox purchase/restore/cancel E2E test was executed.

References:

- Google Play Subscriptions policy: https://support.google.com/googleplay/android-developer/answer/9900533?hl=en
- Google Play Payments policy: https://support.google.com/googleplay/android-developer/answer/9858738?hl=en
- Google Play subscription model concepts: https://support.google.com/googleplay/android-developer/answer/12154973?hl=en

Billing verdict: backend foundation is promising, but paid launch is not ready.

## 13. Infrastructure/Kubernetes Audit

Good evidence:

- Production overlay uses F5 `VirtualServer` resources.
- No ordinary Kubernetes `Ingress` was found in the production overlay.
- `api`, `site`, and `storage` VirtualServers use `https-8443`.
- Postgres, Redis, RabbitMQ, Prometheus, Grafana, worker metrics, and MinIO console are internal services.
- Backup CronJob exists.
- App deployments have probes and resource requests/limits.

Blockers:

- No `imagePullSecrets`.
- RabbitMQ user bootstrap missing.
- `SITE_IMAGE` missing from real production env and fallback placeholder is used.
- Prometheus missing `Recreate`.
- Public API VirtualServer routes all paths to API, exposing operational routes.

Production reproducibility verdict: not acceptable yet. `kubectl apply -k infra/k8s/overlays/production` can render after generated files exist, but the resulting state is not safe/reproducible enough for clean production.

## 14. Cloudflare/Domain/TLS Audit

Commands:

```powershell
curl.exe -L --connect-timeout 10 --max-time 20 -sS -o NUL -w "%{http_code} tls=%{ssl_verify_result} ip=%{remote_ip} url=%{url_effective}" <url>
```

Results:

- `https://nexavend.store/` -> `200`, TLS verify OK.
- `https://nexavend.store/privacy` -> `200`, TLS verify OK.
- `https://nexavend.store/terms` -> `200`, TLS verify OK.
- `https://nexavend.store/delete-account` -> `200`, TLS verify OK.
- `https://nexavend.store:8443/` -> `200`, TLS verify OK.
- `https://api.nexavend.store:8443/` -> `200`, TLS verify OK.
- `https://api.nexavend.store:8443/health/live` -> `200`, TLS verify OK.
- `https://api.nexavend.store:8443/health/ready` -> `200`, TLS verify OK.
- `https://api.nexavend.store:8443/metrics` -> `200`, TLS verify OK.
- `https://api.nexavend.store:8443/docs` -> `200`, TLS verify OK.
- `https://api.nexavend.store:8443/openapi.json` -> `200`, TLS verify OK.
- `https://storage.nexavend.store:8443/` -> `403`, expected for S3 root.
- `https://storage.nexavend.store/` -> `403`, likely Cloudflare origin rule or port rewrite.

Verdict: TLS works publicly, but API operational path exposure is a blocker. Storage root `403` is not itself a failure.

## 15. Storage/MinIO Audit

What exists:

- MinIO StatefulSet and service.
- S3 API routed publicly via storage VirtualServer.
- Console port is internal only.
- Bucket creation helper exists.
- Presigned PUT/GET helpers exist.
- Object keys are user and receipt scoped.

Risks:

- `S3_EXTERNAL_ENDPOINT` mismatch between real `.env.production` and example.
- Storage VirtualServer sets `X-Forwarded-Port: "443"`; ensure this matches Cloudflare signing behavior.
- File type enforcement relies on MIME/Content-Type, not magic sniffing.
- Receipt object deletion is incomplete for single receipt delete.
- No lifecycle policy found.
- Backups are stored in the same MinIO cluster unless replicated externally.

Verdict: storage exposure shape is mostly correct, but deletion and endpoint consistency must be fixed.

## 16. Database/Backup Audit

Evidence:

- `uv run alembic heads` passed with a single head.
- Startup migrations are run by `backend/app/core/migrations.py`.
- Critical user-scoped indexes exist for receipts, subscriptions, planning tables, categories, etc.
- Backup CronJob exists at `infra/k8s/base/postgres-backup-cronjob.yaml`.
- Backup image exists at `infra/images/postgres-backup/Dockerfile`.
- Backup script uploads custom-format `pg_dump` to MinIO and prunes by retention.

Risks:

- Startup migrations during app boot can make rollouts fragile.
- Restore was not tested.
- Single VPS/local-path PVC means disk/node failure is high impact.
- Backup bucket is same MinIO unless externally replicated.

Verdict: backups are scaffolded but not proven.

## 17. Monitoring/Logging/LangSmith Audit

What exists:

- Structured logging helper.
- Request ID middleware and `X-Request-ID`.
- Prometheus metrics for API and worker.
- Worker metrics service is internal.
- Grafana dashboards/datasources ConfigMaps exist.
- LangSmith helper redacts receipt inputs and outputs.
- Production env has `LANGSMITH_HIDE_INPUTS=true` and `LANGSMITH_HIDE_OUTPUTS=true`.

What can be debugged:

- API request counts/latency/status.
- Worker extraction attempts, retries, failures.
- RevenueCat webhook outcomes.
- Dependency readiness via health endpoint.

What cannot be considered ready:

- Public `/metrics` exposure.
- Prometheus targets were not verified in the live cluster.
- Grafana dashboards were not verified.
- LangSmith project traces were not externally verified.
- Alerting rules were not found.

Recommended alerts:

- API 5xx rate.
- API p95 latency.
- Receipt extraction failure rate.
- RabbitMQ queue depth/oldest message age.
- Worker retry exhaustion.
- Postgres backup CronJob failure/missing recent backup.
- PVC disk usage.
- Prometheus scrape failures.
- AI provider error/timeout rate.

## 18. Security Audit

Security risk matrix:

| Severity | Risk | Evidence | Fix |
|---|---|---|---|
| P0 | Public metrics/docs/health | live `200` responses | Block/disable externally |
| P0 | Missing private registry pull secret | no `imagePullSecrets` | Add secret reference |
| P0 | RabbitMQ user manual bootstrap risk | no default user/init/definitions | Declarative bootstrap |
| P1 | Firebase revoked tokens not checked | `check_revoked=False` | Enable revocation check or compensating controls |
| P1 | Upload validation weak | no magic sniffing | Validate content server-side |
| P1 | Dependency vulnerabilities | `pip-audit` found 20 | Upgrade/fix |
| P1 | Receipt object retention after delete | no MinIO delete in receipt delete | Delete object or retention policy |
| P2 | Proxy trust too broad | forwarded allow IPs `*` | Restrict to ingress/controller |
| P2 | No NetworkPolicies | none found | Add default-deny/internal allow |
| P2 | No container securityContext | none found | Run non-root, drop caps |

Secret handling:

- `.env`, `.env.production`, `origin.crt`, `origin.key`, generated secret/config files are ignored by `.gitignore`.
- `git ls-files` showed `.env.production`, origin TLS key/cert, and Firebase service-account JSON are not tracked.
- `expense_tracker_app/android/app/google-services.json` is tracked; this is mobile-public Firebase config, but API key restrictions should be configured in Firebase/Google Cloud.

Verdict: not production safe until P0/P1 security findings are addressed.

## 19. Legal/Google Play Policy Audit

Public legal docs:

- `PRIVACY.md` and `TERMS.md` are present.
- Public legal pages are live.
- Support email is `support@nexavend.store`.
- Privacy/Terms disclose receipt data, AI processing, Google Play, RevenueCat, Firebase/Google, Google Gemini or similar AI services, account deletion, retention limitations, and no professional tax/legal/financial advice.

Policy risks:

- In-app legal copy is stale and inconsistent with public docs.
- Data Safety form must include user data transmitted off-device and SDK behavior.
- App uses sensitive receipt/financial data; Data Safety must be accurate.
- Subscription cancellation link must be present before payments are enabled.

References:

- Google Play Data Safety: https://support.google.com/googleplay/android-developer/answer/10787469?hl=en
- Google Play User Data policy: https://support.google.com/googleplay/android-developer/answer/10144311?hl=en
- Google Play account deletion requirements: https://support.google.com/googleplay/android-developer/answer/13327111?hl=en
- Google Play Subscriptions policy: https://support.google.com/googleplay/android-developer/answer/9900533?hl=en

Data Safety outline:

- Account identifiers/email: collected, linked to user, app functionality/account management.
- Receipt images/files: collected, linked to user, app functionality.
- Financial/purchase/expense data: collected, linked to user, app functionality/analytics.
- App activity/diagnostics: collected if logs/metrics/crash tooling capture it.
- Third-party processing/sharing: Firebase/Google Auth, Google Play, RevenueCat, Google AI/Gemini, LangSmith if enabled.
- Deletion: in-app and web deletion available, but cleanup reliability should be improved.

## 20. CI/CD/Release Audit

Current CI:

- Backend dependency sync.
- Render production overlay from `.env.production.example`.
- Launch-safe backend ruff subset.
- Launch-safe backend test subset.
- Alembic head validation.
- Kustomize render validation.
- Backend and backup Docker builds.
- Flutter dependency install and analyze.

Missing CI gates:

- Full backend ruff.
- Full backend pytest.
- Flutter tests.
- Android release appbundle build.
- Android signing verification.
- Site image build.
- Production image push.
- Dependency vulnerability audit.
- K8s policy/security validation.

Manual deploy:

- Restores `.env.production` from GitHub secret.
- Renders production artifacts.
- Validates Kustomize.
- Builds backend and backup local images.
- Optionally applies overlay.

Missing release process:

- No GHCR push in deploy workflow.
- No site image build/push.
- No imagePullSecret creation/check.
- No rollback workflow.
- No Play Store deployment workflow, which is acceptable for MVP, but release steps must be documented.

Verdict: CI/CD is partial and not production-gated.

## 21. Full Key/Secret Inventory

| Name | Source | Where used | Class | Production value present? | Risk |
|---|---|---|---|---|---|
| `.env.production` | local ignored file | deploy/render | operator-only | yes/redacted | high if mishandled |
| `POSTGRES_PASSWORD` | `.env.production` | Postgres/API/backup | private | yes/redacted | high |
| `DATABASE_URL` | derived or explicit | API/worker/backup | private | derived/redacted | high |
| `REDIS_URL` | derived or explicit | API/worker | private | derived/redacted | medium |
| `RABBITMQ_PASSWORD` | `.env.production` | API/worker/RabbitMQ | private | yes/redacted | high; bootstrap missing |
| `RABBITMQ_ERLANG_COOKIE` | `.env.production` | RabbitMQ | private | yes/redacted | high |
| `RABBITMQ_URL` | derived | API/worker | private | derived/redacted | high |
| `MINIO_ROOT_USER` | `.env.production` | MinIO/S3 fallback | private | yes/redacted | high |
| `MINIO_ROOT_PASSWORD` | `.env.production` | MinIO/S3 fallback | private | yes/redacted | high |
| `S3_ACCESS_KEY` | fallback to MinIO root | API/worker/backup | private | derived/redacted | root reuse risk |
| `S3_SECRET_KEY` | fallback to MinIO root | API/worker/backup | private | derived/redacted | root reuse risk |
| `FIREBASE_SERVICE_ACCOUNT_JSON_B64` | `.env.production` | API/worker Firebase Admin | server-only | yes/redacted | high |
| `FIREBASE_SERVICE_ACCOUNT_PATH` | env/config | API/worker | server-only path | yes/redacted | medium |
| `GOOGLE_API_KEY` | `.env.production` | Gemini extraction | server-only | yes/redacted | high |
| `LANGSMITH_API_KEY` | `.env.production` | tracing | server-only | yes/redacted | trace/privacy risk |
| `REVENUECAT_SECRET_API_KEY` | `.env.production` | backend RevenueCat sync | server-only | yes/redacted | high |
| `REVENUECAT_WEBHOOK_AUTH_SECRET` | `.env.production` | webhook validation | server-only | yes/redacted | high |
| `REVENUECAT_ANDROID_API_KEY` | `.env.production` | mobile build | mobile-public | yes/redacted | acceptable if public SDK key |
| `REVENUECAT_IOS_API_KEY` | `.env.production` | iOS future | mobile-public | empty | none now |
| `DEV_BILLING_INTERNAL_SECRET` | `.env.production` | dev billing only | server-only | empty | ok if disabled |
| `GRAFANA_ADMIN_PASSWORD` | `.env.production` | Grafana | operator-only | yes/redacted | high |
| `INGRESS_TLS_SECRET_NAME` | `.env.production` | VirtualServer TLS secret ref | operator-only name | yes | low |
| `origin.crt` | local ignored file | TLS secret creation | private-ish cert | present/redacted | keep outside repo |
| `origin.key` | local ignored file | TLS secret creation | private key | present/redacted | high |
| GHCR pull token | expected K8s secret | kubelet image pull | private | not found in manifests | P0 |
| Android signing key | expected release secret | Android release | private | not found | P0 |
| `google-services.json` | tracked mobile file | Firebase mobile config | mobile-public | yes | restrict API keys |

## 22. Public Endpoint Inventory

| Endpoint | Expected auth | Public/internal/operator-only | Current status |
|---|---|---|---|
| `https://nexavend.store/` | none | public | 200 |
| `https://nexavend.store/privacy` | none | public | 200 |
| `https://nexavend.store/terms` | none | public | 200 |
| `https://nexavend.store/delete-account` | none | public | 200 |
| `https://api.nexavend.store:8443/` | none | public | 200 |
| `https://api.nexavend.store:8443/health/live` | internal/operator preferred | public now | 200 |
| `https://api.nexavend.store:8443/health/ready` | internal/operator preferred | public now | 200 |
| `https://api.nexavend.store:8443/metrics` | internal only | public now | 200 P0 |
| `https://api.nexavend.store:8443/docs` | disabled/internal | public now | 200 |
| `https://api.nexavend.store:8443/openapi.json` | disabled/internal | public now | 200 |
| `https://api.nexavend.store:8443/v1/*` | Firebase except webhook | public API | protected by app route |
| `https://api.nexavend.store:8443/v1/billing/revenuecat/webhook` | shared secret | public webhook | not POST-tested |
| `https://storage.nexavend.store:8443/` | S3 auth/presign | public S3 API | 403 root expected |
| MinIO console | operator only | internal | no public route found |
| Grafana | operator only | internal | no public route found |
| Prometheus | operator only | internal | no public route found |

## 23. Internal Service Exposure Matrix

| Service | K8s exposure | Public route | Current verdict |
|---|---|---|---|
| Postgres | internal service | none | OK |
| Redis | ClusterIP | none | OK |
| RabbitMQ AMQP | internal service | none | exposure OK; bootstrap not OK |
| RabbitMQ management | internal service | none | OK |
| MinIO S3 | internal service plus storage VirtualServer | S3 API only | OK |
| MinIO console | internal service port 9001 | none | OK |
| Prometheus | ClusterIP | none direct | API metrics public |
| Grafana | ClusterIP | none | OK |
| Worker metrics | ClusterIP | none | OK |
| API | ClusterIP behind VirtualServer | public | path blocking needed |
| Site | ClusterIP behind VirtualServer | public | live, repo image bad |

## 24. Tests Executed And Results

| Command | Result | Notes |
|---|---|---|
| `uv run ruff check .` in `backend` | FAIL | 95 errors |
| CI-scoped backend `ruff check` | PASS | Launch-safe subset only |
| `uv run pytest` in `backend` | FAIL | Collection error: missing `app.schemas.labels` |
| CI-scoped backend pytest subset | PASS | 28 tests |
| `uv run alembic heads` | PASS | Single head |
| `flutter analyze` | PASS | No issues |
| `flutter test` | PASS | 99 tests |
| `flutter build appbundle --release` | PASS | Artifact uses unsafe release config unless dart-defines/signing fixed |
| `kubectl kustomize infra/k8s/overlays/production` | PASS render | Rendered unsafe site image and no pull secrets |
| `docker compose config --quiet` | PASS | Base compose valid |
| `docker compose -f docker-compose.yaml -f docker-compose.prod.yaml config --quiet` | PASS | Combined prod override valid |
| `docker compose -f docker-compose.prod.yaml config` | FAIL | Override file is not standalone |
| `python site/build_site.py --output site/dist-audit` | PASS | Temp output removed |
| `render_k8s_env.py --env-file .env.production.example` | PASS | Temp output removed |
| `pip-audit` on backend requirements | FAIL | 20 vulnerabilities |
| Public URL probes | MIXED | Legal OK, API ops exposed |
| `kubectl config current-context` | FAIL/no context | Live cluster objects not inspected |

## 25. Tests Still Required Manually

- Firebase-authenticated API request.
- Receipt upload with real user.
- Storage object creation verification.
- Worker processing success.
- Gemini extraction success.
- Gemini extraction failure.
- Malformed file rejection.
- Oversized file rejection and cleanup verification.
- Duplicate job behavior.
- Retry behavior and retry exhaustion.
- Cross-user receipt/transaction access denial.
- Account deletion end-to-end including MinIO and Firebase cleanup.
- RevenueCat webhook sandbox test.
- Google Play Billing sandbox purchase, restore, expiration, cancellation.
- Backup CronJob manual run.
- Restore dry run into disposable database.
- Prometheus target check.
- Grafana dashboard check.
- LangSmith trace privacy check.
- External API through Cloudflare after blocking internal paths.
- External storage presigned PUT/GET through Cloudflare.
- Signed Android release install smoke test.

## 26. Production Go-Live Checklist

- Add Android release signing.
- Add production Flutter build script/workflow with required dart-defines.
- Add GHCR imagePullSecret and manifest reference.
- Bootstrap RabbitMQ app user/vhost declaratively.
- Set `SITE_IMAGE` in production and fail on placeholder images.
- Block or disable public `/metrics`, `/health/*`, `/docs`, `/openapi.json`.
- Add Prometheus `Recreate` strategy.
- Fix full backend tests and full ruff.
- Upgrade vulnerable backend dependencies.
- Add subscription manage/cancel link.
- Align in-app legal/localization with public docs.
- Verify Data Safety answers against actual SDK/server data flows.
- Run receipt E2E test.
- Run account deletion E2E test.
- Run billing sandbox E2E test before enabling paid subscriptions.
- Run backup restore dry run.
- Document rollback and rehearse it.

## 27. Rollback Plan

1. Use immutable tags for backend, worker, site, and backup images.
2. Keep the previous rendered production overlay artifact for each deploy.
3. For backend/site rollback, restore previous image tags and apply the previous overlay.
4. Verify `GET /health/ready` internally, not via public path.
5. For mobile rollback, halt staged rollout or promote previous artifact in Play Console.
6. For DB problems, do not blindly rollback migrations; assess migration reversibility.
7. If data corruption occurs, restore from tested backup into a disposable DB first, then plan production restore.
8. Keep an operator runbook for RabbitMQ queue pause/drain, worker scaling to zero, and backup verification.

## 28. Recommended Commit List / Fix Plan

1. `infra: add ghcr imagePullSecret and fail on placeholder images`
2. `infra: bootstrap rabbitmq user and vhost declaratively`
3. `infra: block public metrics health docs and openapi`
4. `infra: set prometheus deployment strategy to Recreate`
5. `mobile: add production signing config and release build workflow`
6. `mobile: require production dart-defines for release builds`
7. `mobile: add Google Play subscription management link`
8. `backend: delete receipt objects when receipts are deleted`
9. `backend: harden receipt upload validation and cleanup failed uploads`
10. `backend: fix full pytest and ruff failures`
11. `backend: update vulnerable dependencies`
12. `legal: align in-app legal strings with public privacy and terms`
13. `ops: add backup restore dry-run documentation and checklist`
14. `ci: run full backend tests, Flutter tests, Android release build, site build, and kustomize validation`

## 29. Final Recommendation

Do not launch to Google Play production yet.

After the P0 blockers are fixed, the project can move to an internal or closed test track. Before public MVP launch, execute the receipt extraction E2E, account deletion E2E, billing sandbox, storage presigned URL, backup/restore, and rollback tests. Paid subscriptions should remain disabled until the Google Play subscription management requirement and RevenueCat/Google Play sandbox tests are complete.

