"""Feature request ORM models."""

from app.models.feature_requests.feature_request import FeatureRequest, FeatureRequestBase
from app.models.feature_requests.feature_request_vote import FeatureRequestVote

__all__ = [
    "FeatureRequest",
    "FeatureRequestBase",
    "FeatureRequestVote",
]
