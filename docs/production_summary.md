# Production Readiness & VPS Summary

## 1. Current State
Phases 1, 2, and 3 are **COMPLETED**. The backend is hardened, Tier-1 backend tests are implemented, and the local Docker infrastructure is locked down. The project has a **CONDITIONAL GO** for VPS deployment, pending only the server-level reverse proxy and DNS tasks.

## 2. Legacy Phases Summary (Archived)
Before attempting VPS deployment, the application underwent significant refinement:
*   **Phase 1 (Stability):** Hardened core pipelines. Fixed database cursor starvation, robustly aligned transaction recalculations upon item deletion, and established comprehensive Python linting/formatting bounds (ruff).
*   **Phase 2 (UX / Polish):** Expanded the frontend. Rolled out a formalized Dark Mode structure parsing standard `ThemeData` components. Fixed negative value renderings in `Trends` analytics, standardized HTTP API timeout failures across app screens, and polished navigation stacks for the receipt scanner.

## 3. Hardened Files (Phase 3 Audit Pass)
During the final hardening pass, these core modules were modified to ensure safe production behavior:

*   **`backend/app/core/startup_checks.py`** & **`app/main.py`**: A strict startup validation loop was added. If critical secrets (Google API, S3, Firebase, DB) are missing in `APP_ENV=production`, the server fatally crashes before trying to process traffic. 
*   **`.env.sample`**: Thoroughly scrubbed of old default passwords and documented extensively so production envs aren't misconfigured.
*   **`docker-compose.yaml`**: Full `healthcheck` arguments added for Postgres, Redis, RabbitMQ, and Minio, paired with `condition: service_healthy` to avoid race conditions. MinIO version was securely pinned.
*   **`docker-compose.prod.yaml`**: New compose override that ensures all backend infrastructure (Postgres, Cache, Queue) binds strictly to `127.0.0.1`, stopping casual exposure to the public internet.
*   **`backend/tests/`**: 6 new integration testing files were added validating auth transitions, duplicate schema protections, and receipt sizes.

## 4. VPS Deployment Checklist (Next Steps)
Since SSL and Reverse Proxy setup were excluded from the codebase, you must address them directly on the VPS:

- [ ] **Generate Passwords**: Create random, secure passwords for `POSTGRES_PASSWORD` and `MINIO_ROOT_PASSWORD`.
- [ ] **Inject Keys**: Add your real `GOOGLE_API_KEY`, `REVENUECAT_SECRET_API_KEY`, and mount the real Firebase `firebase_sa.json`.
- [ ] **Domain Setup**: Purchase a domain and point `api.` and `storage.` subdomains to your VPS Public IPv4 record.
- [ ] **Web Server / SSL**: Install Nginx or Caddy on the VPS natively. Reverse proxy public TLS on port `8443` internally to `127.0.0.1:8000` (FastAPI) and `127.0.0.1:9000` (MinIO) because `443` is already occupied on this VPS.
- [ ] **Storage Visibility**: Update `S3_EXTERNAL_ENDPOINT` in your production environment to exactly match `https://storage.nexavend.store` when Cloudflare rewrites the origin port to `8443`. 
- [ ] **Automated Backups**: Setup a CRON script to run `pg_dump` mapped to block storage.

## 5. Runbook Commands
When ssh'd into your VPS, use these commands to initialize and verify the protected backend:

```bash
# 1. Start the infrastructure securely (Binding to 127.0.0.1)
docker compose -f docker-compose.yaml -f docker-compose.prod.yaml up -d

# 2. Check service initialization 
docker compose ps

# 3. Verify core components are healthy
docker compose exec postgres pg_isready -U expense_user
docker compose exec backend curl -f http://localhost:8000/
docker compose exec minio curl -f http://localhost:9000/minio/health/live
```
