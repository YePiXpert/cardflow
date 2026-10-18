"""Fixtures for schema tests (T-005/T-007 and the 0002 revision round).

* ``scratch_database_url`` -- a fresh, EMPTY database for one test (migration round trips,
  ``cardflow migrate`` runs); never the shared session database.
* ``conn`` -- a connection to the session database inside one transaction that is rolled
  back after the test. Statements expected to fail run in a savepoint
  (``conn.begin_nested()``) so the outer transaction stays usable.
* ``rows`` -- a :class:`Rows` factory bound to ``conn``; ``rows_class`` gives the class for
  other connections (tests import the type only under ``TYPE_CHECKING``:
  ``--import-mode=importlib`` cannot import conftest modules at run time).
* ``engine_0001`` -- an extra database migrated to revision 0001 only (session scope), used to
  show that a review finding (R2-xx) reproduces before revision 0002.
* ``golden_objects`` / ``read_database_objects`` -- trigger and function fingerprints per
  revision (``golden_objects.json``) and the function that reads them from a database.
  After an intentional change of a trigger or function, regenerate the file with
  ``CARDFLOW_UPDATE_GOLDEN=1 uv run pytest tests/db/test_db_objects.py`` and review the diff.
* ``read_catalog`` -- normalised definitions of every constraint, index, column, trigger
  and function, plus (T-006) row-level security flags, policies, privileges of relations,
  columns, functions, schemas and the database, and the admin views (exact round-trip
  comparisons). ACLs are compared as the set of grants they mean: a NULL ACL (the default)
  and an explicit ACL with the same grants are equal, because REVOKE never turns an ACL back
  into NULL.
* ``migration_scripts`` -- the shipped revisions oldest first, with their modules: tests
  derive revision ids, extensions, derived columns ... from them instead of writing them
  down (review R2-30).
* ``head_engine`` -- a pristine database at head (module scope) for catalog checks that
  must not see tables other tests create in the shared session database.
* ``rls_declarations`` -- roles, grants, policies and function privileges as the revisions
  declare them (0003 onwards: ``TABLE_ACCESS``, ``POLICIES``, ``RLS_TABLES`` ...), merged in
  revision order; the RLS tests derive their expectations from it. 0003 declares the full
  initial state; a later revision (0004, T-011) declares only what it adds or changes.

These fixtures connect as the PostgreSQL superuser, so row-level security does not apply
to them; tests that exercise RLS connect through ``app_engine`` & co. (tests/conftest.py).
"""

import hashlib
import json
import re
import uuid
from collections.abc import Callable, Iterable, Iterator
from dataclasses import dataclass
from datetime import UTC, date, datetime
from pathlib import Path
from types import ModuleType
from typing import Any, Final, Protocol

import pytest
from alembic.script import ScriptDirectory
from sqlalchemy import insert, text
from sqlalchemy.engine import URL, Connection, Engine
from sqlalchemy.pool import NullPool

from cardflow.db.engine import create_engine
from cardflow.db.migrations import alembic_config, head_revisions, upgrade
from cardflow.db.models import metadata

T: Final = metadata.tables
NOW: Final = datetime(2026, 10, 16, 8, 0, tzinfo=UTC)
GOLDEN_PATH: Final = Path(__file__).with_name("golden_objects.json")

DbObjects = dict[str, dict[str, str]]
Catalog = dict[str, dict[str, str]]


class DatabaseFactory(Protocol):
    """What ``temporary_databases`` (root conftest) offers."""

    def create(self) -> URL:
        """Create an empty database."""
        ...

    def drop(self, url: URL) -> None:
        """Drop a database created by :meth:`create`."""
        ...


@pytest.fixture
def scratch_database_url(temporary_databases: DatabaseFactory) -> Iterator[URL]:
    """Empty database created for this test only; dropped afterwards."""
    url = temporary_databases.create()
    try:
        yield url
    finally:
        temporary_databases.drop(url)


@pytest.fixture(scope="session")
def engine_0001(temporary_databases: DatabaseFactory) -> Iterator[Engine]:
    """A database at revision 0001 (before the review fixes) for R2 reproductions."""
    url = temporary_databases.create()
    try:
        upgrade(url, "0001")
        engine = create_engine(url, poolclass=NullPool)
        yield engine
        engine.dispose()
    finally:
        temporary_databases.drop(url)


@pytest.fixture
def conn(db_engine: Engine) -> Iterator[Connection]:
    """Connection in a transaction that is always rolled back."""
    with db_engine.connect() as connection:
        transaction = connection.begin()
        try:
            yield connection
        finally:
            transaction.rollback()


# --- row factory --------------------------------------------------------------------------


@dataclass(frozen=True)
class Account:
    """A workspace with one credit account and its currency sub-account."""

    workspace_id: uuid.UUID
    credit_account_id: uuid.UUID
    currency_account_id: uuid.UUID


class Rows:
    """Minimal valid rows (Core inserts through the model tables).

    Inserts name only columns that exist in revision 0001 as well, so the same factory
    works on ``engine_0001``; derived columns of 0002 are filled by the database.
    """

    def __init__(self, connection: Connection) -> None:
        self.connection = connection

    def insert(self, table: str, **values: object) -> uuid.UUID:
        target = T[table]
        statement = insert(target).values(**values).returning(target.c.id)
        return self.connection.execute(statement).scalar_one()

    def workspace(self) -> uuid.UUID:
        return self.insert("workspaces", owner_user_id=self.insert("users"), kind="real")

    def bank(self, workspace_id: uuid.UUID | None = None) -> uuid.UUID:
        return self.insert("banks", workspace_id=workspace_id, name="Test Bank")

    def product(self, bank_id: uuid.UUID, workspace_id: uuid.UUID | None = None) -> uuid.UUID:
        return self.insert(
            "card_products", workspace_id=workspace_id, bank_id=bank_id, name="Test Card"
        )

    def credit_account(
        self,
        workspace_id: uuid.UUID,
        bank_id: uuid.UUID | None = None,
        product_id: uuid.UUID | None = None,
    ) -> uuid.UUID:
        return self.insert(
            "credit_accounts",
            workspace_id=workspace_id,
            bank_id=bank_id or self.bank(),
            product_id=product_id,
            holder_alias="me",
            status="active",
        )

    def currency_account(
        self, workspace_id: uuid.UUID, credit_account_id: uuid.UUID, currency: str = "CNY"
    ) -> uuid.UUID:
        return self.insert(
            "currency_accounts",
            workspace_id=workspace_id,
            credit_account_id=credit_account_id,
            currency=currency,
        )

    def account(self, workspace_id: uuid.UUID | None = None, currency: str = "CNY") -> Account:
        workspace = workspace_id or self.workspace()
        credit_account = self.credit_account(workspace)
        return Account(
            workspace, credit_account, self.currency_account(workspace, credit_account, currency)
        )

    def card(
        self, workspace_id: uuid.UUID, credit_account_id: uuid.UUID, last4: str = "1234"
    ) -> uuid.UUID:
        return self.insert(
            "cards",
            workspace_id=workspace_id,
            credit_account_id=credit_account_id,
            last4=last4,
            holder_kind="primary",
            status="active",
        )

    def transaction(
        self,
        account: Account,
        amount_minor: int = 10_000,
        txn_type: str = "purchase",
        **extra: object,
    ) -> uuid.UUID:
        values: dict[str, object] = {
            "workspace_id": account.workspace_id,
            "currency_account_id": account.currency_account_id,
            "txn_type": txn_type,
            "amount_minor": amount_minor,
            "currency": "CNY",
            "txn_at": NOW,
            "txn_tz": "Asia/Shanghai",
            "time_precision": "datetime",
            "status": "posted",
            "fingerprint": uuid.uuid4().hex,
            "source_kind": "manual",
            "confirmation_level": "user_confirmed",
        }
        values.update(extra)
        return self.insert("transactions", **values)

    def statement(self, account: Account, statement_date: date = date(2026, 11, 10)) -> uuid.UUID:
        return self.insert(
            "statements",
            workspace_id=account.workspace_id,
            currency_account_id=account.currency_account_id,
            statement_date=statement_date,
            due_date=statement_date.replace(day=28),
            status="issued",
        )

    def statement_version(
        self, workspace_id: uuid.UUID, statement_id: uuid.UUID, version_no: int = 1
    ) -> uuid.UUID:
        return self.insert(
            "statement_versions",
            workspace_id=workspace_id,
            statement_id=statement_id,
            version_no=version_no,
            source_kind="pdf",
            previous_balance_minor=50_000,
            new_balance_minor=123_456,
            min_due_minor=12_346,
            payments_minor=50_000,
            credits_minor=0,
            fees_minor=0,
            interest_minor=0,
            installment_due_minor=0,
            credit_balance_minor=0,
            due_date=date(2026, 11, 28),
            recorded_by="import",
        )

    def statement_line(
        self, workspace_id: uuid.UUID, version_id: uuid.UUID, line_no: int = 1, **extra: object
    ) -> uuid.UUID:
        values: dict[str, object] = {
            "workspace_id": workspace_id,
            "statement_version_id": version_id,
            "line_no": line_no,
            "kind": "purchase",
            "description": "COFFEE SHOP",
            "amount_minor": 3_200,
        }
        values.update(extra)
        return self.insert("statement_lines", **values)

    def repayment(self, account: Account, amount_minor: int, **extra: object) -> uuid.UUID:
        values: dict[str, object] = {
            "workspace_id": account.workspace_id,
            "currency_account_id": account.currency_account_id,
            "amount_minor": amount_minor,
            "currency": "CNY",
            "status": "recorded",
        }
        values.update(extra)
        return self.insert("repayments", **values)

    def allocation(
        self,
        workspace_id: uuid.UUID,
        repayment_id: uuid.UUID,
        statement_id: uuid.UUID,
        amount_minor: int,
    ) -> uuid.UUID:
        return self.insert(
            "repayment_allocations",
            workspace_id=workspace_id,
            repayment_id=repayment_id,
            statement_id=statement_id,
            amount_minor=amount_minor,
        )

    def rule_version(
        self,
        workspace_id: uuid.UUID | None,
        subject_kind: str,
        subject_id: uuid.UUID,
        effective_from: date,
        effective_to: date | None = None,
        review_status: str = "user_declared",
    ) -> uuid.UUID:
        return self.insert(
            "billing_rule_versions",
            workspace_id=workspace_id,
            subject_kind=subject_kind,
            subject_id=subject_id,
            statement_day=10,
            due_kind="fixed_day",
            due_day=28,
            source="test",
            effective_from=effective_from,
            effective_to=effective_to,
            version=1,
            review_status=review_status,
        )

    def cash_account(self, workspace_id: uuid.UUID, currency: str = "CNY") -> uuid.UUID:
        return self.insert(
            "cash_accounts", workspace_id=workspace_id, name="Main", currency=currency, kind="bank"
        )

    def cash_event(
        self,
        workspace_id: uuid.UUID,
        cash_account_id: uuid.UUID,
        amount_minor: int = -5_000,
        category: str = "living",
        **extra: object,
    ) -> uuid.UUID:
        values: dict[str, object] = {
            "workspace_id": workspace_id,
            "cash_account_id": cash_account_id,
            "event_on": date(2026, 10, 20),
            "amount_minor": amount_minor,
            "cls": "confirmed",
            "category": category,
            "posting_status": "planned",
        }
        values.update(extra)
        return self.insert("cash_events", **values)

    def cash_snapshot(self, workspace_id: uuid.UUID, cash_account_id: uuid.UUID) -> uuid.UUID:
        return self.insert(
            "cash_balance_snapshots",
            workspace_id=workspace_id,
            cash_account_id=cash_account_id,
            balance_minor=100_000,
            balance_as_of=date(2026, 10, 16),
            observed_at=NOW,
            source_kind="user",
            confirmation_level="user_confirmed",
        )

    def limit_snapshot(self, account: Account, **extra: object) -> uuid.UUID:
        values: dict[str, object] = {
            "workspace_id": account.workspace_id,
            "currency_account_id": account.currency_account_id,
            "fixed_minor": 1_000_000,
            "used_minor": 100_000,
            "available_raw_minor": 900_000,
            "includes_holds": True,
            "source_kind": "bank_app",
            "balance_as_of": NOW,
            "observed_at": NOW,
            "confirmation_level": "user_confirmed",
        }
        values.update(extra)
        return self.insert("limit_snapshots", **values)

    def scenario(self, workspace_id: uuid.UUID, code: str = "baseline") -> uuid.UUID:
        return self.insert("scenarios", workspace_id=workspace_id, code=code, name=code)

    def plan(self, workspace_id: uuid.UUID, currency: str = "CNY") -> uuid.UUID:
        return self.insert(
            "plans",
            workspace_id=workspace_id,
            amount_minor=1_000_000,
            currency=currency,
            txn_date=date(2026, 10, 16),
            channel="pos",
            status="solving",
        )

    def plan_run(self, workspace_id: uuid.UUID, plan_id: uuid.UUID) -> uuid.UUID:
        return self.insert(
            "plan_runs",
            workspace_id=workspace_id,
            plan_id=plan_id,
            profile="cash_safety",
            decision_scenario_id=self.scenario(workspace_id),
            solver_status="OPTIMAL",
            business_status="CONDITIONALLY_FEASIBLE",
            input_hash="h",
            model_version="1.0.0",
            solver_version="9.15.6755",
            protocol_version="1",
            time_limit_s=10,
            workers=8,
            seed=0,
            result={},
        )

    def source_document(self, workspace_id: uuid.UUID) -> uuid.UUID:
        return self.insert(
            "source_documents",
            workspace_id=workspace_id,
            sha256=uuid.uuid4().hex * 2,
            mime="application/pdf",
            size_bytes=1024,
            storage_key=str(uuid.uuid4()),
            dek_wrapped=b"\x00" * 40,
        )


@pytest.fixture
def rows(conn: Connection) -> Rows:
    """Row factory on the rolled-back ``conn`` transaction."""
    return Rows(conn)


@pytest.fixture(scope="session")
def rows_class() -> type[Rows]:
    """The :class:`Rows` class, for connections the test opens itself."""
    return Rows


# --- golden trigger/function fingerprints and full catalog snapshots ----------------------

_OWN_FUNCTIONS = """
SELECT p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS signature,
       md5(p.prosrc) AS body_md5,
       coalesce(array_to_string(p.proconfig, ','), '') AS config,
       p.prosecdef AS security_definer
  FROM pg_proc AS p
  JOIN pg_namespace AS n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND NOT EXISTS (SELECT 1 FROM pg_depend AS d WHERE d.objid = p.oid AND d.deptype = 'e')
"""
_OWN_TRIGGERS = """
SELECT c.relname || '.' || t.tgname AS name,
       pg_get_triggerdef(t.oid) || ' -- enabled=' || t.tgenabled::text AS definition
  FROM pg_trigger AS t
  JOIN pg_class AS c ON c.oid = t.tgrelid
  JOIN pg_namespace AS n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND NOT t.tgisinternal
"""


def _md5(value: str) -> str:
    return hashlib.md5(value.encode(), usedforsecurity=False).hexdigest()


def database_objects(connection: Connection) -> DbObjects:
    """Fingerprints: ``triggers`` (md5 of pg_get_triggerdef plus the enabled state) and
    ``functions`` (md5 of the body, followed by the pinned settings such as search_path and,
    since 0003, ``security_definer`` for SECURITY DEFINER functions)."""
    triggers = {
        name: _md5(definition) for name, definition in connection.execute(text(_OWN_TRIGGERS))
    }
    functions = {
        signature: " ".join(
            part for part in (body_md5, config, "security_definer" if definer else "") if part
        )
        for signature, body_md5, config, definer in connection.execute(text(_OWN_FUNCTIONS))
    }
    return {"triggers": triggers, "functions": functions}


@pytest.fixture(scope="session")
def golden_objects() -> dict[str, DbObjects]:
    """Expected fingerprints per revision id (``golden_objects.json``; empty if absent)."""
    if not GOLDEN_PATH.exists():
        return {}
    return json.loads(GOLDEN_PATH.read_text(encoding="utf-8"))


@pytest.fixture(scope="session")
def read_database_objects() -> Callable[[Connection], DbObjects]:
    """See :func:`database_objects`."""
    return database_objects


def _acl(column: str, default_kind: str, owner: str) -> str:
    """SQL: the grants an ACL column means, as a sorted text list (NULL = the default ACL of
    ``default_kind`` for ``owner``; with ``default_kind`` NULL, a NULL ACL is empty)."""
    return f"""coalesce((
        SELECT string_agg(entry, ',' ORDER BY entry)
          FROM (SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END
                       || '=' || a.privilege_type
                       || CASE WHEN a.is_grantable THEN '*' ELSE '' END
                       || '/' || pg_get_userbyid(a.grantor) AS entry
                  FROM aclexplode(coalesce({column},
                                           acldefault(({default_kind})::"char", {owner}))) AS a
               ) AS e), '-')"""  # noqa: S608 - constant SQL fragments


_CATALOG: Final[dict[str, str]] = {
    "constraints": """
        SELECT c.relname || '.' || con.conname,
               con.contype::text || ' ' || pg_get_constraintdef(con.oid)
          FROM pg_constraint AS con
          JOIN pg_class AS c ON c.oid = con.conrelid
          JOIN pg_namespace AS n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public'
    """,
    "indexes": """
        SELECT tablename || '.' || indexname, indexdef FROM pg_indexes WHERE schemaname = 'public'
    """,
    "columns": """
        SELECT c.relname || '.' || a.attname,
               format_type(a.atttypid, a.atttypmod) || ' ' || a.attnotnull::text || ' '
               || coalesce(pg_get_expr(d.adbin, d.adrelid), '') || ' / '
               || coalesce(col_description(c.oid, a.attnum), '')
          FROM pg_attribute AS a
          JOIN pg_class AS c ON c.oid = a.attrelid
          JOIN pg_namespace AS n ON n.oid = c.relnamespace
          LEFT JOIN pg_attrdef AS d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
         WHERE n.nspname = 'public' AND c.relkind = 'r' AND a.attnum > 0 AND NOT a.attisdropped
    """,
    "triggers": _OWN_TRIGGERS,
    "functions": """
        SELECT p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
               md5(p.prosrc) || ' ' || coalesce(array_to_string(p.proconfig, ','), '')
               || CASE WHEN p.prosecdef THEN ' security_definer' ELSE '' END
          FROM pg_proc AS p
          JOIN pg_namespace AS n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND NOT EXISTS (SELECT 1 FROM pg_depend AS d WHERE d.objid = p.oid AND d.deptype = 'e')
    """,
    # --- T-006: row-level security, policies, privileges, schemas and views -------------
    "row_security": """
        SELECT c.relname || '.(rls)', c.relrowsecurity::text || ' ' || c.relforcerowsecurity::text
          FROM pg_class AS c
          JOIN pg_namespace AS n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public' AND c.relkind = 'r'
    """,
    "policies": """
        SELECT tablename || '.' || policyname,
               permissive || ' ' || cmd || ' ' || roles::text || ' USING ' || coalesce(qual, '-')
               || ' CHECK ' || coalesce(with_check, '-')
          FROM pg_policies
         WHERE schemaname = 'public'
    """,
    "relation_privileges": f"""
        SELECT CASE WHEN n.nspname = 'public' THEN '' ELSE n.nspname || '.' END
               || c.relname || '.(acl)',
               c.relkind::text || ' owner=' || pg_get_userbyid(c.relowner) || ' '
               || {_acl("c.relacl", "CASE c.relkind WHEN 'S' THEN 's' ELSE 'r' END", "c.relowner")}
          FROM pg_class AS c
          JOIN pg_namespace AS n ON n.oid = c.relnamespace
         WHERE n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
           AND n.nspname NOT LIKE 'pg_temp%' AND n.nspname NOT LIKE 'pg_toast_temp%'
           AND c.relkind IN ('r', 'v', 'S', 'm', 'p', 'f')
    """,  # noqa: S608 - constant SQL fragments
    "column_privileges": f"""
        SELECT c.relname || '.' || a.attname, {_acl("a.attacl", "NULL", "NULL")}
          FROM pg_attribute AS a
          JOIN pg_class AS c ON c.oid = a.attrelid
          JOIN pg_namespace AS n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public' AND a.attnum > 0 AND NOT a.attisdropped
           AND a.attacl IS NOT NULL
    """,  # noqa: S608 - constant SQL fragments
    "function_privileges": f"""
        SELECT p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
               {_acl("p.proacl", "'f'", "p.proowner")}
          FROM pg_proc AS p
          JOIN pg_namespace AS n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND NOT EXISTS (SELECT 1 FROM pg_depend AS d WHERE d.objid = p.oid AND d.deptype = 'e')
    """,  # noqa: S608 - constant SQL fragments
    "schemas": f"""
        SELECT '(schema) ' || n.nspname,
               'owner=' || pg_get_userbyid(n.nspowner) || ' '
               || {_acl("n.nspacl", "'n'", "n.nspowner")}
          FROM pg_namespace AS n
         WHERE n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
           AND n.nspname NOT LIKE 'pg_temp%' AND n.nspname NOT LIKE 'pg_toast_temp%'
    """,  # noqa: S608 - constant SQL fragments
    "database_privileges": f"""
        SELECT '(database)', {_acl("d.datacl", "'d'", "d.datdba")}
          FROM pg_database AS d
         WHERE d.datname = current_database()
    """,  # noqa: S608 - constant SQL fragments
    "views": """
        SELECT v.schemaname || '.' || v.viewname,
               'owner=' || v.viewowner || ' options=' || coalesce(c.reloptions::text, '-')
               || ' comment=' || coalesce(obj_description(c.oid, 'pg_class'), '-') || ' '
               || v.definition
          FROM pg_views AS v
          JOIN pg_namespace AS n ON n.nspname = v.schemaname
          JOIN pg_class AS c ON c.relnamespace = n.oid AND c.relname = v.viewname
         WHERE v.schemaname NOT IN ('pg_catalog', 'information_schema')
    """,
}


def catalog(connection: Connection) -> Catalog:
    """Every constraint, index, column (type, nullability, default, comment), trigger and
    function of schema ``public``, normalised by PostgreSQL."""
    return {
        section: {str(key): str(value) for key, value in connection.execute(text(sql))}
        for section, sql in _CATALOG.items()
    }


@pytest.fixture(scope="session")
def read_catalog() -> Callable[[Connection], Catalog]:
    """See :func:`catalog`."""
    return catalog


@pytest.fixture(scope="module")
def head_engine(temporary_databases: DatabaseFactory) -> Iterator[Engine]:
    """A fresh database migrated to head that no other test writes to (catalog checks)."""
    url = temporary_databases.create()
    try:
        upgrade(url, "head")
        engine = create_engine(url, poolclass=NullPool)
        yield engine
        engine.dispose()
    finally:
        temporary_databases.drop(url)


# --- the shipped revisions -----------------------------------------------------------------

_CREATE_EXTENSION: Final = re.compile(r"CREATE EXTENSION IF NOT EXISTS (\w+)")


@dataclass(frozen=True)
class MigrationScripts:
    """The Alembic revisions shipped with the code, oldest first."""

    chain: tuple[str, ...]
    modules: dict[str, ModuleType]

    @property
    def head(self) -> str:
        return self.chain[-1]

    def extensions(self) -> frozenset[str]:
        """Extensions created by the revisions' ``UPGRADE`` statements."""
        return frozenset(
            name
            for module in self.modules.values()
            for statement in getattr(module, "UPGRADE", ())
            for name in _CREATE_EXTENSION.findall(statement)
        )


@pytest.fixture(scope="session")
def migration_scripts() -> MigrationScripts:
    """See :class:`MigrationScripts`; the history must be linear (one head)."""
    directory = ScriptDirectory.from_config(alembic_config())
    scripts = list(reversed(list(directory.walk_revisions())))
    chain = tuple(script.revision for script in scripts)
    assert (chain[-1],) == head_revisions(), "migration history must be linear"
    return MigrationScripts(chain, {script.revision: script.module for script in scripts})


# --- roles, grants and policies declared by the revisions (T-006) ------------------------


@dataclass(frozen=True)
class RlsDeclarations:
    """What the revisions declare about roles and privileges, merged oldest first: a later
    revision's entry for a (table, role), policy (table, name), function or table
    (immutable columns) replaces the earlier one; table sets, role lists and admin views
    accumulate. Tables, columns and roles are plain names; ``table_access`` values are the
    revisions' ``Access`` records (select/insert: True or a column tuple; update: columns;
    delete: bool). ``function_owners`` names the dedicated (non-superuser) owner of a
    SECURITY DEFINER function; the others belong to the migration superuser."""

    group_roles: tuple[str, ...]
    business_roles: tuple[str, ...]
    schema_public_users: tuple[str, ...]
    table_access: dict[str, dict[str, Any]]
    sequence_usage: dict[str, tuple[str, ...]]
    rls_tables: frozenset[str]
    tenant_tables: frozenset[str]
    template_tables: frozenset[str]
    protected_fact_tables: frozenset[str]
    purgeable_tables: frozenset[str]
    policies: dict[tuple[str, str], Any]
    own_functions: frozenset[str]
    function_execute: dict[str, tuple[str, ...]]
    security_definer: frozenset[str]
    function_owners: dict[str, str]
    immutable_columns: dict[str, frozenset[str]]
    admin_view_sources: dict[str, tuple[str, ...]]
    admin_views: tuple[str, ...]


def _accumulate(earlier: tuple[str, ...], later: Iterable[str]) -> tuple[str, ...]:
    """``earlier`` followed by the new names of ``later`` (order kept, no duplicates)."""
    return tuple(dict.fromkeys((*earlier, *later)))


@pytest.fixture(scope="session")
def rls_declarations(migration_scripts: MigrationScripts) -> RlsDeclarations:
    """See :class:`RlsDeclarations`; at least one revision must declare ``TABLE_ACCESS``.

    Only revisions that declare ``TABLE_ACCESS`` take part; any other name may be omitted by
    a revision that has nothing to add to it."""
    table_access: dict[str, dict[str, Any]] = {}
    sequence_usage: dict[str, tuple[str, ...]] = {}
    policies: dict[tuple[str, str], Any] = {}
    function_execute: dict[str, tuple[str, ...]] = {}
    function_owners: dict[str, str] = {}
    immutable: dict[str, frozenset[str]] = {}
    sources: dict[str, tuple[str, ...]] = {}
    sets: dict[str, set[str]] = {
        name: set()
        for name in (
            "RLS_TABLES",
            "TENANT_TABLES",
            "TEMPLATE_TABLES",
            "PROTECTED_FACT_TABLES",
            "PURGEABLE_TABLES",
            "OWN_FUNCTIONS",
            "SECURITY_DEFINER_FUNCTIONS",
        )
    }
    group_roles: tuple[str, ...] = ()
    business_roles: tuple[str, ...] = ()
    schema_public_users: tuple[str, ...] = ()
    views: tuple[str, ...] = ()
    for revision in migration_scripts.chain:
        module = migration_scripts.modules[revision]
        if not hasattr(module, "TABLE_ACCESS"):
            continue
        for table, roles in module.TABLE_ACCESS.items():
            table_access.setdefault(table, {}).update(roles)
        sequence_usage.update(getattr(module, "SEQUENCE_USAGE", {}))
        policies.update(
            {(policy.table, policy.name): policy for policy in getattr(module, "POLICIES", ())}
        )
        function_execute.update(getattr(module, "FUNCTION_EXECUTE", {}))
        function_owners.update(getattr(module, "FUNCTION_OWNERS", {}))
        immutable.update(
            {
                table: frozenset(columns)
                for table, columns in getattr(module, "IMMUTABLE_COLUMNS", {}).items()
            }
        )
        sources.update(getattr(module, "ADMIN_VIEW_SOURCES", {}))
        for name, values in sets.items():
            values.update(getattr(module, name, ()))
        group_roles = _accumulate(group_roles, getattr(module, "GROUP_ROLES", ()))
        business_roles = _accumulate(business_roles, getattr(module, "BUSINESS_ROLES", ()))
        schema_public_users = _accumulate(
            schema_public_users, getattr(module, "SCHEMA_PUBLIC_USERS", ())
        )
        views = _accumulate(views, getattr(module, "ADMIN_VIEWS_SQL", {}))
    assert table_access, "no revision declares TABLE_ACCESS"
    return RlsDeclarations(
        group_roles=group_roles,
        business_roles=business_roles,
        schema_public_users=schema_public_users,
        table_access=table_access,
        sequence_usage=sequence_usage,
        rls_tables=frozenset(sets["RLS_TABLES"]),
        tenant_tables=frozenset(sets["TENANT_TABLES"]),
        template_tables=frozenset(sets["TEMPLATE_TABLES"]),
        protected_fact_tables=frozenset(sets["PROTECTED_FACT_TABLES"]),
        purgeable_tables=frozenset(sets["PURGEABLE_TABLES"]),
        policies=policies,
        own_functions=frozenset(sets["OWN_FUNCTIONS"]),
        function_execute=function_execute,
        security_definer=frozenset(sets["SECURITY_DEFINER_FUNCTIONS"]),
        function_owners=function_owners,
        immutable_columns=immutable,
        admin_view_sources=sources,
        admin_views=views,
    )
