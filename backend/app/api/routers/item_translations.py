"""Item translation cache API routes."""

from fastapi import APIRouter, Depends, Request
from sqlmodel import Session, select

from app.auth.deps import get_current_user
from app.core.db import get_session
from app.core.rate_limiter import limiter
from app.models.translations.item_translation import ItemTranslation
from app.models.users.user import User
from app.schemas.item_translations import (
    ItemTranslationBatchRequest,
    ItemTranslationBatchResponse,
    normalized_source_text_key,
)

router = APIRouter(prefix="/v1", tags=["item-translations"])


@router.post("/item-translations/batch", response_model=ItemTranslationBatchResponse)
@limiter.limit("60/minute")
async def upsert_item_translations_batch(
    payload: ItemTranslationBatchRequest,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Upsert a user-scoped batch of item translation cache entries."""

    inserted_count = 0
    updated_count = 0

    for item in payload.items:
        normalized_source_text = normalized_source_text_key(item.source_text)
        existing = session.exec(
            select(ItemTranslation).where(
                ItemTranslation.user_id == current_user.id,
                ItemTranslation.normalized_source_text == normalized_source_text,
                ItemTranslation.source_language == item.source_language,
                ItemTranslation.target_language == item.target_language,
            )
        ).first()

        if existing is None:
            session.add(
                ItemTranslation(
                    user_id=current_user.id,
                    source_text=item.source_text,
                    normalized_source_text=normalized_source_text,
                    source_language=item.source_language,
                    target_language=item.target_language,
                    translated_text=item.translated_text,
                    provider=item.provider or "mlkit",
                )
            )
            inserted_count += 1
            continue

        existing.source_text = item.source_text
        existing.translated_text = item.translated_text
        existing.provider = item.provider or "mlkit"
        session.add(existing)
        updated_count += 1

    session.commit()
    return ItemTranslationBatchResponse(
        inserted_count=inserted_count,
        updated_count=updated_count,
        provider="mlkit",
    )
