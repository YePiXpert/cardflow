"""Shared fixtures.

Database tests
--------------
Tests that need PostgreSQL carry the ``db`` marker; it is also added automatically to
every test that requests one of :data:`DB_FIXTURES`. They connect with the superuser URL
in ``CARDFLOW_TEST_DATABASE_URL`` (``CARDFLOW_TEST_DATABASE_URL="$(tools/dev-db.sh url)"``
from the repository root), create a temporary database ``cardflow_test_<random>`` once per
session and drop it at the end.

If the variable is unset or the server is unreachable, database tests ERROR -- they are
never skipped. Exclude them explicitly with ``pytest -m "not db"``.

Schema under test
-----------------
:func:`prepare_test_database` runs Alembic (``cardflow.db.migrations.upgrade``) on the
fresh database; it is the only place the test schema is created. The target revision is
``head`` unless ``CARDFLOW_TEST_MIGRATION_TARGET`` names another one, e.g.
``CARDFLOW_TEST_MIGRATION_TARGET=0001``: while a parallel task is still developing the
next revision (0002 ...), other tasks can pin their test runs to the last finished
revision. Tests that only make sense at head (model drift) request ``require_head_schema``
and are SKIPPED with the reason when the session schema is not at head -- a development
switch; leave the variable unset for acceptance runs and CI.

Fixtures for later tasks:

* ``admin_database_url`` -- superuser URL (maintenance database); session scope.
* ``temporary_databases`` -- creates/drops extra empty ``cardflow_test_<random>``
  databases (e.g. migration round trips); session scope.
* ``test_database_url`` -- URL of the temporary database, already prepared by
  :func:`prepare_test_database` (the "migrate to target" hook); session scope.
* ``migration_target`` / ``schema_revision`` -- the requested target and the revision
  id the session database is at; ``require_head_schema`` skips unless it is head.
* ``db_engine`` / ``db_session_factory`` -- engine and session factory on that database.
  They connect as a superuser, which BYPASSES row-level security: use them to arrange
  fixture rows, never to exercise code that must run under RLS.
* ``clean_settings_env`` -- removes every variable ``Settings`` reads.
* ``app`` / ``client`` -- application built from default settings, and a TestClient.

Database roles (T-006, migration 0003)
--------------------------------------
``database_logins`` creates, once per session, temporary LOGIN roles with random names and
passwords (``cardflow_test_<kind>_<hex>``) through the production provisioning code
(``cardflow.db.roles.provision_login_role``), shaped exactly like the deployed logins, and
drops them at the end. Engines on the session database (``NullPool``: every
``connect()`` is a fresh backend session, so no ``SET ROLE`` or setting leaks between
tests):

* ``app_engine`` -- like ``cardflow_api``: member of cardflow_app (the API).
* ``worker_engine`` -- member of cardflow_worker only (job worker without purge rights).
* ``purge_capable_engine`` -- like ``cardflow_worker_login``: cardflow_worker, plus
  cardflow_purge WITH INHERIT FALSE, SET TRUE (DELETE only after ``SET LOCAL ROLE
  cardflow_purge``).
* ``admin_engine`` -- like ``cardflow_admin_login``: member of cardflow_admin.

They need the session database at head (the group roles come from migration 0003) and are
skipped otherwise, like ``require_head_schema``. Typical use in API/worker tests
(T-009/T-010/T-011)::

    def test_something(app_engine, db_engine):
        factory = create_session_factory(app_engine)
        with workspace_tx(factory, workspace_id) as session:   # binds app.workspace_id
            session.execute(...)                               # sees only that workspace

Arrange rows with ``db_engine`` (superuser) and commit them first, then act through the role
engine. For an application under test, point ``DATABASE_URL`` at
``database_logins["app"].url(test_database_url)`` (the password is in the URL; tests only).

Devices and tokens (T-011)
--------------------------
For API tests that need an authenticated device (T-009, T-010, T-031 ...):

* ``api_settings`` -- :class:`Settings` of an API that logs in as the temporary
  ``cardflow_api``-like role (``DATABASE_URL`` + ``DATABASE_PASSWORD``) with a random
  ``JWT_KEY``; ``jwt_secrets`` holds that key and a second one (for rotation tests).
* ``api_app`` / ``api_client`` -- the real application on those settings and its
  TestClient; the database engine is created lazily and disposed afterwards.
* ``pairing_codes`` -- ``pairing_codes(workspace_id=None, ttl=...)`` creates a code exactly
  like ``cardflow pairing create`` (superuser connection) and returns a ``NewPairingCode``
  (``.code`` is the plaintext, display form).
* ``registered_device`` -- a device registered through ``POST /v1/devices/register`` with a
  fresh bootstrap code (new workspace, anonymous owner): ``.headers`` is
  ``{"Authorization": "Bearer <access token>"}``; ``.device_id``, ``.workspace_id``,
  ``.access_token``, ``.refresh_token``, ``.registration`` (the request body) are there too.
* ``device_registration_body`` -- builds a valid API-01 body (fresh Ed25519 key) for a code.
"""

import base64
import os
import secrets
import uuid
from collections.abc import Callable, Iterator
from dataclasses import dataclass, field
from datetime import timedelta
from typing import Any, Final

import pytest
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
from fastapi import FastAPI
from fastapi.testclient import TestClient
from pydantic import SecretStr
from sqlalchemy import text
from sqlalchemy.engine import URL, Engine
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import NullPool

from cardflow.api.app import create_app
from cardflow.api.deps import dispose_database
from cardflow.db import create_engine, create_session_factory, normalize_database_url
from cardflow.db.migrations import head_revisions, resolve_revision, upgrade
from cardflow.db.roles import (
    ADMIN_LOGIN,
    API_LOGIN,
    WORKER_LOGIN,
    WORKER_ROLE,
    LoginRole,
    Membership,
    provision_login_role,
)
from cardflow.identity.pairing import DEFAULT_TTL, NewPairingCode, create_pairing_code
from cardflow.settings import SECRET_FIELDS, Settings

TEST_DATABASE_URL_ENV: Final = "CARDFLOW_TEST_DATABASE_URL"
TEST_MIGRATION_TARGET_ENV: Final = "CARDFLOW_TEST_MIGRATION_TARGET"
TEST_DATABASE_PREFIX: Final = "cardflow_test_"
DB_FIXTURES: Final = frozenset(
    {
        "admin_database_url",
        "temporary_databases",
        "test_database_url",
        "schema_revision",
        "require_head_schema",
        "db_engine",
        "db_session_factory",
        "database_logins",
        "app_engine",
        "worker_engine",
        "purge_capable_engine",
        "admin_engine",
        "api_settings",
        "api_app",
        "api_client",
        "pairing_codes",
        "registered_device",
    }
)
TEST_LOGIN_PREFIX: Final = "cardflow_test_"
# Memberships of the temporary login roles, mirroring cardflow.db.roles.LOGIN_ROLES.
TEST_LOGIN_SHAPES: Final[dict[str, tuple[Membership, ...]]] = {
    "app": API_LOGIN.memberships,
    "worker": (Membership(WORKER_ROLE, inherit=True, set_role=False),),
    "purge_capable": WORKER_LOGIN.memberships,
    "admin": ADMIN_LOGIN.memberships,
}


def pytest_configure(config: pytest.Config) -> None:
    """Register the ``db`` marker."""
    config.addinivalue_line(
        "markers",
        f"db: needs PostgreSQL via {TEST_DATABASE_URL_ENV}; errors (never skips) when "
        'unavailable -- deselect with -m "not db"',
    )


@pytest.hookimpl(tryfirst=True)
def pytest_collection_modifyitems(items: list[pytest.Item]) -> None:
    """Mark every test that uses a database fixture as ``db`` (before ``-m`` filtering)."""
    for item in items:
        if DB_FIXTURES.intersection(getattr(item, "fixturenames", ())):
            item.add_marker(pytest.mark.db)


def requested_migration_target() -> str:
    """Revision the session database is migrated to: ``$CARDFLOW_TEST_MIGRATION_TARGET``
    or ``head``."""
    return os.environ.get(TEST_MIGRATION_TARGET_ENV, "").strip() or "head"


def prepare_test_database(url: URL) -> None:
    """Hook: bring the freshly created, EMPTY test database to the schema under test.

    Runs the Alembic migrations up to :func:`requested_migration_target` (``head`` by
    default). Keep this the single place where the test schema is created.
    """
    upgrade(url, requested_migration_target())


def _masked(url: URL) -> str:
    return url.render_as_string(hide_password=True)


@pytest.fixture(scope="session")
def admin_database_url() -> URL:
    """Superuser URL from ``CARDFLOW_TEST_DATABASE_URL``; fails (not skips) if unusable."""
    raw = os.environ.get(TEST_DATABASE_URL_ENV, "").strip()
    if not raw:
        pytest.fail(
            f"{TEST_DATABASE_URL_ENV} is not set. DB tests need a PostgreSQL superuser URL, "
            f'e.g. {TEST_DATABASE_URL_ENV}="$(tools/dev-db.sh url)"; '
            'or deselect them with -m "not db".',
            pytrace=False,
        )
    try:
        url = normalize_database_url(raw)
    except ValueError as exc:
        pytest.fail(f"{TEST_DATABASE_URL_ENV} is invalid: {exc}", pytrace=False)
    engine = create_engine(url, poolclass=NullPool)
    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
    except SQLAlchemyError as exc:
        reason = getattr(exc, "orig", None) or exc
        pytest.fail(f"cannot connect to {_masked(url)}: {reason}", pytrace=False)
    finally:
        engine.dispose()
    return url


class TemporaryDatabases:
    """Creates empty ``cardflow_test_<random>`` databases and drops them again."""

    def __init__(self, admin_url: URL) -> None:
        self._admin_engine = create_engine(admin_url, poolclass=NullPool)
        self._admin_url = admin_url

    def create(self) -> URL:
        """Create an empty database (from ``template0``) and return its URL."""
        name = f"{TEST_DATABASE_PREFIX}{secrets.token_hex(6)}"  # [0-9a-f]: safe identifier
        admin = self._admin_engine.execution_options(isolation_level="AUTOCOMMIT")
        with admin.connect() as connection:
            connection.execute(
                text(f"CREATE DATABASE \"{name}\" TEMPLATE template0 ENCODING 'UTF8'")
            )
        return self._admin_url.set(database=name)

    def drop(self, url: URL) -> None:
        """Drop a database created by :meth:`create` (terminating its sessions)."""
        name = url.database or ""
        if not name.startswith(TEST_DATABASE_PREFIX):
            raise ValueError(f"refusing to drop {name!r}: not a {TEST_DATABASE_PREFIX}* database")
        admin = self._admin_engine.execution_options(isolation_level="AUTOCOMMIT")
        with admin.connect() as connection:
            connection.execute(text(f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)'))

    def dispose(self) -> None:
        """Release the maintenance connection pool."""
        self._admin_engine.dispose()


@pytest.fixture(scope="session")
def temporary_databases(admin_database_url: URL) -> Iterator[TemporaryDatabases]:
    """Factory for extra empty databases (never the shared session database)."""
    databases = TemporaryDatabases(admin_database_url)
    yield databases
    databases.dispose()


@pytest.fixture(scope="session")
def test_database_url(temporary_databases: TemporaryDatabases) -> Iterator[URL]:
    """Temporary database (random suffix) for this session, migrated; dropped afterwards."""
    url = temporary_databases.create()
    try:
        prepare_test_database(url)
        yield url
    finally:
        temporary_databases.drop(url)


@pytest.fixture(scope="session")
def migration_target() -> str:
    """The requested Alembic target of the session database (default ``head``)."""
    return requested_migration_target()


@pytest.fixture(scope="session")
def schema_revision(test_database_url: URL, migration_target: str) -> str | None:
    """Revision id the session database was migrated to (``None`` = base)."""
    del test_database_url  # ensures the database exists and is migrated
    return resolve_revision(migration_target)


@pytest.fixture
def require_head_schema(schema_revision: str | None, migration_target: str) -> None:
    """Skip (development switch) unless the session database is at the code's head."""
    heads = head_revisions()
    if (schema_revision,) != heads:
        pytest.skip(
            f"{TEST_MIGRATION_TARGET_ENV}={migration_target} pins the schema to revision "
            f"{schema_revision or 'base'}, but this test checks the head schema "
            f"{', '.join(heads)}; unset the variable to run it"
        )


@pytest.fixture(scope="session")
def db_engine(test_database_url: URL) -> Iterator[Engine]:
    """Engine on the temporary database (superuser: RLS does not apply)."""
    engine = create_engine(test_database_url)
    yield engine
    engine.dispose()


@pytest.fixture(scope="session")
def db_session_factory(db_engine: Engine) -> sessionmaker[Session]:
    """Session factory on the temporary database, as used by ``workspace_tx``."""
    return create_session_factory(db_engine)


@pytest.fixture
def clean_settings_env(monkeypatch: pytest.MonkeyPatch) -> pytest.MonkeyPatch:
    """Remove every environment variable ``Settings`` reads (any case), incl. ``*_FILE``."""
    names = {name.upper() for name in Settings.model_fields}
    names |= {f"{name.upper()}_FILE" for name in SECRET_FIELDS}
    for key in list(os.environ):
        if key.upper() in names:
            monkeypatch.delenv(key)
    return monkeypatch


@pytest.fixture
def app(clean_settings_env: pytest.MonkeyPatch) -> FastAPI:
    """Application built from default settings (no environment influence)."""
    return create_app(Settings())


@pytest.fixture
def client(app: FastAPI) -> Iterator[TestClient]:
    """TestClient for :func:`app`."""
    with TestClient(app) as test_client:
        yield test_client


# --- database roles (T-006) -------------------------------------------------------------


@dataclass(frozen=True)
class DatabaseLogin:
    """A temporary LOGIN role of the test session (random name and password)."""

    name: str
    password: str

    def url(self, base: URL) -> URL:
        """``base`` (e.g. ``test_database_url``) with this role's credentials."""
        return base.set(username=self.name, password=self.password)


@pytest.fixture(scope="session")
def database_logins(
    admin_database_url: URL, test_database_url: URL, schema_revision: str | None
) -> Iterator[dict[str, DatabaseLogin]]:
    """Temporary LOGIN roles shaped like the deployed ones (:data:`TEST_LOGIN_SHAPES`),
    created with the production provisioning code and dropped at the end of the session."""
    if (schema_revision,) != head_revisions():
        pytest.skip(
            f"the database roles come from migration head {', '.join(head_revisions())}; "
            f"the session schema is at {schema_revision or 'base'}"
        )
    suffix = secrets.token_hex(4)
    logins = {
        kind: DatabaseLogin(f"{TEST_LOGIN_PREFIX}{kind}_{suffix}", secrets.token_hex(16))
        for kind in TEST_LOGIN_SHAPES
    }
    admin = create_engine(admin_database_url, poolclass=NullPool)
    database = create_engine(test_database_url, poolclass=NullPool)
    try:
        with admin.begin() as connection:
            for kind, login in logins.items():
                spec = LoginRole(login.name, TEST_LOGIN_SHAPES[kind], "", f"test {kind}")
                provision_login_role(connection, spec, login.password)
        yield logins
    finally:
        # Names are "cardflow_test_<kind>_<hex>": safe to inline.
        with database.begin() as connection:
            for login in logins.values():
                connection.execute(text(f'DROP OWNED BY "{login.name}"'))
        with admin.begin() as connection:
            for login in logins.values():
                connection.execute(text(f'DROP ROLE IF EXISTS "{login.name}"'))
        database.dispose()
        admin.dispose()


def _login_engine(login: DatabaseLogin, database_url: URL, kind: str) -> Engine:
    return create_engine(
        login.url(database_url), application_name=f"cardflow-test-{kind}", poolclass=NullPool
    )


@pytest.fixture(scope="session")
def app_engine(
    database_logins: dict[str, DatabaseLogin], test_database_url: URL
) -> Iterator[Engine]:
    """Engine logged in like ``cardflow_api`` (member of cardflow_app)."""
    engine = _login_engine(database_logins["app"], test_database_url, "app")
    yield engine
    engine.dispose()


@pytest.fixture(scope="session")
def worker_engine(
    database_logins: dict[str, DatabaseLogin], test_database_url: URL
) -> Iterator[Engine]:
    """Engine logged in as a member of cardflow_worker only (no purge rights)."""
    engine = _login_engine(database_logins["worker"], test_database_url, "worker")
    yield engine
    engine.dispose()


@pytest.fixture(scope="session")
def purge_capable_engine(
    database_logins: dict[str, DatabaseLogin], test_database_url: URL
) -> Iterator[Engine]:
    """Engine logged in like ``cardflow_worker_login`` (cardflow_worker + SET ROLE purge)."""
    engine = _login_engine(database_logins["purge_capable"], test_database_url, "purge")
    yield engine
    engine.dispose()


@pytest.fixture(scope="session")
def admin_engine(
    database_logins: dict[str, DatabaseLogin], test_database_url: URL
) -> Iterator[Engine]:
    """Engine logged in like ``cardflow_admin_login`` (member of cardflow_admin)."""
    engine = _login_engine(database_logins["admin"], test_database_url, "admin")
    yield engine
    engine.dispose()


# --- devices and tokens (T-011) -----------------------------------------------------------


@pytest.fixture(scope="session")
def jwt_secrets() -> tuple[str, str]:
    """Two random JWT signing secrets (current, previous), 64 characters each."""
    return secrets.token_urlsafe(48), secrets.token_urlsafe(48)


@pytest.fixture
def api_settings(
    database_logins: dict[str, DatabaseLogin],
    test_database_url: URL,
    jwt_secrets: tuple[str, str],
    clean_settings_env: pytest.MonkeyPatch,
) -> Settings:
    """Settings of an API logged in as the temporary cardflow_api-like role, never the
    superuser; ``JWT_KEY`` is ``jwt_secrets[0]``."""
    del clean_settings_env  # the environment must not leak into these settings
    login = database_logins["app"]
    url = URL.create(
        test_database_url.drivername,
        username=login.name,
        host=test_database_url.host,
        port=test_database_url.port,
        database=test_database_url.database,
    )
    return Settings(
        database_url=url.render_as_string(hide_password=False),
        database_password=SecretStr(login.password),
        jwt_key=SecretStr(jwt_secrets[0]),
    )


@pytest.fixture
def api_app(api_settings: Settings) -> Iterator[FastAPI]:
    """The real application on :func:`api_settings`; its engine is disposed afterwards."""
    application = create_app(api_settings)
    yield application
    dispose_database(application)


@pytest.fixture
def api_client(api_app: FastAPI) -> Iterator[TestClient]:
    """TestClient for :func:`api_app`."""
    with TestClient(api_app) as test_client:
        yield test_client


@pytest.fixture
def pairing_codes(db_engine: Engine) -> Callable[..., NewPairingCode]:
    """``create(workspace_id=None, ttl=DEFAULT_TTL)``: a pairing code made like ``cardflow
    pairing create`` (operator, superuser connection)."""

    def create(
        workspace_id: uuid.UUID | None = None, ttl: timedelta = DEFAULT_TTL
    ) -> NewPairingCode:
        with db_engine.begin() as connection:
            return create_pairing_code(connection, workspace_id=workspace_id, ttl=ttl)

    return create


def new_device_public_key() -> str:
    """base64 of the DER SubjectPublicKeyInfo of a fresh Ed25519 key."""
    der = (
        Ed25519PrivateKey.generate()
        .public_key()
        .public_bytes(Encoding.DER, PublicFormat.SubjectPublicKeyInfo)
    )
    return base64.b64encode(der).decode("ascii")


@pytest.fixture
def device_registration_body() -> Callable[..., dict[str, Any]]:
    """``body(code, **overrides)``: a valid API-01 request body with a fresh public key."""

    def body(code: str, **overrides: Any) -> dict[str, Any]:  # noqa: ANN401 - JSON values
        values: dict[str, Any] = {
            "pairing_code": code,
            "public_key": new_device_public_key(),
            "name": "Test phone",
            "platform": "android",
            "app_version": "1.0.0",
        }
        values.update(overrides)
        return values

    return body


@dataclass(frozen=True)
class RegisteredDevice:
    """A device registered through API-01 (tokens as returned by the API)."""

    device_id: uuid.UUID
    workspace_id: uuid.UUID
    access_token: str = field(repr=False)
    refresh_token: str = field(repr=False)
    registration: dict[str, Any] = field(repr=False)

    @property
    def headers(self) -> dict[str, str]:
        """``Authorization: Bearer <access token>``."""
        return {"Authorization": f"Bearer {self.access_token}"}


@pytest.fixture
def registered_device(
    api_client: TestClient,
    pairing_codes: Callable[..., NewPairingCode],
    device_registration_body: Callable[..., dict[str, Any]],
) -> RegisteredDevice:
    """A device registered with a fresh bootstrap code (new workspace, anonymous owner)."""
    body = device_registration_body(pairing_codes().code)
    response = api_client.post(
        "/v1/devices/register", json=body, headers={"Idempotency-Key": str(uuid.uuid4())}
    )
    assert response.status_code == 201, response.text
    tokens = response.json()
    return RegisteredDevice(
        device_id=uuid.UUID(tokens["device_id"]),
        workspace_id=uuid.UUID(tokens["workspace_id"]),
        access_token=tokens["access_token"],
        refresh_token=tokens["refresh_token"],
        registration=body,
    )
