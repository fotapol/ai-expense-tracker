"""Transaction API router facade."""

from fastapi import APIRouter

from app.api.routers.transactions_analytics import router as analytics_router
from app.api.routers.transactions_crud import router as crud_router

router = APIRouter()
# Register the static analytics paths before the dynamic
# ``/transactions/{transaction_id}`` CRUD path. Starlette resolves routes in
# declaration order, so putting CRUD first makes ``/transactions/summary``
# match the transaction detail route and fail UUID validation with a 422.
router.include_router(analytics_router)
router.include_router(crud_router)
