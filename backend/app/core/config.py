"""Application settings loaded from environment variables."""

import os


class S3Settings:
    """S3/MinIO connection settings read from environment."""

    ENDPOINT: str = os.environ.get("S3_ENDPOINT", "http://minio:9000")
    EXTERNAL_ENDPOINT: str | None = os.environ.get("S3_EXTERNAL_ENDPOINT")
    ACCESS_KEY: str = os.environ.get("S3_ACCESS_KEY", "minioadmin")
    SECRET_KEY: str = os.environ.get("S3_SECRET_KEY", "minioadmin123")
    REGION: str = os.environ.get("S3_REGION", "eu-central-1")
    BUCKET_RECEIPTS: str = os.environ.get("S3_BUCKET_RECEIPTS", "receipts")


class LLMSettings:
    """LLM provider settings read from environment."""

    GOOGLE_API_KEY: str = os.environ.get("GOOGLE_API_KEY", "")
    MODEL_NAME: str = os.environ.get("LLM_MODEL_NAME", "gemini-2.5-flash")


s3_settings = S3Settings()
llm_settings = LLMSettings()
