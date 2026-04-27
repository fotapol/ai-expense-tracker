import uuid

from sqlmodel import Session, SQLModel, create_engine

import app.services.billing.category_usage as category_usage
from app.models.shared.enums import CategoryScope
from app.models.taxonomy.category import Category
from app.models.users.user import User


def _category(
    *,
    user_id,
    name,
    scope=CategoryScope.ITEM,
    parent_id=None,
    is_custom=True,
    is_active=True,
):
    return Category(
        scope=scope,
        code=name.upper().replace(" ", "_"),
        name=name,
        parent_id=parent_id,
        user_id=user_id,
        is_custom=is_custom,
        is_active=is_active,
    )


def test_category_usage_counts_only_active_custom_item_rows(monkeypatch):
    engine = create_engine("sqlite:///:memory:")
    SQLModel.metadata.create_all(engine, tables=[User.__table__, Category.__table__])
    user_id = uuid.uuid4()
    other_user_id = uuid.uuid4()
    parent_id = uuid.uuid4()

    monkeypatch.setattr(category_usage, "user_has_feature", lambda *_args, **_kwargs: False)
    with Session(engine) as session:
        session.add_all(
            [
                _category(user_id=user_id, name="Active Custom"),
                _category(user_id=user_id, name="Inactive Custom", is_active=False),
                _category(user_id=None, name="Built In", is_custom=False),
                _category(user_id=other_user_id, name="Other User"),
                _category(user_id=user_id, name="Custom Sub", parent_id=parent_id),
                _category(
                    user_id=user_id,
                    name="Transaction Scope",
                    scope=CategoryScope.TRANSACTION,
                ),
            ]
        )
        session.commit()

        usage = category_usage.resolve_category_usage(session, user_id)

    assert usage.categories_used == 1
    assert usage.categories_limit == 3
    assert usage.categories_remaining == 2
    assert usage.subcategories_used == 1
    assert usage.subcategories_limit == 10
    assert usage.subcategories_remaining == 9
    assert usage.is_unlimited is False


def test_category_usage_is_unlimited_with_premium_feature(monkeypatch):
    engine = create_engine("sqlite:///:memory:")
    SQLModel.metadata.create_all(engine, tables=[User.__table__, Category.__table__])
    user_id = uuid.uuid4()

    monkeypatch.setattr(category_usage, "user_has_feature", lambda *_args, **_kwargs: True)
    with Session(engine) as session:
        session.add(_category(user_id=user_id, name="Active Custom"))
        session.commit()

        usage = category_usage.resolve_category_usage(session, user_id)

    assert usage.categories_used == 1
    assert usage.categories_limit is None
    assert usage.categories_remaining is None
    assert usage.subcategories_limit is None
    assert usage.subcategories_remaining is None
    assert usage.is_unlimited is True
