"""Transaction API router facade."""

from fastapi import APIRouter

from app.api.routers.transactions_analytics import router as analytics_router
from app.api.routers.transactions_crud import router as crud_router

router = APIRouter()
router.include_router(crud_router)
router.include_router(analytics_router)
