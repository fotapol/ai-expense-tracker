"""Application-level rate limiting via slowapi + Redis.

This protects against API abuse (brute-force, scraping), NOT DDoS.
For DDoS protection use a reverse proxy or CDN (Cloudflare, AWS WAF, nginx).
"""

import logging
import os

from slowapi import Limiter
from slowapi.util import get_remote_address

logger = logging.getLogger(__name__)

REDIS_URL: str = os.environ.get("REDIS_URL", "redis://redis:6379/0")

# slowapi uses the `limits` library under the hood, which accepts
# Redis URIs directly for distributed rate limit state.
limiter = Limiter(
    key_func=get_remote_address,
    storage_uri=REDIS_URL,
    default_limits=["60/minute"],
    strategy="fixed-window",
)
