"""``cardflow pairing create`` end to end (operator CLI, T-011)."""

import logging
import re
import uuid
from collections.abc import Iterator
from datetime import UTC, datetime, timedelta
from typing import Final

import pytest
from sqlalchemy import select
from sqlalchemy.engine import URL, Engine

from cardflow.cli import EXIT_OK, EXIT_PAIRING_FAILED, main
from cardflow.db.models import metadata
from cardflow.identity.pairing import normalize_pairing_code, pairing_code_hash

pytestmark = pytest.mark.db

T: Final = metadata.tables
CODE_LINE: Final = re.compile(r"^pairing code:\s+([0-9A-Z]{4}-[0-9A-Z]{4}-[0-9A-Z]{4})$", re.M)
ID_LINE: Final = re.compile(r"^pairing code id:\s+([0-9a-f-]{36})$", re.M)


@pytest.fixture
def restore_root_logging() -> Iterator[None]:
    """The CLI installs its own root log handler; undo that afterwards."""
    root = logging.getLogger()
    handlers, level = list(root.handlers), root.level
    yield
    root.handlers[:] = handlers
    root.setLevel(level)


def use_database(monkeypatch: pytest.MonkeyPatch, url: URL) -> None:
    """DATABASE_URL without the password, DATABASE_PASSWORD separately (as deployed)."""
    without_password = URL.create(
        url.drivername, username=url.username, host=url.host, port=url.port, database=url.database
    )
    monkeypatch.setenv("DATABASE_URL", without_password.render_as_string(hide_password=False))
    monkeypatch.setenv("DATABASE_PASSWORD", url.password or "")


@pytest.mark.usefixtures("restore_root_logging")
def test_create_bootstrap_code_prints_it_once_and_audits(
    clean_settings_env: pytest.MonkeyPatch,
    test_database_url: URL,
    db_engine: Engine,
    capsys: pytest.CaptureFixture[str],
) -> None:
    use_database(clean_settings_env, test_database_url)
    started = datetime.now(UTC)

    assert main(["pairing", "create", "--new-workspace", "--ttl", "15m"]) == EXIT_OK

    out, err = capsys.readouterr()
    code = CODE_LINE.search(out)
    code_id = ID_LINE.search(out)
    assert code is not None, out
    assert code_id is not None, out
    with db_engine.connect() as connection:
        row = connection.execute(
            select(T["pairing_codes"]).where(T["pairing_codes"].c.id == uuid.UUID(code_id[1]))
        ).one()
        audit = connection.execute(
            select(T["audit_log"]).where(T["audit_log"].c.target_id == row.id)
        ).one()
    assert row.code_hash == pairing_code_hash(normalize_pairing_code(code[1]) or "")
    assert (row.purpose, row.workspace_id, row.created_via) == ("bootstrap_workspace", None, "cli")
    assert timedelta(minutes=14) < row.expires_at - started <= timedelta(minutes=16)
    assert row.used_at is None
    assert (audit.action, audit.actor_kind, audit.workspace_id) == (
        "pairing_code.created",
        "cli",
        None,
    )
    assert "workspace:       new" in out
    assert code[1] not in err
    assert normalize_pairing_code(code[1]) not in err
    assert out.count(code[1]) == 1


@pytest.mark.usefixtures("restore_root_logging")
def test_create_join_code_for_a_workspace(
    clean_settings_env: pytest.MonkeyPatch,
    test_database_url: URL,
    db_engine: Engine,
    capsys: pytest.CaptureFixture[str],
) -> None:
    use_database(clean_settings_env, test_database_url)
    with db_engine.begin() as connection:
        owner = connection.execute(T["users"].insert().returning(T["users"].c.id)).scalar_one()
        workspace = connection.execute(
            T["workspaces"]
            .insert()
            .values(owner_user_id=owner, kind="real")
            .returning(T["workspaces"].c.id)
        ).scalar_one()

    assert main(["pairing", "create", "--workspace", str(workspace)]) == EXIT_OK

    out = capsys.readouterr().out
    code_id = ID_LINE.search(out)
    assert code_id is not None
    with db_engine.connect() as connection:
        row = connection.execute(
            select(T["pairing_codes"]).where(T["pairing_codes"].c.id == uuid.UUID(code_id[1]))
        ).one()
    assert (row.purpose, row.workspace_id) == ("join_workspace", workspace)
    assert f"workspace:       {workspace}" in out


@pytest.mark.usefixtures("restore_root_logging")
def test_unknown_workspace_is_refused(
    clean_settings_env: pytest.MonkeyPatch,
    test_database_url: URL,
    capsys: pytest.CaptureFixture[str],
) -> None:
    use_database(clean_settings_env, test_database_url)

    assert main(["pairing", "create", "--workspace", str(uuid.uuid4())]) == EXIT_PAIRING_FAILED
    assert "no live workspace" in capsys.readouterr().err


@pytest.mark.usefixtures("restore_root_logging")
def test_the_api_role_cannot_mint_codes(
    clean_settings_env: pytest.MonkeyPatch,
    test_database_url: URL,
    database_logins: dict[str, object],
    capsys: pytest.CaptureFixture[str],
) -> None:
    """Only the operator (migration credentials) mints codes: the API's LOGIN role gets a
    permission error and nothing is written."""
    login = database_logins["app"]
    use_database(
        clean_settings_env,
        test_database_url.set(username=login.name, password=login.password),  # type: ignore[attr-defined]
    )

    assert main(["pairing", "create", "--new-workspace"]) == EXIT_PAIRING_FAILED
    err = capsys.readouterr().err
    assert "[42501]" in err
    assert "migration credentials" in err


@pytest.mark.parametrize(
    "argv",
    [
        ["pairing", "create"],
        ["pairing", "create", "--new-workspace", "--workspace", str(uuid.uuid4())],
        ["pairing", "create", "--workspace", "not-a-uuid"],
        ["pairing", "create", "--new-workspace", "--ttl", "48h"],
        ["pairing", "create", "--new-workspace", "--ttl", "soon"],
        ["pairing"],
    ],
)
def test_bad_arguments_exit_2(argv: list[str]) -> None:
    with pytest.raises(SystemExit) as caught:
        main(argv)
    assert caught.value.code == 2
