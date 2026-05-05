"""Prometheus metrics helpers for API, worker, and billing observability."""

from __future__ import annotations

import time
from typing import Final

from fastapi import FastAPI, Request, Response
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
    start_http_server,
)
from starlette.middleware.base import BaseHTTPMiddleware

from app.core.config import observability_settings

_METRIC_NAMESPACE: Final = "expense_tracker"

HTTP_REQUESTS_TOTAL = Counter(
    f"{_METRIC_NAMESPACE}_http_requests_total",
    "Total HTTP requests served by the API.",
    labelnames=("method", "path", "status_code"),
)
HTTP_REQUEST_DURATION_SECONDS = Histogram(
    f"{_METRIC_NAMESPACE}_http_request_duration_seconds",
    "HTTP request latency in seconds.",
    labelnames=("method", "path", "status_code"),
    buckets=(0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30),
)
API_DEPENDENCY_UP = Gauge(
    f"{_METRIC_NAMESPACE}_api_dependency_up",
    "Dependency health reported by the API readiness checks.",
    labelnames=("dependency",),
)
WORKER_DEPENDENCY_UP = Gauge(
    f"{_METRIC_NAMESPACE}_worker_dependency_up",
    "Dependency health reported by the worker process.",
    labelnames=("dependency",),
)
WORKER_JOBS_STARTED_TOTAL = Counter(
    f"{_METRIC_NAMESPACE}_worker_jobs_started_total",
    "Receipt worker jobs started.",
)
WORKER_JOBS_COMPLETED_TOTAL = Counter(
    f"{_METRIC_NAMESPACE}_worker_jobs_completed_total",
    "Receipt worker jobs completed successfully.",
)
WORKER_JOBS_FAILED_TOTAL = Counter(
    f"{_METRIC_NAMESPACE}_worker_jobs_failed_total",
    "Receipt worker job failures.",
    labelnames=("reason",),
)
WORKER_JOB_RETRIES_TOTAL = Counter(
    f"{_METRIC_NAMESPACE}_worker_job_retries_total",
    "Receipt worker retries scheduled after a failed attempt.",
)
WORKER_JOBS_IN_PROGRESS = Gauge(
    f"{_METRIC_NAMESPACE}_worker_jobs_in_progress",
    "Receipt worker jobs currently being processed.",
)
WORKER_PROCESSING_DURATION_SECONDS = Histogram(
    f"{_METRIC_NAMESPACE}_worker_processing_duration_seconds",
    "End-to-end receipt processing duration in seconds.",
    buckets=(0.5, 1, 2.5, 5, 10, 20, 30, 60, 120),
)
RECEIPT_EXTRACTION_TOTAL = Counter(
    f"{_METRIC_NAMESPACE}_receipt_extraction_total",
    "AI extraction attempts by provider/model and result.",
    labelnames=("provider", "model", "result"),
)
RECEIPT_EXTRACTION_DURATION_SECONDS = Histogram(
    f"{_METRIC_NAMESPACE}_receipt_extraction_duration_seconds",
    "Receipt AI extraction latency in seconds.",
    labelnames=("provider", "model", "result"),
    buckets=(0.25, 0.5, 1, 2.5, 5, 10, 20, 30, 60),
)
RECEIPT_EXTRACTION_ITEMS = Histogram(
    f"{_METRIC_NAMESPACE}_receipt_extraction_items",
    "Number of line items emitted by the receipt extraction model.",
    buckets=(0, 1, 3, 5, 10, 20, 40, 80),
)
RECEIPT_LAST_SUCCESS_UNIX = Gauge(
    f"{_METRIC_NAMESPACE}_receipt_last_success_unixtime",
    "Unix timestamp of the last successful receipt processing run.",
)
REVENUECAT_WEBHOOK_EVENTS_TOTAL = Counter(
    f"{_METRIC_NAMESPACE}_revenuecat_webhook_events_total",
    "RevenueCat webhook events by type and outcome.",
    labelnames=("event_type", "outcome"),
)

_worker_metrics_started = False


def metrics_enabled() -> bool:
    return observability_settings.METRICS_ENABLED


def _normalize_path_label(request: Request) -> str:
    route = request.scope.get("route")
    route_path = getattr(route, "path", None)
    if isinstance(route_path, str) and route_path:
        return route_path
    return request.url.path or "unknown"


class HTTPMetricsMiddleware(BaseHTTPMiddleware):
    """Collect low-cardinality request metrics for the public API."""

    async def dispatch(self, request: Request, call_next):
        start = time.perf_counter()
        status_code = 500
        response = None
        try:
            response = await call_next(request)
            status_code = response.status_code
        finally:
            if metrics_enabled():
                duration = time.perf_counter() - start
                labels = {
                    "method": request.method,
                    "path": _normalize_path_label(request),
                    "status_code": str(status_code),
                }
                HTTP_REQUESTS_TOTAL.labels(**labels).inc()
                HTTP_REQUEST_DURATION_SECONDS.labels(**labels).observe(duration)
        return response


def install_metrics(app: FastAPI) -> None:
    """Attach metrics middleware and a Prometheus scrape endpoint."""

    if not metrics_enabled():
        return

    app.add_middleware(HTTPMetricsMiddleware)

    @app.get(observability_settings.METRICS_API_PATH, include_in_schema=False)
    async def _metrics_endpoint() -> Response:
        return Response(
            content=generate_latest(),
            media_type=CONTENT_TYPE_LATEST,
        )


def start_worker_metrics_server() -> None:
    """Expose worker metrics on an internal-only HTTP port."""

    global _worker_metrics_started
    if _worker_metrics_started or not metrics_enabled():
        return
    start_http_server(observability_settings.WORKER_METRICS_PORT, addr="0.0.0.0")
    _worker_metrics_started = True


def set_api_dependency_health(*, dependency: str, is_up: bool) -> None:
    API_DEPENDENCY_UP.labels(dependency=dependency).set(1 if is_up else 0)


def set_worker_dependency_health(*, dependency: str, is_up: bool) -> None:
    WORKER_DEPENDENCY_UP.labels(dependency=dependency).set(1 if is_up else 0)


def record_worker_job_started() -> None:
    WORKER_JOBS_STARTED_TOTAL.inc()
    WORKER_JOBS_IN_PROGRESS.inc()


def record_worker_job_completed(*, duration_seconds: float) -> None:
    WORKER_JOBS_COMPLETED_TOTAL.inc()
    WORKER_JOBS_IN_PROGRESS.dec()
    WORKER_PROCESSING_DURATION_SECONDS.observe(duration_seconds)
    RECEIPT_LAST_SUCCESS_UNIX.set(time.time())


def record_worker_job_failed(*, reason: str, duration_seconds: float | None = None) -> None:
    WORKER_JOBS_FAILED_TOTAL.labels(reason=reason).inc()
    WORKER_JOBS_IN_PROGRESS.dec()
    if duration_seconds is not None:
        WORKER_PROCESSING_DURATION_SECONDS.observe(duration_seconds)


def record_worker_retry_scheduled() -> None:
    WORKER_JOB_RETRIES_TOTAL.inc()


def record_receipt_extraction(
    *,
    provider: str,
    model: str,
    success: bool,
    latency_ms: int,
    item_count: int | None = None,
) -> None:
    labels = {
        "provider": provider,
        "model": model,
        "result": "success" if success else "failure",
    }
    RECEIPT_EXTRACTION_TOTAL.labels(**labels).inc()
    RECEIPT_EXTRACTION_DURATION_SECONDS.labels(**labels).observe(latency_ms / 1000)
    if item_count is not None:
        RECEIPT_EXTRACTION_ITEMS.observe(item_count)


def record_revenuecat_webhook_event(*, event_type: str, outcome: str) -> None:
    REVENUECAT_WEBHOOK_EVENTS_TOTAL.labels(
        event_type=event_type or "unknown",
        outcome=outcome,
    ).inc()
