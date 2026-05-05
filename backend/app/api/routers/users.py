"""User-facing API routes (authentication-protected)."""

import logging

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from sqlmodel import Session

from app.auth.deps import get_current_user
from app.cache.user_cache import cache_user, invalidate_user_cache
from app.core.db import get_session
from app.core.rate_limiter import limiter
from app.core.redis import get_redis
from app.models.users.profile import Profile
from app.models.users.user import User
from app.schemas.users import UserUpdate, UserWithProfileRead
from app.services.account_deletion import (
    AccountDeletionStorageCleanupError,
    delete_account_for_user,
)

router = APIRouter(prefix="/v1", tags=["users"])
logger = logging.getLogger(__name__)


@router.get("/me", response_model=UserWithProfileRead)
@limiter.limit("30/minute")
async def get_me(
    request: Request,
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Return the authenticated user's profile.

    Uses the existing ``UserRead`` schema from ``app.schemas.users``
    to guarantee a single source of truth for the API contract.

    Rate limited to 30 requests/minute per IP.
    """
    return current_user


@router.patch("/me", response_model=UserWithProfileRead)
@limiter.limit("30/minute")
async def patch_me(
    payload: UserUpdate,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Update mutable user profile settings such as default currency."""

    current_user = session.merge(current_user)
    update_data = payload.model_dump(exclude_unset=True)
    if not update_data:
        return current_user

    if "display_name" in update_data:
        display_name = update_data.pop("display_name")
        if current_user.profile:
            current_user.profile.display_name = display_name
        else:
            profile = Profile(user_id=current_user.id, display_name=display_name)
            session.add(profile)
            current_user.profile = profile

    for key, value in update_data.items():
        setattr(current_user, key, value)
    session.commit()
    session.refresh(current_user)

    redis = get_redis()
    await invalidate_user_cache(redis, current_user.auth_subject)
    await cache_user(redis, current_user)
    return current_user


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit("5/hour")
async def delete_me(
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Hard-delete the authenticated user's account and local app data."""

    current_user = session.merge(current_user)
    auth_subject = current_user.auth_subject
    try:
        result = delete_account_for_user(session=session, user=current_user)
    except AccountDeletionStorageCleanupError as exc:
        logger.warning(
            "Account deletion blocked by %d receipt storage cleanup failure(s) for user_id=%s.",
            len(exc.failures),
            current_user.id,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Account storage cleanup failed. Please try again.",
        ) from None

    redis = get_redis()
    await invalidate_user_cache(redis, auth_subject)
    if result.storage_delete_failures:
        logger.warning(
            "Account deletion completed with %d receipt storage cleanup failures for user_id=%s.",
            len(result.storage_delete_failures),
            result.user_id,
        )
    return Response(status_code=status.HTTP_204_NO_CONTENT)
