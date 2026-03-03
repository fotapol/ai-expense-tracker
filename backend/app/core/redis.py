"""Redis connection pool and dependency."""

import logging
import os

import redis.asyncio as aioredis

logger = logging.getLogger(__name__)

REDIS_URL: str = os.environ.get("REDIS_URL", "redis://redis:6379/0")

_pool: aioredis.ConnectionPool | None = None


def get_redis_pool() -> aioredis.ConnectionPool:
    """Return (and lazily create) the module-level Redis connection pool."""
    global _pool
    if _pool is None:
        _pool = aioredis.ConnectionPool.from_url(
            REDIS_URL,
            max_connections=20,
            decode_responses=True,
        )
    return _pool


def get_redis() -> aioredis.Redis:
    """Create a Redis client bound to the shared connection pool.

    Usage as a FastAPI dependency::

        @router.get("/example")
        async def example(r: aioredis.Redis = Depends(get_redis)):
            await r.get("key")
    """
    return aioredis.Redis(connection_pool=get_redis_pool())


async def check_redis_health() -> bool:
    """Ping Redis and return True if healthy, False otherwise."""
    try:
        r = get_redis()
        return await r.ping()
    except Exception:
        logger.exception("Redis health check failed.")
        return False


async def close_redis_pool() -> None:
    """Close the connection pool on application shutdown."""
    global _pool
    if _pool is not None:
        await _pool.aclose()
        _pool = None
        logger.info("Redis connection pool closed.")
