"""Revision 0004 in the database: pairing_codes, the lookup functions and their owner, the
API's row-level security on pairing codes and the new columns. (The snapshot tombstone rule
of 0004 is tested with the other fact-table rules: tests/db/test_snapshot_tombstone.py.)

Constraint and trigger checks run as the superuser in rolled-back transactions; privilege
and policy checks run as the temporary role logins of tests/conftest.py (cardflow_api-like
``app_engine`` and friends) against rows the superuser committed.
"""

import uuid
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from typing import TYPE_CHECKING, Final

import pytest
from sqlalchemy import delete, func, insert, select, text, update
from sqlalchemy.engine import Connection, Engine
from sqlalchemy.exc import DBAPIError
from sqlalchemy.sql import Executable

from cardflow.db.models import metadata
from cardflow.db.roles import AUTH_LOOKUP_ROLE, group_role_problems
from cardflow.identity.pairing import pairing_code_hash

if TYPE_CHECKING:
    from tests.identity.conftest import IdentityRows

pytestmark = [pytest.mark.db, pytest.mark.usefixtures("require_head_schema")]

T: Final = metadata.tables
CODES: Final = metadata.tables["pairing_codes"]
CHECK_VIOLATION: Final = "23514"
UNIQUE_VIOLATION: Final = "23505"
INTEGRITY_CONSTRAINT_VIOLATION: Final = "23000"
INSUFFICIENT_PRIVILEGE: Final = "42501"
OK: Final = (None, None)
BIND: Final = text(
    "SELECT set_config('app.workspace_id', :workspace, true), "
    "set_config('app.pairing_code_id', :code, true)"
)

Outcome = tuple[str | None, str | None]


def failure(connection: Connection, action: Callable[[], object]) -> Outcome:
    """Run ``action`` in a savepoint; (SQLSTATE, constraint) of its failure, or OK."""
    try:
        with connection.begin_nested():
            action()
    except DBAPIError as exc:
        diag = getattr(exc.orig, "diag", None)
        return getattr(exc.orig, "sqlstate", None), getattr(diag, "constraint_name", None)
    return OK


def new_code(
    connection: Connection, workspace_id: uuid.UUID | None = None, **values: object
) -> uuid.UUID:
    row: dict[str, object] = {
        "purpose": "bootstrap_workspace" if workspace_id is None else "join_workspace",
        "workspace_id": workspace_id,
        "code_hash": uuid.uuid4().hex * 2,
        "created_via": "cli",
        "expires_at": func.now() + timedelta(minutes=10),
    }
    row.update(values)
    return connection.execute(insert(CODES).values(**row).returning(CODES.c.id)).scalar_one()


def claim(workspace_id: uuid.UUID, device_id: uuid.UUID) -> dict[str, object]:
    return {
        "used_at": func.now(),
        "used_workspace_id": workspace_id,
        "used_by_device_id": device_id,
        "used_key_hash": "a" * 64,
        "used_request_hash": "b" * 64,
    }


# --- pairing_codes: constraints and triggers ---------------------------------------------------


def test_pairing_code_constraints(conn: Connection, rows: "IdentityRows") -> None:
    workspace, other = rows.workspace(), rows.workspace()
    used_elsewhere = claim(other, rows.device(other))
    taken = uuid.uuid4().hex * 2
    new_code(conn, code_hash=taken)
    late = {**used_elsewhere, "used_at": func.now() + timedelta(hours=1)}
    cases: dict[str, tuple[Callable[[], object], Outcome]] = {
        "bootstrap with a workspace": (
            lambda: new_code(conn, purpose="bootstrap_workspace", workspace_id=workspace),
            (CHECK_VIOLATION, "ck_pairing_codes_workspace_matches_purpose"),
        ),
        "join without a workspace": (
            lambda: new_code(conn, purpose="join_workspace"),
            (CHECK_VIOLATION, "ck_pairing_codes_workspace_matches_purpose"),
        ),
        "lifetime over 24 hours": (
            lambda: new_code(conn, expires_at=func.now() + timedelta(hours=24, seconds=1)),
            (CHECK_VIOLATION, "ck_pairing_codes_lifetime"),
        ),
        "expired at creation": (
            lambda: new_code(conn, expires_at=func.now()),
            (CHECK_VIOLATION, "ck_pairing_codes_lifetime"),
        ),
        "hash not hex": (
            lambda: new_code(conn, code_hash="Z" * 64),
            (CHECK_VIOLATION, "ck_pairing_codes_code_hash_hex"),
        ),
        "duplicate hash": (
            lambda: new_code(conn, code_hash=taken),
            (UNIQUE_VIOLATION, "uq_pairing_codes_code_hash"),
        ),
        "unknown creator": (
            lambda: new_code(conn, created_via="web"),
            (CHECK_VIOLATION, "ck_pairing_codes_created_via"),
        ),
        "partial use": (
            lambda: new_code(conn, used_at=func.now()),
            (CHECK_VIOLATION, "ck_pairing_codes_use_recorded_together"),
        ),
        "join code used in another workspace": (
            lambda: new_code(conn, workspace, **used_elsewhere),
            (CHECK_VIOLATION, "ck_pairing_codes_used_in_own_workspace"),
        ),
        "used after expiry": (
            lambda: new_code(conn, **late),
            (CHECK_VIOLATION, "ck_pairing_codes_used_before_expiry"),
        ),
        "used bootstrap code": (lambda: new_code(conn, **used_elsewhere), OK),
    }

    found = {name: failure(conn, action) for name, (action, _) in cases.items()}

    assert found == {name: expected for name, (_, expected) in cases.items()}


def test_used_codes_are_frozen_and_code_identity_never_changes(
    conn: Connection, rows: "IdentityRows"
) -> None:
    """Even for the superuser: a used code keeps its use (no re-arming), and no code ever
    changes its purpose, workspace, hash, creator or expiry."""
    workspace = rows.workspace()
    use = claim(workspace, rows.device(workspace))
    unused, used = new_code(conn), new_code(conn)
    conn.execute(update(CODES).where(CODES.c.id == used).values(**use))

    def change(code: uuid.UUID, **values: object) -> Callable[[], object]:
        return lambda: conn.execute(update(CODES).where(CODES.c.id == code).values(**values))

    rearm = dict.fromkeys(use, None)
    frozen = (INTEGRITY_CONSTRAINT_VIOLATION, "pairing_codes_single_use")
    fixed = (INTEGRITY_CONSTRAINT_VIOLATION, "pairing_codes_immutable")
    assert failure(conn, change(used, **rearm)) == frozen
    assert failure(conn, change(used, used_key_hash="c" * 64)) == frozen
    assert failure(conn, change(unused, expires_at=func.now() + timedelta(hours=1))) == fixed
    assert failure(conn, change(unused, code_hash="d" * 64)) == fixed
    assert failure(conn, change(unused, purpose="join_workspace")) == fixed
    assert failure(conn, change(unused, **use)) == OK  # unused -> used, once


def test_device_app_version_and_session_key_hash_are_checked(
    conn: Connection, rows: "IdentityRows"
) -> None:
    workspace = rows.workspace()
    device = rows.device(workspace)
    devices, sessions = T["devices"], T["auth_sessions"]

    def app_version(value: str) -> Callable[[], object]:
        return lambda: conn.execute(
            update(devices).where(devices.c.id == device).values(app_version=value)
        )

    def session(key_hash: str) -> Callable[[], object]:
        return lambda: conn.execute(
            insert(sessions).values(
                workspace_id=workspace,
                device_id=device,
                refresh_token_hash=uuid.uuid4().hex * 2,
                expires_at=func.now() + timedelta(days=1),
                idempotency_key_hash=key_hash,
            )
        )

    assert failure(conn, app_version("1.2.3+45")) == OK
    assert failure(conn, app_version("1.2.3 beta")) == (
        CHECK_VIOLATION,
        "ck_devices_app_version_format",
    )
    assert failure(conn, app_version("1.0.0-4111111111111111")) == (
        CHECK_VIOLATION,
        "ck_devices_app_version_not_pan",
    )
    assert failure(conn, session("e" * 64)) == OK
    assert failure(conn, session("E" * 64)) == (
        CHECK_VIOLATION,
        "ck_auth_sessions_idempotency_key_hash_hex",
    )


def test_stored_hash_is_the_documented_one(conn: Connection) -> None:
    """The CLI and the API agree on the stored form (SHA-256 of label + normalised code)."""
    code_id = new_code(conn, code_hash=pairing_code_hash("7K2M9QXT4B8R"))
    stored = conn.execute(select(CODES.c.code_hash).where(CODES.c.id == code_id)).scalar_one()
    assert stored == pairing_code_hash("7K2M9QXT4B8R")
    assert "7K2M9QXT4B8R" not in stored


# --- lookup functions and their owner ------------------------------------------------------------


class Committed:
    """Committed rows: workspace A (device, session, join code), workspace B (join code), a
    used and an unused bootstrap code."""

    def __init__(self, connection: Connection, rows: "IdentityRows") -> None:
        self.a, self.b = rows.workspace(), rows.workspace()
        self.device = rows.device(self.a)
        self.session = rows.insert(
            "auth_sessions",
            workspace_id=self.a,
            device_id=self.device,
            refresh_token_hash=uuid.uuid4().hex * 2,
            expires_at=datetime.now(UTC) + timedelta(days=1),
        )
        self.hashes = {
            name: uuid.uuid4().hex * 2 for name in ("join_a", "join_b", "used", "unused")
        }
        self.ids = {
            "join_a": new_code(connection, self.a, code_hash=self.hashes["join_a"]),
            "join_b": new_code(connection, self.b, code_hash=self.hashes["join_b"]),
            "unused": new_code(connection, code_hash=self.hashes["unused"]),
            "used": new_code(
                connection, code_hash=self.hashes["used"], **claim(self.a, self.device)
            ),
        }
        self.token_hash = connection.execute(
            select(T["auth_sessions"].c.refresh_token_hash).where(
                T["auth_sessions"].c.id == self.session
            )
        ).scalar_one()


@pytest.fixture
def committed(db_engine: Engine, rows_class: "type[IdentityRows]") -> Committed:
    with db_engine.begin() as connection:
        return Committed(connection, rows_class(connection))


def test_lookup_functions_return_only_what_binds_a_workspace(
    app_engine: Engine, committed: Committed
) -> None:
    """As the API: the pairing lookup gives (code id, workspace to bind) -- the new workspace
    for a used bootstrap code, NULL for an unused one; the token lookup (session id,
    workspace id). Nothing for unknown hashes, no other column."""
    pairing_sql = text("SELECT * FROM public.resolve_pairing_code(:h)")
    with app_engine.connect() as connection:
        columns = list(connection.execute(pairing_sql, {"h": committed.hashes["used"]}).keys())
        found = {
            name: tuple(connection.execute(pairing_sql, {"h": value}).one())
            for name, value in committed.hashes.items()
        }
        unknown = connection.execute(pairing_sql, {"h": "0" * 64}).all()
        token = connection.execute(
            text("SELECT * FROM public.resolve_refresh_token(:h)"), {"h": committed.token_hash}
        )
        token_columns = list(token.keys())
        session = tuple(token.one())

    assert columns == ["pairing_code_id", "workspace_id"]
    assert found == {
        "join_a": (committed.ids["join_a"], committed.a),
        "join_b": (committed.ids["join_b"], committed.b),
        "used": (committed.ids["used"], committed.a),
        "unused": (committed.ids["unused"], None),
    }
    assert unknown == []
    assert token_columns == ["session_id", "workspace_id"]
    assert session == (committed.session, committed.a)


@pytest.mark.parametrize("engine_name", ["worker_engine", "admin_engine", "purge_capable_engine"])
def test_only_the_api_may_call_the_lookups(
    engine_name: str, request: pytest.FixtureRequest, committed: Committed
) -> None:
    engine: Engine = request.getfixturevalue(engine_name)
    for function in ("resolve_pairing_code", "resolve_refresh_token"):
        statement = text(f"SELECT * FROM public.{function}(:h)")  # noqa: S608 - fixed names
        with engine.connect() as connection:
            outcome = failure(
                connection,
                lambda statement=statement: connection.execute(
                    statement, {"h": committed.token_hash}
                ),
            )
        assert outcome[0] == INSUFFICIENT_PRIVILEGE, (engine_name, function)


def test_lookup_owner_reads_nothing_but_its_columns_and_has_no_members(db_engine: Engine) -> None:
    """cardflow_auth_lookup: NOLOGIN, no attributes, no members; acting as it (only a
    superuser can) shows that only the declared columns are readable and nothing writable."""
    with db_engine.connect() as connection, connection.begin() as transaction:
        flags = connection.execute(
            text(
                "SELECT rolcanlogin, rolsuper, rolbypassrls, rolcreaterole, rolcreatedb, "
                "rolreplication FROM pg_roles WHERE rolname = :role"
            ),
            {"role": AUTH_LOOKUP_ROLE},
        ).one()
        members = connection.execute(
            text("SELECT count(*) FROM pg_auth_members WHERE roleid = CAST(:role AS regrole)"),
            {"role": AUTH_LOOKUP_ROLE},
        ).scalar_one()
        problems = group_role_problems(connection)
        connection.execute(text(f"SET LOCAL ROLE {AUTH_LOOKUP_ROLE}"))
        readable = [
            failure(connection, lambda statement=statement: connection.execute(text(statement)))
            for statement in (
                "SELECT id, workspace_id, refresh_token_hash FROM auth_sessions LIMIT 1",
                "SELECT id, workspace_id, used_workspace_id, code_hash FROM pairing_codes LIMIT 1",
            )
        ]
        denied = {
            statement: failure(
                connection, lambda statement=statement: connection.execute(text(statement))
            )[0]
            for statement in (
                "SELECT expires_at FROM auth_sessions LIMIT 1",
                "SELECT device_id FROM auth_sessions LIMIT 1",
                "SELECT used_key_hash FROM pairing_codes LIMIT 1",
                "SELECT expires_at FROM pairing_codes LIMIT 1",
                "SELECT id FROM devices LIMIT 1",
                "SELECT id FROM workspaces LIMIT 1",
                "UPDATE auth_sessions SET revoked_at = now()",
                "SELECT * FROM public.resolve_refresh_token(repeat('a', 64))",
            )
        }
        transaction.rollback()

    assert tuple(flags) == (False,) * 6
    assert members == 0
    assert problems == []
    assert readable == [OK, OK]
    assert denied == dict.fromkeys(denied, INSUFFICIENT_PRIVILEGE)


# --- the API's view of pairing codes (RLS) -----------------------------------------------------


def as_app(
    app_engine: Engine,
    workspace: uuid.UUID | None,
    code: uuid.UUID | None,
    statement: Executable,
) -> tuple[object, Outcome]:
    """Run ``statement`` as the API bound to ``workspace`` and ``code`` (rolled back)."""
    result: list[object] = []
    with app_engine.connect() as connection, connection.begin() as transaction:
        connection.execute(BIND, {"workspace": str(workspace or ""), "code": str(code or "")})
        outcome = failure(connection, lambda: result.append(connection.execute(statement)))
        value = result[0].scalar() if result and result[0].returns_rows else None  # type: ignore[attr-defined]
        transaction.rollback()
    return value, outcome


def test_api_sees_a_code_only_while_bound_to_it_and_its_workspace(
    app_engine: Engine, committed: Committed
) -> None:
    a, b, ids = committed.a, committed.b, committed.ids

    def visible(workspace: uuid.UUID | None, bound: uuid.UUID | None, code: uuid.UUID) -> object:
        statement = select(func.count()).select_from(CODES).where(CODES.c.id == code)
        return as_app(app_engine, workspace, bound, statement)[0]

    seen = {
        "join A, bound to A and the code": visible(a, ids["join_a"], ids["join_a"]),
        "join A, bound to A only": visible(a, None, ids["join_a"]),
        "join A, bound to B and the code": visible(b, ids["join_a"], ids["join_a"]),
        "join A, another code bound": visible(a, ids["join_b"], ids["join_a"]),
        "used bootstrap, bound to its workspace": visible(a, ids["used"], ids["used"]),
        "used bootstrap, bound to B": visible(b, ids["used"], ids["used"]),
        "unused bootstrap, any workspace": visible(uuid.uuid4(), ids["unused"], ids["unused"]),
        "unused bootstrap, no workspace": visible(None, ids["unused"], ids["unused"]),
    }
    assert seen == {
        "join A, bound to A and the code": 1,
        "join A, bound to A only": 0,
        "join A, bound to B and the code": 0,
        "join A, another code bound": 0,
        "used bootstrap, bound to its workspace": 1,
        "used bootstrap, bound to B": 0,
        "unused bootstrap, any workspace": 1,
        "unused bootstrap, no workspace": 0,
    }


def test_api_may_only_record_a_use(app_engine: Engine, committed: Committed) -> None:
    """No INSERT, no DELETE, no change of a code's identity, no reading its hash; the
    recorded workspace must be the bound one (WITH CHECK)."""
    a, unused = committed.a, committed.ids["unused"]
    use = claim(a, committed.device)
    this_code = CODES.c.id == unused

    def run(statement: Executable, workspace: uuid.UUID = a) -> Outcome:
        return as_app(app_engine, workspace, unused, statement)[1]

    outcomes = {
        "insert": run(
            insert(CODES).values(
                purpose="bootstrap_workspace",
                code_hash="f" * 64,
                created_via="cli",
                expires_at=func.now() + timedelta(minutes=5),
            )
        ),
        "delete": run(delete(CODES).where(this_code)),
        "extend": run(
            update(CODES).where(this_code).values(expires_at=func.now() + timedelta(hours=1))
        ),
        "read hash": run(select(CODES.c.code_hash).where(this_code)),
        "record use elsewhere": run(update(CODES).where(this_code).values(**use), uuid.uuid4()),
        "record use": run(update(CODES).where(this_code).values(**use)),
    }

    assert {name: outcome[0] for name, outcome in outcomes.items()} == {
        "insert": INSUFFICIENT_PRIVILEGE,
        "delete": INSUFFICIENT_PRIVILEGE,
        "extend": INSUFFICIENT_PRIVILEGE,
        "read hash": INSUFFICIENT_PRIVILEGE,
        "record use elsewhere": INSUFFICIENT_PRIVILEGE,
        "record use": None,
    }


def test_purge_deletes_the_codes_of_the_purged_workspace_only(
    purge_capable_engine: Engine, committed: Committed, db_engine: Engine
) -> None:
    ids = committed.ids
    with purge_capable_engine.connect() as connection, connection.begin() as transaction:
        connection.execute(text("SET LOCAL ROLE cardflow_purge"))
        connection.execute(BIND, {"workspace": str(committed.a), "code": ""})
        deleted = set(connection.execute(delete(CODES).returning(CODES.c.id)).scalars())
        transaction.rollback()
    with db_engine.connect() as connection:
        still_there = set(
            connection.execute(
                select(CODES.c.id).where(CODES.c.id.in_(list(ids.values())))
            ).scalars()
        )

    assert deleted == {ids["join_a"], ids["used"]}
    assert still_there == set(ids.values())  # rolled back
