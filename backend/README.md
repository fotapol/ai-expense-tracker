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

## Testing `/v1/me` with Postman

### Step 1 — Get a Firebase ID Token

**Option A: From the Flutter app logs.**
Add `debugPrint(token);` inside `ApiClient.getMe()` temporarily.

**Option B: Use the Firebase Auth REST API directly in Postman.**

1. Create a new **POST** request in Postman:
   - URL: `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=YOUR_FIREBASE_WEB_API_KEY`
   - Body (raw JSON):
     ```json
     {
       "email": "your-test-user@example.com",
       "password": "your-password",
       "returnSecureToken": true
     }
     ```
   - This requires an email/password test user created in Firebase Console → Authentication → Users.
   - The response JSON will contain an `"idToken"` field. Copy it.

**Option C: Use the Google OAuth playground.**
Go to [https://developers.google.com/oauthplayground](https://developers.google.com/oauthplayground), authenticate with Google, get an `id_token`, then exchange it for a Firebase ID token via:
```
POST https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=YOUR_FIREBASE_WEB_API_KEY
{
  "postBody": "id_token=GOOGLE_ID_TOKEN&providerId=google.com",
  "requestUri": "http://localhost",
  "returnSecureToken": true
}
```

### Step 2 — Call `GET /v1/me`

Create a new **GET** request in Postman:

| Field | Value |
|---|---|
| URL | `http://localhost:8000/v1/me` |
| Authorization tab | Type = **Bearer Token**, Token = `<paste idToken>` |

Or set the header manually:
```
Authorization: Bearer <FIREBASE_ID_TOKEN>
```

### Step 3 — Expected Responses

**✅ 200 OK** (valid token, user exists or was auto-created):
```json
{
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "auth_provider": "firebase",
  "auth_subject": "abc123FirebaseUID",
  "email": "user@example.com",
  "default_currency": "EUR",
  "is_active": true,
  "created_at": "2026-03-02T19:30:00Z",
  "updated_at": "2026-03-02T19:30:00Z"
}
```

**❌ 401 Unauthorized** (missing/invalid/expired token):
```json
{
  "detail": "Invalid authentication token."
}
```

**❌ 403 Forbidden** (email not verified):
```json
{
  "detail": "Email address has not been verified."
}
```

**❌ 403 Not Authenticated** (no Authorization header at all):
```json
{
  "detail": "Not authenticated"
}
```

---

## Testing from a Physical Device

When running the backend on your PC and testing from a **physical phone** on the same Wi-Fi:

1. Find your PC's local IP: `ipconfig` → look for `IPv4 Address` (e.g., `192.168.1.42`).
2. Run Flutter with:
   ```bash
   flutter run --dart-define=API_BASE_URL=http://192.168.1.42:8000
   ```
3. Ensure your PC firewall allows inbound connections on port 8000.
