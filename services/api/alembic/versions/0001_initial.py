"""Initial schema: identity, banking, limits, statements, cash, imports, planner, ops tables.

Revision ID: 0001
Revises: (none)
Create Date: 2026-10-16

Covers data-model §1 groups 1-7 plus sync_changes, sync_conflicts, audit_log,
deletion_tasks, jobs and worker_heartbeats (group 10). Promotions, benefits, points,
annual fees and notifications are NOT part of this revision. Row-level security, roles
and grants are revision 0003 (T-006); revision 0002 holds the post-review structural
fixes (data-model §10).

Conventions (see cardflow/db/base.py):
* every name is explicit and equals what the SQLAlchemy naming convention produces
  (pk_<table>, uq_<table>_<cols>, ck_<table>_<name>, fk_<table>_<cols without
  workspace_id>, ix_<table>_<cols>); tests/db/test_model_drift.py checks this;
* primary keys default to uuidv7() (PostgreSQL 18);
* money: *_minor BIGINT + currency; rates NUMERIC(20,10); never float/double/real/money;
* tenant tables: workspace_id NOT NULL + UNIQUE (workspace_id, id) + composite foreign
  keys (workspace_id, parent_id) so the database itself rejects cross-workspace links;
* banks, card_products and billing_rule_versions: workspace_id NULL = official template;
  references to them are plain foreign keys on id plus a scope trigger
  (check_template_scope) that only accepts templates or rows of the same workspace;
* soft references without a foreign key, by design: source_document_id /
  evidence_document_id (attachments are purged by retention while financial facts stay,
  data-model §9), origin_device_id / uploaded_by_device_id (provenance), polymorphic
  references (billing_rule_versions.subject_id is checked by a trigger;
  sync_changes.row_id, sync_conflicts.row_id, audit_log.target_id,
  dedupe_keys.entity_id, import_batch_items.*_id, plan_invalidations.caused_by_id),
  jobs references (parse_jobs.job_id, plan_runs.job_id) and the workspace_id of
  audit_log, deletion_tasks and jobs (they must outlive a purged workspace).

Constraint triggers (T-007):
* statement_versions: amount columns and due_date are append-only (UPDATE rejected,
  data-model §4); DELETE/TRUNCATE are rejected unless the current transaction ran
  SELECT set_config('app.purge', 'on', true) -- reserved for the future
  workspace-deletion task (deletion_tasks, 30-day grace, data-model §9);
* repayment_allocations: DEFERRABLE INITIALLY DEFERRED constraint triggers check at
  commit that the active allocations of a repayment sum to at most repayments.amount_minor,
  also when the repayment amount is lowered, and that every allocated statement belongs
  to the repayment's currency account;
* billing_rule_versions: exclusion constraint per scope (COALESCE(workspace_id, nil uuid)),
  subject and effective period, for in-effect rows (published / user_declared, not
  tombstoned).

This revision never UPDATEs money values; its only data change is the currencies seed.

Extensions (R2-23): btree_gist and pg_trgm are an environment prerequisite. upgrade()
creates them only if missing (IF NOT EXISTS); downgrade() leaves them in place, because
they may predate this revision (installed by a DBA) or serve objects outside this schema,
and dropping them would either remove something this revision did not create or fail.
"""

from collections.abc import Sequence

from alembic import op

revision: str = "0001"
down_revision: str | Sequence[str] | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# Syncable-table columns (architecture §6). Kept as a literal fragment so every CREATE
# TABLE below reads like the DDL in data-model §4.
_SYNC = """
    row_version BIGINT NOT NULL DEFAULT 1,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    origin_device_id UUID,"""

_CONFIRMATION = "('system_estimated', 'user_confirmed', 'bank_confirmed')"
_CASH_CATEGORIES = (
    "('income', 'bill', 'living', 'repayment', 'transfer_in', 'transfer_out', 'fee', 'other')"
)

EXTENSIONS: list[str] = [
    "CREATE EXTENSION IF NOT EXISTS btree_gist",
    "CREATE EXTENSION IF NOT EXISTS pg_trgm",
]

# ---------------------------------------------------------------------------------------
# Group 1 - identity and workspaces
# ---------------------------------------------------------------------------------------
IDENTITY: list[str] = [
    """
CREATE TABLE users (
    id UUID NOT NULL DEFAULT uuidv7(),
    email TEXT,
    password_hash TEXT,
    display_name TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    disabled_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    CONSTRAINT pk_users PRIMARY KEY (id),
    CONSTRAINT uq_users_email UNIQUE (email),
    CONSTRAINT ck_users_email_lowercase CHECK (email = lower(email)),
    CONSTRAINT ck_users_password_needs_email CHECK (password_hash IS NULL OR email IS NOT NULL),
    CONSTRAINT ck_users_password_argon2id
        CHECK (password_hash IS NULL OR password_hash LIKE '$argon2id$%')
)
""",
    """
CREATE TABLE workspaces (
    id UUID NOT NULL DEFAULT uuidv7(),
    owner_user_id UUID NOT NULL,
    kind TEXT NOT NULL,
    dek_wrapped BYTEA,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT pk_workspaces PRIMARY KEY (id),
    CONSTRAINT fk_workspaces_owner_user_id FOREIGN KEY (owner_user_id) REFERENCES users (id),
    CONSTRAINT ck_workspaces_kind CHECK (kind IN ('real', 'demo'))
)
""",
    "CREATE INDEX ix_workspaces_owner_user_id ON workspaces (owner_user_id)",
    """
CREATE TABLE workspace_members (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    user_id UUID NOT NULL,
    role TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_workspace_members PRIMARY KEY (id),
    CONSTRAINT uq_workspace_members_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT uq_workspace_members_workspace_id_user_id UNIQUE (workspace_id, user_id),
    CONSTRAINT fk_workspace_members_workspace_id
        FOREIGN KEY (workspace_id) REFERENCES workspaces (id),
    CONSTRAINT fk_workspace_members_user_id FOREIGN KEY (user_id) REFERENCES users (id),
    CONSTRAINT ck_workspace_members_role CHECK (role IN ('owner', 'admin', 'member'))
)
""",
    "CREATE INDEX ix_workspace_members_user_id ON workspace_members (user_id)",
    """
CREATE TABLE devices (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    user_id UUID,
    name TEXT,
    platform TEXT NOT NULL,
    public_key BYTEA NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    CONSTRAINT pk_devices PRIMARY KEY (id),
    CONSTRAINT uq_devices_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_devices_workspace_id FOREIGN KEY (workspace_id) REFERENCES workspaces (id),
    CONSTRAINT fk_devices_user_id FOREIGN KEY (user_id) REFERENCES users (id)
)
""",
    "CREATE INDEX ix_devices_user_id ON devices (user_id)",
    """
CREATE TABLE auth_sessions (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    device_id UUID NOT NULL,
    refresh_token_hash CHAR(64) NOT NULL,
    rotated_from_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    last_used_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    revoked_reason TEXT,
    CONSTRAINT pk_auth_sessions PRIMARY KEY (id),
    CONSTRAINT uq_auth_sessions_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT uq_auth_sessions_refresh_token_hash UNIQUE (refresh_token_hash),
    CONSTRAINT uq_auth_sessions_rotated_from_id UNIQUE (rotated_from_id),
    CONSTRAINT fk_auth_sessions_device_id
        FOREIGN KEY (workspace_id, device_id) REFERENCES devices (workspace_id, id),
    CONSTRAINT fk_auth_sessions_rotated_from_id
        FOREIGN KEY (workspace_id, rotated_from_id) REFERENCES auth_sessions (workspace_id, id),
    CONSTRAINT ck_auth_sessions_refresh_token_hash_hex
        CHECK (refresh_token_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT ck_auth_sessions_expires_after_created CHECK (expires_at > created_at),
    CONSTRAINT ck_auth_sessions_reason_needs_revocation
        CHECK (revoked_reason IS NULL OR revoked_at IS NOT NULL),
    CONSTRAINT ck_auth_sessions_not_rotated_from_self
        CHECK (rotated_from_id IS NULL OR rotated_from_id <> id)
)
""",
    "CREATE INDEX ix_auth_sessions_device_id ON auth_sessions (device_id)",
    f"""
CREATE TABLE consents (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    purpose TEXT NOT NULL,
    granted_at TIMESTAMPTZ NOT NULL,
    withdrawn_at TIMESTAMPTZ,
    details JSONB NOT NULL DEFAULT '{{}}'::jsonb,{_SYNC}
    CONSTRAINT pk_consents PRIMARY KEY (id),
    CONSTRAINT uq_consents_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_consents_workspace_id FOREIGN KEY (workspace_id) REFERENCES workspaces (id),
    CONSTRAINT ck_consents_withdrawn_after_granted
        CHECK (withdrawn_at IS NULL OR withdrawn_at >= granted_at)
)
""",
    "CREATE INDEX ix_consents_workspace_id_purpose ON consents (workspace_id, purpose)",
    """
CREATE TABLE idempotency_keys (
    workspace_id UUID NOT NULL,
    key TEXT NOT NULL,
    request_hash CHAR(64) NOT NULL,
    response_status SMALLINT NOT NULL,
    response_body JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_idempotency_keys PRIMARY KEY (workspace_id, key),
    CONSTRAINT fk_idempotency_keys_workspace_id
        FOREIGN KEY (workspace_id) REFERENCES workspaces (id),
    CONSTRAINT ck_idempotency_keys_request_hash_hex CHECK (request_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT ck_idempotency_keys_response_status_range
        CHECK (response_status BETWEEN 100 AND 599)
)
""",
]

# ---------------------------------------------------------------------------------------
# Group 2 - banks, products, accounts, cards, billing rules
# ---------------------------------------------------------------------------------------
BANKING: list[str] = [
    """
CREATE TABLE currencies (
    code CHAR(3) NOT NULL,
    minor_digits SMALLINT NOT NULL,
    CONSTRAINT pk_currencies PRIMARY KEY (code),
    CONSTRAINT ck_currencies_code_format CHECK (code ~ '^[A-Z]{3}$'),
    CONSTRAINT ck_currencies_minor_digits_range CHECK (minor_digits BETWEEN 0 AND 3)
)
""",
    # Same table as the engine (planner money.MINOR_DIGITS / PoC money.py).
    """
INSERT INTO currencies (code, minor_digits) VALUES
    ('CNY', 2), ('USD', 2), ('EUR', 2), ('HKD', 2), ('GBP', 2), ('MOP', 2), ('TWD', 2),
    ('JPY', 0), ('KRW', 0), ('VND', 0),
    ('KWD', 3), ('BHD', 3), ('JOD', 3)
""",
    f"""
CREATE TABLE banks (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID,
    name TEXT NOT NULL,
    country CHAR(2),
    business_tz_default TEXT NOT NULL DEFAULT 'Asia/Shanghai',
    source TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),{_SYNC}
    CONSTRAINT pk_banks PRIMARY KEY (id),
    CONSTRAINT uq_banks_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_banks_workspace_id FOREIGN KEY (workspace_id) REFERENCES workspaces (id),
    CONSTRAINT ck_banks_country_format CHECK (country ~ '^[A-Z]{{2}}$')
)
""",
    f"""
CREATE TABLE card_products (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID,
    bank_id UUID NOT NULL,
    name TEXT NOT NULL,
    network TEXT,
    source TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),{_SYNC}
    CONSTRAINT pk_card_products PRIMARY KEY (id),
    CONSTRAINT uq_card_products_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_card_products_workspace_id
        FOREIGN KEY (workspace_id) REFERENCES workspaces (id),
    CONSTRAINT fk_card_products_bank_id FOREIGN KEY (bank_id) REFERENCES banks (id)
)
""",
    "CREATE INDEX ix_card_products_bank_id ON card_products (bank_id)",
    f"""
CREATE TABLE credit_pools (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    bank_id UUID NOT NULL,
    name TEXT NOT NULL,
    parent_pool_id UUID,{_SYNC}
    CONSTRAINT pk_credit_pools PRIMARY KEY (id),
    CONSTRAINT uq_credit_pools_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_credit_pools_workspace_id FOREIGN KEY (workspace_id) REFERENCES workspaces (id),
    CONSTRAINT fk_credit_pools_bank_id FOREIGN KEY (bank_id) REFERENCES banks (id),
    CONSTRAINT fk_credit_pools_parent_pool_id
        FOREIGN KEY (workspace_id, parent_pool_id) REFERENCES credit_pools (workspace_id, id),
    CONSTRAINT ck_credit_pools_not_own_parent CHECK (parent_pool_id IS NULL OR parent_pool_id <> id)
)
""",
    """
CREATE TABLE credit_accounts (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    bank_id UUID NOT NULL,
    product_id UUID,
    holder_alias TEXT NOT NULL,
    business_tz TEXT NOT NULL DEFAULT 'Asia/Shanghai',
    status TEXT NOT NULL,
    opened_on DATE,
    closed_on DATE,
    row_version BIGINT NOT NULL DEFAULT 1,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    origin_device_id UUID,
    CONSTRAINT pk_credit_accounts PRIMARY KEY (id),
    CONSTRAINT uq_credit_accounts_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_credit_accounts_workspace_id
        FOREIGN KEY (workspace_id) REFERENCES workspaces (id),
    CONSTRAINT fk_credit_accounts_bank_id FOREIGN KEY (bank_id) REFERENCES banks (id),
    CONSTRAINT fk_credit_accounts_product_id FOREIGN KEY (product_id) REFERENCES card_products (id),
    CONSTRAINT ck_credit_accounts_status CHECK (status IN ('active', 'frozen', 'closed')),
    CONSTRAINT ck_credit_accounts_closed_after_opened
        CHECK (closed_on IS NULL OR opened_on IS NULL OR closed_on >= opened_on)
)
""",
    "CREATE INDEX ix_credit_accounts_bank_id ON credit_accounts (bank_id)",
    f"""
CREATE TABLE credit_pool_members (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    pool_id UUID NOT NULL,
    credit_account_id UUID NOT NULL,{_SYNC}
    CONSTRAINT pk_credit_pool_members PRIMARY KEY (id),
    CONSTRAINT uq_credit_pool_members_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT uq_credit_pool_members_pool_id_credit_account_id UNIQUE (pool_id, credit_account_id),
    CONSTRAINT fk_credit_pool_members_pool_id
        FOREIGN KEY (workspace_id, pool_id) REFERENCES credit_pools (workspace_id, id),
    CONSTRAINT fk_credit_pool_members_credit_account_id
        FOREIGN KEY (workspace_id, credit_account_id) REFERENCES credit_accounts (workspace_id, id)
)
""",
    "CREATE INDEX ix_credit_pool_members_credit_account_id ON credit_pool_members "
    "(credit_account_id)",
    f"""
CREATE TABLE currency_accounts (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    credit_account_id UUID NOT NULL,
    currency CHAR(3) NOT NULL,
    is_primary BOOLEAN NOT NULL DEFAULT false,{_SYNC}
    CONSTRAINT pk_currency_accounts PRIMARY KEY (id),
    CONSTRAINT uq_currency_accounts_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT uq_currency_accounts_credit_account_id_currency UNIQUE (credit_account_id, currency),
    CONSTRAINT fk_currency_accounts_credit_account_id
        FOREIGN KEY (workspace_id, credit_account_id) REFERENCES credit_accounts (workspace_id, id),
    CONSTRAINT fk_currency_accounts_currency FOREIGN KEY (currency) REFERENCES currencies (code)
)
""",
    # At most one live primary currency sub-account per credit account.
    "CREATE UNIQUE INDEX uq_currency_accounts_one_primary ON currency_accounts "
    "(credit_account_id) WHERE is_primary AND deleted_at IS NULL",
    f"""
CREATE TABLE cards (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    credit_account_id UUID NOT NULL,
    last4 CHAR(4) NOT NULL,
    network TEXT,
    holder_kind TEXT NOT NULL,
    status TEXT NOT NULL,
    expires_ym CHAR(7),
    replaced_by_card_id UUID,
    alias TEXT,{_SYNC}
    CONSTRAINT pk_cards PRIMARY KEY (id),
    CONSTRAINT uq_cards_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_cards_credit_account_id
        FOREIGN KEY (workspace_id, credit_account_id) REFERENCES credit_accounts (workspace_id, id),
    CONSTRAINT fk_cards_replaced_by_card_id
        FOREIGN KEY (workspace_id, replaced_by_card_id) REFERENCES cards (workspace_id, id),
    CONSTRAINT ck_cards_last4_digits CHECK (last4 ~ '^[0-9]{{4}}$'),
    CONSTRAINT ck_cards_holder_kind CHECK (holder_kind IN ('primary', 'supplementary')),
    CONSTRAINT ck_cards_status
        CHECK (status IN ('draft', 'active', 'frozen', 'replaced', 'closed')),
    CONSTRAINT ck_cards_expires_ym_format CHECK (expires_ym ~ '^[0-9]{{4}}-(0[1-9]|1[0-2])$'),
    CONSTRAINT ck_cards_not_replaced_by_self
        CHECK (replaced_by_card_id IS NULL OR replaced_by_card_id <> id)
)
""",
    "CREATE INDEX ix_cards_credit_account_id ON cards (credit_account_id)",
    f"""
CREATE TABLE billing_rule_versions (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID,
    subject_kind TEXT NOT NULL,
    subject_id UUID NOT NULL,
    statement_day SMALLINT NOT NULL,
    statement_day_inclusive BOOLEAN NOT NULL DEFAULT true,
    due_kind TEXT NOT NULL,
    due_day SMALLINT,
    due_month_offset SMALLINT NOT NULL DEFAULT 0,
    due_days SMALLINT,
    due_day_kind TEXT NOT NULL DEFAULT 'calendar',
    holiday_rollover TEXT NOT NULL DEFAULT 'none',
    cutoff_time TIME,
    cutoff_tz TEXT,
    source TEXT NOT NULL,
    published_on DATE,
    effective_from DATE NOT NULL,
    effective_to DATE,
    verified_on DATE,
    version INTEGER NOT NULL,
    review_status TEXT NOT NULL,
    exceptions TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),{_SYNC}
    CONSTRAINT pk_billing_rule_versions PRIMARY KEY (id),
    CONSTRAINT uq_billing_rule_versions_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_billing_rule_versions_workspace_id
        FOREIGN KEY (workspace_id) REFERENCES workspaces (id),
    CONSTRAINT ck_billing_rule_versions_subject_kind
        CHECK (subject_kind IN ('product', 'credit_account', 'currency_account')),
    CONSTRAINT ck_billing_rule_versions_statement_day_range CHECK (statement_day BETWEEN 1 AND 31),
    CONSTRAINT ck_billing_rule_versions_due_kind
        CHECK (due_kind IN ('fixed_day', 'days_after_statement')),
    CONSTRAINT ck_billing_rule_versions_due_day_range CHECK (due_day BETWEEN 1 AND 31),
    CONSTRAINT ck_billing_rule_versions_due_month_offset CHECK (due_month_offset IN (0, 1, 2)),
    CONSTRAINT ck_billing_rule_versions_due_days_range CHECK (due_days BETWEEN 1 AND 60),
    CONSTRAINT ck_billing_rule_versions_due_day_kind
        CHECK (due_day_kind IN ('calendar', 'business')),
    CONSTRAINT ck_billing_rule_versions_holiday_rollover
        CHECK (holiday_rollover IN ('none', 'next_business_day')),
    CONSTRAINT ck_billing_rule_versions_review_status
        CHECK (review_status IN
               ('draft', 'in_review', 'verified', 'published', 'user_declared', 'expired')),
    CONSTRAINT ck_billing_rule_versions_due_rule_complete
        CHECK ((due_kind = 'fixed_day' AND due_day IS NOT NULL)
               OR (due_kind = 'days_after_statement' AND due_days IS NOT NULL)),
    CONSTRAINT ck_billing_rule_versions_effective_range
        CHECK (effective_to IS NULL OR effective_to > effective_from),
    CONSTRAINT ck_billing_rule_versions_cutoff_tz_needs_time
        CHECK (cutoff_tz IS NULL OR cutoff_time IS NOT NULL),
    CONSTRAINT ck_billing_rule_versions_version_positive CHECK (version >= 1),
    -- Official templates are product rules; user-declared rules belong to a workspace.
    CONSTRAINT ck_billing_rule_versions_template_subject
        CHECK (workspace_id IS NOT NULL OR subject_kind = 'product'),
    CONSTRAINT ck_billing_rule_versions_user_declared_scope
        CHECK (review_status <> 'user_declared' OR workspace_id IS NOT NULL),
    -- data-model §4 keyed this on subject_id only, which made an official template and a
    -- workspace's user_declared rule (and two workspaces) collide. The scope is part of
    -- the key now: only "same scope + same subject + overlapping period" is rejected.
    CONSTRAINT ex_billing_rule_versions_scope_subject_period EXCLUDE USING gist (
        (COALESCE(workspace_id, '00000000-0000-0000-0000-000000000000'::uuid)) WITH =,
        subject_id WITH =,
        (daterange(effective_from, effective_to, '[)')) WITH &&
    ) WHERE (review_status IN ('published', 'user_declared') AND deleted_at IS NULL)
)
""",
    "CREATE INDEX ix_billing_rule_versions_subject_id ON billing_rule_versions (subject_id)",
    f"""
CREATE TABLE rule_bindings (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    credit_account_id UUID NOT NULL,
    currency_account_id UUID,
    billing_rule_version_id UUID NOT NULL,
    effective_from DATE NOT NULL,
    effective_to DATE,{_SYNC}
    CONSTRAINT pk_rule_bindings PRIMARY KEY (id),
    CONSTRAINT uq_rule_bindings_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_rule_bindings_credit_account_id
        FOREIGN KEY (workspace_id, credit_account_id) REFERENCES credit_accounts (workspace_id, id),
    CONSTRAINT fk_rule_bindings_currency_account_id
        FOREIGN KEY (workspace_id, currency_account_id)
        REFERENCES currency_accounts (workspace_id, id),
    CONSTRAINT fk_rule_bindings_billing_rule_version_id
        FOREIGN KEY (billing_rule_version_id) REFERENCES billing_rule_versions (id),
    CONSTRAINT ck_rule_bindings_effective_range
        CHECK (effective_to IS NULL OR effective_to > effective_from)
)
""",
    "CREATE INDEX ix_rule_bindings_credit_account_id ON rule_bindings (credit_account_id)",
    "CREATE INDEX ix_rule_bindings_billing_rule_version_id ON rule_bindings "
    "(billing_rule_version_id)",
]

# ---------------------------------------------------------------------------------------
# Group 3 (part 1) - limits
# ---------------------------------------------------------------------------------------
LIMITS: list[str] = [
    f"""
CREATE TABLE limit_snapshots (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    currency_account_id UUID NOT NULL,
    fixed_minor BIGINT NOT NULL,
    temp_minor BIGINT NOT NULL DEFAULT 0,
    temp_expires_on DATE,
    special_minor BIGINT NOT NULL DEFAULT 0,
    special_purpose TEXT,
    used_minor BIGINT NOT NULL,
    available_raw_minor BIGINT NOT NULL,          -- may be negative: over-limit raw value kept
    includes_holds BOOLEAN NOT NULL,
    source_kind TEXT NOT NULL,
    source_document_id UUID,
    balance_as_of TIMESTAMPTZ NOT NULL,
    observed_at TIMESTAMPTZ NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    confirmation_level TEXT NOT NULL,{_SYNC}
    CONSTRAINT pk_limit_snapshots PRIMARY KEY (id),
    CONSTRAINT uq_limit_snapshots_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_limit_snapshots_currency_account_id
        FOREIGN KEY (workspace_id, currency_account_id)
        REFERENCES currency_accounts (workspace_id, id),
    CONSTRAINT ck_limit_snapshots_source_kind
        CHECK (source_kind IN ('bank_app', 'statement', 'user', 'import')),
    CONSTRAINT ck_limit_snapshots_confirmation_level CHECK (confirmation_level IN {_CONFIRMATION})
)
""",
    "CREATE INDEX ix_limit_snapshots_currency_account_id_balance_as_of ON limit_snapshots "
    "(currency_account_id, balance_as_of DESC)",
    f"""
CREATE TABLE limit_adjustments (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    currency_account_id UUID NOT NULL,
    kind TEXT NOT NULL,
    previous_limit_minor BIGINT,
    new_limit_minor BIGINT NOT NULL,
    effective_on DATE NOT NULL,
    expires_on DATE,
    purpose TEXT,
    source_kind TEXT NOT NULL,
    source_document_id UUID,
    observed_at TIMESTAMPTZ,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    confirmation_level TEXT NOT NULL,{_SYNC}
    CONSTRAINT pk_limit_adjustments PRIMARY KEY (id),
    CONSTRAINT uq_limit_adjustments_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_limit_adjustments_currency_account_id
        FOREIGN KEY (workspace_id, currency_account_id)
        REFERENCES currency_accounts (workspace_id, id),
    CONSTRAINT ck_limit_adjustments_kind CHECK (kind IN ('fixed', 'temp', 'special')),
    CONSTRAINT ck_limit_adjustments_new_limit_non_negative CHECK (new_limit_minor >= 0),
    CONSTRAINT ck_limit_adjustments_expires_after_effective
        CHECK (expires_on IS NULL OR expires_on > effective_on),
    CONSTRAINT ck_limit_adjustments_source_kind
        CHECK (source_kind IN ('bank_app', 'statement', 'user', 'import')),
    CONSTRAINT ck_limit_adjustments_confirmation_level
        CHECK (confirmation_level IN {_CONFIRMATION})
)
""",
    "CREATE INDEX ix_limit_adjustments_currency_account_id ON limit_adjustments "
    "(currency_account_id)",
]

# ---------------------------------------------------------------------------------------
# Group 4 - transactions, statements, installments, charges
# ---------------------------------------------------------------------------------------
STATEMENTS: list[str] = [
    f"""
CREATE TABLE transactions (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    currency_account_id UUID NOT NULL,
    card_id UUID,
    txn_type TEXT NOT NULL,
    amount_minor BIGINT NOT NULL,                 -- liability increase positive, credits negative
    currency CHAR(3) NOT NULL,
    txn_at TIMESTAMPTZ NOT NULL,
    txn_tz TEXT NOT NULL,
    time_precision TEXT NOT NULL,
    posted_on DATE,
    merchant TEXT,
    mcc CHAR(4),
    category TEXT,
    status TEXT NOT NULL,
    bank_reference TEXT,
    parent_transaction_id UUID,
    fingerprint TEXT NOT NULL,
    source_kind TEXT NOT NULL,
    source_document_id UUID,
    confirmation_level TEXT NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),{_SYNC}
    CONSTRAINT pk_transactions PRIMARY KEY (id),
    CONSTRAINT uq_transactions_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_transactions_currency_account_id
        FOREIGN KEY (workspace_id, currency_account_id)
        REFERENCES currency_accounts (workspace_id, id),
    CONSTRAINT fk_transactions_card_id
        FOREIGN KEY (workspace_id, card_id) REFERENCES cards (workspace_id, id),
    CONSTRAINT fk_transactions_parent_transaction_id
        FOREIGN KEY (workspace_id, parent_transaction_id)
        REFERENCES transactions (workspace_id, id),
    CONSTRAINT fk_transactions_currency FOREIGN KEY (currency) REFERENCES currencies (code),
    CONSTRAINT ck_transactions_txn_type
        CHECK (txn_type IN ('purchase', 'refund', 'reversal', 'cash_advance', 'fee', 'interest',
                            'repayment', 'transfer', 'preauth', 'installment_principal',
                            'adjustment')),
    CONSTRAINT ck_transactions_time_precision
        CHECK (time_precision IN ('datetime', 'date', 'month')),
    CONSTRAINT ck_transactions_status CHECK (status IN ('pending', 'posted', 'reversed')),
    CONSTRAINT ck_transactions_mcc_digits CHECK (mcc ~ '^[0-9]{{4}}$'),
    CONSTRAINT ck_transactions_confirmation_level CHECK (confirmation_level IN {_CONFIRMATION}),
    CONSTRAINT ck_transactions_not_own_parent
        CHECK (parent_transaction_id IS NULL OR parent_transaction_id <> id)
)
""",
    "CREATE INDEX ix_transactions_currency_account_id_posted_on ON transactions "
    "(currency_account_id, posted_on)",
    "CREATE INDEX ix_transactions_workspace_id_fingerprint ON transactions "
    "(workspace_id, fingerprint)",
    "CREATE INDEX ix_transactions_merchant_trgm ON transactions USING gin (merchant gin_trgm_ops)",
    f"""
CREATE TABLE transaction_links (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    from_transaction_id UUID NOT NULL,
    to_transaction_id UUID NOT NULL,
    kind TEXT NOT NULL,
    confirmation_level TEXT NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),{_SYNC}
    CONSTRAINT pk_transaction_links PRIMARY KEY (id),
    CONSTRAINT uq_transaction_links_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT uq_transaction_links_from_transaction_id_to_transaction_id_kind
        UNIQUE (from_transaction_id, to_transaction_id, kind),
    CONSTRAINT fk_transaction_links_from_transaction_id
        FOREIGN KEY (workspace_id, from_transaction_id) REFERENCES transactions (workspace_id, id),
    CONSTRAINT fk_transaction_links_to_transaction_id
        FOREIGN KEY (workspace_id, to_transaction_id) REFERENCES transactions (workspace_id, id),
    CONSTRAINT ck_transaction_links_distinct_transactions
        CHECK (from_transaction_id <> to_transaction_id),
    CONSTRAINT ck_transaction_links_confirmation_level
        CHECK (confirmation_level IN {_CONFIRMATION})
)
""",
    "CREATE INDEX ix_transaction_links_to_transaction_id ON transaction_links (to_transaction_id)",
    f"""
CREATE TABLE preauth_holds (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    currency_account_id UUID NOT NULL,
    card_id UUID,
    amount_minor BIGINT NOT NULL,
    currency CHAR(3) NOT NULL,
    held_at TIMESTAMPTZ NOT NULL,
    held_tz TEXT NOT NULL,
    time_precision TEXT NOT NULL,
    expected_release_on DATE,
    merchant TEXT,
    status TEXT NOT NULL,
    transaction_id UUID,
    source_kind TEXT NOT NULL,
    source_document_id UUID,
    confirmation_level TEXT NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),{_SYNC}
    CONSTRAINT pk_preauth_holds PRIMARY KEY (id),
    CONSTRAINT uq_preauth_holds_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_preauth_holds_currency_account_id
        FOREIGN KEY (workspace_id, currency_account_id)
        REFERENCES currency_accounts (workspace_id, id),
    CONSTRAINT fk_preauth_holds_card_id
        FOREIGN KEY (workspace_id, card_id) REFERENCES cards (workspace_id, id),
    CONSTRAINT fk_preauth_holds_transaction_id
        FOREIGN KEY (workspace_id, transaction_id) REFERENCES transactions (workspace_id, id),
    CONSTRAINT fk_preauth_holds_currency FOREIGN KEY (currency) REFERENCES currencies (code),
    CONSTRAINT ck_preauth_holds_amount_positive CHECK (amount_minor > 0),
    CONSTRAINT ck_preauth_holds_time_precision
        CHECK (time_precision IN ('datetime', 'date', 'month')),
    CONSTRAINT ck_preauth_holds_confirmation_level CHECK (confirmation_level IN {_CONFIRMATION})
)
""",
    "CREATE INDEX ix_preauth_holds_currency_account_id ON preauth_holds (currency_account_id)",
    f"""
CREATE TABLE statements (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    currency_account_id UUID NOT NULL,
    statement_date DATE NOT NULL,
    due_date DATE NOT NULL,
    status TEXT NOT NULL,
    current_version_id UUID,{_SYNC}
    CONSTRAINT pk_statements PRIMARY KEY (id),
    CONSTRAINT uq_statements_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT uq_statements_currency_account_id_statement_date
        UNIQUE (currency_account_id, statement_date),
    CONSTRAINT fk_statements_currency_account_id
        FOREIGN KEY (workspace_id, currency_account_id)
        REFERENCES currency_accounts (workspace_id, id),
    CONSTRAINT ck_statements_due_after_statement CHECK (due_date > statement_date),
    CONSTRAINT ck_statements_status
        CHECK (status IN ('predicted', 'issued', 'amended', 'partially_settled', 'settled',
                          'overdue'))
)
""",
    f"""
CREATE TABLE statement_versions (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    statement_id UUID NOT NULL,
    version_no INTEGER NOT NULL,
    source_kind TEXT NOT NULL,
    source_document_id UUID,
    previous_balance_minor BIGINT,
    new_balance_minor BIGINT NOT NULL,
    min_due_minor BIGINT,
    payments_minor BIGINT,
    credits_minor BIGINT,
    fees_minor BIGINT,
    interest_minor BIGINT,
    installment_due_minor BIGINT,
    credit_balance_minor BIGINT,                  -- overpayment / credit balance
    due_date DATE NOT NULL,
    recorded_by TEXT NOT NULL,
    reason TEXT,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),{_SYNC}
    CONSTRAINT pk_statement_versions PRIMARY KEY (id),
    CONSTRAINT uq_statement_versions_statement_id_version_no UNIQUE (statement_id, version_no),
    CONSTRAINT uq_statement_versions_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT uq_statement_versions_workspace_id_statement_id_id
        UNIQUE (workspace_id, statement_id, id),
    CONSTRAINT fk_statement_versions_statement_id
        FOREIGN KEY (workspace_id, statement_id) REFERENCES statements (workspace_id, id),
    CONSTRAINT ck_statement_versions_source_kind
        CHECK (source_kind IN ('pdf', 'email', 'screenshot', 'csv', 'manual', 'correction')),
    CONSTRAINT ck_statement_versions_version_no_positive CHECK (version_no >= 1)
)
""",
    # current_version_id must be one of this statement's own versions. Deferred so that a
    # statement and its first version can be written in either order inside a transaction.
    """
ALTER TABLE statements ADD CONSTRAINT fk_statements_id_current_version_id
    FOREIGN KEY (workspace_id, id, current_version_id)
    REFERENCES statement_versions (workspace_id, statement_id, id)
    DEFERRABLE INITIALLY DEFERRED
""",
    f"""
CREATE TABLE statement_lines (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    statement_version_id UUID NOT NULL,
    line_no INTEGER NOT NULL,
    kind TEXT NOT NULL,
    description TEXT,
    txn_on DATE,
    posted_on DATE,
    amount_minor BIGINT NOT NULL,
    card_last4 CHAR(4),
    transaction_id UUID,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),{_SYNC}
    CONSTRAINT pk_statement_lines PRIMARY KEY (id),
    CONSTRAINT uq_statement_lines_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT uq_statement_lines_statement_version_id_line_no
        UNIQUE (statement_version_id, line_no),
    CONSTRAINT fk_statement_lines_statement_version_id
        FOREIGN KEY (workspace_id, statement_version_id)
        REFERENCES statement_versions (workspace_id, id),
    CONSTRAINT fk_statement_lines_transaction_id
        FOREIGN KEY (workspace_id, transaction_id) REFERENCES transactions (workspace_id, id),
    CONSTRAINT ck_statement_lines_line_no_positive CHECK (line_no >= 1),
    CONSTRAINT ck_statement_lines_card_last4_digits CHECK (card_last4 ~ '^[0-9]{{4}}$')
)
""",
    "CREATE INDEX ix_statement_lines_transaction_id ON statement_lines (transaction_id)",
    f"""
CREATE TABLE statement_attributions (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    transaction_id UUID NOT NULL,
    statement_id UUID NOT NULL,
    confirmation_level TEXT NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),{_SYNC}
    CONSTRAINT pk_statement_attributions PRIMARY KEY (id),
    CONSTRAINT uq_statement_attributions_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT uq_statement_attributions_transaction_id_statement_id
        UNIQUE (transaction_id, statement_id),
    CONSTRAINT fk_statement_attributions_transaction_id
        FOREIGN KEY (workspace_id, transaction_id) REFERENCES transactions (workspace_id, id),
    CONSTRAINT fk_statement_attributions_statement_id
        FOREIGN KEY (workspace_id, statement_id) REFERENCES statements (workspace_id, id),
    CONSTRAINT ck_statement_attributions_confirmation_level
        CHECK (confirmation_level IN {_CONFIRMATION})
)
""",
    "CREATE INDEX ix_statement_attributions_statement_id ON statement_attributions (statement_id)",
    f"""
CREATE TABLE installment_plans (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    transaction_id UUID NOT NULL,
    principal_minor BIGINT NOT NULL,
    periods SMALLINT NOT NULL,
    per_period_rate NUMERIC(20, 10) NOT NULL,
    fee_mode TEXT NOT NULL,
    remainder_policy TEXT NOT NULL DEFAULT 'last',
    rounding TEXT NOT NULL DEFAULT 'HALF_UP',
    status TEXT NOT NULL,
    early_settled_at TIMESTAMPTZ,{_SYNC}
    CONSTRAINT pk_installment_plans PRIMARY KEY (id),
    CONSTRAINT uq_installment_plans_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_installment_plans_transaction_id
        FOREIGN KEY (workspace_id, transaction_id) REFERENCES transactions (workspace_id, id),
    CONSTRAINT ck_installment_plans_principal_positive CHECK (principal_minor > 0),
    CONSTRAINT ck_installment_plans_periods_positive CHECK (periods >= 1),
    CONSTRAINT ck_installment_plans_rate_non_negative CHECK (per_period_rate >= 0),
    CONSTRAINT ck_installment_plans_fee_mode CHECK (fee_mode IN ('per_period', 'upfront')),
    CONSTRAINT ck_installment_plans_remainder_policy
        CHECK (remainder_policy IN ('last', 'first')),
    -- The rounding modes the planner engine implements (money.ROUNDING).
    CONSTRAINT ck_installment_plans_rounding
        CHECK (rounding IN ('HALF_UP', 'DOWN', 'HALF_EVEN', 'UP'))
)
""",
    # transactions ||--o| installment_plans: at most one live plan per transaction.
    "CREATE UNIQUE INDEX uq_installment_plans_transaction_id ON installment_plans "
    "(transaction_id) WHERE deleted_at IS NULL",
    f"""
CREATE TABLE installment_schedule (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    plan_id UUID NOT NULL,
    period_no SMALLINT NOT NULL,
    principal_minor BIGINT NOT NULL,
    interest_minor BIGINT NOT NULL DEFAULT 0,
    statement_date DATE NOT NULL,
    due_date DATE NOT NULL,
    status TEXT NOT NULL,{_SYNC}
    CONSTRAINT pk_installment_schedule PRIMARY KEY (id),
    CONSTRAINT uq_installment_schedule_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT uq_installment_schedule_plan_id_period_no UNIQUE (plan_id, period_no),
    CONSTRAINT fk_installment_schedule_plan_id
        FOREIGN KEY (workspace_id, plan_id) REFERENCES installment_plans (workspace_id, id),
    CONSTRAINT ck_installment_schedule_period_no_positive CHECK (period_no >= 1),
    CONSTRAINT ck_installment_schedule_principal_non_negative CHECK (principal_minor >= 0),
    CONSTRAINT ck_installment_schedule_interest_non_negative CHECK (interest_minor >= 0),
    CONSTRAINT ck_installment_schedule_due_after_statement CHECK (due_date > statement_date)
)
""",
    f"""
CREATE TABLE charges (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    currency_account_id UUID NOT NULL,
    statement_id UUID,
    transaction_id UUID,
    kind TEXT NOT NULL,
    amount_minor BIGINT NOT NULL,
    currency CHAR(3) NOT NULL,
    charged_on DATE NOT NULL,
    details JSONB NOT NULL DEFAULT '{{}}'::jsonb,
    source_kind TEXT NOT NULL,
    confirmation_level TEXT NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),{_SYNC}
    CONSTRAINT pk_charges PRIMARY KEY (id),
    CONSTRAINT uq_charges_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_charges_currency_account_id
        FOREIGN KEY (workspace_id, currency_account_id)
        REFERENCES currency_accounts (workspace_id, id),
    CONSTRAINT fk_charges_statement_id
        FOREIGN KEY (workspace_id, statement_id) REFERENCES statements (workspace_id, id),
    CONSTRAINT fk_charges_transaction_id
        FOREIGN KEY (workspace_id, transaction_id) REFERENCES transactions (workspace_id, id),
    CONSTRAINT fk_charges_currency FOREIGN KEY (currency) REFERENCES currencies (code),
    CONSTRAINT ck_charges_confirmation_level CHECK (confirmation_level IN {_CONFIRMATION})
)
""",
    "CREATE INDEX ix_charges_currency_account_id ON charges (currency_account_id)",
]

# ---------------------------------------------------------------------------------------
# Group 5 (part 1) - cash accounts, snapshots, recurring items, repayments
# ---------------------------------------------------------------------------------------
CASH: list[str] = [
    f"""
CREATE TABLE cash_accounts (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    name TEXT NOT NULL,
    currency CHAR(3) NOT NULL,
    kind TEXT NOT NULL,
    usable_for_repayment BOOLEAN NOT NULL DEFAULT true,
    available_from DATE,
    reserve_floor_minor BIGINT NOT NULL DEFAULT 0,{_SYNC}
    CONSTRAINT pk_cash_accounts PRIMARY KEY (id),
    CONSTRAINT uq_cash_accounts_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_cash_accounts_workspace_id FOREIGN KEY (workspace_id) REFERENCES workspaces (id),
    CONSTRAINT fk_cash_accounts_currency FOREIGN KEY (currency) REFERENCES currencies (code),
    CONSTRAINT ck_cash_accounts_kind CHECK (kind IN ('bank', 'wallet', 'wealth', 'restricted')),
    CONSTRAINT ck_cash_accounts_reserve_floor_non_negative CHECK (reserve_floor_minor >= 0)
)
""",
    f"""
CREATE TABLE cash_balance_snapshots (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    cash_account_id UUID NOT NULL,
    balance_minor BIGINT NOT NULL,
    balance_as_of DATE NOT NULL,
    observed_at TIMESTAMPTZ NOT NULL,
    source_kind TEXT NOT NULL,
    confirmation_level TEXT NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),{_SYNC}
    CONSTRAINT pk_cash_balance_snapshots PRIMARY KEY (id),
    CONSTRAINT uq_cash_balance_snapshots_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_cash_balance_snapshots_cash_account_id
        FOREIGN KEY (workspace_id, cash_account_id) REFERENCES cash_accounts (workspace_id, id),
    CONSTRAINT ck_cash_balance_snapshots_confirmation_level
        CHECK (confirmation_level IN {_CONFIRMATION})
)
""",
    "CREATE INDEX ix_cash_balance_snapshots_cash_account_id_balance_as_of "
    "ON cash_balance_snapshots (cash_account_id, balance_as_of)",
    f"""
CREATE TABLE recurring_items (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    cash_account_id UUID NOT NULL,
    label TEXT NOT NULL,
    category TEXT NOT NULL,
    amount_minor BIGINT NOT NULL,                 -- signed like cash_events: negative = outflow
    cls TEXT NOT NULL,
    recurrence JSONB NOT NULL,
    starts_on DATE NOT NULL,
    ends_on DATE,{_SYNC}
    CONSTRAINT pk_recurring_items PRIMARY KEY (id),
    CONSTRAINT uq_recurring_items_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_recurring_items_cash_account_id
        FOREIGN KEY (workspace_id, cash_account_id) REFERENCES cash_accounts (workspace_id, id),
    CONSTRAINT ck_recurring_items_category CHECK (category IN {_CASH_CATEGORIES}),
    CONSTRAINT ck_recurring_items_cls CHECK (cls IN ('confirmed', 'expected', 'planned')),
    CONSTRAINT ck_recurring_items_ends_after_start CHECK (ends_on IS NULL OR ends_on >= starts_on)
)
""",
    "CREATE INDEX ix_recurring_items_cash_account_id ON recurring_items (cash_account_id)",
    """
CREATE TABLE repayments (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    currency_account_id UUID NOT NULL,
    cash_account_id UUID,
    amount_minor BIGINT NOT NULL,
    currency CHAR(3) NOT NULL,
    status TEXT NOT NULL,
    method TEXT,
    payment_initiated_at TIMESTAMPTZ,
    cash_debited_at TIMESTAMPTZ,
    credit_posted_at TIMESTAMPTZ,
    bank_confirmed_at TIMESTAMPTZ,
    evidence_document_id UUID,
    origin_device_id UUID,
    row_version BIGINT NOT NULL DEFAULT 1,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT pk_repayments PRIMARY KEY (id),
    CONSTRAINT uq_repayments_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_repayments_currency_account_id
        FOREIGN KEY (workspace_id, currency_account_id)
        REFERENCES currency_accounts (workspace_id, id),
    CONSTRAINT fk_repayments_cash_account_id
        FOREIGN KEY (workspace_id, cash_account_id) REFERENCES cash_accounts (workspace_id, id),
    CONSTRAINT fk_repayments_currency FOREIGN KEY (currency) REFERENCES currencies (code),
    CONSTRAINT ck_repayments_amount_positive CHECK (amount_minor > 0),
    CONSTRAINT ck_repayments_status
        CHECK (status IN ('recorded', 'processing', 'cash_debited', 'credit_posted',
                          'bank_confirmed', 'failed', 'user_marked_paid', 'needs_review',
                          'reversed')),
    CONSTRAINT ck_repayments_bank_confirmed_needs_timestamp
        CHECK (status <> 'bank_confirmed' OR bank_confirmed_at IS NOT NULL)
)
""",
    "CREATE INDEX ix_repayments_currency_account_id ON repayments (currency_account_id)",
    f"""
CREATE TABLE repayment_allocations (
    id UUID NOT NULL DEFAULT uuidv7(),
    repayment_id UUID NOT NULL,
    statement_id UUID NOT NULL,
    workspace_id UUID NOT NULL,
    amount_minor BIGINT NOT NULL,{_SYNC}
    CONSTRAINT pk_repayment_allocations PRIMARY KEY (repayment_id, statement_id),
    CONSTRAINT uq_repayment_allocations_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_repayment_allocations_repayment_id
        FOREIGN KEY (workspace_id, repayment_id) REFERENCES repayments (workspace_id, id),
    CONSTRAINT fk_repayment_allocations_statement_id
        FOREIGN KEY (workspace_id, statement_id) REFERENCES statements (workspace_id, id),
    CONSTRAINT ck_repayment_allocations_amount_positive CHECK (amount_minor > 0)
)
""",
    "CREATE INDEX ix_repayment_allocations_statement_id ON repayment_allocations (statement_id)",
]

# ---------------------------------------------------------------------------------------
# Group 6 - documents, parsing, import batches, dedupe keys
# ---------------------------------------------------------------------------------------
IMPORTS: list[str] = [
    """
CREATE TABLE source_documents (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    sha256 CHAR(64) NOT NULL,
    mime TEXT NOT NULL,
    size_bytes BIGINT NOT NULL,
    storage_key TEXT NOT NULL,
    dek_wrapped BYTEA NOT NULL,
    uploaded_by_device_id UUID,
    retention_until DATE,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    row_version BIGINT NOT NULL DEFAULT 1,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    origin_device_id UUID,
    CONSTRAINT pk_source_documents PRIMARY KEY (id),
    CONSTRAINT uq_source_documents_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT uq_source_documents_workspace_id_sha256 UNIQUE (workspace_id, sha256),
    CONSTRAINT fk_source_documents_workspace_id
        FOREIGN KEY (workspace_id) REFERENCES workspaces (id),
    CONSTRAINT ck_source_documents_sha256_hex CHECK (sha256 ~ '^[0-9a-f]{64}$'),
    CONSTRAINT ck_source_documents_size_limit CHECK (size_bytes > 0 AND size_bytes <= 26214400)
)
""",
    """
CREATE TABLE import_batches (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    kind TEXT NOT NULL,
    status TEXT NOT NULL,
    target_currency_account_id UUID,
    source_document_id UUID,
    failure_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    confirmed_at TIMESTAMPTZ,
    posted_at TIMESTAMPTZ,
    rolled_back_at TIMESTAMPTZ,
    CONSTRAINT pk_import_batches PRIMARY KEY (id),
    CONSTRAINT uq_import_batches_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_import_batches_workspace_id FOREIGN KEY (workspace_id) REFERENCES workspaces (id),
    CONSTRAINT fk_import_batches_target_currency_account_id
        FOREIGN KEY (workspace_id, target_currency_account_id)
        REFERENCES currency_accounts (workspace_id, id),
    CONSTRAINT ck_import_batches_status
        CHECK (status IN ('uploaded', 'parsing', 'needs_review', 'confirmed', 'posted', 'failed',
                          'rolled_back'))
)
""",
    """
CREATE TABLE parse_jobs (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    source_document_id UUID NOT NULL,
    import_batch_id UUID,
    job_id UUID,
    parser TEXT,
    parser_version TEXT,
    status TEXT NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    failure_reason TEXT,
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_parse_jobs PRIMARY KEY (id),
    CONSTRAINT uq_parse_jobs_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_parse_jobs_source_document_id
        FOREIGN KEY (workspace_id, source_document_id)
        REFERENCES source_documents (workspace_id, id),
    CONSTRAINT fk_parse_jobs_import_batch_id
        FOREIGN KEY (workspace_id, import_batch_id) REFERENCES import_batches (workspace_id, id),
    CONSTRAINT ck_parse_jobs_attempts_non_negative CHECK (attempts >= 0)
)
""",
    "CREATE INDEX ix_parse_jobs_source_document_id ON parse_jobs (source_document_id)",
    """
CREATE TABLE extraction_candidates (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    parse_job_id UUID NOT NULL,
    field_path TEXT NOT NULL,
    raw_value TEXT,
    normalized_value TEXT,
    raw_location JSONB NOT NULL,
    parser_version TEXT NOT NULL,
    confidence NUMERIC(5, 4) NOT NULL,
    validations JSONB NOT NULL DEFAULT '[]'::jsonb,
    confirmed_value TEXT,
    confirmed_by TEXT,
    confirmed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_extraction_candidates PRIMARY KEY (id),
    CONSTRAINT uq_extraction_candidates_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_extraction_candidates_parse_job_id
        FOREIGN KEY (workspace_id, parse_job_id) REFERENCES parse_jobs (workspace_id, id),
    CONSTRAINT ck_extraction_candidates_confidence_range CHECK (confidence BETWEEN 0 AND 1)
)
""",
    "CREATE INDEX ix_extraction_candidates_parse_job_id ON extraction_candidates (parse_job_id)",
    """
CREATE TABLE import_batch_items (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    import_batch_id UUID NOT NULL,
    item_no INTEGER NOT NULL,
    entity_kind TEXT NOT NULL,
    candidate_refs JSONB NOT NULL DEFAULT '[]'::jsonb,
    decision TEXT,
    duplicate_of_id UUID,
    resulting_entity_kind TEXT,
    resulting_entity_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_import_batch_items PRIMARY KEY (id),
    CONSTRAINT uq_import_batch_items_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT uq_import_batch_items_import_batch_id_item_no UNIQUE (import_batch_id, item_no),
    CONSTRAINT fk_import_batch_items_import_batch_id
        FOREIGN KEY (workspace_id, import_batch_id) REFERENCES import_batches (workspace_id, id),
    CONSTRAINT ck_import_batch_items_item_no_positive CHECK (item_no >= 1),
    CONSTRAINT ck_import_batch_items_decision
        CHECK (decision IN ('new', 'duplicate', 'new_version', 'skip')),
    CONSTRAINT ck_import_batch_items_duplicate_needs_target
        CHECK (decision IS DISTINCT FROM 'duplicate' OR duplicate_of_id IS NOT NULL),
    CONSTRAINT ck_import_batch_items_resulting_entity_pair
        CHECK ((resulting_entity_kind IS NULL) = (resulting_entity_id IS NULL))
)
""",
    """
CREATE TABLE dedupe_keys (
    workspace_id UUID NOT NULL,
    key_hash CHAR(64) NOT NULL,
    entity_kind TEXT NOT NULL,
    entity_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_dedupe_keys PRIMARY KEY (workspace_id, key_hash),
    CONSTRAINT fk_dedupe_keys_workspace_id FOREIGN KEY (workspace_id) REFERENCES workspaces (id),
    CONSTRAINT ck_dedupe_keys_key_hash_hex CHECK (key_hash ~ '^[0-9a-f]{64}$')
)
""",
]

# ---------------------------------------------------------------------------------------
# Group 7 - scenarios, forecasts, plans and solver runs (+ plan_reservations, group 3)
# ---------------------------------------------------------------------------------------
PLANNER: list[str] = [
    f"""
CREATE TABLE scenarios (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    code TEXT NOT NULL,
    name TEXT NOT NULL,
    include_expected BOOLEAN NOT NULL DEFAULT true,
    income_delay_days INTEGER NOT NULL DEFAULT 0,
    income_scale NUMERIC(20, 10) NOT NULL DEFAULT 1,
    expense_scale NUMERIC(20, 10) NOT NULL DEFAULT 1,
    event_overrides JSONB NOT NULL DEFAULT '{{}}'::jsonb,
    same_day_order TEXT NOT NULL DEFAULT 'conservative',
    description TEXT,{_SYNC}
    CONSTRAINT pk_scenarios PRIMARY KEY (id),
    CONSTRAINT uq_scenarios_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_scenarios_workspace_id FOREIGN KEY (workspace_id) REFERENCES workspaces (id),
    CONSTRAINT ck_scenarios_income_scale_non_negative CHECK (income_scale >= 0),
    CONSTRAINT ck_scenarios_expense_scale_non_negative CHECK (expense_scale >= 0),
    CONSTRAINT ck_scenarios_same_day_order
        CHECK (same_day_order IN ('conservative', 'timestamp'))
)
""",
    f"""
CREATE TABLE forecast_runs (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    scenario_id UUID NOT NULL,
    horizon_start DATE NOT NULL,
    horizon_end DATE NOT NULL,
    input_hash TEXT NOT NULL,
    model_version TEXT NOT NULL,
    protocol_version TEXT,
    computed_locally BOOLEAN NOT NULL DEFAULT false,
    result JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),{_SYNC}
    CONSTRAINT pk_forecast_runs PRIMARY KEY (id),
    CONSTRAINT uq_forecast_runs_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_forecast_runs_scenario_id
        FOREIGN KEY (workspace_id, scenario_id) REFERENCES scenarios (workspace_id, id),
    CONSTRAINT ck_forecast_runs_horizon_order CHECK (horizon_end >= horizon_start)
)
""",
    "CREATE INDEX ix_forecast_runs_scenario_id ON forecast_runs (scenario_id)",
    f"""
CREATE TABLE plans (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    amount_minor BIGINT NOT NULL,
    currency CHAR(3) NOT NULL,
    txn_date DATE NOT NULL,
    allow_split BOOLEAN NOT NULL DEFAULT false,
    max_cards SMALLINT NOT NULL DEFAULT 1,
    min_split_minor BIGINT NOT NULL DEFAULT 1,
    payment_lead_days SMALLINT NOT NULL DEFAULT 0,
    channel TEXT NOT NULL,
    merchant TEXT,
    category TEXT,
    allow_installment BOOLEAN NOT NULL DEFAULT false,
    status TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),{_SYNC}
    CONSTRAINT pk_plans PRIMARY KEY (id),
    CONSTRAINT uq_plans_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_plans_workspace_id FOREIGN KEY (workspace_id) REFERENCES workspaces (id),
    CONSTRAINT fk_plans_currency FOREIGN KEY (currency) REFERENCES currencies (code),
    CONSTRAINT ck_plans_amount_positive CHECK (amount_minor > 0),
    CONSTRAINT ck_plans_max_cards_positive CHECK (max_cards >= 1),
    CONSTRAINT ck_plans_min_split_positive CHECK (min_split_minor >= 1),
    CONSTRAINT ck_plans_payment_lead_days_non_negative CHECK (payment_lead_days >= 0),
    -- PRD §6.5
    CONSTRAINT ck_plans_status
        CHECK (status IN ('draft', 'solving', 'solved', 'infeasible', 'unknown', 'needs_data',
                          'baseline_shortfall', 'model_invalid', 'adopted', 'linked', 'stale',
                          'cancelled'))
)
""",
    f"""
CREATE TABLE plan_runs (
    id UUID NOT NULL DEFAULT uuidv7(),           -- run_id
    workspace_id UUID NOT NULL,
    plan_id UUID NOT NULL,
    job_id UUID,
    profile TEXT NOT NULL,
    decision_scenario_id UUID NOT NULL,
    solver_status TEXT NOT NULL,
    business_status TEXT NOT NULL,
    input_hash TEXT NOT NULL,
    model_version TEXT NOT NULL,
    solver_version TEXT NOT NULL,
    protocol_version TEXT NOT NULL,
    time_limit_s NUMERIC(8, 3) NOT NULL,
    workers SMALLINT NOT NULL,
    seed INTEGER NOT NULL,
    wall_time_s NUMERIC(10, 3),
    reserve_override_minor BIGINT,
    computed_locally BOOLEAN NOT NULL DEFAULT false,
    result JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),{_SYNC}
    CONSTRAINT pk_plan_runs PRIMARY KEY (id),
    CONSTRAINT uq_plan_runs_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_plan_runs_plan_id
        FOREIGN KEY (workspace_id, plan_id) REFERENCES plans (workspace_id, id),
    CONSTRAINT fk_plan_runs_decision_scenario_id
        FOREIGN KEY (workspace_id, decision_scenario_id) REFERENCES scenarios (workspace_id, id),
    CONSTRAINT ck_plan_runs_profile
        CHECK (profile IN ('cash_safety', 'verified_benefit', 'fewer_cards')),
    CONSTRAINT ck_plan_runs_solver_status
        CHECK (solver_status IN ('OPTIMAL', 'FEASIBLE', 'INFEASIBLE', 'UNKNOWN', 'MODEL_INVALID',
                                 'NOT_RUN')),
    CONSTRAINT ck_plan_runs_business_status
        CHECK (business_status IN ('NEEDS_DATA', 'MODEL_INVALID', 'BASELINE_SHORTFALL',
                                   'INFEASIBLE', 'UNKNOWN', 'FEASIBLE_ROBUST',
                                   'CONDITIONALLY_FEASIBLE')),
    CONSTRAINT ck_plan_runs_time_limit_positive CHECK (time_limit_s > 0),
    CONSTRAINT ck_plan_runs_workers_positive CHECK (workers >= 1),
    CONSTRAINT ck_plan_runs_wall_time_non_negative CHECK (wall_time_s >= 0),
    CONSTRAINT ck_plan_runs_reserve_override_non_negative CHECK (reserve_override_minor >= 0)
)
""",
    "CREATE INDEX ix_plan_runs_plan_id_created_at ON plan_runs (plan_id, created_at)",
    f"""
CREATE TABLE plan_allocations (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    run_id UUID NOT NULL,
    currency_account_id UUID NOT NULL,
    card_id UUID,
    amount_minor BIGINT NOT NULL,
    statement_date DATE NOT NULL,
    due_date DATE NOT NULL,
    repay_on DATE NOT NULL,
    repay_from_cash_account_id UUID NOT NULL,
    buffer_days INTEGER NOT NULL,
    fee_minor BIGINT NOT NULL DEFAULT 0,
    verified_benefit_minor BIGINT NOT NULL DEFAULT 0,
    potential_benefit_minor BIGINT NOT NULL DEFAULT 0,
    cycle_assumptions JSONB NOT NULL DEFAULT '[]'::jsonb,
    alternative_cycles JSONB NOT NULL DEFAULT '[]'::jsonb,{_SYNC}
    CONSTRAINT pk_plan_allocations PRIMARY KEY (run_id, currency_account_id),
    CONSTRAINT uq_plan_allocations_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_plan_allocations_run_id
        FOREIGN KEY (workspace_id, run_id) REFERENCES plan_runs (workspace_id, id),
    CONSTRAINT fk_plan_allocations_currency_account_id
        FOREIGN KEY (workspace_id, currency_account_id)
        REFERENCES currency_accounts (workspace_id, id),
    CONSTRAINT fk_plan_allocations_card_id
        FOREIGN KEY (workspace_id, card_id) REFERENCES cards (workspace_id, id),
    CONSTRAINT fk_plan_allocations_repay_from_cash_account_id
        FOREIGN KEY (workspace_id, repay_from_cash_account_id)
        REFERENCES cash_accounts (workspace_id, id),
    CONSTRAINT ck_plan_allocations_amount_positive CHECK (amount_minor > 0),
    CONSTRAINT ck_plan_allocations_due_after_statement CHECK (due_date > statement_date),
    CONSTRAINT ck_plan_allocations_fee_non_negative CHECK (fee_minor >= 0),
    CONSTRAINT ck_plan_allocations_verified_benefit_non_negative
        CHECK (verified_benefit_minor >= 0),
    CONSTRAINT ck_plan_allocations_potential_benefit_non_negative
        CHECK (potential_benefit_minor >= 0)
)
""",
    f"""
CREATE TABLE plan_run_checks (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    run_id UUID NOT NULL,
    scenario_id UUID NOT NULL,
    ok BOOLEAN NOT NULL,
    ok_zero BOOLEAN NOT NULL,
    min_balance_by_account JSONB NOT NULL,
    min_on_by_account JSONB NOT NULL DEFAULT '{{}}'::jsonb,
    breaches JSONB NOT NULL DEFAULT '[]'::jsonb,
    assumptions JSONB NOT NULL DEFAULT '[]'::jsonb,{_SYNC}
    CONSTRAINT pk_plan_run_checks PRIMARY KEY (id),
    CONSTRAINT uq_plan_run_checks_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT uq_plan_run_checks_run_id_scenario_id UNIQUE (run_id, scenario_id),
    CONSTRAINT fk_plan_run_checks_run_id
        FOREIGN KEY (workspace_id, run_id) REFERENCES plan_runs (workspace_id, id),
    CONSTRAINT fk_plan_run_checks_scenario_id
        FOREIGN KEY (workspace_id, scenario_id) REFERENCES scenarios (workspace_id, id)
)
""",
    f"""
CREATE TABLE plan_invalidations (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    plan_id UUID NOT NULL,
    run_id UUID,
    cause TEXT NOT NULL,
    caused_by_table TEXT,
    caused_by_id UUID,
    invalidated_at TIMESTAMPTZ NOT NULL DEFAULT now(),{_SYNC}
    CONSTRAINT pk_plan_invalidations PRIMARY KEY (id),
    CONSTRAINT uq_plan_invalidations_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_plan_invalidations_plan_id
        FOREIGN KEY (workspace_id, plan_id) REFERENCES plans (workspace_id, id),
    CONSTRAINT fk_plan_invalidations_run_id
        FOREIGN KEY (workspace_id, run_id) REFERENCES plan_runs (workspace_id, id)
)
""",
    "CREATE INDEX ix_plan_invalidations_plan_id ON plan_invalidations (plan_id)",
    f"""
CREATE TABLE plan_reservations (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    plan_id UUID NOT NULL,
    run_id UUID,
    currency_account_id UUID NOT NULL,
    cash_account_id UUID,
    amount_minor BIGINT NOT NULL,
    status TEXT NOT NULL,
    linked_transaction_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),{_SYNC}
    CONSTRAINT pk_plan_reservations PRIMARY KEY (id),
    CONSTRAINT uq_plan_reservations_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_plan_reservations_plan_id
        FOREIGN KEY (workspace_id, plan_id) REFERENCES plans (workspace_id, id),
    CONSTRAINT fk_plan_reservations_run_id
        FOREIGN KEY (workspace_id, run_id) REFERENCES plan_runs (workspace_id, id),
    CONSTRAINT fk_plan_reservations_currency_account_id
        FOREIGN KEY (workspace_id, currency_account_id)
        REFERENCES currency_accounts (workspace_id, id),
    CONSTRAINT fk_plan_reservations_cash_account_id
        FOREIGN KEY (workspace_id, cash_account_id) REFERENCES cash_accounts (workspace_id, id),
    CONSTRAINT fk_plan_reservations_linked_transaction_id
        FOREIGN KEY (workspace_id, linked_transaction_id)
        REFERENCES transactions (workspace_id, id),
    CONSTRAINT ck_plan_reservations_amount_positive CHECK (amount_minor > 0),
    CONSTRAINT ck_plan_reservations_status CHECK (status IN ('active', 'converted', 'released')),
    CONSTRAINT ck_plan_reservations_converted_needs_transaction
        CHECK (status <> 'converted' OR linked_transaction_id IS NOT NULL)
)
""",
    "CREATE INDEX ix_plan_reservations_plan_id ON plan_reservations (plan_id)",
    "CREATE INDEX ix_plan_reservations_currency_account_id ON plan_reservations "
    "(currency_account_id)",
]

# ---------------------------------------------------------------------------------------
# Group 5 (part 2) - cash events and their links (need repayments and plan_runs)
# ---------------------------------------------------------------------------------------
CASH_EVENTS: list[str] = [
    f"""
CREATE TABLE cash_events (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    cash_account_id UUID NOT NULL,
    event_on DATE NOT NULL,
    event_at TIMESTAMPTZ,
    amount_minor BIGINT NOT NULL,                 -- negative = outflow
    cls TEXT NOT NULL,
    category TEXT NOT NULL,
    label TEXT,
    posting_status TEXT NOT NULL,
    recurring_item_id UUID,
    linked_repayment_id UUID,
    linked_plan_run_id UUID,{_SYNC}
    CONSTRAINT pk_cash_events PRIMARY KEY (id),
    CONSTRAINT uq_cash_events_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_cash_events_cash_account_id
        FOREIGN KEY (workspace_id, cash_account_id) REFERENCES cash_accounts (workspace_id, id),
    CONSTRAINT fk_cash_events_recurring_item_id
        FOREIGN KEY (workspace_id, recurring_item_id) REFERENCES recurring_items (workspace_id, id),
    CONSTRAINT fk_cash_events_linked_repayment_id
        FOREIGN KEY (workspace_id, linked_repayment_id) REFERENCES repayments (workspace_id, id),
    CONSTRAINT fk_cash_events_linked_plan_run_id
        FOREIGN KEY (workspace_id, linked_plan_run_id) REFERENCES plan_runs (workspace_id, id),
    CONSTRAINT ck_cash_events_cls CHECK (cls IN ('confirmed', 'expected', 'planned')),
    CONSTRAINT ck_cash_events_category CHECK (category IN {_CASH_CATEGORIES}),
    CONSTRAINT ck_cash_events_posting_status CHECK (posting_status IN ('planned', 'posted'))
)
""",
    "CREATE INDEX ix_cash_events_cash_account_id_event_on ON cash_events "
    "(cash_account_id, event_on) WHERE deleted_at IS NULL",
    "CREATE INDEX ix_cash_events_label_trgm ON cash_events USING gin (label gin_trgm_ops)",
    f"""
CREATE TABLE snapshot_included_events (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    snapshot_id UUID NOT NULL,
    cash_event_id UUID NOT NULL,{_SYNC}
    CONSTRAINT pk_snapshot_included_events PRIMARY KEY (snapshot_id, cash_event_id),
    CONSTRAINT uq_snapshot_included_events_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_snapshot_included_events_snapshot_id
        FOREIGN KEY (workspace_id, snapshot_id)
        REFERENCES cash_balance_snapshots (workspace_id, id) ON DELETE CASCADE,
    CONSTRAINT fk_snapshot_included_events_cash_event_id
        FOREIGN KEY (workspace_id, cash_event_id) REFERENCES cash_events (workspace_id, id)
)
""",
    "CREATE INDEX ix_snapshot_included_events_cash_event_id ON snapshot_included_events "
    "(cash_event_id)",
    f"""
CREATE TABLE cash_transfers (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    from_cash_account_id UUID NOT NULL,
    to_cash_account_id UUID NOT NULL,
    amount_minor BIGINT NOT NULL,
    currency CHAR(3) NOT NULL,
    sent_on DATE NOT NULL,
    arrives_on DATE,
    out_event_id UUID,
    in_event_id UUID,{_SYNC}
    CONSTRAINT pk_cash_transfers PRIMARY KEY (id),
    CONSTRAINT uq_cash_transfers_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_cash_transfers_from_cash_account_id
        FOREIGN KEY (workspace_id, from_cash_account_id)
        REFERENCES cash_accounts (workspace_id, id),
    CONSTRAINT fk_cash_transfers_to_cash_account_id
        FOREIGN KEY (workspace_id, to_cash_account_id) REFERENCES cash_accounts (workspace_id, id),
    CONSTRAINT fk_cash_transfers_out_event_id
        FOREIGN KEY (workspace_id, out_event_id) REFERENCES cash_events (workspace_id, id),
    CONSTRAINT fk_cash_transfers_in_event_id
        FOREIGN KEY (workspace_id, in_event_id) REFERENCES cash_events (workspace_id, id),
    CONSTRAINT fk_cash_transfers_currency FOREIGN KEY (currency) REFERENCES currencies (code),
    CONSTRAINT ck_cash_transfers_amount_positive CHECK (amount_minor > 0),
    CONSTRAINT ck_cash_transfers_distinct_accounts
        CHECK (from_cash_account_id <> to_cash_account_id),
    CONSTRAINT ck_cash_transfers_arrives_after_sent
        CHECK (arrives_on IS NULL OR arrives_on >= sent_on)
)
""",
    f"""
CREATE TABLE reconciliation_items (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    kind TEXT NOT NULL,
    refs JSONB NOT NULL,
    status TEXT NOT NULL,
    source_kind TEXT,
    suggested_action TEXT,
    resolution TEXT,
    resolved_by TEXT,
    resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),{_SYNC}
    CONSTRAINT pk_reconciliation_items PRIMARY KEY (id),
    CONSTRAINT uq_reconciliation_items_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_reconciliation_items_workspace_id
        FOREIGN KEY (workspace_id) REFERENCES workspaces (id),
    CONSTRAINT ck_reconciliation_items_kind
        CHECK (kind IN ('amount_mismatch', 'missing', 'duplicate_txn', 'duplicate_repayment',
                        'refund_pending', 'unmatched_repayment', 'sync_conflict'))
)
""",
    "CREATE INDEX ix_reconciliation_items_workspace_id_status ON reconciliation_items "
    "(workspace_id, status)",
]

# ---------------------------------------------------------------------------------------
# Group 10 (subset) - sync, audit, deletion, jobs, worker heartbeats
# ---------------------------------------------------------------------------------------
OPERATIONS: list[str] = [
    """
CREATE TABLE sync_changes (
    seq BIGSERIAL NOT NULL,
    workspace_id UUID NOT NULL,
    table_name TEXT NOT NULL,
    row_id UUID NOT NULL,
    op TEXT NOT NULL,
    row_version BIGINT NOT NULL,
    payload JSONB,
    origin_device_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_sync_changes PRIMARY KEY (seq),
    CONSTRAINT fk_sync_changes_workspace_id FOREIGN KEY (workspace_id) REFERENCES workspaces (id),
    CONSTRAINT ck_sync_changes_op CHECK (op IN ('insert', 'update', 'delete'))
)
""",
    "CREATE INDEX ix_sync_changes_workspace_id_seq ON sync_changes (workspace_id, seq)",
    """
CREATE TABLE sync_conflicts (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    origin_device_id UUID,
    table_name TEXT NOT NULL,
    row_id UUID NOT NULL,
    server_version BIGINT NOT NULL,
    client_base_version BIGINT NOT NULL,
    fields JSONB NOT NULL DEFAULT '[]'::jsonb,
    server_payload JSONB NOT NULL,
    client_payload JSONB NOT NULL,
    status TEXT NOT NULL,
    resolved_by TEXT,
    resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_sync_conflicts PRIMARY KEY (id),
    CONSTRAINT uq_sync_conflicts_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT fk_sync_conflicts_workspace_id FOREIGN KEY (workspace_id) REFERENCES workspaces (id)
)
""",
    "CREATE INDEX ix_sync_conflicts_workspace_id_table_name_row_id ON sync_conflicts "
    "(workspace_id, table_name, row_id)",
    """
CREATE TABLE audit_log (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID,
    actor_kind TEXT NOT NULL,
    actor_id UUID,
    action TEXT NOT NULL,
    target_table TEXT,
    target_id UUID,
    before_hash CHAR(64),
    after_hash CHAR(64),
    ip INET,
    at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_audit_log PRIMARY KEY (id),
    CONSTRAINT ck_audit_log_before_hash_hex CHECK (before_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT ck_audit_log_after_hash_hex CHECK (after_hash ~ '^[0-9a-f]{64}$')
)
""",
    "CREATE INDEX ix_audit_log_workspace_id_at ON audit_log (workspace_id, at)",
    "CREATE INDEX ix_audit_log_at ON audit_log (at)",
    """
CREATE TABLE deletion_tasks (
    id UUID NOT NULL DEFAULT uuidv7(),
    workspace_id UUID NOT NULL,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    grace_until TIMESTAMPTZ NOT NULL,
    status TEXT NOT NULL,
    executed_at TIMESTAMPTZ,
    CONSTRAINT pk_deletion_tasks PRIMARY KEY (id),
    CONSTRAINT uq_deletion_tasks_workspace_id_id UNIQUE (workspace_id, id),
    CONSTRAINT ck_deletion_tasks_grace_after_request CHECK (grace_until >= requested_at)
)
""",
    "CREATE INDEX ix_deletion_tasks_status_grace_until ON deletion_tasks (status, grace_until)",
    """
CREATE TABLE jobs (
    id UUID NOT NULL DEFAULT uuidv7(),
    kind TEXT NOT NULL,
    payload JSONB NOT NULL,
    status TEXT NOT NULL DEFAULT 'queued',
    run_after TIMESTAMPTZ NOT NULL DEFAULT now(),
    attempts INTEGER NOT NULL DEFAULT 0,
    max_attempts INTEGER NOT NULL DEFAULT 5,
    locked_by TEXT,
    locked_until TIMESTAMPTZ,
    heartbeat_at TIMESTAMPTZ,
    timeout_s INTEGER,
    last_error TEXT,
    result JSONB,
    workspace_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at TIMESTAMPTZ,
    CONSTRAINT pk_jobs PRIMARY KEY (id),
    CONSTRAINT ck_jobs_status
        CHECK (status IN ('queued', 'running', 'succeeded', 'failed', 'dead')),
    CONSTRAINT ck_jobs_attempts_non_negative CHECK (attempts >= 0),
    CONSTRAINT ck_jobs_max_attempts_positive CHECK (max_attempts >= 1),
    CONSTRAINT ck_jobs_timeout_positive CHECK (timeout_s > 0),
    CONSTRAINT ck_jobs_running_has_lease
        CHECK (status <> 'running' OR (locked_by IS NOT NULL AND locked_until IS NOT NULL))
)
""",
    "CREATE INDEX ix_jobs_status_run_after ON jobs (status, run_after) WHERE status = 'queued'",
    """
CREATE TABLE worker_heartbeats (
    worker_id TEXT NOT NULL,
    hostname TEXT NOT NULL,
    pid INTEGER NOT NULL,
    version TEXT NOT NULL,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    running_jobs INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT pk_worker_heartbeats PRIMARY KEY (worker_id),
    CONSTRAINT ck_worker_heartbeats_running_jobs_non_negative CHECK (running_jobs >= 0)
)
""",
    "CREATE INDEX ix_worker_heartbeats_last_seen_at ON worker_heartbeats (last_seen_at)",
]

# ---------------------------------------------------------------------------------------
# Constraint functions and triggers (T-007)
# ---------------------------------------------------------------------------------------
TRIGGERS: list[str] = [
    # --- statement_versions: bank originals are append-only (data-model §4, R-STMT-07) ---
    # Any UPDATE that names one of these columns is rejected, even if the value would not
    # change: corrections are a new version (statement_versions.version_no + 1).
    """
CREATE FUNCTION forbid_amount_update() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'statement_versions amounts are append-only; insert a new version'
        USING ERRCODE = 'integrity_constraint_violation',
              TABLE = TG_TABLE_NAME,
              CONSTRAINT = TG_NAME;
END
$$
""",
    """
CREATE TRIGGER statement_versions_append_only
    BEFORE UPDATE OF previous_balance_minor, new_balance_minor, min_due_minor, payments_minor,
                     credits_minor, fees_minor, interest_minor, installment_due_minor,
                     credit_balance_minor, due_date
    ON statement_versions FOR EACH ROW EXECUTE FUNCTION forbid_amount_update()
""",
    # DELETE / TRUNCATE are rejected unless the current transaction opted in with
    #     SELECT set_config('app.purge', 'on', true);
    # (transaction-local, cleared at COMMIT/ROLLBACK). This is reserved for the future
    # workspace-deletion task (deletion_tasks, data-model §9); everything else tombstones
    # rows with deleted_at instead.
    """
CREATE FUNCTION forbid_statement_version_delete() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('app.purge', true) = 'on' THEN
        RETURN OLD;
    END IF;
    RAISE EXCEPTION 'statement_versions rows are never deleted; set deleted_at instead'
        USING ERRCODE = 'integrity_constraint_violation',
              TABLE = TG_TABLE_NAME,
              CONSTRAINT = TG_NAME,
              HINT = 'A workspace purge runs SELECT set_config(''app.purge'', ''on'', true) '
                     || 'in the same transaction first.';
END
$$
""",
    """
CREATE TRIGGER statement_versions_no_delete
    BEFORE DELETE ON statement_versions
    FOR EACH ROW EXECUTE FUNCTION forbid_statement_version_delete()
""",
    """
CREATE TRIGGER statement_versions_no_truncate
    BEFORE TRUNCATE ON statement_versions
    FOR EACH STATEMENT EXECUTE FUNCTION forbid_statement_version_delete()
""",
    # --- repayment_allocations: SUM(active allocations) <= repayments.amount_minor and same
    # currency account; checked at COMMIT (DEFERRABLE INITIALLY DEFERRED) so a transaction
    # may pass through an intermediate over-allocation and fix it before committing.
    # The repayment row is locked (FOR NO KEY UPDATE) so concurrent READ COMMITTED
    # transactions validate one after the other and see each other's committed rows.
    # Soft-deleted allocations (deleted_at IS NOT NULL) do not count.
    """
CREATE FUNCTION check_repayment_allocations(p_repayment_id uuid) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    v_amount bigint;
    v_currency_account_id uuid;
    v_allocated numeric;
BEGIN
    SELECT r.amount_minor, r.currency_account_id
      INTO v_amount, v_currency_account_id
      FROM repayments AS r
     WHERE r.id = p_repayment_id
       FOR NO KEY UPDATE;
    IF NOT FOUND THEN
        RETURN;  -- the repayment itself is gone; foreign keys report orphans
    END IF;

    SELECT coalesce(sum(a.amount_minor), 0)
      INTO v_allocated
      FROM repayment_allocations AS a
     WHERE a.repayment_id = p_repayment_id
       AND a.deleted_at IS NULL;
    IF v_allocated > v_amount THEN
        RAISE EXCEPTION 'repayment allocations exceed the repayment amount'
            USING ERRCODE = 'check_violation',
                  TABLE = 'repayment_allocations',
                  CONSTRAINT = 'repayment_allocations_within_amount';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM repayment_allocations AS a
          JOIN statements AS s ON s.id = a.statement_id
         WHERE a.repayment_id = p_repayment_id
           AND a.deleted_at IS NULL
           AND s.currency_account_id <> v_currency_account_id
    ) THEN
        RAISE EXCEPTION 'repayment allocated to a statement of another currency account'
            USING ERRCODE = 'check_violation',
                  TABLE = 'repayment_allocations',
                  CONSTRAINT = 'repayment_allocations_same_currency_account';
    END IF;
END
$$
""",
    """
CREATE FUNCTION repayment_allocations_check() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM check_repayment_allocations(NEW.repayment_id);
    RETURN NULL;
END
$$
""",
    """
CREATE CONSTRAINT TRIGGER repayment_allocations_within_amount
    AFTER INSERT OR UPDATE ON repayment_allocations
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION repayment_allocations_check()
""",
    """
CREATE FUNCTION repayments_allocation_check() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM check_repayment_allocations(NEW.id);
    RETURN NULL;
END
$$
""",
    """
CREATE CONSTRAINT TRIGGER repayments_allocations_within_amount
    AFTER UPDATE OF amount_minor, currency_account_id ON repayments
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION repayments_allocation_check()
""",
    """
CREATE FUNCTION statements_allocation_check() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_repayment_id uuid;
BEGIN
    FOR v_repayment_id IN
        SELECT DISTINCT a.repayment_id FROM repayment_allocations AS a WHERE a.statement_id = NEW.id
    LOOP
        PERFORM check_repayment_allocations(v_repayment_id);
    END LOOP;
    RETURN NULL;
END
$$
""",
    """
CREATE CONSTRAINT TRIGGER statements_allocations_same_currency_account
    AFTER UPDATE OF currency_account_id ON statements
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION statements_allocation_check()
""",
    # --- template scope: a reference to banks / card_products / billing_rule_versions must
    # point at an official template (workspace_id IS NULL) or at a row of the referencing
    # row's own workspace. Plain foreign keys cannot express this. The lookup filters on
    # the scope itself instead of reading the target's workspace_id, so it stays correct
    # when row-level security hides other workspaces' rows from the caller.
    """
CREATE FUNCTION check_template_scope() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_column text := TG_ARGV[0];
    v_table text := TG_ARGV[1];
    v_ref uuid;
    v_ok boolean;
BEGIN
    EXECUTE format('SELECT ($1).%I', v_column) INTO v_ref USING NEW;
    IF v_ref IS NULL THEN
        RETURN NEW;
    END IF;
    EXECUTE format(
        'SELECT EXISTS (SELECT 1 FROM %I AS t WHERE t.id = $1 '
        'AND (t.workspace_id IS NULL OR t.workspace_id = $2))', v_table)
        INTO v_ok USING v_ref, NEW.workspace_id;
    IF NOT v_ok THEN
        RAISE EXCEPTION '%.% must reference an official template or a row of the same workspace',
                        TG_TABLE_NAME, v_column
            USING ERRCODE = 'foreign_key_violation',
                  TABLE = TG_TABLE_NAME,
                  COLUMN = v_column,
                  CONSTRAINT = TG_NAME;
    END IF;
    RETURN NEW;
END
$$
""",
    """
CREATE TRIGGER card_products_bank_scope
    BEFORE INSERT OR UPDATE OF workspace_id, bank_id ON card_products
    FOR EACH ROW EXECUTE FUNCTION check_template_scope('bank_id', 'banks')
""",
    """
CREATE TRIGGER credit_pools_bank_scope
    BEFORE INSERT OR UPDATE OF workspace_id, bank_id ON credit_pools
    FOR EACH ROW EXECUTE FUNCTION check_template_scope('bank_id', 'banks')
""",
    """
CREATE TRIGGER credit_accounts_bank_scope
    BEFORE INSERT OR UPDATE OF workspace_id, bank_id ON credit_accounts
    FOR EACH ROW EXECUTE FUNCTION check_template_scope('bank_id', 'banks')
""",
    """
CREATE TRIGGER credit_accounts_product_scope
    BEFORE INSERT OR UPDATE OF workspace_id, product_id ON credit_accounts
    FOR EACH ROW EXECUTE FUNCTION check_template_scope('product_id', 'card_products')
""",
    """
CREATE TRIGGER rule_bindings_rule_version_scope
    BEFORE INSERT OR UPDATE OF workspace_id, billing_rule_version_id ON rule_bindings
    FOR EACH ROW EXECUTE FUNCTION check_template_scope('billing_rule_version_id',
                                                       'billing_rule_versions')
""",
    # billing_rule_versions.subject_id is polymorphic (subject_kind), so no foreign key:
    # the subject must exist and be a template product or a row of the same workspace.
    """
CREATE FUNCTION check_rule_subject_scope() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_ok boolean;
BEGIN
    IF NEW.subject_kind = 'product' THEN
        SELECT EXISTS (
            SELECT 1 FROM card_products AS p
             WHERE p.id = NEW.subject_id
               AND (p.workspace_id IS NULL OR p.workspace_id = NEW.workspace_id)
        ) INTO v_ok;
    ELSIF NEW.subject_kind = 'credit_account' THEN
        SELECT EXISTS (
            SELECT 1 FROM credit_accounts AS c
             WHERE c.id = NEW.subject_id AND c.workspace_id = NEW.workspace_id
        ) INTO v_ok;
    ELSE
        SELECT EXISTS (
            SELECT 1 FROM currency_accounts AS c
             WHERE c.id = NEW.subject_id AND c.workspace_id = NEW.workspace_id
        ) INTO v_ok;
    END IF;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'billing_rule_versions.subject_id: no % in this scope',
                        NEW.subject_kind
            USING ERRCODE = 'foreign_key_violation',
                  TABLE = TG_TABLE_NAME,
                  COLUMN = 'subject_id',
                  CONSTRAINT = TG_NAME;
    END IF;
    RETURN NEW;
END
$$
""",
    """
CREATE TRIGGER billing_rule_versions_subject_scope
    BEFORE INSERT OR UPDATE OF workspace_id, subject_kind, subject_id ON billing_rule_versions
    FOR EACH ROW EXECUTE FUNCTION check_rule_subject_scope()
""",
    # Moving a template into a workspace (or back) would silently re-scope every row that
    # references it, so workspace_id of the template-capable tables is immutable.
    """
CREATE FUNCTION forbid_workspace_change() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.workspace_id IS DISTINCT FROM OLD.workspace_id THEN
        RAISE EXCEPTION '%.workspace_id cannot change', TG_TABLE_NAME
            USING ERRCODE = 'integrity_constraint_violation',
                  TABLE = TG_TABLE_NAME,
                  COLUMN = 'workspace_id',
                  CONSTRAINT = TG_NAME;
    END IF;
    RETURN NEW;
END
$$
""",
    """
CREATE TRIGGER banks_workspace_immutable
    BEFORE UPDATE OF workspace_id ON banks
    FOR EACH ROW EXECUTE FUNCTION forbid_workspace_change()
""",
    """
CREATE TRIGGER card_products_workspace_immutable
    BEFORE UPDATE OF workspace_id ON card_products
    FOR EACH ROW EXECUTE FUNCTION forbid_workspace_change()
""",
    """
CREATE TRIGGER billing_rule_versions_workspace_immutable
    BEFORE UPDATE OF workspace_id ON billing_rule_versions
    FOR EACH ROW EXECUTE FUNCTION forbid_workspace_change()
""",
]

UPGRADE: list[str] = [
    *EXTENSIONS,
    *IDENTITY,
    *BANKING,
    *LIMITS,
    *STATEMENTS,
    *CASH,
    *IMPORTS,
    *PLANNER,
    *CASH_EVENTS,
    *OPERATIONS,
    *TRIGGERS,
]

# Reverse creation order. No CASCADE: an unexpected dependency (for example a policy or
# view left behind by a later revision) must make the downgrade fail loudly.
TABLES_IN_DROP_ORDER: tuple[str, ...] = (
    "worker_heartbeats",
    "jobs",
    "deletion_tasks",
    "audit_log",
    "sync_conflicts",
    "sync_changes",
    "reconciliation_items",
    "cash_transfers",
    "snapshot_included_events",
    "cash_events",
    "plan_reservations",
    "plan_invalidations",
    "plan_run_checks",
    "plan_allocations",
    "plan_runs",
    "plans",
    "forecast_runs",
    "scenarios",
    "dedupe_keys",
    "import_batch_items",
    "extraction_candidates",
    "parse_jobs",
    "import_batches",
    "source_documents",
    "repayment_allocations",
    "repayments",
    "recurring_items",
    "cash_balance_snapshots",
    "cash_accounts",
    "charges",
    "installment_schedule",
    "installment_plans",
    "statement_attributions",
    "statement_lines",
    "statement_versions",
    "statements",
    "preauth_holds",
    "transaction_links",
    "transactions",
    "limit_adjustments",
    "limit_snapshots",
    "rule_bindings",
    "billing_rule_versions",
    "cards",
    "currency_accounts",
    "credit_pool_members",
    "credit_accounts",
    "credit_pools",
    "card_products",
    "banks",
    "currencies",
    "idempotency_keys",
    "consents",
    "auth_sessions",
    "devices",
    "workspace_members",
    "workspaces",
    "users",
)

FUNCTIONS_IN_DROP_ORDER: tuple[str, ...] = (
    "forbid_workspace_change()",
    "check_rule_subject_scope()",
    "check_template_scope()",
    "statements_allocation_check()",
    "repayments_allocation_check()",
    "repayment_allocations_check()",
    "check_repayment_allocations(uuid)",
    "forbid_statement_version_delete()",
    "forbid_amount_update()",
)

DOWNGRADE: list[str] = [
    # statements <-> statement_versions reference each other; break the cycle first.
    "ALTER TABLE statements DROP CONSTRAINT fk_statements_id_current_version_id",
    *(f"DROP TABLE {table}" for table in TABLES_IN_DROP_ORDER),
    *(f"DROP FUNCTION {signature}" for signature in FUNCTIONS_IN_DROP_ORDER),
    # btree_gist / pg_trgm stay: environment prerequisite (R2-23, module docstring).
]


def upgrade() -> None:
    """Create the initial schema."""
    for statement in UPGRADE:
        op.execute(statement)


def downgrade() -> None:
    """Drop everything :func:`upgrade` created except the extensions (environment
    prerequisite, R2-23); the currencies seed goes with its table."""
    for statement in DOWNGRADE:
        op.execute(statement)
