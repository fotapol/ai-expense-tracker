"""Application-level rate limiting via slowapi + Redis.

This protects against API abuse (brute-force, scraping), NOT DDoS.
For DDoS protection use a reverse proxy or CDN (Cloudflare, AWS WAF, nginx).
"""

import logging

from slowapi import Limiter
from slowapi.util import get_remote_address

from app.core.config import redis_settings

logger = logging.getLogger(__name__)

# slowapi uses the `limits` library under the hood, which accepts
# Redis URIs directly for distributed rate limit state.
limiter = Limiter(
    key_func=get_remote_address,
    storage_uri=redis_settings.REDIS_URL,
    default_limits=["60/minute"],
    strategy="fixed-window",
)
