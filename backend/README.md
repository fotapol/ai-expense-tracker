# Backend

FastAPI backend for the Expense Tracker application.

## Prerequisites

| Variable | Description | Example |
|---|---|---|
| `DATABASE_URL` | PostgreSQL connection string | `postgresql+psycopg://user:pass@localhost:5432/expense_tracker` |
| `FIREBASE_SERVICE_ACCOUNT_PATH` | Path to Firebase service-account JSON | `/run/secrets/firebase_sa.json` |

## Running Locally

```bash
# With Docker Compose (from repo root)
docker compose up backend

# Or directly with uv
uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## Firebase Authentication

The backend verifies Firebase ID tokens on every protected endpoint.
The service-account JSON must be at the path specified by `FIREBASE_SERVICE_ACCOUNT_PATH`.

In Docker Compose, it is mounted from `backend/.secrets/firebase_sa.json`.

---

## Testing from a Physical Device

When running the backend on your PC and testing from a **physical phone** on the same Wi-Fi:

1. Find your PC's local IP: `ipconfig` → look for `IPv4 Address` (e.g., `192.168.1.42`).
2. Run Flutter with:
   ```bash
   flutter run --dart-define=API_BASE_URL=http://192.168.1.42:8000
   ```
