"""Transactions, statements and versions, installments, charges, repayments, reconciliation.

Data-model §1 groups 4 and 5 (repayment side). Database-enforced rules (migrations 0001
and 0002, data-model §10):

* ``statement_versions`` and ``statement_lines`` are immutable: the only UPDATE allowed is
  the one-time tombstone (``deleted_at`` NULL -> NOT NULL; triggers ``*_immutable``). A
  correction is a new version; ``(statement_id, version_no)`` is never reused. Lines can
  only be written in the transaction that created their version. Rows are deleted only
  by a workspace purge holding the transaction-scoped token
  ``SELECT set_config('app.purge', pg_current_xact_id()::text, true)`` (triggers
  ``*_no_delete`` / ``*_no_truncate``).
* ``statements.current_version_id`` must be one of the statement's own versions
  (deferred composite foreign key).
* Currency and account consistency are composite foreign keys: a transaction's card
  belongs to its credit account, a version/line/attribution/allocation stays on its
  statement's currency account, ``currency`` matches the account. The redundant account
  columns (``transactions.credit_account_id``, ``statement_versions.currency_account_id``,
  ...) are derived from the parent row by trigger; clients do not supply them.
* ``repayment_allocations``: at COMMIT, the live allocations of a repayment sum to at most
  ``repayments.amount_minor`` and to zero for a deleted, reversed or failed repayment. The
  check writes the repayment's :class:`RepaymentAllocationTotal` row, so concurrent
  allocators conflict in every isolation level (deferred constraint triggers; an
  intermediate over-allocation inside the transaction is fine).
* Natural keys (statement date, allocation, attribution, links, schedule periods) are
  unique among live rows only (``WHERE deleted_at IS NULL``): tombstoned rows can be
  recreated.
* ``repayments`` in status ``bank_confirmed`` must carry ``bank_confirmed_at``; any recorded
  time needs ``event_tz``. Amount signs per type are CHECKed and documented as column
  comments. ``row_version`` / ``updated_at`` are maintained by trigger.
"""

import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Any

from sqlalchemy import (
    CHAR,
    BigInteger,
    CheckConstraint,
    ForeignKeyConstraint,
    Index,
    Integer,
    SmallInteger,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from cardflow.db.base import (
    CONFIRMATION_LEVELS,
    EMPTY_JSON_OBJECT,
    LIVE_ROWS,
    OPEN_SOURCES_COMMENT,
    TIME_PRECISIONS,
    Base,
    SyncColumns,
    minor,
    not_pan,
    now_default,
    uuid_pk,
)

TXN_TYPES = (
    "('purchase', 'refund', 'reversal', 'cash_advance', 'fee', 'interest', 'repayment', "
    "'transfer', 'preauth', 'installment_principal', 'adjustment')"
)
REPAYMENT_STATUSES = (
    "('recorded', 'processing', 'cash_debited', 'credit_posted', 'bank_confirmed', 'failed', "
    "'user_marked_paid', 'needs_review', 'reversed')"
)
TRANSACTION_AMOUNT_COMMENT = (
    "Minor units of the currency account's currency, never 0. Positive = liability "
    "increase (purchase, cash_advance, fee, interest, installment_principal); negative = "
    "credit (refund, reversal, repayment); adjustment, transfer, preauth: either sign."
)
STATUS_INSTALLMENT_PLAN = "('active', 'completed', 'early_settled', 'cancelled')"
STATUS_INSTALLMENT_PERIOD = "('scheduled', 'billed', 'settled', 'cancelled')"
RECONCILIATION_KINDS = (
    "('amount_mismatch', 'missing', 'duplicate_txn', 'duplicate_repayment', 'refund_pending', "
    "'unmatched_repayment', 'sync_conflict')"
)


class Transaction(SyncColumns, Base):
    """Card transaction; ``amount_minor`` > 0 increases the liability, credits are < 0."""

    __tablename__ = "transactions"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        UniqueConstraint("workspace_id", "currency_account_id", "id"),
        ForeignKeyConstraint(
            ["workspace_id", "currency_account_id", "currency"],
            [
                "currency_accounts.workspace_id",
                "currency_accounts.id",
                "currency_accounts.currency",
            ],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "credit_account_id", "currency_account_id"],
            [
                "currency_accounts.workspace_id",
                "currency_accounts.credit_account_id",
                "currency_accounts.id",
            ],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "credit_account_id", "card_id"],
            ["cards.workspace_id", "cards.credit_account_id", "cards.id"],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "parent_transaction_id"],
            ["transactions.workspace_id", "transactions.id"],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "source_document_id"],
            ["source_documents.workspace_id", "source_documents.id"],
        ),
        ForeignKeyConstraint(["currency"], ["currencies.code"]),
        CheckConstraint(f"txn_type IN {TXN_TYPES}", name="txn_type"),
        CheckConstraint(f"time_precision IN {TIME_PRECISIONS}", name="time_precision"),
        CheckConstraint("status IN ('pending', 'posted', 'reversed')", name="status"),
        CheckConstraint("mcc ~ '^[0-9]{4}$'", name="mcc_digits"),
        CheckConstraint(f"confirmation_level IN {CONFIRMATION_LEVELS}", name="confirmation_level"),
        CheckConstraint(
            "parent_transaction_id IS NULL OR parent_transaction_id <> id", name="not_own_parent"
        ),
        CheckConstraint("amount_minor <> 0", name="amount_nonzero"),
        CheckConstraint(
            "(txn_type IN ('purchase', 'cash_advance', 'fee', 'interest', "
            "'installment_principal') AND amount_minor > 0)"
            " OR (txn_type IN ('refund', 'reversal', 'repayment') AND amount_minor < 0)"
            " OR txn_type IN ('adjustment', 'transfer', 'preauth')",
            name="amount_sign",
        ),
        not_pan("merchant"),
        not_pan("category"),
        Index("ix_transactions_currency_account_id_posted_on", "currency_account_id", "posted_on"),
        Index("ix_transactions_workspace_id_fingerprint", "workspace_id", "fingerprint"),
        Index(
            "ix_transactions_merchant_trgm",
            "merchant",
            postgresql_using="gin",
            postgresql_ops={"merchant": "gin_trgm_ops"},
        ),
        Index("ix_transactions_card_id", "card_id"),
        Index("ix_transactions_parent_transaction_id", "parent_transaction_id"),
        Index("ix_transactions_source_document_id", "source_document_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    currency_account_id: Mapped[uuid.UUID] = mapped_column()
    card_id: Mapped[uuid.UUID | None] = mapped_column()
    txn_type: Mapped[str] = mapped_column()
    amount_minor: Mapped[int] = mapped_column(BigInteger, comment=TRANSACTION_AMOUNT_COMMENT)
    currency: Mapped[str] = mapped_column(CHAR(3))
    txn_at: Mapped[datetime] = mapped_column()
    txn_tz: Mapped[str] = mapped_column()
    time_precision: Mapped[str] = mapped_column()
    posted_on: Mapped[date | None] = mapped_column()
    merchant: Mapped[str | None] = mapped_column()
    mcc: Mapped[str | None] = mapped_column(CHAR(4))
    category: Mapped[str | None] = mapped_column()
    status: Mapped[str] = mapped_column()
    bank_reference: Mapped[str | None] = mapped_column()
    parent_transaction_id: Mapped[uuid.UUID | None] = mapped_column()
    fingerprint: Mapped[str] = mapped_column()
    source_kind: Mapped[str] = mapped_column(comment=OPEN_SOURCES_COMMENT)
    source_document_id: Mapped[uuid.UUID | None] = mapped_column()
    confirmation_level: Mapped[str] = mapped_column()
    recorded_at: Mapped[datetime] = now_default()
    credit_account_id: Mapped[uuid.UUID] = mapped_column(
        comment="Derived from currency_account_id by trigger; clients do not supply it."
    )
    observed_at: Mapped[datetime | None] = mapped_column()


class TransactionLink(SyncColumns, Base):
    """Typed link between two transactions (pre-auth capture, refund, duplicate, ...)."""

    __tablename__ = "transaction_links"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(
            ["workspace_id", "from_transaction_id"],
            ["transactions.workspace_id", "transactions.id"],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "to_transaction_id"],
            ["transactions.workspace_id", "transactions.id"],
        ),
        CheckConstraint("from_transaction_id <> to_transaction_id", name="distinct_transactions"),
        CheckConstraint(f"confirmation_level IN {CONFIRMATION_LEVELS}", name="confirmation_level"),
        Index("ix_transaction_links_to_transaction_id", "to_transaction_id"),
        Index(
            "uq_transaction_links_from_transaction_id_to_transaction_id_kind",
            "from_transaction_id",
            "to_transaction_id",
            "kind",
            unique=True,
            postgresql_where=LIVE_ROWS,
        ),
        Index("ix_transaction_links_from_transaction_id", "from_transaction_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    from_transaction_id: Mapped[uuid.UUID] = mapped_column()
    to_transaction_id: Mapped[uuid.UUID] = mapped_column()
    kind: Mapped[str] = mapped_column(
        comment=(
            "Open set (preauth_capture, refund_of, reversal_of, duplicate_of ...); no CHECK by "
            "design."
        )
    )
    confirmation_level: Mapped[str] = mapped_column()
    recorded_at: Mapped[datetime] = now_default()


class Statement(SyncColumns, Base):
    """Statement of a currency account for one statement date (PRD §6.2 status)."""

    __tablename__ = "statements"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        UniqueConstraint("workspace_id", "currency_account_id", "id"),
        ForeignKeyConstraint(
            ["workspace_id", "currency_account_id"],
            ["currency_accounts.workspace_id", "currency_accounts.id"],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "id", "current_version_id"],
            [
                "statement_versions.workspace_id",
                "statement_versions.statement_id",
                "statement_versions.id",
            ],
            deferrable=True,
            initially="DEFERRED",
            use_alter=True,
        ),
        CheckConstraint("due_date > statement_date", name="due_after_statement"),
        CheckConstraint(
            "status IN ('predicted', 'issued', 'amended', 'partially_settled', 'settled', "
            "'overdue')",
            name="status",
        ),
        Index(
            "uq_statements_currency_account_id_statement_date",
            "currency_account_id",
            "statement_date",
            unique=True,
            postgresql_where=LIVE_ROWS,
        ),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    currency_account_id: Mapped[uuid.UUID] = mapped_column()
    statement_date: Mapped[date] = mapped_column()
    due_date: Mapped[date] = mapped_column()
    status: Mapped[str] = mapped_column()
    current_version_id: Mapped[uuid.UUID | None] = mapped_column()


class StatementVersion(SyncColumns, Base):
    """Append-only bank original (or correction) of a statement; see module docstring."""

    __tablename__ = "statement_versions"
    __table_args__ = (
        UniqueConstraint("statement_id", "version_no"),
        UniqueConstraint("workspace_id", "id"),
        UniqueConstraint("workspace_id", "statement_id", "id"),
        UniqueConstraint("workspace_id", "id", "currency_account_id"),
        ForeignKeyConstraint(
            ["workspace_id", "statement_id", "currency_account_id"],
            ["statements.workspace_id", "statements.id", "statements.currency_account_id"],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "source_document_id"],
            ["source_documents.workspace_id", "source_documents.id"],
        ),
        CheckConstraint(
            "source_kind IN ('pdf', 'email', 'screenshot', 'csv', 'manual', 'correction')",
            name="source_kind",
        ),
        CheckConstraint("version_no >= 1", name="version_no_positive"),
        not_pan("reason"),
        Index("ix_statement_versions_source_document_id", "source_document_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    statement_id: Mapped[uuid.UUID] = mapped_column()
    version_no: Mapped[int] = mapped_column(Integer)
    source_kind: Mapped[str] = mapped_column()
    source_document_id: Mapped[uuid.UUID | None] = mapped_column()
    previous_balance_minor: Mapped[int | None] = minor()
    new_balance_minor: Mapped[int] = minor()
    min_due_minor: Mapped[int | None] = minor()
    payments_minor: Mapped[int | None] = minor()
    credits_minor: Mapped[int | None] = minor()
    fees_minor: Mapped[int | None] = minor()
    interest_minor: Mapped[int | None] = minor()
    installment_due_minor: Mapped[int | None] = minor()
    credit_balance_minor: Mapped[int | None] = minor()
    due_date: Mapped[date] = mapped_column()
    recorded_by: Mapped[str] = mapped_column()
    reason: Mapped[str | None] = mapped_column()
    recorded_at: Mapped[datetime] = now_default()
    currency_account_id: Mapped[uuid.UUID] = mapped_column(
        comment="Derived from statement_id by trigger; clients do not supply it."
    )


class StatementLine(SyncColumns, Base):
    """Itemised line of a statement version, optionally matched to a transaction."""

    __tablename__ = "statement_lines"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        UniqueConstraint("statement_version_id", "line_no"),
        ForeignKeyConstraint(
            ["workspace_id", "statement_version_id", "currency_account_id"],
            [
                "statement_versions.workspace_id",
                "statement_versions.id",
                "statement_versions.currency_account_id",
            ],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "currency_account_id", "transaction_id"],
            [
                "transactions.workspace_id",
                "transactions.currency_account_id",
                "transactions.id",
            ],
        ),
        CheckConstraint("line_no >= 1", name="line_no_positive"),
        CheckConstraint("card_last4 ~ '^[0-9]{4}$'", name="card_last4_digits"),
        not_pan("description"),
        Index("ix_statement_lines_transaction_id", "transaction_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    statement_version_id: Mapped[uuid.UUID] = mapped_column()
    line_no: Mapped[int] = mapped_column(Integer)
    kind: Mapped[str] = mapped_column(
        comment=(
            "Open set of statement line kinds (purchase, refund, fee, interest, installment, "
            "repayment, adjustment, info ...); no CHECK by design."
        )
    )
    description: Mapped[str | None] = mapped_column()
    txn_on: Mapped[date | None] = mapped_column()
    posted_on: Mapped[date | None] = mapped_column()
    amount_minor: Mapped[int] = mapped_column(
        BigInteger,
        comment=(
            "Minor units; same convention as transactions.amount_minor (positive = liability "
            "increase, negative = credit). Informational lines may carry any sign."
        ),
    )
    card_last4: Mapped[str | None] = mapped_column(CHAR(4))
    transaction_id: Mapped[uuid.UUID | None] = mapped_column()
    recorded_at: Mapped[datetime] = now_default()
    currency_account_id: Mapped[uuid.UUID] = mapped_column(
        comment="Derived from statement_version_id by trigger; clients do not supply it."
    )


class StatementAttribution(SyncColumns, Base):
    """Which statement a transaction is (predicted or confirmed to be) billed on."""

    __tablename__ = "statement_attributions"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(
            ["workspace_id", "currency_account_id", "transaction_id"],
            [
                "transactions.workspace_id",
                "transactions.currency_account_id",
                "transactions.id",
            ],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "currency_account_id", "statement_id"],
            ["statements.workspace_id", "statements.currency_account_id", "statements.id"],
        ),
        CheckConstraint(f"confirmation_level IN {CONFIRMATION_LEVELS}", name="confirmation_level"),
        Index("ix_statement_attributions_statement_id", "statement_id"),
        Index(
            "uq_statement_attributions_transaction_id_statement_id",
            "transaction_id",
            "statement_id",
            unique=True,
            postgresql_where=LIVE_ROWS,
        ),
        Index("ix_statement_attributions_transaction_id", "transaction_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    transaction_id: Mapped[uuid.UUID] = mapped_column()
    statement_id: Mapped[uuid.UUID] = mapped_column()
    confirmation_level: Mapped[str] = mapped_column()
    recorded_at: Mapped[datetime] = now_default()
    currency_account_id: Mapped[uuid.UUID] = mapped_column(
        comment="Derived from transaction_id by trigger; clients do not supply it."
    )


class InstallmentPlan(SyncColumns, Base):
    """Installment conversion of a transaction (rounding/remainder are explicit fields)."""

    __tablename__ = "installment_plans"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(
            ["workspace_id", "transaction_id"], ["transactions.workspace_id", "transactions.id"]
        ),
        CheckConstraint("principal_minor > 0", name="principal_positive"),
        CheckConstraint("periods >= 1", name="periods_positive"),
        CheckConstraint("per_period_rate >= 0", name="rate_non_negative"),
        CheckConstraint("fee_mode IN ('per_period', 'upfront')", name="fee_mode"),
        CheckConstraint("remainder_policy IN ('last', 'first')", name="remainder_policy"),
        CheckConstraint("rounding IN ('HALF_UP', 'DOWN', 'HALF_EVEN', 'UP')", name="rounding"),
        CheckConstraint(f"status IN {STATUS_INSTALLMENT_PLAN}", name="status"),
        Index(
            "uq_installment_plans_transaction_id",
            "transaction_id",
            unique=True,
            postgresql_where=text("deleted_at IS NULL"),
        ),
        Index("ix_installment_plans_transaction_id", "transaction_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    transaction_id: Mapped[uuid.UUID] = mapped_column()
    principal_minor: Mapped[int] = minor()
    periods: Mapped[int] = mapped_column(SmallInteger)
    per_period_rate: Mapped[Decimal] = mapped_column()
    fee_mode: Mapped[str] = mapped_column()
    remainder_policy: Mapped[str] = mapped_column(server_default=text("'last'"))
    rounding: Mapped[str] = mapped_column(server_default=text("'HALF_UP'"))
    status: Mapped[str] = mapped_column()
    early_settled_at: Mapped[datetime | None] = mapped_column()


class InstallmentSchedule(SyncColumns, Base):
    """One period of an installment plan (``plan_id`` -> ``installment_plans``)."""

    __tablename__ = "installment_schedule"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(
            ["workspace_id", "plan_id"], ["installment_plans.workspace_id", "installment_plans.id"]
        ),
        CheckConstraint("period_no >= 1", name="period_no_positive"),
        CheckConstraint("principal_minor >= 0", name="principal_non_negative"),
        CheckConstraint("interest_minor >= 0", name="interest_non_negative"),
        CheckConstraint("due_date > statement_date", name="due_after_statement"),
        CheckConstraint(f"status IN {STATUS_INSTALLMENT_PERIOD}", name="status"),
        Index(
            "uq_installment_schedule_plan_id_period_no",
            "plan_id",
            "period_no",
            unique=True,
            postgresql_where=LIVE_ROWS,
        ),
        Index("ix_installment_schedule_plan_id", "plan_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    plan_id: Mapped[uuid.UUID] = mapped_column()
    period_no: Mapped[int] = mapped_column(SmallInteger)
    principal_minor: Mapped[int] = minor()
    interest_minor: Mapped[int] = minor(default=0)
    statement_date: Mapped[date] = mapped_column()
    due_date: Mapped[date] = mapped_column()
    status: Mapped[str] = mapped_column()


class Charge(SyncColumns, Base):
    """Fee or interest (estimated or bank-confirmed) on a currency account."""

    __tablename__ = "charges"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(
            ["workspace_id", "currency_account_id", "currency"],
            [
                "currency_accounts.workspace_id",
                "currency_accounts.id",
                "currency_accounts.currency",
            ],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "currency_account_id", "statement_id"],
            ["statements.workspace_id", "statements.currency_account_id", "statements.id"],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "currency_account_id", "transaction_id"],
            [
                "transactions.workspace_id",
                "transactions.currency_account_id",
                "transactions.id",
            ],
        ),
        ForeignKeyConstraint(["currency"], ["currencies.code"]),
        CheckConstraint(f"confirmation_level IN {CONFIRMATION_LEVELS}", name="confirmation_level"),
        CheckConstraint("amount_minor <> 0", name="amount_nonzero"),
        Index("ix_charges_currency_account_id", "currency_account_id"),
        Index("ix_charges_statement_id", "statement_id"),
        Index("ix_charges_transaction_id", "transaction_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    currency_account_id: Mapped[uuid.UUID] = mapped_column()
    statement_id: Mapped[uuid.UUID | None] = mapped_column()
    transaction_id: Mapped[uuid.UUID | None] = mapped_column()
    kind: Mapped[str] = mapped_column(
        comment=(
            "Open set (annual_fee, cash_advance_fee, fx_fee, interest, late_fee, "
            "installment_fee, other ...); no CHECK by design."
        )
    )
    amount_minor: Mapped[int] = mapped_column(
        BigInteger,
        comment=(
            "Minor units, never 0. Positive = fee or interest charged; negative = waiver or "
            "refund of a charge."
        ),
    )
    currency: Mapped[str] = mapped_column(CHAR(3))
    charged_on: Mapped[date] = mapped_column()
    details: Mapped[Any] = mapped_column(JSONB, server_default=EMPTY_JSON_OBJECT)
    source_kind: Mapped[str] = mapped_column(comment=OPEN_SOURCES_COMMENT)
    confirmation_level: Mapped[str] = mapped_column()
    recorded_at: Mapped[datetime] = now_default()


class Repayment(SyncColumns, Base):
    """Repayment of a currency account from a cash account (PRD §6.3 status)."""

    __tablename__ = "repayments"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        UniqueConstraint("workspace_id", "currency_account_id", "id"),
        UniqueConstraint("workspace_id", "cash_account_id", "id"),
        ForeignKeyConstraint(
            ["workspace_id", "currency_account_id", "currency"],
            [
                "currency_accounts.workspace_id",
                "currency_accounts.id",
                "currency_accounts.currency",
            ],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "cash_account_id"], ["cash_accounts.workspace_id", "cash_accounts.id"]
        ),
        ForeignKeyConstraint(
            ["workspace_id", "evidence_document_id"],
            ["source_documents.workspace_id", "source_documents.id"],
        ),
        ForeignKeyConstraint(["currency"], ["currencies.code"]),
        CheckConstraint("amount_minor > 0", name="amount_positive"),
        CheckConstraint(f"status IN {REPAYMENT_STATUSES}", name="status"),
        CheckConstraint(
            "status <> 'bank_confirmed' OR bank_confirmed_at IS NOT NULL",
            name="bank_confirmed_needs_timestamp",
        ),
        CheckConstraint(
            f"cash_debited_precision IN {TIME_PRECISIONS}", name="cash_debited_precision"
        ),
        CheckConstraint(
            f"credit_posted_precision IN {TIME_PRECISIONS}", name="credit_posted_precision"
        ),
        CheckConstraint(
            "(cash_debited_at IS NULL) = (cash_debited_precision IS NULL)",
            name="cash_debited_precision_pair",
        ),
        CheckConstraint(
            "(credit_posted_at IS NULL) = (credit_posted_precision IS NULL)",
            name="credit_posted_precision_pair",
        ),
        CheckConstraint(
            "event_tz IS NOT NULL OR (payment_initiated_at IS NULL AND cash_debited_at IS NULL"
            " AND credit_posted_at IS NULL AND bank_confirmed_at IS NULL)",
            name="times_need_tz",
        ),
        Index("ix_repayments_currency_account_id", "currency_account_id"),
        Index("ix_repayments_cash_account_id", "cash_account_id"),
        Index("ix_repayments_evidence_document_id", "evidence_document_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    currency_account_id: Mapped[uuid.UUID] = mapped_column()
    cash_account_id: Mapped[uuid.UUID | None] = mapped_column()
    amount_minor: Mapped[int] = minor()
    currency: Mapped[str] = mapped_column(CHAR(3))
    status: Mapped[str] = mapped_column()
    method: Mapped[str | None] = mapped_column()
    payment_initiated_at: Mapped[datetime | None] = mapped_column()
    cash_debited_at: Mapped[datetime | None] = mapped_column()
    credit_posted_at: Mapped[datetime | None] = mapped_column()
    bank_confirmed_at: Mapped[datetime | None] = mapped_column()
    evidence_document_id: Mapped[uuid.UUID | None] = mapped_column()
    event_tz: Mapped[str | None] = mapped_column()
    cash_debited_precision: Mapped[str | None] = mapped_column()
    credit_posted_precision: Mapped[str | None] = mapped_column()
    recorded_at: Mapped[datetime] = now_default()


class RepaymentAllocation(SyncColumns, Base):
    """Part of a repayment applied to one statement of the same currency account.

    One live row per (repayment, statement); the running sum lives in
    :class:`RepaymentAllocationTotal`, maintained by trigger.
    """

    __tablename__ = "repayment_allocations"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(
            ["workspace_id", "currency_account_id", "repayment_id"],
            ["repayments.workspace_id", "repayments.currency_account_id", "repayments.id"],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "currency_account_id", "statement_id"],
            ["statements.workspace_id", "statements.currency_account_id", "statements.id"],
        ),
        CheckConstraint("amount_minor > 0", name="amount_positive"),
        Index("ix_repayment_allocations_statement_id", "statement_id"),
        Index(
            "uq_repayment_allocations_repayment_id_statement_id",
            "repayment_id",
            "statement_id",
            unique=True,
            postgresql_where=LIVE_ROWS,
        ),
        Index("ix_repayment_allocations_repayment_id", "repayment_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    repayment_id: Mapped[uuid.UUID] = mapped_column()
    statement_id: Mapped[uuid.UUID] = mapped_column()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    amount_minor: Mapped[int] = minor()
    currency_account_id: Mapped[uuid.UUID] = mapped_column(
        comment="Derived from repayment_id by trigger; clients do not supply it."
    )


class RepaymentAllocationTotal(Base):
    """Sum of the live allocations of one repayment (trigger-maintained, never synced).

    Writes to this row make concurrent allocators conflict in every isolation level, which
    is what keeps the deferred "allocations <= amount" check correct (R2-02).
    """

    __tablename__ = "repayment_allocation_totals"
    __table_args__ = (
        ForeignKeyConstraint(
            ["workspace_id", "repayment_id"],
            ["repayments.workspace_id", "repayments.id"],
            ondelete="CASCADE",
        ),
        CheckConstraint("allocated_minor >= 0", name="allocated_non_negative"),
    )

    repayment_id: Mapped[uuid.UUID] = mapped_column(primary_key=True)
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    allocated_minor: Mapped[int] = minor(default=0)


class ReconciliationItem(SyncColumns, Base):
    """Open reconciliation difference with source, suggested action and resolution."""

    __tablename__ = "reconciliation_items"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(["workspace_id"], ["workspaces.id"]),
        CheckConstraint(f"kind IN {RECONCILIATION_KINDS}", name="kind"),
        CheckConstraint("status IN ('open', 'resolved', 'dismissed')", name="status"),
        not_pan("suggested_action"),
        not_pan("resolution"),
        Index("ix_reconciliation_items_workspace_id_status", "workspace_id", "status"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    kind: Mapped[str] = mapped_column()
    refs: Mapped[Any] = mapped_column(JSONB)
    status: Mapped[str] = mapped_column()
    source_kind: Mapped[str | None] = mapped_column(comment=OPEN_SOURCES_COMMENT)
    suggested_action: Mapped[str | None] = mapped_column()
    resolution: Mapped[str | None] = mapped_column()
    resolved_by: Mapped[str | None] = mapped_column()
    resolved_at: Mapped[datetime | None] = mapped_column()
    created_at: Mapped[datetime] = now_default()
