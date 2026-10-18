"""``workspace_tx`` transaction semantics and settings-to-engine wiring on real PostgreSQL."""

import uuid
from collections.abc import Iterator

import pytest
from pydantic import SecretStr
from sqlalchemy import text
from sqlalchemy.engine import URL, Engine
from sqlalchemy.exc import InvalidRequestError
from sqlalchemy.orm import Session, sessionmaker

from cardflow.db import (
    create_engine_from_settings,
    set_user_id,
    set_workspace_id,
    workspace_tx,
)
from cardflow.settings import Settings

pytestmark = pytest.mark.db

CURRENT_WORKSPACE = text("SELECT current_setting('app.workspace_id', true)")
CURRENT_USER_ID = text("SELECT current_setting('app.user_id', true)")


class ProbeError(Exception):
    """Raised inside a workspace transaction to force a rollback."""


@pytest.fixture
def probe_table(db_engine: Engine) -> Iterator[None]:
    """Scratch table, dropped after each test (the session database is shared)."""
    with db_engine.begin() as connection:
        connection.execute(text("CREATE TABLE t002_probe (id int PRIMARY KEY, workspace_id uuid)"))
    yield
    with db_engine.begin() as connection:
        connection.execute(text("DROP TABLE t002_probe"))


def probe_workspace_ids(engine: Engine) -> list[uuid.UUID | None]:
    with engine.connect() as connection:
        rows = connection.execute(text("SELECT workspace_id FROM t002_probe ORDER BY id"))
        return list(rows.scalars())


@pytest.mark.usefixtures("probe_table")
def test_commits_on_success(db_engine: Engine, db_session_factory: sessionmaker[Session]) -> None:
    workspace_id = uuid.uuid4()

    with workspace_tx(db_session_factory, workspace_id) as session:
        session.execute(
            text("INSERT INTO t002_probe VALUES (1, current_setting('app.workspace_id')::uuid)")
        )

    assert probe_workspace_ids(db_engine) == [workspace_id]


@pytest.mark.usefixtures("probe_table")
def test_rolls_back_on_exception(
    db_engine: Engine, db_session_factory: sessionmaker[Session]
) -> None:
    def insert_then_fail() -> None:
        with workspace_tx(db_session_factory, uuid.uuid4()) as session:
            session.execute(text("INSERT INTO t002_probe VALUES (1, NULL)"))
            raise ProbeError

    with pytest.raises(ProbeError):
        insert_then_fail()

    assert probe_workspace_ids(db_engine) == []


def test_no_statement_runs_after_an_early_commit(
    db_session_factory: sessionmaker[Session],
) -> None:
    def commit_then_query() -> None:
        with workspace_tx(db_session_factory, uuid.uuid4()) as session:
            session.commit()
            session.execute(CURRENT_WORKSPACE)

    with pytest.raises(InvalidRequestError):
        commit_then_query()


def test_rejects_non_uuid_workspace(db_session_factory: sessionmaker[Session]) -> None:
    with (
        pytest.raises(TypeError, match=r"uuid\.UUID"),
        workspace_tx(db_session_factory, "not-a-uuid"),  # type: ignore[arg-type]
    ):
        pass


def test_workspace_tx_binds_the_user_for_this_transaction_only(
    db_session_factory: sessionmaker[Session],
) -> None:
    """T-006: ``user_id`` binds app.user_id next to app.workspace_id (users policies);
    like the workspace it is transaction-local."""
    workspace_id, user_id = uuid.uuid4(), uuid.uuid4()

    with workspace_tx(db_session_factory, workspace_id, user_id=user_id) as session:
        bound = (
            session.execute(CURRENT_WORKSPACE).scalar_one(),
            session.execute(CURRENT_USER_ID).scalar_one(),
        )
    with workspace_tx(db_session_factory, workspace_id) as session:
        unbound_user = session.execute(CURRENT_USER_ID).scalar_one()

    assert bound == (str(workspace_id), str(user_id))
    assert unbound_user in (None, "")


def test_rejects_non_uuid_user(db_session_factory: sessionmaker[Session]) -> None:
    with (
        pytest.raises(TypeError, match=r"user_id must be uuid\.UUID"),
        workspace_tx(db_session_factory, uuid.uuid4(), user_id="admin"),  # type: ignore[arg-type]
    ):
        pass


def test_set_user_id_on_core_connection(db_engine: Engine) -> None:
    user_id = uuid.uuid4()

    with db_engine.begin() as connection:
        set_user_id(connection, user_id)
        assert connection.execute(CURRENT_USER_ID).scalar_one() == str(user_id)


def test_set_workspace_id_on_core_connection(db_engine: Engine) -> None:
    workspace_id = uuid.uuid4()

    with db_engine.begin() as connection:
        set_workspace_id(connection, workspace_id)
        assert connection.execute(CURRENT_WORKSPACE).scalar_one() == str(workspace_id)


@pytest.mark.usefixtures("clean_settings_env")
def test_engine_from_settings_connects_with_secret_password(test_database_url: URL) -> None:
    assert test_database_url.password is not None
    without_password = URL.create(
        drivername=test_database_url.drivername,
        username=test_database_url.username,
        host=test_database_url.host,
        port=test_database_url.port,
        database=test_database_url.database,
    )
    settings = Settings(
        database_url=without_password.render_as_string(hide_password=False),
        database_password=SecretStr(test_database_url.password),
    )
    engine = create_engine_from_settings(settings)
    try:
        with engine.connect() as connection:
            database = connection.execute(text("SELECT current_database()")).scalar_one()
            application = connection.execute(text("SHOW application_name")).scalar_one()
    finally:
        engine.dispose()

    assert database == test_database_url.database
    assert application == "cardflow"
