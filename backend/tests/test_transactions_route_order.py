"""Regression tests for transaction route precedence."""

from starlette.routing import Match

from app.main import app


def _first_full_match(path: str, method: str = "GET") -> str | None:
    scope = {
        "type": "http",
        "path": path,
        "root_path": "",
        "method": method,
    }
    for route in app.routes:
        match, _ = route.matches(scope)
        if match is Match.FULL:
            return route.path
    return None


def test_transaction_summary_is_not_captured_as_transaction_id() -> None:
    """Static analytics paths must win over the dynamic detail route."""

    assert _first_full_match("/v1/transactions/summary") == "/v1/transactions/summary"


def test_nested_transaction_summary_is_not_captured_as_transaction_id() -> None:
    """Nested analytics paths must remain reachable after router changes."""

    assert (
        _first_full_match("/v1/transactions/summary/trends")
        == "/v1/transactions/summary/trends"
    )
