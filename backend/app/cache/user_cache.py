"""User profile cache backed by Redis.

Caches the User ORM object as JSON keyed by auth_subject to avoid a DB
round-trip on every authenticated request.  TTL is intentionally short
(5 min) so that email syncs and profile changes propagate quickly.
"""

import json
import logging

import redis.asyncio as aioredis

from app.models.users.user import User

logger = logging.getLogger(__name__)

_KEY_PREFIX = "user:firebase:"
_TTL_SECONDS = 300  # 5 minutes


def _cache_key(auth_subject: str) -> str:
    return f"{_KEY_PREFIX}{auth_subject}"


async def get_cached_user(r: aioredis.Redis, auth_subject: str) -> User | None:
    """Return a User from cache, or None on miss / error."""
    try:
        raw = await r.get(_cache_key(auth_subject))
        if raw is None:
            return None
        data = json.loads(raw)
        return User.model_validate(data)
    except Exception:
        # Cache errors must never break authentication.
        logger.warning("Cache read failed for %s, falling back to DB.", auth_subject)
        return None


async def cache_user(r: aioredis.Redis, user: User) -> None:
    """Store a User in cache with TTL."""
    try:
        key = _cache_key(user.auth_subject)
        payload = user.model_dump_json()
        await r.setex(key, _TTL_SECONDS, payload)
    except Exception:
        logger.warning("Cache write failed for user %s.", user.id)


async def invalidate_user_cache(r: aioredis.Redis, auth_subject: str) -> None:
    """Delete a user's cached entry (e.g. after profile update)."""
    try:
        await r.delete(_cache_key(auth_subject))
    except Exception:
        logger.warning("Cache invalidation failed for %s.", auth_subject)
