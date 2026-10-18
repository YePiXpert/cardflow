"""``cardflow db-provision`` and :mod:`cardflow.db.roles` (T-006): the LOGIN roles.

Every test provisions roles with random names (``cardflow_test_<kind>_login_<hex>``), never
the deployed names, and drops them afterwards; the end-to-end CLI test swaps
``LOGIN_ROLES`` for such specs. Passwords are random and only ever compared, never printed.
"""

import logging
import secrets
from collections.abc import Iterator
from dataclasses import replace
from pathlib import Path
from typing import Final

import pytest
from sqlalchemy import text
from sqlalchemy.engine import URL, Connection, Engine
from sqlalchemy.exc import OperationalError
from sqlalchemy.pool import NullPool

from cardflow.cli import EXIT_OK, EXIT_PROVISION_FAILED, main
from cardflow.db import roles
from cardflow.db.engine import create_engine
from cardflow.db.roles import (
    ADMIN_VIEWS_ROLE,
    AUTH_LOOKUP_ROLE,
    LOGIN_ROLES,
    PURGE_ROLE,
    LoginRole,
    ProvisionError,
    group_role_problems,
    provision_login_role,
)

pytestmark = [pytest.mark.db, pytest.mark.usefixtures("require_head_schema")]

ROLE_FLAGS: Final = (
    "rolcanlogin",
    "rolsuper",
    "rolcreatedb",
    "rolcreaterole",
    "rolreplication",
    "rolbypassrls",
    "rolinherit",
)


@pytest.fixture
def admin_engine_su(admin_database_url: URL) -> Iterator[Engine]:
    """Superuser engine on the maintenance database (roles are cluster-wide)."""
    engine = create_engine(admin_database_url, poolclass=NullPool)
    yield engine
    engine.dispose()


@pytest.fixture
def scratch_logins(admin_engine_su: Engine) -> Iterator[dict[str, LoginRole]]:
    """``LOGIN_ROLES`` with random names; whatever exists afterwards is dropped."""
    suffix = secrets.token_hex(4)
    specs = {
        key: replace(spec, name=f"cardflow_test_{key}_login_{suffix}")
        for key, spec in LOGIN_ROLES.items()
    }
    yield specs
    with admin_engine_su.begin() as connection:
        for spec in specs.values():
            connection.execute(text(f'DROP ROLE IF EXISTS "{spec.name}"'))


def role_state(connection: Connection, name: str) -> tuple[dict[str, bool], set[tuple]]:
    flags = connection.execute(
        text(f"SELECT {', '.join(ROLE_FLAGS)} FROM pg_roles WHERE rolname = :name"),  # noqa: S608
        {"name": name},
    ).one()
    memberships = {
        tuple(row)
        for row in connection.execute(
            text(
                "SELECT g.rolname, m.inherit_option, m.set_option, m.admin_option "
                "FROM pg_auth_members AS m JOIN pg_roles AS g ON g.oid = m.roleid "
                "JOIN pg_roles AS r ON r.oid = m.member WHERE r.rolname = :name"
            ),
            {"name": name},
        )
    }
    return dict(zip(ROLE_FLAGS, flags, strict=True)), memberships


def can_log_in(database_url: URL, name: str, password: str) -> bool:
    engine = create_engine(database_url.set(username=name, password=password), poolclass=NullPool)
    try:
        with engine.connect() as connection:
            return connection.execute(text("SELECT current_user")).scalar_one() == name
    except OperationalError:
        return False
    finally:
        engine.dispose()


EXPECTED_FLAGS: Final = {
    "rolcanlogin": True,
    "rolsuper": False,
    "rolcreatedb": False,
    "rolcreaterole": False,
    "rolreplication": False,
    "rolbypassrls": False,
    "rolinherit": True,
}
EXPECTED_MEMBERSHIPS: Final = {
    "api": {("cardflow_app", True, False, False)},
    "worker": {("cardflow_worker", True, False, False), ("cardflow_purge", False, True, False)},
    "admin": {("cardflow_admin", True, False, False)},
}


def test_provision_creates_roles_exactly_like_the_spec(
    admin_engine_su: Engine, scratch_logins: dict[str, LoginRole], test_database_url: URL
) -> None:
    """LOGIN, no superuser/BYPASSRLS/CREATEROLE/CREATEDB/REPLICATION, the spec's memberships
    with their INHERIT/SET options (purge: NOINHERIT, SET), a working password."""
    passwords = {key: secrets.token_urlsafe(24) for key in scratch_logins}
    with admin_engine_su.begin() as connection:
        results = {
            key: provision_login_role(connection, spec, passwords[key])
            for key, spec in scratch_logins.items()
        }
        states = {key: role_state(connection, spec.name) for key, spec in scratch_logins.items()}
        problems = group_role_problems(connection)

    assert all(result.created for result in results.values())
    assert {key: flags for key, (flags, _) in states.items()} == dict.fromkeys(
        scratch_logins, EXPECTED_FLAGS
    )
    assert {key: members for key, (_, members) in states.items()} == EXPECTED_MEMBERSHIPS
    assert problems == []
    for key, spec in scratch_logins.items():
        assert can_log_in(test_database_url, spec.name, passwords[key])
        line = results[key].describe()
        assert spec.name in line
        assert "********" in line
        assert passwords[key] not in line


def test_provision_is_idempotent_and_rotates_the_password(
    admin_engine_su: Engine, scratch_logins: dict[str, LoginRole], test_database_url: URL
) -> None:
    """A second run changes nothing but the password; the old password stops working."""
    spec = scratch_logins["worker"]
    old, new = secrets.token_urlsafe(24), secrets.token_urlsafe(24)
    with admin_engine_su.begin() as connection:
        provision_login_role(connection, spec, old)
        before = role_state(connection, spec.name)
    with admin_engine_su.begin() as connection:
        again = provision_login_role(connection, spec, new)
        after = role_state(connection, spec.name)

    assert (again.created, again.granted, again.revoked, again.attributes_changed) == (
        False,
        (),
        (),
        (),
    )
    assert after == before
    assert not can_log_in(test_database_url, spec.name, old)
    assert can_log_in(test_database_url, spec.name, new)


def test_provision_repairs_attributes_and_memberships(
    admin_engine_su: Engine, scratch_logins: dict[str, LoginRole]
) -> None:
    """An existing role with extra attributes, an extra membership and an inherited purge
    membership is brought back to the spec; the report names what changed."""
    spec = scratch_logins["worker"]
    with admin_engine_su.begin() as connection:
        connection.execute(text(f'CREATE ROLE "{spec.name}" LOGIN CREATEDB NOINHERIT'))
        connection.execute(text(f'GRANT cardflow_admin TO "{spec.name}"'))
        connection.execute(text(f'GRANT cardflow_purge TO "{spec.name}" WITH INHERIT TRUE'))
        assert any(
            spec.name in problem for problem in group_role_problems(connection)
        )  # inherited purge is reported before the repair
        result = provision_login_role(connection, spec, secrets.token_urlsafe(24))
        flags, members = role_state(connection, spec.name)

    assert result.created is False
    assert set(result.attributes_changed) == {"rolcreatedb", "rolinherit"}
    assert result.revoked == ("cardflow_admin",)
    assert flags == EXPECTED_FLAGS
    assert members == EXPECTED_MEMBERSHIPS["worker"]


def test_provision_refuses_short_passwords_and_superusers(
    admin_engine_su: Engine, scratch_logins: dict[str, LoginRole]
) -> None:
    spec = scratch_logins["api"]
    with admin_engine_su.begin() as connection:
        with pytest.raises(ProvisionError, match="shorter than 16"):
            provision_login_role(connection, spec, "short")
        connection.execute(text(f'CREATE ROLE "{spec.name}" NOLOGIN SUPERUSER'))
        with pytest.raises(ProvisionError, match="is a superuser"):
            provision_login_role(connection, spec, secrets.token_urlsafe(24))
        superuser = connection.execute(
            text("SELECT rolsuper FROM pg_roles WHERE rolname = :name"), {"name": spec.name}
        ).scalar_one()
        connection.execute(text(f'DROP ROLE "{spec.name}"'))

    assert superuser is True


@pytest.mark.parametrize(
    ("grant", "expected"),
    [
        (f"GRANT {ADMIN_VIEWS_ROLE} TO {{role}}", f"must not be a member of {ADMIN_VIEWS_ROLE}"),
        (f"GRANT {AUTH_LOOKUP_ROLE} TO {{role}}", f"must not be a member of {AUTH_LOOKUP_ROLE}"),
        (f"GRANT {PURGE_ROLE} TO {{role}} WITH INHERIT TRUE", f"inherits {PURGE_ROLE}"),
    ],
)
def test_group_role_problems_reports_unsafe_memberships(
    admin_engine_su: Engine, grant: str, expected: str
) -> None:
    """Nobody may act as the admin views' or the lookup functions' owner; purge rights must
    need SET ROLE."""
    role = f"cardflow_test_probe_{secrets.token_hex(4)}"
    with admin_engine_su.connect() as connection, connection.begin():
        connection.execute(text(f"CREATE ROLE {role} NOLOGIN"))
        connection.execute(text(grant.format(role=role)))
        problems = group_role_problems(connection)
        connection.rollback()

    found = [problem for problem in problems if role in problem]
    assert len(found) == 1
    assert found[0].startswith(f"{role} {expected}")


@pytest.fixture
def restore_root_logging() -> Iterator[None]:
    """``cardflow db-provision`` installs its own root log handler; undo that afterwards."""
    root = logging.getLogger()
    handlers, level = list(root.handlers), root.level
    yield
    root.handlers[:] = handlers
    root.setLevel(level)


def _secret_file(directory: Path, name: str, value: str) -> Path:
    path = directory / name
    path.write_text(value + "\n", encoding="utf-8")
    path.chmod(0o600)
    return path


def test_cli_db_provision_end_to_end(
    scratch_logins: dict[str, LoginRole],
    test_database_url: URL,
    clean_settings_env: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
    tmp_path: Path,
    restore_root_logging: None,
) -> None:
    """``cardflow db-provision`` with *_FILE secrets: exit 0, one line per role, passwords
    masked and never echoed; a rerun is idempotent; ``--role`` limits the run; a missing
    secret fails with exit 1 before anything changes."""
    del restore_root_logging
    monkeypatch = clean_settings_env
    monkeypatch.setattr(roles, "LOGIN_ROLES", scratch_logins)
    assert test_database_url.password is not None
    superuser_url = URL.create(
        drivername=test_database_url.drivername,
        username=test_database_url.username,
        host=test_database_url.host,
        port=test_database_url.port,
        database=test_database_url.database,
    )
    monkeypatch.setenv("DATABASE_URL", superuser_url.render_as_string(hide_password=False))
    monkeypatch.setenv(
        "DATABASE_PASSWORD_FILE",
        str(_secret_file(tmp_path, "db_password", test_database_url.password)),
    )
    passwords = {key: secrets.token_urlsafe(24) for key in scratch_logins}
    for key, password in passwords.items():
        monkeypatch.setenv(
            f"DATABASE_{key.upper()}_PASSWORD_FILE",
            str(_secret_file(tmp_path, f"db_{key}_password", password)),
        )

    first = main(["db-provision"])
    first_output = capsys.readouterr()
    second = main(["db-provision"])
    second_output = capsys.readouterr()
    only_api = main(["db-provision", "--role", "api"])
    only_api_output = capsys.readouterr()
    monkeypatch.delenv("DATABASE_ADMIN_PASSWORD_FILE")
    missing = main(["db-provision"])
    missing_output = capsys.readouterr()

    everything = "".join(
        part.out + part.err
        for part in (first_output, second_output, only_api_output, missing_output)
    )
    assert (first, second, only_api, missing) == (
        EXIT_OK,
        EXIT_OK,
        EXIT_OK,
        EXIT_PROVISION_FAILED,
    ), first_output.err
    assert first_output.out.count(": created; password ********") == 3
    assert second_output.out.count(": updated; password ********") == 3
    assert only_api_output.out.splitlines() == [
        line for line in second_output.out.splitlines() if scratch_logins["api"].name in line
    ]
    assert "DATABASE_ADMIN_PASSWORD_FILE" in missing_output.err
    assert test_database_url.password not in everything
    for key, password in passwords.items():
        assert password not in everything
        assert can_log_in(test_database_url, scratch_logins[key].name, password)
