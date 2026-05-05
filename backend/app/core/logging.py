"""Logging helpers for API and worker processes."""

from __future__ import annotations

import json
import logging
import sys
import time
import uuid
from collections.abc import Mapping
from datetime import UTC, datetime
from typing import Any, Final

from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware

from app.core.config import observability_settings

_RESERVED_FIELDS: Final = {
    "args",
    "asctime",
    "created",
    "exc_info",
    "exc_text",
    "filename",
    "funcName",
    "levelname",
    "levelno",
    "lineno",
    "module",
    "msecs",
    "message",
    "msg",
    "name",
    "pathname",
    "process",
    "processName",
    "relativeCreated",
    "stack_info",
    "thread",
    "threadName",
}


def _parse_log_level() -> int:
    raw_level = observability_settings.LOG_LEVEL.upper()
    return getattr(logging, raw_level, logging.INFO)


def _json_safe(value: Any) -> Any:
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    if isinstance(value, datetime):
        return value.astimezone(UTC).isoformat()
    if isinstance(value, Mapping):
        return {str(key): _json_safe(inner) for key, inner in value.items()}
    if isinstance(value, (list, tuple, set, frozenset)):
        return [_json_safe(item) for item in value]
    return str(value)


class JsonLogFormatter(logging.Formatter):
    """Render structured log records as single-line JSON."""

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "timestamp": datetime.fromtimestamp(record.created, UTC).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "service": getattr(record, "service", None),
        }
        for key, value in record.__dict__.items():
            if key in _RESERVED_FIELDS or key.startswith("_"):
                continue
            if key == "service" and value is None:
                continue
            payload[key] = _json_safe(value)
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, separators=(",", ":"), ensure_ascii=True)


def configure_logging(*, service_name: str) -> None:
    """Configure root logging once per process."""

    root_logger = logging.getLogger()
    desired_level = _parse_log_level()
    if getattr(root_logger, "_expense_tracker_configured", False):
        root_logger.setLevel(desired_level)
        return

    handler = logging.StreamHandler(sys.stdout)
    if observability_settings.LOG_JSON:
        handler.setFormatter(JsonLogFormatter())
    else:
        handler.setFormatter(
            logging.Formatter(
                fmt="%(asctime)s %(levelname)s %(name)s [%(service)s]: %(message)s",
                defaults={"service": service_name},
            )
        )

    root_logger.handlers.clear()
    root_logger.addHandler(handler)
    root_logger.setLevel(desired_level)
    root_logger._expense_tracker_configured = True  # type: ignore[attr-defined]

    for logger_name in ("uvicorn", "uvicorn.access", "uvicorn.error"):
        logging.getLogger(logger_name).setLevel(desired_level)
        logging.getLogger(logger_name).handlers.clear()
        logging.getLogger(logger_name).propagate = True


def _request_client_ip(request: Request) -> str | None:
    candidate = (
        request.headers.get("cf-connecting-ip")
        or request.headers.get("x-forwarded-for")
        or request.headers.get("x-real-ip")
    )
    if candidate:
        return candidate.split(",")[0].strip()
    if request.client is not None:
        return request.client.host
    return None


def _proxy_diagnostics(request: Request) -> dict[str, str | None]:
    if not observability_settings.PROXY_DIAGNOSTICS_ENABLED:
        return {}

    return {
        "proxy_host": request.headers.get("host"),
        "proxy_forwarded_host": request.headers.get("x-forwarded-host"),
        "proxy_forwarded_proto": request.headers.get("x-forwarded-proto"),
        "proxy_cf_connecting_ip": request.headers.get("cf-connecting-ip"),
        "proxy_x_forwarded_for": request.headers.get("x-forwarded-for"),
        "proxy_socket_client_host": (
            request.client.host if request.client is not None else None
        ),
    }


logger = logging.getLogger(__name__)


class BackendLoggingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        start_time = time.perf_counter()
        request_id = str(uuid.uuid4())
        request.state.request_id = request_id

        try:
            response = await call_next(request)
            duration_ms = round((time.perf_counter() - start_time) * 1000, 2)
            logger.info(
                "HTTP request completed.",
                extra={
                    "service": "api",
                    "event": "http_request",
                    "request_id": request_id,
                    "method": request.method,
                    "path": request.url.path,
                    "status_code": response.status_code,
                    "duration_ms": duration_ms,
                    "client_ip": _request_client_ip(request),
                    **_proxy_diagnostics(request),
                },
            )
            response.headers["X-Request-ID"] = request_id
            return response
        except Exception:
            duration_ms = round((time.perf_counter() - start_time) * 1000, 2)
            logger.exception(
                "Unhandled exception during request.",
                extra={
                    "service": "api",
                    "event": "http_request_error",
                    "request_id": request_id,
                    "method": request.method,
                    "path": request.url.path,
                    "duration_ms": duration_ms,
                    "client_ip": _request_client_ip(request),
                    **_proxy_diagnostics(request),
                },
            )
            raise
