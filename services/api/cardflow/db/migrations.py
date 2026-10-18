"""Alembic integration: configuration, revision status and (locked) upgrades.

Used by ``cardflow migrate`` (T-005), by the test suite (``prepare_test_database``) and,
for readiness, by ``/readyz`` (T-012)::

    with engine.connect() as connection:
        status = migration_status(connection)
    status.up_to_date            # database revision == code head
    status.current, status.heads # e.g. ("0001",), ("0001",)

``migration_status`` only reads ``alembic_version``: whatever role ``/readyz`` connects as
needs SELECT on that table, which the roles/RLS revision 0003, T-006 grants to cardflow_app,
cardflow_worker and cardflow_admin (with SELECT on worker_heartbeats for the heartbeat
check). Migrations themselves must run as a superuser (they create roles and grants).
"""

import logging
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any, Final

from alembic.config import Config
from alembic.script import ScriptDirectory
from sqlalchemy import func, select, text
from sqlalchemy.engine import URL, Connection
from sqlalchemy.pool import NullPool

from alembic import command
from cardflow.db.engine import create_engine, normalize_database_url

log = logging.getLogger(__name__)

API_ROOT: Final = Path(__file__).resolve().parents[2]
"""``services/api``: holds ``alembic.ini`` and the ``alembic/`` script directory."""
ALEMBIC_INI: Final = API_ROOT / "alembic.ini"
MIGRATE_APPLICATION_NAME: Final = "cardflow-migrate"
MIGRATION_LOCK_KEY: Final = 0x63617264666C6F77
"""``pg_advisory_lock`` key of ``cardflow migrate --lock``: the ASCII bytes of "cardflow"."""

# Autogenerate comparison options shared by env.py and tests/db/test_model_drift.py.
COMPARE_OPTIONS: Final[dict[str, Any]] = {"compare_type": True, "compare_server_default": True}
VERSION_TABLE: Final = "alembic_version"
_VERSION_TABLE_EXISTS: Final = text(f"SELECT to_regclass('{VERSION_TABLE}') IS NOT NULL")
_VERSION_NUMBERS: Final = text(f"SELECT version_num FROM {VERSION_TABLE}")  # noqa: S608


@dataclass(frozen=True)
class MigrationStatus:
    """Revision(s) recorded in the database versus the head(s) shipped with this code."""

    current: tuple[str, ...]
    heads: tuple[str, ...]

    @property
    def up_to_date(self) -> bool:
        """True when the database is exactly at the code's head revision(s)."""
        return bool(self.heads) and self.current == self.heads


def alembic_config(url: str | URL | None = None, *, ini_path: Path = ALEMBIC_INI) -> Config:
    """Alembic :class:`Config` for ``ini_path``; ``url`` (if given) is the target database.

    The URL travels in ``config.attributes`` rather than ``sqlalchemy.url`` so that a
    password is never written into (or %-interpolated by) the ini parser. Logging is left
    to the caller.
    """
    if not ini_path.is_file():
        raise FileNotFoundError(f"Alembic configuration not found: {ini_path}")
    config = Config(str(ini_path))
    config.attributes["configure_logger"] = False
    if url is not None:
        config.attributes["database_url"] = normalize_database_url(url)
    return config


@lru_cache(maxsize=1)
def head_revisions() -> tuple[str, ...]:
    """Head revision id(s) of the migration scripts shipped with this code (cached)."""
    return tuple(sorted(ScriptDirectory.from_config(alembic_config()).get_heads()))


def resolve_revision(target: str) -> str | None:
    """Revision id for ``target`` (``"head"``, ``"0001"``, ...); ``None`` for ``"base"``.

    Raises :class:`alembic.util.CommandError` for an unknown revision.
    """
    script = ScriptDirectory.from_config(alembic_config())
    revision = script.get_revision(target)
    return None if revision is None else revision.revision


def database_revisions(connection: Connection) -> tuple[str, ...]:
    """Revision id(s) stored in ``alembic_version``; empty if the schema was never migrated.

    Plain SQL instead of Alembic's MigrationContext: same answer for our (default) version
    table, but no INFO log lines on every ``/readyz`` probe.
    """
    if not connection.execute(_VERSION_TABLE_EXISTS).scalar_one():
        return ()
    return tuple(sorted(connection.execute(_VERSION_NUMBERS).scalars()))


def migration_status(connection: Connection) -> MigrationStatus:
    """Compare the database revision with the code's head (``/readyz``, ``migrate --check``)."""
    return MigrationStatus(current=database_revisions(connection), heads=head_revisions())


@contextmanager
def migration_lock(url: str | URL) -> Iterator[None]:
    """Hold the session-level advisory lock :data:`MIGRATION_LOCK_KEY` for the block.

    The lock lives on a dedicated autocommit connection, so it survives the migration's
    own transactions and is released even if the process dies (the session ends).
    """
    engine = create_engine(url, application_name=MIGRATE_APPLICATION_NAME, poolclass=NullPool)
    try:
        with engine.connect() as connection:
            connection.execution_options(isolation_level="AUTOCOMMIT")
            log.info("waiting for the migration advisory lock")
            connection.execute(select(func.pg_advisory_lock(MIGRATION_LOCK_KEY)))
            log.info("migration advisory lock acquired")
            try:
                yield
            finally:
                connection.execute(select(func.pg_advisory_unlock(MIGRATION_LOCK_KEY)))
                log.info("migration advisory lock released")
    finally:
        engine.dispose()


def upgrade(url: str | URL, target: str = "head", *, lock: bool = False) -> None:
    """Upgrade the database at ``url`` to ``target``; with ``lock`` under the advisory lock."""
    config = alembic_config(url)
    if not lock:
        command.upgrade(config, target)
        return
    with migration_lock(url):
        command.upgrade(config, target)


def downgrade(url: str | URL, target: str) -> None:
    """Downgrade the database at ``url`` to ``target`` (``"base"`` drops the schema)."""
    command.downgrade(alembic_config(url), target)
