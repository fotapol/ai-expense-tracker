"""Render Kubernetes env inputs from a single operator-managed env file.

This keeps ``.env.production`` as the source of truth while still letting the
cluster consume native ConfigMaps and Secrets through Kustomize generators.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from urllib.parse import quote, urlparse

CONFIG_KEYS = {
    "APP_ENV",
    "APP_ADMIN_EMAILS",
    "PUBLIC_API_BASE_URL",
    "PUBLIC_APP_BASE_URL",
    "APP_WEBSITE_URL",
    "APP_PRIVACY_URL",
    "APP_TERMS_URL",
    "APP_DELETE_ACCOUNT_URL",
    "APP_PLAY_SUBSCRIPTIONS_URL",
    "APP_SUPPORT_EMAIL",
    "APP_SUPPORT_SUBJECT",
    "SITE_APP_STORE_URL",
    "SITE_GOOGLE_PLAY_URL",
    "SITE_OPEN_APP_URL",
    "API_DOCS_ENABLED",
    "TRUSTED_HOSTS",
    "CORS_ALLOWED_ORIGINS",
    "RUN_STARTUP_MIGRATIONS",
    "MAX_RECEIPT_FILE_BYTES",
    "LOG_LEVEL",
    "LOG_JSON",
    "PROXY_DIAGNOSTICS_ENABLED",
    "UVICORN_FORWARDED_ALLOW_IPS",
    "INGRESS_CLASS_NAME",
    "INGRESS_TLS_SECRET_NAME",
    "POSTGRES_HOST",
    "POSTGRES_PORT",
    "POSTGRES_DB",
    "REDIS_HOST",
    "REDIS_PORT",
    "REDIS_DB",
    "RABBITMQ_HOST",
    "RABBITMQ_PORT",
    "RABBITMQ_MANAGEMENT_PORT",
    "RABBITMQ_VHOST",
    "RECEIPT_EXTRACTION_QUEUE_NAME",
    "S3_ENDPOINT",
    "S3_EXTERNAL_ENDPOINT",
    "S3_REGION",
    "S3_BUCKET_RECEIPTS",
    "S3_BUCKET_BACKUPS",
    "S3_PRESIGNED_PUT_EXPIRY_SECONDS",
    "S3_PRESIGNED_GET_EXPIRY_SECONDS",
    "FIREBASE_SERVICE_ACCOUNT_PATH",
    "LLM_PROVIDER",
    "LLM_MODEL_NAME",
    "RECEIPT_PROCESSING_STALE_AFTER_MINUTES",
    "RECEIPT_PROCESSING_MAX_RETRIES",
    "RECEIPT_PROCESSING_RETRY_BACKOFF_SECONDS",
    "FRANKFURTER_BASE_URL",
    "CURRENCY_API_CDN_BASE_URL",
    "FX_HTTP_TIMEOUT_SECONDS",
    "METRICS_ENABLED",
    "METRICS_API_PATH",
    "WORKER_METRICS_PORT",
    "LANGSMITH_TRACING",
    "LANGSMITH_PROJECT",
    "LANGSMITH_ENDPOINT",
    "LANGSMITH_HIDE_INPUTS",
    "LANGSMITH_HIDE_OUTPUTS",
    "BACKEND_IMAGE",
    "SITE_IMAGE",
    "POSTGRES_BACKUP_IMAGE",
    "REVENUECAT_API_BASE_URL",
    "REVENUECAT_HTTP_TIMEOUT_SECONDS",
    "REVENUECAT_PERSONAL_PREMIUM_ENTITLEMENT_ID",
    "REVENUECAT_FAMILY_PREMIUM_ENTITLEMENT_ID",
    "REVENUECAT_PERSONAL_PRODUCT_IDS",
    "REVENUECAT_FAMILY_PRODUCT_IDS",
    "REVENUECAT_WEBHOOK_AUTH_HEADER",
    "ENABLE_DEV_BILLING_ENDPOINTS",
    "DEV_BILLING_ADMIN_EMAILS",
    "PROMETHEUS_RETENTION_TIME",
    "PROMETHEUS_RETENTION_SIZE",
    "PROMETHEUS_SCRAPE_INTERVAL",
    "PROMETHEUS_EVALUATION_INTERVAL",
    "GRAFANA_ROOT_URL",
    "POSTGRES_BACKUP_SCHEDULE",
    "POSTGRES_BACKUP_RETENTION_DAYS",
    "POSTGRES_BACKUP_PREFIX",
}

IMAGE_KEYS = {
    "BACKEND_IMAGE",
    "SITE_IMAGE",
    "POSTGRES_BACKUP_IMAGE",
}

SECRET_KEYS = {
    "POSTGRES_USER",
    "POSTGRES_PASSWORD",
    "DATABASE_URL",
    "REDIS_URL",
    "RABBITMQ_USER",
    "RABBITMQ_PASSWORD",
    "RABBITMQ_ERLANG_COOKIE",
    "RABBITMQ_URL",
    "MINIO_ROOT_USER",
    "MINIO_ROOT_PASSWORD",
    "S3_ACCESS_KEY",
    "S3_SECRET_KEY",
    "FIREBASE_SERVICE_ACCOUNT_JSON_B64",
    "GOOGLE_API_KEY",
    "LANGSMITH_API_KEY",
    "REVENUECAT_SECRET_API_KEY",
    "REVENUECAT_WEBHOOK_AUTH_SECRET",
    "DEV_BILLING_INTERNAL_SECRET",
    "GRAFANA_ADMIN_USER",
    "GRAFANA_ADMIN_PASSWORD",
}

REQUIRED_KEYS = {
    "APP_ENV",
    "PUBLIC_API_BASE_URL",
    "PUBLIC_APP_BASE_URL",
    "POSTGRES_USER",
    "POSTGRES_PASSWORD",
    "POSTGRES_DB",
    "POSTGRES_HOST",
    "POSTGRES_PORT",
    "RABBITMQ_USER",
    "RABBITMQ_PASSWORD",
    "RABBITMQ_ERLANG_COOKIE",
    "MINIO_ROOT_USER",
    "MINIO_ROOT_PASSWORD",
    "S3_ENDPOINT",
    "S3_EXTERNAL_ENDPOINT",
    "S3_BUCKET_RECEIPTS",
    "S3_BUCKET_BACKUPS",
    "FIREBASE_SERVICE_ACCOUNT_PATH",
    "FIREBASE_SERVICE_ACCOUNT_JSON_B64",
    "GOOGLE_API_KEY",
    "GRAFANA_ADMIN_USER",
    "GRAFANA_ADMIN_PASSWORD",
    "POSTGRES_BACKUP_SCHEDULE",
    "UVICORN_FORWARDED_ALLOW_IPS",
    "BACKEND_IMAGE",
    "SITE_IMAGE",
    "POSTGRES_BACKUP_IMAGE",
}

DEFAULTS = {
    "APP_ENV": "production",
    "API_DOCS_ENABLED": "false",
    "RUN_STARTUP_MIGRATIONS": "true",
    "LOG_LEVEL": "INFO",
    "LOG_JSON": "false",
    "PROXY_DIAGNOSTICS_ENABLED": "false",
    "INGRESS_CLASS_NAME": "nginx",
    "INGRESS_TLS_SECRET_NAME": "expense-tracker-origin-tls",
    "POSTGRES_PORT": "5432",
    "REDIS_PORT": "6379",
    "REDIS_DB": "0",
    "RABBITMQ_PORT": "5672",
    "RABBITMQ_MANAGEMENT_PORT": "15672",
    "RABBITMQ_VHOST": "/",
    "RECEIPT_EXTRACTION_QUEUE_NAME": "receipt_extraction",
    "S3_REGION": "eu-central-1",
    "S3_BUCKET_RECEIPTS": "receipts",
    "S3_BUCKET_BACKUPS": "postgres-backups",
    "S3_PRESIGNED_PUT_EXPIRY_SECONDS": "600",
    "S3_PRESIGNED_GET_EXPIRY_SECONDS": "600",
    "LLM_PROVIDER": "google",
    "LLM_MODEL_NAME": "gemini-2.5-flash",
    "RECEIPT_PROCESSING_STALE_AFTER_MINUTES": "15",
    "RECEIPT_PROCESSING_MAX_RETRIES": "3",
    "RECEIPT_PROCESSING_RETRY_BACKOFF_SECONDS": "5",
    "FRANKFURTER_BASE_URL": "https://api.frankfurter.app",
    "CURRENCY_API_CDN_BASE_URL": "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api",
    "FX_HTTP_TIMEOUT_SECONDS": "8",
    "METRICS_ENABLED": "true",
    "METRICS_API_PATH": "/metrics",
    "WORKER_METRICS_PORT": "9101",
    "LANGSMITH_TRACING": "false",
    "LANGSMITH_PROJECT": "ai-expense-tracker-production",
    "LANGSMITH_ENDPOINT": "https://api.smith.langchain.com",
    "LANGSMITH_HIDE_INPUTS": "true",
    "LANGSMITH_HIDE_OUTPUTS": "true",
    "REVENUECAT_API_BASE_URL": "https://api.revenuecat.com",
    "REVENUECAT_HTTP_TIMEOUT_SECONDS": "8",
    "REVENUECAT_PERSONAL_PREMIUM_ENTITLEMENT_ID": "personal_premium",
    "REVENUECAT_FAMILY_PREMIUM_ENTITLEMENT_ID": "family_premium",
    "REVENUECAT_PERSONAL_PRODUCT_IDS": "personal_premium,individual_plan_monthly,individual_plan_yearly",
    "REVENUECAT_FAMILY_PRODUCT_IDS": "family_premium,family_plan_monthly,family_plan_yearly",
    "REVENUECAT_WEBHOOK_AUTH_HEADER": "Authorization",
    "ENABLE_DEV_BILLING_ENDPOINTS": "false",
    "PROMETHEUS_RETENTION_TIME": "7d",
    "PROMETHEUS_RETENTION_SIZE": "2GB",
    "PROMETHEUS_SCRAPE_INTERVAL": "15s",
    "PROMETHEUS_EVALUATION_INTERVAL": "15s",
    "GRAFANA_ROOT_URL": "https://grafana.internal.example.com",
    "POSTGRES_BACKUP_SCHEDULE": "0 3 * * *",
    "POSTGRES_BACKUP_RETENTION_DAYS": "30",
    "POSTGRES_BACKUP_PREFIX": "postgres",
    "APP_SUPPORT_SUBJECT": "Expense Tracker Support",
}


def parse_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        cleaned_key = key.strip()
        cleaned_value = value.strip()
        if (
            len(cleaned_value) >= 2
            and cleaned_value[0] == cleaned_value[-1]
            and cleaned_value[0] in {'"', "'"}
        ):
            cleaned_value = cleaned_value[1:-1]
        values[cleaned_key] = cleaned_value
    return values


def url_host(value: str) -> str:
    parsed = urlparse(value)
    return parsed.hostname or ""


def build_database_url(values: dict[str, str]) -> str:
    explicit = values.get("DATABASE_URL", "").strip()
    if explicit:
        return explicit
    return (
        "postgresql+psycopg://"
        f"{values['POSTGRES_USER']}:{values['POSTGRES_PASSWORD']}"
        f"@{values['POSTGRES_HOST']}:{values['POSTGRES_PORT']}/{values['POSTGRES_DB']}"
    )


def build_redis_url(values: dict[str, str]) -> str:
    explicit = values.get("REDIS_URL", "").strip()
    if explicit:
        return explicit
    return f"redis://{values['REDIS_HOST']}:{values['REDIS_PORT']}/{values['REDIS_DB']}"


def build_rabbitmq_url(values: dict[str, str]) -> str:
    explicit = values.get("RABBITMQ_URL", "").strip()
    if explicit:
        return explicit
    vhost = values.get("RABBITMQ_VHOST", "/").strip() or "/"
    if not vhost.startswith("/"):
        vhost = f"/{vhost}"
    return (
        "amqp://"
        f"{values['RABBITMQ_USER']}:{values['RABBITMQ_PASSWORD']}"
        f"@{values['RABBITMQ_HOST']}:{values['RABBITMQ_PORT']}{quote(vhost, safe='/')}"
    )


def validate_production_images(values: dict[str, str]) -> None:
    if values.get("APP_ENV", "").strip().lower() != "production":
        return

    for key in sorted(IMAGE_KEYS):
        image = values.get(key, "").strip()
        if not image:
            continue
        image_without_digest = image.split("@", 1)[0]
        if "ghcr.io/example/" in image:
            raise SystemExit(f"{key} must not use placeholder ghcr.io/example images")
        if image_without_digest.endswith(":latest"):
            raise SystemExit(f"{key} must not use the :latest tag in production")


def validate(values: dict[str, str]) -> None:
    missing = [key for key in sorted(REQUIRED_KEYS) if not values.get(key, "").strip()]
    if missing:
        missing_keys = ", ".join(missing)
        raise SystemExit(f"Missing required production env values: {missing_keys}")

    if (
        values.get("LANGSMITH_TRACING", "").lower() in {"1", "true", "yes", "on"}
        and not values.get("LANGSMITH_API_KEY", "").strip()
    ):
        raise SystemExit("LANGSMITH_API_KEY is required when LANGSMITH_TRACING=true")

    if values.get("PUBLIC_API_BASE_URL") and not url_host(values["PUBLIC_API_BASE_URL"]):
        raise SystemExit("PUBLIC_API_BASE_URL must be a valid absolute URL")
    if values.get("PUBLIC_APP_BASE_URL") and not url_host(values["PUBLIC_APP_BASE_URL"]):
        raise SystemExit("PUBLIC_APP_BASE_URL must be a valid absolute URL")
    if values.get("S3_EXTERNAL_ENDPOINT") and not url_host(values["S3_EXTERNAL_ENDPOINT"]):
        raise SystemExit("S3_EXTERNAL_ENDPOINT must be a valid absolute URL")
    if (
        values.get("APP_ENV", "").strip().lower() == "production"
        and values.get("UVICORN_FORWARDED_ALLOW_IPS", "").strip() == "*"
    ):
        raise SystemExit(
            "UVICORN_FORWARDED_ALLOW_IPS must not be '*' in production; "
            "set the observed ingress source IP or CIDR"
        )

    validate_production_images(values)


def write_env_file(path: Path, values: dict[str, str]) -> None:
    lines = [f"{key}={values[key]}" for key in sorted(values)]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


def write_schedule_patch(path: Path, schedule: str) -> None:
    path.write_text(
        "\n".join(
            [
                "apiVersion: batch/v1",
                "kind: CronJob",
                "metadata:",
                "  name: postgres-backup",
                "spec:",
                f'  schedule: "{schedule}"',
                "",
            ]
        ),
        encoding="utf-8",
        newline="\n",
    )


def write_prometheus_config(path: Path, values: dict[str, str]) -> None:
    metrics_path = values.get("METRICS_API_PATH", "/metrics")
    path.write_text(
        "\n".join(
            [
                "global:",
                f"  scrape_interval: {values['PROMETHEUS_SCRAPE_INTERVAL']}",
                f"  evaluation_interval: {values['PROMETHEUS_EVALUATION_INTERVAL']}",
                "",
                "rule_files:",
                "  - /etc/prometheus/rules.yml",
                "",
                "scrape_configs:",
                "  - job_name: expense-tracker-api",
                f"    metrics_path: {metrics_path}",
                "    static_configs:",
                "      - targets:",
                "          - expense-tracker-api:80",
                "  - job_name: expense-tracker-worker",
                "    static_configs:",
                "      - targets:",
                "          - expense-tracker-worker:9101",
                "  - job_name: prometheus",
                "    static_configs:",
                "      - targets:",
                "          - prometheus:9090",
                "",
            ]
        ),
        encoding="utf-8",
        newline="\n",
    )


def write_yaml_file(path: Path, lines: list[str]) -> None:
    path.write_text(
        "\n".join([*lines, ""]),
        encoding="utf-8",
        newline="\n",
    )


def write_image_patches(output_dir: Path, values: dict[str, str]) -> None:
    write_yaml_file(
        output_dir / "api-image-patch.yaml",
        [
            "apiVersion: apps/v1",
            "kind: Deployment",
            "metadata:",
            "  name: expense-tracker-api",
            "spec:",
            "  template:",
            "    spec:",
            "      containers:",
            "        - name: api",
            f"          image: {values['BACKEND_IMAGE']}",
        ],
    )
    write_yaml_file(
        output_dir / "worker-image-patch.yaml",
        [
            "apiVersion: apps/v1",
            "kind: Deployment",
            "metadata:",
            "  name: expense-tracker-worker",
            "spec:",
            "  template:",
            "    spec:",
            "      containers:",
            "        - name: worker",
            f"          image: {values['BACKEND_IMAGE']}",
        ],
    )
    write_yaml_file(
        output_dir / "site-image-patch.yaml",
        [
            "apiVersion: apps/v1",
            "kind: Deployment",
            "metadata:",
            "  name: expense-tracker-site",
            "spec:",
            "  template:",
            "    spec:",
            "      containers:",
            "        - name: site",
            f"          image: {values['SITE_IMAGE']}",
        ],
    )
    write_yaml_file(
        output_dir / "postgres-backup-image-patch.yaml",
        [
            "apiVersion: batch/v1",
            "kind: CronJob",
            "metadata:",
            "  name: postgres-backup",
            "spec:",
            "  jobTemplate:",
            "    spec:",
            "      template:",
            "        spec:",
            "          containers:",
            "            - name: postgres-backup",
            f"              image: {values['POSTGRES_BACKUP_IMAGE']}",
        ],
    )
    legacy_patch = output_dir / "image-overrides-patch.yaml"
    if legacy_patch.exists():
        legacy_patch.unlink()


def _legacy_write_image_patch(path: Path, values: dict[str, str]) -> None:
    path.write_text(
        "\n".join(
            [
                "apiVersion: apps/v1",
                "kind: Deployment",
                "metadata:",
                "  name: expense-tracker-api",
                "spec:",
                "  template:",
                "    spec:",
                "      containers:",
                "        - name: api",
                f"          image: {values['BACKEND_IMAGE']}",
                "---",
                "apiVersion: apps/v1",
                "kind: Deployment",
                "metadata:",
                "  name: expense-tracker-worker",
                "spec:",
                "  template:",
                "    spec:",
                "      containers:",
                "        - name: worker",
                f"          image: {values['BACKEND_IMAGE']}",
                "---",
                "apiVersion: apps/v1",
                "kind: Deployment",
                "metadata:",
                "  name: expense-tracker-site",
                "spec:",
                "  template:",
                "    spec:",
                "      containers:",
                "        - name: site",
                f"          image: {values['SITE_IMAGE']}",
                "---",
                "apiVersion: batch/v1",
                "kind: CronJob",
                "metadata:",
                "  name: postgres-backup",
                "spec:",
                "  jobTemplate:",
                "    spec:",
                "      template:",
                "        spec:",
                "          containers:",
                "            - name: postgres-backup",
                f"              image: {values['POSTGRES_BACKUP_IMAGE']}",
                "",
            ]
        ),
        encoding="utf-8",
        newline="\n",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env-file", default=".env.production")
    parser.add_argument(
        "--output-dir",
        default="infra/k8s/overlays/production/generated",
    )
    args = parser.parse_args()

    env_path = Path(args.env_file).resolve()
    output_dir = Path(args.output_dir).resolve()
    if not env_path.is_file():
        raise SystemExit(f"Env file not found: {env_path}")

    raw_values = parse_env_file(env_path)
    values = {**DEFAULTS, **raw_values}

    values["DATABASE_URL"] = build_database_url(values)
    values["REDIS_URL"] = build_redis_url(values)
    values["RABBITMQ_URL"] = build_rabbitmq_url(values)
    values["S3_ACCESS_KEY"] = values.get("S3_ACCESS_KEY", "").strip() or values["MINIO_ROOT_USER"]
    values["S3_SECRET_KEY"] = values.get("S3_SECRET_KEY", "").strip() or values["MINIO_ROOT_PASSWORD"]
    values["PUBLIC_APP_BASE_URL"] = values["PUBLIC_APP_BASE_URL"].rstrip("/")
    values["PUBLIC_API_HOST"] = url_host(values["PUBLIC_API_BASE_URL"])
    values["PUBLIC_APP_HOST"] = url_host(values["PUBLIC_APP_BASE_URL"])
    values["PUBLIC_STORAGE_HOST"] = url_host(values["S3_EXTERNAL_ENDPOINT"])
    values["APP_WEBSITE_URL"] = (
        values.get("APP_WEBSITE_URL", "").strip() or values["PUBLIC_APP_BASE_URL"]
    ).rstrip("/")
    values["APP_PRIVACY_URL"] = (
        values.get("APP_PRIVACY_URL", "").strip() or "https://example.com/privacy"
    )
    values["APP_TERMS_URL"] = (
        values.get("APP_TERMS_URL", "").strip() or "https://example.com/terms"
    )
    values["APP_DELETE_ACCOUNT_URL"] = (
        values.get("APP_DELETE_ACCOUNT_URL", "").strip()
        or f"{values['APP_WEBSITE_URL']}/delete-account"
    )
    values["APP_PLAY_SUBSCRIPTIONS_URL"] = (
        values.get("APP_PLAY_SUBSCRIPTIONS_URL", "").strip()
        or "https://play.google.com/store/account/subscriptions?package=com.nexavend.expense_tracker_app"
    )

    validate(values)

    config_values = {key: values[key] for key in CONFIG_KEYS if values.get(key, "").strip()}
    config_values["PUBLIC_API_HOST"] = values["PUBLIC_API_HOST"]
    config_values["PUBLIC_APP_HOST"] = values["PUBLIC_APP_HOST"]
    config_values["PUBLIC_STORAGE_HOST"] = values["PUBLIC_STORAGE_HOST"]
    secret_values = {key: values[key] for key in SECRET_KEYS if values.get(key, "").strip()}

    output_dir.mkdir(parents=True, exist_ok=True)
    write_env_file(output_dir / "config.env", config_values)
    write_env_file(output_dir / "secret.env", secret_values)
    write_schedule_patch(
        output_dir / "postgres-backup-schedule-patch.yaml",
        values["POSTGRES_BACKUP_SCHEDULE"],
    )
    write_prometheus_config(output_dir / "prometheus.yml", values)
    write_image_patches(output_dir, values)
    print(f"Wrote {output_dir / 'config.env'}")
    print(f"Wrote {output_dir / 'secret.env'}")
    print(f"Wrote {output_dir / 'postgres-backup-schedule-patch.yaml'}")
    print(f"Wrote {output_dir / 'prometheus.yml'}")
    print(f"Wrote {output_dir / 'api-image-patch.yaml'}")
    print(f"Wrote {output_dir / 'worker-image-patch.yaml'}")
    print(f"Wrote {output_dir / 'site-image-patch.yaml'}")
    print(f"Wrote {output_dir / 'postgres-backup-image-patch.yaml'}")


if __name__ == "__main__":
    main()
