"""Hard-delete account data for an authenticated user."""

from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass, field
from typing import Any

from sqlalchemy import delete, false, or_, update
from sqlmodel import Session, select

from app.auth.firebase_admin import delete_firebase_user
from app.core.minio import delete_object
from app.models.billing.entitlement import Entitlement
from app.models.billing.subscription import Subscription
from app.models.billing.webhook_event import BillingWebhookEvent
from app.models.feature_requests.feature_request import FeatureRequest
from app.models.feature_requests.feature_request_vote import FeatureRequestVote
from app.models.households.household import Household
from app.models.households.household_invite import HouseholdInvite
from app.models.households.household_member import HouseholdMember
from app.models.labels.label import Label
from app.models.labels.transaction_label import TransactionLabel
from app.models.merchants.merchant import MerchantAlias
from app.models.overrides.user_category import (
    UserCategoryOverride,
    UserItemCategoryOverride,
)
from app.models.planning.bill_reminder import BillReminder
from app.models.planning.budget import BudgetCategoryLimit, BudgetSettings
from app.models.receipts.receipt import Receipt
from app.models.receipts.receipt_extraction import ReceiptExtraction
from app.models.shared.enums import EntitlementScopeType
from app.models.taxonomy.category import Category
from app.models.taxonomy.category_hidden import UserHiddenCategory
from app.models.transactions.transaction import Transaction
from app.models.transactions.transaction_item import TransactionItem
from app.models.translations.item_translation import ItemTranslation
from app.models.users.profile import Profile
from app.models.users.user import User

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class StoredReceiptObject:
    bucket: str
    key: str


@dataclass
class AccountDeletionResult:
    user_id: uuid.UUID
    auth_subject: str
    storage_delete_failures: list[StoredReceiptObject] = field(default_factory=list)
    firebase_user_deleted: bool = False


def _ids(session: Session, statement: Any) -> list[uuid.UUID]:
    return list(session.exec(statement).all())


def _values(session: Session, statement: Any) -> list[Any]:
    return list(session.exec(statement).all())


def _delete_by_ids(session: Session, model: type, ids: list[uuid.UUID]) -> None:
    if ids:
        session.exec(delete(model).where(model.id.in_(ids)))


def _in_or_false(column: Any, values: list[uuid.UUID]) -> Any:
    if not values:
        return false()
    return column.in_(values)


def _receipt_objects_for_user(session: Session, user_id: uuid.UUID) -> list[StoredReceiptObject]:
    rows = session.exec(
        select(Receipt.storage_bucket, Receipt.storage_key).where(Receipt.user_id == user_id)
    ).all()
    return [
        StoredReceiptObject(bucket=row[0], key=row[1])
        for row in rows
        if row[0] and row[1]
    ]


def _delete_receipt_objects_best_effort(
    receipt_objects: list[StoredReceiptObject],
) -> list[StoredReceiptObject]:
    failures: list[StoredReceiptObject] = []
    for receipt_object in receipt_objects:
        try:
            delete_object(receipt_object.key, bucket=receipt_object.bucket)
        except Exception:
            logger.warning(
                "Failed to delete receipt object during account deletion: bucket=%s key=%s",
                receipt_object.bucket,
                receipt_object.key,
                exc_info=True,
            )
            failures.append(receipt_object)
    return failures


def delete_account_for_user(*, session: Session, user: User) -> AccountDeletionResult:
    """Hard-delete local account data and best-effort external resources."""

    user_id = user.id
    auth_subject = user.auth_subject
    receipt_objects = _receipt_objects_for_user(session, user_id)
    receipt_ids = _ids(session, select(Receipt.id).where(Receipt.user_id == user_id))
    custom_category_ids = _ids(session, select(Category.id).where(Category.user_id == user_id))
    label_ids = _ids(session, select(Label.id).where(Label.user_id == user_id))
    budget_settings_ids = _ids(
        session,
        select(BudgetSettings.id).where(BudgetSettings.user_id == user_id),
    )
    subscription_ids = _ids(session, select(Subscription.id).where(Subscription.user_id == user_id))
    owned_household_ids = _ids(
        session,
        select(Household.id).where(Household.owner_user_id == user_id),
    )
    feature_request_ids = _ids(
        session,
        select(FeatureRequest.id).where(FeatureRequest.creator_user_id == user_id),
    )
    transaction_ids = _ids(
        session,
        select(Transaction.id).where(
            or_(
                Transaction.user_id == user_id,
                Transaction.created_by_user_id == user_id,
                Transaction.owner_user_id == user_id,
                _in_or_false(Transaction.receipt_id, receipt_ids),
            )
        ),
    )

    webhook_app_user_ids = {
        value
        for value in _values(
            session,
            select(Subscription.external_customer_id).where(Subscription.user_id == user_id),
        )
        if value
    }
    if auth_subject:
        webhook_app_user_ids.add(auth_subject)

    if webhook_app_user_ids:
        session.exec(
            update(BillingWebhookEvent)
            .where(BillingWebhookEvent.app_user_id.in_(webhook_app_user_ids))
            .values(app_user_id=None)
        )

    if feature_request_ids:
        session.exec(
            delete(FeatureRequestVote).where(
                FeatureRequestVote.feature_request_id.in_(feature_request_ids)
            )
        )
    session.exec(delete(FeatureRequestVote).where(FeatureRequestVote.user_id == user_id))
    session.exec(
        update(FeatureRequest)
        .where(FeatureRequest.reviewed_by_user_id == user_id)
        .values(reviewed_by_user_id=None)
    )
    session.exec(delete(FeatureRequest).where(FeatureRequest.creator_user_id == user_id))

    if owned_household_ids:
        session.exec(
            update(Transaction)
            .where(Transaction.household_id.in_(owned_household_ids))
            .values(household_id=None)
        )
        session.exec(
            delete(Entitlement).where(
                Entitlement.scope_type == EntitlementScopeType.HOUSEHOLD,
                Entitlement.scope_id.in_(owned_household_ids),
            )
        )
        session.exec(
            delete(HouseholdInvite).where(HouseholdInvite.household_id.in_(owned_household_ids))
        )
        session.exec(
            delete(HouseholdMember).where(HouseholdMember.household_id.in_(owned_household_ids))
        )
    session.exec(
        delete(HouseholdInvite).where(
            or_(
                HouseholdInvite.invited_by_user_id == user_id,
                HouseholdInvite.invited_user_id == user_id,
            )
        )
    )
    session.exec(delete(HouseholdMember).where(HouseholdMember.user_id == user_id))
    session.exec(delete(Household).where(Household.owner_user_id == user_id))

    if subscription_ids:
        session.exec(
            delete(Entitlement).where(Entitlement.source_subscription_id.in_(subscription_ids))
        )
    session.exec(
        delete(Entitlement).where(
            Entitlement.scope_type == EntitlementScopeType.USER,
            Entitlement.scope_id == user_id,
        )
    )
    session.exec(delete(Subscription).where(Subscription.user_id == user_id))

    if transaction_ids:
        session.exec(
            delete(TransactionLabel).where(TransactionLabel.transaction_id.in_(transaction_ids))
        )
        session.exec(
            delete(TransactionItem).where(TransactionItem.transaction_id.in_(transaction_ids))
        )
    if label_ids:
        session.exec(delete(TransactionLabel).where(TransactionLabel.label_id.in_(label_ids)))
    if custom_category_ids:
        session.exec(
            delete(TransactionItem).where(TransactionItem.category_id.in_(custom_category_ids))
        )
        session.exec(
            update(Transaction)
            .where(Transaction.category_id.in_(custom_category_ids))
            .values(category_id=None)
        )
    _delete_by_ids(session, Transaction, transaction_ids)

    if receipt_ids:
        session.exec(delete(ReceiptExtraction).where(ReceiptExtraction.receipt_id.in_(receipt_ids)))
    _delete_by_ids(session, Receipt, receipt_ids)

    if budget_settings_ids:
        session.exec(
            delete(BudgetCategoryLimit).where(
                BudgetCategoryLimit.budget_settings_id.in_(budget_settings_ids)
            )
        )
    if custom_category_ids:
        session.exec(
            delete(BudgetCategoryLimit).where(
                BudgetCategoryLimit.category_id.in_(custom_category_ids)
            )
        )
        session.exec(
            delete(UserCategoryOverride).where(
                UserCategoryOverride.category_id.in_(custom_category_ids)
            )
        )
        session.exec(
            delete(UserItemCategoryOverride).where(
                UserItemCategoryOverride.category_id.in_(custom_category_ids)
            )
        )
        session.exec(
            delete(UserHiddenCategory).where(
                UserHiddenCategory.category_id.in_(custom_category_ids)
            )
        )
        session.exec(
            update(Category)
            .where(Category.user_id == user_id)
            .values(parent_id=None)
        )
    session.exec(delete(UserCategoryOverride).where(UserCategoryOverride.user_id == user_id))
    session.exec(delete(UserItemCategoryOverride).where(UserItemCategoryOverride.user_id == user_id))
    session.exec(delete(BudgetSettings).where(BudgetSettings.user_id == user_id))
    session.exec(delete(BillReminder).where(BillReminder.user_id == user_id))
    session.exec(delete(ItemTranslation).where(ItemTranslation.user_id == user_id))
    session.exec(delete(MerchantAlias).where(MerchantAlias.user_id == user_id))
    session.exec(delete(UserHiddenCategory).where(UserHiddenCategory.user_id == user_id))
    session.exec(delete(Label).where(Label.user_id == user_id))
    session.exec(delete(Category).where(Category.user_id == user_id))
    session.exec(delete(Profile).where(Profile.user_id == user_id))
    session.exec(delete(User).where(User.id == user_id))
    session.commit()

    storage_delete_failures = _delete_receipt_objects_best_effort(receipt_objects)
    firebase_user_deleted = delete_firebase_user(auth_subject)
    if not firebase_user_deleted:
        logger.warning(
            "Firebase user was not deleted during account deletion: user_id=%s auth_subject=%s",
            user_id,
            auth_subject,
        )

    return AccountDeletionResult(
        user_id=user_id,
        auth_subject=auth_subject,
        storage_delete_failures=storage_delete_failures,
        firebase_user_deleted=firebase_user_deleted,
    )
