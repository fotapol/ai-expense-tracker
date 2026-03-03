"""FastAPI application entry point."""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from app.api.routers import users
from app.auth.firebase_admin import initialize_firebase
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
    initialize_firebase()

    redis_ok = await check_redis_health()
    if redis_ok:
        logger.info("Redis connection verified.")
    else:
        logger.warning("Redis is not available — caching and rate limiting disabled.")

    await connect_rabbitmq()

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
