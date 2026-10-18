"""Fixtures for the identity tests (T-011).

* ``conn`` -- a superuser connection in a transaction that is rolled back after the test.
* ``rows`` / ``rows_class`` -- a tiny row factory (users, workspaces, devices, any table via
  ``insert``) for the identity schema tests; the full business row factory lives in
  tests/db/conftest.py and is not visible from here.
"""

import uuid
from collections.abc import Iterator

import pytest
from sqlalchemy import insert
from sqlalchemy.engine import Connection, Engine

from cardflow.db.models import metadata


class IdentityRows:
    """Minimal valid identity rows (Core inserts, superuser)."""

    def __init__(self, connection: Connection) -> None:
        self.connection = connection

    def insert(self, table: str, **values: object) -> uuid.UUID:
        target = metadata.tables[table]
        return self.connection.execute(
            insert(target).values(**values).returning(target.c.id)
        ).scalar_one()

    def workspace(self) -> uuid.UUID:
        return self.insert("workspaces", owner_user_id=self.insert("users"), kind="real")

    def device(self, workspace_id: uuid.UUID) -> uuid.UUID:
        return self.insert(
            "devices", workspace_id=workspace_id, platform="android", public_key=b"k" * 32
        )


@pytest.fixture
def conn(db_engine: Engine) -> Iterator[Connection]:
    """Superuser connection in a transaction that is always rolled back."""
    with db_engine.connect() as connection:
        transaction = connection.begin()
        try:
            yield connection
        finally:
            transaction.rollback()


@pytest.fixture
def rows(conn: Connection) -> IdentityRows:
    """Row factory on the rolled-back ``conn`` transaction."""
    return IdentityRows(conn)


@pytest.fixture(scope="session")
def rows_class() -> type[IdentityRows]:
    """The :class:`IdentityRows` class, for connections the test opens itself."""
    return IdentityRows
