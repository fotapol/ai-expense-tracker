"""add is_custom/user_id, seed taxonomy, and backfill transaction categories

Revision ID: 24f215cbe72a
Revises: 84485dd9c1e5
Create Date: 2026-03-05 11:27:28.086762
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from datetime import datetime, timezone

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "24f215cbe72a"
down_revision: str | Sequence[str] | None = "84485dd9c1e5"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


TOP_LEVEL_CATEGORIES: list[tuple[str, str]] = [
    ("FOOD", "Food"),
    ("CLOTHING", "Clothing"),
    ("TRANSPORT", "Transport"),
    ("UTILITIES", "Utilities"),
    ("HEALTH", "Health"),
    ("ENTERTAINMENT", "Entertainment"),
    ("HOME", "Home"),
    ("ELECTRONICS", "Electronics"),
    ("EDUCATION", "Education"),
    ("PERSONAL_CARE", "Personal Care"),
    ("OTHER", "Other"),
]

ITEM_SUBCATEGORIES: dict[str, list[tuple[str, str]]] = {
    "FOOD": [
        ("BAKERY_PRODUCTS", "Bakery Products"),
        ("BEVERAGES", "Beverages"),
        ("COFFEE_AND_TEA", "Coffee and Tea"),
        ("DAIRY_PRODUCTS", "Dairy Products"),
        ("FAST_FOOD", "Fast Food"),
        ("FROZEN_PRODUCTS", "Frozen Products"),
        ("FRUITS_AND_VEGETABLES", "Fruits and Vegetables"),
        ("MEAT_AND_SEAFOOD", "Meat and Seafood"),
        ("SNACKS_AND_SWEETS", "Snacks and Sweets"),
        ("PANTRY_STAPLES", "Pantry Staples"),
        ("BABY_FOOD", "Baby Food"),
        ("PET_FOOD", "Pet Food"),
    ],
    "CLOTHING": [
        ("EVERYDAY_WEAR", "Everyday Wear"),
        ("FORMAL_WEAR", "Formal Wear"),
        ("SHOES", "Shoes"),
        ("OUTERWEAR", "Outerwear"),
        ("SPORTSWEAR", "Sportswear"),
        ("UNDERWEAR", "Underwear"),
        ("ACCESSORIES", "Accessories"),
        ("KIDS_CLOTHING", "Kids Clothing"),
    ],
    "TRANSPORT": [
        ("FUEL", "Fuel"),
        ("PUBLIC_TRANSPORT", "Public Transport"),
        ("TAXI_RIDE_HAILING", "Taxi and Ride Hailing"),
        ("PARKING", "Parking"),
        ("TOLLS", "Tolls"),
        ("CAR_MAINTENANCE", "Car Maintenance"),
        ("CAR_WASH", "Car Wash"),
        ("VEHICLE_INSURANCE", "Vehicle Insurance"),
    ],
    "UTILITIES": [
        ("ELECTRICITY", "Electricity"),
        ("WATER", "Water"),
        ("GAS", "Gas"),
        ("INTERNET", "Internet"),
        ("MOBILE_PHONE", "Mobile Phone"),
        ("TV_AND_STREAMING", "TV and Streaming"),
        ("WASTE_COLLECTION", "Waste Collection"),
        ("HEATING", "Heating"),
    ],
    "HEALTH": [
        ("PHARMACY", "Pharmacy"),
        ("DOCTOR_VISIT", "Doctor Visit"),
        ("DENTAL", "Dental"),
        ("VISION", "Vision"),
        ("LAB_TESTS", "Lab Tests"),
        ("HEALTH_INSURANCE", "Health Insurance"),
        ("FITNESS", "Fitness"),
        ("SUPPLEMENTS", "Supplements"),
    ],
    "ENTERTAINMENT": [
        ("CINEMA", "Cinema"),
        ("MUSIC", "Music"),
        ("GAMES", "Games"),
        ("BOOKS", "Books"),
        ("EVENTS", "Events"),
        ("HOBBIES", "Hobbies"),
        ("STREAMING_SUBSCRIPTIONS", "Streaming Subscriptions"),
        ("TRAVEL_LEISURE", "Travel and Leisure"),
    ],
    "HOME": [
        ("RENT", "Rent"),
        ("MORTGAGE", "Mortgage"),
        ("FURNITURE", "Furniture"),
        ("HOME_MAINTENANCE", "Home Maintenance"),
        ("CLEANING_SUPPLIES", "Cleaning Supplies"),
        ("HOME_DECOR", "Home Decor"),
        ("APPLIANCES", "Appliances"),
        ("GARDEN", "Garden"),
    ],
    "ELECTRONICS": [
        ("PHONES", "Phones"),
        ("COMPUTERS", "Computers"),
        ("TABLETS", "Tablets"),
        ("ACCESSORIES", "Accessories"),
        ("SOFTWARE", "Software"),
        ("GAMING_HARDWARE", "Gaming Hardware"),
        ("SMART_HOME", "Smart Home"),
        ("REPAIRS", "Repairs"),
    ],
    "EDUCATION": [
        ("TUITION", "Tuition"),
        ("COURSES", "Courses"),
        ("BOOKS_AND_MATERIALS", "Books and Materials"),
        ("SCHOOL_SUPPLIES", "School Supplies"),
        ("ONLINE_LEARNING", "Online Learning"),
        ("EXAMS_CERTIFICATIONS", "Exams and Certifications"),
        ("TRAINING_WORKSHOPS", "Training and Workshops"),
        ("LANGUAGE_LEARNING", "Language Learning"),
    ],
    "PERSONAL_CARE": [
        ("HAIRCARE", "Haircare"),
        ("SKINCARE", "Skincare"),
        ("COSMETICS", "Cosmetics"),
        ("HYGIENE_PRODUCTS", "Hygiene Products"),
        ("BARBER_SALON", "Barber and Salon"),
        ("SPA_WELLNESS", "Spa and Wellness"),
        ("FRAGRANCES", "Fragrances"),
        ("PERSONAL_SERVICES", "Personal Services"),
    ],
    "OTHER": [
        ("MISCELLANEOUS", "Miscellaneous"),
        ("GIFTS_AND_DONATIONS", "Gifts and Donations"),
        ("FEES_AND_CHARGES", "Fees and Charges"),
        ("UNKNOWN_ITEM", "Unknown Item"),
    ],
}


def _ensure_category(
    conn: sa.Connection,
    *,
    scope: str,
    code: str,
    name: str,
    parent_id: uuid.UUID | None = None,
    user_id: uuid.UUID | None = None,
    is_custom: bool = False,
) -> uuid.UUID:
    if user_id is None:
        select_sql = sa.text(
            """
            SELECT id
            FROM categories
            WHERE scope = :scope
              AND code = :code
              AND user_id IS NULL
            ORDER BY updated_at DESC
            LIMIT 1
            """
        )
        existing_id = conn.execute(
            select_sql,
            {"scope": scope, "code": code},
        ).scalar_one_or_none()
    else:
        select_sql = sa.text(
            """
            SELECT id
            FROM categories
            WHERE scope = :scope
              AND code = :code
              AND user_id = :user_id
            ORDER BY updated_at DESC
            LIMIT 1
            """
        )
        existing_id = conn.execute(
            select_sql,
            {"scope": scope, "code": code, "user_id": user_id},
        ).scalar_one_or_none()
    if existing_id:
        conn.execute(
            sa.text(
                """
                UPDATE categories
                SET
                  name = :name,
                  parent_id = :parent_id,
                  is_active = TRUE,
                  is_custom = :is_custom,
                  updated_at = :now
                WHERE id = :id
                """
            ),
            {
                "id": existing_id,
                "name": name,
                "parent_id": parent_id,
                "is_custom": is_custom,
                "now": datetime.now(timezone.utc),
            },
        )
        return existing_id

    new_id = uuid.uuid4()
    now = datetime.now(timezone.utc)
    conn.execute(
        sa.text(
            """
            INSERT INTO categories (
              id, created_at, updated_at, scope, code, name, parent_id, is_active, user_id, is_custom
            )
            VALUES (
              :id, :created_at, :updated_at, :scope, :code, :name, :parent_id, TRUE, :user_id, :is_custom
            )
            """
        ),
        {
            "id": new_id,
            "created_at": now,
            "updated_at": now,
            "scope": scope,
            "code": code,
            "name": name,
            "parent_id": parent_id,
            "user_id": user_id,
            "is_custom": is_custom,
        },
    )
    return new_id


def _seed_taxonomy(conn: sa.Connection) -> dict[str, uuid.UUID]:
    tx_ids: dict[str, uuid.UUID] = {}
    item_top_ids: dict[str, uuid.UUID] = {}

    for code, name in TOP_LEVEL_CATEGORIES:
        tx_ids[code] = _ensure_category(conn, scope="TRANSACTION", code=code, name=name)
        item_top_ids[code] = _ensure_category(conn, scope="ITEM", code=code, name=name)

    for parent_code, children in ITEM_SUBCATEGORIES.items():
        parent_id = item_top_ids[parent_code]
        for child_code, child_name in children:
            _ensure_category(
                conn,
                scope="ITEM",
                code=child_code,
                name=child_name,
                parent_id=parent_id,
            )

    # Fallback item category is kept active and nested under OTHER.
    _ensure_category(
        conn,
        scope="ITEM",
        code="UNCATEGORIZED",
        name="Uncategorized",
        parent_id=item_top_ids["OTHER"],
    )
    return tx_ids


def _derive_parent_code_for_transaction(conn: sa.Connection, tx_id: uuid.UUID) -> str | None:
    rows = conn.execute(
        sa.text(
            """
            SELECT
              COALESCE(parent.code, child.code) AS top_code,
              SUM(ti.amount) AS total_amount
            FROM transaction_items ti
            JOIN categories child ON child.id = ti.category_id
            LEFT JOIN categories parent ON parent.id = child.parent_id
            WHERE ti.transaction_id = :tx_id
            GROUP BY COALESCE(parent.code, child.code)
            ORDER BY total_amount DESC
            """
        ),
        {"tx_id": tx_id},
    ).all()
    if not rows:
        return None
    return rows[0][0]


def _backfill_transaction_categories(conn: sa.Connection, tx_code_to_id: dict[str, uuid.UUID]) -> None:
    tx_rows = conn.execute(
        sa.text(
            """
            SELECT id, receipt_id
            FROM transactions
            WHERE category_id IS NULL
            """
        )
    ).all()
    if not tx_rows:
        return

    fallback_tx_category_id = tx_code_to_id["OTHER"]

    for tx_id, receipt_id in tx_rows:
        target_code: str | None = None

        if receipt_id is not None:
            target_code = conn.execute(
                sa.text(
                    """
                    SELECT UPPER(TRIM(structured_json ->> 'primary_category_code'))
                    FROM receipt_extractions
                    WHERE receipt_id = :receipt_id
                    LIMIT 1
                    """
                ),
                {"receipt_id": receipt_id},
            ).scalar_one_or_none()

        if not target_code or target_code not in tx_code_to_id:
            target_code = _derive_parent_code_for_transaction(conn, tx_id)

        target_id = tx_code_to_id.get(target_code or "", fallback_tx_category_id)
        conn.execute(
            sa.text("UPDATE transactions SET category_id = :category_id WHERE id = :tx_id"),
            {"category_id": target_id, "tx_id": tx_id},
        )


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column("categories", sa.Column("user_id", sa.Uuid(), nullable=True))
    op.add_column(
        "categories",
        sa.Column("is_custom", sa.Boolean(), nullable=False, server_default=sa.text("FALSE")),
    )
    op.create_index(op.f("ix_categories_user_id"), "categories", ["user_id"], unique=False)
    op.create_foreign_key(
        "fk_categories_user_id_users",
        "categories",
        "users",
        ["user_id"],
        ["id"],
    )

    op.drop_constraint("uq_categories_scope_code", "categories", type_="unique")
    op.create_index(
        "uq_categories_global_scope_code",
        "categories",
        ["scope", "code"],
        unique=True,
        postgresql_where=sa.text("user_id IS NULL"),
    )
    op.create_index(
        "uq_categories_user_scope_code",
        "categories",
        ["scope", "user_id", "code"],
        unique=True,
        postgresql_where=sa.text("user_id IS NOT NULL"),
    )
    op.create_index(
        "ix_categories_scope_user_code_active",
        "categories",
        ["scope", "user_id", "code", "is_active"],
        unique=False,
    )

    conn = op.get_bind()
    tx_code_to_id = _seed_taxonomy(conn)
    _backfill_transaction_categories(conn, tx_code_to_id)

    # Keep ORM default handling (no persistent DB-level default needed).
    op.alter_column("categories", "is_custom", server_default=None)


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index("ix_categories_scope_user_code_active", table_name="categories")
    op.drop_index("uq_categories_user_scope_code", table_name="categories")
    op.drop_index("uq_categories_global_scope_code", table_name="categories")
    op.create_unique_constraint("uq_categories_scope_code", "categories", ["scope", "code"])

    op.drop_constraint("fk_categories_user_id_users", "categories", type_="foreignkey")
    op.drop_index(op.f("ix_categories_user_id"), table_name="categories")
    op.drop_column("categories", "is_custom")
    op.drop_column("categories", "user_id")
