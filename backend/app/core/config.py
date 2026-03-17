"""Application settings loaded from environment variables."""

import os
from functools import lru_cache


class S3Settings:
    """S3/MinIO connection settings read from environment."""

    ENDPOINT: str = os.environ.get("S3_ENDPOINT", "http://minio:9000")
    EXTERNAL_ENDPOINT: str | None = os.environ.get("S3_EXTERNAL_ENDPOINT")
    # No default credentials — missing values will cause an explicit error
    # rather than silently using the well-known minioadmin defaults.
    ACCESS_KEY: str = os.environ.get("S3_ACCESS_KEY", "")
    SECRET_KEY: str = os.environ.get("S3_SECRET_KEY", "")
    REGION: str = os.environ.get("S3_REGION", "eu-central-1")
    BUCKET_RECEIPTS: str = os.environ.get("S3_BUCKET_RECEIPTS", "receipts")


class LLMSettings:
    """LLM provider settings read from environment."""

    GOOGLE_API_KEY: str = os.environ.get("GOOGLE_API_KEY", "")
    MODEL_NAME: str = os.environ.get("LLM_MODEL_NAME", "gemini-2.5-flash")


class AppSettings:
    """General application settings read from environment."""

    PUBLIC_APP_BASE_URL: str = os.environ.get("PUBLIC_APP_BASE_URL", "").strip().rstrip("/")


s3_settings = S3Settings()
llm_settings = LLMSettings()
app_settings = AppSettings()


@lru_cache(maxsize=1)
def get_dev_billing_admin_emails() -> frozenset[str]:
    """Return the set of emails that have admin billing access.

    Cached at module load time so the allowlist is not reparsed on every request.
    """
    raw = os.environ.get("DEV_BILLING_ADMIN_EMAILS", "")
    return frozenset(item.strip().lower() for item in raw.split(",") if item.strip())
