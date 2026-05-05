"""RabbitMQ async connection infrastructure.

Provides connect / close lifecycle hooks and a health probe.
No producers or consumers are implemented yet — those will be
added when receipt processing or notifications are built.
"""

import asyncio
import logging

import aio_pika

from app.core.config import rabbitmq_settings

logger = logging.getLogger(__name__)

_connection: aio_pika.abc.AbstractRobustConnection | None = None

_MAX_RETRIES = 5
_RETRY_DELAY_SECONDS = 3


async def connect_rabbitmq() -> None:
    """Open a robust (auto-reconnecting) connection to RabbitMQ.

    Retries up to _MAX_RETRIES times with a delay, because RabbitMQ
    can take 5-10 seconds to become ready after container start.
    """
    global _connection
    for attempt in range(1, _MAX_RETRIES + 1):
        try:
            _connection = await aio_pika.connect_robust(rabbitmq_settings.RABBITMQ_URL)
            logger.info("RabbitMQ connection established (attempt %d).", attempt)
            return
        except Exception:
            if attempt < _MAX_RETRIES:
                logger.warning(
                    "RabbitMQ not ready (attempt %d/%d), retrying in %ds...",
                    attempt,
                    _MAX_RETRIES,
                    _RETRY_DELAY_SECONDS,
                )
                await asyncio.sleep(_RETRY_DELAY_SECONDS)
            else:
                logger.exception(
                    "Failed to connect to RabbitMQ after %d attempts — "
                    "message queuing unavailable.",
                    _MAX_RETRIES,
                )
                # Non-fatal: the app can still serve HTTP without the queue.
                _connection = None


async def close_rabbitmq() -> None:
    """Gracefully close the RabbitMQ connection."""
    global _connection
    if _connection is not None and not _connection.is_closed:
        await _connection.close()
        logger.info("RabbitMQ connection closed.")
    _connection = None


def get_rabbitmq_connection() -> aio_pika.abc.AbstractRobustConnection | None:
    """Return the current connection, or None if unavailable."""
    return _connection


async def check_rabbitmq_health() -> bool:
    """Return True if the RabbitMQ connection is open."""
    return _connection is not None and not _connection.is_closed
