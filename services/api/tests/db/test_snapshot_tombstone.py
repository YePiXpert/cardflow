"""data-model §10.13 (revision 0004, T-011): limit_snapshots and cash_balance_snapshots take
the tombstone once, like the five immutable fact tables.

Before 0004 only the amount, time and account columns of a snapshot were frozen (0002), so a
tombstoned snapshot could be revived (deleted_at back to NULL) or re-dated. Each case runs
first on a database at revision 0003 (the old behaviour) and then on the session database
at head, as the superuser -- the trigger holds for every role, not only through grants.
"""

import uuid
from collections.abc import Callable, Iterator
from datetime import UTC, datetime
from typing import TYPE_CHECKING, Any, Final

import pytest
from sqlalchemy import func, update
from sqlalchemy.engine import Connection, Engine
from sqlalchemy.exc import DBAPIError
from sqlalchemy.pool import NullPool

from cardflow.db.engine import create_engine
from cardflow.db.migrations import upgrade
from cardflow.db.models import metadata

if TYPE_CHECKING:
    from tests.db.conftest import DatabaseFactory, Rows

pytestmark = [pytest.mark.db, pytest.mark.usefixtures("require_head_schema")]

T: Final = metadata.tables
INTEGRITY_CONSTRAINT_VIOLATION: Final = "23000"
OK: Final = (None, None)
SNAPSHOT_TABLES: Final = ("limit_snapshots", "cash_balance_snapshots")


@pytest.fixture(scope="module")
def engine_0003(temporary_databases: "DatabaseFactory") -> Iterator[Engine]:
    """A database at revision 0003, to show the behaviour 0004 changes."""
    url = temporary_databases.create()
    try:
        upgrade(url, "0003")
        engine = create_engine(url, poolclass=NullPool)
        yield engine
        engine.dispose()
    finally:
        temporary_databases.drop(url)


def _snapshot(rows: "Rows", table: str) -> uuid.UUID:
    if table == "limit_snapshots":
        return rows.limit_snapshot(rows.account())
    workspace = rows.workspace()
    return rows.cash_snapshot(workspace, rows.cash_account(workspace))


def _attempt(connection: Connection, action: Callable[[], object]) -> tuple[str | None, str | None]:
    try:
        with connection.begin_nested():
            action()
    except DBAPIError as exc:
        diag = getattr(exc.orig, "diag", None)
        return getattr(exc.orig, "sqlstate", None), getattr(diag, "constraint_name", None)
    return OK


@pytest.mark.parametrize("table", SNAPSHOT_TABLES)
def test_snapshot_tombstone_is_set_once_and_never_undone(
    table: str, db_engine: Engine, engine_0003: Engine, rows_class: "type[Rows]"
) -> None:
    """0003: revive and re-date were possible. Head: deleted_at goes from NULL to a value
    once and the tombstoned row is frozen; a live snapshot keeps its other non-amount
    columns editable (the trigger fires only for tombstoned rows)."""
    target = T[table]
    results: dict[str, list[tuple[str | None, str | None]]] = {}
    for name, engine in (("0003", engine_0003), ("head", db_engine)):
        with engine.connect() as connection, connection.begin() as transaction:
            snapshot = _snapshot(rows_class(connection), table)

            def change(snapshot: uuid.UUID = snapshot, **values: Any) -> Callable[[], object]:  # noqa: ANN401
                return lambda: connection.execute(
                    update(target).where(target.c.id == snapshot).values(**values)
                )

            results[name] = [
                _attempt(connection, change(confirmation_level="bank_confirmed")),
                _attempt(connection, change(deleted_at=func.now())),
                _attempt(connection, change(deleted_at=None)),
                _attempt(connection, change(deleted_at=datetime(2030, 1, 1, tzinfo=UTC))),
                _attempt(connection, change(confirmation_level="user_confirmed")),
            ]
            transaction.rollback()

    frozen = (INTEGRITY_CONSTRAINT_VIOLATION, f"{table}_tombstone_once")
    assert results["0003"] == [OK, OK, OK, OK, OK]
    assert results["head"] == [OK, OK, frozen, frozen, frozen]
