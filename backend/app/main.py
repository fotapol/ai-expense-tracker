"""FastAPI application entry point."""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from starlette.exceptions import HTTPException as StarletteHTTPException
from starlette.middleware.cors import CORSMiddleware
from starlette.middleware.trustedhost import TrustedHostMiddleware
from starlette.responses import JSONResponse

from app.api.routers import (
    billing,
    categories,
    data,
    feature_requests,
    item_translations,
    labels,
    planning,
    receipts,
    transactions,
    users,
)
from app.auth.firebase_admin import initialize_firebase
from app.core.config import app_settings
from app.core.db import check_database_health
from app.core.logging import BackendLoggingMiddleware, configure_logging
from app.core.metrics import install_metrics, set_api_dependency_health
from app.core.migrations import run_startup_migrations
from app.core.rabbitmq import check_rabbitmq_health, close_rabbitmq, connect_rabbitmq
from app.core.rate_limiter import limiter
from app.core.redis import check_redis_health, close_redis_pool
from app.core.startup_checks import validate_production_config

configure_logging(service_name="api")
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application startup and shutdown lifecycle handler."""
    # --- Startup ---------------------------------------------------------
    validate_production_config()
    if app_settings.RUN_STARTUP_MIGRATIONS:
        await run_startup_migrations()
    else:
        logger.info("Startup database migrations disabled by RUN_STARTUP_MIGRATIONS.")
    initialize_firebase()

    redis_ok = await check_redis_health()
    if redis_ok:
        logger.info("Redis connection verified.")
    else:
        logger.warning("Redis is not available — caching and rate limiting disabled.")

    await connect_rabbitmq()

    # Ensure required MinIO buckets exist before serving traffic.
    try:
        from app.core.config import s3_settings
        from app.core.minio import ensure_bucket

        ensure_bucket(s3_settings.BUCKET_RECEIPTS)
        ensure_bucket(s3_settings.BUCKET_BACKUPS)
    except Exception:
        logger.warning("Could not verify or create required S3 buckets.", exc_info=True)

    logger.info("Application startup complete.")
    yield

    # --- Shutdown --------------------------------------------------------
    await close_rabbitmq()
    await close_redis_pool()
    logger.info("Application shutdown.")


app = FastAPI(
    title="Expense Tracker API",
    lifespan=lifespan,
    docs_url="/docs" if app_settings.API_DOCS_ENABLED else None,
    redoc_url="/redoc" if app_settings.API_DOCS_ENABLED else None,
    openapi_url="/openapi.json" if app_settings.API_DOCS_ENABLED else None,
)

# Rate limiting
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

app.add_middleware(
    TrustedHostMiddleware,
    allowed_hosts=list(app_settings.TRUSTED_HOSTS),
    www_redirect=False,
)
if app_settings.CORS_ALLOWED_ORIGINS:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=list(app_settings.CORS_ALLOWED_ORIGINS),
        allow_credentials=True,
        allow_methods=["DELETE", "GET", "OPTIONS", "PATCH", "POST", "PUT"],
        allow_headers=["Authorization", "Content-Type", "X-Requested-With"],
    )
app.add_middleware(BackendLoggingMiddleware)
install_metrics(app)

@app.exception_handler(StarletteHTTPException)
async def _http_exception_handler(request: Request, exc: StarletteHTTPException):
    from starlette.responses import JSONResponse
    # If the detail is a dict (like from auth limits), preserve it, else string
    message = exc.detail if isinstance(exc.detail, dict) else str(exc.detail)
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": {"code": "HTTP_ERROR", "message": message}},
    )

@app.exception_handler(RequestValidationError)
async def _validation_exception_handler(request: Request, exc: RequestValidationError):
    from starlette.responses import JSONResponse
    # Safely convert errors to dict layout
    errors = exc.errors()
    # Pydantic validation errors format
    return JSONResponse(
        status_code=422,
        content={
            "error": {
                "code": "VALIDATION_ERROR",
                "message": "Invalid request attributes.",
                "details": errors,
            }
        },
    )

# Global unhandled exception handler — ensures unexpected 500 errors return
# a safe, generic response instead of leaking internal tracebacks to clients.
@app.exception_handler(Exception)
async def _unhandled_exception_handler(request: Request, exc: Exception):
    from starlette.responses import JSONResponse

    request_id = getattr(request.state, "request_id", "unknown")
    logger.exception(
        "[%s] Unhandled %s on %s %s",
        request_id,
        type(exc).__name__,
        request.method,
        request.url.path,
    )
    return JSONResponse(
        status_code=500,
        content={"error": {"code": "INTERNAL_ERROR", "message": "An internal error occurred. Please try again later."}},
    )


app.include_router(users.router)
app.include_router(receipts.router)
app.include_router(transactions.router)
app.include_router(categories.router)
app.include_router(labels.router)
app.include_router(item_translations.router)
app.include_router(billing.router)
app.include_router(data.router)
app.include_router(feature_requests.router)
app.include_router(feature_requests.internal_router)
app.include_router(planning.router)
if billing.should_include_dev_billing_router():
    app.include_router(billing.dev_router)

async def _build_health_payload() -> tuple[dict, bool]:
    """Return dependency health details and readiness state."""

    database_ok = check_database_health()
    redis_ok = await check_redis_health()
    rabbitmq_ok = await check_rabbitmq_health()
    set_api_dependency_health(dependency="database", is_up=database_ok)
    set_api_dependency_health(dependency="redis", is_up=redis_ok)
    set_api_dependency_health(dependency="rabbitmq", is_up=rabbitmq_ok)
    ready = database_ok and rabbitmq_ok
    return (
        {
            "status": "ok" if ready else "degraded",
            "dependencies": {
                "database": "up" if database_ok else "down",
                "redis": "up" if redis_ok else "down",
                "rabbitmq": "up" if rabbitmq_ok else "down",
            },
        },
        ready,
    )


@app.get("/", tags=["health"])
async def healthcheck():
    """Minimal public-safe root status endpoint."""

    return {
        "status": "ok",
        "service": "expense-tracker-api",
    }


@app.get("/health/live", tags=["health"])
async def liveness_check():
    """Container liveness probe that only verifies the process is serving HTTP."""

    return {"status": "ok"}


@app.get("/health/ready", tags=["health"])
async def readiness_check():
    """Readiness probe for critical launch-path dependencies."""

    payload, ready = await _build_health_payload()
    return JSONResponse(
        status_code=status.HTTP_200_OK if ready else status.HTTP_503_SERVICE_UNAVAILABLE,
        content=payload,
    )
