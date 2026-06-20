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

From the repository root:

```bash
cp .env.example .env
docker compose up --build
```

Direct backend workflow:

```bash
cd backend
uv sync --frozen --all-groups
uv run alembic upgrade head
uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
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

## Security Notes

- Protected routes require Firebase authentication.
- Receipt and transaction reads are scoped to the current user.
- Uploaded files are checked for allowed MIME type, size, and file signature.
- Receipt extraction runs asynchronously to avoid blocking the API.
- Webhook authentication uses a shared secret comparison.
