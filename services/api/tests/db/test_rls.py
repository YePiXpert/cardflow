"""Row-level security under the real roles (T-006, revision 0003): TC-DB-04/05/06, F-65.

Every test acts through the temporary login roles of tests/conftest.py -- ``app_engine``
(cardflow_api), ``worker_engine``, ``purge_capable_engine`` (cardflow_worker_login) and
``admin_engine`` (cardflow_admin_login) -- never as the superuser. Fixture rows are created
and committed by the superuser (``db_engine``) in fresh workspaces per test, so tests do
not depend on each other. Statements expected to fail run in their own transaction.

Errors: ``42501`` insufficient_privilege covers both "permission denied" (no grant) and
"new row violates row-level security policy" (WITH CHECK); rows hidden by a policy are
simply not there (0 rows read, updated or deleted).
"""

import threading
import time
import uuid
from collections.abc import Callable, Iterator
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from typing import TYPE_CHECKING, Any, Final

import pytest
from sqlalchemy import Table, delete, func, insert, select, text, update
from sqlalchemy.engine import Connection, Engine
from sqlalchemy.exc import DBAPIError
from sqlalchemy.pool import NullPool
from sqlalchemy.sql import Executable, Insert, Select

from cardflow.db import create_session_factory, workspace_tx
from cardflow.db.engine import create_engine
from cardflow.db.migrations import head_revisions, migration_status, upgrade
from cardflow.db.models import metadata
from cardflow.db.roles import PURGE_ROLE
from cardflow.jobs.queue import claim_jobs, enqueue, get_job, mark_succeeded
from cardflow.jobs.registry import Registry

if TYPE_CHECKING:
    from sqlalchemy.engine import URL

    from tests.db.conftest import Account, DatabaseFactory, RlsDeclarations, Rows

pytestmark = [pytest.mark.db, pytest.mark.usefixtures("require_head_schema")]

T: Final = metadata.tables
INSUFFICIENT_PRIVILEGE: Final = "42501"
FOREIGN_KEY_VIOLATION: Final = "23503"
CHECK_VIOLATION: Final = "23514"
INTEGRITY_CONSTRAINT_VIOLATION: Final = "23000"
SERIALIZATION_FAILURE: Final = "40001"
NOW: Final = datetime(2026, 10, 17, 8, 0, tzinfo=UTC)
JOB_KIND: Final = "test_rls.noop"
BIND_WORKSPACE: Final = text("SELECT set_config('app.workspace_id', :value, true)")
BIND_USER: Final = text("SELECT set_config('app.user_id', :value, true)")
PURGE_TOKEN: Final = text("SELECT set_config('app.purge', pg_current_xact_id()::text, true)")


@dataclass(frozen=True)
class Outcome:
    """What one transaction did: the error (SQLSTATE, constraint) or the action's value."""

    sqlstate: str | None = None
    constraint: str | None = None
    value: Any = None
    message: str | None = None

    @property
    def ok(self) -> bool:
        return self.sqlstate is None


def act(
    engine: Engine,
    action: Callable[[Connection], Any],
    *,
    workspace: uuid.UUID | None = None,
    user: uuid.UUID | None = None,
    role: str | None = None,
    purge_token: bool = False,
    commit: bool = False,
) -> Outcome:
    """Run ``action`` in one transaction of ``engine``, optionally bound to a workspace and
    user, after ``SET LOCAL ROLE`` and with the purge token; rolled back unless ``commit``."""
    with engine.connect() as connection:
        transaction = connection.begin()
        try:
            if role is not None:
                connection.execute(text(f"SET LOCAL ROLE {role}"))
            if workspace is not None:
                connection.execute(BIND_WORKSPACE, {"value": str(workspace)})
            if user is not None:
                connection.execute(BIND_USER, {"value": str(user)})
            if purge_token:
                connection.execute(PURGE_TOKEN)
            value = action(connection)
            if commit:
                transaction.commit()
        except DBAPIError as exc:
            diag = getattr(exc.orig, "diag", None)
            return Outcome(
                getattr(exc.orig, "sqlstate", None),
                getattr(diag, "constraint_name", None),
                message=getattr(diag, "message_primary", None),
            )
        finally:
            if transaction.is_active:
                transaction.rollback()
    return Outcome(value=value)


def rowcount(statement: Executable) -> Callable[[Connection], int]:
    return lambda connection: connection.execute(statement).rowcount


def scalar(statement: Executable) -> Callable[[Connection], Any]:
    return lambda connection: connection.execute(statement).scalar_one()


def count_rows(table: str, **where: object) -> Select[tuple[int]]:
    target = T[table]
    statement = select(func.count()).select_from(target)
    for column, value in where.items():
        statement = statement.where(target.c[column] == value)
    return statement


# --- fixture data ------------------------------------------------------------------------------


@dataclass(frozen=True)
class Tenant:
    """A workspace with at least one row in most tenant tables (committed by the superuser)."""

    workspace_id: uuid.UUID
    user_id: uuid.UUID
    account: "Account"
    card: uuid.UUID
    transaction: uuid.UUID
    statement: uuid.UUID
    version: uuid.UUID
    line: uuid.UUID
    repayment: uuid.UUID
    cash_account: uuid.UUID
    cash_event: uuid.UUID
    cash_snapshot: uuid.UUID
    limit_snapshot: uuid.UUID
    plan_run: uuid.UUID
    plan_allocation: uuid.UUID
    plan_run_check: uuid.UUID
    bank: uuid.UUID
    rule: uuid.UUID
    device: uuid.UUID
    document: uuid.UUID
    job: uuid.UUID


def build_tenant(rows: "Rows") -> Tenant:
    connection = rows.connection
    user = rows.insert("users")
    workspace = rows.insert("workspaces", owner_user_id=user, kind="real")
    rows.insert("workspace_members", workspace_id=workspace, user_id=user, role="owner")
    device = rows.insert(
        "devices", workspace_id=workspace, user_id=user, platform="ios", public_key=b"k" * 32
    )
    rows.insert(
        "auth_sessions",
        workspace_id=workspace,
        device_id=device,
        refresh_token_hash=uuid.uuid4().hex * 2,
        expires_at=datetime.now(UTC) + timedelta(days=30),
        last_used_at=NOW,
    )
    rows.insert("consents", workspace_id=workspace, purpose="server_sync", granted_at=NOW)
    bank = rows.bank(workspace)
    account = rows.account(workspace)
    card = rows.card(workspace, account.credit_account_id)
    transaction = rows.transaction(account, card_id=card)
    statement = rows.statement(account)
    version = rows.statement_version(workspace, statement)
    line = rows.statement_line(workspace, version)
    repayment = rows.repayment(account, 100_000)
    rows.allocation(workspace, repayment, statement, 10_000)
    cash = rows.cash_account(workspace)
    cash_event = rows.cash_event(workspace, cash)
    cash_snapshot = rows.cash_snapshot(workspace, cash)
    limit_snapshot = rows.limit_snapshot(account)
    plan = rows.plan(workspace)
    run = rows.plan_run(workspace, plan)
    allocation = rows.insert(
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
    check = rows.insert(
        "plan_run_checks",
        workspace_id=workspace,
        run_id=run,
        scenario_id=rows.scenario(workspace, "confirmed"),
        ok=True,
        ok_zero=True,
        min_balance_by_account={},
    )
    rule = rows.rule_version(
        workspace, "credit_account", account.credit_account_id, date(2026, 1, 1)
    )
    document = rows.source_document(workspace)
    connection.execute(
        insert(T["idempotency_keys"]).values(
            workspace_id=workspace,
            key=str(uuid.uuid4()),
            request_hash=uuid.uuid4().hex * 2,
            response_status=201,
            response_body={"id": "x"},
        )
    )
    connection.execute(
        insert(T["sync_changes"]).values(
            workspace_id=workspace, table_name="cards", row_id=card, op="insert", row_version=1
        )
    )
    connection.execute(
        insert(T["audit_log"]).values(workspace_id=workspace, actor_kind="system", action="seed")
    )
    rows.insert(
        "deletion_tasks",
        workspace_id=workspace,
        grace_until=datetime.now(UTC) + timedelta(days=30),
        status="pending",
    )
    job = rows.insert(
        "jobs", kind=JOB_KIND, payload={"workspace": str(workspace)}, workspace_id=workspace
    )
    return Tenant(
        workspace_id=workspace,
        user_id=user,
        account=account,
        card=card,
        transaction=transaction,
        statement=statement,
        version=version,
        line=line,
        repayment=repayment,
        cash_account=cash,
        cash_event=cash_event,
        cash_snapshot=cash_snapshot,
        limit_snapshot=limit_snapshot,
        plan_run=run,
        plan_allocation=allocation,
        plan_run_check=check,
        bank=bank,
        rule=rule,
        device=device,
        document=document,
        job=job,
    )


@pytest.fixture
def tenants(db_engine: Engine, rows_class: "type[Rows]") -> Iterator[tuple[Tenant, Tenant]]:
    """Two fully populated workspaces A and B (committed); their jobs are removed after."""
    with db_engine.begin() as connection:
        rows = rows_class(connection)
        pair = (build_tenant(rows), build_tenant(rows))
    yield pair
    with db_engine.begin() as connection:
        connection.execute(delete(T["jobs"]).where(T["jobs"].c.kind == JOB_KIND))


def tables_readable_by(
    declarations: "RlsDeclarations", role: str, *, scoped: bool = True
) -> list[str]:
    """Tables ``role`` may SELECT that carry a workspace scope (workspace_id, or workspaces)."""
    return sorted(
        table
        for table, roles in declarations.table_access.items()
        if roles.get(role) is not None
        and roles[role].select
        and table in T
        and (not scoped or table == "workspaces" or "workspace_id" in T[table].c)
    )


def in_workspace(table: str, workspace: uuid.UUID) -> Select[tuple[int]]:
    target = T[table]
    column = target.c.id if table == "workspaces" else target.c.workspace_id
    return select(func.count()).select_from(target).where(column == workspace)


# --- TC-DB-05 / F-65: app bound to A never reaches B ----------------------------------------


def test_tc_db_05_bound_to_a_nothing_of_b_is_visible(
    app_engine: Engine, tenants: tuple[Tenant, Tenant], rls_declarations: "RlsDeclarations"
) -> None:
    """F-65: bound to A, every table the API can read shows A's rows and none of B's."""
    a, b = tenants
    readable = tables_readable_by(rls_declarations, "cardflow_app")
    assert len(readable) > 50

    def counts(workspace: uuid.UUID) -> Callable[[Connection], dict[str, int]]:
        return lambda connection: {
            table: connection.execute(in_workspace(table, workspace)).scalar_one()
            for table in readable
        }

    of_b = act(app_engine, counts(b.workspace_id), workspace=a.workspace_id)
    of_a = act(app_engine, counts(a.workspace_id), workspace=a.workspace_id)

    assert of_b.ok, of_b
    assert {table: n for table, n in of_b.value.items() if n} == {}
    assert of_a.ok, of_a
    empty_for_a = {table for table, n in of_a.value.items() if n == 0}
    # Tables the fixture does not populate (the rest hold A's rows).
    assert empty_for_a <= {
        "cash_transfers",
        "charges",
        "credit_pool_members",
        "credit_pools",
        "dedupe_keys",
        "extraction_candidates",
        "forecast_runs",
        "import_batch_items",
        "import_batches",
        "installment_plans",
        "installment_schedule",
        "limit_adjustments",
        "parse_jobs",
        "plan_invalidations",
        "plan_reservations",
        "preauth_holds",
        "reconciliation_items",
        "recurring_items",
        "rule_bindings",
        "snapshot_included_events",
        "statement_attributions",
        "sync_conflicts",
        "transaction_links",
        "card_products",
        # 0004: visible to the API only while a registration binds app.pairing_code_id
        # (tests/identity/test_identity_schema.py).
        "pairing_codes",
    }


def test_tc_db_05_rows_of_b_cannot_be_changed_or_deleted(
    app_engine: Engine, tenants: tuple[Tenant, Tenant]
) -> None:
    """F-65: UPDATE/DELETE aimed at B's rows touch nothing; DELETE is not granted at all
    outside workspace_members."""
    a, b = tenants
    as_a = {"workspace": a.workspace_id}
    transactions, statements, members = T["transactions"], T["statements"], T["workspace_members"]

    assert (
        act(
            app_engine,
            rowcount(
                update(transactions).where(transactions.c.id == b.transaction).values(merchant="X")
            ),
            **as_a,
        ).value
        == 0
    )
    assert (
        act(
            app_engine,
            rowcount(
                update(statements).where(statements.c.id == b.statement).values(status="settled")
            ),
            **as_a,
        ).value
        == 0
    )
    assert (
        act(
            app_engine,
            rowcount(delete(members).where(members.c.workspace_id == b.workspace_id)),
            **as_a,
        ).value
        == 0
    )
    assert (
        act(
            app_engine,
            rowcount(
                update(transactions).where(transactions.c.id == a.transaction).values(merchant="X")
            ),
            **as_a,
        ).value
        == 1
    )
    denied = act(
        app_engine, rowcount(delete(transactions).where(transactions.c.id == b.transaction)), **as_a
    )
    assert denied.sqlstate == INSUFFICIENT_PRIVILEGE


@pytest.mark.parametrize(
    ("table", "values"),
    [
        ("cash_accounts", {"name": "x", "currency": "CNY", "kind": "bank"}),
        ("scenarios", {"code": "x", "name": "x"}),
        ("consents", {"purpose": "analytics", "granted_at": NOW}),
        ("jobs", {"kind": JOB_KIND, "payload": {}, "status": "queued"}),
        ("audit_log", {"actor_kind": "user", "action": "x"}),
        (
            "sync_changes",
            {"table_name": "cards", "row_id": uuid.uuid4(), "op": "insert", "row_version": 1},
        ),
    ],
)
def test_tc_db_05_rows_for_b_are_rejected_by_with_check(
    app_engine: Engine, tenants: tuple[Tenant, Tenant], table: str, values: dict[str, object]
) -> None:
    """F-65: bound to A, inserting a row of workspace B violates the WITH CHECK policy."""
    a, b = tenants
    # .inline(): no implicit RETURNING (audit_log is append-only for the API, no SELECT).
    own = act(
        app_engine,
        rowcount(insert(T[table]).values(workspace_id=a.workspace_id, **values).inline()),
        workspace=a.workspace_id,
    )
    foreign = act(
        app_engine,
        rowcount(insert(T[table]).values(workspace_id=b.workspace_id, **values).inline()),
        workspace=a.workspace_id,
    )

    assert own.ok, own
    assert foreign.sqlstate == INSUFFICIENT_PRIVILEGE


def test_tc_db_05_a_row_cannot_be_moved_to_b(
    app_engine: Engine, tenants: tuple[Tenant, Tenant]
) -> None:
    """workspace_id is not updatable by any role (column grant), so a row cannot move."""
    a, b = tenants
    target = T["cash_accounts"]
    moved = act(
        app_engine,
        rowcount(
            update(target).where(target.c.id == a.cash_account).values(workspace_id=b.workspace_id)
        ),
        workspace=a.workspace_id,
    )
    assert moved.sqlstate == INSUFFICIENT_PRIVILEGE


def test_tc_db_05_unbound_sessions_see_no_tenant_row(
    app_engine: Engine, tenants: tuple[Tenant, Tenant], rls_declarations: "RlsDeclarations"
) -> None:
    """Without app.workspace_id nothing tenant-owned is visible -- also on a connection whose
    earlier transaction had a binding (the setting then reads '' instead of NULL). Official
    templates (workspace_id IS NULL) and currencies stay readable."""
    a, _b = tenants
    readable = tables_readable_by(rls_declarations, "cardflow_app", scoped=False)

    def visible(connection: Connection) -> dict[str, int]:
        found = {}
        for table in readable:
            target = T[table]
            statement = select(func.count()).select_from(target)
            if "workspace_id" in target.c:
                statement = statement.where(target.c.workspace_id.is_not(None))
            found[table] = connection.execute(statement).scalar_one()
        return found

    system_tables = {"currencies", "alembic_version", "worker_heartbeats"}  # no RLS by design
    fresh = act(app_engine, visible)
    with app_engine.connect() as connection:
        with connection.begin():
            connection.execute(BIND_WORKSPACE, {"value": str(a.workspace_id)})
            assert connection.execute(count_rows("cards")).scalar_one() > 0
        with connection.begin():
            setting = connection.execute(
                text("SELECT current_setting('app.workspace_id', true)")
            ).scalar_one()
            reused = visible(connection)

    assert fresh.ok, fresh
    assert {table: n for table, n in fresh.value.items() if n and table not in system_tables} == {}
    assert setting == ""
    assert {table: n for table, n in reused.items() if n and table not in system_tables} == {}
    assert "users" in fresh.value
    assert fresh.value["currencies"] > 0


def test_tc_db_04_composite_keys_still_reject_cross_workspace_links_under_rls(
    app_engine: Engine, tenants: tuple[Tenant, Tenant]
) -> None:
    """TC-DB-04 again, as the API under RLS: the foreign-key checks (run as the table owner)
    still reject links from A's rows to B's rows the API cannot even see."""
    a, b = tenants
    as_a = {"workspace": a.workspace_id}
    currency_account = act(
        app_engine,
        rowcount(
            insert(T["currency_accounts"]).values(
                workspace_id=a.workspace_id,
                credit_account_id=b.account.credit_account_id,
                currency="USD",
            )
        ),
        **as_a,
    )
    card_link = act(
        app_engine,
        rowcount(
            update(T["transactions"])
            .where(T["transactions"].c.id == a.transaction)
            .values(card_id=b.card)
        ),
        **as_a,
    )
    allocation = act(
        app_engine,
        rowcount(
            insert(T["repayment_allocations"]).values(
                workspace_id=a.workspace_id,
                repayment_id=a.repayment,
                statement_id=b.statement,
                amount_minor=1_000,
            )
        ),
        **as_a,
    )

    assert (currency_account.sqlstate, currency_account.constraint) == (
        FOREIGN_KEY_VIOLATION,
        "fk_currency_accounts_credit_account_id",
    )
    assert (card_link.sqlstate, card_link.constraint) == (
        FOREIGN_KEY_VIOLATION,
        "fk_transactions_credit_account_id_card_id",
    )
    assert (allocation.sqlstate, allocation.constraint) == (
        FOREIGN_KEY_VIOLATION,
        "fk_repayment_allocations_currency_account_id_statement_id",
    )


# --- R2-01: no temporary objects -----------------------------------------------------------


@pytest.mark.parametrize("engine_name", ["app_engine", "worker_engine", "admin_engine"])
def test_r2_01_roles_cannot_create_temporary_tables(
    engine_name: str, request: pytest.FixtureRequest
) -> None:
    """R2-01 regression: TEMPORARY is revoked from PUBLIC and granted to no role, so no
    session can shadow a table name with a temporary table."""
    engine: Engine = request.getfixturevalue(engine_name)
    created = act(engine, rowcount(text("CREATE TEMP TABLE banks (id uuid, workspace_id uuid)")))
    assert created.sqlstate == INSUFFICIENT_PRIVILEGE


def test_r2_01_purge_role_cannot_create_temporary_tables(purge_capable_engine: Engine) -> None:
    created = act(
        purge_capable_engine, rowcount(text("CREATE TEMP TABLE x (i int)")), role=PURGE_ROLE
    )
    assert created.sqlstate == INSUFFICIENT_PRIVILEGE


# --- TC-DB-06: the admin console sees metadata only ------------------------------------------


@pytest.mark.parametrize(
    "statement",
    [
        "SELECT * FROM transactions",
        "SELECT new_balance_minor FROM statement_versions",
        "SELECT description FROM statement_lines",
        "SELECT raw_value FROM extraction_candidates",
        "SELECT * FROM repayments",
        "SELECT * FROM cash_events",
        "SELECT result FROM plan_runs",
        "SELECT storage_key FROM source_documents",
        "SELECT * FROM idempotency_keys",
        "SELECT response_body FROM idempotency_keys",
        "SELECT payload FROM jobs",
        "SELECT result FROM jobs",
        "SELECT * FROM jobs",
        "SELECT payload FROM sync_changes",
        "SELECT server_payload FROM sync_conflicts",
        "SELECT allocated_minor FROM repayment_allocation_totals",
        "SELECT email FROM users",
        "SELECT dek_wrapped FROM workspaces",
        "SELECT refresh_token_hash FROM auth_sessions",
        "SELECT * FROM devices",
    ],
)
def test_tc_db_06_admin_cannot_read_content(admin_engine: Engine, statement: str) -> None:
    """TC-DB-06: content tables and content columns: permission denied for the admin role."""
    assert act(admin_engine, scalar(text(f"{statement} LIMIT 1"))).sqlstate == (
        INSUFFICIENT_PRIVILEGE
    )


def test_tc_db_06_admin_views_count_across_workspaces(
    admin_engine: Engine, tenants: tuple[Tenant, Tenant]
) -> None:
    """The admin views aggregate both workspaces (cross-workspace counts, states, times)."""
    a, b = tenants
    ids = [a.workspace_id, b.workspace_id]
    overview = act(
        admin_engine,
        lambda connection: connection.execute(
            text(
                "SELECT workspace_id, kind, member_count, device_count, active_device_count, "
                "last_active_at IS NOT NULL, last_sync_at IS NOT NULL, document_count, "
                "document_bytes, deletion_status FROM admin.workspace_overview "
                "WHERE workspace_id = ANY (:ids) ORDER BY workspace_id"
            ),
            {"ids": ids},
        ).all(),
    )
    devices = act(
        admin_engine,
        lambda connection: connection.execute(
            text(
                "SELECT count(*), sum(active_session_count) FROM admin.device_overview "
                "WHERE workspace_id = ANY (:ids)"
            ),
            {"ids": ids},
        ).one(),
    )
    users = act(
        admin_engine,
        lambda connection: connection.execute(
            text(
                "SELECT count(*), sum(workspace_count) FROM admin.user_overview "
                "WHERE user_id = ANY (:ids)"
            ),
            {"ids": [a.user_id, b.user_id]},
        ).one(),
    )
    deletions = act(
        admin_engine,
        scalar(
            text(
                "SELECT count(*) FROM admin.deletion_requests WHERE workspace_id = ANY (:ids)"
            ).bindparams(ids=ids)
        ),
    )
    jobs = act(
        admin_engine,
        scalar(
            text(
                "SELECT job_count FROM admin.job_summary WHERE kind = :kind AND status = 'queued'"
            ).bindparams(kind=JOB_KIND)
        ),
    )
    status = act(
        admin_engine,
        lambda connection: connection.execute(
            text("SELECT schema_revision, queued_jobs >= 2 FROM admin.system_status")
        ).one(),
    )

    assert overview.ok, overview
    assert [tuple(row[1:]) for row in overview.value] == [
        ("real", 1, 1, 1, True, True, 1, 1024, "pending")
    ] * 2
    assert tuple(devices.value) == (2, 2)
    assert tuple(users.value) == (2, 2)
    assert deletions.value == 2
    assert jobs.value >= 2
    assert tuple(status.value) == (",".join(head_revisions()), True)


def test_tc_db_06_admin_reads_job_metadata_and_audit_but_changes_nothing(
    admin_engine: Engine, tenants: tuple[Tenant, Tenant]
) -> None:
    """Job metadata (incl. the safe error code last_error, AP-05) and the audit log are
    readable across workspaces; neither can be changed by the admin role."""
    a, b = tenants
    job_ids = [a.job, b.job]
    jobs = act(
        admin_engine,
        lambda connection: connection.execute(
            text("SELECT id, status, last_error, workspace_id FROM jobs WHERE id = ANY (:ids)"),
            {"ids": job_ids},
        ).all(),
    )
    audit = act(
        admin_engine,
        scalar(
            text("SELECT count(*) FROM audit_log WHERE workspace_id = ANY (:ids)").bindparams(
                ids=[a.workspace_id, b.workspace_id]
            )
        ),
    )

    assert len(jobs.value) == 2
    assert audit.value == 2
    for statement in (
        "UPDATE jobs SET status = 'cancelled' WHERE id = :id",
        "DELETE FROM jobs WHERE id = :id",
        "UPDATE audit_log SET action = 'x' WHERE workspace_id = :id",
        "DELETE FROM audit_log WHERE workspace_id = :id",
    ):
        changed = act(
            admin_engine,
            rowcount(
                text(statement).bindparams(id=a.job if "jobs" in statement else a.workspace_id)
            ),
        )
        assert changed.sqlstate == INSUFFICIENT_PRIVILEGE, statement


# --- templates -------------------------------------------------------------------------------


@pytest.fixture
def templates(
    db_engine: Engine, rows_class: "type[Rows]", tenants: tuple[Tenant, Tenant]
) -> dict[str, uuid.UUID]:
    """An official template bank, product and product rule (workspace_id NULL)."""
    with db_engine.begin() as connection:
        rows = rows_class(connection)
        bank = rows.bank()
        product = rows.product(bank)
        rule = rows.rule_version(
            None, "product", product, date(2026, 1, 1), review_status="published"
        )
    return {"bank": bank, "product": product, "rule": rule}


def test_templates_app_reads_templates_and_own_rows_only(
    app_engine: Engine, tenants: tuple[Tenant, Tenant], templates: dict[str, uuid.UUID]
) -> None:
    """The API sees official templates and its own workspace's private rows, never B's."""
    a, b = tenants
    banks, rules = T["banks"], T["billing_rule_versions"]

    def visible(table: Table, ids: list[uuid.UUID]) -> Callable[[Connection], set[uuid.UUID]]:
        return lambda connection: set(
            connection.execute(select(table.c.id).where(table.c.id.in_(ids))).scalars()
        )

    seen_banks = act(
        app_engine, visible(banks, [templates["bank"], a.bank, b.bank]), workspace=a.workspace_id
    )
    seen_rules = act(
        app_engine, visible(rules, [templates["rule"], a.rule, b.rule]), workspace=a.workspace_id
    )

    assert seen_banks.value == {templates["bank"], a.bank}
    assert seen_rules.value == {templates["rule"], a.rule}


def test_templates_app_cannot_change_templates(
    app_engine: Engine, tenants: tuple[Tenant, Tenant], templates: dict[str, uuid.UUID]
) -> None:
    """The API cannot modify or create templates; it can create private rows and reference
    templates and its own rows, not B's private bank (scope trigger under RLS)."""
    a, b = tenants
    as_a = {"workspace": a.workspace_id}
    banks = T["banks"]

    renamed = act(
        app_engine,
        rowcount(update(banks).where(banks.c.id == templates["bank"]).values(name="Mine")),
        **as_a,
    )
    template = act(app_engine, rowcount(insert(banks).values(name="Fake template")), **as_a)
    private = act(
        app_engine,
        rowcount(insert(banks).values(workspace_id=a.workspace_id, name="My bank")),
        **as_a,
    )

    def account(bank: uuid.UUID) -> Callable[[Connection], int]:
        return rowcount(
            insert(T["credit_accounts"]).values(
                workspace_id=a.workspace_id, bank_id=bank, holder_alias="me", status="active"
            )
        )

    assert renamed.value == 0
    assert template.sqlstate == INSUFFICIENT_PRIVILEGE
    assert private.ok, private
    assert act(app_engine, account(templates["bank"]), **as_a).ok
    assert act(app_engine, account(a.bank), **as_a).ok
    foreign = act(app_engine, account(b.bank), **as_a)
    assert (foreign.sqlstate, foreign.constraint) == (
        FOREIGN_KEY_VIOLATION,
        "credit_accounts_bank_scope",
    )


def test_templates_admin_maintains_templates_and_sees_no_user_rules(
    admin_engine: Engine, tenants: tuple[Tenant, Tenant], templates: dict[str, uuid.UUID]
) -> None:
    """The admin role writes official templates (incl. a product rule through the scope
    triggers) and cannot read or write any workspace's private rows."""
    a, _b = tenants
    banks, products, rules = T["banks"], T["card_products"], T["billing_rule_versions"]

    def create_template_chain(connection: Connection) -> uuid.UUID:
        bank = connection.execute(
            insert(banks).values(name="Template Bank").returning(banks.c.id)
        ).scalar_one()
        product = connection.execute(
            insert(products).values(bank_id=bank, name="Template Card").returning(products.c.id)
        ).scalar_one()
        return connection.execute(
            insert(rules)
            .values(
                subject_kind="product",
                subject_id=product,
                statement_day=5,
                due_kind="fixed_day",
                due_day=25,
                source="S01",
                effective_from=date(2026, 1, 1),
                version=1,
                review_status="draft",
            )
            .returning(rules.c.id)
        ).scalar_one()

    created = act(admin_engine, create_template_chain)
    renamed = act(
        admin_engine,
        rowcount(update(banks).where(banks.c.id == templates["bank"]).values(name="Renamed")),
    )
    user_rules = act(
        admin_engine,
        scalar(select(func.count()).select_from(rules).where(rules.c.workspace_id.is_not(None))),
    )
    private_insert = act(
        admin_engine, rowcount(insert(banks).values(workspace_id=a.workspace_id, name="x"))
    )
    private_update = act(
        admin_engine, rowcount(update(banks).where(banks.c.id == a.bank).values(name="x"))
    )
    deleted = act(admin_engine, rowcount(delete(banks).where(banks.c.id == templates["bank"])))

    assert created.ok, created
    assert renamed.value == 1
    assert user_rules.value == 0
    assert private_insert.sqlstate == INSUFFICIENT_PRIVILEGE
    assert private_update.value == 0
    assert deleted.sqlstate == INSUFFICIENT_PRIVILEGE


# --- append-only facts -----------------------------------------------------------------------

PROTECTED: Final[dict[str, tuple[str, Any]]] = {
    "statement_versions": ("version", {"reason": "edited"}),
    "statement_lines": ("line", {"description": "edited"}),
    "plan_runs": ("plan_run", {"input_hash": "edited"}),
    "plan_allocations": ("plan_allocation", {"buffer_days": 1}),
    "plan_run_checks": ("plan_run_check", {"ok": False}),
    "limit_snapshots": ("limit_snapshot", {"confirmation_level": "bank_confirmed"}),
    "cash_balance_snapshots": ("cash_snapshot", {"source_kind": "edited"}),
}


@pytest.mark.parametrize("table", sorted(PROTECTED))
def test_protected_facts_take_only_the_tombstone(
    app_engine: Engine, tenants: tuple[Tenant, Tenant], table: str
) -> None:
    """The seven protected fact tables: the API cannot DELETE or TRUNCATE them and cannot
    UPDATE any column but deleted_at; it can tombstone a row exactly once -- a second
    tombstone is rejected by the 0002 trigger on the five immutable fact tables and, since
    revision 0004 (data-model §10.13), by <table>_tombstone_once on the two snapshot
    tables."""
    a, _b = tenants
    attribute, edit = PROTECTED[table]
    row_id = getattr(a, attribute)
    target = T[table]
    as_a = {"workspace": a.workspace_id}

    deleted = act(app_engine, rowcount(delete(target).where(target.c.id == row_id)), **as_a)
    truncated = act(app_engine, rowcount(text(f"TRUNCATE {table} CASCADE")), **as_a)
    edited = act(
        app_engine, rowcount(update(target).where(target.c.id == row_id).values(**edit)), **as_a
    )

    def tombstone_twice(connection: Connection) -> tuple[int, str | None]:
        statement = update(target).where(target.c.id == row_id)
        first = connection.execute(statement.values(deleted_at=NOW)).rowcount
        try:
            with connection.begin_nested():
                connection.execute(statement.values(deleted_at=NOW + timedelta(days=1)))
        except DBAPIError as exc:
            return first, getattr(exc.orig, "sqlstate", None)
        return first, None

    tombstoned = act(app_engine, tombstone_twice, **as_a)

    assert deleted.sqlstate == INSUFFICIENT_PRIVILEGE
    assert truncated.sqlstate == INSUFFICIENT_PRIVILEGE
    assert edited.sqlstate == INSUFFICIENT_PRIVILEGE
    # Every protected table freezes a row once it is tombstoned: the five immutable fact
    # tables through 0002's forbid_fact_rewrite, the two snapshot tables (whose amount/time/
    # account columns 0002 freezes anyway) through 0004's <table>_tombstone_once.
    assert tombstoned.value == (1, INTEGRITY_CONSTRAINT_VIOLATION)


# --- the worker -----------------------------------------------------------------------------


def _registry() -> Registry:
    registry = Registry()
    registry.register(JOB_KIND, mode="inline", timeout_s=30, max_attempts=3)(lambda ctx: None)
    return registry


def test_worker_claims_jobs_of_every_workspace(
    worker_engine: Engine, tenants: tuple[Tenant, Tenant], db_engine: Engine
) -> None:
    """jobs is cross-workspace for the worker: it leases A's, B's and system jobs and
    finishes them (cardflow.jobs.queue, as cardflow_worker)."""
    a, b = tenants
    with db_engine.begin() as connection:
        system_job = enqueue(connection, JOB_KIND, {}, workspace_id=None, registry=_registry())
    factory = create_session_factory(worker_engine)

    claimed = claim_jobs(
        factory, worker_id="test-rls-worker", slots={JOB_KIND: None}, limit=10, lease_s=60
    )
    with factory.begin() as session:
        for job in claimed:
            mark_succeeded(session, job.id, "{}")

    assert {job.id for job in claimed} >= {a.job, b.job, system_job}
    with db_engine.connect() as connection:
        statuses = set(
            connection.execute(
                select(T["jobs"].c.status).where(T["jobs"].c.id.in_([a.job, b.job, system_job]))
            ).scalars()
        )
    assert statuses == {"succeeded"}


def test_worker_bound_to_a_reads_and_writes_only_a(
    worker_engine: Engine, tenants: tuple[Tenant, Tenant]
) -> None:
    """Business tables bind the worker to the job's workspace, exactly like the API."""
    a, b = tenants
    transactions = T["transactions"]
    factory = create_session_factory(worker_engine)

    with workspace_tx(factory, a.workspace_id) as session:
        visible = set(
            session.execute(
                select(transactions.c.workspace_id).where(
                    transactions.c.id.in_([a.transaction, b.transaction])
                )
            ).scalars()
        )
        mine = session.execute(
            update(transactions).where(transactions.c.id == a.transaction).values(category="w")
        ).rowcount
        theirs = session.execute(
            update(transactions).where(transactions.c.id == b.transaction).values(category="w")
        ).rowcount
    foreign_insert = act(
        worker_engine,
        rowcount(insert(T["scenarios"]).values(workspace_id=b.workspace_id, code="w", name="w")),
        workspace=a.workspace_id,
    )

    assert visible == {a.workspace_id}
    assert (mine, theirs) == (1, 0)
    assert foreign_insert.sqlstate == INSUFFICIENT_PRIVILEGE


def test_worker_cannot_mint_api_access(
    worker_engine: Engine, tenants: tuple[Tenant, Tenant]
) -> None:
    """Identity and credentials stay with the API: bound to A, the worker can neither read
    refresh sessions or idempotency keys nor create sessions, devices or memberships."""
    a, _b = tenants
    as_a = {"workspace": a.workspace_id}
    attempts = {
        "read sessions": scalar(select(func.count()).select_from(T["auth_sessions"])),
        "read idempotency keys": scalar(select(func.count()).select_from(T["idempotency_keys"])),
        "create session": rowcount(
            insert(T["auth_sessions"]).values(
                workspace_id=a.workspace_id,
                device_id=a.device,
                refresh_token_hash=uuid.uuid4().hex * 2,
                expires_at=datetime.now(UTC) + timedelta(days=1),
            )
        ),
        "create device": rowcount(
            insert(T["devices"])
            .values(workspace_id=a.workspace_id, platform="ios", public_key=b"w" * 32)
            .inline()
        ),
        "join workspace": rowcount(
            insert(T["workspace_members"])
            .values(workspace_id=a.workspace_id, user_id=a.user_id, role="admin")
            .inline()
        ),
        "rename user": rowcount(
            update(T["users"]).where(T["users"].c.id == a.user_id).values(display_name="w")
        ),
    }
    results = {
        name: act(worker_engine, attempt, **as_a).sqlstate for name, attempt in attempts.items()
    }
    members = act(worker_engine, scalar(count_rows("workspace_members")), **as_a)

    assert results == dict.fromkeys(attempts, INSUFFICIENT_PRIVILEGE)
    assert members.value == 1  # read access to identity data remains


def test_worker_heartbeats_and_readyz_queries(
    worker_engine: Engine, app_engine: Engine, admin_engine: Engine
) -> None:
    """The worker writes worker_heartbeats; the API runs the /readyz reads (alembic_version
    via migration_status, worker_heartbeats) and the admin role reads both too."""
    from cardflow.jobs.queue import WorkerIdentity, delete_heartbeat, upsert_heartbeat

    identity = WorkerIdentity("test-rls-heartbeat", "host", 1, "dev", NOW)
    factory = create_session_factory(worker_engine)
    with factory.begin() as session:
        upsert_heartbeat(session, identity, running_jobs=0)
    try:
        with app_engine.connect() as connection:
            status = migration_status(connection)
            seen = connection.execute(
                text("SELECT max(last_seen_at) IS NOT NULL FROM worker_heartbeats")
            ).scalar_one()
        written = act(
            app_engine,
            rowcount(text("DELETE FROM worker_heartbeats WHERE worker_id = 'test-rls-heartbeat'")),
        )
        admin_status = act(admin_engine, scalar(text("SELECT count(*) FROM alembic_version")))
    finally:
        with factory.begin() as session:
            delete_heartbeat(session, identity.worker_id)

    assert status.up_to_date
    assert seen is True
    assert written.sqlstate == INSUFFICIENT_PRIVILEGE
    assert admin_status.value == 1


# --- physical deletion: cardflow_purge -------------------------------------------------------


def test_purge_requires_set_role_and_the_purge_token(
    purge_capable_engine: Engine, worker_engine: Engine, tenants: tuple[Tenant, Tenant]
) -> None:
    """Physical deletion of protected facts: not as the worker (purge is NOINHERIT), not
    without SET ROLE rights, not without the transaction's purge token; with both, only the
    bound workspace's rows go."""
    a, b = tenants
    lines, versions = T["statement_lines"], T["statement_versions"]
    as_a = {"workspace": a.workspace_id}

    def purge_statement(connection: Connection) -> tuple[int, int, int]:
        foreign = connection.execute(delete(lines).where(lines.c.workspace_id == b.workspace_id))
        own_lines = connection.execute(delete(lines).where(lines.c.id == a.line))
        own_version = connection.execute(delete(versions).where(versions.c.id == a.version))
        return foreign.rowcount, own_lines.rowcount, own_version.rowcount

    inherited = act(purge_capable_engine, purge_statement, purge_token=True, **as_a)
    not_member = act(worker_engine, purge_statement, role=PURGE_ROLE, purge_token=True, **as_a)
    no_token = act(purge_capable_engine, purge_statement, role=PURGE_ROLE, **as_a)
    truncate = act(
        purge_capable_engine,
        rowcount(text("TRUNCATE statement_lines")),
        role=PURGE_ROLE,
        purge_token=True,
        **as_a,
    )
    no_writes = act(
        purge_capable_engine,
        rowcount(update(lines).where(lines.c.id == a.line).values(deleted_at=NOW)),
        role=PURGE_ROLE,
        **as_a,
    )
    purged = act(purge_capable_engine, purge_statement, role=PURGE_ROLE, purge_token=True, **as_a)

    assert inherited.sqlstate == INSUFFICIENT_PRIVILEGE
    assert not_member.sqlstate == INSUFFICIENT_PRIVILEGE
    assert (no_token.sqlstate, no_token.constraint) == (
        INTEGRITY_CONSTRAINT_VIOLATION,
        "statement_lines_no_delete",
    )
    assert truncate.sqlstate == INSUFFICIENT_PRIVILEGE
    assert no_writes.sqlstate == INSUFFICIENT_PRIVILEGE
    assert purged.value == (0, 1, 1)


def test_purge_deletes_ordinary_rows_of_the_bound_workspace_only(
    purge_capable_engine: Engine, tenants: tuple[Tenant, Tenant]
) -> None:
    """Rows without a purge gate (e.g. cash events, allocations) need SET ROLE only; the
    allocation total follows through its SECURITY DEFINER trigger."""
    a, b = tenants
    events, allocations = T["cash_events"], T["repayment_allocations"]

    def purge(connection: Connection) -> tuple[int, int, int]:
        return (
            connection.execute(
                delete(events).where(events.c.id.in_([a.cash_event, b.cash_event]))
            ).rowcount,
            connection.execute(
                delete(allocations).where(
                    allocations.c.repayment_id.in_([a.repayment, b.repayment])
                )
            ).rowcount,
            connection.execute(
                text(
                    "SELECT allocated_minor FROM repayment_allocation_totals "
                    "WHERE repayment_id = :r"
                ),
                {"r": a.repayment},
            ).scalar_one(),
        )

    outcome = act(purge_capable_engine, purge, role=PURGE_ROLE, workspace=a.workspace_id)
    assert outcome.value == (1, 1, 0)


# --- repayment allocations as the API -------------------------------------------------------


def test_allocations_as_app_hold_the_amount_at_commit(
    app_engine: Engine, db_engine: Engine, rows_class: "type[Rows]"
) -> None:
    """TC-DB-09 as cardflow_app (READ COMMITTED): allocations within the amount commit, an
    over-allocation fails at COMMIT -- the check runs although the API has no privilege on
    repayment_allocation_totals (SECURITY DEFINER trigger functions)."""
    with db_engine.begin() as connection:
        rows = rows_class(connection)
        account = rows.account()
        repayment = rows.repayment(account, 100_000)
        first = rows.statement(account, date(2026, 10, 10))
        second = rows.statement(account, date(2026, 11, 10))

    def allocate(statement_id: uuid.UUID, amount: int) -> Callable[[Connection], int]:
        return rowcount(
            insert(T["repayment_allocations"]).values(
                workspace_id=account.workspace_id,
                repayment_id=repayment,
                statement_id=statement_id,
                amount_minor=amount,
            )
        )

    ok = act(app_engine, allocate(first, 60_000), workspace=account.workspace_id, commit=True)
    over = act(app_engine, allocate(second, 50_000), workspace=account.workspace_id, commit=True)
    fits = act(app_engine, allocate(second, 40_000), workspace=account.workspace_id, commit=True)
    total = act(
        app_engine,
        scalar(
            text(
                "SELECT allocated_minor FROM repayment_allocation_totals WHERE repayment_id = :r"
            ).bindparams(r=repayment)
        ),
        workspace=account.workspace_id,
    )

    assert ok.ok, ok
    assert (over.sqlstate, over.constraint) == (
        CHECK_VIOLATION,
        "repayment_allocations_within_amount",
    )
    assert fits.ok, fits
    assert total.value == 100_000


def _waiting_on_lock(monitor: Connection, pid: int) -> bool:
    return bool(
        monitor.execute(
            text("SELECT wait_event_type = 'Lock' FROM pg_stat_activity WHERE pid = :pid"),
            {"pid": pid},
        ).scalar()
    )


@pytest.mark.parametrize(
    ("isolation", "second_outcome"),
    [("READ COMMITTED", CHECK_VIOLATION), ("REPEATABLE READ", SERIALIZATION_FAILURE)],
)
def test_allocations_as_app_race_in_both_isolation_levels(
    app_engine: Engine,
    db_engine: Engine,
    rows_class: "type[Rows]",
    isolation: str,
    second_outcome: str,
) -> None:
    """R2-02 as cardflow_app: two concurrent sessions allocate 70000 + 60000 on 100000. The
    second waits on the allocation total (written by the SECURITY DEFINER trigger); READ
    COMMITTED then sees the committed sum and fails its check (23514), REPEATABLE READ fails
    with 40001. The committed total stays 70000 either way."""
    with db_engine.begin() as connection:
        rows = rows_class(connection)
        account = rows.account()
        repayment = rows.repayment(account, 100_000)
        first = rows.statement(account, date(2026, 10, 10))
        second = rows.statement(account, date(2026, 11, 10))
    workspace = str(account.workspace_id)
    outcomes: list[str | None] = []
    inserted = threading.Event()
    proceed = threading.Event()

    def allocation(statement_id: uuid.UUID, amount: int) -> Insert:
        return insert(T["repayment_allocations"]).values(
            workspace_id=account.workspace_id,
            repayment_id=repayment,
            statement_id=statement_id,
            amount_minor=amount,
        )

    with (
        app_engine.connect() as session_1,
        app_engine.connect() as session_2,
        db_engine.connect() as monitor,
    ):
        for session in (session_1, session_2):
            session.execution_options(isolation_level=isolation)
            session.begin()
            session.execute(BIND_WORKSPACE, {"value": workspace})
        pid_2 = session_2.execute(text("SELECT pg_backend_pid()")).scalar_one()
        session_1.execute(allocation(first, 70_000))

        def second_session() -> None:
            try:
                session_2.execute(allocation(second, 60_000))
                inserted.set()
                proceed.wait(30)
                session_2.commit()
                outcomes.append(None)
            except DBAPIError as exc:
                outcomes.append(getattr(exc.orig, "sqlstate", None))
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
    with db_engine.connect() as connection:
        total = connection.execute(
            text(
                "SELECT coalesce(sum(amount_minor), 0) FROM repayment_allocations "
                "WHERE repayment_id = :id AND deleted_at IS NULL"
            ),
            {"id": repayment},
        ).scalar_one()

    assert outcomes == [second_outcome]
    assert total == 70_000


def test_allocation_totals_cannot_be_rewritten_or_bypassed(
    app_engine: Engine, admin_engine: Engine, tenants: tuple[Tenant, Tenant]
) -> None:
    """Missing privileges never let the check pass silently: the API can read its totals
    but not write them or call the helper functions; trigger functions are not callable;
    the admin role cannot allocate at all."""
    a, _b = tenants
    as_a = {"workspace": a.workspace_id}
    calls = {
        "update total": text("UPDATE repayment_allocation_totals SET allocated_minor = 0"),
        "insert total": text(
            "INSERT INTO repayment_allocation_totals VALUES (gen_random_uuid(), :ws, 0)"
        ).bindparams(ws=a.workspace_id),
        "add_to_total": text(
            "SELECT add_to_repayment_allocation_total(:ws, :r, -10000)"
        ).bindparams(ws=a.workspace_id, r=a.repayment),
        "check": text("SELECT check_repayment_allocations(:r)").bindparams(r=a.repayment),
        "trigger function": text("SELECT maintain_repayment_allocation_totals()"),
    }
    results = {
        name: act(app_engine, rowcount(statement), **as_a).sqlstate
        for name, statement in calls.items()
    }
    readable = act(
        app_engine,
        scalar(
            text(
                "SELECT allocated_minor FROM repayment_allocation_totals WHERE repayment_id = :r"
            ).bindparams(r=a.repayment)
        ),
        **as_a,
    )
    admin_allocation = act(
        admin_engine,
        rowcount(
            insert(T["repayment_allocations"]).values(
                workspace_id=a.workspace_id,
                repayment_id=a.repayment,
                statement_id=a.statement,
                amount_minor=1,
            )
        ),
    )

    assert results == dict.fromkeys(calls, INSUFFICIENT_PRIVILEGE)
    assert readable.value == 10_000
    assert admin_allocation.sqlstate == INSUFFICIENT_PRIVILEGE


def test_allocation_check_fails_closed_when_its_owner_is_subject_to_rls(
    temporary_databases: "DatabaseFactory", rows_class: "type[Rows]", admin_database_url: "URL"
) -> None:
    """The SECURITY DEFINER trigger functions run as the migration superuser, which RLS does
    not filter. Were they and the tables owned by an ordinary role, FORCE ROW LEVEL SECURITY
    would apply to that owner too: with no policy for it the allocation total cannot be
    written and the allocation fails (42501) -- it is never accepted unchecked."""
    url = temporary_databases.create()
    owner = f"cardflow_test_owner_{uuid.uuid4().hex[:8]}"
    admin = create_engine(admin_database_url, poolclass=NullPool)
    engine = create_engine(url, poolclass=NullPool)
    try:
        upgrade(url, "head")
        with admin.begin() as connection:
            connection.execute(text(f"CREATE ROLE {owner} NOLOGIN NOBYPASSRLS"))
        with engine.begin() as connection:
            connection.execute(text(f"GRANT USAGE ON SCHEMA public TO {owner}"))
            for table in ("repayments", "repayment_allocation_totals"):
                connection.execute(text(f"ALTER TABLE {table} OWNER TO {owner}"))
            for function in (
                "maintain_repayment_allocation_totals()",
                "repayment_allocations_check()",
                "repayments_allocation_check()",
                "add_to_repayment_allocation_total(uuid, uuid, bigint)",
                "check_repayment_allocations(uuid)",
            ):
                connection.execute(text(f"ALTER FUNCTION {function} OWNER TO {owner}"))
            rows = rows_class(connection)
            account = rows.account()
            repayment = rows.repayment(account, 100_000)
            statement = rows.statement(account)
        allocated = act(
            engine,
            lambda connection: rows_class(connection).allocation(
                account.workspace_id, repayment, statement, 1_000
            ),
            commit=True,
        )
    finally:
        engine.dispose()
        temporary_databases.drop(url)
        with admin.begin() as connection:
            connection.execute(text(f"DROP ROLE IF EXISTS {owner}"))
        admin.dispose()

    assert allocated.sqlstate == INSUFFICIENT_PRIVILEGE
    assert "row-level security" in str(allocated.message)


# --- registration, users, jobs, audit, sync -------------------------------------------------


def test_registration_flow_under_rls(app_engine: Engine, db_engine: Engine) -> None:
    """Registration as the API: bind the new workspace and user ids first, then insert user,
    workspace, membership, device and refresh session (ORM-style INSERT ... RETURNING works
    because the bound rows are visible); later the user is visible through the membership."""
    workspace, user = uuid.uuid4(), uuid.uuid4()
    stranger = act(db_engine, scalar(insert(T["users"]).returning(T["users"].c.id)), commit=True)

    def register(connection: Connection) -> uuid.UUID:
        connection.execute(insert(T["users"]).values(id=user).returning(T["users"].c.created_at))
        connection.execute(
            insert(T["workspaces"])
            .values(id=workspace, owner_user_id=user, kind="real")
            .returning(T["workspaces"].c.created_at)
        )
        connection.execute(
            insert(T["workspace_members"]).values(
                workspace_id=workspace, user_id=user, role="owner"
            )
        )
        device = connection.execute(
            insert(T["devices"])
            .values(workspace_id=workspace, user_id=user, platform="android", public_key=b"p" * 32)
            .returning(T["devices"].c.id)
        ).scalar_one()
        connection.execute(
            insert(T["auth_sessions"]).values(
                workspace_id=workspace,
                device_id=device,
                refresh_token_hash=uuid.uuid4().hex * 2,
                expires_at=datetime.now(UTC) + timedelta(days=30),
            )
        )
        return device

    unbound = act(app_engine, rowcount(insert(T["users"]).values(id=uuid.uuid4())))
    registered = act(app_engine, register, workspace=workspace, user=user, commit=True)
    users = T["users"]
    later = act(
        app_engine,
        lambda connection: set(
            connection.execute(
                select(users.c.id).where(users.c.id.in_([user, stranger.value]))
            ).scalars()
        ),
        workspace=workspace,
    )
    other_user_update = act(
        app_engine,
        rowcount(update(users).where(users.c.id == stranger.value).values(display_name="x")),
        workspace=workspace,
        user=user,
    )

    assert unbound.sqlstate == INSUFFICIENT_PRIVILEGE
    assert registered.ok, registered
    assert later.value == {user}
    assert other_user_update.value == 0


def test_app_enqueues_and_reads_only_its_own_jobs(
    app_engine: Engine, tenants: tuple[Tenant, Tenant]
) -> None:
    """The API enqueues queued jobs of its workspace only and reads only those
    (cardflow.jobs.queue.enqueue / get_job as cardflow_app); it cannot change jobs."""
    a, b = tenants
    registry = _registry()

    def enqueue_for(workspace: uuid.UUID | None) -> Callable[[Connection], uuid.UUID]:
        return lambda connection: enqueue(
            connection, JOB_KIND, {}, workspace_id=workspace, registry=registry
        )

    own = act(app_engine, enqueue_for(a.workspace_id), workspace=a.workspace_id)
    foreign = act(app_engine, enqueue_for(b.workspace_id), workspace=a.workspace_id)
    system = act(app_engine, enqueue_for(None), workspace=a.workspace_id)
    running = act(
        app_engine,
        rowcount(
            insert(T["jobs"]).values(
                kind=JOB_KIND, payload={}, status="running", workspace_id=a.workspace_id
            )
        ),
        workspace=a.workspace_id,
    )
    views = act(
        app_engine,
        lambda connection: (
            get_job(connection, a.job, workspace_id=a.workspace_id),
            get_job(connection, b.job, workspace_id=b.workspace_id),
        ),
        workspace=a.workspace_id,
    )
    changed = act(
        app_engine,
        rowcount(update(T["jobs"]).where(T["jobs"].c.id == a.job).values(status="cancelled")),
        workspace=a.workspace_id,
    )

    assert own.ok, own
    assert foreign.sqlstate == INSUFFICIENT_PRIVILEGE
    assert system.sqlstate == INSUFFICIENT_PRIVILEGE
    assert running.sqlstate == INSUFFICIENT_PRIVILEGE
    own_view, foreign_view = views.value
    assert own_view is not None
    assert own_view.id == a.job
    assert foreign_view is None
    assert changed.sqlstate == INSUFFICIENT_PRIVILEGE


@pytest.mark.parametrize("engine_name", ["app_engine", "worker_engine", "admin_engine"])
def test_audit_log_is_append_only_for_everyone(
    engine_name: str, request: pytest.FixtureRequest, tenants: tuple[Tenant, Tenant]
) -> None:
    """AP-06: no role may UPDATE, DELETE or TRUNCATE audit_log."""
    a, _b = tenants
    engine: Engine = request.getfixturevalue(engine_name)
    for statement in (
        "UPDATE audit_log SET action = 'x'",
        "DELETE FROM audit_log",
        "TRUNCATE audit_log",
    ):
        assert act(engine, rowcount(text(statement)), workspace=a.workspace_id).sqlstate == (
            INSUFFICIENT_PRIVILEGE
        ), statement


def test_api_appends_audit_rows_of_its_workspace_or_the_system(
    app_engine: Engine, tenants: tuple[Tenant, Tenant]
) -> None:
    """The API appends audit rows for its workspace or system-wide (workspace_id NULL), never
    for another workspace; it cannot read the log nor choose the timestamp."""
    a, b = tenants
    audit = T["audit_log"]
    as_a = {"workspace": a.workspace_id}

    def append(**values: object) -> Callable[[Connection], int]:
        # .inline(): no RETURNING -- the API has no SELECT on audit_log (append-only).
        return rowcount(
            insert(audit).values(actor_kind="user", action="test.append", **values).inline()
        )

    assert act(app_engine, append(workspace_id=a.workspace_id), **as_a).ok
    assert act(app_engine, append(workspace_id=None), **as_a).ok
    assert act(app_engine, append(workspace_id=b.workspace_id), **as_a).sqlstate == (
        INSUFFICIENT_PRIVILEGE
    )
    assert act(app_engine, append(workspace_id=a.workspace_id, at=NOW), **as_a).sqlstate == (
        INSUFFICIENT_PRIVILEGE
    )
    assert act(app_engine, scalar(select(func.count()).select_from(audit)), **as_a).sqlstate == (
        INSUFFICIENT_PRIVILEGE
    )


def test_sync_changes_are_append_and_read_per_workspace(
    app_engine: Engine, tenants: tuple[Tenant, Tenant]
) -> None:
    """The API appends and reads its workspace's change log; the database assigns seq and
    txid (the pull cursor) -- the API can neither supply them nor change or delete rows."""
    a, b = tenants
    changes = T["sync_changes"]
    as_a = {"workspace": a.workspace_id}
    values = {"table_name": "cards", "row_id": a.card, "op": "update", "row_version": 2}

    appended = act(
        app_engine,
        scalar(
            insert(changes).values(workspace_id=a.workspace_id, **values).returning(changes.c.seq)
        ),
        **as_a,
    )
    forged = act(
        app_engine,
        rowcount(
            text(
                "INSERT INTO sync_changes (workspace_id, table_name, row_id, op, row_version, "
                "txid) VALUES (:ws, 'cards', :row, 'update', 2, '1')"
            ).bindparams(ws=a.workspace_id, row=a.card)
        ),
        **as_a,
    )
    seen = act(
        app_engine,
        lambda connection: set(
            connection.execute(
                select(changes.c.workspace_id).where(
                    changes.c.workspace_id.in_([a.workspace_id, b.workspace_id])
                )
            ).scalars()
        ),
        **as_a,
    )

    assert appended.ok, appended
    assert forged.sqlstate == INSUFFICIENT_PRIVILEGE
    assert seen.value == {a.workspace_id}
    for statement in ("UPDATE sync_changes SET op = 'delete'", "DELETE FROM sync_changes"):
        assert act(app_engine, rowcount(text(statement)), **as_a).sqlstate == INSUFFICIENT_PRIVILEGE


def test_idempotency_keys_are_per_workspace(
    app_engine: Engine, tenants: tuple[Tenant, Tenant]
) -> None:
    """The API stores and reads idempotency keys of its workspace only (the admin role is
    denied in test_tc_db_06_admin_cannot_read_content)."""
    a, b = tenants
    keys = T["idempotency_keys"]
    seen = act(
        app_engine,
        lambda connection: set(
            connection.execute(
                select(keys.c.workspace_id).where(
                    keys.c.workspace_id.in_([a.workspace_id, b.workspace_id])
                )
            ).scalars()
        ),
        workspace=a.workspace_id,
    )
    assert seen.value == {a.workspace_id}
