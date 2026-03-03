"""Database engine and session dependency."""

import logging
import os

from sqlmodel import Session, create_engine

logger = logging.getLogger(__name__)

DATABASE_URL = os.environ["DATABASE_URL"]

engine = create_engine(DATABASE_URL, echo=False)


def get_session():
    """Yield a SQLModel session scoped to a single request."""
    with Session(engine) as session:
        yield session
