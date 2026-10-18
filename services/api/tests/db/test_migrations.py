"""Migration round trips and the ``cardflow migrate`` command (T-005, revision round 0002).

Every test here works on its own scratch database (``scratch_database_url``), never on the
shared session database, except the last one, which checks that the session database is
at the revision requested through ``CARDFLOW_TEST_MIGRATION_TARGET``.

Nothing about a particular head is written down here (review R2-30): revision ids come from
the shipped scripts (``head_revisions()``, ``migration_scripts.chain``), tables and sequences
from the models, triggers and functions from the golden manifest ``golden_objects.json``
(one entry per revision), extensions from the revisions' ``UPGRADE`` statements and the
currency seed from the planner engine's ``MINOR_DIGITS``. A new revision needs its golden
entry (``CARDFLOW_UPDATE_GOLDEN=1``), not edits in this file. Only the data tests of the
0001 -> 0002 step name their two revisions, because they check that step's backfill.

Extensions are an environment prerequisite (review R2-23, T-006): 0001 creates btree_gist
and pg_trgm only if they are missing and no downgrade drops them, because they may predate
the schema or serve other objects. So the exact round trips compare the catalog without
the extension list and check separately that the extensions are present after every
upgrade and still present after every downgrade.
"""

import json
import logging
import threading
import time
from collections.abc import Callable, Iterator
from dataclasses import dataclass
from datetime import date
from typing import TYPE_CHECKING, Any, Final

import pytest
from sqlalchemy import and_, func, select, text
from sqlalchemy.engine import URL, Connection, Engine
from sqlalchemy.exc import DBAPIError
from sqlalchemy.pool import NullPool

from cardflow.cli import EXIT_MIGRATE_FAILED, EXIT_OK, main
from cardflow.db.engine import create_engine
from cardflow.db.migrations import (
    MIGRATE_APPLICATION_NAME,
    MIGRATION_LOCK_KEY,
    database_revisions,
    downgrade,
    head_revisions,
    migration_status,
    upgrade,
)
from cardflow.db.models import metadata
from cardflow.planner.engine.money import MINOR_DIGITS

if TYPE_CHECKING:
    from tests.db.conftest import Catalog, DbObjects, MigrationScripts, Rows

pytestmark = pytest.mark.db

T: Final = metadata.tables
NO_OBJECTS: Final[dict[str, dict[str, str]]] = {"triggers": {}, "functions": {}}


@dataclass(frozen=True)
class SchemaObjects:
    """What one database contains."""

    revisions: tuple[str, ...]
    tables: frozenset[str]
    objects: "DbObjects"  # trigger definitions and function bodies, fingerprinted
    extensions: frozenset[str]
    sequences: frozenset[str]
    currencies: int | None


@dataclass(frozen=True)
class Expected:
    """The schema at head as the code describes it (R2-30: derived, not written down)."""

    revisions: tuple[str, ...]
    tables: frozenset[str]
    objects: "DbObjects"
    extensions: frozenset[str]
    sequences: frozenset[str]
    currencies: int

    def assert_at_head(self, actual: SchemaObjects) -> None:
        assert actual.revisions == self.revisions
        assert actual.tables == self.tables
        assert actual.objects == self.objects
        assert actual.extensions >= self.extensions
        assert actual.sequences == self.sequences
        assert actual.currencies == self.currencies

    def assert_at_base(self, actual: SchemaObjects) -> None:
        assert actual.revisions == ()
        assert actual.tables == {"alembic_version"}
        assert actual.objects == NO_OBJECTS
        assert actual.extensions >= self.extensions  # environment prerequisite (R2-23)
        assert actual.sequences == frozenset()
        assert actual.currencies is None


@pytest.fixture(scope="session")
def expected(
    golden_objects: dict[str, "DbObjects"], migration_scripts: "MigrationScripts"
) -> Expected:
    (head,) = head_revisions()
    assert migration_scripts.head == head
    return Expected(
        revisions=head_revisions(),
        tables=frozenset({*T, "alembic_version"}),
        objects=golden_objects[head],
        extensions=migration_scripts.extensions(),
        sequences=frozenset(
            f"{table.name}_{table.autoincrement_column.name}_seq"
            for table in T.values()
            if table.autoincrement_column is not None
        ),
        currencies=len(MINOR_DIGITS),
    )


@pytest.fixture(scope="session")
def inspect_schema(
    read_database_objects: Callable[[Connection], "DbObjects"],
) -> Callable[[URL], SchemaObjects]:
    def inspect(url: URL) -> SchemaObjects:
        engine = create_engine(url, poolclass=NullPool)
        try:
            with engine.connect() as connection:

                def names(sql: str) -> frozenset[str]:
                    return frozenset(connection.execute(text(sql)).scalars())

                tables = names("SELECT tablename FROM pg_tables WHERE schemaname = 'public'")
                currencies = (
                    connection.execute(text("SELECT count(*) FROM currencies")).scalar_one()
                    if "currencies" in tables
                    else None
                )
                return SchemaObjects(
                    revisions=database_revisions(connection),
                    tables=tables,
                    objects=read_database_objects(connection),
                    extensions=names("SELECT extname FROM pg_extension"),
                    sequences=names(
                        "SELECT sequencename FROM pg_sequences WHERE schemaname = 'public'"
                    ),
                    currencies=currencies,
                )
        finally:
            engine.dispose()

    return inspect


def test_r2_30_expectations_are_derived_from_the_code(
    expected: Expected, migration_scripts: "MigrationScripts"
) -> None:
    """R2-30: the expectations follow head_revisions(), the models and the manifest."""
    assert expected.revisions == (migration_scripts.chain[-1],)
    assert expected.objects["triggers"]
    assert expected.objects["functions"]
    assert expected.extensions
    assert expected.sequences
    assert expected.currencies == len(MINOR_DIGITS)


def test_upgrade_downgrade_upgrade_round_trip(
    scratch_database_url: URL,
    inspect_schema: Callable[[URL], SchemaObjects],
    expected: Expected,
) -> None:
    """Empty DB: upgrade head -> downgrade base -> upgrade head (and down again)."""
    empty = inspect_schema(scratch_database_url)
    assert empty.tables == frozenset()
    assert empty.revisions == ()

    upgrade(scratch_database_url, "head")
    expected.assert_at_head(inspect_schema(scratch_database_url))

    downgrade(scratch_database_url, "base")
    expected.assert_at_base(inspect_schema(scratch_database_url))

    upgrade(scratch_database_url, "head")
    expected.assert_at_head(inspect_schema(scratch_database_url))

    downgrade(scratch_database_url, "base")  # repeatable, not a one-off
    expected.assert_at_base(inspect_schema(scratch_database_url))


def _state(
    engine: Engine, read_catalog: Callable[[Connection], "Catalog"]
) -> dict[str, dict[str, str]]:
    """Catalog plus version and seed rows (the bookkeeping table itself, which an empty
    database lacks and a downgraded one keeps, only via its version row). Extensions are
    left out: they are an environment prerequisite (R2-23), see :func:`_extensions`."""
    with engine.connect() as connection:
        state = {
            section: {
                key: value
                for key, value in entries.items()
                if not key.startswith("alembic_version.")
            }
            for section, entries in read_catalog(connection).items()
        }
        tables = set(
            connection.execute(
                text("SELECT tablename FROM pg_tables WHERE schemaname = 'public'")
            ).scalars()
        )
        seed = (
            connection.execute(text("SELECT code, minor_digits FROM currencies")).all()
            if "currencies" in tables
            else []
        )
        state["meta"] = {
            "revisions": ",".join(database_revisions(connection)),
            "currencies": json.dumps(sorted([code, digits] for code, digits in seed)),
        }
    return state


def _extensions(engine: Engine) -> frozenset[str]:
    with engine.connect() as connection:
        return frozenset(connection.execute(text("SELECT extname FROM pg_extension")).scalars())


def _differences(
    actual: dict[str, dict[str, str]], wanted: dict[str, dict[str, str]]
) -> dict[str, dict[str, list[str]]]:
    found: dict[str, dict[str, list[str]]] = {}
    for section in sorted(set(actual) | set(wanted)):
        mine, theirs = actual.get(section, {}), wanted.get(section, {})
        delta = {
            "unexpected": sorted(set(mine) - set(theirs)),
            "missing": sorted(set(theirs) - set(mine)),
            "changed": sorted(key for key in set(mine) & set(theirs) if mine[key] != theirs[key]),
        }
        if any(delta.values()):
            found[section] = delta
    return found


def test_every_revision_steps_down_and_up_exactly(
    scratch_database_url: URL,
    migration_scripts: "MigrationScripts",
    golden_objects: dict[str, "DbObjects"],
    read_catalog: Callable[[Connection], "Catalog"],
    read_database_objects: Callable[[Connection], "DbObjects"],
) -> None:
    """Each revision of the chain (0001 <-> 0002 <-> 0003 ...): its downgrade restores the
    previous catalog exactly and its upgrade rebuilds an identical one -- constraints,
    indexes, columns (type, nullability, default, comment), triggers, function bodies,
    settings and SECURITY DEFINER, row-level security flags, policies, the privileges of
    relations, columns, functions, schemas and the database, views, version row and seed
    rows. Each revision also matches its golden entry. The extensions every revision needs
    are present after each upgrade and survive each downgrade (R2-23)."""
    required = migration_scripts.extensions()
    engine = create_engine(scratch_database_url, poolclass=NullPool)
    try:
        previous, before = "base", _state(engine, read_catalog)
        for revision in migration_scripts.chain:
            upgrade(scratch_database_url, revision)
            after = _state(engine, read_catalog)
            assert after["meta"]["revisions"] == revision
            assert _extensions(engine) >= required
            with engine.connect() as connection:
                assert read_database_objects(connection) == golden_objects[revision]

            downgrade(scratch_database_url, previous)
            assert _differences(_state(engine, read_catalog), before) == {}, (
                f"downgrade {revision} -> {previous} is not exact"
            )
            assert _extensions(engine) >= required
            upgrade(scratch_database_url, revision)
            assert _differences(_state(engine, read_catalog), after) == {}, (
                f"upgrade {previous} -> {revision} is not repeatable"
            )
            previous, before = revision, after
    finally:
        engine.dispose()


def test_r2_23_downgrade_keeps_extensions_that_others_use(scratch_database_url: URL) -> None:
    """R2-23: pg_trgm installed before the schema and used by an object outside it. The
    downgrade to base used to drop the extension (or fail with 2BP01 because of the foreign
    index); now it leaves the extension and that index alone."""
    engine = create_engine(scratch_database_url, poolclass=NullPool)
    try:
        with engine.begin() as connection:
            connection.execute(text("CREATE EXTENSION pg_trgm"))
            connection.execute(text("CREATE SCHEMA r2_23_other"))
            connection.execute(text("CREATE TABLE r2_23_other.notes (body text)"))
            connection.execute(
                text(
                    "CREATE INDEX notes_body_trgm ON r2_23_other.notes "
                    "USING gin (body public.gin_trgm_ops)"
                )
            )
        upgrade(scratch_database_url, "head")
        downgrade(scratch_database_url, "base")

        with engine.connect() as connection:
            extensions = set(connection.execute(text("SELECT extname FROM pg_extension")).scalars())
            foreign_index = connection.execute(
                text("SELECT to_regclass('r2_23_other.notes_body_trgm') IS NOT NULL")
            ).scalar_one()
            revisions = database_revisions(connection)
    finally:
        engine.dispose()

    assert {"pg_trgm", "btree_gist"} <= extensions
    assert foreign_index is True
    assert revisions == ()


def test_upgrade_at_head_is_a_no_op(
    scratch_database_url: URL,
    inspect_schema: Callable[[URL], SchemaObjects],
    expected: Expected,
) -> None:
    upgrade(scratch_database_url, "head")
    upgrade(scratch_database_url, "head")

    expected.assert_at_head(inspect_schema(scratch_database_url))


def test_migration_status_reports_base_and_head(scratch_database_url: URL) -> None:
    engine = create_engine(scratch_database_url, poolclass=NullPool)
    try:
        with engine.connect() as connection:
            before = migration_status(connection)
        upgrade(scratch_database_url, "head")
        with engine.connect() as connection:
            after = migration_status(connection)
    finally:
        engine.dispose()

    assert before.current == ()
    assert before.heads == head_revisions()
    assert not before.up_to_date
    assert after.current == after.heads == head_revisions()
    assert after.up_to_date


# --- the 0001 -> 0002 step with rows in the tables ----------------------------------------

STEP: Final = ("0001", "0002")


def _populate(rows: "Rows") -> dict[str, Any]:
    """At least one row in every table that 0002 gives a derived column, two allocations."""
    account = rows.account()
    workspace = account.workspace_id
    card = rows.card(workspace, account.credit_account_id)
    transaction = rows.transaction(account, card_id=card)
    rows.insert(
        "preauth_holds",
        workspace_id=workspace,
        currency_account_id=account.currency_account_id,
        card_id=card,
        amount_minor=100,
        currency="CNY",
        held_at=text("now()"),
        held_tz="Asia/Shanghai",
        time_precision="datetime",
        status="active",
        source_kind="manual",
        confirmation_level="user_confirmed",
    )
    statement = rows.statement(account)
    version = rows.statement_version(workspace, statement)
    rows.statement_line(workspace, version)
    rows.insert(
        "statement_attributions",
        workspace_id=workspace,
        transaction_id=transaction,
        statement_id=statement,
        confirmation_level="system_estimated",
    )
    cash = rows.cash_account(workspace)
    rows.insert(
        "snapshot_included_events",
        workspace_id=workspace,
        snapshot_id=rows.cash_snapshot(workspace, cash),
        cash_event_id=rows.cash_event(workspace, cash),
    )
    repayment = rows.repayment(account, 100_000)
    rows.allocation(workspace, repayment, statement, 30_000)
    rows.allocation(workspace, repayment, rows.statement(account, date(2026, 12, 10)), 20_000)
    plan = rows.plan(workspace)
    run = rows.plan_run(workspace, plan)
    rows.insert(
        "plan_allocations",
        workspace_id=workspace,
        run_id=run,
        currency_account_id=account.currency_account_id,
        card_id=card,
        amount_minor=1_000,
        statement_date=date(2026, 11, 10),
        due_date=date(2026, 11, 28),
        repay_on=date(2026, 11, 28),
        repay_from_cash_account_id=cash,
        buffer_days=43,
    )
    rows.insert(
        "plan_reservations",
        workspace_id=workspace,
        plan_id=plan,
        run_id=run,
        currency_account_id=account.currency_account_id,
        cash_account_id=cash,
        amount_minor=1_000,
        status="active",
    )
    return {"repayment": repayment, "run": run}


def _json_order(row: dict[str, Any]) -> str:
    return json.dumps(row, sort_keys=True)


def _table_rows(connection: Connection) -> dict[str, list[dict[str, Any]]]:
    """Every row of every table (alembic_version aside) as JSON, in a stable order."""
    present = connection.execute(
        text(
            "SELECT tablename FROM pg_tables "
            "WHERE schemaname = 'public' AND tablename <> 'alembic_version'"
        )
    ).scalars()
    return {
        name: sorted(
            connection.execute(select(func.to_jsonb(T[name].table_valued()))).scalars(),
            key=_json_order,
        )
        for name in present
    }


def _projected(
    rows_now: dict[str, list[dict[str, Any]]], rows_then: dict[str, list[dict[str, Any]]]
) -> dict[str, list[dict[str, Any]]]:
    """``rows_now`` limited to the tables and columns that ``rows_then`` had."""
    columns = {name: set().union(*(row.keys() for row in rows)) for name, rows in rows_then.items()}
    return {
        name: sorted(
            ({key: value for key, value in row.items() if key in columns[name]} for row in rows),
            key=_json_order,
        )
        for name, rows in rows_now.items()
        if name in rows_then
    }


def test_step_0001_0002_with_rows_backfills_and_keeps_every_value(
    scratch_database_url: URL,
    rows_class: "type[Rows]",
    migration_scripts: "MigrationScripts",
) -> None:
    """0001 -> 0002 on a populated database: every existing value survives unchanged, the
    derived account/currency columns (from the migration's DERIVED_COLUMNS) and the
    allocation totals are backfilled, and the downgrade brings back exactly the old rows.
    Empty-database round trips cannot see data-dependent failures such as a backfill
    UPDATE that leaves deferred trigger events pending for the next ALTER TABLE (55006)."""
    old, new = STEP
    assert migration_scripts.chain[:2] == STEP
    upgrade(scratch_database_url, old)
    engine = create_engine(scratch_database_url, poolclass=NullPool)
    try:
        with engine.begin() as connection:
            ids = _populate(rows_class(connection))
        with engine.connect() as connection:
            before = _table_rows(connection)

        upgrade(scratch_database_url, new)
        with engine.connect() as connection:
            after = _table_rows(connection)
            derived: dict[str, tuple[int, int]] = {}
            for table, column, _type, parent, key, source in migration_scripts.modules[
                new
            ].DERIVED_COLUMNS:
                child, owner = T[table].alias("c"), T[parent].alias("p")
                total, matching = connection.execute(
                    select(
                        func.count(),
                        func.count().filter(child.c[column].is_not_distinct_from(owner.c[source])),
                    ).select_from(
                        child.join(
                            owner,
                            and_(
                                owner.c.workspace_id == child.c.workspace_id,
                                owner.c.id == child.c[key],
                            ),
                        )
                    )
                ).one()
                derived[f"{table}.{column}"] = (total, matching)
            totals = connection.execute(
                select(
                    T["repayment_allocation_totals"].c.repayment_id,
                    T["repayment_allocation_totals"].c.allocated_minor,
                )
            ).all()

        assert _projected(after, before) == before
        assert {name: count for name, count in derived.items() if count[0] < 1} == {}
        assert {name: count for name, count in derived.items() if count[0] != count[1]} == {}
        assert totals == [(ids["repayment"], 50_000)]

        downgrade(scratch_database_url, old)
        with engine.connect() as connection:
            assert _table_rows(connection) == before
    finally:
        engine.dispose()


def test_step_0001_0002_refuses_rows_it_cannot_hold(
    scratch_database_url: URL, rows_class: "type[Rows]"
) -> None:
    """Fail closed: a 0001 plan allocation without card (0002 allocates per card,
    decision 1) stops the upgrade; the migration's transaction rolls back and the database
    stays at 0001 with all its rows. No value is invented."""
    old, new = STEP
    upgrade(scratch_database_url, old)
    engine = create_engine(scratch_database_url, poolclass=NullPool)
    try:
        with engine.begin() as connection:
            rows = rows_class(connection)
            account = rows.account()
            workspace = account.workspace_id
            rows.insert(
                "plan_allocations",
                workspace_id=workspace,
                run_id=rows.plan_run(workspace, rows.plan(workspace)),
                currency_account_id=account.currency_account_id,
                amount_minor=1_000,
                statement_date=date(2026, 11, 10),
                due_date=date(2026, 11, 28),
                repay_on=date(2026, 11, 28),
                repay_from_cash_account_id=rows.cash_account(workspace),
                buffer_days=43,
            )
        with engine.connect() as connection:
            before = _table_rows(connection)

        with pytest.raises(DBAPIError) as excinfo:
            upgrade(scratch_database_url, new)
        assert getattr(excinfo.value.orig, "sqlstate", None) == "23502"  # not_null_violation

        with engine.connect() as connection:
            assert database_revisions(connection) == (old,)
            assert _table_rows(connection) == before
    finally:
        engine.dispose()


# --- cardflow migrate -----------------------------------------------------------------


@pytest.fixture
def restore_root_logging() -> Iterator[None]:
    """``cardflow migrate`` installs its own root log handler; undo that after the test."""
    root = logging.getLogger()
    handlers, level = list(root.handlers), root.level
    yield
    root.handlers[:] = handlers
    root.setLevel(level)


@pytest.fixture
def migrate_env(
    scratch_database_url: URL,
    clean_settings_env: pytest.MonkeyPatch,
    restore_root_logging: None,
) -> URL:
    """Point ``Settings`` (DATABASE_URL + DATABASE_PASSWORD) at the scratch database."""
    del restore_root_logging
    assert scratch_database_url.password is not None
    without_password = URL.create(
        drivername=scratch_database_url.drivername,
        username=scratch_database_url.username,
        host=scratch_database_url.host,
        port=scratch_database_url.port,
        database=scratch_database_url.database,
    )
    clean_settings_env.setenv("DATABASE_URL", without_password.render_as_string())
    clean_settings_env.setenv("DATABASE_PASSWORD", scratch_database_url.password)
    return scratch_database_url


def test_migrate_check_exit_codes(migrate_env: URL, capsys: pytest.CaptureFixture[str]) -> None:
    """``--check``: 1 while not at head, 0 at head; plain ``migrate`` upgrades."""
    heads = ",".join(head_revisions())

    assert main(["migrate", "--check"]) == EXIT_MIGRATE_FAILED == 1
    assert f"database revision (none); code head {heads}: NOT at head" in capsys.readouterr().out

    assert main(["migrate"]) == EXIT_OK
    assert "up to date" in capsys.readouterr().out

    assert main(["migrate", "--check"]) == EXIT_OK == 0
    captured = capsys.readouterr()
    assert f"database revision {heads}; code head {heads}: up to date" in captured.out
    assert migrate_env.password not in captured.out + captured.err


def test_migrate_check_below_head_exits_1(
    migrate_env: URL, migration_scripts: "MigrationScripts", capsys: pytest.CaptureFixture[str]
) -> None:
    """One revision below head (and base) is reported as NOT at head."""
    upgrade(migrate_env, "head")
    assert main(["migrate", "--check"]) == EXIT_OK

    below_head = ",".join(migration_scripts.chain[-2:-1]) or "(none)"
    downgrade(migrate_env, "-1")
    capsys.readouterr()

    assert main(["migrate", "--check"]) == EXIT_MIGRATE_FAILED
    assert f"database revision {below_head}; " in capsys.readouterr().out

    downgrade(migrate_env, "base")

    assert main(["migrate", "--check"]) == EXIT_MIGRATE_FAILED


def test_migrate_lock_upgrades_and_releases_the_lock(
    migrate_env: URL,
    inspect_schema: Callable[[URL], SchemaObjects],
    expected: Expected,
) -> None:
    assert main(["migrate", "--lock"]) == EXIT_OK

    expected.assert_at_head(inspect_schema(migrate_env))
    engine = create_engine(migrate_env, poolclass=NullPool)
    try:
        with engine.connect() as connection:
            got = connection.execute(select(func.pg_try_advisory_lock(MIGRATION_LOCK_KEY)))
            assert got.scalar_one() is True
            connection.execute(select(func.pg_advisory_unlock(MIGRATION_LOCK_KEY)))
    finally:
        engine.dispose()


def _waiting_for_migration_lock(connection: Connection) -> bool:
    waiting = connection.execute(
        text(
            """
            SELECT count(*)
              FROM pg_locks AS l JOIN pg_stat_activity AS a ON a.pid = l.pid
             WHERE l.locktype = 'advisory' AND NOT l.granted
               AND a.application_name = :application_name
               AND l.database = (SELECT oid FROM pg_database WHERE datname = current_database())
            """
        ),
        {"application_name": MIGRATE_APPLICATION_NAME},
    ).scalar_one()
    return bool(waiting)


def test_migrate_lock_waits_while_another_migrator_holds_it(
    scratch_database_url: URL,
    inspect_schema: Callable[[URL], SchemaObjects],
    expected: Expected,
) -> None:
    """A second ``migrate --lock`` blocks on the advisory lock and runs after release."""
    failures: list[BaseException] = []

    def migrate_locked() -> None:
        try:
            upgrade(scratch_database_url, "head", lock=True)
        except BaseException as exc:  # noqa: BLE001 - re-raised in the main thread
            failures.append(exc)

    engine = create_engine(scratch_database_url, poolclass=NullPool)
    try:
        with engine.connect() as holder:
            holder.execution_options(isolation_level="AUTOCOMMIT")
            holder.execute(select(func.pg_advisory_lock(MIGRATION_LOCK_KEY)))
            worker = threading.Thread(target=migrate_locked, daemon=True)
            worker.start()
            deadline = time.monotonic() + 30
            while not _waiting_for_migration_lock(holder):
                assert time.monotonic() < deadline, "migrator never waited for the lock"
                assert worker.is_alive(), f"migrator finished without the lock: {failures}"
                time.sleep(0.05)

            assert database_revisions(holder) == ()  # nothing ran while the lock was held
            holder.execute(select(func.pg_advisory_unlock(MIGRATION_LOCK_KEY)))
            worker.join(timeout=120)
    finally:
        engine.dispose()

    assert not worker.is_alive()
    assert failures == []
    expected.assert_at_head(inspect_schema(scratch_database_url))


def test_session_database_is_at_the_requested_target(
    conn: Connection, schema_revision: str | None, migration_target: str
) -> None:
    """``CARDFLOW_TEST_MIGRATION_TARGET`` (default head) decides the session schema."""
    expected_revisions = () if schema_revision is None else (schema_revision,)

    assert database_revisions(conn) == expected_revisions
    if migration_target == "head":
        assert expected_revisions == head_revisions()
