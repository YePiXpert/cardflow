"""Alembic environment for the CardFlow schema.

URL resolution (first match wins):

1. ``config.attributes["connection"]`` -- an open SQLAlchemy connection supplied by the
   caller (shared-connection recipe); it is used as-is and not closed here;
2. ``-x url=postgresql+psycopg://user:password@host:port/db`` on the alembic command line
   (tests and tools; e.g. ``uv run alembic -x url=... upgrade head``);
3. ``config.attributes["database_url"]`` -- set by :mod:`cardflow.db.migrations`
   (``cardflow migrate``) from the settings;
4. :mod:`cardflow.settings`: ``DATABASE_URL`` plus ``DATABASE_PASSWORD``/``_FILE``.

``config.attributes["configure_logger"] = False`` keeps the caller's logging setup (the
``cardflow`` CLI installs its JSON handler); otherwise ``alembic.ini`` configures logging.
"""

from logging.config import fileConfig

from sqlalchemy.engine import URL, Connection
from sqlalchemy.pool import NullPool

from alembic import context
from cardflow.db.engine import create_engine, database_url_from_settings, normalize_database_url
from cardflow.db.migrations import COMPARE_OPTIONS, MIGRATE_APPLICATION_NAME
from cardflow.db.models import metadata

config = context.config

if config.config_file_name is not None and config.attributes.get("configure_logger", True):
    fileConfig(config.config_file_name, disable_existing_loggers=False)

target_metadata = metadata


def _database_url() -> URL:
    x_url = context.get_x_argument(as_dictionary=True).get("url")
    if x_url:
        return normalize_database_url(x_url)
    configured = config.attributes.get("database_url")
    if configured is not None:
        return normalize_database_url(configured)
    # Imported lazily: reading settings may fail (missing secrets) and is only needed here.
    from cardflow.settings import get_settings

    return database_url_from_settings(get_settings())


def _configure(connection: Connection) -> None:
    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        transaction_per_migration=True,
        **COMPARE_OPTIONS,
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_offline() -> None:
    """Emit the SQL instead of executing it (``alembic upgrade head --sql``)."""
    context.configure(
        url=_database_url().render_as_string(hide_password=False),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        transaction_per_migration=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Run the migrations on a live connection."""
    connection = config.attributes.get("connection")
    if connection is not None:
        _configure(connection)
        return
    engine = create_engine(
        _database_url(), application_name=MIGRATE_APPLICATION_NAME, poolclass=NullPool
    )
    try:
        with engine.connect() as connection:
            _configure(connection)
    finally:
        engine.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
