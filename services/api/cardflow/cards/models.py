"""Banks, products, credit accounts, currency sub-accounts, cards, billing rules and limits.

Data-model §1 groups 2 and 3 (``plan_reservations`` lives in :mod:`cardflow.planner.models`).

* ``currencies`` is global reference data, seeded by migration 0001 with the engine's
  minor-unit table (``money.MINOR_DIGITS``).
* ``banks``, ``card_products`` and ``billing_rule_versions`` hold official templates
  (``workspace_id`` NULL, maintained in the admin console) next to workspace-private rows.
  References to them are plain foreign keys on ``id``; the database trigger
  ``check_template_scope`` only accepts a template or a row of the same workspace.
  Workspace-private rules cannot claim ``verified`` / ``published``.
* ``workspace_id`` cannot change on any tenant table and is never the nil UUID (0002).
* ``currency_accounts.(credit_account_id, currency)`` and ``cash_accounts.currency`` are
  immutable; ``UNIQUE (workspace_id, id, currency)`` keys let child tables reference
  "this account in this currency" (composite foreign keys, data-model §10.4/§10.5).
* ``rule_bindings`` periods of one account do not overlap (exclusion constraint); credit
  pools and card replacements cannot form cycles (triggers).
* ``limit_snapshots.available_raw_minor`` may be negative (over-limit raw value is kept,
  data-model §3); only the derived "capacity for new spend" is clamped at zero.
"""

import uuid
from datetime import date, datetime, time

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
from sqlalchemy.dialects.postgresql import ExcludeConstraint
from sqlalchemy.orm import Mapped, mapped_column

from cardflow.db.base import (
    CONFIRMATION_LEVELS,
    LIMIT_SOURCE_KINDS,
    LIVE_ROWS,
    NIL_UUID,
    OPEN_SOURCES_COMMENT,
    TIME_PRECISIONS,
    Base,
    SyncColumns,
    minor,
    not_pan,
    now_default,
    uuid_pk,
)


class Currency(Base):
    """ISO 4217 code and minor-unit digits (ADR-008)."""

    __tablename__ = "currencies"
    __table_args__ = (
        CheckConstraint("code ~ '^[A-Z]{3}$'", name="code_format"),
        CheckConstraint("minor_digits BETWEEN 0 AND 3", name="minor_digits_range"),
    )

    code: Mapped[str] = mapped_column(CHAR(3), primary_key=True)
    minor_digits: Mapped[int] = mapped_column(SmallInteger)


class Bank(SyncColumns, Base):
    """Issuing bank; ``workspace_id`` NULL = official template."""

    __tablename__ = "banks"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(["workspace_id"], ["workspaces.id"]),
        CheckConstraint("country ~ '^[A-Z]{2}$'", name="country_format"),
        not_pan("name"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID | None] = mapped_column()
    name: Mapped[str] = mapped_column()
    country: Mapped[str | None] = mapped_column(CHAR(2))
    business_tz_default: Mapped[str] = mapped_column(server_default=text("'Asia/Shanghai'"))
    source: Mapped[str | None] = mapped_column()
    created_at: Mapped[datetime] = now_default()


class CardProduct(SyncColumns, Base):
    """Card product of a bank; ``workspace_id`` NULL = official template."""

    __tablename__ = "card_products"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(["workspace_id"], ["workspaces.id"]),
        ForeignKeyConstraint(["bank_id"], ["banks.id"]),
        not_pan("name"),
        Index("ix_card_products_bank_id", "bank_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID | None] = mapped_column()
    bank_id: Mapped[uuid.UUID] = mapped_column()
    name: Mapped[str] = mapped_column()
    network: Mapped[str | None] = mapped_column()
    source: Mapped[str | None] = mapped_column()
    created_at: Mapped[datetime] = now_default()


class CreditPool(SyncColumns, Base):
    """Explicit shared credit line; nested pools via ``parent_pool_id``."""

    __tablename__ = "credit_pools"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(["workspace_id"], ["workspaces.id"]),
        ForeignKeyConstraint(["bank_id"], ["banks.id"]),
        ForeignKeyConstraint(
            ["workspace_id", "parent_pool_id"], ["credit_pools.workspace_id", "credit_pools.id"]
        ),
        CheckConstraint("parent_pool_id IS NULL OR parent_pool_id <> id", name="not_own_parent"),
        not_pan("name"),
        Index("ix_credit_pools_parent_pool_id", "parent_pool_id"),
        Index("ix_credit_pools_bank_id", "bank_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    bank_id: Mapped[uuid.UUID] = mapped_column()
    name: Mapped[str] = mapped_column()
    parent_pool_id: Mapped[uuid.UUID | None] = mapped_column()


class CreditPoolMember(SyncColumns, Base):
    """Membership of a credit account in a pool."""

    __tablename__ = "credit_pool_members"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(
            ["workspace_id", "pool_id"], ["credit_pools.workspace_id", "credit_pools.id"]
        ),
        ForeignKeyConstraint(
            ["workspace_id", "credit_account_id"],
            ["credit_accounts.workspace_id", "credit_accounts.id"],
        ),
        Index("ix_credit_pool_members_credit_account_id", "credit_account_id"),
        Index(
            "uq_credit_pool_members_pool_id_credit_account_id",
            "pool_id",
            "credit_account_id",
            unique=True,
            postgresql_where=LIVE_ROWS,
        ),
        Index("ix_credit_pool_members_pool_id", "pool_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    pool_id: Mapped[uuid.UUID] = mapped_column()
    credit_account_id: Mapped[uuid.UUID] = mapped_column()


class CreditAccount(SyncColumns, Base):
    """Credit account (the billing subject); cards and currency sub-accounts hang off it."""

    __tablename__ = "credit_accounts"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(["workspace_id"], ["workspaces.id"]),
        ForeignKeyConstraint(["bank_id"], ["banks.id"]),
        ForeignKeyConstraint(["product_id"], ["card_products.id"]),
        CheckConstraint("status IN ('active', 'frozen', 'closed')", name="status"),
        CheckConstraint(
            "closed_on IS NULL OR opened_on IS NULL OR closed_on >= opened_on",
            name="closed_after_opened",
        ),
        not_pan("holder_alias"),
        Index("ix_credit_accounts_bank_id", "bank_id"),
        Index("ix_credit_accounts_product_id", "product_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    bank_id: Mapped[uuid.UUID] = mapped_column()
    product_id: Mapped[uuid.UUID | None] = mapped_column()
    holder_alias: Mapped[str] = mapped_column()
    business_tz: Mapped[str] = mapped_column(server_default=text("'Asia/Shanghai'"))
    status: Mapped[str] = mapped_column()
    opened_on: Mapped[date | None] = mapped_column()
    closed_on: Mapped[date | None] = mapped_column()


class CurrencyAccount(SyncColumns, Base):
    """Per-currency sub-account; statements and transactions attach here."""

    __tablename__ = "currency_accounts"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        UniqueConstraint("workspace_id", "id", "currency"),
        UniqueConstraint("workspace_id", "credit_account_id", "id"),
        ForeignKeyConstraint(
            ["workspace_id", "credit_account_id"],
            ["credit_accounts.workspace_id", "credit_accounts.id"],
        ),
        ForeignKeyConstraint(["currency"], ["currencies.code"]),
        Index(
            "uq_currency_accounts_credit_account_id_currency",
            "credit_account_id",
            "currency",
            unique=True,
            postgresql_where=LIVE_ROWS,
        ),
        Index(
            "uq_currency_accounts_one_primary",
            "credit_account_id",
            unique=True,
            postgresql_where=text("is_primary AND deleted_at IS NULL"),
        ),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    credit_account_id: Mapped[uuid.UUID] = mapped_column()
    currency: Mapped[str] = mapped_column(CHAR(3))
    is_primary: Mapped[bool] = mapped_column(server_default=text("false"))


class Card(SyncColumns, Base):
    """A plastic/virtual card; only the last four digits are ever stored."""

    __tablename__ = "cards"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        UniqueConstraint("workspace_id", "credit_account_id", "id"),
        ForeignKeyConstraint(
            ["workspace_id", "credit_account_id"],
            ["credit_accounts.workspace_id", "credit_accounts.id"],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "replaced_by_card_id"], ["cards.workspace_id", "cards.id"]
        ),
        CheckConstraint("last4 ~ '^[0-9]{4}$'", name="last4_digits"),
        CheckConstraint("holder_kind IN ('primary', 'supplementary')", name="holder_kind"),
        CheckConstraint(
            "status IN ('draft', 'active', 'frozen', 'replaced', 'closed')", name="status"
        ),
        CheckConstraint("expires_ym ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'", name="expires_ym_format"),
        CheckConstraint(
            "replaced_by_card_id IS NULL OR replaced_by_card_id <> id", name="not_replaced_by_self"
        ),
        not_pan("alias"),
        Index("ix_cards_credit_account_id", "credit_account_id"),
        Index("ix_cards_replaced_by_card_id", "replaced_by_card_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    credit_account_id: Mapped[uuid.UUID] = mapped_column()
    last4: Mapped[str] = mapped_column(CHAR(4))
    network: Mapped[str | None] = mapped_column()
    holder_kind: Mapped[str] = mapped_column()
    status: Mapped[str] = mapped_column()
    expires_ym: Mapped[str | None] = mapped_column(CHAR(7))
    replaced_by_card_id: Mapped[uuid.UUID | None] = mapped_column()
    alias: Mapped[str | None] = mapped_column()


class BillingRuleVersion(SyncColumns, Base):
    """Versioned billing-cycle rule (bank-rules-spec §2) for a product/account subject.

    In-effect versions (``published`` / ``user_declared``, not tombstoned) of the same scope
    (workspace, or official templates) and subject must not overlap in time.
    """

    __tablename__ = "billing_rule_versions"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(["workspace_id"], ["workspaces.id"]),
        CheckConstraint(
            "subject_kind IN ('product', 'credit_account', 'currency_account')",
            name="subject_kind",
        ),
        CheckConstraint("statement_day BETWEEN 1 AND 31", name="statement_day_range"),
        CheckConstraint("due_kind IN ('fixed_day', 'days_after_statement')", name="due_kind"),
        CheckConstraint("due_day BETWEEN 1 AND 31", name="due_day_range"),
        CheckConstraint("due_month_offset IN (0, 1, 2)", name="due_month_offset"),
        CheckConstraint("due_days BETWEEN 1 AND 60", name="due_days_range"),
        CheckConstraint("due_day_kind IN ('calendar', 'business')", name="due_day_kind"),
        CheckConstraint(
            "holiday_rollover IN ('none', 'next_business_day')", name="holiday_rollover"
        ),
        CheckConstraint(
            "review_status IN "
            "('draft', 'in_review', 'verified', 'published', 'user_declared', 'expired')",
            name="review_status",
        ),
        CheckConstraint(
            "(due_kind = 'fixed_day' AND due_day IS NOT NULL) "
            "OR (due_kind = 'days_after_statement' AND due_days IS NOT NULL)",
            name="due_rule_complete",
        ),
        CheckConstraint(
            "effective_to IS NULL OR effective_to > effective_from", name="effective_range"
        ),
        CheckConstraint(
            "cutoff_tz IS NULL OR cutoff_time IS NOT NULL", name="cutoff_tz_needs_time"
        ),
        CheckConstraint("version >= 1", name="version_positive"),
        CheckConstraint(
            "workspace_id IS NOT NULL OR subject_kind = 'product'", name="template_subject"
        ),
        CheckConstraint(
            "review_status <> 'user_declared' OR workspace_id IS NOT NULL",
            name="user_declared_scope",
        ),
        CheckConstraint(
            "workspace_id IS NULL OR review_status IN ('draft', 'user_declared', 'expired')",
            name="workspace_review_status",
        ),
        not_pan("exceptions"),
        ExcludeConstraint(
            (text(f"(COALESCE(workspace_id, {NIL_UUID}))"), "="),
            ("subject_id", "="),
            (text("(daterange(effective_from, effective_to, '[)'))"), "&&"),
            using="gist",
            where=text("review_status IN ('published', 'user_declared') AND deleted_at IS NULL"),
            name="ex_billing_rule_versions_scope_subject_period",
        ),
        Index("ix_billing_rule_versions_subject_id", "subject_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID | None] = mapped_column()
    subject_kind: Mapped[str] = mapped_column()
    subject_id: Mapped[uuid.UUID] = mapped_column()
    statement_day: Mapped[int] = mapped_column(SmallInteger)
    statement_day_inclusive: Mapped[bool] = mapped_column(server_default=text("true"))
    due_kind: Mapped[str] = mapped_column()
    due_day: Mapped[int | None] = mapped_column(SmallInteger)
    due_month_offset: Mapped[int] = mapped_column(SmallInteger, server_default=text("0"))
    due_days: Mapped[int | None] = mapped_column(SmallInteger)
    due_day_kind: Mapped[str] = mapped_column(server_default=text("'calendar'"))
    holiday_rollover: Mapped[str] = mapped_column(server_default=text("'none'"))
    cutoff_time: Mapped[time | None] = mapped_column()
    cutoff_tz: Mapped[str | None] = mapped_column()
    source: Mapped[str] = mapped_column()
    published_on: Mapped[date | None] = mapped_column()
    effective_from: Mapped[date] = mapped_column()
    effective_to: Mapped[date | None] = mapped_column()
    verified_on: Mapped[date | None] = mapped_column()
    version: Mapped[int] = mapped_column(Integer)
    review_status: Mapped[str] = mapped_column()
    exceptions: Mapped[str | None] = mapped_column()
    created_at: Mapped[datetime] = now_default()


class RuleBinding(SyncColumns, Base):
    """Which rule version (template or user-declared) an account uses from when."""

    __tablename__ = "rule_bindings"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(
            ["workspace_id", "credit_account_id"],
            ["credit_accounts.workspace_id", "credit_accounts.id"],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "credit_account_id", "currency_account_id"],
            [
                "currency_accounts.workspace_id",
                "currency_accounts.credit_account_id",
                "currency_accounts.id",
            ],
        ),
        ForeignKeyConstraint(["billing_rule_version_id"], ["billing_rule_versions.id"]),
        CheckConstraint(
            "effective_to IS NULL OR effective_to > effective_from", name="effective_range"
        ),
        ExcludeConstraint(
            ("workspace_id", "="),
            ("credit_account_id", "="),
            (text(f"(COALESCE(currency_account_id, {NIL_UUID}))"), "="),
            (text("(daterange(effective_from, effective_to, '[)'))"), "&&"),
            using="gist",
            where=LIVE_ROWS,
            name="ex_rule_bindings_account_period",
        ),
        Index("ix_rule_bindings_credit_account_id", "credit_account_id"),
        Index("ix_rule_bindings_billing_rule_version_id", "billing_rule_version_id"),
        Index("ix_rule_bindings_currency_account_id", "currency_account_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    credit_account_id: Mapped[uuid.UUID] = mapped_column()
    currency_account_id: Mapped[uuid.UUID | None] = mapped_column()
    billing_rule_version_id: Mapped[uuid.UUID] = mapped_column()
    effective_from: Mapped[date] = mapped_column()
    effective_to: Mapped[date | None] = mapped_column()


class LimitSnapshot(SyncColumns, Base):
    """Bank-reported limit state at ``balance_as_of`` (raw values kept, may be negative)."""

    __tablename__ = "limit_snapshots"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(
            ["workspace_id", "currency_account_id"],
            ["currency_accounts.workspace_id", "currency_accounts.id"],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "source_document_id"],
            ["source_documents.workspace_id", "source_documents.id"],
        ),
        CheckConstraint(f"source_kind IN {LIMIT_SOURCE_KINDS}", name="source_kind"),
        CheckConstraint(f"confirmation_level IN {CONFIRMATION_LEVELS}", name="confirmation_level"),
        not_pan("special_purpose"),
        Index(
            "ix_limit_snapshots_currency_account_id_balance_as_of",
            "currency_account_id",
            text("balance_as_of DESC"),
        ),
        Index("ix_limit_snapshots_source_document_id", "source_document_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    currency_account_id: Mapped[uuid.UUID] = mapped_column()
    fixed_minor: Mapped[int] = minor()
    temp_minor: Mapped[int] = minor(default=0)
    temp_expires_on: Mapped[date | None] = mapped_column()
    special_minor: Mapped[int] = minor(default=0)
    special_purpose: Mapped[str | None] = mapped_column()
    used_minor: Mapped[int] = minor()
    available_raw_minor: Mapped[int] = mapped_column(
        BigInteger,
        comment=(
            "Available limit exactly as the bank reports it; may be negative (over limit). "
            "Only the derived capacity for new spend is clamped at zero."
        ),
    )
    includes_holds: Mapped[bool] = mapped_column()
    source_kind: Mapped[str] = mapped_column()
    source_document_id: Mapped[uuid.UUID | None] = mapped_column()
    balance_as_of: Mapped[datetime] = mapped_column()
    observed_at: Mapped[datetime] = mapped_column()
    recorded_at: Mapped[datetime] = now_default()
    confirmation_level: Mapped[str] = mapped_column()


class LimitAdjustment(SyncColumns, Base):
    """Limit change history: fixed, temporary (with expiry) or special-purpose limits."""

    __tablename__ = "limit_adjustments"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(
            ["workspace_id", "currency_account_id"],
            ["currency_accounts.workspace_id", "currency_accounts.id"],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "source_document_id"],
            ["source_documents.workspace_id", "source_documents.id"],
        ),
        CheckConstraint("kind IN ('fixed', 'temp', 'special')", name="kind"),
        CheckConstraint("new_limit_minor >= 0", name="new_limit_non_negative"),
        CheckConstraint(
            "expires_on IS NULL OR expires_on > effective_on", name="expires_after_effective"
        ),
        CheckConstraint(f"source_kind IN {LIMIT_SOURCE_KINDS}", name="source_kind"),
        CheckConstraint(f"confirmation_level IN {CONFIRMATION_LEVELS}", name="confirmation_level"),
        not_pan("purpose"),
        Index("ix_limit_adjustments_currency_account_id", "currency_account_id"),
        Index("ix_limit_adjustments_source_document_id", "source_document_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    currency_account_id: Mapped[uuid.UUID] = mapped_column()
    kind: Mapped[str] = mapped_column()
    previous_limit_minor: Mapped[int | None] = minor()
    new_limit_minor: Mapped[int] = minor()
    effective_on: Mapped[date] = mapped_column()
    expires_on: Mapped[date | None] = mapped_column()
    purpose: Mapped[str | None] = mapped_column()
    source_kind: Mapped[str] = mapped_column()
    source_document_id: Mapped[uuid.UUID | None] = mapped_column()
    observed_at: Mapped[datetime | None] = mapped_column()
    recorded_at: Mapped[datetime] = now_default()
    confirmation_level: Mapped[str] = mapped_column()


class PreauthHold(SyncColumns, Base):
    """Pre-authorisation hold; ``transaction_id`` links the captured transaction."""

    __tablename__ = "preauth_holds"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(["currency"], ["currencies.code"]),
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
            ["workspace_id", "currency_account_id", "transaction_id"],
            [
                "transactions.workspace_id",
                "transactions.currency_account_id",
                "transactions.id",
            ],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "source_document_id"],
            ["source_documents.workspace_id", "source_documents.id"],
        ),
        CheckConstraint("amount_minor > 0", name="amount_positive"),
        CheckConstraint(f"time_precision IN {TIME_PRECISIONS}", name="time_precision"),
        CheckConstraint(f"confirmation_level IN {CONFIRMATION_LEVELS}", name="confirmation_level"),
        CheckConstraint("status IN ('active', 'captured', 'released', 'expired')", name="status"),
        not_pan("merchant"),
        Index("ix_preauth_holds_currency_account_id", "currency_account_id"),
        Index("ix_preauth_holds_card_id", "card_id"),
        Index("ix_preauth_holds_transaction_id", "transaction_id"),
        Index("ix_preauth_holds_source_document_id", "source_document_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    currency_account_id: Mapped[uuid.UUID] = mapped_column()
    card_id: Mapped[uuid.UUID | None] = mapped_column()
    amount_minor: Mapped[int] = minor()
    currency: Mapped[str] = mapped_column(CHAR(3))
    held_at: Mapped[datetime] = mapped_column()
    held_tz: Mapped[str] = mapped_column()
    time_precision: Mapped[str] = mapped_column()
    expected_release_on: Mapped[date | None] = mapped_column()
    merchant: Mapped[str | None] = mapped_column()
    status: Mapped[str] = mapped_column()
    transaction_id: Mapped[uuid.UUID | None] = mapped_column()
    source_kind: Mapped[str] = mapped_column(comment=OPEN_SOURCES_COMMENT)
    source_document_id: Mapped[uuid.UUID | None] = mapped_column()
    confirmation_level: Mapped[str] = mapped_column()
    recorded_at: Mapped[datetime] = now_default()
    credit_account_id: Mapped[uuid.UUID] = mapped_column(
        comment="Derived from currency_account_id by trigger; clients do not supply it."
    )
