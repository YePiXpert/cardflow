"""Plans, solver runs, allocations, verification checks, invalidations and reservations.

Data-model §1 group 7 plus ``plan_reservations`` (group 3). Not part of the pure engine
(:mod:`cardflow.planner.engine` must stay framework-free).

Run records (engine-spec §6/§11, API-52): ``plan_runs`` keeps the scalar run metadata as
columns and the complete engine outcome (allocation, verification, rejections,
sensitivity, assumptions, tiers, notes) in ``result`` JSONB. ``plan_runs`` has no
"pending" state: the worker inserts the row when a solve finishes, using the run_id that
API-51 pre-allocated and returned with the job id. History is never overwritten:
``plan_runs``, ``plan_allocations`` and ``plan_run_checks`` are immutable except for the
one-time tombstone and are deleted only under the purge token (migration 0002,
data-model §10.3). ``plan_allocations`` holds one live row per (run, card) (§10 decision
1); ``currency`` columns of runs, allocations and reservations are derived from the plan
by trigger and tie every account reference to the plan's currency.
"""

import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Any

from sqlalchemy import (
    CHAR,
    CheckConstraint,
    ForeignKeyConstraint,
    Index,
    Integer,
    Numeric,
    SmallInteger,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from cardflow.db.base import (
    EMPTY_JSON_ARRAY,
    EMPTY_JSON_OBJECT,
    LIVE_ROWS,
    NOW,
    Base,
    SyncColumns,
    minor,
    not_pan,
    now_default,
    uuid_pk,
)

PLAN_STATUSES = (
    "('draft', 'solving', 'solved', 'infeasible', 'unknown', 'needs_data', "
    "'baseline_shortfall', 'model_invalid', 'adopted', 'linked', 'stale', 'cancelled')"
)
SOLVER_STATUSES = "('OPTIMAL', 'FEASIBLE', 'INFEASIBLE', 'UNKNOWN', 'MODEL_INVALID', 'NOT_RUN')"
BUSINESS_STATUSES = (
    "('NEEDS_DATA', 'MODEL_INVALID', 'BASELINE_SHORTFALL', 'INFEASIBLE', 'UNKNOWN', "
    "'FEASIBLE_ROBUST', 'CONDITIONALLY_FEASIBLE')"
)


class Plan(SyncColumns, Base):
    """A planned spend (engine ``PlanRequest``); status follows PRD §6.5."""

    __tablename__ = "plans"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        UniqueConstraint("workspace_id", "id", "currency"),
        ForeignKeyConstraint(["workspace_id"], ["workspaces.id"]),
        ForeignKeyConstraint(["currency"], ["currencies.code"]),
        CheckConstraint("amount_minor > 0", name="amount_positive"),
        CheckConstraint("max_cards >= 1", name="max_cards_positive"),
        CheckConstraint("min_split_minor >= 1", name="min_split_positive"),
        CheckConstraint("payment_lead_days >= 0", name="payment_lead_days_non_negative"),
        CheckConstraint(f"status IN {PLAN_STATUSES}", name="status"),
        not_pan("merchant"),
        not_pan("category"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    amount_minor: Mapped[int] = minor()
    currency: Mapped[str] = mapped_column(CHAR(3))
    txn_date: Mapped[date] = mapped_column()
    allow_split: Mapped[bool] = mapped_column(server_default=text("false"))
    max_cards: Mapped[int] = mapped_column(SmallInteger, server_default=text("1"))
    min_split_minor: Mapped[int] = minor(default=1)
    payment_lead_days: Mapped[int] = mapped_column(SmallInteger, server_default=text("0"))
    channel: Mapped[str] = mapped_column()
    merchant: Mapped[str | None] = mapped_column()
    category: Mapped[str | None] = mapped_column()
    allow_installment: Mapped[bool] = mapped_column(server_default=text("false"))
    status: Mapped[str] = mapped_column()
    created_at: Mapped[datetime] = now_default()


class PlanRun(SyncColumns, Base):
    """One solver run (``id`` is the run_id); never updated after insert except tombstones."""

    __tablename__ = "plan_runs"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        UniqueConstraint("workspace_id", "id", "currency"),
        UniqueConstraint("workspace_id", "plan_id", "id"),
        ForeignKeyConstraint(
            ["workspace_id", "plan_id", "currency"],
            ["plans.workspace_id", "plans.id", "plans.currency"],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "decision_scenario_id"], ["scenarios.workspace_id", "scenarios.id"]
        ),
        CheckConstraint(
            "profile IN ('cash_safety', 'verified_benefit', 'fewer_cards')", name="profile"
        ),
        CheckConstraint(f"solver_status IN {SOLVER_STATUSES}", name="solver_status"),
        CheckConstraint(f"business_status IN {BUSINESS_STATUSES}", name="business_status"),
        CheckConstraint("time_limit_s > 0", name="time_limit_positive"),
        CheckConstraint("workers >= 1", name="workers_positive"),
        CheckConstraint("wall_time_s >= 0", name="wall_time_non_negative"),
        CheckConstraint("reserve_override_minor >= 0", name="reserve_override_non_negative"),
        Index("ix_plan_runs_plan_id_created_at", "plan_id", "created_at"),
        Index("ix_plan_runs_decision_scenario_id", "decision_scenario_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    plan_id: Mapped[uuid.UUID] = mapped_column()
    job_id: Mapped[uuid.UUID | None] = mapped_column()
    profile: Mapped[str] = mapped_column()
    decision_scenario_id: Mapped[uuid.UUID] = mapped_column()
    solver_status: Mapped[str] = mapped_column()
    business_status: Mapped[str] = mapped_column()
    input_hash: Mapped[str] = mapped_column()
    model_version: Mapped[str] = mapped_column()
    solver_version: Mapped[str] = mapped_column()
    protocol_version: Mapped[str] = mapped_column()
    time_limit_s: Mapped[Decimal] = mapped_column(Numeric(8, 3))
    workers: Mapped[int] = mapped_column(SmallInteger)
    seed: Mapped[int] = mapped_column(Integer)
    wall_time_s: Mapped[Decimal | None] = mapped_column(Numeric(10, 3))
    reserve_override_minor: Mapped[int | None] = minor()
    computed_locally: Mapped[bool] = mapped_column(server_default=text("false"))
    result: Mapped[Any] = mapped_column(JSONB)
    created_at: Mapped[datetime] = mapped_column(server_default=NOW)
    currency: Mapped[str] = mapped_column(
        CHAR(3), comment="Derived from plan_id by trigger; clients do not supply it."
    )


class PlanAllocation(SyncColumns, Base):
    """Allocation of a run to one card; one live row per (run, card) (decision 1)."""

    __tablename__ = "plan_allocations"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(
            ["workspace_id", "run_id", "currency"],
            ["plan_runs.workspace_id", "plan_runs.id", "plan_runs.currency"],
        ),
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
            ["workspace_id", "repay_from_cash_account_id", "currency"],
            ["cash_accounts.workspace_id", "cash_accounts.id", "cash_accounts.currency"],
        ),
        CheckConstraint("amount_minor > 0", name="amount_positive"),
        CheckConstraint("due_date > statement_date", name="due_after_statement"),
        CheckConstraint("fee_minor >= 0", name="fee_non_negative"),
        CheckConstraint("verified_benefit_minor >= 0", name="verified_benefit_non_negative"),
        CheckConstraint("potential_benefit_minor >= 0", name="potential_benefit_non_negative"),
        Index(
            "uq_plan_allocations_run_id_card_id",
            "run_id",
            "card_id",
            unique=True,
            postgresql_where=LIVE_ROWS,
        ),
        Index("ix_plan_allocations_run_id", "run_id"),
        Index("ix_plan_allocations_card_id", "card_id"),
        Index("ix_plan_allocations_currency_account_id", "currency_account_id"),
        Index("ix_plan_allocations_repay_from_cash_account_id", "repay_from_cash_account_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    run_id: Mapped[uuid.UUID] = mapped_column()
    currency_account_id: Mapped[uuid.UUID] = mapped_column()
    card_id: Mapped[uuid.UUID] = mapped_column()
    amount_minor: Mapped[int] = minor()
    statement_date: Mapped[date] = mapped_column()
    due_date: Mapped[date] = mapped_column()
    repay_on: Mapped[date] = mapped_column()
    repay_from_cash_account_id: Mapped[uuid.UUID] = mapped_column()
    buffer_days: Mapped[int] = mapped_column(Integer)
    fee_minor: Mapped[int] = minor(default=0)
    verified_benefit_minor: Mapped[int] = minor(default=0)
    potential_benefit_minor: Mapped[int] = minor(default=0)
    cycle_assumptions: Mapped[Any] = mapped_column(JSONB, server_default=EMPTY_JSON_ARRAY)
    alternative_cycles: Mapped[Any] = mapped_column(JSONB, server_default=EMPTY_JSON_ARRAY)
    currency: Mapped[str] = mapped_column(
        CHAR(3), comment="Derived from run_id by trigger; clients do not supply it."
    )
    credit_account_id: Mapped[uuid.UUID] = mapped_column(
        comment="Derived from currency_account_id by trigger; clients do not supply it."
    )


class PlanRunCheck(SyncColumns, Base):
    """Independent-verifier result of a run for one scenario (engine ``ScenarioCheck``)."""

    __tablename__ = "plan_run_checks"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(
            ["workspace_id", "run_id"], ["plan_runs.workspace_id", "plan_runs.id"]
        ),
        ForeignKeyConstraint(
            ["workspace_id", "scenario_id"], ["scenarios.workspace_id", "scenarios.id"]
        ),
        Index(
            "uq_plan_run_checks_run_id_scenario_id",
            "run_id",
            "scenario_id",
            unique=True,
            postgresql_where=LIVE_ROWS,
        ),
        Index("ix_plan_run_checks_run_id", "run_id"),
        Index("ix_plan_run_checks_scenario_id", "scenario_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    run_id: Mapped[uuid.UUID] = mapped_column()
    scenario_id: Mapped[uuid.UUID] = mapped_column()
    ok: Mapped[bool] = mapped_column()
    ok_zero: Mapped[bool] = mapped_column()
    min_balance_by_account: Mapped[Any] = mapped_column(JSONB)
    min_on_by_account: Mapped[Any] = mapped_column(JSONB, server_default=EMPTY_JSON_OBJECT)
    breaches: Mapped[Any] = mapped_column(JSONB, server_default=EMPTY_JSON_ARRAY)
    assumptions: Mapped[Any] = mapped_column(JSONB, server_default=EMPTY_JSON_ARRAY)


class PlanInvalidation(SyncColumns, Base):
    """Why and when a plan (or one run) became stale (R-PLAN-07)."""

    __tablename__ = "plan_invalidations"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(["workspace_id", "plan_id"], ["plans.workspace_id", "plans.id"]),
        ForeignKeyConstraint(
            ["workspace_id", "plan_id", "run_id"],
            ["plan_runs.workspace_id", "plan_runs.plan_id", "plan_runs.id"],
        ),
        Index("ix_plan_invalidations_plan_id", "plan_id"),
        Index("ix_plan_invalidations_run_id", "run_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    plan_id: Mapped[uuid.UUID] = mapped_column()
    run_id: Mapped[uuid.UUID | None] = mapped_column()
    cause: Mapped[str] = mapped_column(
        comment=(
            "Open set (snapshot_changed, cash_event_changed, rule_changed, manual ...); no CHECK "
            "by design."
        )
    )
    caused_by_table: Mapped[str | None] = mapped_column()
    caused_by_id: Mapped[uuid.UUID | None] = mapped_column()
    invalidated_at: Mapped[datetime] = now_default()


class PlanReservation(SyncColumns, Base):
    """Limit/cash reserved by an adopted plan until the real transaction converts it."""

    __tablename__ = "plan_reservations"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(
            ["workspace_id", "plan_id", "currency"],
            ["plans.workspace_id", "plans.id", "plans.currency"],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "plan_id", "run_id"],
            ["plan_runs.workspace_id", "plan_runs.plan_id", "plan_runs.id"],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "currency_account_id", "currency"],
            [
                "currency_accounts.workspace_id",
                "currency_accounts.id",
                "currency_accounts.currency",
            ],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "cash_account_id", "currency"],
            ["cash_accounts.workspace_id", "cash_accounts.id", "cash_accounts.currency"],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "currency_account_id", "linked_transaction_id"],
            [
                "transactions.workspace_id",
                "transactions.currency_account_id",
                "transactions.id",
            ],
        ),
        CheckConstraint("amount_minor > 0", name="amount_positive"),
        CheckConstraint("status IN ('active', 'converted', 'released')", name="status"),
        CheckConstraint(
            "status <> 'converted' OR linked_transaction_id IS NOT NULL",
            name="converted_needs_transaction",
        ),
        Index("ix_plan_reservations_plan_id", "plan_id"),
        Index("ix_plan_reservations_currency_account_id", "currency_account_id"),
        Index("ix_plan_reservations_run_id", "run_id"),
        Index("ix_plan_reservations_cash_account_id", "cash_account_id"),
        Index("ix_plan_reservations_linked_transaction_id", "linked_transaction_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    plan_id: Mapped[uuid.UUID] = mapped_column()
    run_id: Mapped[uuid.UUID | None] = mapped_column()
    currency_account_id: Mapped[uuid.UUID] = mapped_column()
    cash_account_id: Mapped[uuid.UUID | None] = mapped_column()
    amount_minor: Mapped[int] = minor()
    status: Mapped[str] = mapped_column()
    linked_transaction_id: Mapped[uuid.UUID | None] = mapped_column()
    created_at: Mapped[datetime] = now_default()
    currency: Mapped[str] = mapped_column(
        CHAR(3), comment="Derived from plan_id by trigger; clients do not supply it."
    )
