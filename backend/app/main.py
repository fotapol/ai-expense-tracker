"""FastAPI application entry point."""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from app.api.routers import (
    billing,
    categories,
    data,
    feature_requests,
    # TODO(household): re-import when household feature ships
    # households,
    item_translations,
    labels,
    planning,
    receipts,
    transactions,
    users,
)
from app.auth.firebase_admin import initialize_firebase
from app.core.migrations import run_startup_migrations
from app.core.rabbitmq import check_rabbitmq_health, close_rabbitmq, connect_rabbitmq
from app.core.rate_limiter import limiter
from app.core.redis import check_redis_health, close_redis_pool

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application startup and shutdown lifecycle handler."""
    # --- Startup ---------------------------------------------------------
    await run_startup_migrations()
    initialize_firebase()

    redis_ok = await check_redis_health()
    if redis_ok:
        logger.info("Redis connection verified.")
    else:
        logger.warning("Redis is not available — caching and rate limiting disabled.")

    await connect_rabbitmq()

    # Ensure the receipts S3 bucket exists in MinIO.
    try:
        from app.core.minio import ensure_bucket

        ensure_bucket()
    except Exception:
        logger.warning("Could not verify or create S3 receipts bucket.", exc_info=True)

    logger.info("Application startup complete.")
    yield

    # --- Shutdown --------------------------------------------------------
    await close_rabbitmq()
    await close_redis_pool()
    logger.info("Application shutdown.")


app = FastAPI(
    title="Expense Tracker API",
    lifespan=lifespan,
)

# Rate limiting
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

app.include_router(users.router)
app.include_router(receipts.router)
app.include_router(transactions.router)
app.include_router(categories.router)
app.include_router(labels.router)
app.include_router(item_translations.router)
app.include_router(billing.router)
app.include_router(data.router)
# TODO(household): re-enable when household feature ships
# app.include_router(households.router)
app.include_router(feature_requests.router)
app.include_router(feature_requests.internal_router)
app.include_router(planning.router)
if billing.should_include_dev_billing_router():
    app.include_router(billing.dev_router)

@app.get("/", tags=["health"])
async def healthcheck():
    """Liveness + dependency health probe."""
    redis_ok = await check_redis_health()
    rabbitmq_ok = await check_rabbitmq_health()
    return {
        "status": "ok",
        "dependencies": {
            "redis": "up" if redis_ok else "down",
            "rabbitmq": "up" if rabbitmq_ok else "down",
        },
    }
