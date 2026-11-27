# Backend

FastAPI backend for AI Expense Tracker.

The backend owns authentication enforcement, receipt metadata, transaction
creation, billing webhooks, planning data, metrics, migrations, and the API
surface consumed by the Flutter app and receipt worker.

## Responsibilities

- Verify Firebase ID tokens and enforce user ownership.
- Create presigned receipt upload URLs.
- Validate uploaded receipt objects before queueing AI extraction.
- Persist transactions, receipt extractions, categories, labels, plans, and
  subscription state.
- Process RevenueCat webhooks with shared-secret validation.
- Expose health and metrics endpoints for operations.

## Local Setup

Follow the [root setup instructions](../README.md#local-backend-and-services)
to run the full stack. To run the API directly on your machine, start its
dependencies from the repository root.

```bash
docker compose up -d postgres redis rabbitmq minio
```

In `.env`, use `127.0.0.1` for `POSTGRES_HOST`, `REDIS_HOST`, and
`RABBITMQ_HOST`, set `S3_ENDPOINT=http://127.0.0.1:9000`, and set
`FIREBASE_SERVICE_ACCOUNT_PATH` to the absolute path of your local Firebase
Admin JSON file. Use the Compose service hostnames if you switch back to running
the API in Docker.

```bash
cd backend
uv sync --frozen --all-groups
uv run --env-file ../.env alembic upgrade head
uv run --env-file ../.env uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## Testing

```bash
uv run ruff check .
uv run pytest -q
uv run alembic heads
```

## Configuration

Important environment groups:

- Database: `DATABASE_URL` or `POSTGRES_*`
- Firebase: `FIREBASE_SERVICE_ACCOUNT_PATH` or `FIREBASE_SERVICE_ACCOUNT_JSON_B64`
- Storage: `S3_ENDPOINT`, `S3_EXTERNAL_ENDPOINT`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`
- Queue: `RABBITMQ_URL` or `RABBITMQ_*`
- AI: `GOOGLE_API_KEY`, `LLM_MODEL_NAME`
- Billing: `REVENUECAT_SECRET_API_KEY`, `REVENUECAT_WEBHOOK_AUTH_SECRET`

Use `.env.example` for local development and
[docs/ENVIRONMENT_VARIABLES.md](../docs/ENVIRONMENT_VARIABLES.md) for the full
reference. Never commit real environment files.

## Service behavior

- Protected routes require Firebase authentication.
- Receipt and transaction reads are scoped to the current user.
- Uploaded files are checked for allowed MIME type, size, and file signature.
- Receipt extraction runs asynchronously to avoid blocking the API.
- Webhook authentication uses a shared secret comparison.
