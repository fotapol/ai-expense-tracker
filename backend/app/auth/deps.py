"""FastAPI dependency that resolves the current authenticated user."""

import logging
import os

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from firebase_admin import auth as firebase_auth
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.auth.firebase_admin import verify_token
from app.cache.user_cache import cache_user, get_cached_user, invalidate_user_cache
from app.core.db import get_session
from app.core.redis import get_redis
from app.models.users.user import User

logger = logging.getLogger(__name__)

_bearer_scheme = HTTPBearer(
    description="Firebase ID token obtained via Firebase Auth SDK.",
)


def _parse_admin_email_allowlist() -> set[str]:
    raw = os.environ.get("DEV_BILLING_ADMIN_EMAILS", "")
    return {item.strip().lower() for item in raw.split(",") if item.strip()}


def _email_is_dev_billing_admin(email: str | None) -> bool:
    if not email:
        return False
    return email.strip().lower() in _parse_admin_email_allowlist()


async def get_current_user(
    request: Request,
    credentials: HTTPAuthorizationCredentials = Depends(_bearer_scheme),  # noqa: B008
    session: Session = Depends(get_session),  # noqa: B008
) -> User:
    """Verify the Firebase ID token, resolve (or create) the local user row.

    Performance: checks Redis cache before hitting the database.
    Cache is invalidated when user data changes (email sync).

    Security notes:
    * Rejects tokens that are expired, malformed, or signed by an
      unknown project.
    * Checks that ``email_verified`` is True before auto-creating a user;
      prevents abuse with unverified throwaway emails.
    * Never logs the raw token value; only the short Firebase UID.
    """
    # --- Verify token ---------------------------------------------------
    try:
        claims = verify_token(credentials.credentials)
    except firebase_auth.ExpiredIdTokenError:
        logger.warning("Rejected expired Firebase ID token.")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token has expired. Please re-authenticate.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from None
    except firebase_auth.RevokedIdTokenError:
        logger.warning("Rejected revoked Firebase ID token.")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token has been revoked. Please re-authenticate.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from None
    except firebase_auth.InvalidIdTokenError:
        logger.warning("Rejected invalid Firebase ID token.")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication token.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from None
    except Exception:
        logger.exception("Unexpected error during token verification.")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication failed.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from None

    # --- Extract claims --------------------------------------------------
    uid: str | None = claims.get("uid")
    email: str | None = claims.get("email")
    email_verified: bool = claims.get("email_verified", False)

    if not uid:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token does not contain a valid uid.",
        )

    should_be_admin = _email_is_dev_billing_admin(email)

    # --- Cache-first lookup ----------------------------------------------
    redis = get_redis()
    statement = select(User).where(
        User.auth_subject == uid,
        User.auth_provider == "firebase",
    )

    cached = await get_cached_user(redis, uid)
    if cached is not None:
        user = session.exec(select(User).where(User.id == cached.id)).first()
        if user is None:
            # Cache may be stale relative to DB; fall back to auth_subject lookup.
            user = session.exec(statement).first()
        if user is not None:
            # Even on cache hit, sync email if it changed.
            changed = False
            if email and user.email != email:
                user.email = email
                changed = True
            if should_be_admin and not user.is_admin:
                user.is_admin = True
                changed = True
            if changed:
                session.add(user)
                session.commit()
                session.refresh(user)
                await invalidate_user_cache(redis, uid)
                await cache_user(redis, user)
            return user

        await invalidate_user_cache(redis, uid)

    # --- DB lookup -------------------------------------------------------
    user = session.exec(statement).first()

    if user is not None:
        # Update email if it changed on the provider side.
        changed = False
        if email and user.email != email:
            user.email = email
            changed = True
        if should_be_admin and not user.is_admin:
            user.is_admin = True
            changed = True
        if changed:
            session.add(user)
            session.commit()
            session.refresh(user)
        await cache_user(redis, user)
        return user

    # --- Auto-create user ------------------------------------------------
    if email and not email_verified:
        logger.warning("Blocked auto-creation for uid=%s: email not verified.", uid)
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Email address has not been verified.",
        )

    user = User(
        email=email,
        auth_provider="firebase",
        auth_subject=uid,
        is_admin=should_be_admin,
    )
    session.add(user)
    try:
        session.commit()
        session.refresh(user)
    except IntegrityError:
        # Concurrent request created the same user first.
        session.rollback()
        user = session.exec(statement).first()
        if user is None:
            raise

    logger.info("Created new local user id=%s for firebase uid=%s.", user.id, uid)
    await cache_user(redis, user)
    return user
