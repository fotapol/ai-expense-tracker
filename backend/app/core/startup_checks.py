"""Production configuration validation.

Called during application startup to catch misconfiguration early,
especially for production deployments where silent empty credentials
would cause hard-to-diagnose runtime failures.
"""

import logging
import os
import re

logger = logging.getLogger(__name__)

# Patterns that indicate a non-production endpoint value
_LOCAL_PATTERNS = re.compile(
    r"(192\.168\.\d+\.\d+|10\.0\.\d+\.\d+|127\.0\.0\.1|localhost)",
    re.IGNORECASE,
)


class _ConfigError:
    """Collected configuration error."""

    def __init__(self, var: str, message: str, *, fatal: bool = True):
        self.var = var
        self.message = message
        self.fatal = fatal

    def __str__(self) -> str:
        prefix = "ERROR" if self.fatal else "WARNING"
        return f"  [{prefix}] {self.var}: {self.message}"


def validate_production_config() -> None:
    """Validate critical environment variables at startup.

    In production (``APP_ENV=production``), missing or dangerous values
    cause a hard failure so the operator sees the problem immediately
    instead of discovering it through user-facing errors.

    In development, the same checks emit warnings.
    """
    app_env = os.environ.get("APP_ENV", "development").strip().lower()
    is_prod = app_env == "production"

    errors: list[_ConfigError] = []

    # --- General App --------------------------------------------------------
    public_url = os.environ.get("PUBLIC_APP_BASE_URL", "")
    if is_prod:
        if not public_url:
            errors.append(_ConfigError(
                "PUBLIC_APP_BASE_URL",
                "Not set. External links and redirects will not work.",
            ))
        elif _LOCAL_PATTERNS.search(public_url):
            errors.append(_ConfigError(
                "PUBLIC_APP_BASE_URL",
                f"Contains a local/private IP ({public_url}). "
                "Must be a publicly reachable endpoint in production.",
            ))

    # --- Database -----------------------------------------------------------
    db_url = os.environ.get("DATABASE_URL", "")
    if not db_url:
        errors.append(_ConfigError("DATABASE_URL", "Not set. Database connection will fail."))

    # --- S3 / MinIO ---------------------------------------------------------
    s3_access = os.environ.get("S3_ACCESS_KEY", "")
    s3_secret = os.environ.get("S3_SECRET_KEY", "")
    if not s3_access or not s3_secret:
        errors.append(_ConfigError(
            "S3_ACCESS_KEY / S3_SECRET_KEY",
            "Empty. Receipt storage will fail.",
        ))

    s3_ext = os.environ.get("S3_EXTERNAL_ENDPOINT", "")
    if is_prod:
        if not s3_ext:
            errors.append(_ConfigError(
                "S3_EXTERNAL_ENDPOINT",
                "Not set. Presigned receipt URLs will be unreachable by clients.",
            ))
        elif _LOCAL_PATTERNS.search(s3_ext):
            errors.append(_ConfigError(
                "S3_EXTERNAL_ENDPOINT",
                f"Contains a local/private IP ({s3_ext}). "
                "Must be a publicly reachable endpoint in production.",
            ))

    # --- Google / LLM -------------------------------------------------------
    google_key = os.environ.get("GOOGLE_API_KEY", "")
    if not google_key:
        errors.append(_ConfigError(
            "GOOGLE_API_KEY",
            "Empty. Receipt AI extraction will fail.",
        ))

    # --- RabbitMQ -----------------------------------------------------------
    rabbitmq_url = os.environ.get("RABBITMQ_URL", "")
    if rabbitmq_url and "guest:guest" in rabbitmq_url:
        errors.append(_ConfigError(
            "RABBITMQ_URL",
            "Uses default guest:guest credentials. Change for any non-localhost deployment.",
            fatal=is_prod,
        ))

    # --- Firebase -----------------------------------------------------------
    fb_path = os.environ.get("FIREBASE_SERVICE_ACCOUNT_PATH", "")
    if not fb_path:
        errors.append(_ConfigError(
            "FIREBASE_SERVICE_ACCOUNT_PATH",
            "Not set. Authentication will fail at startup.",
        ))

    # --- RevenueCat ---------------------------------------------------------
    rc_secret = os.environ.get("REVENUECAT_SECRET_API_KEY", "")
    if not rc_secret:
        errors.append(_ConfigError(
            "REVENUECAT_SECRET_API_KEY",
            "Empty. Subscription billing sync will not work.",
            fatal=False,  # App can start without billing
        ))

    # --- Report results -----------------------------------------------------
    if not errors:
        logger.info("Configuration validation passed (APP_ENV=%s).", app_env)
        return

    fatal_errors = [e for e in errors if e.fatal]
    warnings = [e for e in errors if not e.fatal]

    for w in warnings:
        logger.warning(str(w))

    if fatal_errors:
        for e in fatal_errors:
            logger.error(str(e))

        if is_prod:
            msg = (
                f"Production startup blocked: {len(fatal_errors)} critical "
                f"configuration error(s). Fix the above and restart."
            )
            logger.critical(msg)
            raise SystemExit(msg)
        else:
            logger.warning(
                "%d configuration issue(s) found. These would block "
                "startup in APP_ENV=production.",
                len(fatal_errors),
            )
