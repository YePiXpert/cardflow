"""Review findings of evidence/m0/review-wave2-schema.md, fixed by revision 0002.

Every test first reproduces the finding on a database at revision 0001 (``engine_0001``) and
then shows the fix on the session database at head. Fixture rows are committed where a
COMMIT-time check is involved; everything else runs in a transaction that is rolled back.
"""

import re
import secrets
import threading
import time
import uuid
from collections.abc import Callable, Iterator
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import TYPE_CHECKING, Any, Final

import pytest
from sqlalchemy import insert, select, text, update
from sqlalchemy.engine import URL, Connection, Engine
from sqlalchemy.exc import DBAPIError
from sqlalchemy.pool import NullPool

from cardflow.db.engine import create_engine
from cardflow.db.migrations import API_ROOT
from cardflow.db.models import metadata
from cardflow.db.roles import APP_ROLE

if TYPE_CHECKING:
    from tests.db.conftest import Account, Rows

pytestmark = pytest.mark.db

T: Final = metadata.tables
OK: Final = (None, None)
CHECK_VIOLATION: Final = "23514"
FOREIGN_KEY_VIOLATION: Final = "23503"
UNIQUE_VIOLATION: Final = "23505"
EXCLUSION_VIOLATION: Final = "23P01"
INTEGRITY_CONSTRAINT_VIOLATION: Final = "23000"
NOT_NULL_VIOLATION: Final = "23502"
SERIALIZATION_FAILURE: Final = "40001"
UNDEFINED_COLUMN: Final = "42703"
VISA_TEST_PAN: Final = "4111111111111111"  # Luhn-valid test card number
BIND_WORKSPACE: Final = text("SELECT set_config('app.workspace_id', :ws, true)")

Outcome = tuple[str | None, str | None]


@dataclass(frozen=True)
class Revisions:
    """The same scenario against revision 0001 (``old``) and head (``new``)."""

    old: Engine
    new: Engine
    rows: "type[Rows]"


@pytest.fixture
def revisions(
    engine_0001: Engine, db_engine: Engine, rows_class: "type[Rows]", require_head_schema: None
) -> Revisions:
    del require_head_schema
    return Revisions(old=engine_0001, new=db_engine, rows=rows_class)


def sqlstate_of(error: DBAPIError) -> Outcome:
    orig = error.orig
    diag = getattr(orig, "diag", None)
    return getattr(orig, "sqlstate", None), getattr(diag, "constraint_name", None)


def run(
    engine: Engine,
    rows_class: "type[Rows]",
    action: "Callable[[Rows], object]",
    *,
    commit: bool = False,
) -> Outcome:
    """Run ``action`` in one transaction; return the failure (SQLSTATE, constraint) or OK."""
    with engine.connect() as connection:
        transaction = connection.begin()
        try:
            action(rows_class(connection))
            if commit:
                transaction.commit()
        except DBAPIError as exc:
            return sqlstate_of(exc)
        finally:
            if transaction.is_active:
                transaction.rollback()
    return OK


def committed[R](engine: Engine, rows_class: "type[Rows]", build: "Callable[[Rows], R]") -> R:
    """Create fixture rows in their own, committed transaction."""
    with engine.begin() as connection:
        return build(rows_class(connection))


def column_names(engine: Engine, table: str) -> set[str]:
    with engine.connect() as connection:
        return set(
            connection.execute(
                text(
                    "SELECT column_name FROM information_schema.columns "
                    "WHERE table_schema = 'public' AND table_name = :table"
                ),
                {"table": table},
            ).scalars()
        )


# --- R2-01: session temp tables must not shadow the scope/sum lookups ---------------------


@dataclass(frozen=True)
class LoginRole:
    name: str
    password: str

    def url(self, base: URL) -> URL:
        return base.set(username=self.name, password=self.password)


@pytest.fixture
def unprivileged_role(
    admin_database_url: URL, test_database_url: URL, engine_0001: Engine
) -> Iterator[LoginRole]:
    """A temporary non-superuser LOGIN role with plain table privileges and TEMP on both
    databases; dropped afterwards. Since revision 0003 (T-006) nobody holds TEMP and tenant
    tables are under row-level security: the role gets TEMP explicitly -- so these tests
    keep proving the pinned search_path on its own, independent of the TEMP revocation that
    tests/db/test_rls.py checks -- and membership in cardflow_app, so that the app's
    policies (and EXECUTE on the CHECK helpers) apply to it; the tests bind the workspace."""
    role = LoginRole(f"cardflow_test_role_{secrets.token_hex(4)}", secrets.token_hex(16))
    databases = [test_database_url, engine_0001.url]
    admin = create_engine(admin_database_url, poolclass=NullPool).execution_options(
        isolation_level="AUTOCOMMIT"
    )
    # Role name and password are random hex: safe to inline into DDL.
    with admin.connect() as connection:
        connection.execute(
            text(
                f"CREATE ROLE {role.name} LOGIN PASSWORD '{role.password}' "
                "NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE"
            )
        )
        connection.execute(text(f"GRANT {APP_ROLE} TO {role.name}"))
    try:
        for url in databases:
            engine = create_engine(url, poolclass=NullPool)
            with engine.begin() as connection:
                connection.execute(
                    text(f'GRANT TEMPORARY ON DATABASE "{url.database}" TO {role.name}')
                )
                connection.execute(text(f"GRANT USAGE ON SCHEMA public TO {role.name}"))
                connection.execute(
                    text(
                        "GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public "
                        f"TO {role.name}"
                    )
                )
                connection.execute(
                    text(f"GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO {role.name}")
                )
            engine.dispose()
        yield role
    finally:
        for url in databases:
            engine = create_engine(url, poolclass=NullPool)
            with engine.begin() as connection:
                connection.execute(text(f"DROP OWNED BY {role.name}"))
            engine.dispose()
        with admin.connect() as connection:
            connection.execute(text(f"DROP ROLE {role.name}"))
        admin.dispose()


def _as_role(role: LoginRole, engine: Engine) -> Engine:
    return create_engine(role.url(engine.url), poolclass=NullPool)


def test_r2_01_temp_table_cannot_fake_the_template_scope(
    revisions: Revisions, unprivileged_role: LoginRole
) -> None:
    """R2-01: a non-superuser shadows ``banks`` with a temp table to reference another
    workspace's private bank. 0001: accepted. Head: rejected (pinned search_path)."""

    def attempt(engine: Engine) -> Outcome:
        mine, foreign_bank = committed(
            engine, revisions.rows, lambda rows: (rows.workspace(), rows.bank(rows.workspace()))
        )
        role_engine = _as_role(unprivileged_role, engine)
        try:
            with role_engine.connect() as connection:
                transaction = connection.begin()
                try:
                    user = connection.execute(text("SELECT current_user")).scalar_one()
                    assert user == unprivileged_role.name
                    connection.execute(BIND_WORKSPACE, {"ws": str(mine)})
                    connection.execute(text("CREATE TEMP TABLE banks (id uuid, workspace_id uuid)"))
                    connection.execute(
                        text("INSERT INTO pg_temp.banks VALUES (:id, NULL)"), {"id": foreign_bank}
                    )
                    connection.execute(
                        insert(T["credit_accounts"]).values(
                            workspace_id=mine,
                            bank_id=foreign_bank,
                            holder_alias="me",
                            status="active",
                        )
                    )
                except DBAPIError as exc:
                    return sqlstate_of(exc)
                finally:
                    transaction.rollback()
        finally:
            role_engine.dispose()
        return OK

    assert attempt(revisions.old) == OK
    assert attempt(revisions.new) == (FOREIGN_KEY_VIOLATION, "credit_accounts_bank_scope")


def test_r2_01_temp_table_cannot_fake_the_allocation_sum(
    revisions: Revisions, unprivileged_role: LoginRole
) -> None:
    """R2-01 (review C4): shadowing the allocation tables lets 999999 be allocated on a
    100000 repayment at 0001; at head the check reads public tables only."""

    def attempt(engine: Engine) -> Outcome:
        account, repayment, statement = committed(
            engine,
            revisions.rows,
            lambda rows: (
                account := rows.account(),
                rows.repayment(account, 100_000),
                rows.statement(account),
            ),
        )
        role_engine = _as_role(unprivileged_role, engine)
        try:
            with role_engine.connect() as connection:
                transaction = connection.begin()
                try:
                    connection.execute(BIND_WORKSPACE, {"ws": str(account.workspace_id)})
                    for shadow in ("repayment_allocations", "repayment_allocation_totals"):
                        connection.execute(
                            text(
                                f"CREATE TEMP TABLE {shadow} (repayment_id uuid, "
                                "statement_id uuid, workspace_id uuid, deleted_at timestamptz, "
                                "amount_minor bigint, allocated_minor bigint)"
                            )
                        )
                    connection.execute(
                        text(
                            "INSERT INTO public.repayment_allocations "
                            "(workspace_id, repayment_id, statement_id, amount_minor) "
                            "VALUES (:ws, :repayment, :statement, 999999)"
                        ),
                        {
                            "ws": account.workspace_id,
                            "repayment": repayment,
                            "statement": statement,
                        },
                    )
                    transaction.commit()
                except DBAPIError as exc:
                    return sqlstate_of(exc)
                finally:
                    if transaction.is_active:
                        transaction.rollback()
        finally:
            role_engine.dispose()
        return OK

    assert attempt(revisions.old) == OK
    assert attempt(revisions.new) == (CHECK_VIOLATION, "repayment_allocations_within_amount")


# --- R2-02: the allocation sum holds in REPEATABLE READ too --------------------------------


def _waiting_on_lock(monitor: Connection, pid: int) -> bool:
    return bool(
        monitor.execute(
            text("SELECT wait_event_type = 'Lock' FROM pg_stat_activity WHERE pid = :pid"),
            {"pid": pid},
        ).scalar()
    )


def _repeatable_read_race(revisions: Revisions, engine: Engine) -> tuple[list[Outcome], int]:
    account, repayment, first, second = committed(
        engine,
        revisions.rows,
        lambda rows: (
            account := rows.account(),
            rows.repayment(account, 100_000),
            rows.statement(account, date(2026, 10, 10)),
            rows.statement(account, date(2026, 11, 10)),
        ),
    )
    outcomes: list[Outcome] = []
    inserted = threading.Event()
    proceed = threading.Event()
    with (
        engine.connect() as session_1,
        engine.connect() as session_2,
        engine.connect() as monitor,
    ):
        session_1.execution_options(isolation_level="REPEATABLE READ")
        session_2.execution_options(isolation_level="REPEATABLE READ")
        session_1.begin()
        session_2.begin()
        pid_2 = session_2.execute(text("SELECT pg_backend_pid()")).scalar_one()  # snapshot
        revisions.rows(session_1).allocation(account.workspace_id, repayment, first, 70_000)

        def second_session() -> None:
            try:
                revisions.rows(session_2).allocation(
                    account.workspace_id, repayment, second, 60_000
                )
                inserted.set()
                proceed.wait(30)
                session_2.commit()
                outcomes.append(OK)
            except DBAPIError as exc:
                outcomes.append(sqlstate_of(exc))
                session_2.rollback()

        worker = threading.Thread(target=second_session, daemon=True)
        worker.start()
        deadline = time.monotonic() + 30
        while not (inserted.is_set() or _waiting_on_lock(monitor, pid_2)):
            assert time.monotonic() < deadline
            time.sleep(0.05)
        session_1.commit()
        proceed.set()
        worker.join(30)
        assert not worker.is_alive()
    with engine.connect() as connection:
        total = connection.execute(
            text(
                "SELECT coalesce(sum(amount_minor), 0) FROM repayment_allocations "
                "WHERE repayment_id = :id AND deleted_at IS NULL"
            ),
            {"id": repayment},
        ).scalar_one()
    return outcomes, int(total)


def test_r2_02_allocation_sum_holds_under_repeatable_read(revisions: Revisions) -> None:
    """R2-02 (review C1): two REPEATABLE READ sessions allocate 70000 + 60000 on 100000.
    0001: both commit (130000). Head: the second fails with 40001, total stays 70000."""
    old_outcomes, old_total = _repeatable_read_race(revisions, revisions.old)
    new_outcomes, new_total = _repeatable_read_race(revisions, revisions.new)

    assert (old_outcomes, old_total) == ([OK], 130_000)
    assert new_outcomes == [(SERIALIZATION_FAILURE, None)]
    assert new_total == 70_000


# --- R2-03 / decision 2: bank facts are immutable; lines belong to their version's tx ----


def test_r2_03_statement_lines_are_immutable(revisions: Revisions) -> None:
    """R2-03 (review L1-L3): lines of a bank version could be rewritten, deleted and appended."""
    lines = T["statement_lines"]

    def build(rows: "Rows") -> tuple[uuid.UUID, uuid.UUID, uuid.UUID]:
        account = rows.account()
        version = rows.statement_version(account.workspace_id, rows.statement(account))
        return account.workspace_id, version, rows.statement_line(account.workspace_id, version)

    for engine, expected in (
        (revisions.old, (OK, OK, OK)),
        (
            revisions.new,
            (
                (INTEGRITY_CONSTRAINT_VIOLATION, "statement_lines_immutable"),
                (INTEGRITY_CONSTRAINT_VIOLATION, "statement_lines_no_delete"),
                (INTEGRITY_CONSTRAINT_VIOLATION, "statement_lines_same_transaction"),
            ),
        ),
    ):
        workspace, version, line = committed(engine, revisions.rows, build)
        rewrite = run(
            engine,
            revisions.rows,
            lambda rows, line=line: rows.connection.execute(
                update(lines).where(lines.c.id == line).values(amount_minor=1)
            ),
        )
        remove = run(
            engine,
            revisions.rows,
            lambda rows, line=line: rows.connection.execute(
                lines.delete().where(lines.c.id == line)
            ),
        )
        append = run(
            engine,
            revisions.rows,
            lambda rows, ws=workspace, v=version: rows.statement_line(ws, v, line_no=2),
        )
        assert (rewrite, remove, append) == expected


def test_r2_03_lines_are_written_with_their_version_even_in_savepoints(
    conn: Connection, rows: "Rows", require_head_schema: None
) -> None:
    """R2-03: same-transaction writes (also from a released savepoint) stay possible."""
    del require_head_schema
    account = rows.account()
    with conn.begin_nested():
        version = rows.statement_version(account.workspace_id, rows.statement(account))
    rows.statement_line(account.workspace_id, version, line_no=1)
    with conn.begin_nested():
        rows.statement_line(account.workspace_id, version, line_no=2)


def test_r2_03_statement_version_only_takes_the_tombstone(revisions: Revisions) -> None:
    """R2-03 / decision 2: moving or annotating a version was possible at 0001; at head the
    only UPDATE is deleted_at NULL -> value, once."""

    def build(rows: "Rows") -> tuple[uuid.UUID, uuid.UUID]:
        account = rows.account()
        statement = rows.statement(account)
        other = rows.statement(account, date(2026, 12, 10))
        return rows.statement_version(account.workspace_id, statement), other

    versions = T["statement_versions"]
    for engine, expected in (
        (revisions.old, (OK, OK)),
        (
            revisions.new,
            (
                (INTEGRITY_CONSTRAINT_VIOLATION, "statement_versions_immutable"),
                (INTEGRITY_CONSTRAINT_VIOLATION, "statement_versions_immutable"),
            ),
        ),
    ):
        version, other_statement = committed(engine, revisions.rows, build)
        move = run(
            engine,
            revisions.rows,
            lambda rows, v=version, s=other_statement: rows.connection.execute(
                update(versions).where(versions.c.id == v).values(statement_id=s, version_no=2)
            ),
        )
        annotate = run(
            engine,
            revisions.rows,
            lambda rows, v=version: rows.connection.execute(
                update(versions).where(versions.c.id == v).values(reason="edited later")
            ),
        )
        assert (move, annotate) == expected

    version, _other = committed(revisions.new, revisions.rows, build)
    tombstone = update(versions).where(versions.c.id == version).values(deleted_at=text("now()"))
    assert (
        run(
            revisions.new,
            revisions.rows,
            lambda rows: rows.connection.execute(tombstone),
            commit=True,
        )
        == OK
    )
    assert run(revisions.new, revisions.rows, lambda rows: rows.connection.execute(tombstone)) == (
        INTEGRITY_CONSTRAINT_VIOLATION,
        "statement_versions_immutable",
    )


# --- R2-04 / decision 3: currency consistency by composite foreign keys -------------------


def test_r2_04_currency_must_match_the_account(revisions: Revisions) -> None:
    """R2-04 (review C5/I5): a CNY sub-account could become USD under its CNY facts, and a
    USD hold/transaction/repayment could sit on a CNY sub-account."""

    def build(rows: "Rows") -> tuple["Account", uuid.UUID, uuid.UUID]:
        account = rows.account()
        rows.repayment(account, 1_000)
        usd_cash = rows.cash_account(account.workspace_id, "USD")
        cny_cash = rows.cash_account(account.workspace_id, "CNY")
        return account, usd_cash, cny_cash

    def scenarios(
        account: "Account", usd_cash: uuid.UUID, cny_cash: uuid.UUID
    ) -> list[Callable[["Rows"], object]]:
        currency_accounts = T["currency_accounts"]
        return [
            lambda rows: rows.connection.execute(
                update(currency_accounts)
                .where(currency_accounts.c.id == account.currency_account_id)
                .values(currency="USD")
            ),
            lambda rows: rows.insert(
                "preauth_holds",
                workspace_id=account.workspace_id,
                currency_account_id=account.currency_account_id,
                amount_minor=100,
                currency="USD",
                held_at=text("now()"),
                held_tz="UTC",
                time_precision="datetime",
                status="active",
                source_kind="manual",
                confirmation_level="user_confirmed",
            ),
            lambda rows: rows.transaction(account, currency="USD"),
            lambda rows: rows.repayment(account, 500, currency="USD"),
            lambda rows: rows.insert(
                "cash_transfers",
                workspace_id=account.workspace_id,
                from_cash_account_id=cny_cash,
                to_cash_account_id=usd_cash,
                amount_minor=100,
                currency="CNY",
                sent_on=date(2026, 10, 16),
            ),
        ]

    old = [
        run(revisions.old, revisions.rows, scenario)
        for scenario in scenarios(*committed(revisions.old, revisions.rows, build))
    ]
    new = [
        run(revisions.new, revisions.rows, scenario)
        for scenario in scenarios(*committed(revisions.new, revisions.rows, build))
    ]

    assert old == [OK] * 5
    assert new == [
        (INTEGRITY_CONSTRAINT_VIOLATION, "currency_accounts_identity_immutable"),
        (FOREIGN_KEY_VIOLATION, "fk_preauth_holds_currency_account_id_currency"),
        (FOREIGN_KEY_VIOLATION, "fk_transactions_currency_account_id_currency"),
        (FOREIGN_KEY_VIOLATION, "fk_repayments_currency_account_id_currency"),
        (FOREIGN_KEY_VIOLATION, "fk_cash_transfers_to_cash_account_id_currency"),
    ]


def test_r2_04_plan_allocation_currency_follows_the_plan(revisions: Revisions) -> None:
    """R2-04: a CNY plan could allocate onto a USD sub-account / repay from a USD cash account."""

    def build(rows: "Rows") -> dict[str, uuid.UUID]:
        account = rows.account(currency="USD")
        plan = rows.plan(account.workspace_id, "CNY")
        return {
            "workspace": account.workspace_id,
            "currency_account": account.currency_account_id,
            "card": rows.card(account.workspace_id, account.credit_account_id),
            "cash": rows.cash_account(account.workspace_id, "CNY"),
            "run": rows.plan_run(account.workspace_id, plan),
        }

    def allocate(ids: dict[str, uuid.UUID]) -> Callable[["Rows"], object]:
        return lambda rows: rows.insert(
            "plan_allocations",
            workspace_id=ids["workspace"],
            run_id=ids["run"],
            currency_account_id=ids["currency_account"],
            card_id=ids["card"],
            amount_minor=1_000,
            statement_date=date(2026, 11, 10),
            due_date=date(2026, 11, 28),
            repay_on=date(2026, 11, 28),
            repay_from_cash_account_id=ids["cash"],
            buffer_days=43,
        )

    assert (
        run(
            revisions.old, revisions.rows, allocate(committed(revisions.old, revisions.rows, build))
        )
        == OK
    )
    assert run(
        revisions.new, revisions.rows, allocate(committed(revisions.new, revisions.rows, build))
    ) == (
        FOREIGN_KEY_VIOLATION,
        "fk_plan_allocations_currency_account_id_currency",
    )


# --- R2-05: same-account consistency -------------------------------------------------------


def test_r2_05_relations_stay_within_one_account(revisions: Revisions) -> None:
    """R2-05 (review I1-I4 and siblings): cross-account links inside one workspace."""

    def build(rows: "Rows") -> dict[str, Any]:
        workspace = rows.workspace()
        a = rows.account(workspace)
        b = rows.account(workspace)
        cash_a = rows.cash_account(workspace)
        cash_b = rows.cash_account(workspace)
        return {
            "a": a,
            "b": b,
            "card_b": rows.card(workspace, b.credit_account_id),
            "statement_b": rows.statement(b),
            "transaction_a": rows.transaction(a),
            "cash_a": cash_a,
            "snapshot_a": rows.cash_snapshot(workspace, cash_a),
            "event_b": rows.cash_event(workspace, cash_b),
            "cash_b": cash_b,
            "repayment_b": rows.repayment(b, 1_000, cash_account_id=cash_b),
        }

    def scenarios(ids: dict[str, Any]) -> list[Callable[["Rows"], object]]:
        a, b = ids["a"], ids["b"]
        workspace = a.workspace_id
        return [
            lambda rows: rows.transaction(a, card_id=ids["card_b"]),
            lambda rows: rows.insert(
                "rule_bindings",
                workspace_id=workspace,
                credit_account_id=a.credit_account_id,
                currency_account_id=b.currency_account_id,
                billing_rule_version_id=rows.rule_version(
                    workspace, "credit_account", a.credit_account_id, date(2026, 1, 1)
                ),
                effective_from=date(2026, 1, 1),
            ),
            lambda rows: rows.insert(
                "statement_attributions",
                workspace_id=workspace,
                transaction_id=ids["transaction_a"],
                statement_id=ids["statement_b"],
                confirmation_level="system_estimated",
            ),
            lambda rows: rows.insert(
                "charges",
                workspace_id=workspace,
                currency_account_id=a.currency_account_id,
                statement_id=ids["statement_b"],
                kind="late_fee",
                amount_minor=1_000,
                currency="CNY",
                charged_on=date(2026, 11, 28),
                source_kind="statement",
                confirmation_level="bank_confirmed",
            ),
            lambda rows: rows.insert(
                "snapshot_included_events",
                workspace_id=workspace,
                snapshot_id=ids["snapshot_a"],
                cash_event_id=ids["event_b"],
            ),
            lambda rows: rows.insert(
                "cash_transfers",
                workspace_id=workspace,
                from_cash_account_id=ids["cash_a"],
                to_cash_account_id=ids["cash_b"],
                amount_minor=100,
                currency="CNY",
                sent_on=date(2026, 10, 16),
                out_event_id=ids["event_b"],
            ),
            lambda rows: rows.cash_event(
                workspace,
                ids["cash_a"],
                amount_minor=-1_000,
                category="repayment",
                linked_repayment_id=ids["repayment_b"],
            ),
        ]

    old = [
        run(revisions.old, revisions.rows, scenario)
        for scenario in scenarios(committed(revisions.old, revisions.rows, build))
    ]
    new = [
        run(revisions.new, revisions.rows, scenario)
        for scenario in scenarios(committed(revisions.new, revisions.rows, build))
    ]

    assert old == [OK] * 7
    assert new == [
        (FOREIGN_KEY_VIOLATION, "fk_transactions_credit_account_id_card_id"),
        (FOREIGN_KEY_VIOLATION, "fk_rule_bindings_credit_account_id_currency_account_id"),
        (FOREIGN_KEY_VIOLATION, "fk_statement_attributions_currency_account_id_statement_id"),
        (FOREIGN_KEY_VIOLATION, "fk_charges_currency_account_id_statement_id"),
        (FOREIGN_KEY_VIOLATION, "fk_snapshot_included_events_cash_account_id_cash_event_id"),
        (FOREIGN_KEY_VIOLATION, "fk_cash_transfers_from_cash_account_id_out_event_id"),
        (FOREIGN_KEY_VIOLATION, "fk_cash_events_cash_account_id_linked_repayment_id"),
    ]


def test_r2_05_derived_account_columns_are_filled_by_the_database(
    conn: Connection, rows: "Rows", require_head_schema: None
) -> None:
    """R2-05: clients never supply the redundant account columns; a wrong value is replaced."""
    del require_head_schema
    account = rows.account()
    other = rows.account(account.workspace_id)
    transaction = rows.transaction(account, credit_account_id=other.credit_account_id)
    transactions = T["transactions"]

    derived = conn.execute(
        select(transactions.c.credit_account_id).where(transactions.c.id == transaction)
    ).scalar_one()
    assert derived == account.credit_account_id


# --- R2-06: tombstones do not block re-creating a natural key ------------------------------


def test_r2_06_tombstoned_natural_keys_can_be_recreated(revisions: Revisions) -> None:
    """R2-06 (review E1/C2): deleted statements, sub-accounts, pool memberships, allocations
    and documents blocked their natural key forever at 0001."""

    def build(rows: "Rows") -> dict[str, object]:
        account = rows.account()
        workspace = account.workspace_id
        pool = rows.insert("credit_pools", workspace_id=workspace, bank_id=rows.bank(), name="p")
        member = rows.insert(
            "credit_pool_members",
            workspace_id=workspace,
            pool_id=pool,
            credit_account_id=account.credit_account_id,
        )
        usd = rows.currency_account(workspace, account.credit_account_id, "USD")
        statement = rows.statement(account, date(2026, 9, 10))
        other_statement = rows.statement(account, date(2026, 8, 10))
        repayment = rows.repayment(account, 10_000)
        return {
            "account": account,
            "pool": pool,
            "member": member,
            "usd": usd,
            "statement": statement,
            "other_statement": other_statement,
            "repayment": repayment,
            "allocation": rows.allocation(workspace, repayment, other_statement, 1_000),
            "document": rows.source_document(workspace),
        }

    def tombstone_then_recreate(ids: dict[str, Any]) -> list[Callable[["Rows"], object]]:
        account = ids["account"]
        workspace = account.workspace_id

        def again(
            table: str, row_id: object, recreate: Callable[["Rows"], object]
        ) -> Callable[["Rows"], object]:
            def action(rows: "Rows") -> object:
                rows.connection.execute(
                    update(T[table]).where(T[table].c.id == row_id).values(deleted_at=text("now()"))
                )
                return recreate(rows)

            return action

        sha256 = select(T["source_documents"].c.sha256).where(
            T["source_documents"].c.id == ids["document"]
        )
        return [
            again(
                "statements",
                ids["statement"],
                lambda rows: rows.statement(account, date(2026, 9, 10)),
            ),
            again(
                "currency_accounts",
                ids["usd"],
                lambda rows: rows.currency_account(workspace, account.credit_account_id, "USD"),
            ),
            again(
                "credit_pool_members",
                ids["member"],
                lambda rows: rows.insert(
                    "credit_pool_members",
                    workspace_id=workspace,
                    pool_id=ids["pool"],
                    credit_account_id=account.credit_account_id,
                ),
            ),
            again(
                "repayment_allocations",
                ids["allocation"],
                lambda rows: rows.allocation(
                    workspace, ids["repayment"], ids["other_statement"], 2_000
                ),
            ),
            again(
                "source_documents",
                ids["document"],
                lambda rows: rows.insert(
                    "source_documents",
                    workspace_id=workspace,
                    sha256=rows.connection.execute(sha256).scalar_one(),
                    mime="application/pdf",
                    size_bytes=1024,
                    storage_key="again",
                    dek_wrapped=b"\x01" * 40,
                ),
            ),
        ]

    old = [
        run(revisions.old, revisions.rows, action, commit=True)
        for action in tombstone_then_recreate(committed(revisions.old, revisions.rows, build))
    ]
    new = [
        run(revisions.new, revisions.rows, action, commit=True)
        for action in tombstone_then_recreate(committed(revisions.new, revisions.rows, build))
    ]

    assert old == [
        (UNIQUE_VIOLATION, "uq_statements_currency_account_id_statement_date"),
        (UNIQUE_VIOLATION, "uq_currency_accounts_credit_account_id_currency"),
        (UNIQUE_VIOLATION, "uq_credit_pool_members_pool_id_credit_account_id"),
        (UNIQUE_VIOLATION, "pk_repayment_allocations"),
        (UNIQUE_VIOLATION, "uq_source_documents_workspace_id_sha256"),
    ]
    assert new == [OK] * 5


# --- R2-07: lossless pull cursor -----------------------------------------------------------


def _insert_change(connection: Connection, workspace: uuid.UUID) -> int:
    return connection.execute(
        text(
            "INSERT INTO sync_changes (workspace_id, table_name, row_id, op, row_version) "
            "VALUES (:ws, 'cards', :row, 'insert', 1) RETURNING seq"
        ),
        {"ws": workspace, "row": uuid.uuid4()},
    ).scalar_one()


def test_r2_07_seq_cursor_loses_late_commits_at_0001(
    engine_0001: Engine, rows_class: "type[Rows]"
) -> None:
    """R2-07 (review E2): seq is taken at INSERT; a seq cursor skips a late committer."""
    workspace = committed(engine_0001, rows_class, lambda rows: rows.workspace())
    with (
        engine_0001.connect() as late,
        engine_0001.connect() as early,
        engine_0001.connect() as reader,
    ):
        late.begin()
        late_seq = _insert_change(late, workspace)
        early.begin()
        early_seq = _insert_change(early, workspace)
        early.commit()
        first_pull = (
            reader.execute(
                text(
                    "SELECT seq FROM sync_changes WHERE workspace_id = :ws AND seq > 0 ORDER BY seq"
                ),
                {"ws": workspace},
            )
            .scalars()
            .all()
        )
        reader.rollback()
        late.commit()
        second_pull = (
            reader.execute(
                text(
                    "SELECT seq FROM sync_changes "
                    "WHERE workspace_id = :ws AND seq > :c ORDER BY seq"
                ),
                {"ws": workspace, "c": max(first_pull)},
            )
            .scalars()
            .all()
        )
        reader.rollback()

    assert late_seq < early_seq
    assert first_pull == [early_seq]
    assert second_pull == []  # late_seq is never delivered


def _pull(
    reader: Connection, workspace: uuid.UUID, cursor: tuple[str, int]
) -> list[tuple[str, int]]:
    """(txid, seq) cursor: rows of finished transactions only, in (txid, seq) order."""
    rows = reader.execute(
        text(
            "SELECT txid::text, seq FROM sync_changes "
            "WHERE workspace_id = :ws AND (txid, seq) > (CAST(:t AS xid8), :s) "
            "AND txid < pg_snapshot_xmin(pg_current_snapshot()) ORDER BY txid, seq"
        ),
        {"ws": workspace, "t": cursor[0], "s": cursor[1]},
    ).all()
    reader.rollback()
    return [(txid, seq) for txid, seq in rows]


def test_r2_07_txid_cursor_delivers_every_change(
    db_engine: Engine, rows_class: "type[Rows]", require_head_schema: None
) -> None:
    """R2-07: with sync_changes.txid a (txid, seq) cursor loses nothing -- also when the late
    committer holds the lower seq *and* the higher xid (where "read by seq, stop at the first
    in-flight txid" would skip it: the in-flight row is invisible to the reader)."""
    del require_head_schema
    workspace = committed(db_engine, rows_class, lambda rows: rows.workspace())
    with db_engine.connect() as late, db_engine.connect() as early, db_engine.connect() as reader:
        early.begin()
        early.execute(text("SELECT pg_current_xact_id()"))  # early gets the lower xid
        late.begin()
        late_seq = _insert_change(late, workspace)  # but late gets the lower seq
        early_seq = _insert_change(early, workspace)
        early.commit()
        first = _pull(reader, workspace, ("0", 0))
        stop_rule = (
            reader.execute(  # architecture §6 wording: seq order, stop at in-flight
                text(
                    "SELECT seq FROM sync_changes WHERE workspace_id = :ws AND seq > 0 "
                    "AND txid < pg_snapshot_xmin(pg_current_snapshot()) ORDER BY seq"
                ),
                {"ws": workspace},
            )
            .scalars()
            .all()
        )
        reader.rollback()
        late.commit()
        second = _pull(reader, workspace, first[-1])

    assert late_seq < early_seq
    assert [seq for _txid, seq in first] == [early_seq]
    assert stop_rule == [early_seq]  # a seq cursor would now jump past late_seq
    assert [seq for _txid, seq in second] == [late_seq]


# --- R2-08: time zone, precision and recorded_at ------------------------------------------


def test_r2_08_event_times_carry_zone_precision_and_recorded_at(revisions: Revisions) -> None:
    """R2-08: repayments had no tz/precision/recorded_at; cash_events.event_at no tz."""
    added = {
        "repayments": {
            "event_tz",
            "cash_debited_precision",
            "credit_posted_precision",
            "recorded_at",
        },
        "transactions": {"observed_at"},
        "cash_events": {"event_tz", "recorded_at"},
    }
    for table, columns in added.items():
        assert columns.isdisjoint(column_names(revisions.old, table))
        assert columns <= column_names(revisions.new, table)

    account = committed(revisions.new, revisions.rows, lambda rows: rows.account())
    debited = {"cash_debited_at": text("now()")}
    assert run(
        revisions.new, revisions.rows, lambda rows: rows.repayment(account, 100, **debited)
    ) == (
        CHECK_VIOLATION,
        "ck_repayments_cash_debited_precision_pair",
    )
    assert run(
        revisions.new,
        revisions.rows,
        lambda rows: rows.repayment(account, 100, cash_debited_precision="date", **debited),
    ) == (CHECK_VIOLATION, "ck_repayments_times_need_tz")
    assert (
        run(
            revisions.new,
            revisions.rows,
            lambda rows: rows.repayment(
                account, 100, cash_debited_precision="date", event_tz="Asia/Shanghai", **debited
            ),
        )
        == OK
    )


# --- R2-09: no card numbers in free text ---------------------------------------------------


@pytest.mark.parametrize(
    ("value", "expected"),
    [
        (VISA_TEST_PAN, True),
        ("4111 1111 1111 1111", True),
        ("4111-1111-1111-1111", True),
        ("POS 4111111111111111 SHANGHAI", True),
        ("4111111111111112", False),  # fails Luhn
        ("411111111111", False),  # 12 digits
        ("41111111111111111111", False),  # 20 digits: not a card number
        ("ORDER 2026-10-16 AMOUNT 120.00", False),
        (None, False),
    ],
)
def test_r2_09_looks_like_pan(
    conn: Connection, value: str | None, expected: bool, require_head_schema: None
) -> None:
    """R2-09: 13-19 digits, single spaces/hyphens allowed, Luhn-valid."""
    del require_head_schema
    assert conn.execute(text("SELECT looks_like_pan(:v)"), {"v": value}).scalar_one() is expected


def test_r2_09_free_text_rejects_card_numbers(revisions: Revisions) -> None:
    """R2-09 (review I9): a full card number in a statement line description was stored."""

    def build(rows: "Rows") -> tuple[uuid.UUID, uuid.UUID]:
        account = rows.account()
        return account.workspace_id, rows.statement(account)

    def store(ids: tuple[uuid.UUID, uuid.UUID]) -> Callable[["Rows"], object]:
        def action(rows: "Rows") -> object:
            version = rows.statement_version(ids[0], ids[1])
            return rows.statement_line(ids[0], version, description=f"POS {VISA_TEST_PAN} SH")

        return action

    assert (
        run(revisions.old, revisions.rows, store(committed(revisions.old, revisions.rows, build)))
        == OK
    )
    assert run(
        revisions.new, revisions.rows, store(committed(revisions.new, revisions.rows, build))
    ) == (
        CHECK_VIOLATION,
        "ck_statement_lines_description_not_pan",
    )


def test_r2_09_bank_reference_candidates_are_exempt(
    rows: "Rows", require_head_schema: None
) -> None:
    """R2-09: long bank reference numbers are legitimate extraction candidates."""
    del require_head_schema
    workspace = rows.workspace()
    job = rows.insert(
        "parse_jobs",
        workspace_id=workspace,
        source_document_id=rows.source_document(workspace),
        status="running",
    )
    rows.insert(
        "extraction_candidates",
        workspace_id=workspace,
        parse_job_id=job,
        field_path="transactions[3].bank_reference",
        raw_value=VISA_TEST_PAN,
        raw_location={"page": 1},
        parser_version="t",
        confidence=1,
    )


# --- R2-10: the purge gate needs a token of the current transaction ------------------------


def test_r2_10_purge_gate(revisions: Revisions) -> None:
    """R2-10 (review SV6/P2): a session-level SET app.purge stayed open for later
    transactions; at head only the current transaction id opens the gate."""

    def build(rows: "Rows") -> uuid.UUID:
        account = rows.account()
        return rows.statement_version(account.workspace_id, rows.statement(account))

    def delete_after_session_level_set(engine: Engine) -> Outcome:
        version = committed(engine, revisions.rows, build)
        private = create_engine(engine.url, poolclass=NullPool)
        try:
            with private.connect() as connection:
                connection.execute(text("SET app.purge = 'on'"))  # session level
                connection.commit()
                versions = T["statement_versions"]
                with connection.begin():
                    try:
                        connection.execute(versions.delete().where(versions.c.id == version))
                    except DBAPIError as exc:
                        return sqlstate_of(exc)
        finally:
            private.dispose()
        return OK

    assert delete_after_session_level_set(revisions.old) == OK
    assert delete_after_session_level_set(revisions.new) == (
        INTEGRITY_CONSTRAINT_VIOLATION,
        "statement_versions_no_delete",
    )

    version = committed(revisions.new, revisions.rows, build)
    versions = T["statement_versions"]

    def with_token(token: str) -> Callable[["Rows"], object]:
        def action(rows: "Rows") -> object:
            rows.connection.execute(text(f"SELECT set_config('app.purge', {token}, true)"))
            return rows.connection.execute(versions.delete().where(versions.c.id == version))

        return action

    assert run(revisions.new, revisions.rows, with_token("'on'")) == (
        INTEGRITY_CONSTRAINT_VIOLATION,
        "statement_versions_no_delete",
    )
    assert run(revisions.new, revisions.rows, with_token("pg_current_xact_id()::text")) == OK


# --- R2-11 .. R2-18 -----------------------------------------------------------------------


def test_r2_11_workspace_id_is_immutable_everywhere(revisions: Revisions) -> None:
    """R2-11 (review B11): a credit account could be moved into another workspace."""

    def move(engine: Engine) -> Outcome:
        account, other = committed(
            engine,
            revisions.rows,
            lambda rows: (rows.credit_account(rows.workspace()), rows.workspace()),
        )
        accounts = T["credit_accounts"]
        return run(
            engine,
            revisions.rows,
            lambda rows: rows.connection.execute(
                update(accounts).where(accounts.c.id == account).values(workspace_id=other)
            ),
        )

    assert move(revisions.old) == OK
    assert move(revisions.new) == (
        INTEGRITY_CONSTRAINT_VIOLATION,
        "credit_accounts_workspace_immutable",
    )


def test_r2_12_nil_workspace_id_rejected(revisions: Revisions) -> None:
    """R2-12 (review N1): the nil UUID collided with the template scope of rule versions."""

    def create(rows: "Rows") -> object:
        return rows.insert(
            "workspaces", id=uuid.UUID(int=0), owner_user_id=rows.insert("users"), kind="real"
        )

    assert run(revisions.old, revisions.rows, create) == OK
    assert run(revisions.new, revisions.rows, create) == (
        CHECK_VIOLATION,
        "ck_workspaces_id_not_nil",
    )


def test_r2_13_private_rules_cannot_claim_review_states(revisions: Revisions) -> None:
    """R2-13 (review R1/R2): a workspace rule could pose as verified/published."""

    def declare(rows: "Rows") -> object:
        account = rows.account()
        return rows.rule_version(
            account.workspace_id,
            "credit_account",
            account.credit_account_id,
            date(2026, 1, 1),
            review_status="verified",
        )

    assert run(revisions.old, revisions.rows, declare) == OK
    assert run(revisions.new, revisions.rows, declare) == (
        CHECK_VIOLATION,
        "ck_billing_rule_versions_workspace_review_status",
    )


def test_r2_14_rule_bindings_do_not_overlap(revisions: Revisions) -> None:
    """R2-14 (review I6): two live bindings of one account overlapped in time."""

    def bind_twice(rows: "Rows") -> object:
        account = rows.account()
        rule = rows.rule_version(
            account.workspace_id, "credit_account", account.credit_account_id, date(2026, 1, 1)
        )
        for start in (date(2026, 1, 1), date(2026, 6, 1)):
            rows.insert(
                "rule_bindings",
                workspace_id=account.workspace_id,
                credit_account_id=account.credit_account_id,
                billing_rule_version_id=rule,
                effective_from=start,
            )
        return None

    assert run(revisions.old, revisions.rows, bind_twice) == OK
    assert run(revisions.new, revisions.rows, bind_twice) == (
        EXCLUSION_VIOLATION,
        "ex_rule_bindings_account_period",
    )


def test_r2_15_inactive_repayments_keep_no_allocations(revisions: Revisions) -> None:
    """R2-15 (review C3): a reversed or tombstoned repayment kept settling statements."""

    def build(rows: "Rows") -> uuid.UUID:
        account = rows.account()
        repayment = rows.repayment(account, 100_000)
        rows.allocation(account.workspace_id, repayment, rows.statement(account), 50_000)
        return repayment

    repayments = T["repayments"]
    for values in ({"status": "reversed"}, {"deleted_at": text("now()")}):
        old_id = committed(revisions.old, revisions.rows, build)
        new_id = committed(revisions.new, revisions.rows, build)
        assert (
            run(
                revisions.old,
                revisions.rows,
                lambda rows, i=old_id, v=values: rows.connection.execute(
                    update(repayments).where(repayments.c.id == i).values(**v)
                ),
                commit=True,
            )
            == OK
        )
        assert run(
            revisions.new,
            revisions.rows,
            lambda rows, i=new_id, v=values: rows.connection.execute(
                update(repayments).where(repayments.c.id == i).values(**v)
            ),
            commit=True,
        ) == (CHECK_VIOLATION, "repayment_allocations_inactive_repayment")


def test_r2_16_amount_signs(revisions: Revisions) -> None:
    """R2-16 (review I7): zero amounts and wrong signs per type/category were accepted."""

    def build(rows: "Rows") -> tuple["Account", uuid.UUID]:
        account = rows.account()
        return account, rows.cash_account(account.workspace_id)

    def scenarios(account: "Account", cash: uuid.UUID) -> list[Callable[["Rows"], object]]:
        return [
            lambda rows: rows.transaction(account, amount_minor=0),
            lambda rows: rows.transaction(account, amount_minor=5_000, txn_type="refund"),
            lambda rows: rows.cash_event(
                account.workspace_id, cash, amount_minor=-100, category="income"
            ),
            lambda rows: rows.insert(
                "charges",
                workspace_id=account.workspace_id,
                currency_account_id=account.currency_account_id,
                kind="interest",
                amount_minor=0,
                currency="CNY",
                charged_on=date(2026, 11, 10),
                source_kind="rule",
                confirmation_level="system_estimated",
            ),
        ]

    old = [
        run(revisions.old, revisions.rows, s)
        for s in scenarios(*committed(revisions.old, revisions.rows, build))
    ]
    new = [
        run(revisions.new, revisions.rows, s)
        for s in scenarios(*committed(revisions.new, revisions.rows, build))
    ]

    assert old == [OK] * 4
    assert new == [
        (CHECK_VIOLATION, "ck_transactions_amount_nonzero"),
        (CHECK_VIOLATION, "ck_transactions_amount_sign"),
        (CHECK_VIOLATION, "ck_cash_events_amount_sign"),
        (CHECK_VIOLATION, "ck_charges_amount_nonzero"),
    ]


def test_r2_16_r2_32_sign_conventions_are_column_comments(revisions: Revisions) -> None:
    """R2-16/R2-32: the sign convention lived in SQL comments of the migration only."""
    query = text(
        "SELECT col_description('public.transactions'::regclass, "
        "(SELECT attnum FROM pg_attribute WHERE attrelid = 'public.transactions'::regclass "
        "AND attname = 'amount_minor'))"
    )
    with revisions.old.connect() as old, revisions.new.connect() as new:
        assert old.execute(query).scalar() is None
        assert "Positive = liability increase" in new.execute(query).scalar_one()


def test_r2_17_state_machine_statuses_are_checked(revisions: Revisions) -> None:
    """R2-17: status columns with a state machine accepted any text."""

    def build(rows: "Rows") -> dict[str, Any]:
        account = rows.account()
        workspace = account.workspace_id
        return {
            "account": account,
            "workspace": workspace,
            "transaction": rows.transaction(account),
            "document": rows.source_document(workspace),
        }

    def scenarios(ids: dict[str, Any]) -> list[Callable[["Rows"], object]]:
        account = ids["account"]
        workspace = ids["workspace"]
        return [
            lambda rows: rows.insert(
                "preauth_holds",
                workspace_id=workspace,
                currency_account_id=account.currency_account_id,
                amount_minor=100,
                currency="CNY",
                held_at=text("now()"),
                held_tz="UTC",
                time_precision="datetime",
                status="bogus",
                source_kind="manual",
                confirmation_level="user_confirmed",
            ),
            lambda rows: rows.insert(
                "installment_plans",
                workspace_id=workspace,
                transaction_id=ids["transaction"],
                principal_minor=1_000,
                periods=3,
                per_period_rate=0,
                fee_mode="per_period",
                status="bogus",
            ),
            lambda rows: rows.insert(
                "parse_jobs",
                workspace_id=workspace,
                source_document_id=ids["document"],
                status="bogus",
            ),
            lambda rows: rows.insert(
                "reconciliation_items",
                workspace_id=workspace,
                kind="missing",
                refs={},
                status="bogus",
            ),
            lambda rows: rows.insert(
                "sync_conflicts",
                workspace_id=workspace,
                table_name="cards",
                row_id=uuid.uuid4(),
                server_version=2,
                client_base_version=1,
                server_payload={},
                client_payload={},
                status="bogus",
            ),
            lambda rows: rows.insert(
                "deletion_tasks", workspace_id=workspace, grace_until=text("now()"), status="bogus"
            ),
        ]

    old = [
        run(revisions.old, revisions.rows, s)
        for s in scenarios(committed(revisions.old, revisions.rows, build))
    ]
    new = [
        run(revisions.new, revisions.rows, s)
        for s in scenarios(committed(revisions.new, revisions.rows, build))
    ]

    assert old == [OK] * 6
    assert new == [
        (CHECK_VIOLATION, "ck_preauth_holds_status"),
        (CHECK_VIOLATION, "ck_installment_plans_status"),
        (CHECK_VIOLATION, "ck_parse_jobs_status"),
        (CHECK_VIOLATION, "ck_reconciliation_items_status"),
        (CHECK_VIOLATION, "ck_sync_conflicts_status"),
        (CHECK_VIOLATION, "ck_deletion_tasks_status"),
    ]


def test_r2_18_no_pool_or_card_replacement_cycles(revisions: Revisions) -> None:
    """R2-18 (review Y1/Y2): 2-cycles in pool hierarchies and card replacement chains."""

    def pools(rows: "Rows") -> object:
        workspace = rows.workspace()
        bank = rows.bank()
        first = rows.insert("credit_pools", workspace_id=workspace, bank_id=bank, name="a")
        second = rows.insert(
            "credit_pools", workspace_id=workspace, bank_id=bank, name="b", parent_pool_id=first
        )
        table = T["credit_pools"]
        return rows.connection.execute(
            update(table).where(table.c.id == first).values(parent_pool_id=second)
        )

    def cards(rows: "Rows") -> object:
        account = rows.account()
        first = rows.card(account.workspace_id, account.credit_account_id, "1111")
        second = rows.card(account.workspace_id, account.credit_account_id, "2222")
        table = T["cards"]
        rows.connection.execute(
            update(table).where(table.c.id == first).values(replaced_by_card_id=second)
        )
        return rows.connection.execute(
            update(table).where(table.c.id == second).values(replaced_by_card_id=first)
        )

    assert (
        run(revisions.old, revisions.rows, pools),
        run(revisions.old, revisions.rows, cards),
    ) == (OK, OK)
    assert run(revisions.new, revisions.rows, pools) == (CHECK_VIOLATION, "credit_pools_no_cycle")
    assert run(revisions.new, revisions.rows, cards) == (
        CHECK_VIOLATION,
        "cards_no_replacement_cycle",
    )


# --- R2-19 .. R2-21 -----------------------------------------------------------------------


def test_r2_19_run_records_and_snapshots_are_not_rewritten(revisions: Revisions) -> None:
    """R2-19: plan runs and limit snapshot amounts could be overwritten."""

    def build(rows: "Rows") -> tuple[uuid.UUID, uuid.UUID]:
        account = rows.account()
        run_id = rows.plan_run(account.workspace_id, rows.plan(account.workspace_id))
        return run_id, rows.limit_snapshot(account)

    def rewrite(ids: tuple[uuid.UUID, uuid.UUID]) -> list[Callable[["Rows"], object]]:
        runs, snapshots = T["plan_runs"], T["limit_snapshots"]
        return [
            lambda rows: rows.connection.execute(
                update(runs).where(runs.c.id == ids[0]).values(business_status="FEASIBLE_ROBUST")
            ),
            lambda rows: rows.connection.execute(
                update(snapshots).where(snapshots.c.id == ids[1]).values(available_raw_minor=1)
            ),
        ]

    old = [
        run(revisions.old, revisions.rows, s)
        for s in rewrite(committed(revisions.old, revisions.rows, build))
    ]
    new_ids = committed(revisions.new, revisions.rows, build)
    new = [run(revisions.new, revisions.rows, s) for s in rewrite(new_ids)]

    assert old == [OK, OK]
    assert new == [
        (INTEGRITY_CONSTRAINT_VIOLATION, "plan_runs_immutable"),
        (INTEGRITY_CONSTRAINT_VIOLATION, "limit_snapshots_amounts_immutable"),
    ]
    runs = T["plan_runs"]
    assert (
        run(
            revisions.new,
            revisions.rows,
            lambda rows: rows.connection.execute(
                update(runs).where(runs.c.id == new_ids[0]).values(deleted_at=text("now()"))
            ),
        )
        == OK
    )


def test_r2_20_attachment_references_are_foreign_keys(revisions: Revisions) -> None:
    """R2-20: a fact could cite another workspace's document; purging kept no metadata row."""

    def build(rows: "Rows") -> tuple["Account", uuid.UUID]:
        return rows.account(), rows.source_document(rows.workspace())

    def cite(ids: tuple["Account", uuid.UUID]) -> Callable[["Rows"], object]:
        return lambda rows: rows.limit_snapshot(ids[0], source_document_id=ids[1])

    assert (
        run(revisions.old, revisions.rows, cite(committed(revisions.old, revisions.rows, build)))
        == OK
    )
    assert run(
        revisions.new, revisions.rows, cite(committed(revisions.new, revisions.rows, build))
    ) == (
        FOREIGN_KEY_VIOLATION,
        "fk_limit_snapshots_source_document_id",
    )

    documents = T["source_documents"]

    def purge_blob(tombstone: bool) -> Callable[["Rows"], object]:
        def action(rows: "Rows") -> object:
            document = rows.source_document(rows.workspace())
            values: dict[str, object] = {"storage_key": None, "dek_wrapped": None}
            if tombstone:
                values["deleted_at"] = text("now()")
            return rows.connection.execute(
                update(documents).where(documents.c.id == document).values(**values)
            )

        return action

    assert run(revisions.old, revisions.rows, purge_blob(True))[0] == NOT_NULL_VIOLATION
    assert run(revisions.new, revisions.rows, purge_blob(True)) == OK
    assert run(revisions.new, revisions.rows, purge_blob(False)) == (
        CHECK_VIOLATION,
        "ck_source_documents_blob_while_live",
    )


def test_r2_21_row_version_is_maintained_by_the_database(revisions: Revisions) -> None:
    """R2-21: row_version/updated_at depended on every writer remembering them."""
    accounts = T["credit_accounts"]

    def versions_after_update(engine: Engine) -> tuple[int, bool]:
        account = committed(engine, revisions.rows, lambda rows: rows.account())
        with engine.begin() as connection:
            connection.execute(
                update(accounts)
                .where(accounts.c.id == account.credit_account_id)
                .values(holder_alias="renamed")
            )
        with engine.connect() as connection:
            row_version, changed = connection.execute(
                text(
                    "SELECT a.row_version, a.updated_at > c.created_at FROM credit_accounts a "
                    "JOIN workspaces c ON c.id = a.workspace_id WHERE a.id = :id"
                ),
                {"id": account.credit_account_id},
            ).one()
        return int(row_version), bool(changed)

    assert versions_after_update(revisions.old) == (1, False)
    assert versions_after_update(revisions.new) == (2, True)


# --- R2-23 .. R2-33 -----------------------------------------------------------------------


def test_r2_23_revision_notes_name_the_rls_revision() -> None:
    """R2-23 (docstring part): RLS and roles are revision 0003, not 0002."""
    initial = (API_ROOT / "alembic" / "versions" / "0001_initial.py").read_text(encoding="utf-8")
    migrations = (API_ROOT / "cardflow" / "db" / "migrations.py").read_text(encoding="utf-8")

    assert "grants are revision 0003 (T-006)" in initial
    assert "revision 0003, T-006" in migrations


# --- R2-24: counterexamples the review found missing ----------------------------------------
# RR concurrency: test_r2_02_*; temp-table shadowing with a non-superuser LOGIN role:
# test_r2_01_*; re-creating after a tombstone: test_r2_06_*; leftover session-level purge
# setting: test_r2_10_*. The golden manifest is tests/db/test_db_objects.py.


def _set(table: str, row_id: uuid.UUID, **values: object) -> "Callable[[Rows], object]":
    target = T[table]
    return lambda rows: rows.connection.execute(
        update(target).where(target.c.id == row_id).values(**values)
    )


def test_r2_24_scope_triggers_guard_the_update_path(revisions: Revisions) -> None:
    """R2-24 (mutations M6, M8): the UPDATE path of every scope trigger and the
    currency-account branch of the rule-subject check reject other workspaces' rows.

    0001 already enforced this, but no test exercised it: an INSERT-only scope trigger (M6)
    or a currency-account branch without the workspace condition (M8) passed the whole
    suite. Each mutation now fails here (and in the golden manifest)."""

    def build(rows: "Rows") -> dict[str, Any]:
        foreign = rows.account()
        foreign_bank = rows.bank(foreign.workspace_id)
        mine = rows.account()
        template_bank = rows.bank()
        own_rule = rows.rule_version(
            mine.workspace_id, "credit_account", mine.credit_account_id, date(2026, 1, 1)
        )
        return {
            "foreign": foreign,
            "foreign_bank": foreign_bank,
            "foreign_product": rows.product(foreign_bank, foreign.workspace_id),
            "foreign_rule": rows.rule_version(
                foreign.workspace_id, "credit_account", foreign.credit_account_id, date(2026, 1, 1)
            ),
            "mine": mine,
            "template_product": rows.product(template_bank),
            "pool": rows.insert(
                "credit_pools", workspace_id=mine.workspace_id, bank_id=template_bank, name="p"
            ),
            "binding": rows.insert(
                "rule_bindings",
                workspace_id=mine.workspace_id,
                credit_account_id=mine.credit_account_id,
                billing_rule_version_id=own_rule,
                effective_from=date(2026, 1, 1),
            ),
            "own_rule": own_rule,
            "own_currency_rule": rows.rule_version(
                mine.workspace_id, "currency_account", mine.currency_account_id, date(2026, 1, 1)
            ),
        }

    def scenarios(ids: dict[str, Any]) -> "list[Callable[[Rows], object]]":
        mine, foreign = ids["mine"], ids["foreign"]
        return [
            _set("card_products", ids["template_product"], bank_id=ids["foreign_bank"]),
            _set("credit_accounts", mine.credit_account_id, bank_id=ids["foreign_bank"]),
            _set("credit_accounts", mine.credit_account_id, product_id=ids["foreign_product"]),
            _set("credit_pools", ids["pool"], bank_id=ids["foreign_bank"]),
            _set("rule_bindings", ids["binding"], billing_rule_version_id=ids["foreign_rule"]),
            _set("billing_rule_versions", ids["own_rule"], subject_id=foreign.credit_account_id),
            _set(
                "billing_rule_versions",
                ids["own_currency_rule"],
                subject_id=foreign.currency_account_id,
            ),
            lambda rows: rows.rule_version(
                mine.workspace_id,
                "currency_account",
                foreign.currency_account_id,
                date(2027, 1, 1),
            ),
        ]

    expected = [
        (FOREIGN_KEY_VIOLATION, "card_products_bank_scope"),
        (FOREIGN_KEY_VIOLATION, "credit_accounts_bank_scope"),
        (FOREIGN_KEY_VIOLATION, "credit_accounts_product_scope"),
        (FOREIGN_KEY_VIOLATION, "credit_pools_bank_scope"),
        (FOREIGN_KEY_VIOLATION, "rule_bindings_rule_version_scope"),
        *[(FOREIGN_KEY_VIOLATION, "billing_rule_versions_subject_scope")] * 3,
    ]
    for engine in (revisions.old, revisions.new):
        ids = committed(engine, revisions.rows, build)
        assert [run(engine, revisions.rows, action) for action in scenarios(ids)] == expected


def test_r2_24_template_rows_keep_their_workspace(revisions: Revisions) -> None:
    """R2-24 (mutation M5): templates of banks, card_products and billing_rule_versions
    cannot be moved into a workspace. 0001 enforced it, but only banks was tested, so a
    card_products guard firing on the wrong column (M5) passed; now it fails here."""
    tables = ("banks", "card_products", "billing_rule_versions")

    def build(rows: "Rows") -> dict[str, uuid.UUID]:
        bank = rows.bank()
        product = rows.product(bank)
        return {
            "workspace": rows.workspace(),
            "banks": bank,
            "card_products": product,
            "billing_rule_versions": rows.rule_version(
                None, "product", product, date(2026, 1, 1), review_status="published"
            ),
        }

    expected = [
        (INTEGRITY_CONSTRAINT_VIOLATION, f"{table}_workspace_immutable") for table in tables
    ]
    for engine in (revisions.old, revisions.new):
        ids = committed(engine, revisions.rows, build)
        outcomes = [
            run(engine, revisions.rows, _set(table, ids[table], workspace_id=ids["workspace"]))
            for table in tables
        ]
        assert outcomes == expected


_FK_COVERAGE = text(
    """
    WITH fks AS (
        SELECT con.conname, con.conrelid, con.conkey, c.relname AS table_name
          FROM pg_constraint AS con
          JOIN pg_class AS c ON c.oid = con.conrelid
          JOIN pg_namespace AS n ON n.oid = c.relnamespace
         WHERE con.contype = 'f' AND n.nspname = 'public'
           AND con.confrelid <> 'public.currencies'::regclass
    )
    SELECT fks.table_name || '.' || fks.conname
      FROM fks
     WHERE NOT EXISTS (
           SELECT 1 FROM pg_index AS i
            WHERE i.indrelid = fks.conrelid AND i.indpred IS NULL
              AND ((i.indkey[0] = ANY (fks.conkey)
                    AND (SELECT a.attname FROM pg_attribute AS a
                          WHERE a.attrelid = i.indrelid AND a.attnum = i.indkey[0])
                        <> 'workspace_id')
                   OR (SELECT array_agg(k ORDER BY k)
                         FROM unnest((i.indkey::int2[])[0:cardinality(fks.conkey) - 1]) AS k)
                      = (SELECT array_agg(k ORDER BY k) FROM unnest(fks.conkey) AS k)))
     ORDER BY 1
    """
)


def test_r2_25_every_foreign_key_has_a_supporting_index(revisions: Revisions) -> None:
    """R2-25: foreign keys without a usable (non-partial, leading-column) index."""
    with revisions.old.connect() as old, revisions.new.connect() as new:
        uncovered_old = old.execute(_FK_COVERAGE).scalars().all()
        uncovered_new = new.execute(_FK_COVERAGE).scalars().all()

    assert "transactions.fk_transactions_parent_transaction_id" in uncovered_old
    assert uncovered_new == []


def test_r2_26_idempotency_keys_can_be_pruned_by_age(revisions: Revisions) -> None:
    """R2-26 (index part): a created_at index for the retention clean-up."""
    query = text(
        "SELECT count(*) FROM pg_indexes WHERE indexname = 'ix_idempotency_keys_created_at'"
    )
    with revisions.old.connect() as old, revisions.new.connect() as new:
        assert (old.execute(query).scalar_one(), new.execute(query).scalar_one()) == (0, 1)


def test_r2_27_jobs_dedupe_key_and_lease_index(revisions: Revisions) -> None:
    """R2-27: at most one queued/running job per dedupe_key; lease reclaim index exists."""
    assert "dedupe_key" not in column_names(revisions.old, "jobs")
    key = f"tick-{uuid.uuid4().hex}"

    def enqueue_twice(rows: "Rows") -> object:
        rows.insert("jobs", kind="system.tick", payload={}, dedupe_key=key)
        return rows.insert("jobs", kind="system.tick", payload={}, dedupe_key=key)

    def enqueue_after_done(rows: "Rows") -> object:
        first = rows.insert("jobs", kind="system.tick", payload={}, dedupe_key=key)
        jobs = T["jobs"]
        rows.connection.execute(update(jobs).where(jobs.c.id == first).values(status="succeeded"))
        return rows.insert("jobs", kind="system.tick", payload={}, dedupe_key=key)

    assert run(revisions.new, revisions.rows, enqueue_twice) == (
        UNIQUE_VIOLATION,
        "uq_jobs_dedupe_key_active",
    )
    assert run(revisions.new, revisions.rows, enqueue_after_done) == OK
    with revisions.new.connect() as connection:
        definition = connection.execute(
            text("SELECT indexdef FROM pg_indexes WHERE indexname = 'ix_jobs_running_locked_until'")
        ).scalar_one()
    assert "WHERE (status = 'running'::text)" in definition


def test_r2_29_email_and_public_key_sanity(revisions: Revisions) -> None:
    """R2-29: empty e-mail addresses and one-byte public keys were accepted."""

    def empty_email(rows: "Rows") -> object:
        return rows.insert("users", email="")

    def tiny_key(rows: "Rows") -> object:
        return rows.insert(
            "devices", workspace_id=rows.workspace(), platform="ios", public_key=b"x"
        )

    assert (
        run(revisions.old, revisions.rows, empty_email),
        run(revisions.old, revisions.rows, tiny_key),
    ) == (OK, OK)
    assert run(revisions.new, revisions.rows, empty_email) == (
        CHECK_VIOLATION,
        "ck_users_email_not_empty",
    )
    assert run(revisions.new, revisions.rows, tiny_key) == (
        CHECK_VIOLATION,
        "ck_devices_public_key_length",
    )


_LOOP_OVER_QUERY = re.compile(r"FOR\s+\w+\s+IN\s+(SELECT.*?)\s+LOOP", re.IGNORECASE | re.DOTALL)


def _unordered_loops(engine: Engine) -> list[str]:
    with engine.connect() as connection:
        bodies = connection.execute(
            text(
                "SELECT p.proname, p.prosrc FROM pg_proc AS p "
                "JOIN pg_namespace AS n ON n.oid = p.pronamespace WHERE n.nspname = 'public' "
                "AND NOT EXISTS (SELECT 1 FROM pg_depend AS d "
                "WHERE d.objid = p.oid AND d.deptype = 'e')"
            )
        ).all()
    return sorted(
        name
        for name, body in bodies
        for query in _LOOP_OVER_QUERY.findall(body)
        if "ORDER BY" not in query.upper()
    )


def test_r2_33_no_lock_taking_loop_in_unspecified_order(revisions: Revisions) -> None:
    """R2-33: a loop locked repayments in arbitrary order (deadlock-prone)."""
    assert _unordered_loops(revisions.old) == ["statements_allocation_check"]
    assert _unordered_loops(revisions.new) == []


# --- decision 1: plan allocations are per card ----------------------------------------------


def test_decision_1_plan_allocations_are_unique_per_card(revisions: Revisions) -> None:
    """Decision 1: two cards of one currency account in one run; one card only once."""

    def build(rows: "Rows") -> dict[str, uuid.UUID]:
        account = rows.account()
        workspace = account.workspace_id
        return {
            "workspace": workspace,
            "currency_account": account.currency_account_id,
            "card_1": rows.card(workspace, account.credit_account_id, "1111"),
            "card_2": rows.card(workspace, account.credit_account_id, "2222"),
            "cash": rows.cash_account(workspace),
            "run": rows.plan_run(workspace, rows.plan(workspace)),
        }

    def allocate(ids: dict[str, uuid.UUID], cards: tuple[str, ...]) -> Callable[["Rows"], object]:
        def action(rows: "Rows") -> object:
            for card in cards:
                rows.insert(
                    "plan_allocations",
                    workspace_id=ids["workspace"],
                    run_id=ids["run"],
                    currency_account_id=ids["currency_account"],
                    card_id=ids[card],
                    amount_minor=1_000,
                    statement_date=date(2026, 11, 10),
                    due_date=date(2026, 11, 28),
                    repay_on=date(2026, 11, 28),
                    repay_from_cash_account_id=ids["cash"],
                    buffer_days=43,
                )
            return None

        return action

    old_ids = committed(revisions.old, revisions.rows, build)
    new_ids = committed(revisions.new, revisions.rows, build)

    assert run(revisions.old, revisions.rows, allocate(old_ids, ("card_1", "card_2"))) == (
        UNIQUE_VIOLATION,
        "pk_plan_allocations",
    )
    assert run(revisions.new, revisions.rows, allocate(new_ids, ("card_1", "card_2"))) == OK
    assert run(revisions.new, revisions.rows, allocate(new_ids, ("card_1", "card_1"))) == (
        UNIQUE_VIOLATION,
        "uq_plan_allocations_run_id_card_id",
    )


def test_revision_files_are_present() -> None:
    """0002 sits next to 0001 (sanity for the reproductions above)."""
    versions = API_ROOT / "alembic" / "versions"
    assert {path.name for path in versions.glob("*.py")} >= {
        "0001_initial.py",
        "0002_schema_fixes.py",
    }
    assert isinstance(versions, Path)
