"""T-002 smoke tests: liveness, error envelope, secret files, workspace transaction."""

import re
import uuid
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import text
from sqlalchemy.engine import URL
from sqlalchemy.pool import StaticPool

from cardflow.db import create_engine, create_session_factory, workspace_tx
from cardflow.settings import Settings

REQUEST_ID = re.compile(r"[0-9a-f]{32}")


def test_healthz_returns_ok(client: TestClient) -> None:
    response = client.get("/healthz")

    assert response.status_code == 200
    assert response.headers["content-type"] == "application/json"
    assert response.json() == {"status": "ok"}
    assert REQUEST_ID.fullmatch(response.headers["x-request-id"])


def test_unknown_route_returns_error_envelope_with_request_id(client: TestClient) -> None:
    response = client.get("/no-such-route")

    assert response.status_code == 404
    body = response.json()
    assert list(body) == ["error"]
    assert set(body["error"]) == {"code", "message", "details", "request_id"}
    assert body["error"]["code"] == "NOT_FOUND"
    assert body["error"]["details"] == {}
    assert REQUEST_ID.fullmatch(body["error"]["request_id"])
    assert body["error"]["request_id"] == response.headers["x-request-id"]


def test_settings_read_secret_files_without_leaking(
    tmp_path: Path, clean_settings_env: pytest.MonkeyPatch
) -> None:
    secrets = {
        "DATABASE_PASSWORD": "db-pw-7f3a9c",
        "JWT_KEY": "jwt-key-41d2e8",
        "KEK": "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=",  # base64 of 32 bytes
    }
    for name, value in secrets.items():
        path = tmp_path / name.lower()
        path.write_text(value + "\n", encoding="utf-8")  # trailing newline is stripped
        clean_settings_env.setenv(f"{name}_FILE", str(path))

    settings = Settings()

    assert settings.database_password is not None
    assert settings.jwt_key is not None
    assert settings.kek is not None
    assert settings.database_password.get_secret_value() == secrets["DATABASE_PASSWORD"]
    assert settings.jwt_key.get_secret_value() == secrets["JWT_KEY"]
    assert settings.kek.get_secret_value() == secrets["KEK"]
    rendered = " ".join([repr(settings), str(settings), settings.model_dump_json()])
    for value in secrets.values():
        assert value not in rendered


@pytest.mark.db
def test_workspace_tx_binds_workspace_for_one_transaction_only(test_database_url: URL) -> None:
    # StaticPool = exactly one physical connection, so the second transaction provably
    # runs on the same PostgreSQL backend as the first one.
    engine = create_engine(test_database_url, poolclass=StaticPool)
    session_factory = create_session_factory(engine)
    workspace_id = uuid.uuid4()
    query = text("SELECT current_setting('app.workspace_id', true), pg_backend_pid()")
    try:
        with workspace_tx(session_factory, workspace_id) as session:
            bound, backend_pid = session.execute(query).one()
            assert bound == str(workspace_id)

        with session_factory() as session:
            after, backend_pid_after = session.execute(query).one()
    finally:
        engine.dispose()

    assert backend_pid_after == backend_pid
    assert after in (None, "")  # '' once the GUC was ever set on this backend
