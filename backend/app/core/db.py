"""Database engine and session dependency."""

import logging

from sqlalchemy import text
from sqlmodel import Session, create_engine

from app.core.config import database_settings

logger = logging.getLogger(__name__)

engine = create_engine(database_settings.DATABASE_URL, echo=False, pool_pre_ping=True)


def get_session():
    """Yield a SQLModel session scoped to a single request."""
    with Session(engine) as session:
        yield session


def check_database_health() -> bool:
    """Return whether the application can execute a trivial database query."""

    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
        return True
    except Exception:
        logger.exception("Database health check failed.")
        return False
