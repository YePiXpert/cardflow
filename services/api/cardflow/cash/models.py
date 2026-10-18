"""Cash accounts, balance snapshots, cash events, transfers, recurring items, scenarios.

Data-model §1 groups 5 (cash side) and 7 (scenarios, forecast runs). Cash amounts are
signed: negative ``amount_minor`` is an outflow (engine ``cash.CashEvent``). Each account
is checked on its own; a transfer is two events (out/in) plus a ``cash_transfers`` row.
``snapshot_included_events`` lists the same-day events a balance snapshot already
contains (R-CASH-06), all of the snapshot's own cash account (composite foreign key); its
rows go away with their snapshot (ON DELETE CASCADE, purge only). The amount, time and
account columns of ``cash_balance_snapshots`` are immutable (migration 0002).
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
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from cardflow.db.base import (
    CASH_EVENT_CATEGORIES,
    CASH_EVENT_CLASSES,
    CONFIRMATION_LEVELS,
    EMPTY_JSON_OBJECT,
    LIVE_ROWS,
    OPEN_SOURCES_COMMENT,
    Base,
    SyncColumns,
    minor,
    not_pan,
    now_default,
    uuid_pk,
)


class CashAccount(SyncColumns, Base):
    """Bank/wallet/wealth/restricted cash account with a reserve floor."""

    __tablename__ = "cash_accounts"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        UniqueConstraint("workspace_id", "id", "currency"),
        ForeignKeyConstraint(["workspace_id"], ["workspaces.id"]),
        ForeignKeyConstraint(["currency"], ["currencies.code"]),
        CheckConstraint("kind IN ('bank', 'wallet', 'wealth', 'restricted')", name="kind"),
        CheckConstraint("reserve_floor_minor >= 0", name="reserve_floor_non_negative"),
        not_pan("name"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    name: Mapped[str] = mapped_column()
    currency: Mapped[str] = mapped_column(CHAR(3))
    kind: Mapped[str] = mapped_column()
    usable_for_repayment: Mapped[bool] = mapped_column(server_default=text("true"))
    available_from: Mapped[date | None] = mapped_column()
    reserve_floor_minor: Mapped[int] = minor(default=0)


class CashBalanceSnapshot(SyncColumns, Base):
    """Observed balance of a cash account at the end of ``balance_as_of`` (minus exclusions)."""

    __tablename__ = "cash_balance_snapshots"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        UniqueConstraint("workspace_id", "cash_account_id", "id"),
        ForeignKeyConstraint(
            ["workspace_id", "cash_account_id"], ["cash_accounts.workspace_id", "cash_accounts.id"]
        ),
        CheckConstraint(f"confirmation_level IN {CONFIRMATION_LEVELS}", name="confirmation_level"),
        Index(
            "ix_cash_balance_snapshots_cash_account_id_balance_as_of",
            "cash_account_id",
            "balance_as_of",
        ),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    cash_account_id: Mapped[uuid.UUID] = mapped_column()
    balance_minor: Mapped[int] = minor()
    balance_as_of: Mapped[date] = mapped_column()
    observed_at: Mapped[datetime] = mapped_column()
    source_kind: Mapped[str] = mapped_column(comment=OPEN_SOURCES_COMMENT)
    confirmation_level: Mapped[str] = mapped_column()
    recorded_at: Mapped[datetime] = now_default()


class SnapshotIncludedEvent(SyncColumns, Base):
    """Same-day event (of the same cash account) already reflected in a snapshot."""

    __tablename__ = "snapshot_included_events"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(
            ["workspace_id", "cash_account_id", "snapshot_id"],
            [
                "cash_balance_snapshots.workspace_id",
                "cash_balance_snapshots.cash_account_id",
                "cash_balance_snapshots.id",
            ],
            ondelete="CASCADE",
        ),
        ForeignKeyConstraint(
            ["workspace_id", "cash_account_id", "cash_event_id"],
            ["cash_events.workspace_id", "cash_events.cash_account_id", "cash_events.id"],
        ),
        Index("ix_snapshot_included_events_cash_event_id", "cash_event_id"),
        Index(
            "uq_snapshot_included_events_snapshot_id_cash_event_id",
            "snapshot_id",
            "cash_event_id",
            unique=True,
            postgresql_where=LIVE_ROWS,
        ),
        Index("ix_snapshot_included_events_snapshot_id", "snapshot_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    snapshot_id: Mapped[uuid.UUID] = mapped_column()
    cash_event_id: Mapped[uuid.UUID] = mapped_column()
    cash_account_id: Mapped[uuid.UUID] = mapped_column(
        comment="Derived from snapshot_id by trigger; clients do not supply it."
    )


class CashEvent(SyncColumns, Base):
    """The single cash-fact table: confirmed / expected / planned inflows and outflows."""

    __tablename__ = "cash_events"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        UniqueConstraint("workspace_id", "cash_account_id", "id"),
        ForeignKeyConstraint(
            ["workspace_id", "cash_account_id"], ["cash_accounts.workspace_id", "cash_accounts.id"]
        ),
        ForeignKeyConstraint(
            ["workspace_id", "cash_account_id", "recurring_item_id"],
            [
                "recurring_items.workspace_id",
                "recurring_items.cash_account_id",
                "recurring_items.id",
            ],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "cash_account_id", "linked_repayment_id"],
            ["repayments.workspace_id", "repayments.cash_account_id", "repayments.id"],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "linked_plan_run_id"], ["plan_runs.workspace_id", "plan_runs.id"]
        ),
        CheckConstraint(f"cls IN {CASH_EVENT_CLASSES}", name="cls"),
        CheckConstraint(f"category IN {CASH_EVENT_CATEGORIES}", name="category"),
        CheckConstraint("posting_status IN ('planned', 'posted')", name="posting_status"),
        CheckConstraint("amount_minor <> 0", name="amount_nonzero"),
        CheckConstraint(
            "(category IN ('income', 'transfer_in') AND amount_minor > 0)"
            " OR (category IN ('bill', 'living', 'repayment', 'transfer_out', 'fee')"
            " AND amount_minor < 0)"
            " OR category = 'other'",
            name="amount_sign",
        ),
        CheckConstraint("event_at IS NULL OR event_tz IS NOT NULL", name="event_at_needs_tz"),
        not_pan("label"),
        Index(
            "ix_cash_events_cash_account_id_event_on",
            "cash_account_id",
            "event_on",
            postgresql_where=text("deleted_at IS NULL"),
        ),
        Index(
            "ix_cash_events_label_trgm",
            "label",
            postgresql_using="gin",
            postgresql_ops={"label": "gin_trgm_ops"},
        ),
        Index("ix_cash_events_recurring_item_id", "recurring_item_id"),
        Index("ix_cash_events_linked_repayment_id", "linked_repayment_id"),
        Index("ix_cash_events_linked_plan_run_id", "linked_plan_run_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    cash_account_id: Mapped[uuid.UUID] = mapped_column()
    event_on: Mapped[date] = mapped_column()
    event_at: Mapped[datetime | None] = mapped_column()
    amount_minor: Mapped[int] = mapped_column(
        BigInteger,
        comment=(
            "Minor units of the cash account's currency, never 0. Positive = inflow (income, "
            "transfer_in); negative = outflow (bill, living, repayment, transfer_out, fee); "
            "other: either sign."
        ),
    )
    cls: Mapped[str] = mapped_column()
    category: Mapped[str] = mapped_column()
    label: Mapped[str | None] = mapped_column()
    posting_status: Mapped[str] = mapped_column()
    recurring_item_id: Mapped[uuid.UUID | None] = mapped_column()
    linked_repayment_id: Mapped[uuid.UUID | None] = mapped_column()
    linked_plan_run_id: Mapped[uuid.UUID | None] = mapped_column()
    event_tz: Mapped[str | None] = mapped_column()
    recorded_at: Mapped[datetime] = now_default()


class CashTransfer(SyncColumns, Base):
    """Transfer between two cash accounts, represented by its out and in events."""

    __tablename__ = "cash_transfers"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(
            ["workspace_id", "from_cash_account_id", "currency"],
            ["cash_accounts.workspace_id", "cash_accounts.id", "cash_accounts.currency"],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "to_cash_account_id", "currency"],
            ["cash_accounts.workspace_id", "cash_accounts.id", "cash_accounts.currency"],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "from_cash_account_id", "out_event_id"],
            ["cash_events.workspace_id", "cash_events.cash_account_id", "cash_events.id"],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "to_cash_account_id", "in_event_id"],
            ["cash_events.workspace_id", "cash_events.cash_account_id", "cash_events.id"],
        ),
        ForeignKeyConstraint(["currency"], ["currencies.code"]),
        CheckConstraint("amount_minor > 0", name="amount_positive"),
        CheckConstraint("from_cash_account_id <> to_cash_account_id", name="distinct_accounts"),
        CheckConstraint("arrives_on IS NULL OR arrives_on >= sent_on", name="arrives_after_sent"),
        Index("ix_cash_transfers_from_cash_account_id", "from_cash_account_id"),
        Index("ix_cash_transfers_to_cash_account_id", "to_cash_account_id"),
        Index("ix_cash_transfers_out_event_id", "out_event_id"),
        Index("ix_cash_transfers_in_event_id", "in_event_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    from_cash_account_id: Mapped[uuid.UUID] = mapped_column()
    to_cash_account_id: Mapped[uuid.UUID] = mapped_column()
    amount_minor: Mapped[int] = minor()
    currency: Mapped[str] = mapped_column(CHAR(3))
    sent_on: Mapped[date] = mapped_column()
    arrives_on: Mapped[date | None] = mapped_column()
    out_event_id: Mapped[uuid.UUID | None] = mapped_column()
    in_event_id: Mapped[uuid.UUID | None] = mapped_column()


class RecurringItem(SyncColumns, Base):
    """Recurring income/expense that generates cash events (each overridable/skippable)."""

    __tablename__ = "recurring_items"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        UniqueConstraint("workspace_id", "cash_account_id", "id"),
        ForeignKeyConstraint(
            ["workspace_id", "cash_account_id"], ["cash_accounts.workspace_id", "cash_accounts.id"]
        ),
        CheckConstraint(f"category IN {CASH_EVENT_CATEGORIES}", name="category"),
        CheckConstraint(f"cls IN {CASH_EVENT_CLASSES}", name="cls"),
        CheckConstraint("ends_on IS NULL OR ends_on >= starts_on", name="ends_after_start"),
        CheckConstraint("amount_minor <> 0", name="amount_nonzero"),
        CheckConstraint(
            "(category IN ('income', 'transfer_in') AND amount_minor > 0)"
            " OR (category IN ('bill', 'living', 'repayment', 'transfer_out', 'fee')"
            " AND amount_minor < 0)"
            " OR category = 'other'",
            name="amount_sign",
        ),
        not_pan("label"),
        Index("ix_recurring_items_cash_account_id", "cash_account_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    cash_account_id: Mapped[uuid.UUID] = mapped_column()
    label: Mapped[str] = mapped_column()
    category: Mapped[str] = mapped_column()
    amount_minor: Mapped[int] = mapped_column(
        BigInteger,
        comment="Minor units per occurrence; same sign convention as cash_events.amount_minor.",
    )
    cls: Mapped[str] = mapped_column()
    recurrence: Mapped[Any] = mapped_column(JSONB)
    starts_on: Mapped[date] = mapped_column()
    ends_on: Mapped[date | None] = mapped_column()


class Scenario(SyncColumns, Base):
    """Cash scenario (engine ``Scenario``): ``code`` is the protocol id, e.g. ``baseline``."""

    __tablename__ = "scenarios"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(["workspace_id"], ["workspaces.id"]),
        CheckConstraint("income_scale >= 0", name="income_scale_non_negative"),
        CheckConstraint("expense_scale >= 0", name="expense_scale_non_negative"),
        CheckConstraint("same_day_order IN ('conservative', 'timestamp')", name="same_day_order"),
        not_pan("name"),
        not_pan("description"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    code: Mapped[str] = mapped_column()
    name: Mapped[str] = mapped_column()
    include_expected: Mapped[bool] = mapped_column(server_default=text("true"))
    income_delay_days: Mapped[int] = mapped_column(Integer, server_default=text("0"))
    income_scale: Mapped[Decimal] = mapped_column(server_default=text("1"))
    expense_scale: Mapped[Decimal] = mapped_column(server_default=text("1"))
    event_overrides: Mapped[Any] = mapped_column(JSONB, server_default=EMPTY_JSON_OBJECT)
    same_day_order: Mapped[str] = mapped_column(server_default=text("'conservative'"))
    description: Mapped[str | None] = mapped_column()


class ForecastRun(SyncColumns, Base):
    """Stored cash forecast (API-42) for history and scenario comparison."""

    __tablename__ = "forecast_runs"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(
            ["workspace_id", "scenario_id"], ["scenarios.workspace_id", "scenarios.id"]
        ),
        CheckConstraint("horizon_end >= horizon_start", name="horizon_order"),
        Index("ix_forecast_runs_scenario_id", "scenario_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    scenario_id: Mapped[uuid.UUID] = mapped_column()
    horizon_start: Mapped[date] = mapped_column()
    horizon_end: Mapped[date] = mapped_column()
    input_hash: Mapped[str] = mapped_column()
    model_version: Mapped[str] = mapped_column()
    protocol_version: Mapped[str | None] = mapped_column()
    computed_locally: Mapped[bool] = mapped_column(server_default=text("false"))
    result: Mapped[Any] = mapped_column(JSONB)
    created_at: Mapped[datetime] = now_default()
