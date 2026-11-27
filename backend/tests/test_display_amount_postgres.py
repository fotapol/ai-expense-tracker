"""Execute display-currency filtering with PostgreSQL NUMERIC and real FKs."""

import os
import uuid

import pytest
from sqlalchemy import text
from sqlmodel import Session, SQLModel, create_engine
from test_transaction_history import OWNER, add, add_rate, page

import app.models  # noqa: F401 - register the complete model graph
from app.models.users.user import User


def test_postgres_converted_bounds_are_rounded_scoped_and_paginated():
    dsn = os.environ.get("TEST_POSTGRES_DSN")
    if not dsn:
        pytest.skip("Set TEST_POSTGRES_DSN for the disposable PostgreSQL contract test")
    schema = f"display_amount_{uuid.uuid4().hex}"
    admin = create_engine(dsn)
    with admin.begin() as connection:
        connection.execute(text(f'CREATE SCHEMA "{schema}"'))
    engine = create_engine(dsn, connect_args={"options": f"-csearch_path={schema}"})
    try:
        SQLModel.metadata.create_all(engine)
        with Session(engine) as session:
            session.add(User(id=OWNER, auth_subject="display-amount-test"))
            other = User(auth_subject="other-display-amount-test")
            session.add(other)
            session.commit()
            add_rate(session, "USD", "0.5")
            add_rate(session, "RSD", "0.00833333")
            add(session, 1, amount="10")
            add(session, 2, currency="USD", amount="20")
            add(session, 3, currency="RSD", amount="1200")
            add(session, 4, amount="10.01")
            add(session, 5, currency="JPY", amount="10")
            hidden = add(session, 6, amount="10")
            hidden.user_id = other.id
            session.add(hidden)
            session.commit()
            params = dict(
                min_display_amount="10", max_display_amount="10", target_currency="EUR", page_size=2
            )
            first = page(session, **params)
            second = page(session, page=2, **params)
            assert len(first) == 2 and len(second) == 1
            assert {row.id.int for row in first + second} == {1, 2, 3}
    finally:
        engine.dispose()
        with admin.begin() as connection:
            connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        admin.dispose()
