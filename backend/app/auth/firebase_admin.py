"""Firebase Admin SDK initialization and token verification."""

import logging
import os

import firebase_admin
from firebase_admin import auth, credentials

logger = logging.getLogger(__name__)

_FIREBASE_SERVICE_ACCOUNT_PATH = os.getenv(
    "FIREBASE_SERVICE_ACCOUNT_PATH",
    "/run/secrets/firebase_sa.json",
)


def initialize_firebase() -> None:
    """Initialize the Firebase Admin SDK once using a service-account JSON file.

    Raises RuntimeError if the credential file is missing or invalid so that
    the application fails fast on startup instead of silently accepting
    every request without verification.
    """
    if firebase_admin._apps:
        logger.info("Firebase Admin SDK already initialized, skipping.")
        return

    if not os.path.isfile(_FIREBASE_SERVICE_ACCOUNT_PATH):
        raise RuntimeError(
            f"Firebase service-account file not found: {_FIREBASE_SERVICE_ACCOUNT_PATH}. "
            "Set FIREBASE_SERVICE_ACCOUNT_PATH to a valid path."
        )

    cred = credentials.Certificate(_FIREBASE_SERVICE_ACCOUNT_PATH)
    firebase_admin.initialize_app(cred)
    logger.info("Firebase Admin SDK initialized successfully.")


def verify_token(id_token: str, *, check_revoked: bool = False) -> dict:
    """Verify a Firebase ID token and return the decoded claims.

    Raises firebase_admin.auth exceptions on invalid / expired / revoked
    tokens so the caller can map them to appropriate HTTP responses.
    """
    return auth.verify_id_token(id_token, check_revoked=check_revoked)


def delete_firebase_user(uid: str) -> bool:
    """Delete a Firebase Auth user, returning whether a row was removed."""
    normalized_uid = (uid or "").strip()
    if not normalized_uid:
        logger.warning("Skipped Firebase user deletion because uid was empty.")
        return False
    try:
        auth.delete_user(normalized_uid)
    except auth.UserNotFoundError:
        logger.info("Firebase user already absent for uid=%s.", normalized_uid)
        return False
    except Exception:
        logger.exception("Failed to delete Firebase user uid=%s.", normalized_uid)
        return False
    return True
