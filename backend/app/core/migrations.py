"""Startup migration utilities."""

from __future__ import annotations

import asyncio
import logging
import os
from pathlib import Path

from alembic import command
from alembic.config import Config

logger = logging.getLogger(__name__)

_MAX_RETRIES = 10
_RETRY_DELAY_SECONDS = 2


def _upgrade_head() -> None:
    ini_path = Path(__file__).resolve().parents[2] / "alembic.ini"
    cfg = Config(str(ini_path))
    database_url = os.environ.get("DATABASE_URL")
    if database_url:
        cfg.set_main_option("sqlalchemy.url", database_url)
    command.upgrade(cfg, "head")


async def run_startup_migrations() -> None:
    """Apply Alembic migrations before serving requests."""

    for attempt in range(1, _MAX_RETRIES + 1):
        try:
            await asyncio.to_thread(_upgrade_head)
            logger.info("Database migrations are up to date (attempt %d).", attempt)
            return
        except Exception:
            if attempt >= _MAX_RETRIES:
                logger.exception(
                    "Failed to apply database migrations after %d attempts.",
                    _MAX_RETRIES,
                )
                raise
            logger.warning(
                "Database not ready for migrations (attempt %d/%d), retrying in %ds...",
                attempt,
                _MAX_RETRIES,
                _RETRY_DELAY_SECONDS,
            )
            await asyncio.sleep(_RETRY_DELAY_SECONDS)

