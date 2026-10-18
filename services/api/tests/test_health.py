"""T-012: ``/readyz`` (database, migration head, worker heartbeat, attachment volume) and the
API docs switch.

The application under test runs as the app login role (``database_logins["app"]``, shaped like
``cardflow_api``); worker heartbeats are written by the worker role (``worker_engine``) with
the production ``upsert_heartbeat``. ``worker_heartbeats`` is a global table of the shared
session database, so every DB test starts and ends without heartbeat rows (as tests/jobs do).
"""

import asyncio
import logging
import socket
import threading
import time
from collections.abc import Callable, Iterator
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Final

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import text
from sqlalchemy.engine import URL, Engine

from cardflow.api.app import create_app
from cardflow.api.routes import health
from cardflow.db import create_session_factory
from cardflow.db.migrations import alembic_config, head_revisions
from cardflow.jobs.queue import WorkerIdentity, upsert_heartbeat
from cardflow.settings import Settings

VERSION: Final = "9.9.9-t012"
HEAD: Final = ",".join(head_revisions())
ALL_OK: Final = {"database": True, "migrations": True, "worker": True, "attachments": True}
READYZ_BUDGET_S: Final = 3.0
"""The brief's upper bound for one /readyz answer."""


class Login:
    """The app login of the session (``database_logins["app"]``) and its URL parts."""

    def __init__(self, database_logins: dict[str, Any], database: URL) -> None:
        self.login = database_logins["app"]
        url = self.login.url(database)
        without_password = URL.create(
            url.drivername, url.username, None, url.host, url.port, url.database
        )
        self.url_without_password = without_password.render_as_string(hide_password=False)
        self.password: str = url.password or ""
        self.host = url.host or ""
        self.port = str(url.port or "")
        self.database = url.database or ""


@pytest.fixture
def app_login(database_logins: dict[str, Any], test_database_url: URL) -> Login:
    return Login(database_logins, test_database_url)


@pytest.fixture
def attachments(tmp_path: Path) -> Path:
    directory = tmp_path / "attachments"
    directory.mkdir()
    return directory


def _settings(login: Login, attachments: Path, **overrides: object) -> Settings:
    values: dict[str, object] = {
        "database_url": login.url_without_password,
        "database_password": login.password,
        "attachments_dir": attachments,
        "cardflow_version": VERSION,
    }
    values.update(overrides)
    return Settings(**values)  # type: ignore[arg-type]


@pytest.fixture
def make_client(
    clean_settings_env: pytest.MonkeyPatch,
) -> Iterator[Callable[[Settings], TestClient]]:
    del clean_settings_env
    clients: list[TestClient] = []

    def make(settings: Settings) -> TestClient:
        client = TestClient(create_app(settings))
        client.__enter__()
        clients.append(client)
        return client

    yield make
    for client in clients:
        client.__exit__(None, None, None)


def _delete_heartbeats(db_engine: Engine) -> None:
    with db_engine.begin() as connection:
        connection.execute(text("DELETE FROM worker_heartbeats"))


@pytest.fixture
def no_heartbeats(db_engine: Engine) -> Iterator[None]:
    _delete_heartbeats(db_engine)
    yield
    _delete_heartbeats(db_engine)


@pytest.fixture
def beat(worker_engine: Engine, no_heartbeats: None) -> Callable[..., str]:
    """Write (or refresh) a worker heartbeat as the worker role; optionally age it."""
    del no_heartbeats
    factory = create_session_factory(worker_engine)

    def write(worker_id: str = "t012-readyz", *, age_s: float | None = None) -> str:
        identity = WorkerIdentity(worker_id, "readyz-test", 1, VERSION, datetime.now(UTC))
        with factory.begin() as session:
            upsert_heartbeat(session, identity, running_jobs=0)
            if age_s is not None:  # the worker role may update last_seen_at (migration 0003)
                session.execute(
                    text(
                        "UPDATE worker_heartbeats SET last_seen_at = now() - "
                        "make_interval(secs => :age) WHERE worker_id = :id"
                    ),
                    {"age": age_s, "id": worker_id},
                )
        return worker_id

    return write


def _get_readyz(client: TestClient) -> tuple[int, dict[str, Any], float]:
    started = time.perf_counter()
    response = client.get("/readyz")
    elapsed = time.perf_counter() - started
    assert response.headers["cache-control"] == "no-store"
    return response.status_code, response.json(), elapsed


def _assert_no_connection_details(body: dict[str, Any], login: Login) -> None:
    assert set(body) == {"checks", "version", "head"}
    assert set(body["checks"]) == set(ALL_OK)
    assert all(isinstance(value, bool) for value in body["checks"].values())
    rendered = repr(body)
    leaks = [login.login.name, login.password, login.host, login.database, "postgresql"]
    leaks += ["psycopg", "Error", "error", "Exception", "@", "://"]
    assert [leak for leak in leaks if leak and leak in rendered] == []


# --- all checks pass ---------------------------------------------------------------------


def test_readyz_200_when_every_check_passes(
    make_client: Callable[[Settings], TestClient],
    app_login: Login,
    attachments: Path,
    beat: Callable[..., str],
) -> None:
    beat()
    client = make_client(_settings(app_login, attachments))

    status, body, elapsed = _get_readyz(client)

    assert (status, body) == (200, {"checks": ALL_OK, "version": VERSION, "head": HEAD})
    assert elapsed < READYZ_BUDGET_S
    assert list(attachments.iterdir()) == []  # the probe file is removed again
    _assert_no_connection_details(body, app_login)


def test_heartbeat_window_is_two_minutes(
    make_client: Callable[[Settings], TestClient],
    app_login: Login,
    attachments: Path,
    beat: Callable[..., str],
) -> None:
    client = make_client(_settings(app_login, attachments))

    beat(age_s=100)
    recent = _get_readyz(client)
    beat(age_s=130)
    stale = _get_readyz(client)

    assert (recent[0], recent[1]["checks"]) == (200, ALL_OK)
    assert (stale[0], stale[1]["checks"]) == (503, ALL_OK | {"worker": False})


# --- one failing check -> 503 ------------------------------------------------------------


@pytest.mark.parametrize("problem", ["missing", "not_a_directory"])
def test_readyz_503_when_attachments_dir_is_not_writable(
    problem: str,
    make_client: Callable[[Settings], TestClient],
    app_login: Login,
    tmp_path: Path,
    beat: Callable[..., str],
) -> None:
    """Real filesystem conditions (the suite runs as root here, so a chmod would not stop
    writes): the directory does not exist, or the path is a regular file."""
    beat()
    target = tmp_path / "attachments"
    if problem == "not_a_directory":
        target.write_bytes(b"")
    client = make_client(_settings(app_login, target))

    status, body, _ = _get_readyz(client)

    assert (status, body["checks"]) == (503, ALL_OK | {"attachments": False})
    _assert_no_connection_details(body, app_login)


def test_readyz_503_without_worker_heartbeat(
    make_client: Callable[[Settings], TestClient],
    app_login: Login,
    attachments: Path,
    no_heartbeats: None,
) -> None:
    del no_heartbeats
    client = make_client(_settings(app_login, attachments))

    status, body, _ = _get_readyz(client)

    assert (status, body) == (
        503,
        {"checks": ALL_OK | {"worker": False}, "version": VERSION, "head": HEAD},
    )


def test_readyz_503_when_database_is_not_at_head(
    make_client: Callable[[Settings], TestClient],
    app_login: Login,
    attachments: Path,
    beat: Callable[..., str],
    db_engine: Engine,
) -> None:
    """The database reports the revision before head (as after a skipped ``migrate``)."""
    beat()
    previous = _down_revision(HEAD)
    client = make_client(_settings(app_login, attachments))
    set_version = text("UPDATE alembic_version SET version_num = :v")
    with db_engine.begin() as connection:
        original = connection.execute(text("SELECT version_num FROM alembic_version")).scalar_one()
        connection.execute(set_version, {"v": previous})
    try:
        status, body, _ = _get_readyz(client)
    finally:
        with db_engine.begin() as connection:
            connection.execute(set_version, {"v": original})

    assert (status, body) == (
        503,
        {"checks": ALL_OK | {"migrations": False}, "version": VERSION, "head": HEAD},
    )


def _down_revision(head: str) -> str:
    from alembic.script import ScriptDirectory

    revision = ScriptDirectory.from_config(alembic_config()).get_revision(head)
    assert revision is not None
    assert isinstance(revision.down_revision, str)
    return revision.down_revision


# --- database unreachable, wrong password, hanging server ---------------------------------


def _closed_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.bind(("127.0.0.1", 0))
        return int(probe.getsockname()[1])


@pytest.mark.usefixtures("clean_settings_env")
def test_readyz_503_when_database_is_unreachable(
    make_client: Callable[[Settings], TestClient], tmp_path: Path
) -> None:
    port = _closed_port()
    settings = Settings(
        database_url=f"postgresql+psycopg://cardflow_api@127.0.0.1:{port}/cardflow",
        database_password="not-used-0123456789",
        attachments_dir=tmp_path,
        cardflow_version=VERSION,
    )
    client = make_client(settings)

    status, body, elapsed = _get_readyz(client)

    assert (status, body["checks"]) == (
        503,
        {"database": False, "migrations": False, "worker": False, "attachments": True},
    )
    assert str(port) not in repr(body)
    assert "cardflow_api" not in repr(body)
    assert elapsed < READYZ_BUDGET_S
    assert client.get("/healthz").status_code == 200  # liveness ignores dependencies


def test_wrong_password_is_reported_without_details(
    make_client: Callable[[Settings], TestClient],
    app_login: Login,
    attachments: Path,
    beat: Callable[..., str],
    caplog: pytest.LogCaptureFixture,
) -> None:
    beat()
    wrong = "wrong-password-t012-0123456789"
    client = make_client(_settings(app_login, attachments, database_password=wrong))

    with caplog.at_level(logging.WARNING, logger="cardflow.api.readiness"):
        status, body, _ = _get_readyz(client)

    assert (status, body["checks"]) == (
        503,
        {"database": False, "migrations": False, "worker": False, "attachments": True},
    )
    _assert_no_connection_details(body, app_login)
    messages = [record.getMessage() for record in caplog.records]
    # libpq reports connection failures as text only (no SQLSTATE); the type is all we log.
    assert "readiness check failed check=database error=OperationalError" in messages
    secrets_and_targets = (wrong, "://", app_login.login.name, app_login.host, app_login.port)
    assert [m for m in messages if any(part in m for part in secrets_and_targets)] == []


@pytest.mark.usefixtures("clean_settings_env")
def test_hanging_database_answers_within_the_budget(
    make_client: Callable[[Settings], TestClient], tmp_path: Path
) -> None:
    """A server that accepts TCP but never speaks: connect_timeout (2 s) ends the attempt."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as silent:
        silent.bind(("127.0.0.1", 0))
        silent.listen(8)
        port = silent.getsockname()[1]
        settings = Settings(
            database_url=f"postgresql+psycopg://cardflow_api@127.0.0.1:{port}/cardflow",
            database_password="not-used-0123456789",
            attachments_dir=tmp_path,
            cardflow_version=VERSION,
        )
        client = make_client(settings)

        status, body, elapsed = _get_readyz(client)

    assert (status, body["checks"]["database"], body["checks"]["attachments"]) == (503, False, True)
    assert elapsed < READYZ_BUDGET_S


def test_locked_heartbeat_table_times_out_only_that_check(
    make_client: Callable[[Settings], TestClient],
    app_login: Login,
    attachments: Path,
    beat: Callable[..., str],
    db_engine: Engine,
) -> None:
    """Per-query timeout: a lock on worker_heartbeats fails the worker check after 500 ms
    (lock_timeout) while the other checks still pass."""
    beat()
    client = make_client(_settings(app_login, attachments))
    with db_engine.connect() as locker:
        transaction = locker.begin()
        locker.execute(text("LOCK TABLE worker_heartbeats IN ACCESS EXCLUSIVE MODE"))
        try:
            status, body, elapsed = _get_readyz(client)
        finally:
            transaction.rollback()

    assert (status, body["checks"]) == (503, ALL_OK | {"worker": False})
    assert elapsed < READYZ_BUDGET_S


def test_hanging_attachment_volume_fails_only_that_check(
    make_client: Callable[[Settings], TestClient],
    app_login: Login,
    attachments: Path,
    beat: Callable[..., str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Per-check timeout for the volume (simulated: a write that blocks for 2.5 s)."""
    beat()
    release = threading.Event()

    def blocked_write(directory: Path) -> bool:
        del directory
        release.wait(2.5)
        return True

    monkeypatch.setattr(health, "attachments_writable", blocked_write)
    client = make_client(_settings(app_login, attachments))
    try:
        status, body, elapsed = _get_readyz(client)
    finally:
        release.set()

    assert (status, body["checks"]) == (503, ALL_OK | {"attachments": False})
    assert elapsed < READYZ_BUDGET_S


# --- probe mechanics (no database) ------------------------------------------------------------


@pytest.mark.usefixtures("clean_settings_env")
def test_concurrent_requests_share_one_probe(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    calls: list[float] = []

    def fake_database_checks(engine: Engine, results: dict[str, bool]) -> None:
        del engine
        calls.append(time.monotonic())
        time.sleep(0.3)
        results.update(dict.fromkeys(health.DATABASE_CHECKS, True))

    monkeypatch.setattr(health, "database_checks", fake_database_checks)
    probe = health.ReadinessProbe(Settings(attachments_dir=tmp_path, cardflow_version=VERSION))

    async def scenario() -> tuple[list[health.Readiness], health.Readiness]:
        burst = await asyncio.gather(*(probe.run() for _ in range(5)))
        later = await probe.run()
        return list(burst), later

    burst, later = asyncio.run(scenario())

    assert len(calls) == 2  # one shared run for the burst, a new one afterwards
    assert all(result.ready for result in [*burst, later])


# --- API docs switch (T-012) ----------------------------------------------------------------


DOC_PATHS: Final = ("/docs", "/redoc", "/openapi.json")


@pytest.mark.usefixtures("clean_settings_env")
def test_docs_are_off_by_default_but_the_schema_stays_available_in_code() -> None:
    app = create_app(Settings())
    with TestClient(app) as client:
        statuses = {path: client.get(path).status_code for path in DOC_PATHS}

    assert statuses == dict.fromkeys(DOC_PATHS, 404)
    paths = app.openapi()["paths"]
    assert {"/healthz", "/readyz"} <= set(paths)
    assert set(paths["/readyz"]["get"]["responses"]) == {"200", "503"}


def test_docs_can_be_enabled(clean_settings_env: pytest.MonkeyPatch) -> None:
    clean_settings_env.setenv("API_DOCS_ENABLED", "true")
    with TestClient(create_app(Settings())) as client:
        statuses = {path: client.get(path).status_code for path in DOC_PATHS}

    assert statuses == dict.fromkeys(DOC_PATHS, 200)
