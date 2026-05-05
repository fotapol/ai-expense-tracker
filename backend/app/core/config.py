"""Application settings loaded from environment variables.

The project intentionally keeps operator configuration environment-driven for
local development, CI, Docker Compose, and Kubernetes. These helpers avoid
scattering connection-string assembly logic and launch-critical defaults across
the codebase while remaining test-friendly: values are resolved dynamically on
attribute access, so ``monkeypatch.setenv`` still works without extra reload
hooks.
"""

from __future__ import annotations

import os
from collections.abc import Iterable
from urllib.parse import quote, urlparse


def _env(name: str, default: str = "") -> str:
    return (os.environ.get(name) or default).strip()


def _env_first(names: Iterable[str], default: str = "") -> str:
    for name in names:
        value = _env(name)
        if value:
            return value
    return default


def _bool_env(name: str, default: bool = False) -> bool:
    raw = _env(name)
    if not raw:
        return default
    return raw.lower() in {"1", "true", "yes", "on"}


def _optional_bool_env(name: str) -> bool | None:
    raw = _env(name)
    if not raw:
        return None
    return raw.lower() in {"1", "true", "yes", "on"}


def _int_env(name: str, default: int) -> int:
    raw = _env(name)
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        return default


def _float_env(name: str, default: float) -> float:
    raw = _env(name)
    if not raw:
        return default
    try:
        return float(raw)
    except ValueError:
        return default


def _normalize_base_url(raw: str) -> str:
    return raw.rstrip("/")


def _normalize_vhost(raw: str) -> str:
    cleaned = raw.strip()
    if not cleaned:
        return "/"
    if cleaned.startswith("/"):
        return cleaned
    return f"/{cleaned}"


def _url_host(raw: str) -> str:
    if not raw:
        return ""
    parsed = urlparse(raw)
    return parsed.hostname or ""


def _host_without_port(raw: str) -> str:
    cleaned = raw.strip().lower()
    if not cleaned:
        return ""
    if cleaned.startswith("[") and "]" in cleaned:
        return cleaned[1:cleaned.index("]")]
    if cleaned.count(":") == 1:
        return cleaned.rsplit(":", 1)[0]
    return cleaned


def _csv_set(raw: str) -> frozenset[str]:
    return frozenset(item.strip().lower() for item in raw.split(",") if item.strip())


def _csv_hosts(raw: str) -> tuple[str, ...]:
    hosts = []
    for item in raw.split(","):
        host = _host_without_port(item)
        if host and host not in hosts:
            hosts.append(host)
    return tuple(hosts)


def _csv_origins(raw: str) -> tuple[str, ...]:
    origins = []
    for item in raw.split(","):
        origin = item.strip().rstrip("/")
        if origin and origin not in origins:
            origins.append(origin)
    return tuple(origins)


class AppSettings:
    def __getattr__(self, name: str):
        if name == "APP_ENV":
            return _env_first(("APP_ENV", "ENVIRONMENT"), "development").lower()
        if name == "PUBLIC_API_BASE_URL":
            return _normalize_base_url(
                _env_first(("PUBLIC_API_BASE_URL", "PUBLIC_APP_BASE_URL"), "")
            )
        if name == "PUBLIC_APP_BASE_URL":
            return _normalize_base_url(_env("PUBLIC_APP_BASE_URL"))
        if name == "PUBLIC_API_HOST":
            return _url_host(self.PUBLIC_API_BASE_URL)
        if name == "PUBLIC_APP_HOST":
            return _url_host(self.PUBLIC_APP_BASE_URL)
        if name == "API_DOCS_ENABLED":
            explicit = _optional_bool_env("API_DOCS_ENABLED")
            if explicit is not None:
                return explicit
            return not self.is_production
        if name == "TRUSTED_HOSTS":
            explicit = _csv_hosts(_env("TRUSTED_HOSTS"))
            if explicit:
                return explicit
            defaults = [
                "testserver",
                "localhost",
                "127.0.0.1",
                "expense-tracker-api",
                "expense-tracker-api.expense-tracker",
                "expense-tracker-api.expense-tracker.svc",
                "expense-tracker-api.expense-tracker.svc.cluster.local",
            ]
            if self.PUBLIC_API_HOST:
                defaults.append(self.PUBLIC_API_HOST)
            return tuple(dict.fromkeys(defaults))
        if name == "CORS_ALLOWED_ORIGINS":
            explicit = _csv_origins(_env("CORS_ALLOWED_ORIGINS"))
            if explicit:
                return explicit
            if self.PUBLIC_APP_BASE_URL:
                return (self.PUBLIC_APP_BASE_URL,)
            if not self.is_production:
                return ("http://localhost:3000", "http://127.0.0.1:3000")
            return ()
        if name == "RUN_STARTUP_MIGRATIONS":
            return _bool_env("RUN_STARTUP_MIGRATIONS", True)
        if name == "MAX_RECEIPT_FILE_BYTES":
            return _int_env("MAX_RECEIPT_FILE_BYTES", 15 * 1024 * 1024)
        if name == "UVICORN_FORWARDED_ALLOW_IPS":
            return _env("UVICORN_FORWARDED_ALLOW_IPS", "127.0.0.1")
        if name == "INGRESS_CLASS_NAME":
            return _env("INGRESS_CLASS_NAME", "nginx")
        if name == "INGRESS_TLS_SECRET_NAME":
            return _env("INGRESS_TLS_SECRET_NAME", "expense-tracker-origin-tls")
        raise AttributeError(name)

    @property
    def is_production(self) -> bool:
        return self.APP_ENV == "production"


class DatabaseSettings:
    def __getattr__(self, name: str):
        if name == "POSTGRES_USER":
            return _env("POSTGRES_USER", "expense_user")
        if name == "POSTGRES_PASSWORD":
            return _env("POSTGRES_PASSWORD", "expense_pass")
        if name == "POSTGRES_DB":
            return _env("POSTGRES_DB", "expense_tracker")
        if name == "POSTGRES_HOST":
            return _env("POSTGRES_HOST", "postgres")
        if name == "POSTGRES_PORT":
            return _int_env("POSTGRES_PORT", 5432)
        if name == "DATABASE_URL":
            explicit = _env("DATABASE_URL")
            if explicit:
                return explicit
            return (
                "postgresql+psycopg://"
                f"{self.POSTGRES_USER}:{self.POSTGRES_PASSWORD}"
                f"@{self.POSTGRES_HOST}:{self.POSTGRES_PORT}/{self.POSTGRES_DB}"
            )
        raise AttributeError(name)


class RedisSettings:
    def __getattr__(self, name: str):
        if name == "REDIS_HOST":
            return _env("REDIS_HOST", "redis")
        if name == "REDIS_PORT":
            return _int_env("REDIS_PORT", 6379)
        if name == "REDIS_DB":
            return _int_env("REDIS_DB", 0)
        if name == "REDIS_URL":
            explicit = _env("REDIS_URL")
            if explicit:
                return explicit
            return f"redis://{self.REDIS_HOST}:{self.REDIS_PORT}/{self.REDIS_DB}"
        raise AttributeError(name)


class RabbitMQSettings:
    def __getattr__(self, name: str):
        if name == "RABBITMQ_HOST":
            return _env("RABBITMQ_HOST", "rabbitmq")
        if name == "RABBITMQ_PORT":
            return _int_env("RABBITMQ_PORT", 5672)
        if name == "RABBITMQ_MANAGEMENT_PORT":
            return _int_env("RABBITMQ_MANAGEMENT_PORT", 15672)
        if name == "RABBITMQ_USER":
            return _env("RABBITMQ_USER", "guest")
        if name == "RABBITMQ_PASSWORD":
            return _env("RABBITMQ_PASSWORD", "guest")
        if name == "RABBITMQ_VHOST":
            return _normalize_vhost(_env("RABBITMQ_VHOST", "/"))
        if name == "RABBITMQ_ERLANG_COOKIE":
            return _env("RABBITMQ_ERLANG_COOKIE")
        if name == "RECEIPT_EXTRACTION_QUEUE_NAME":
            return _env("RECEIPT_EXTRACTION_QUEUE_NAME", "receipt_extraction")
        if name == "RABBITMQ_URL":
            explicit = _env("RABBITMQ_URL")
            if explicit:
                return explicit
            encoded_vhost = quote(self.RABBITMQ_VHOST, safe="/")
            return (
                "amqp://"
                f"{self.RABBITMQ_USER}:{self.RABBITMQ_PASSWORD}"
                f"@{self.RABBITMQ_HOST}:{self.RABBITMQ_PORT}{encoded_vhost}"
            )
        raise AttributeError(name)


class S3Settings:
    def __getattr__(self, name: str):
        if name == "MINIO_ROOT_USER":
            return _env("MINIO_ROOT_USER", "minioadmin")
        if name == "MINIO_ROOT_PASSWORD":
            return _env("MINIO_ROOT_PASSWORD", "minioadmin123")
        if name == "ENDPOINT":
            return _normalize_base_url(_env("S3_ENDPOINT", "http://minio:9000"))
        if name == "EXTERNAL_ENDPOINT":
            return _normalize_base_url(_env("S3_EXTERNAL_ENDPOINT"))
        if name == "ACCESS_KEY":
            return _env("S3_ACCESS_KEY") or self.MINIO_ROOT_USER
        if name == "SECRET_KEY":
            return _env("S3_SECRET_KEY") or self.MINIO_ROOT_PASSWORD
        if name == "REGION":
            return _env("S3_REGION", "eu-central-1")
        if name == "BUCKET_RECEIPTS":
            return _env("S3_BUCKET_RECEIPTS", "receipts")
        if name == "BUCKET_BACKUPS":
            return _env("S3_BUCKET_BACKUPS", "postgres-backups")
        if name == "PRESIGNED_PUT_EXPIRY_SECONDS":
            return _int_env("S3_PRESIGNED_PUT_EXPIRY_SECONDS", 600)
        if name == "PRESIGNED_GET_EXPIRY_SECONDS":
            return _int_env("S3_PRESIGNED_GET_EXPIRY_SECONDS", 600)
        if name == "EXTERNAL_HOST":
            return _url_host(self.EXTERNAL_ENDPOINT)
        raise AttributeError(name)


class LLMSettings:
    def __getattr__(self, name: str):
        if name == "PROVIDER":
            return _env("LLM_PROVIDER", "google")
        if name == "GOOGLE_API_KEY":
            return _env("GOOGLE_API_KEY")
        if name == "MODEL_NAME":
            return _env("LLM_MODEL_NAME", "gemini-2.5-flash")
        raise AttributeError(name)


class WorkerSettings:
    def __getattr__(self, name: str):
        if name == "PROCESSING_STALE_AFTER_MINUTES":
            return _int_env("RECEIPT_PROCESSING_STALE_AFTER_MINUTES", 15)
        if name == "MAX_RETRIES":
            return _int_env("RECEIPT_PROCESSING_MAX_RETRIES", 3)
        if name == "RETRY_BACKOFF_SECONDS":
            return _int_env("RECEIPT_PROCESSING_RETRY_BACKOFF_SECONDS", 5)
        raise AttributeError(name)


class FirebaseSettings:
    def __getattr__(self, name: str):
        if name == "SERVICE_ACCOUNT_PATH":
            return _env("FIREBASE_SERVICE_ACCOUNT_PATH", "/run/secrets/firebase_sa.json")
        if name == "SERVICE_ACCOUNT_JSON_B64":
            return _env("FIREBASE_SERVICE_ACCOUNT_JSON_B64")
        raise AttributeError(name)


class BillingSettings:
    def __getattr__(self, name: str):
        if name == "ENABLE_DEV_BILLING_ENDPOINTS":
            return _bool_env("ENABLE_DEV_BILLING_ENDPOINTS", False)
        if name == "DEV_BILLING_INTERNAL_SECRET":
            return _env("DEV_BILLING_INTERNAL_SECRET")
        if name == "REVENUECAT_SECRET_API_KEY":
            return _env("REVENUECAT_SECRET_API_KEY")
        if name == "REVENUECAT_API_BASE_URL":
            return _env("REVENUECAT_API_BASE_URL", "https://api.revenuecat.com")
        if name == "REVENUECAT_HTTP_TIMEOUT_SECONDS":
            return _float_env("REVENUECAT_HTTP_TIMEOUT_SECONDS", 8.0)
        if name == "REVENUECAT_PERSONAL_PREMIUM_ENTITLEMENT_ID":
            return _env("REVENUECAT_PERSONAL_PREMIUM_ENTITLEMENT_ID", "personal_premium")
        if name == "REVENUECAT_FAMILY_PREMIUM_ENTITLEMENT_ID":
            return _env("REVENUECAT_FAMILY_PREMIUM_ENTITLEMENT_ID", "family_premium")
        if name == "REVENUECAT_PERSONAL_PRODUCT_IDS":
            return _env(
                "REVENUECAT_PERSONAL_PRODUCT_IDS",
                "personal_premium,individual_plan_monthly,individual_plan_yearly",
            )
        if name == "REVENUECAT_FAMILY_PRODUCT_IDS":
            return _env(
                "REVENUECAT_FAMILY_PRODUCT_IDS",
                "family_premium,family_plan_monthly,family_plan_yearly",
            )
        if name == "REVENUECAT_WEBHOOK_AUTH_HEADER":
            return _env("REVENUECAT_WEBHOOK_AUTH_HEADER", "Authorization")
        if name == "REVENUECAT_WEBHOOK_AUTH_SECRET":
            return _env("REVENUECAT_WEBHOOK_AUTH_SECRET")
        raise AttributeError(name)


class FxSettings:
    def __getattr__(self, name: str):
        if name == "FRANKFURTER_BASE_URL":
            return _env("FRANKFURTER_BASE_URL", "https://api.frankfurter.app")
        if name == "CURRENCY_API_CDN_BASE_URL":
            return _env(
                "CURRENCY_API_CDN_BASE_URL",
                "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api",
            )
        if name == "HTTP_TIMEOUT_SECONDS":
            return _float_env("FX_HTTP_TIMEOUT_SECONDS", 8.0)
        raise AttributeError(name)


class ObservabilitySettings:
    def __getattr__(self, name: str):
        if name == "LOG_LEVEL":
            return _env("LOG_LEVEL", "INFO")
        if name == "LOG_JSON":
            return _bool_env("LOG_JSON", False)
        if name == "PROXY_DIAGNOSTICS_ENABLED":
            return _bool_env("PROXY_DIAGNOSTICS_ENABLED", False)
        if name == "METRICS_ENABLED":
            return _bool_env("METRICS_ENABLED", True)
        if name == "METRICS_API_PATH":
            return _env("METRICS_API_PATH", "/metrics")
        if name == "WORKER_METRICS_PORT":
            return _int_env("WORKER_METRICS_PORT", 9101)
        if name == "PROMETHEUS_RETENTION_TIME":
            return _env("PROMETHEUS_RETENTION_TIME", "7d")
        if name == "PROMETHEUS_SCRAPE_INTERVAL":
            return _env("PROMETHEUS_SCRAPE_INTERVAL", "15s")
        if name == "PROMETHEUS_EVALUATION_INTERVAL":
            return _env("PROMETHEUS_EVALUATION_INTERVAL", "15s")
        if name == "GRAFANA_ADMIN_USER":
            return _env("GRAFANA_ADMIN_USER", "admin")
        if name == "GRAFANA_ADMIN_PASSWORD":
            return _env("GRAFANA_ADMIN_PASSWORD")
        if name == "LANGSMITH_TRACING":
            return _bool_env("LANGSMITH_TRACING", False)
        if name == "LANGSMITH_API_KEY":
            return _env("LANGSMITH_API_KEY")
        if name == "LANGSMITH_PROJECT":
            return _env("LANGSMITH_PROJECT", "ai-expense-tracker")
        if name == "LANGSMITH_ENDPOINT":
            return _env("LANGSMITH_ENDPOINT", "https://api.smith.langchain.com")
        if name == "LANGSMITH_HIDE_INPUTS":
            return _bool_env("LANGSMITH_HIDE_INPUTS", True)
        if name == "LANGSMITH_HIDE_OUTPUTS":
            return _bool_env("LANGSMITH_HIDE_OUTPUTS", True)
        raise AttributeError(name)


app_settings = AppSettings()
database_settings = DatabaseSettings()
redis_settings = RedisSettings()
rabbitmq_settings = RabbitMQSettings()
s3_settings = S3Settings()
llm_settings = LLMSettings()
worker_settings = WorkerSettings()
firebase_settings = FirebaseSettings()
billing_settings = BillingSettings()
fx_settings = FxSettings()
observability_settings = ObservabilitySettings()


def get_dev_billing_admin_emails() -> frozenset[str]:
    """Return the set of emails that have admin billing access."""

    return _csv_set(_env("DEV_BILLING_ADMIN_EMAILS"))


def get_app_admin_emails() -> frozenset[str]:
    """Return the set of emails that should resolve to ``users.is_admin``."""

    admin_emails = set(get_dev_billing_admin_emails())
    admin_emails.update(_csv_set(_env("APP_ADMIN_EMAILS")))
    return frozenset(admin_emails)
