"""User-facing API routes (authentication-protected)."""

from fastapi import APIRouter, Depends

from app.auth.deps import get_current_user
from app.models.users.user import User
from app.schemas.users import UserRead

router = APIRouter(prefix="/v1", tags=["users"])


@router.get("/me", response_model=UserRead)
def get_me(current_user: User = Depends(get_current_user)):  # noqa: B008
    """Return the authenticated user's profile.

    Uses the existing ``UserRead`` schema from ``app.schemas.users``
    to guarantee a single source of truth for the API contract.
    """
    return current_user
