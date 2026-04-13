"""Backend request logging middleware."""

import logging
import time
import uuid

from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.types import Message

logger = logging.getLogger(__name__)

class BackendLoggingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        start_time = time.time()
        request_id = str(uuid.uuid4())
        
        # We inject correlation ID for traceability but attach to state if needed later
        request.state.request_id = request_id
        
        # Basic context logger adapter to include request_id prefix
        prefix = f"[{request_id}]"

        try:
            response = await call_next(request)
            process_time = time.time() - start_time
            logger.info(
                "%s %s %s %d - %.3fs",
                prefix,
                request.method,
                request.url.path,
                response.status_code,
                process_time,
            )
            response.headers["X-Request-ID"] = request_id
            return response
        except Exception:
            process_time = time.time() - start_time
            logger.error(
                "%s %s %s 500 - %.3fs",
                prefix,
                request.method,
                request.url.path,
                process_time,
            )
            raise
