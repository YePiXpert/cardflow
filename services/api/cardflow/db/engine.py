"""SQLAlchemy 2 engine and session factories for PostgreSQL (psycopg 3 driver only)."""

from __future__ import annotations

from typing import TYPE_CHECKING, Final

import sqlalchemy
from sqlalchemy.engine import URL, Engine, make_url
from sqlalchemy.exc import ArgumentError
from sqlalchemy.orm import Session, sessionmaker

if TYPE_CHECKING:
    from sqlalchemy.pool import Pool

    from cardflow.settings import Settings

DRIVERNAME: Final = "postgresql+psycopg"
_ALIASES: Final = frozenset({"postgresql", "postgres", DRIVERNAME})
DEFAULT_APPLICATION_NAME: Final = "cardflow"
DEFAULT_CONNECT_TIMEOUT_S: Final = 10


def normalize_database_url(url: str | URL) -> URL:
    """Parse ``url`` and force the psycopg 3 driver.

    ``postgresql://`` and ``postgres://`` become ``postgresql+psycopg://``; any other
    driver (psycopg2, asyncpg, sqlite, ...) is rejected. Error messages never echo the
    URL, so a password inside it cannot leak through exceptions.
    """
    try:
        parsed = make_url(url)
    except ArgumentError:
        raise ValueError("not a valid database URL") from None
    if parsed.drivername not in _ALIASES:
        raise ValueError(f"unsupported database driver {parsed.drivername!r}; use {DRIVERNAME}")
    return parsed.set(drivername=DRIVERNAME)


def database_url_from_settings(settings: Settings) -> URL:
    """Build the connection URL from ``DATABASE_URL`` plus the secret database password."""
    url = normalize_database_url(settings.database_url)
    if settings.database_password is not None:
        url = url.set(password=settings.database_password.get_secret_value())
    return url


def create_engine(
    url: str | URL,
    *,
    application_name: str = DEFAULT_APPLICATION_NAME,
    connect_timeout_s: int = DEFAULT_CONNECT_TIMEOUT_S,
    poolclass: type[Pool] | None = None,
) -> Engine:
    """Create an engine with pre-ping enabled; ``application_name`` shows in pg_stat_activity.

    ``poolclass=None`` keeps SQLAlchemy's default pool for the dialect.
    """
    return sqlalchemy.create_engine(
        normalize_database_url(url),
        pool_pre_ping=True,
        connect_args={"application_name": application_name, "connect_timeout": connect_timeout_s},
        poolclass=poolclass,
    )


def create_engine_from_settings(settings: Settings) -> Engine:
    """Create the application engine from :class:`cardflow.settings.Settings`."""
    return create_engine(database_url_from_settings(settings))


def create_session_factory(engine: Engine) -> sessionmaker[Session]:
    """Return a session factory bound to ``engine``.

    ``expire_on_commit=False``: objects stay readable after the workspace transaction has
    committed, instead of lazily re-loading in a new transaction that has no
    ``app.workspace_id`` bound (which row-level security would reject).
    """
    return sessionmaker(bind=engine, expire_on_commit=False)
