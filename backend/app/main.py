"""FastAPI application entry point."""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.api.routers import users
from app.auth.firebase_admin import initialize_firebase

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application startup and shutdown lifecycle handler."""
    initialize_firebase()
    logger.info("Application startup complete.")
    yield
    logger.info("Application shutdown.")


app = FastAPI(
    title="Expense Tracker API",
    lifespan=lifespan,
)

app.include_router(users.router)


@app.get("/", tags=["health"])
async def healthcheck():
    """Simple liveness probe."""
    return {"status": "ok"}
