"""Database constraints (T-005 / T-007, revisions 0001 + 0002), test-plan §4 TC-DB-01..09.

Revision 0002 (data-model §10) made statement versions immutable except for the one-time
tombstone, gated physical deletes behind a transaction-scoped purge token and expressed
"same currency account" through composite foreign keys; the tests below follow head.

TC-DB-05/06 (row-level security, roles) belong to T-006; TC-DB-10 (jobs SKIP LOCKED) to
T-008. TC-DB-07 is checked at the database layer only (the unique key that makes a
replay detectable); the HTTP replay semantics are T-010.

Immediate violations run inside a savepoint of the rolled-back ``conn`` transaction.
Deferred checks (TC-DB-09) need real COMMITs: they use their own connections, commit the
fixture rows first and only then open the transaction under test. Every test works in
fresh workspaces, so committed rows never interfere with each other.
"""

import re
import threading
import time
import uuid
from collections.abc import Iterator
from dataclasses import dataclass
from datetime import UTC, date, datetime
from typing import TYPE_CHECKING

import pytest
from sqlalchemy import Executable, delete, insert, select, text, update
from sqlalchemy.engine import Connection, Engine
from sqlalchemy.exc import DBAPIError

from cardflow.db.models import metadata
from cardflow.planner.engine.money import MINOR_DIGITS, ROUNDING

if TYPE_CHECKING:
    from tests.db.conftest import Account, Rows

pytestmark = [pytest.mark.db, pytest.mark.usefixtures("require_head_schema")]

CHECK_VIOLATION = "23514"
FOREIGN_KEY_VIOLATION = "23503"
UNIQUE_VIOLATION = "23505"
EXCLUSION_VIOLATION = "23P01"
INTEGRITY_CONSTRAINT_VIOLATION = "23000"
STRING_DATA_RIGHT_TRUNCATION = "22001"

T = metadata.tables
NOW = datetime(2026, 10, 16, 8, 0, tzinfo=UTC)


def sqlstate_of(error: DBAPIError) -> tuple[str | None, str | None]:
    orig = error.orig
    diag = getattr(orig, "diag", None)
    return getattr(orig, "sqlstate", None), getattr(diag, "constraint_name", None)


def assert_rejected(
    conn: Connection, statement: Executable, sqlstate: str, constraint: str | None = None
) -> None:
    """Run ``statement`` in a savepoint; it must fail with ``sqlstate`` (and constraint)."""
    with pytest.raises(DBAPIError) as excinfo, conn.begin_nested():
        conn.execute(statement)
    state, name = sqlstate_of(excinfo.value)
    assert state == sqlstate, excinfo.value
    if constraint is not None:
        assert name == constraint


# --- TC-DB-01: statement_versions are append-only ------------------------------------

AMOUNT_COLUMNS = (
    "previous_balance_minor",
    "new_balance_minor",
    "min_due_minor",
    "payments_minor",
    "credits_minor",
    "fees_minor",
    "interest_minor",
    "installment_due_minor",
    "credit_balance_minor",
)


@pytest.fixture
def version(rows: "Rows") -> tuple[uuid.UUID, uuid.UUID]:
    """(workspace_id, statement_version_id) of a fresh statement version."""
    account = rows.account()
    statement = rows.statement(account)
    return account.workspace_id, rows.statement_version(account.workspace_id, statement)


@pytest.mark.parametrize(
    ("column", "value"),
    [*((column, 1) for column in AMOUNT_COLUMNS), ("due_date", date(2026, 12, 1))],
)
def test_tc_db_01_statement_version_amount_update_rejected(
    conn: Connection, version: tuple[uuid.UUID, uuid.UUID], column: str, value: object
) -> None:
    """TC-DB-01: UPDATE of any amount column or due_date is rejected (whole row immutable)."""
    _, version_id = version
    table = T["statement_versions"]

    assert_rejected(
        conn,
        update(table).where(table.c.id == version_id).values({column: value}),
        INTEGRITY_CONSTRAINT_VIOLATION,
        "statement_versions_immutable",
    )


def test_tc_db_01_unchanged_amount_in_update_is_still_rejected(
    conn: Connection, version: tuple[uuid.UUID, uuid.UUID]
) -> None:
    """TC-DB-01: any UPDATE that is not the tombstone is rejected, even a no-op one."""
    _, version_id = version
    table = T["statement_versions"]

    assert_rejected(
        conn,
        update(table).where(table.c.id == version_id).values(new_balance_minor=123_456),
        INTEGRITY_CONSTRAINT_VIOLATION,
        "statement_versions_immutable",
    )


def test_tc_db_01_only_the_tombstone_is_allowed(
    conn: Connection, version: tuple[uuid.UUID, uuid.UUID]
) -> None:
    """TC-DB-01 (0002): annotating is rejected; deleted_at may be set once (tombstone)."""
    _, version_id = version
    table = T["statement_versions"]

    assert_rejected(
        conn,
        update(table).where(table.c.id == version_id).values(reason="duplicate import"),
        INTEGRITY_CONSTRAINT_VIOLATION,
        "statement_versions_immutable",
    )
    conn.execute(update(table).where(table.c.id == version_id).values(deleted_at=NOW))

    stored = conn.execute(
        select(table.c.new_balance_minor, table.c.deleted_at, table.c.row_version).where(
            table.c.id == version_id
        )
    ).one()
    assert stored == (123_456, NOW, 2)  # row_version is bumped by the database
    assert_rejected(
        conn,
        update(table).where(table.c.id == version_id).values(deleted_at=None),
        INTEGRITY_CONSTRAINT_VIOLATION,
        "statement_versions_immutable",
    )


def test_tc_db_01_correction_is_a_new_version(
    conn: Connection, rows: "Rows", version: tuple[uuid.UUID, uuid.UUID]
) -> None:
    """TC-DB-01: the supported correction path appends version 2 next to version 1."""
    workspace_id, version_id = version
    table = T["statement_versions"]
    statement_id = conn.execute(
        select(table.c.statement_id).where(table.c.id == version_id)
    ).scalar_one()

    rows.statement_version(workspace_id, statement_id, version_no=2)
    assert_rejected(
        conn,
        insert(table).values(
            workspace_id=workspace_id,
            statement_id=statement_id,
            version_no=2,
            source_kind="correction",
            new_balance_minor=1,
            due_date=date(2026, 11, 28),
            recorded_by="user",
        ),
        UNIQUE_VIOLATION,
        "uq_statement_versions_statement_id_version_no",
    )


def test_tc_db_01_delete_rejected_without_purge_flag(
    conn: Connection, version: tuple[uuid.UUID, uuid.UUID]
) -> None:
    """TC-DB-01: DELETE is rejected without the purge token of this transaction."""
    _, version_id = version
    table = T["statement_versions"]

    assert_rejected(
        conn,
        delete(table).where(table.c.id == version_id),
        INTEGRITY_CONSTRAINT_VIOLATION,
        "statement_versions_no_delete",
    )


def test_tc_db_01_truncate_rejected_without_purge_flag(conn: Connection) -> None:
    """TC-DB-01: TRUNCATE (statement-level trigger) is rejected as well.

    Runs in the always-rolled-back ``conn`` transaction with no pending trigger events
    (PostgreSQL refuses TRUNCATE of tables with pending deferred events before any
    trigger runs), so even a missing trigger could not empty the shared database.
    """
    assert_rejected(
        conn,
        text("TRUNCATE statement_versions CASCADE"),
        INTEGRITY_CONSTRAINT_VIOLATION,
        "statement_versions_no_truncate",
    )


def test_tc_db_01_purge_token_allows_delete_for_one_transaction_only(
    db_engine: Engine, rows_class: "type[Rows]"
) -> None:
    """TC-DB-01 (0002): app.purge must equal this transaction's id (workspace purge only)."""
    table = T["statement_versions"]
    with db_engine.begin() as connection:
        rows = rows_class(connection)
        account = rows.account()
        first = rows.statement(account, date(2026, 11, 10))
        second = rows.statement(account, date(2026, 12, 10))
        first_version = rows.statement_version(account.workspace_id, first)
        second_version = rows.statement_version(account.workspace_id, second)

    with db_engine.begin() as connection:
        connection.execute(text("SELECT set_config('app.purge', pg_current_xact_id()::text, true)"))
        purged = connection.execute(delete(table).where(table.c.id == first_version)).rowcount
        # The purge token never unlocks updates.
        with pytest.raises(DBAPIError) as excinfo, connection.begin_nested():
            connection.execute(
                update(table).where(table.c.id == second_version).values(fees_minor=1)
            )
        assert sqlstate_of(excinfo.value) == (
            INTEGRITY_CONSTRAINT_VIOLATION,
            "statement_versions_immutable",
        )
        token = connection.execute(text("SELECT current_setting('app.purge')")).scalar_one()
    assert purged == 1

    with db_engine.connect() as connection:
        # A stale token (an earlier transaction id) does not open the gate.
        stale = connection.begin()
        connection.execute(text("SELECT set_config('app.purge', :t, true)"), {"t": token})
        with pytest.raises(DBAPIError) as excinfo:
            connection.execute(delete(table).where(table.c.id == second_version))
        stale.rollback()
        assert sqlstate_of(excinfo.value) == (
            INTEGRITY_CONSTRAINT_VIOLATION,
            "statement_versions_no_delete",
        )


# --- TC-DB-02: cards.last4 ------------------------------------------------------------


@pytest.mark.parametrize(
    ("last4", "sqlstate"),
    [
        ("123", CHECK_VIOLATION),
        ("12a4", CHECK_VIOLATION),
        ("abcd", CHECK_VIOLATION),
        ("", CHECK_VIOLATION),
        ("12 4", CHECK_VIOLATION),
        ("12345", STRING_DATA_RIGHT_TRUNCATION),
        ("6222021234567890123", STRING_DATA_RIGHT_TRUNCATION),
    ],
)
def test_tc_db_02_card_last4_must_be_four_digits(
    conn: Connection, rows: "Rows", last4: str, sqlstate: str
) -> None:
    """TC-DB-02: anything but exactly four digits is rejected (no full card numbers)."""
    account = rows.account()

    assert_rejected(
        conn,
        insert(T["cards"]).values(
            workspace_id=account.workspace_id,
            credit_account_id=account.credit_account_id,
            last4=last4,
            holder_kind="primary",
            status="active",
        ),
        sqlstate,
        "ck_cards_last4_digits" if sqlstate == CHECK_VIOLATION else None,
    )


def test_tc_db_02_card_last4_accepts_four_digits(conn: Connection, rows: "Rows") -> None:
    """TC-DB-02: a valid last4 (leading zero kept) is stored."""
    account = rows.account()
    card_id = rows.card(account.workspace_id, account.credit_account_id, last4="0123")

    stored = conn.execute(select(T["cards"].c.last4).where(T["cards"].c.id == card_id))
    assert stored.scalar_one() == "0123"


# --- TC-DB-03: billing rule versions do not overlap within one scope ------------------


def test_tc_db_03_same_scope_overlap_rejected(conn: Connection, rows: "Rows") -> None:
    """TC-DB-03: same workspace + same subject + overlapping period -> exclusion error."""
    account = rows.account()
    rows.rule_version(
        account.workspace_id, "credit_account", account.credit_account_id, date(2026, 1, 1)
    )

    assert_rejected(
        conn,
        insert(T["billing_rule_versions"]).values(
            workspace_id=account.workspace_id,
            subject_kind="credit_account",
            subject_id=account.credit_account_id,
            statement_day=5,
            due_kind="days_after_statement",
            due_days=20,
            source="test",
            effective_from=date(2026, 6, 1),
            effective_to=date(2027, 1, 1),
            version=2,
            review_status="user_declared",
        ),
        EXCLUSION_VIOLATION,
        "ex_billing_rule_versions_scope_subject_period",
    )


def test_tc_db_03_two_published_templates_overlap_rejected(conn: Connection, rows: "Rows") -> None:
    """TC-DB-03: official templates form one scope (workspace_id NULL)."""
    product = rows.product(rows.bank())
    rows.rule_version(None, "product", product, date(2026, 1, 1), review_status="published")

    assert_rejected(
        conn,
        insert(T["billing_rule_versions"]).values(
            workspace_id=None,
            subject_kind="product",
            subject_id=product,
            statement_day=10,
            due_kind="fixed_day",
            due_day=28,
            source="S02",
            effective_from=date(2026, 3, 1),
            version=2,
            review_status="published",
        ),
        EXCLUSION_VIOLATION,
        "ex_billing_rule_versions_scope_subject_period",
    )


def test_tc_db_03_template_and_user_declared_do_not_conflict(rows: "Rows") -> None:
    """TC-DB-03: a workspace may declare its own rule over a published template."""
    product = rows.product(rows.bank())
    workspace = rows.workspace()

    rows.rule_version(None, "product", product, date(2026, 1, 1), review_status="published")
    rows.rule_version(workspace, "product", product, date(2026, 1, 1))


def test_tc_db_03_two_workspaces_do_not_conflict(rows: "Rows") -> None:
    """TC-DB-03: user-declared rules of different workspaces for one template product."""
    product = rows.product(rows.bank())

    rows.rule_version(rows.workspace(), "product", product, date(2026, 1, 1))
    rows.rule_version(rows.workspace(), "product", product, date(2026, 1, 1))


def test_tc_db_03_adjacent_periods_drafts_and_tombstones_do_not_conflict(
    conn: Connection, rows: "Rows"
) -> None:
    """TC-DB-03: [from, to) ranges may touch; drafts and tombstoned rows are not in effect."""
    account = rows.account()
    subject = account.credit_account_id
    first = rows.rule_version(
        account.workspace_id, "credit_account", subject, date(2026, 1, 1), date(2026, 7, 1)
    )
    rows.rule_version(account.workspace_id, "credit_account", subject, date(2026, 7, 1))
    rows.rule_version(
        account.workspace_id, "credit_account", subject, date(2026, 1, 1), review_status="draft"
    )
    table = T["billing_rule_versions"]
    conn.execute(update(table).where(table.c.id == first).values(deleted_at=NOW))

    rows.rule_version(
        account.workspace_id, "credit_account", subject, date(2026, 2, 1), date(2026, 7, 1)
    )


# --- TC-DB-04: composite foreign keys reject cross-workspace links --------------------


def test_tc_db_04_currency_account_cannot_join_other_workspace_account(
    conn: Connection, rows: "Rows"
) -> None:
    """TC-DB-04: (workspace_id, credit_account_id) must exist in the SAME workspace."""
    foreign = rows.account()
    mine = rows.workspace()

    assert_rejected(
        conn,
        insert(T["currency_accounts"]).values(
            workspace_id=mine, credit_account_id=foreign.credit_account_id, currency="USD"
        ),
        FOREIGN_KEY_VIOLATION,
        "fk_currency_accounts_credit_account_id",
    )


def test_tc_db_04_transaction_cannot_use_other_workspace_card(
    conn: Connection, rows: "Rows"
) -> None:
    """TC-DB-04: a transaction cannot point at another workspace's card."""
    foreign = rows.account()
    foreign_card = rows.card(foreign.workspace_id, foreign.credit_account_id)
    mine = rows.account()

    assert_rejected(
        conn,
        insert(T["transactions"]).values(
            workspace_id=mine.workspace_id,
            currency_account_id=mine.currency_account_id,
            card_id=foreign_card,
            txn_type="purchase",
            amount_minor=10_000,
            currency="CNY",
            txn_at=NOW,
            txn_tz="Asia/Shanghai",
            time_precision="datetime",
            status="posted",
            fingerprint="f",
            source_kind="manual",
            confirmation_level="user_confirmed",
        ),
        FOREIGN_KEY_VIOLATION,
        "fk_transactions_credit_account_id_card_id",
    )


def test_tc_db_04_allocation_cannot_link_other_workspace_statement(
    conn: Connection, rows: "Rows"
) -> None:
    """TC-DB-04: a repayment of workspace A cannot settle a statement of workspace B."""
    mine = rows.account()
    repayment = rows.repayment(mine, 10_000)
    foreign = rows.account()
    foreign_statement = rows.statement(foreign)

    assert_rejected(
        conn,
        insert(T["repayment_allocations"]).values(
            workspace_id=mine.workspace_id,
            repayment_id=repayment,
            statement_id=foreign_statement,
            amount_minor=1_000,
        ),
        FOREIGN_KEY_VIOLATION,
        "fk_repayment_allocations_currency_account_id_statement_id",
    )


def test_tc_db_04_current_version_must_belong_to_the_statement(
    conn: Connection, rows: "Rows"
) -> None:
    """TC-DB-04: statements.current_version_id cannot point at another statement's version."""
    account = rows.account()
    first = rows.statement(account, date(2026, 11, 10))
    second = rows.statement(account, date(2026, 12, 10))
    other_version = rows.statement_version(account.workspace_id, second)
    table = T["statements"]

    # The foreign key is DEFERRABLE INITIALLY DEFERRED: accepted for now ...
    conn.execute(update(table).where(table.c.id == first).values(current_version_id=other_version))
    # ... and rejected as soon as it is checked (at COMMIT, or here on demand).
    assert_rejected(
        conn,
        text("SET CONSTRAINTS fk_statements_id_current_version_id IMMEDIATE"),
        FOREIGN_KEY_VIOLATION,
        "fk_statements_id_current_version_id",
    )


def test_tc_db_04_template_references_accept_templates_and_own_rows(rows: "Rows") -> None:
    """TC-DB-04: banks/products: official templates or the same workspace are fine."""
    workspace = rows.workspace()
    template_bank = rows.bank()
    own_bank = rows.bank(workspace)

    rows.credit_account(workspace, bank_id=template_bank)
    rows.credit_account(workspace, bank_id=own_bank, product_id=rows.product(template_bank))
    rows.credit_account(workspace, bank_id=own_bank, product_id=rows.product(own_bank, workspace))


def test_tc_db_04_template_references_reject_other_workspaces(
    conn: Connection, rows: "Rows"
) -> None:
    """TC-DB-04: a plain FK cannot stop it, the scope trigger does (template tables)."""
    foreign_workspace = rows.workspace()
    foreign_bank = rows.bank(foreign_workspace)
    foreign_product = rows.product(foreign_bank, foreign_workspace)
    mine = rows.workspace()
    accounts = T["credit_accounts"]

    assert_rejected(
        conn,
        insert(accounts).values(
            workspace_id=mine, bank_id=foreign_bank, holder_alias="me", status="active"
        ),
        FOREIGN_KEY_VIOLATION,
        "credit_accounts_bank_scope",
    )
    assert_rejected(
        conn,
        insert(accounts).values(
            workspace_id=mine,
            bank_id=rows.bank(),
            product_id=foreign_product,
            holder_alias="me",
            status="active",
        ),
        FOREIGN_KEY_VIOLATION,
        "credit_accounts_product_scope",
    )
    assert_rejected(
        conn,
        insert(T["card_products"]).values(workspace_id=None, bank_id=foreign_bank, name="x"),
        FOREIGN_KEY_VIOLATION,
        "card_products_bank_scope",
    )
    assert_rejected(
        conn,
        insert(T["credit_pools"]).values(workspace_id=mine, bank_id=foreign_bank, name="pool"),
        FOREIGN_KEY_VIOLATION,
        "credit_pools_bank_scope",
    )


def test_tc_db_04_rule_binding_and_subject_stay_in_scope(conn: Connection, rows: "Rows") -> None:
    """TC-DB-04: rule bindings and rule subjects cannot reach into another workspace."""
    foreign = rows.account()
    foreign_rule = rows.rule_version(
        foreign.workspace_id, "credit_account", foreign.credit_account_id, date(2026, 1, 1)
    )
    mine = rows.account()

    assert_rejected(
        conn,
        insert(T["rule_bindings"]).values(
            workspace_id=mine.workspace_id,
            credit_account_id=mine.credit_account_id,
            billing_rule_version_id=foreign_rule,
            effective_from=date(2026, 1, 1),
        ),
        FOREIGN_KEY_VIOLATION,
        "rule_bindings_rule_version_scope",
    )
    assert_rejected(
        conn,
        insert(T["billing_rule_versions"]).values(
            workspace_id=mine.workspace_id,
            subject_kind="credit_account",
            subject_id=foreign.credit_account_id,
            statement_day=10,
            due_kind="fixed_day",
            due_day=28,
            source="test",
            effective_from=date(2026, 1, 1),
            version=1,
            review_status="user_declared",
        ),
        FOREIGN_KEY_VIOLATION,
        "billing_rule_versions_subject_scope",
    )
    template_product = rows.product(rows.bank())
    template_rule = rows.rule_version(
        None, "product", template_product, date(2026, 1, 1), review_status="published"
    )
    conn.execute(
        insert(T["rule_bindings"]).values(
            workspace_id=mine.workspace_id,
            credit_account_id=mine.credit_account_id,
            billing_rule_version_id=template_rule,
            effective_from=date(2026, 1, 1),
        )
    )


def test_tc_db_04_template_rows_cannot_change_workspace(conn: Connection, rows: "Rows") -> None:
    """TC-DB-04: re-scoping a template would silently re-scope everything using it."""
    bank = rows.bank()
    table = T["banks"]

    assert_rejected(
        conn,
        update(table).where(table.c.id == bank).values(workspace_id=rows.workspace()),
        INTEGRITY_CONSTRAINT_VIOLATION,
        "banks_workspace_immutable",
    )


def test_tc_db_04_templates_must_be_product_rules(conn: Connection, rows: "Rows") -> None:
    """TC-DB-04: an official template cannot target a (workspace-private) account.

    Two independent layers reject it: the BEFORE trigger (subject must be in scope; it
    runs first) and, underneath, ``ck_billing_rule_versions_template_subject`` -- checked by
    its definition here instead of disabling the trigger on the shared database (R2-34).
    """
    account = rows.account()
    template_for_account = insert(T["billing_rule_versions"]).values(
        workspace_id=None,
        subject_kind="credit_account",
        subject_id=account.credit_account_id,
        statement_day=10,
        due_kind="fixed_day",
        due_day=28,
        source="test",
        effective_from=date(2026, 1, 1),
        version=1,
        review_status="published",
    )

    assert_rejected(
        conn, template_for_account, FOREIGN_KEY_VIOLATION, "billing_rule_versions_subject_scope"
    )
    definition = conn.execute(
        text(
            "SELECT pg_get_constraintdef(oid) FROM pg_constraint "
            "WHERE conname = 'ck_billing_rule_versions_template_subject'"
        )
    ).scalar_one()
    assert definition == (
        "CHECK (((workspace_id IS NOT NULL) OR (subject_kind = 'product'::text)))"
    )


# --- TC-DB-07: idempotency key uniqueness (database layer) ----------------------------


def idempotency_key(workspace_id: uuid.UUID, key: str, status: int = 201) -> Executable:
    return insert(T["idempotency_keys"]).values(
        workspace_id=workspace_id,
        key=key,
        request_hash="a" * 64,
        response_status=status,
        response_body={"id": "x"},
    )


def test_tc_db_07_duplicate_idempotency_key_rejected(conn: Connection, rows: "Rows") -> None:
    """TC-DB-07: PK (workspace_id, key) makes a replay detectable; same key elsewhere ok."""
    workspace = rows.workspace()
    key = str(uuid.uuid4())
    conn.execute(idempotency_key(workspace, key))

    assert_rejected(
        conn, idempotency_key(workspace, key, status=200), UNIQUE_VIOLATION, "pk_idempotency_keys"
    )
    conn.execute(idempotency_key(rows.workspace(), key))
    stored = conn.execute(
        select(T["idempotency_keys"].c.response_status).where(
            T["idempotency_keys"].c.workspace_id == workspace
        )
    ).scalar_one()
    assert stored == 201  # the first response is what a replay would return


def test_tc_db_07_request_hash_must_be_sha256_hex(conn: Connection, rows: "Rows") -> None:
    """TC-DB-07: request_hash is a 64-character lowercase hex digest."""
    statement = insert(T["idempotency_keys"]).values(
        workspace_id=rows.workspace(),
        key="k",
        request_hash="not-a-hash",
        response_status=201,
        response_body={},
    )

    assert_rejected(conn, statement, CHECK_VIOLATION, "ck_idempotency_keys_request_hash_hex")


# --- TC-DB-08: raw available limit may be negative ------------------------------------


def test_tc_db_08_negative_available_raw_is_kept(conn: Connection, rows: "Rows") -> None:
    """TC-DB-08: an over-limit snapshot stores the negative raw value unchanged."""
    account = rows.account()
    snapshot = rows.insert(
        "limit_snapshots",
        workspace_id=account.workspace_id,
        currency_account_id=account.currency_account_id,
        fixed_minor=1_000_000,
        used_minor=1_012_345,
        available_raw_minor=-12_345,
        includes_holds=True,
        source_kind="bank_app",
        balance_as_of=NOW,
        observed_at=NOW,
        confirmation_level="user_confirmed",
    )

    table = T["limit_snapshots"]
    stored = conn.execute(
        select(table.c.available_raw_minor, table.c.used_minor).where(table.c.id == snapshot)
    ).one()
    assert stored == (-12_345, 1_012_345)


# --- TC-DB-09: allocations never exceed the repayment (deferred constraint triggers) --


@dataclass(frozen=True)
class Settlement:
    """Committed fixture: one repayment and two statements of the same currency account."""

    account: "Account"
    repayment_id: uuid.UUID
    statement_ids: tuple[uuid.UUID, uuid.UUID]


@pytest.fixture
def settlement(db_engine: Engine, rows_class: "type[Rows]") -> Settlement:
    with db_engine.begin() as connection:
        rows = rows_class(connection)
        account = rows.account()
        return Settlement(
            account=account,
            repayment_id=rows.repayment(account, 100_000),
            statement_ids=(
                rows.statement(account, date(2026, 10, 10)),
                rows.statement(account, date(2026, 11, 10)),
            ),
        )


@pytest.fixture
def tx(db_engine: Engine) -> Iterator[Connection]:
    """A connection with an open transaction; the test commits (or expects a failure)."""
    with db_engine.connect() as connection:
        connection.begin()
        yield connection


def commit_rejected(connection: Connection, constraint: str) -> None:
    with pytest.raises(DBAPIError) as excinfo:
        connection.commit()
    assert sqlstate_of(excinfo.value) == (CHECK_VIOLATION, constraint)


def allocated(engine: Engine, repayment_id: uuid.UUID) -> list[int]:
    table = T["repayment_allocations"]
    with engine.connect() as connection:
        query = (
            select(table.c.amount_minor)
            .where(table.c.repayment_id == repayment_id, table.c.deleted_at.is_(None))
            .order_by(table.c.amount_minor)
        )
        return list(connection.execute(query).scalars())


def test_tc_db_09_over_allocation_rejected_at_commit(
    db_engine: Engine, settlement: Settlement, tx: Connection, rows_class: "type[Rows]"
) -> None:
    """TC-DB-09: SUM(allocations) > repayment amount fails at COMMIT, not at INSERT."""
    first, second = settlement.statement_ids
    rows = rows_class(tx)
    rows.allocation(settlement.account.workspace_id, settlement.repayment_id, first, 60_000)
    rows.allocation(settlement.account.workspace_id, settlement.repayment_id, second, 40_001)

    commit_rejected(tx, "repayment_allocations_within_amount")
    assert allocated(db_engine, settlement.repayment_id) == []


def test_tc_db_09_full_allocation_across_two_statements_commits(
    db_engine: Engine, settlement: Settlement, tx: Connection, rows_class: "type[Rows]"
) -> None:
    """TC-DB-09 / F-33: one repayment split over two statements, sum == amount."""
    first, second = settlement.statement_ids
    rows = rows_class(tx)
    rows.allocation(settlement.account.workspace_id, settlement.repayment_id, first, 60_000)
    rows.allocation(settlement.account.workspace_id, settlement.repayment_id, second, 40_000)
    tx.commit()

    assert allocated(db_engine, settlement.repayment_id) == [40_000, 60_000]


def test_tc_db_09_temporary_overage_fixed_before_commit_succeeds(
    db_engine: Engine, settlement: Settlement, tx: Connection, rows_class: "type[Rows]"
) -> None:
    """TC-DB-09: the check is deferred -- an intermediate overage inside the transaction is ok."""
    first, second = settlement.statement_ids
    workspace = settlement.account.workspace_id
    rows = rows_class(tx)
    rows.allocation(workspace, settlement.repayment_id, first, 90_000)
    rows.allocation(workspace, settlement.repayment_id, second, 30_000)  # 120_000 > 100_000
    table = T["repayment_allocations"]
    tx.execute(
        update(table)
        .where(table.c.repayment_id == settlement.repayment_id, table.c.statement_id == first)
        .values(amount_minor=70_000)
    )
    tx.commit()

    assert allocated(db_engine, settlement.repayment_id) == [30_000, 70_000]


def test_tc_db_09_set_constraints_immediate_reports_at_once(
    settlement: Settlement, tx: Connection, rows_class: "type[Rows]"
) -> None:
    """TC-DB-09: the triggers are DEFERRABLE; IMMEDIATE mode checks at the statement."""
    first, _ = settlement.statement_ids
    rows_class(tx).allocation(
        settlement.account.workspace_id, settlement.repayment_id, first, 100_001
    )

    with pytest.raises(DBAPIError) as excinfo:
        tx.execute(text("SET CONSTRAINTS repayment_allocations_within_amount IMMEDIATE"))
    assert sqlstate_of(excinfo.value) == (CHECK_VIOLATION, "repayment_allocations_within_amount")
    tx.rollback()


def test_tc_db_09_lowering_repayment_below_allocations_rejected(
    db_engine: Engine, settlement: Settlement, tx: Connection, rows_class: "type[Rows]"
) -> None:
    """TC-DB-09: repayments.amount_minor cannot drop below what is already allocated."""
    first, _ = settlement.statement_ids
    with db_engine.begin() as connection:
        rows_class(connection).allocation(
            settlement.account.workspace_id, settlement.repayment_id, first, 80_000
        )
    table = T["repayments"]
    tx.execute(
        update(table).where(table.c.id == settlement.repayment_id).values(amount_minor=79_999)
    )

    commit_rejected(tx, "repayment_allocations_within_amount")


def test_tc_db_09_tombstoned_allocations_do_not_count(
    db_engine: Engine, settlement: Settlement, tx: Connection, rows_class: "type[Rows]"
) -> None:
    """TC-DB-09: only live allocations (deleted_at IS NULL) are summed."""
    first, second = settlement.statement_ids
    workspace = settlement.account.workspace_id
    with db_engine.begin() as connection:
        rows_class(connection).allocation(workspace, settlement.repayment_id, first, 100_000)
    table = T["repayment_allocations"]
    tx.execute(
        update(table)
        .where(table.c.repayment_id == settlement.repayment_id, table.c.statement_id == first)
        .values(deleted_at=NOW)
    )
    rows_class(tx).allocation(workspace, settlement.repayment_id, second, 100_000)
    tx.commit()

    assert allocated(db_engine, settlement.repayment_id) == [100_000]


def test_tc_db_09_statement_of_other_currency_account_rejected(
    conn: Connection, rows: "Rows", settlement: Settlement
) -> None:
    """TC-DB-09 (0002): a repayment only settles statements of its own currency account;
    a composite foreign key rejects it at INSERT (it was a COMMIT-time check in 0001)."""
    usd = rows.currency_account(
        settlement.account.workspace_id, settlement.account.credit_account_id, "USD"
    )
    usd_statement = rows.insert(
        "statements",
        workspace_id=settlement.account.workspace_id,
        currency_account_id=usd,
        statement_date=date(2026, 11, 10),
        due_date=date(2026, 11, 28),
        status="issued",
    )

    assert_rejected(
        conn,
        insert(T["repayment_allocations"]).values(
            workspace_id=settlement.account.workspace_id,
            repayment_id=settlement.repayment_id,
            statement_id=usd_statement,
            amount_minor=1_000,
        ),
        FOREIGN_KEY_VIOLATION,
        "fk_repayment_allocations_currency_account_id_statement_id",
    )


def test_tc_db_09_moving_an_allocated_statement_rejected(
    db_engine: Engine, settlement: Settlement, rows_class: "type[Rows]"
) -> None:
    """TC-DB-09 (0002): re-homing an allocated statement to another currency account fails
    on the composite foreign key of the allocation."""
    first, _ = settlement.statement_ids
    workspace = settlement.account.workspace_id
    with db_engine.begin() as connection:
        rows = rows_class(connection)
        rows.allocation(workspace, settlement.repayment_id, first, 10_000)
        usd = rows.currency_account(workspace, settlement.account.credit_account_id, "USD")
    table = T["statements"]

    with db_engine.connect() as connection:
        with pytest.raises(DBAPIError) as excinfo, connection.begin():
            connection.execute(
                update(table).where(table.c.id == first).values(currency_account_id=usd)
            )
        assert sqlstate_of(excinfo.value) == (
            FOREIGN_KEY_VIOLATION,
            "fk_repayment_allocations_currency_account_id_statement_id",
        )


def test_tc_db_09_concurrent_allocations_are_serialised(
    db_engine: Engine, settlement: Settlement, rows_class: "type[Rows]"
) -> None:
    """TC-DB-09 (READ COMMITTED): two sessions that each stay within the amount cannot
    together exceed it. Session 2 waits for session 1's allocation total (a real write
    conflict, R2-02), then sees the committed sum and fails at its check."""
    first, second = settlement.statement_ids
    workspace = settlement.account.workspace_id
    outcome: list[BaseException | None] = []

    with (
        db_engine.connect() as session_1,
        db_engine.connect() as session_2,
        db_engine.connect() as monitor,
    ):
        session_1.begin()
        rows_class(session_1).allocation(workspace, settlement.repayment_id, first, 70_000)
        session_1.execute(text("SET CONSTRAINTS ALL IMMEDIATE"))

        session_2.begin()
        pid_2 = session_2.execute(text("SELECT pg_backend_pid()")).scalar_one()

        def allocate_and_check_session_2() -> None:
            try:
                rows_class(session_2).allocation(workspace, settlement.repayment_id, second, 60_000)
                session_2.execute(text("SET CONSTRAINTS ALL IMMEDIATE"))
                outcome.append(None)
            except DBAPIError as exc:
                outcome.append(exc)

        waiter = threading.Thread(target=allocate_and_check_session_2, daemon=True)
        waiter.start()
        deadline = time.monotonic() + 30
        waiting = False
        while not waiting:
            assert time.monotonic() < deadline, "session 2 never waited for session 1"
            assert waiter.is_alive(), f"session 2 did not wait: {outcome}"
            waiting = bool(
                monitor.execute(
                    text("SELECT wait_event_type = 'Lock' FROM pg_stat_activity WHERE pid = :pid"),
                    {"pid": pid_2},
                ).scalar()
            )
            time.sleep(0.05)

        session_1.commit()
        waiter.join(timeout=30)
        assert not waiter.is_alive()
        session_2.rollback()

    assert len(outcome) == 1
    error = outcome[0]
    assert isinstance(error, DBAPIError)
    assert sqlstate_of(error) == (CHECK_VIOLATION, "repayment_allocations_within_amount")
    assert allocated(db_engine, settlement.repayment_id) == [70_000]


# --- other constraints required by the brief (T-005 §4d) ------------------------------


def test_statement_due_date_must_follow_statement_date(conn: Connection, rows: "Rows") -> None:
    account = rows.account()

    assert_rejected(
        conn,
        insert(T["statements"]).values(
            workspace_id=account.workspace_id,
            currency_account_id=account.currency_account_id,
            statement_date=date(2026, 11, 10),
            due_date=date(2026, 11, 10),
            status="predicted",
        ),
        CHECK_VIOLATION,
        "ck_statements_due_after_statement",
    )


def test_one_statement_per_currency_account_and_date(conn: Connection, rows: "Rows") -> None:
    account = rows.account()
    rows.statement(account, date(2026, 11, 10))

    assert_rejected(
        conn,
        insert(T["statements"]).values(
            workspace_id=account.workspace_id,
            currency_account_id=account.currency_account_id,
            statement_date=date(2026, 11, 10),
            due_date=date(2026, 12, 8),
            status="predicted",
        ),
        UNIQUE_VIOLATION,
        "uq_statements_currency_account_id_statement_date",
    )


def test_bank_confirmed_repayment_needs_bank_confirmed_at(conn: Connection, rows: "Rows") -> None:
    account = rows.account()
    values = {
        "workspace_id": account.workspace_id,
        "currency_account_id": account.currency_account_id,
        "amount_minor": 10_000,
        "currency": "CNY",
        "status": "bank_confirmed",
    }

    assert_rejected(
        conn,
        insert(T["repayments"]).values(**values),
        CHECK_VIOLATION,
        "ck_repayments_bank_confirmed_needs_timestamp",
    )
    # 0002 (R2-08): a recorded time needs the event's time zone.
    conn.execute(
        insert(T["repayments"]).values(**values, bank_confirmed_at=NOW, event_tz="Asia/Shanghai")
    )


def test_source_document_fingerprint_unique_per_workspace(conn: Connection, rows: "Rows") -> None:
    sha256 = "0" * 64

    def document(workspace_id: uuid.UUID) -> Executable:
        return insert(T["source_documents"]).values(
            workspace_id=workspace_id,
            sha256=sha256,
            mime="application/pdf",
            size_bytes=1024,
            storage_key=str(uuid.uuid4()),
            dek_wrapped=b"\x00" * 40,
        )

    workspace = rows.workspace()
    conn.execute(document(workspace))
    assert_rejected(
        conn, document(workspace), UNIQUE_VIOLATION, "uq_source_documents_workspace_id_sha256"
    )
    conn.execute(document(rows.workspace()))


def test_dedupe_key_primary_key(conn: Connection, rows: "Rows") -> None:
    workspace = rows.workspace()

    def key(entity_id: uuid.UUID) -> Executable:
        return insert(T["dedupe_keys"]).values(
            workspace_id=workspace,
            key_hash="b" * 64,
            entity_kind="transaction",
            entity_id=entity_id,
        )

    conn.execute(key(uuid.uuid4()))
    assert_rejected(conn, key(uuid.uuid4()), UNIQUE_VIOLATION, "pk_dedupe_keys")


def test_currencies_seed_matches_engine_minor_units(conn: Connection) -> None:
    """R2-31: the seed equals the engine's money.MINOR_DIGITS (imported, not copied)."""
    seeded = dict(
        conn.execute(select(T["currencies"].c.code, T["currencies"].c.minor_digits)).all()
    )

    assert seeded == MINOR_DIGITS


def test_installment_rounding_modes_match_the_engine(conn: Connection) -> None:
    """R2-31: ck_installment_plans_rounding allows exactly the engine's ROUNDING modes."""
    definition = conn.execute(
        text(
            "SELECT pg_get_constraintdef(oid) FROM pg_constraint "
            "WHERE conname = 'ck_installment_plans_rounding'"
        )
    ).scalar_one()

    assert set(re.findall(r"'([A-Z_]+)'::text", definition)) == set(ROUNDING)


def test_primary_keys_default_to_uuidv7(rows: "Rows") -> None:
    workspace = rows.workspace()

    assert workspace.version == 7


def test_one_live_primary_currency_account(conn: Connection, rows: "Rows") -> None:
    account = rows.account()
    table = T["currency_accounts"]
    conn.execute(
        update(table).where(table.c.id == account.currency_account_id).values(is_primary=True)
    )

    assert_rejected(
        conn,
        insert(table).values(
            workspace_id=account.workspace_id,
            credit_account_id=account.credit_account_id,
            currency="USD",
            is_primary=True,
        ),
        UNIQUE_VIOLATION,
        "uq_currency_accounts_one_primary",
    )


def test_running_job_needs_a_lease_and_heartbeat_counts_are_non_negative(
    conn: Connection,
) -> None:
    assert_rejected(
        conn,
        insert(T["jobs"]).values(kind="solve", payload={}, status="running"),
        CHECK_VIOLATION,
        "ck_jobs_running_has_lease",
    )
    conn.execute(
        insert(T["jobs"]).values(
            kind="solve", payload={}, status="running", locked_by="w1", locked_until=NOW
        )
    )
    assert_rejected(
        conn,
        insert(T["worker_heartbeats"]).values(
            worker_id="w1", hostname="h", pid=1, version="dev", running_jobs=-1
        ),
        CHECK_VIOLATION,
        "ck_worker_heartbeats_running_jobs_non_negative",
    )
