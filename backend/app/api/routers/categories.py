"""Category API endpoints for fetching taxonomy data."""

import logging
from typing import Annotated

from fastapi import APIRouter, Depends, Request
from sqlmodel import Session, select

from app.auth.deps import get_current_user
from app.core.db import get_session
from app.core.rate_limiter import limiter
from app.models.taxonomy.category import Category
from app.models.users.user import User

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1", tags=["categories"])

@router.get("/categories")
@limiter.limit("60/minute")
async def list_categories(
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """List all available categories.""" # Returning all instead of CategoryRead to avoid schema boilerplate for now
    
    # Simple list of all active categories (since there's no CategoryRead schema created yet, 
    # we return dicts to keep it fast, or rely on FastAPI to serialize the SQLModel directly)
    categories = session.exec(
        select(Category).where(Category.is_active == True).order_by(Category.name)
    ).all()
    
    return categories
