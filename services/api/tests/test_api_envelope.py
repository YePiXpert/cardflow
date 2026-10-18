"""Error envelope (404/405/422/500/ApiError) and access-log behaviour."""

import json
import logging
from collections.abc import AsyncIterator, Iterator

import httpx
import pytest
from fastapi import APIRouter, FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from fastapi.testclient import TestClient

from cardflow.api.errors import ApiError, ErrorCode
from cardflow.log import JsonFormatter

ENVELOPE_KEYS = {"code", "message", "details", "request_id"}
ACCESS_LOG_KEYS = {
    "ts",
    "level",
    "logger",
    "message",
    "request_id",
    "method",
    "path",
    "status",
    "duration_ms",
}


def envelope(response: httpx.Response) -> dict[str, object]:
    """Assert the envelope shape and return ``body["error"]``."""
    body = response.json()
    assert list(body) == ["error"]
    error = body["error"]
    assert set(error) == ENVELOPE_KEYS
    assert error["request_id"] == response.headers["x-request-id"]
    assert response.headers.get_list("x-request-id") == [error["request_id"]]
    return error


@pytest.fixture
def probe_client(app: FastAPI) -> Iterator[TestClient]:
    """Client for an app extended with test-only routes covering every error path."""

    @app.get("/_probe/items/{item_id}")
    async def get_item(item_id: int) -> dict[str, int]:
        return {"item_id": item_id}

    @app.get("/_probe/boom")
    async def boom() -> None:
        raise RuntimeError("secret-detail-4411")

    @app.get("/_probe/conflict")
    async def conflict() -> None:
        raise ApiError(
            409, ErrorCode.VERSION_CONFLICT, "Row version mismatch", details={"row_version": 3}
        )

    @app.get("/_probe/forbidden")
    async def forbidden() -> None:
        raise HTTPException(status_code=403)

    router = APIRouter()

    @router.get("/things/{thing_id}")
    async def get_thing(thing_id: str) -> dict[str, str]:
        return {"thing_id": thing_id}

    app.include_router(router, prefix="/v1")
    with TestClient(app) as client:
        yield client


def access_records(caplog: pytest.LogCaptureFixture) -> list[logging.LogRecord]:
    return [record for record in caplog.records if record.name == "cardflow.access"]


def test_method_not_allowed(client: TestClient) -> None:
    response = client.post("/healthz")

    assert response.status_code == 405
    error = envelope(response)
    assert error["code"] == "METHOD_NOT_ALLOWED"
    assert "GET" in response.headers["allow"]


def test_validation_error_does_not_echo_input(probe_client: TestClient) -> None:
    response = probe_client.get("/_probe/items/not-a-number-77")

    assert response.status_code == 422
    error = envelope(response)
    assert error["code"] == "VALIDATION_ERROR"
    assert error["message"] == "Request validation failed"
    details = error["details"]
    assert isinstance(details, dict)
    [item] = details["errors"]
    assert item["loc"] == ["path", "item_id"]
    assert item["type"] == "int_parsing"
    assert set(item) == {"loc", "type", "msg"}
    assert "not-a-number-77" not in response.text


def test_unexpected_exception_is_internal_error_without_details(
    probe_client: TestClient, caplog: pytest.LogCaptureFixture
) -> None:
    caplog.set_level(logging.INFO)

    response = probe_client.get("/_probe/boom")

    assert response.status_code == 500
    error = envelope(response)
    assert error["code"] == "INTERNAL_ERROR"
    assert error["message"] == "Internal server error"
    assert error["details"] == {}
    assert "secret-detail-4411" not in response.text
    [logged] = [r for r in caplog.records if r.getMessage() == "unhandled_exception"]
    assert logged.request_id == error["request_id"]
    line = JsonFormatter().format(logged)
    assert json.loads(line)["exc_type"] == "RuntimeError"
    assert "secret-detail-4411" not in line
    [access] = access_records(caplog)
    assert access.status == 500
    assert access.path == "/_probe/boom"


def test_failure_after_response_start_is_logged_once_with_request_id(
    app: FastAPI, caplog: pytest.LogCaptureFixture
) -> None:
    async def chunks() -> AsyncIterator[bytes]:
        yield b"partial"
        raise RuntimeError("stream-detail-9")

    @app.get("/_probe/stream")
    async def stream() -> StreamingResponse:
        return StreamingResponse(chunks())

    caplog.set_level(logging.INFO)
    with TestClient(app, raise_server_exceptions=False) as client:
        response = client.get("/_probe/stream")

    assert response.status_code == 200  # headers were already sent
    [logged] = [r for r in caplog.records if r.getMessage() == "unhandled_exception"]
    assert logged.request_id == response.headers["x-request-id"]
    assert "stream-detail-9" not in JsonFormatter().format(logged)
    [access] = access_records(caplog)
    assert (access.status, access.path) == (200, "/_probe/stream")


def test_api_error_carries_contract_code_and_details(probe_client: TestClient) -> None:
    response = probe_client.get("/_probe/conflict")

    assert response.status_code == 409
    error = envelope(response)
    assert error["code"] == "VERSION_CONFLICT"
    assert error["message"] == "Row version mismatch"
    assert error["details"] == {"row_version": 3}


def test_http_exception_status_maps_to_contract_code(probe_client: TestClient) -> None:
    response = probe_client.get("/_probe/forbidden")

    assert response.status_code == 403
    error = envelope(response)
    assert error["code"] == "FORBIDDEN"
    assert error["message"] == "Forbidden"


def test_request_ids_are_unique(client: TestClient) -> None:
    ids = {client.get("/healthz").headers["x-request-id"] for _ in range(5)}
    assert len(ids) == 5


def test_access_log_has_route_template_and_whitelisted_fields_only(
    probe_client: TestClient, caplog: pytest.LogCaptureFixture
) -> None:
    caplog.set_level(logging.INFO, logger="cardflow.access")

    response = probe_client.get(
        "/_probe/items/987654321?token=supersecret-q", headers={"Authorization": "Bearer tok-x"}
    )

    assert response.status_code == 200
    [record] = access_records(caplog)
    line = JsonFormatter().format(record)
    fields = json.loads(line)
    assert set(fields) == ACCESS_LOG_KEYS
    assert fields["method"] == "GET"
    assert fields["path"] == "/_probe/items/{item_id}"
    assert fields["status"] == 200
    assert fields["request_id"] == response.headers["x-request-id"]
    assert isinstance(fields["duration_ms"], float)
    for leaked in ("987654321", "supersecret-q", "token", "tok-x", "Bearer"):
        assert leaked not in line


def test_access_log_includes_router_prefix(
    probe_client: TestClient, caplog: pytest.LogCaptureFixture
) -> None:
    caplog.set_level(logging.INFO, logger="cardflow.access")

    assert probe_client.get("/v1/things/abc-123").status_code == 200

    [record] = access_records(caplog)
    assert record.path == "/v1/things/{thing_id}"


def test_access_log_for_unmatched_route_hides_raw_path(
    client: TestClient, caplog: pytest.LogCaptureFixture
) -> None:
    caplog.set_level(logging.INFO, logger="cardflow.access")

    assert client.get("/nope/raw-segment-55").status_code == 404

    [record] = access_records(caplog)
    assert record.path == "<unmatched>"
    assert record.status == 404
    assert "raw-segment-55" not in JsonFormatter().format(record)


def test_access_log_for_wrong_method_uses_template(
    client: TestClient, caplog: pytest.LogCaptureFixture
) -> None:
    caplog.set_level(logging.INFO, logger="cardflow.access")

    assert client.delete("/healthz").status_code == 405

    [record] = access_records(caplog)
    assert record.path == "/healthz"
    assert record.status == 405
