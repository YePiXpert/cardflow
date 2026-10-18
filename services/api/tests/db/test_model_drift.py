"""The SQLAlchemy models (``cardflow.db.models``) describe exactly the migrated schema.

Three layers, all on the session database migrated to head (``require_head_schema``):

1. ``alembic.autogenerate.compare_metadata`` must report no difference (column types,
   nullability, server defaults, indexes and unique constraints by name, foreign-key
   structure incl. ON DELETE / DEFERRABLE).
2. Autogenerate is blind to several things. Probed against Alembic 1.20 by removing or
   changing them in the metadata (no difference was reported):
   :data:`AUTOGENERATE_BLIND_SPOTS`. Those that models CAN express are compared here
   anyway: a second database is built straight from the models (``metadata.create_all``)
   and PostgreSQL's own normalised definitions (``pg_get_constraintdef``,
   ``pg_get_indexdef``, ``format_type``, column defaults) must be identical, object by
   object, to the migrated database.
3. :data:`NOT_IN_MODELS` lists what the models cannot express at all; each entry is
   verified to exist in the migrated database instead -- against expectations derived
   from the code (review R2-30): ``head_revisions()``, the golden trigger/function
   manifest, the revisions' extensions and the engine's ``MINOR_DIGITS``.
"""

from collections.abc import Iterator
from typing import TYPE_CHECKING, Final, Protocol

import pytest
from alembic.autogenerate import compare_metadata
from alembic.runtime.migration import MigrationContext
from sqlalchemy import text
from sqlalchemy.engine import URL, Connection, Engine
from sqlalchemy.pool import NullPool

from cardflow.db.engine import create_engine
from cardflow.db.migrations import COMPARE_OPTIONS, database_revisions, head_revisions
from cardflow.db.models import metadata
from cardflow.planner.engine.money import MINOR_DIGITS

if TYPE_CHECKING:
    from tests.db.conftest import DbObjects, MigrationScripts

pytestmark = [pytest.mark.db, pytest.mark.usefixtures("require_head_schema")]

POSTGRES_MAX_IDENTIFIER: Final = 63

# Known exemption 1: things `compare_metadata` does not see (layer 2 compares them).
AUTOGENERATE_BLIND_SPOTS: Final[dict[str, str]] = {
    "CHECK constraints": "compared via pg_get_constraintdef (contype 'c')",
    "EXCLUDE constraints (billing_rule_versions, rule_bindings)": (
        "compared via pg_get_constraintdef ('x')"
    ),
    "partial-index predicates (WHERE deleted_at IS NULL natural keys, jobs, ...)": (
        "compared via pg_get_indexdef"
    ),
    "index access method and operator class (gin_trgm_ops), DESC ordering": (
        "compared via pg_get_indexdef"
    ),
    "foreign-key constraint names": "compared via pg_constraint.conname",
    "primary keys": "compared via pg_get_constraintdef (contype 'p')",
}

# Known exemption 2: objects the models cannot express; verified to exist in the database.
NOT_IN_MODELS: Final[dict[str, str]] = {
    "trigger functions and triggers (T-007, 0002)": "fingerprinted against "
    "golden_objects.json (tests/db/test_db_objects.py); constraint triggers also appear in "
    "pg_constraint (contype 't') and are excluded from layer 2 when the manifest lists them",
    "extensions (btree_gist, pg_trgm)": "created by 0001 if missing and never dropped "
    "(environment prerequisite, R2-23); create_all needs them too, taken from the "
    "revisions' UPGRADE statements",
    "currencies seed rows": "data, not schema; equal to the engine's MINOR_DIGITS",
    "alembic_version table": "Alembic bookkeeping",
    "roles, grants, row-level security, policies, schema admin and its views (0003)": (
        "checked against the declarative maps of the revision in "
        "tests/db/test_rls_grants.py and by behaviour in tests/db/test_rls.py"
    ),
}


class DatabaseFactory(Protocol):
    """What ``temporary_databases`` (root conftest) offers."""

    def create(self) -> URL:
        """Create an empty database."""
        ...

    def drop(self, url: URL) -> None:
        """Drop a database created by :meth:`create`."""
        ...


@pytest.fixture(scope="module")
def model_database(
    temporary_databases: DatabaseFactory, migration_scripts: "MigrationScripts"
) -> Iterator[Engine]:
    """A database built only from the models (no Alembic), for layer 2. Extensions and the
    pure helper functions that CHECK constraints call (looks_like_pan, luhn_valid) come
    from the revisions, so nothing is copied here."""
    url = temporary_databases.create()
    engine = create_engine(url, poolclass=NullPool)
    try:
        with engine.begin() as connection:
            for name in sorted(migration_scripts.extensions()):
                connection.execute(text(f'CREATE EXTENSION "{name}"'))
            for module in migration_scripts.modules.values():
                for statement in getattr(module, "PAN_FUNCTIONS", ()):
                    connection.execute(text(statement))
            metadata.create_all(connection)
        yield engine
    finally:
        engine.dispose()
        temporary_databases.drop(url)


def test_autogenerate_reports_no_difference(db_engine: Engine) -> None:
    """Layer 1: ``compare_metadata`` (types, nullability, defaults, indexes, uniques, FKs)."""
    with db_engine.connect() as connection:
        context = MigrationContext.configure(connection, opts=dict(COMPARE_OPTIONS))
        differences = compare_metadata(context, metadata)

    assert differences == []


Catalog = dict[str, dict[tuple[str, str], object]]


def read_catalog(connection: Connection) -> Catalog:
    """Normalised definitions of every constraint, index and column in ``public``."""
    constraints = {
        (table, name): (kind, definition)
        for table, name, kind, definition in connection.execute(
            text(
                """
                SELECT c.relname, con.conname, con.contype, pg_get_constraintdef(con.oid)
                  FROM pg_constraint AS con
                  JOIN pg_class AS c ON c.oid = con.conrelid
                  JOIN pg_namespace AS n ON n.oid = c.relnamespace
                 WHERE n.nspname = 'public' AND c.relname <> 'alembic_version'
                """
            )
        )
    }
    indexes = {
        (table, name): definition
        for table, name, definition in connection.execute(
            text(
                """
                SELECT tablename, indexname, indexdef FROM pg_indexes
                 WHERE schemaname = 'public' AND tablename <> 'alembic_version'
                """
            )
        )
    }
    columns = {
        (table, column): (column_type, not_null, default)
        for table, column, column_type, not_null, default in connection.execute(
            text(
                """
                SELECT c.relname, a.attname, format_type(a.atttypid, a.atttypmod),
                       a.attnotnull, coalesce(pg_get_expr(d.adbin, d.adrelid), '') || ' / '
                       || coalesce(col_description(c.oid, a.attnum), '')
                  FROM pg_attribute AS a
                  JOIN pg_class AS c ON c.oid = a.attrelid
                  JOIN pg_namespace AS n ON n.oid = c.relnamespace
                  LEFT JOIN pg_attrdef AS d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
                 WHERE n.nspname = 'public' AND c.relkind = 'r'
                   AND c.relname <> 'alembic_version' AND a.attnum > 0 AND NOT a.attisdropped
                """
            )
        )
    }
    return {"constraints": constraints, "indexes": indexes, "columns": columns}


def test_catalog_definitions_match_models(
    db_engine: Engine, model_database: Engine, golden_objects: dict[str, "DbObjects"]
) -> None:
    """Layer 2: every constraint/index/column definition (incl. column comments) is
    identical in both databases."""
    with db_engine.connect() as connection:
        migrated = read_catalog(connection)
    with model_database.connect() as connection:
        modelled = read_catalog(connection)

    triggers_as_constraints = {
        key for key, (kind, _) in migrated["constraints"].items() if kind == "t"
    }
    (head,) = head_revisions()
    manifest = set(golden_objects[head]["triggers"])
    assert triggers_as_constraints
    assert {f"{table}.{name}" for table, name in triggers_as_constraints} <= manifest
    for key in triggers_as_constraints:
        del migrated["constraints"][key]

    for section in ("constraints", "indexes", "columns"):
        only_migrated = sorted(set(migrated[section]) - set(modelled[section]))
        only_modelled = sorted(set(modelled[section]) - set(migrated[section]))
        assert only_migrated == [], f"{section} missing from the models"
        assert only_modelled == [], f"{section} missing from the migrations"
        different = {
            key: (migrated[section][key], modelled[section][key])
            for key in migrated[section]
            if migrated[section][key] != modelled[section][key]
        }
        assert different == {}, f"{section} differ (migration, model)"


def test_catalog_covers_the_blind_spots(db_engine: Engine) -> None:
    """The layer-2 catalog really contains the object kinds autogenerate ignores."""
    with db_engine.connect() as connection:
        catalog = read_catalog(connection)
    kinds = {kind for kind, _ in catalog["constraints"].values()}
    index_definitions = " ".join(str(value) for value in catalog["indexes"].values())

    assert {"p", "u", "f", "c", "x"} <= kinds
    assert "gin_trgm_ops" in index_definitions
    assert "WHERE (status = 'queued'::text)" in index_definitions
    assert "balance_as_of DESC" in index_definitions
    assert len(AUTOGENERATE_BLIND_SPOTS) == 6


def test_objects_outside_the_models_exist(
    db_engine: Engine,
    golden_objects: dict[str, "DbObjects"],
    migration_scripts: "MigrationScripts",
) -> None:
    """Layer 3: NOT_IN_MODELS entries are present; expectations derived (R2-30)."""
    with db_engine.connect() as connection:
        extensions = set(connection.execute(text("SELECT extname FROM pg_extension")).scalars())
        triggers = set(
            connection.execute(
                text(
                    "SELECT c.relname || '.' || t.tgname FROM pg_trigger AS t "
                    "JOIN pg_class AS c ON c.oid = t.tgrelid "
                    "JOIN pg_namespace AS n ON n.oid = c.relnamespace "
                    "WHERE n.nspname = 'public' AND NOT t.tgisinternal"
                )
            ).scalars()
        )
        currencies = connection.execute(text("SELECT count(*) FROM currencies")).scalar_one()
        version = database_revisions(connection)

    (head,) = head_revisions()
    assert migration_scripts.extensions() <= extensions
    assert triggers == set(golden_objects[head]["triggers"])
    assert currencies == len(MINOR_DIGITS)
    assert version == head_revisions()
    assert len(NOT_IN_MODELS) == 5


def test_every_name_fits_the_postgres_identifier_limit() -> None:
    """Longer names would be truncated by PostgreSQL and drift from the models."""
    names = [str(constraint.name) for t in metadata.tables.values() for constraint in t.constraints]
    names += [str(index.name) for t in metadata.tables.values() for index in t.indexes]

    assert names
    assert [name for name in names if len(name) > POSTGRES_MAX_IDENTIFIER] == []
    assert len(names) == len(set(names))  # every name embeds its table name
