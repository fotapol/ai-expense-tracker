# AI Expense Tracker

Full-stack expense tracking app with receipt scanning via Vision LLM.

## Architecture

```
Flutter App → FastAPI Backend → PostgreSQL
                  ↓
              MinIO (S3) ← receipt images
                  ↓
            RabbitMQ queue
                  ↓
          Worker (Gemini Vision LLM) → Transaction + Items
```

## Required Environment Variables

Copy `.env.sample` to `.env` and configure:

| Variable | Description | Default |
|---|---|---|
| `DATABASE_URL` | PostgreSQL connection string | — |
| `REDIS_URL` | Redis URL for caching | `redis://redis:6379/0` |
| `RABBITMQ_URL` | RabbitMQ AMQP URL | `amqp://guest:guest@rabbitmq:5672/` |
| `FIREBASE_SERVICE_ACCOUNT_PATH` | Path to Firebase SA JSON | `/run/secrets/firebase_sa.json` |
| `S3_ENDPOINT` | MinIO/S3 endpoint | `http://minio:9000` |
| `S3_ACCESS_KEY` | MinIO access key | `minioadmin` |
| `S3_SECRET_KEY` | MinIO secret key | `minioadmin123` |
| `S3_REGION` | S3 region | `us-east-1` |
| `S3_BUCKET_RECEIPTS` | Bucket name for receipts | `receipts` |
| `GOOGLE_API_KEY` | Google API key for Gemini Vision LLM | — |
| `MINIO_ROOT_USER` | MinIO root user (for MinIO container) | `minioadmin` |
| `MINIO_ROOT_PASSWORD` | MinIO root password (for MinIO container) | `minioadmin123` |

## Running

```bash
# Start all services
docker-compose up --build

# Run Alembic migrations
docker exec -it fastapi uv run alembic upgrade head

# Run Flutter app
cd expense_tracker_app
flutter run --dart-define=API_BASE_URL=http://<your-host-ip>:8000
```

## Services

| Service | Port | Description |
|---|---|---|
| `backend` | 8000 | FastAPI application |
| `worker` | — | Receipt extraction worker (no exposed port) |
| `postgres` | 5432 | PostgreSQL database |
| `redis` | 6379 | Redis cache |
| `minio` | 9000 / 9001 | S3-compatible storage (API / Console) |
| `rabbitmq` | 5672 / 15672 | Message broker (AMQP / Management UI) |

## Receipt Upload Flow

1. **Flutter** picks image → `POST /v1/receipts` with `mime_type`
2. **Backend** creates receipt row, returns presigned PUT URL
3. **Flutter** uploads image bytes directly to MinIO via presigned URL
4. **Flutter** calls `POST /v1/receipts/{id}/confirm-upload`
5. **Backend** HEADs MinIO object to verify, enqueues extraction job
6. **Worker** downloads image, calls Gemini Vision LLM, creates Transaction + Items
7. **Flutter** polls `GET /v1/receipts/{id}` until `COMPLETED` or `FAILED`