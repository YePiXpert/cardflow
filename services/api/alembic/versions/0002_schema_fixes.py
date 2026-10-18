"""Post-review structural fixes (M0 review wave 2, data-model §10).

Revision ID: 0002
Revises: 0001
Create Date: 2026-10-17

Implements the rulings of data-model §10 for evidence/m0/review-wave2-schema.md. 0001 is
not modified; everything is expressed here and reverted exactly by downgrade() (the
0001 function and trigger bodies are restored verbatim from V0001_FUNCTIONS /
V0001_TRIGGERS). Row-level security, roles and grants follow in 0003 (T-006).

What changes (R2 = review finding):

* R2-01  Every trigger/check function runs with ``SET search_path = pg_catalog, public,
         pg_temp`` and qualifies tables with ``public.``: session temp tables can no longer
         shadow the lookups.
* R2-02  Allocation sums live in repayment_allocation_totals (maintained row by row by
         trigger). The deferred check *writes* that row, so concurrent allocators conflict
         in every isolation level (READ COMMITTED waits and re-reads; REPEATABLE READ and
         SERIALIZABLE fail with 40001) instead of relying on READ COMMITTED.
* R2-03/19  statement_versions, statement_lines, plan_runs, plan_allocations and
         plan_run_checks are immutable except for the one-time tombstone
         (deleted_at NULL -> NOT NULL). limit_snapshots / cash_balance_snapshots: amount,
         time and account columns are immutable. Statement lines can only be written in
         the transaction that creates their version.
* R2-10  Physical DELETE/TRUNCATE of those facts needs the transaction-scoped purge token
         ``SELECT set_config('app.purge', pg_current_xact_id()::text, true)``; a leftover
         session-level setting or the old value 'on' no longer opens the gate.
* R2-04/05  Currency and same-account consistency by composite foreign keys onto new
         UNIQUE (workspace_id, id, currency) / (workspace_id, <account>, id) keys. Redundant
         account columns (transactions.credit_account_id, statement_versions.
         currency_account_id, ...) are derived from the parent row by BEFORE triggers
         (derive_from_parent); clients never supply them. currency_accounts.(credit_account_id,
         currency) and cash_accounts.currency are immutable.
* R2-06  Primary keys are id everywhere; natural keys (statement date, sub-account
         currency, pool membership, document fingerprint, allocation, attribution, snapshot
         inclusion, links, schedule periods, run checks) are partial unique indexes
         WHERE deleted_at IS NULL. (statement_id, version_no) stays fully unique.
* R2-07  sync_changes.txid xid8 (top-level transaction id) for a lossless pull cursor.
* R2-08  repayments: event_tz, precision of cash_debited_at / credit_posted_at,
         recorded_at; transactions.observed_at; cash_events.event_tz, recorded_at.
* R2-09  looks_like_pan(): free-text columns reject card-number-like digit runs
         (13-19 digits, single spaces/hyphens allowed, Luhn-valid).
* R2-11..18, 20, 21, 25, 26, 27, 29, 32, 33: workspace_id immutable on every tenant table;
         nil workspace id rejected; private rules cannot claim verified/published; no
         overlapping rule bindings; inactive repayments keep no live allocations; non-zero
         amounts with a sign per type/category and COMMENT ON COLUMN; status CHECKs; no
         pool / card-replacement cycles; attachment references are composite foreign keys
         (purging a document wipes the blob key, the metadata row stays); row_version /
         updated_at maintained by trigger; foreign-key indexes; idempotency_keys.created_at
         index; jobs.dedupe_key and lease-reclaim index; email/public key sanity checks.
* T-008  (coordinator, after the T-008 review) jobs.status admits 'canceled'
         (admin-console-spec AP-05; the cancel action itself comes later), and the claim
         index is ix_jobs_queued_run_after_created_at (run_after, created_at) WHERE status =
         'queued' -- the worker's ORDER BY run_after, created_at -- replacing
         ix_jobs_status_run_after (status, run_after).

Backfills only touch derived id/currency columns and the allocation totals; no money
value is updated (data-model §7).

R2-23 (extensions dropped by 0001's downgrade) needed an edit of 0001 and was resolved there
in T-006: the downgrade no longer drops extensions.
"""

from collections.abc import Sequence

from alembic import op

revision: str = "0002"
down_revision: str | Sequence[str] | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

NIL_UUID = "'00000000-0000-0000-0000-000000000000'::uuid"
TIME_PRECISIONS = "('datetime', 'date', 'month')"

# --------------------------------------------------------------------------------------
# Table and column lists (explicit; the drift and golden tests check them against the DB)
# --------------------------------------------------------------------------------------

# Tenant tables (workspace_id NOT NULL) that 0001 did not guard yet; banks, card_products
# and billing_rule_versions already have <table>_workspace_immutable from 0001.
WORKSPACE_GUARDED_TABLES: tuple[str, ...] = (
    "workspace_members",
    "devices",
    "auth_sessions",
    "consents",
    "idempotency_keys",
    "credit_pools",
    "credit_accounts",
    "credit_pool_members",
    "currency_accounts",
    "cards",
    "rule_bindings",
    "limit_snapshots",
    "limit_adjustments",
    "transactions",
    "transaction_links",
    "preauth_holds",
    "statements",
    "statement_versions",
    "statement_lines",
    "statement_attributions",
    "installment_plans",
    "installment_schedule",
    "charges",
    "cash_accounts",
    "cash_balance_snapshots",
    "recurring_items",
    "repayments",
    "repayment_allocations",
    "repayment_allocation_totals",
    "source_documents",
    "import_batches",
    "parse_jobs",
    "extraction_candidates",
    "import_batch_items",
    "dedupe_keys",
    "scenarios",
    "forecast_runs",
    "plans",
    "plan_runs",
    "plan_allocations",
    "plan_run_checks",
    "plan_invalidations",
    "plan_reservations",
    "cash_events",
    "snapshot_included_events",
    "cash_transfers",
    "reconciliation_items",
    "sync_changes",
    "sync_conflicts",
    "deletion_tasks",
)

# Tables carrying row_version / updated_at / deleted_at / origin_device_id (architecture §6).
SYNCABLE_TABLES: tuple[str, ...] = (
    "consents",
    "banks",
    "card_products",
    "credit_pools",
    "credit_accounts",
    "credit_pool_members",
    "currency_accounts",
    "cards",
    "billing_rule_versions",
    "rule_bindings",
    "limit_snapshots",
    "limit_adjustments",
    "transactions",
    "transaction_links",
    "preauth_holds",
    "statements",
    "statement_versions",
    "statement_lines",
    "statement_attributions",
    "installment_plans",
    "installment_schedule",
    "charges",
    "cash_accounts",
    "cash_balance_snapshots",
    "recurring_items",
    "repayments",
    "repayment_allocations",
    "source_documents",
    "scenarios",
    "forecast_runs",
    "plans",
    "plan_runs",
    "plan_allocations",
    "plan_run_checks",
    "plan_invalidations",
    "plan_reservations",
    "cash_events",
    "snapshot_included_events",
    "cash_transfers",
    "reconciliation_items",
)

# Bank facts and run records: whole row immutable except the one-time tombstone.
IMMUTABLE_FACT_TABLES: tuple[str, ...] = (
    "statement_versions",
    "statement_lines",
    "plan_runs",
    "plan_allocations",
    "plan_run_checks",
)
# Observations whose amount/time/account columns are immutable.
SNAPSHOT_IMMUTABLE_COLUMNS: dict[str, tuple[str, ...]] = {
    "limit_snapshots": (
        "currency_account_id",
        "fixed_minor",
        "temp_minor",
        "temp_expires_on",
        "special_minor",
        "used_minor",
        "available_raw_minor",
        "includes_holds",
        "balance_as_of",
        "observed_at",
        "recorded_at",
    ),
    "cash_balance_snapshots": (
        "cash_account_id",
        "balance_minor",
        "balance_as_of",
        "observed_at",
        "recorded_at",
    ),
}
# Physical deletion needs the transaction-scoped purge token.
PURGE_GUARDED_TABLES: tuple[str, ...] = (
    *IMMUTABLE_FACT_TABLES,
    "limit_snapshots",
    "cash_balance_snapshots",
)

# Free-text columns that must not hold a card number (R2-09, data-model §10.9).
PAN_CHECKED_COLUMNS: tuple[tuple[str, str], ...] = (
    ("users", "display_name"),
    ("devices", "name"),
    ("banks", "name"),
    ("card_products", "name"),
    ("credit_pools", "name"),
    ("credit_accounts", "holder_alias"),
    ("cards", "alias"),
    ("billing_rule_versions", "exceptions"),
    ("limit_snapshots", "special_purpose"),
    ("limit_adjustments", "purpose"),
    ("preauth_holds", "merchant"),
    ("transactions", "merchant"),
    ("transactions", "category"),
    ("statement_versions", "reason"),
    ("statement_lines", "description"),
    ("cash_accounts", "name"),
    ("cash_events", "label"),
    ("recurring_items", "label"),
    ("reconciliation_items", "suggested_action"),
    ("reconciliation_items", "resolution"),
    ("plans", "merchant"),
    ("plans", "category"),
    ("scenarios", "name"),
    ("scenarios", "description"),
    ("import_batches", "failure_reason"),
    ("parse_jobs", "failure_reason"),
)

# Status columns with a state machine (R2-17). Values not enumerated by the PRD were
# defined here; they are listed in evidence/m0/T-005/0002-r2-map.md.
STATUS_CHECKS: dict[str, str] = {
    "installment_plans": "('active', 'completed', 'early_settled', 'cancelled')",
    "installment_schedule": "('scheduled', 'billed', 'settled', 'cancelled')",
    "preauth_holds": "('active', 'captured', 'released', 'expired')",
    "parse_jobs": "('queued', 'running', 'succeeded', 'failed', 'quarantined')",
    "reconciliation_items": "('open', 'resolved', 'dismissed')",
    "sync_conflicts": "('open', 'resolved')",
    "deletion_tasks": "('pending', 'cancelled', 'executing', 'executed', 'failed')",
}

_OPEN_SOURCES = (
    "Open set of data sources (manual, csv, pdf, email, screenshot, sms, bank_app, "
    "import ...); no CHECK by design."
)
# COMMENT ON COLUMN (R2-16/R2-32 sign conventions, R2-17 deliberately open sets, R2-07).
COLUMN_COMMENTS: dict[tuple[str, str], str] = {
    ("transactions", "amount_minor"): (
        "Minor units of the currency account's currency, never 0. Positive = liability "
        "increase (purchase, cash_advance, fee, interest, installment_principal); negative = "
        "credit (refund, reversal, repayment); adjustment, transfer, preauth: either sign."
    ),
    ("statement_lines", "amount_minor"): (
        "Minor units; same convention as transactions.amount_minor (positive = liability "
        "increase, negative = credit). Informational lines may carry any sign."
    ),
    ("charges", "amount_minor"): (
        "Minor units, never 0. Positive = fee or interest charged; negative = waiver or "
        "refund of a charge."
    ),
    ("cash_events", "amount_minor"): (
        "Minor units of the cash account's currency, never 0. Positive = inflow (income, "
        "transfer_in); negative = outflow (bill, living, repayment, transfer_out, fee); "
        "other: either sign."
    ),
    ("recurring_items", "amount_minor"): (
        "Minor units per occurrence; same sign convention as cash_events.amount_minor."
    ),
    ("limit_snapshots", "available_raw_minor"): (
        "Available limit exactly as the bank reports it; may be negative (over limit). Only "
        "the derived capacity for new spend is clamped at zero."
    ),
    ("charges", "kind"): (
        "Open set (annual_fee, cash_advance_fee, fx_fee, interest, late_fee, "
        "installment_fee, other ...); no CHECK by design."
    ),
    ("statement_lines", "kind"): (
        "Open set of statement line kinds (purchase, refund, fee, interest, installment, "
        "repayment, adjustment, info ...); no CHECK by design."
    ),
    ("transaction_links", "kind"): (
        "Open set (preauth_capture, refund_of, reversal_of, duplicate_of ...); no CHECK by design."
    ),
    ("import_batches", "kind"): (
        "Open set of import channels (csv, pdf, text, screenshot, eml, html, sms ...); no "
        "CHECK by design."
    ),
    ("plan_invalidations", "cause"): (
        "Open set (snapshot_changed, cash_event_changed, rule_changed, manual ...); no CHECK "
        "by design."
    ),
    ("devices", "platform"): "Open set (ios, android ...); no CHECK by design.",
    ("jobs", "kind"): "Job type registered by the worker; no CHECK by design.",
    ("dedupe_keys", "entity_kind"): ("Table name of the deduplicated entity; no CHECK by design."),
    ("audit_log", "actor_kind"): (
        "Open set (user, device, admin, system ...); no CHECK by design."
    ),
    ("consents", "purpose"): (
        "Open set (ai_extract, gmail, server_sync, analytics ...), data-model §3; no CHECK "
        "by design."
    ),
    ("transactions", "source_kind"): _OPEN_SOURCES,
    ("charges", "source_kind"): _OPEN_SOURCES,
    ("preauth_holds", "source_kind"): _OPEN_SOURCES,
    ("cash_balance_snapshots", "source_kind"): _OPEN_SOURCES,
    ("reconciliation_items", "source_kind"): _OPEN_SOURCES,
    ("sync_changes", "txid"): (
        "Top-level transaction id of the writer. Pull with cursor (txid, seq) over rows "
        "whose txid < pg_snapshot_xmin(pg_current_snapshot()); seq alone is assigned at "
        "INSERT, not at COMMIT."
    ),
    ("jobs", "dedupe_key"): (
        "Optional key; at most one queued or running job per key (e.g. one periodic tick)."
    ),
}

# Foreign-key columns without a usable (non-partial, leading) index in 0001 (R2-25), plus
# the columns of the new composite keys.
FK_INDEXES: tuple[tuple[str, str], ...] = (
    ("transactions", "card_id"),
    ("transactions", "parent_transaction_id"),
    ("transactions", "source_document_id"),
    ("transaction_links", "from_transaction_id"),
    ("preauth_holds", "card_id"),
    ("preauth_holds", "transaction_id"),
    ("preauth_holds", "source_document_id"),
    ("statement_versions", "source_document_id"),
    ("statement_attributions", "transaction_id"),
    ("installment_plans", "transaction_id"),
    ("installment_schedule", "plan_id"),
    ("charges", "statement_id"),
    ("charges", "transaction_id"),
    ("repayments", "cash_account_id"),
    ("repayments", "evidence_document_id"),
    ("repayment_allocations", "repayment_id"),
    ("cash_events", "recurring_item_id"),
    ("cash_events", "linked_repayment_id"),
    ("cash_events", "linked_plan_run_id"),
    ("snapshot_included_events", "snapshot_id"),
    ("cash_transfers", "from_cash_account_id"),
    ("cash_transfers", "to_cash_account_id"),
    ("cash_transfers", "out_event_id"),
    ("cash_transfers", "in_event_id"),
    ("cards", "replaced_by_card_id"),
    ("credit_pools", "parent_pool_id"),
    ("credit_pools", "bank_id"),
    ("credit_pool_members", "pool_id"),
    ("credit_accounts", "product_id"),
    ("rule_bindings", "currency_account_id"),
    ("limit_snapshots", "source_document_id"),
    ("limit_adjustments", "source_document_id"),
    ("import_batches", "target_currency_account_id"),
    ("import_batches", "source_document_id"),
    ("parse_jobs", "import_batch_id"),
    ("plan_runs", "decision_scenario_id"),
    ("plan_allocations", "run_id"),
    ("plan_allocations", "card_id"),
    ("plan_allocations", "currency_account_id"),
    ("plan_allocations", "repay_from_cash_account_id"),
    ("plan_run_checks", "run_id"),
    ("plan_run_checks", "scenario_id"),
    ("plan_invalidations", "run_id"),
    ("plan_reservations", "run_id"),
    ("plan_reservations", "cash_account_id"),
    ("plan_reservations", "linked_transaction_id"),
)

# Natural keys that become partial (live rows only) unique indexes (R2-06):
# name -> (table, columns, was_constraint_in_0001).
PARTIAL_UNIQUES: dict[str, tuple[str, str, bool]] = {
    "uq_statements_currency_account_id_statement_date": (
        "statements",
        "currency_account_id, statement_date",
        True,
    ),
    "uq_currency_accounts_credit_account_id_currency": (
        "currency_accounts",
        "credit_account_id, currency",
        True,
    ),
    "uq_credit_pool_members_pool_id_credit_account_id": (
        "credit_pool_members",
        "pool_id, credit_account_id",
        True,
    ),
    "uq_source_documents_workspace_id_sha256": ("source_documents", "workspace_id, sha256", True),
    "uq_statement_attributions_transaction_id_statement_id": (
        "statement_attributions",
        "transaction_id, statement_id",
        True,
    ),
    "uq_transaction_links_from_transaction_id_to_transaction_id_kind": (
        "transaction_links",
        "from_transaction_id, to_transaction_id, kind",
        True,
    ),
    "uq_installment_schedule_plan_id_period_no": (
        "installment_schedule",
        "plan_id, period_no",
        True,
    ),
    "uq_plan_run_checks_run_id_scenario_id": ("plan_run_checks", "run_id, scenario_id", True),
    "uq_repayment_allocations_repayment_id_statement_id": (
        "repayment_allocations",
        "repayment_id, statement_id",
        False,
    ),
    "uq_snapshot_included_events_snapshot_id_cash_event_id": (
        "snapshot_included_events",
        "snapshot_id, cash_event_id",
        False,
    ),
    "uq_plan_allocations_run_id_card_id": ("plan_allocations", "run_id, card_id", False),
}

# Tables whose 0001 natural primary key becomes id (R2-06, decision 1).
NATURAL_PKS: dict[str, str] = {
    "repayment_allocations": "repayment_id, statement_id",
    "snapshot_included_events": "snapshot_id, cash_event_id",
    "plan_allocations": "run_id, currency_account_id",
}

# --------------------------------------------------------------------------------------
# Functions
# --------------------------------------------------------------------------------------

# Pure helpers, also used by CHECK constraints (tests/db/test_model_drift.py creates them in
# its model-only database, so keep them free of table references).
PAN_FUNCTIONS: list[str] = [
    """
CREATE FUNCTION public.luhn_valid(digits text) RETURNS boolean
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
SET search_path = pg_catalog, public, pg_temp
AS $$
    SELECT CASE
        WHEN digits !~ '^[0-9]+$' THEN false
        ELSE (
            SELECT sum(CASE WHEN d.i % 2 = 0
                            THEN (CASE WHEN d.digit * 2 > 9 THEN d.digit * 2 - 9
                                       ELSE d.digit * 2 END)
                            ELSE d.digit END) % 10 = 0
              FROM (SELECT i, substr(reverse(digits), i, 1)::int AS digit
                      FROM generate_series(1, length(digits)) AS i) AS d
        )
    END
$$
""",
    """
CREATE FUNCTION public.looks_like_pan(value text) RETURNS boolean
LANGUAGE sql IMMUTABLE PARALLEL SAFE
SET search_path = pg_catalog, public, pg_temp
AS $$
    SELECT coalesce(bool_or(length(t.digits) BETWEEN 13 AND 19
                            AND public.luhn_valid(t.digits)), false)
      FROM (SELECT regexp_replace(m[1], '[ -]', '', 'g') AS digits
              FROM regexp_matches(coalesce(value, ''), '([0-9](?:[ -]?[0-9])*)', 'g') AS m) AS t
$$
""",
]

NEW_FUNCTIONS: list[str] = [
    # True when a row with this xmin was written by the current transaction (including its
    # subtransactions): uncommitted rows of other transactions are invisible anyway, so an
    # "in progress" xmin of a visible row can only be ours.
    """
CREATE FUNCTION public.inserted_by_current_transaction(p_xmin xid) RETURNS boolean
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    v_reference bigint := pg_current_xact_id()::text::bigint;
    v_xmin bigint := p_xmin::text::bigint;
    v_full bigint;
BEGIN
    IF v_xmin < 3 THEN
        RETURN false;  -- invalid, bootstrap or frozen: never the current transaction
    END IF;
    v_full := ((v_reference >> 32) << 32) | v_xmin;
    IF v_full > v_reference + 2147483648 THEN
        v_full := v_full - 4294967296;
    ELSIF v_full < v_reference - 2147483648 THEN
        v_full := v_full + 4294967296;
    END IF;
    RETURN coalesce(pg_xact_status(v_full::text::xid8) = 'in progress', false);
END
$$
""",
    """
CREATE FUNCTION public.bump_row_version() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
    NEW.row_version := OLD.row_version + 1;
    NEW.updated_at := now();
    RETURN NEW;
END
$$
""",
    """
CREATE FUNCTION public.forbid_fact_rewrite() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
    -- The only permitted UPDATE is the tombstone itself: deleted_at goes from NULL to a
    -- value once, nothing else changes (row_version/updated_at are bumped by trigger).
    IF OLD.deleted_at IS NOT NULL THEN
        RAISE EXCEPTION '% rows are frozen once tombstoned', TG_TABLE_NAME
            USING ERRCODE = 'integrity_constraint_violation',
                  TABLE = TG_TABLE_NAME,
                  CONSTRAINT = TG_NAME;
    END IF;
    IF NEW.deleted_at IS NULL
       OR (to_jsonb(NEW) - ARRAY['deleted_at', 'row_version', 'updated_at'])
          IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['deleted_at', 'row_version', 'updated_at']) THEN
        RAISE EXCEPTION '% rows are immutable; only deleted_at may be set once (tombstone)',
                        TG_TABLE_NAME
            USING ERRCODE = 'integrity_constraint_violation',
                  TABLE = TG_TABLE_NAME,
                  CONSTRAINT = TG_NAME;
    END IF;
    RETURN NEW;
END
$$
""",
    """
CREATE FUNCTION public.forbid_column_update() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    v_new jsonb := to_jsonb(NEW);
    v_old jsonb := to_jsonb(OLD);
    v_column text;
BEGIN
    FOREACH v_column IN ARRAY TG_ARGV LOOP
        IF v_new -> v_column IS DISTINCT FROM v_old -> v_column THEN
            RAISE EXCEPTION '%.% cannot change', TG_TABLE_NAME, v_column
                USING ERRCODE = 'integrity_constraint_violation',
                      TABLE = TG_TABLE_NAME,
                      COLUMN = v_column,
                      CONSTRAINT = TG_NAME;
        END IF;
    END LOOP;
    RETURN NEW;
END
$$
""",
    """
CREATE FUNCTION public.forbid_fact_delete() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
    IF current_setting('app.purge', true) = pg_current_xact_id()::text THEN
        RETURN OLD;
    END IF;
    RAISE EXCEPTION '% rows are never deleted; set deleted_at (tombstone) instead', TG_TABLE_NAME
        USING ERRCODE = 'integrity_constraint_violation',
              TABLE = TG_TABLE_NAME,
              CONSTRAINT = TG_NAME,
              HINT = 'A workspace purge first runs '
                     || 'SELECT set_config(''app.purge'', pg_current_xact_id()::text, true).';
END
$$
""",
    """
CREATE FUNCTION public.derive_from_parent() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    v_target text := TG_ARGV[0];
    v_parent text := TG_ARGV[1];
    v_key text := TG_ARGV[2];
    v_source text := TG_ARGV[3];
    v_key_value uuid;
    v_found boolean;
    v_value jsonb;
BEGIN
    EXECUTE format('SELECT ($1).%I', v_key) INTO v_key_value USING NEW;
    EXECUTE format(
        'SELECT true, to_jsonb(p.%I) FROM public.%I AS p '
        'WHERE p.workspace_id = $1 AND p.id = $2', v_source, v_parent)
        INTO v_found, v_value USING NEW.workspace_id, v_key_value;
    IF v_found IS NULL THEN
        RAISE EXCEPTION '%.% does not reference a % row of the same workspace',
                        TG_TABLE_NAME, v_key, v_parent
            USING ERRCODE = 'foreign_key_violation',
                  TABLE = TG_TABLE_NAME,
                  COLUMN = v_key,
                  CONSTRAINT = TG_NAME;
    END IF;
    NEW := jsonb_populate_record(NEW, jsonb_build_object(v_target, v_value));
    RETURN NEW;
END
$$
""",
    """
CREATE FUNCTION public.add_to_repayment_allocation_total(
    p_workspace_id uuid, p_repayment_id uuid, p_delta bigint) RETURNS void
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
    -- UPDATE first: INSERT ... ON CONFLICT would check allocated_minor >= 0 on the proposed
    -- row (a negative delta) before resolving the conflict.
    UPDATE public.repayment_allocation_totals AS t
       SET allocated_minor = t.allocated_minor + p_delta
     WHERE t.repayment_id = p_repayment_id;
    IF NOT FOUND THEN
        -- First allocation of this repayment (concurrent first inserts meet in ON CONFLICT).
        INSERT INTO public.repayment_allocation_totals AS t
               (repayment_id, workspace_id, allocated_minor)
        VALUES (p_repayment_id, p_workspace_id, p_delta)
        ON CONFLICT (repayment_id)
        DO UPDATE SET allocated_minor = t.allocated_minor + EXCLUDED.allocated_minor;
    END IF;
END
$$
""",
    """
CREATE FUNCTION public.maintain_repayment_allocation_totals() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    v_old bigint := 0;
    v_new bigint := 0;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.deleted_at IS NULL THEN
            v_new := NEW.amount_minor;
        END IF;
        PERFORM public.add_to_repayment_allocation_total(
            NEW.workspace_id, NEW.repayment_id, v_new);
    ELSIF TG_OP = 'DELETE' THEN
        IF OLD.deleted_at IS NULL THEN
            v_old := OLD.amount_minor;
        END IF;
        PERFORM public.add_to_repayment_allocation_total(
            OLD.workspace_id, OLD.repayment_id, -v_old);
    ELSE
        IF OLD.deleted_at IS NULL THEN
            v_old := OLD.amount_minor;
        END IF;
        IF NEW.deleted_at IS NULL THEN
            v_new := NEW.amount_minor;
        END IF;
        IF OLD.repayment_id IS DISTINCT FROM NEW.repayment_id THEN
            PERFORM public.add_to_repayment_allocation_total(
                OLD.workspace_id, OLD.repayment_id, -v_old);
            PERFORM public.add_to_repayment_allocation_total(
                NEW.workspace_id, NEW.repayment_id, v_new);
        ELSE
            PERFORM public.add_to_repayment_allocation_total(
                NEW.workspace_id, NEW.repayment_id, v_new - v_old);
        END IF;
    END IF;
    RETURN NULL;
END
$$
""",
    """
CREATE FUNCTION public.check_credit_pool_cycle() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
    IF NEW.parent_pool_id IS NOT NULL AND EXISTS (
        WITH RECURSIVE ancestors (id, parent_pool_id, depth) AS (
            SELECT p.id, p.parent_pool_id, 1
              FROM public.credit_pools AS p
             WHERE p.id = NEW.parent_pool_id
            UNION ALL
            SELECT p.id, p.parent_pool_id, a.depth + 1
              FROM public.credit_pools AS p
              JOIN ancestors AS a ON p.id = a.parent_pool_id
             WHERE a.depth < 1000
        )
        SELECT 1 FROM ancestors WHERE ancestors.id = NEW.id
    ) THEN
        RAISE EXCEPTION 'credit pool hierarchy would contain a cycle'
            USING ERRCODE = 'check_violation',
                  TABLE = TG_TABLE_NAME,
                  COLUMN = 'parent_pool_id',
                  CONSTRAINT = TG_NAME;
    END IF;
    RETURN NEW;
END
$$
""",
    """
CREATE FUNCTION public.check_card_replacement_cycle() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
    IF NEW.replaced_by_card_id IS NOT NULL AND EXISTS (
        WITH RECURSIVE successors (id, replaced_by_card_id, depth) AS (
            SELECT c.id, c.replaced_by_card_id, 1
              FROM public.cards AS c
             WHERE c.id = NEW.replaced_by_card_id
            UNION ALL
            SELECT c.id, c.replaced_by_card_id, s.depth + 1
              FROM public.cards AS c
              JOIN successors AS s ON c.id = s.replaced_by_card_id
             WHERE s.depth < 1000
        )
        SELECT 1 FROM successors WHERE successors.id = NEW.id
    ) THEN
        RAISE EXCEPTION 'card replacement chain would contain a cycle'
            USING ERRCODE = 'check_violation',
                  TABLE = TG_TABLE_NAME,
                  COLUMN = 'replaced_by_card_id',
                  CONSTRAINT = TG_NAME;
    END IF;
    RETURN NEW;
END
$$
""",
    """
CREATE FUNCTION public.check_statement_line_transaction() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    v_xmin xid;
BEGIN
    SELECT v.xmin INTO v_xmin
      FROM public.statement_versions AS v
     WHERE v.id = NEW.statement_version_id;
    IF FOUND AND NOT public.inserted_by_current_transaction(v_xmin) THEN
        RAISE EXCEPTION 'statement lines are written in the transaction that creates their version'
            USING ERRCODE = 'integrity_constraint_violation',
                  TABLE = TG_TABLE_NAME,
                  CONSTRAINT = TG_NAME;
    END IF;
    RETURN NEW;
END
$$
""",
]

# Hardened replacements of 0001 functions (same signatures).
HARDENED_FUNCTIONS: list[str] = [
    """
CREATE OR REPLACE FUNCTION public.forbid_workspace_change() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
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
CREATE OR REPLACE FUNCTION public.check_template_scope() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
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
        'SELECT EXISTS (SELECT 1 FROM public.%I AS t WHERE t.id = $1 '
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
CREATE OR REPLACE FUNCTION public.check_rule_subject_scope() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    v_ok boolean;
BEGIN
    IF NEW.subject_kind = 'product' THEN
        SELECT EXISTS (
            SELECT 1 FROM public.card_products AS p
             WHERE p.id = NEW.subject_id
               AND (p.workspace_id IS NULL OR p.workspace_id = NEW.workspace_id)
        ) INTO v_ok;
    ELSIF NEW.subject_kind = 'credit_account' THEN
        SELECT EXISTS (
            SELECT 1 FROM public.credit_accounts AS c
             WHERE c.id = NEW.subject_id AND c.workspace_id = NEW.workspace_id
        ) INTO v_ok;
    ELSE
        SELECT EXISTS (
            SELECT 1 FROM public.currency_accounts AS c
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
    # The sum comes from repayment_allocation_totals. Both statements below write or lock,
    # so a concurrent change of the repayment or of its allocations is waited for (READ
    # COMMITTED, then re-read) or reported as 40001 (REPEATABLE READ / SERIALIZABLE).
    # Same-currency-account is a composite foreign key now and needs no code.
    """
CREATE OR REPLACE FUNCTION public.check_repayment_allocations(p_repayment_id uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    v_amount bigint;
    v_status text;
    v_deleted_at timestamptz;
    v_allocated bigint;
BEGIN
    SELECT r.amount_minor, r.status, r.deleted_at
      INTO v_amount, v_status, v_deleted_at
      FROM public.repayments AS r
     WHERE r.id = p_repayment_id
       FOR NO KEY UPDATE;
    IF NOT FOUND THEN
        RETURN;  -- the repayment itself is gone; foreign keys report orphans
    END IF;

    UPDATE public.repayment_allocation_totals AS t
       SET allocated_minor = t.allocated_minor
     WHERE t.repayment_id = p_repayment_id
    RETURNING t.allocated_minor INTO v_allocated;
    v_allocated := coalesce(v_allocated, 0);

    IF v_allocated > v_amount THEN
        RAISE EXCEPTION 'repayment allocations exceed the repayment amount'
            USING ERRCODE = 'check_violation',
                  TABLE = 'repayment_allocations',
                  CONSTRAINT = 'repayment_allocations_within_amount';
    END IF;
    IF v_allocated > 0 AND (v_deleted_at IS NOT NULL OR v_status IN ('reversed', 'failed')) THEN
        RAISE EXCEPTION 'a deleted, reversed or failed repayment keeps no live allocations'
            USING ERRCODE = 'check_violation',
                  TABLE = 'repayment_allocations',
                  CONSTRAINT = 'repayment_allocations_inactive_repayment';
    END IF;
END
$$
""",
    """
CREATE OR REPLACE FUNCTION public.repayment_allocations_check() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
    PERFORM public.check_repayment_allocations(NEW.repayment_id);
    RETURN NULL;
END
$$
""",
    """
CREATE OR REPLACE FUNCTION public.repayments_allocation_check() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
    PERFORM public.check_repayment_allocations(NEW.id);
    RETURN NULL;
END
$$
""",
]

# 0001 definitions restored by downgrade() (verbatim copies of 0001's statements).
V0001_FUNCTIONS: dict[str, str] = {
    "forbid_amount_update": """
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
    "forbid_statement_version_delete": """
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
    "check_repayment_allocations": """
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
    "repayment_allocations_check": """
CREATE FUNCTION repayment_allocations_check() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM check_repayment_allocations(NEW.repayment_id);
    RETURN NULL;
END
$$
""",
    "repayments_allocation_check": """
CREATE FUNCTION repayments_allocation_check() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM check_repayment_allocations(NEW.id);
    RETURN NULL;
END
$$
""",
    "statements_allocation_check": """
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
    "check_template_scope": """
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
    "check_rule_subject_scope": """
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
    "forbid_workspace_change": """
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
}
V0001_TRIGGERS: dict[str, str] = {
    "statement_versions_append_only": """
CREATE TRIGGER statement_versions_append_only
    BEFORE UPDATE OF previous_balance_minor, new_balance_minor, min_due_minor, payments_minor,
                     credits_minor, fees_minor, interest_minor, installment_due_minor,
                     credit_balance_minor, due_date
    ON statement_versions FOR EACH ROW EXECUTE FUNCTION forbid_amount_update()
""",
    "statement_versions_no_delete": """
CREATE TRIGGER statement_versions_no_delete
    BEFORE DELETE ON statement_versions
    FOR EACH ROW EXECUTE FUNCTION forbid_statement_version_delete()
""",
    "statement_versions_no_truncate": """
CREATE TRIGGER statement_versions_no_truncate
    BEFORE TRUNCATE ON statement_versions
    FOR EACH STATEMENT EXECUTE FUNCTION forbid_statement_version_delete()
""",
    "repayments_allocations_within_amount": """
CREATE CONSTRAINT TRIGGER repayments_allocations_within_amount
    AFTER UPDATE OF amount_minor, currency_account_id ON repayments
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION repayments_allocation_check()
""",
    "statements_allocations_same_currency_account": """
CREATE CONSTRAINT TRIGGER statements_allocations_same_currency_account
    AFTER UPDATE OF currency_account_id ON statements
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION statements_allocation_check()
""",
}

# --------------------------------------------------------------------------------------
# Schema changes
# --------------------------------------------------------------------------------------

# New composite keys on parents (targets of the consistency foreign keys).
PARENT_KEYS: list[tuple[str, str, str]] = [
    (
        "currency_accounts",
        "uq_currency_accounts_workspace_id_id_currency",
        "workspace_id, id, currency",
    ),
    (
        "currency_accounts",
        "uq_currency_accounts_workspace_id_credit_account_id_id",
        "workspace_id, credit_account_id, id",
    ),
    ("cards", "uq_cards_workspace_id_credit_account_id_id", "workspace_id, credit_account_id, id"),
    ("cash_accounts", "uq_cash_accounts_workspace_id_id_currency", "workspace_id, id, currency"),
    (
        "statements",
        "uq_statements_workspace_id_currency_account_id_id",
        "workspace_id, currency_account_id, id",
    ),
    (
        "transactions",
        "uq_transactions_workspace_id_currency_account_id_id",
        "workspace_id, currency_account_id, id",
    ),
    (
        "repayments",
        "uq_repayments_workspace_id_currency_account_id_id",
        "workspace_id, currency_account_id, id",
    ),
    (
        "repayments",
        "uq_repayments_workspace_id_cash_account_id_id",
        "workspace_id, cash_account_id, id",
    ),
    (
        "cash_events",
        "uq_cash_events_workspace_id_cash_account_id_id",
        "workspace_id, cash_account_id, id",
    ),
    (
        "cash_balance_snapshots",
        "uq_cash_balance_snapshots_workspace_id_cash_account_id_id",
        "workspace_id, cash_account_id, id",
    ),
    (
        "recurring_items",
        "uq_recurring_items_workspace_id_cash_account_id_id",
        "workspace_id, cash_account_id, id",
    ),
    ("plans", "uq_plans_workspace_id_id_currency", "workspace_id, id, currency"),
]

# Derived (redundant) columns: (table, column, type, parent table, local key, parent column).
DERIVED_COLUMNS: list[tuple[str, str, str, str, str, str]] = [
    (
        "transactions",
        "credit_account_id",
        "UUID",
        "currency_accounts",
        "currency_account_id",
        "credit_account_id",
    ),
    (
        "preauth_holds",
        "credit_account_id",
        "UUID",
        "currency_accounts",
        "currency_account_id",
        "credit_account_id",
    ),
    (
        "statement_versions",
        "currency_account_id",
        "UUID",
        "statements",
        "statement_id",
        "currency_account_id",
    ),
    (
        "statement_lines",
        "currency_account_id",
        "UUID",
        "statement_versions",
        "statement_version_id",
        "currency_account_id",
    ),
    (
        "statement_attributions",
        "currency_account_id",
        "UUID",
        "transactions",
        "transaction_id",
        "currency_account_id",
    ),
    (
        "snapshot_included_events",
        "cash_account_id",
        "UUID",
        "cash_balance_snapshots",
        "snapshot_id",
        "cash_account_id",
    ),
    (
        "repayment_allocations",
        "currency_account_id",
        "UUID",
        "repayments",
        "repayment_id",
        "currency_account_id",
    ),
    ("plan_runs", "currency", "CHAR(3)", "plans", "plan_id", "currency"),
    ("plan_allocations", "currency", "CHAR(3)", "plan_runs", "run_id", "currency"),
    (
        "plan_allocations",
        "credit_account_id",
        "UUID",
        "currency_accounts",
        "currency_account_id",
        "credit_account_id",
    ),
    ("plan_reservations", "currency", "CHAR(3)", "plans", "plan_id", "currency"),
]
DERIVED_COMMENTS: dict[tuple[str, str], str] = {
    (table, column): f"Derived from {key} by trigger; clients do not supply it."
    for table, column, _type, _parent, key, _source in DERIVED_COLUMNS
}
DERIVED_TRIGGER_SUFFIX: dict[str, str] = {
    "credit_account_id": "derive_credit_account",
    "currency_account_id": "derive_currency_account",
    "cash_account_id": "derive_cash_account",
    "currency": "derive_currency",
}

# Keys on the tables that just received derived columns.
DERIVED_KEYS: list[tuple[str, str, str]] = [
    ("plan_runs", "uq_plan_runs_workspace_id_id_currency", "workspace_id, id, currency"),
    ("plan_runs", "uq_plan_runs_workspace_id_plan_id_id", "workspace_id, plan_id, id"),
    (
        "statement_versions",
        "uq_statement_versions_workspace_id_id_currency_account_id",
        "workspace_id, id, currency_account_id",
    ),
]

# Foreign keys of 0001 replaced by composite ones: table -> {old name: 0001 definition}.
REPLACED_FKS: dict[str, dict[str, str]] = {
    "transactions": {
        "fk_transactions_currency_account_id": (
            "FOREIGN KEY (workspace_id, currency_account_id) "
            "REFERENCES currency_accounts (workspace_id, id)"
        ),
        "fk_transactions_card_id": (
            "FOREIGN KEY (workspace_id, card_id) REFERENCES cards (workspace_id, id)"
        ),
    },
    "repayments": {
        "fk_repayments_currency_account_id": (
            "FOREIGN KEY (workspace_id, currency_account_id) "
            "REFERENCES currency_accounts (workspace_id, id)"
        ),
    },
    "charges": {
        "fk_charges_currency_account_id": (
            "FOREIGN KEY (workspace_id, currency_account_id) "
            "REFERENCES currency_accounts (workspace_id, id)"
        ),
        "fk_charges_statement_id": (
            "FOREIGN KEY (workspace_id, statement_id) REFERENCES statements (workspace_id, id)"
        ),
        "fk_charges_transaction_id": (
            "FOREIGN KEY (workspace_id, transaction_id) REFERENCES transactions (workspace_id, id)"
        ),
    },
    "preauth_holds": {
        "fk_preauth_holds_currency_account_id": (
            "FOREIGN KEY (workspace_id, currency_account_id) "
            "REFERENCES currency_accounts (workspace_id, id)"
        ),
        "fk_preauth_holds_card_id": (
            "FOREIGN KEY (workspace_id, card_id) REFERENCES cards (workspace_id, id)"
        ),
        "fk_preauth_holds_transaction_id": (
            "FOREIGN KEY (workspace_id, transaction_id) REFERENCES transactions (workspace_id, id)"
        ),
    },
    "cash_transfers": {
        "fk_cash_transfers_from_cash_account_id": (
            "FOREIGN KEY (workspace_id, from_cash_account_id) "
            "REFERENCES cash_accounts (workspace_id, id)"
        ),
        "fk_cash_transfers_to_cash_account_id": (
            "FOREIGN KEY (workspace_id, to_cash_account_id) "
            "REFERENCES cash_accounts (workspace_id, id)"
        ),
        "fk_cash_transfers_out_event_id": (
            "FOREIGN KEY (workspace_id, out_event_id) REFERENCES cash_events (workspace_id, id)"
        ),
        "fk_cash_transfers_in_event_id": (
            "FOREIGN KEY (workspace_id, in_event_id) REFERENCES cash_events (workspace_id, id)"
        ),
    },
    "rule_bindings": {
        "fk_rule_bindings_currency_account_id": (
            "FOREIGN KEY (workspace_id, currency_account_id) "
            "REFERENCES currency_accounts (workspace_id, id)"
        ),
    },
    "statement_versions": {
        "fk_statement_versions_statement_id": (
            "FOREIGN KEY (workspace_id, statement_id) REFERENCES statements (workspace_id, id)"
        ),
    },
    "statement_lines": {
        "fk_statement_lines_statement_version_id": (
            "FOREIGN KEY (workspace_id, statement_version_id) "
            "REFERENCES statement_versions (workspace_id, id)"
        ),
        "fk_statement_lines_transaction_id": (
            "FOREIGN KEY (workspace_id, transaction_id) REFERENCES transactions (workspace_id, id)"
        ),
    },
    "statement_attributions": {
        "fk_statement_attributions_transaction_id": (
            "FOREIGN KEY (workspace_id, transaction_id) REFERENCES transactions (workspace_id, id)"
        ),
        "fk_statement_attributions_statement_id": (
            "FOREIGN KEY (workspace_id, statement_id) REFERENCES statements (workspace_id, id)"
        ),
    },
    "snapshot_included_events": {
        "fk_snapshot_included_events_snapshot_id": (
            "FOREIGN KEY (workspace_id, snapshot_id) "
            "REFERENCES cash_balance_snapshots (workspace_id, id) ON DELETE CASCADE"
        ),
        "fk_snapshot_included_events_cash_event_id": (
            "FOREIGN KEY (workspace_id, cash_event_id) REFERENCES cash_events (workspace_id, id)"
        ),
    },
    "cash_events": {
        "fk_cash_events_recurring_item_id": (
            "FOREIGN KEY (workspace_id, recurring_item_id) "
            "REFERENCES recurring_items (workspace_id, id)"
        ),
        "fk_cash_events_linked_repayment_id": (
            "FOREIGN KEY (workspace_id, linked_repayment_id) "
            "REFERENCES repayments (workspace_id, id)"
        ),
    },
    "plan_runs": {
        "fk_plan_runs_plan_id": (
            "FOREIGN KEY (workspace_id, plan_id) REFERENCES plans (workspace_id, id)"
        ),
    },
    "plan_allocations": {
        "fk_plan_allocations_run_id": (
            "FOREIGN KEY (workspace_id, run_id) REFERENCES plan_runs (workspace_id, id)"
        ),
        "fk_plan_allocations_currency_account_id": (
            "FOREIGN KEY (workspace_id, currency_account_id) "
            "REFERENCES currency_accounts (workspace_id, id)"
        ),
        "fk_plan_allocations_card_id": (
            "FOREIGN KEY (workspace_id, card_id) REFERENCES cards (workspace_id, id)"
        ),
        "fk_plan_allocations_repay_from_cash_account_id": (
            "FOREIGN KEY (workspace_id, repay_from_cash_account_id) "
            "REFERENCES cash_accounts (workspace_id, id)"
        ),
    },
    "plan_reservations": {
        "fk_plan_reservations_plan_id": (
            "FOREIGN KEY (workspace_id, plan_id) REFERENCES plans (workspace_id, id)"
        ),
        "fk_plan_reservations_run_id": (
            "FOREIGN KEY (workspace_id, run_id) REFERENCES plan_runs (workspace_id, id)"
        ),
        "fk_plan_reservations_currency_account_id": (
            "FOREIGN KEY (workspace_id, currency_account_id) "
            "REFERENCES currency_accounts (workspace_id, id)"
        ),
        "fk_plan_reservations_cash_account_id": (
            "FOREIGN KEY (workspace_id, cash_account_id) "
            "REFERENCES cash_accounts (workspace_id, id)"
        ),
        "fk_plan_reservations_linked_transaction_id": (
            "FOREIGN KEY (workspace_id, linked_transaction_id) "
            "REFERENCES transactions (workspace_id, id)"
        ),
    },
    "plan_invalidations": {
        "fk_plan_invalidations_run_id": (
            "FOREIGN KEY (workspace_id, run_id) REFERENCES plan_runs (workspace_id, id)"
        ),
    },
    "repayment_allocations": {
        "fk_repayment_allocations_repayment_id": (
            "FOREIGN KEY (workspace_id, repayment_id) REFERENCES repayments (workspace_id, id)"
        ),
        "fk_repayment_allocations_statement_id": (
            "FOREIGN KEY (workspace_id, statement_id) REFERENCES statements (workspace_id, id)"
        ),
    },
}

# New foreign keys: table -> {name: definition}.
NEW_FKS: dict[str, dict[str, str]] = {
    "transactions": {
        "fk_transactions_currency_account_id_currency": (
            "FOREIGN KEY (workspace_id, currency_account_id, currency) "
            "REFERENCES currency_accounts (workspace_id, id, currency)"
        ),
        "fk_transactions_credit_account_id_currency_account_id": (
            "FOREIGN KEY (workspace_id, credit_account_id, currency_account_id) "
            "REFERENCES currency_accounts (workspace_id, credit_account_id, id)"
        ),
        "fk_transactions_credit_account_id_card_id": (
            "FOREIGN KEY (workspace_id, credit_account_id, card_id) "
            "REFERENCES cards (workspace_id, credit_account_id, id)"
        ),
        "fk_transactions_source_document_id": (
            "FOREIGN KEY (workspace_id, source_document_id) "
            "REFERENCES source_documents (workspace_id, id)"
        ),
    },
    "repayments": {
        "fk_repayments_currency_account_id_currency": (
            "FOREIGN KEY (workspace_id, currency_account_id, currency) "
            "REFERENCES currency_accounts (workspace_id, id, currency)"
        ),
        "fk_repayments_evidence_document_id": (
            "FOREIGN KEY (workspace_id, evidence_document_id) "
            "REFERENCES source_documents (workspace_id, id)"
        ),
    },
    "charges": {
        "fk_charges_currency_account_id_currency": (
            "FOREIGN KEY (workspace_id, currency_account_id, currency) "
            "REFERENCES currency_accounts (workspace_id, id, currency)"
        ),
        "fk_charges_currency_account_id_statement_id": (
            "FOREIGN KEY (workspace_id, currency_account_id, statement_id) "
            "REFERENCES statements (workspace_id, currency_account_id, id)"
        ),
        "fk_charges_currency_account_id_transaction_id": (
            "FOREIGN KEY (workspace_id, currency_account_id, transaction_id) "
            "REFERENCES transactions (workspace_id, currency_account_id, id)"
        ),
    },
    "preauth_holds": {
        "fk_preauth_holds_currency_account_id_currency": (
            "FOREIGN KEY (workspace_id, currency_account_id, currency) "
            "REFERENCES currency_accounts (workspace_id, id, currency)"
        ),
        "fk_preauth_holds_credit_account_id_currency_account_id": (
            "FOREIGN KEY (workspace_id, credit_account_id, currency_account_id) "
            "REFERENCES currency_accounts (workspace_id, credit_account_id, id)"
        ),
        "fk_preauth_holds_credit_account_id_card_id": (
            "FOREIGN KEY (workspace_id, credit_account_id, card_id) "
            "REFERENCES cards (workspace_id, credit_account_id, id)"
        ),
        "fk_preauth_holds_currency_account_id_transaction_id": (
            "FOREIGN KEY (workspace_id, currency_account_id, transaction_id) "
            "REFERENCES transactions (workspace_id, currency_account_id, id)"
        ),
        "fk_preauth_holds_source_document_id": (
            "FOREIGN KEY (workspace_id, source_document_id) "
            "REFERENCES source_documents (workspace_id, id)"
        ),
    },
    "cash_transfers": {
        "fk_cash_transfers_from_cash_account_id_currency": (
            "FOREIGN KEY (workspace_id, from_cash_account_id, currency) "
            "REFERENCES cash_accounts (workspace_id, id, currency)"
        ),
        "fk_cash_transfers_to_cash_account_id_currency": (
            "FOREIGN KEY (workspace_id, to_cash_account_id, currency) "
            "REFERENCES cash_accounts (workspace_id, id, currency)"
        ),
        "fk_cash_transfers_from_cash_account_id_out_event_id": (
            "FOREIGN KEY (workspace_id, from_cash_account_id, out_event_id) "
            "REFERENCES cash_events (workspace_id, cash_account_id, id)"
        ),
        "fk_cash_transfers_to_cash_account_id_in_event_id": (
            "FOREIGN KEY (workspace_id, to_cash_account_id, in_event_id) "
            "REFERENCES cash_events (workspace_id, cash_account_id, id)"
        ),
    },
    "rule_bindings": {
        "fk_rule_bindings_credit_account_id_currency_account_id": (
            "FOREIGN KEY (workspace_id, credit_account_id, currency_account_id) "
            "REFERENCES currency_accounts (workspace_id, credit_account_id, id)"
        ),
    },
    "statement_versions": {
        "fk_statement_versions_statement_id_currency_account_id": (
            "FOREIGN KEY (workspace_id, statement_id, currency_account_id) "
            "REFERENCES statements (workspace_id, id, currency_account_id)"
        ),
        "fk_statement_versions_source_document_id": (
            "FOREIGN KEY (workspace_id, source_document_id) "
            "REFERENCES source_documents (workspace_id, id)"
        ),
    },
    "statement_lines": {
        "fk_statement_lines_statement_version_id_currency_account_id": (
            "FOREIGN KEY (workspace_id, statement_version_id, currency_account_id) "
            "REFERENCES statement_versions (workspace_id, id, currency_account_id)"
        ),
        "fk_statement_lines_currency_account_id_transaction_id": (
            "FOREIGN KEY (workspace_id, currency_account_id, transaction_id) "
            "REFERENCES transactions (workspace_id, currency_account_id, id)"
        ),
    },
    "statement_attributions": {
        "fk_statement_attributions_currency_account_id_transaction_id": (
            "FOREIGN KEY (workspace_id, currency_account_id, transaction_id) "
            "REFERENCES transactions (workspace_id, currency_account_id, id)"
        ),
        "fk_statement_attributions_currency_account_id_statement_id": (
            "FOREIGN KEY (workspace_id, currency_account_id, statement_id) "
            "REFERENCES statements (workspace_id, currency_account_id, id)"
        ),
    },
    "snapshot_included_events": {
        "fk_snapshot_included_events_cash_account_id_snapshot_id": (
            "FOREIGN KEY (workspace_id, cash_account_id, snapshot_id) "
            "REFERENCES cash_balance_snapshots (workspace_id, cash_account_id, id) "
            "ON DELETE CASCADE"
        ),
        "fk_snapshot_included_events_cash_account_id_cash_event_id": (
            "FOREIGN KEY (workspace_id, cash_account_id, cash_event_id) "
            "REFERENCES cash_events (workspace_id, cash_account_id, id)"
        ),
    },
    "cash_events": {
        "fk_cash_events_cash_account_id_recurring_item_id": (
            "FOREIGN KEY (workspace_id, cash_account_id, recurring_item_id) "
            "REFERENCES recurring_items (workspace_id, cash_account_id, id)"
        ),
        "fk_cash_events_cash_account_id_linked_repayment_id": (
            "FOREIGN KEY (workspace_id, cash_account_id, linked_repayment_id) "
            "REFERENCES repayments (workspace_id, cash_account_id, id)"
        ),
    },
    "plan_runs": {
        "fk_plan_runs_plan_id_currency": (
            "FOREIGN KEY (workspace_id, plan_id, currency) "
            "REFERENCES plans (workspace_id, id, currency)"
        ),
    },
    "plan_allocations": {
        "fk_plan_allocations_run_id_currency": (
            "FOREIGN KEY (workspace_id, run_id, currency) "
            "REFERENCES plan_runs (workspace_id, id, currency)"
        ),
        "fk_plan_allocations_currency_account_id_currency": (
            "FOREIGN KEY (workspace_id, currency_account_id, currency) "
            "REFERENCES currency_accounts (workspace_id, id, currency)"
        ),
        "fk_plan_allocations_credit_account_id_currency_account_id": (
            "FOREIGN KEY (workspace_id, credit_account_id, currency_account_id) "
            "REFERENCES currency_accounts (workspace_id, credit_account_id, id)"
        ),
        "fk_plan_allocations_credit_account_id_card_id": (
            "FOREIGN KEY (workspace_id, credit_account_id, card_id) "
            "REFERENCES cards (workspace_id, credit_account_id, id)"
        ),
        "fk_plan_allocations_repay_from_cash_account_id_currency": (
            "FOREIGN KEY (workspace_id, repay_from_cash_account_id, currency) "
            "REFERENCES cash_accounts (workspace_id, id, currency)"
        ),
    },
    "plan_reservations": {
        "fk_plan_reservations_plan_id_currency": (
            "FOREIGN KEY (workspace_id, plan_id, currency) "
            "REFERENCES plans (workspace_id, id, currency)"
        ),
        "fk_plan_reservations_plan_id_run_id": (
            "FOREIGN KEY (workspace_id, plan_id, run_id) "
            "REFERENCES plan_runs (workspace_id, plan_id, id)"
        ),
        "fk_plan_reservations_currency_account_id_currency": (
            "FOREIGN KEY (workspace_id, currency_account_id, currency) "
            "REFERENCES currency_accounts (workspace_id, id, currency)"
        ),
        "fk_plan_reservations_cash_account_id_currency": (
            "FOREIGN KEY (workspace_id, cash_account_id, currency) "
            "REFERENCES cash_accounts (workspace_id, id, currency)"
        ),
        "fk_plan_reservations_currency_account_id_linked_transaction_id": (
            "FOREIGN KEY (workspace_id, currency_account_id, linked_transaction_id) "
            "REFERENCES transactions (workspace_id, currency_account_id, id)"
        ),
    },
    "plan_invalidations": {
        "fk_plan_invalidations_plan_id_run_id": (
            "FOREIGN KEY (workspace_id, plan_id, run_id) "
            "REFERENCES plan_runs (workspace_id, plan_id, id)"
        ),
    },
    "repayment_allocations": {
        "fk_repayment_allocations_currency_account_id_repayment_id": (
            "FOREIGN KEY (workspace_id, currency_account_id, repayment_id) "
            "REFERENCES repayments (workspace_id, currency_account_id, id)"
        ),
        "fk_repayment_allocations_currency_account_id_statement_id": (
            "FOREIGN KEY (workspace_id, currency_account_id, statement_id) "
            "REFERENCES statements (workspace_id, currency_account_id, id)"
        ),
    },
    "limit_snapshots": {
        "fk_limit_snapshots_source_document_id": (
            "FOREIGN KEY (workspace_id, source_document_id) "
            "REFERENCES source_documents (workspace_id, id)"
        ),
    },
    "limit_adjustments": {
        "fk_limit_adjustments_source_document_id": (
            "FOREIGN KEY (workspace_id, source_document_id) "
            "REFERENCES source_documents (workspace_id, id)"
        ),
    },
    "import_batches": {
        "fk_import_batches_source_document_id": (
            "FOREIGN KEY (workspace_id, source_document_id) "
            "REFERENCES source_documents (workspace_id, id)"
        ),
    },
}

# New CHECK constraints: (table, name, expression).
NEW_CHECKS: list[tuple[str, str, str]] = [
    ("workspaces", "ck_workspaces_id_not_nil", f"id <> {NIL_UUID}"),
    ("users", "ck_users_email_not_empty", "email <> ''"),
    ("devices", "ck_devices_public_key_length", "octet_length(public_key) BETWEEN 32 AND 4096"),
    (
        "billing_rule_versions",
        "ck_billing_rule_versions_workspace_review_status",
        "workspace_id IS NULL OR review_status IN ('draft', 'user_declared', 'expired')",
    ),
    ("transactions", "ck_transactions_amount_nonzero", "amount_minor <> 0"),
    (
        "transactions",
        "ck_transactions_amount_sign",
        "(txn_type IN ('purchase', 'cash_advance', 'fee', 'interest', 'installment_principal')"
        " AND amount_minor > 0)"
        " OR (txn_type IN ('refund', 'reversal', 'repayment') AND amount_minor < 0)"
        " OR txn_type IN ('adjustment', 'transfer', 'preauth')",
    ),
    ("charges", "ck_charges_amount_nonzero", "amount_minor <> 0"),
    ("cash_events", "ck_cash_events_amount_nonzero", "amount_minor <> 0"),
    (
        "cash_events",
        "ck_cash_events_amount_sign",
        "(category IN ('income', 'transfer_in') AND amount_minor > 0)"
        " OR (category IN ('bill', 'living', 'repayment', 'transfer_out', 'fee')"
        " AND amount_minor < 0)"
        " OR category = 'other'",
    ),
    ("cash_events", "ck_cash_events_event_at_needs_tz", "event_at IS NULL OR event_tz IS NOT NULL"),
    ("recurring_items", "ck_recurring_items_amount_nonzero", "amount_minor <> 0"),
    (
        "recurring_items",
        "ck_recurring_items_amount_sign",
        "(category IN ('income', 'transfer_in') AND amount_minor > 0)"
        " OR (category IN ('bill', 'living', 'repayment', 'transfer_out', 'fee')"
        " AND amount_minor < 0)"
        " OR category = 'other'",
    ),
    (
        "repayments",
        "ck_repayments_cash_debited_precision",
        f"cash_debited_precision IN {TIME_PRECISIONS}",
    ),
    (
        "repayments",
        "ck_repayments_credit_posted_precision",
        f"credit_posted_precision IN {TIME_PRECISIONS}",
    ),
    (
        "repayments",
        "ck_repayments_cash_debited_precision_pair",
        "(cash_debited_at IS NULL) = (cash_debited_precision IS NULL)",
    ),
    (
        "repayments",
        "ck_repayments_credit_posted_precision_pair",
        "(credit_posted_at IS NULL) = (credit_posted_precision IS NULL)",
    ),
    (
        "repayments",
        "ck_repayments_times_need_tz",
        "event_tz IS NOT NULL OR (payment_initiated_at IS NULL AND cash_debited_at IS NULL"
        " AND credit_posted_at IS NULL AND bank_confirmed_at IS NULL)",
    ),
    (
        "source_documents",
        "ck_source_documents_blob_while_live",
        "deleted_at IS NOT NULL OR (storage_key IS NOT NULL AND dek_wrapped IS NOT NULL)",
    ),
    (
        "extraction_candidates",
        "ck_extraction_candidates_values_not_pan",
        "field_path ~ '(^|[.])bank_reference$' OR NOT (looks_like_pan(raw_value)"
        " OR looks_like_pan(normalized_value) OR looks_like_pan(confirmed_value))",
    ),
    *(
        (table, f"ck_{table}_status", f"status IN {values}")
        for table, values in STATUS_CHECKS.items()
    ),
    *(
        (table, f"ck_{table}_{column}_not_pan", f"NOT looks_like_pan({column})")
        for table, column in PAN_CHECKED_COLUMNS
    ),
]

NEW_COLUMNS: list[str] = [
    "ALTER TABLE repayments ADD COLUMN event_tz TEXT",
    "ALTER TABLE repayments ADD COLUMN cash_debited_precision TEXT",
    "ALTER TABLE repayments ADD COLUMN credit_posted_precision TEXT",
    "ALTER TABLE repayments ADD COLUMN recorded_at TIMESTAMPTZ NOT NULL DEFAULT now()",
    "ALTER TABLE transactions ADD COLUMN observed_at TIMESTAMPTZ",
    "ALTER TABLE cash_events ADD COLUMN event_tz TEXT",
    "ALTER TABLE cash_events ADD COLUMN recorded_at TIMESTAMPTZ NOT NULL DEFAULT now()",
    "ALTER TABLE sync_changes ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id()",
    "ALTER TABLE jobs ADD COLUMN dedupe_key TEXT",
    # Purging a document wipes its blob key and storage location; the row stays (R2-20).
    "ALTER TABLE source_documents ALTER COLUMN storage_key DROP NOT NULL",
    "ALTER TABLE source_documents ALTER COLUMN dek_wrapped DROP NOT NULL",
]

NEW_INDEXES: list[str] = [
    "CREATE INDEX ix_idempotency_keys_created_at ON idempotency_keys (created_at)",
    "CREATE INDEX ix_sync_changes_workspace_id_txid_seq ON sync_changes (workspace_id, txid, seq)",
    "CREATE UNIQUE INDEX uq_jobs_dedupe_key_active ON jobs (dedupe_key) "
    "WHERE dedupe_key IS NOT NULL AND status IN ('queued', 'running')",
    "CREATE INDEX ix_jobs_running_locked_until ON jobs (locked_until) WHERE status = 'running'",
    *(f"CREATE INDEX ix_{table}_{column} ON {table} ({column})" for table, column in FK_INDEXES),
]

# Coordinator rulings for the job queue (T-008): (table, name, 0001 expression, new one).
REPLACED_CHECKS: list[tuple[str, str, str, str]] = [
    (
        "jobs",
        "ck_jobs_status",
        "status IN ('queued', 'running', 'succeeded', 'failed', 'dead')",
        "status IN ('queued', 'running', 'succeeded', 'failed', 'dead', 'canceled')",
    ),
]
# (0001 name, 0001 definition, new name, new definition)
REPLACED_INDEXES: list[tuple[str, str, str, str]] = [
    (
        "ix_jobs_status_run_after",
        "CREATE INDEX ix_jobs_status_run_after ON jobs (status, run_after) WHERE status = 'queued'",
        "ix_jobs_queued_run_after_created_at",
        "CREATE INDEX ix_jobs_queued_run_after_created_at ON jobs (run_after, created_at) "
        "WHERE status = 'queued'",
    ),
]

RULE_BINDING_EXCLUSION = f"""
ALTER TABLE rule_bindings ADD CONSTRAINT ex_rule_bindings_account_period EXCLUDE USING gist (
    workspace_id WITH =,
    credit_account_id WITH =,
    (COALESCE(currency_account_id, {NIL_UUID})) WITH =,
    (daterange(effective_from, effective_to, '[)')) WITH &&
) WHERE (deleted_at IS NULL)
"""

ALLOCATION_TOTALS_TABLE = """
CREATE TABLE repayment_allocation_totals (
    repayment_id UUID NOT NULL,
    workspace_id UUID NOT NULL,
    allocated_minor BIGINT NOT NULL DEFAULT 0,
    CONSTRAINT pk_repayment_allocation_totals PRIMARY KEY (repayment_id),
    CONSTRAINT fk_repayment_allocation_totals_repayment_id
        FOREIGN KEY (workspace_id, repayment_id) REFERENCES repayments (workspace_id, id)
        ON DELETE CASCADE,
    CONSTRAINT ck_repayment_allocation_totals_allocated_non_negative
        CHECK (allocated_minor >= 0)
)
"""
ALLOCATION_TOTALS_BACKFILL = """
INSERT INTO repayment_allocation_totals (repayment_id, workspace_id, allocated_minor)
SELECT a.repayment_id, a.workspace_id, sum(a.amount_minor)
  FROM repayment_allocations AS a
 WHERE a.deleted_at IS NULL
 GROUP BY a.repayment_id, a.workspace_id
"""


def _derived_column_statements() -> list[str]:
    statements: list[str] = []
    for table, column, sql_type, parent, key, source in DERIVED_COLUMNS:
        statements += [
            f"ALTER TABLE {table} ADD COLUMN {column} {sql_type}",
            # Identifiers come from the constant DERIVED_COLUMNS list above.
            f"UPDATE {table} AS c SET {column} = p.{source} FROM {parent} AS p "  # noqa: S608
            f"WHERE p.workspace_id = c.workspace_id AND p.id = c.{key}",
            f"ALTER TABLE {table} ALTER COLUMN {column} SET NOT NULL",
        ]
    return statements


def _natural_key_statements() -> list[str]:
    statements: list[str] = [
        f"ALTER TABLE {table} DROP CONSTRAINT pk_{table}" for table in NATURAL_PKS
    ]
    statements += [
        f"ALTER TABLE {table} ADD CONSTRAINT pk_{table} PRIMARY KEY (id)" for table in NATURAL_PKS
    ]
    statements.append("ALTER TABLE plan_allocations ALTER COLUMN card_id SET NOT NULL")
    for name, (table, columns, was_constraint) in PARTIAL_UNIQUES.items():
        if was_constraint:
            statements.append(f"ALTER TABLE {table} DROP CONSTRAINT {name}")
        statements.append(
            f"CREATE UNIQUE INDEX {name} ON {table} ({columns}) WHERE deleted_at IS NULL"
        )
    return statements


def _quoted(text: str) -> str:
    return "'" + text.replace("'", "''") + "'"


SCHEMA: list[str] = [
    *(
        f"ALTER TABLE {table} ADD CONSTRAINT {name} UNIQUE ({columns})"
        for table, name, columns in PARENT_KEYS
    ),
    # 0001's deferred allocation check fires on every UPDATE of repayment_allocations: the
    # backfill would leave trigger events pending and the next ALTER TABLE of that table
    # fails (55006). The backfill only fills the derived column, so the check is not needed.
    "ALTER TABLE repayment_allocations DISABLE TRIGGER repayment_allocations_within_amount",
    *_derived_column_statements(),
    "ALTER TABLE repayment_allocations ENABLE TRIGGER repayment_allocations_within_amount",
    *(
        f"ALTER TABLE {table} ADD CONSTRAINT {name} UNIQUE ({columns})"
        for table, name, columns in DERIVED_KEYS
    ),
    *(
        f"ALTER TABLE {table} DROP CONSTRAINT {name}"
        for table, fks in REPLACED_FKS.items()
        for name in fks
    ),
    *(
        f"ALTER TABLE {table} ADD CONSTRAINT {name} {definition}"
        for table, fks in NEW_FKS.items()
        for name, definition in fks.items()
    ),
    *_natural_key_statements(),
    *NEW_COLUMNS,
    *(
        f"ALTER TABLE {table} ADD CONSTRAINT {name} CHECK ({expression})"
        for table, name, expression in NEW_CHECKS
    ),
    RULE_BINDING_EXCLUSION,
    *NEW_INDEXES,
    *(
        statement
        for table, name, _old, new in REPLACED_CHECKS
        for statement in (
            f"ALTER TABLE {table} DROP CONSTRAINT {name}",
            f"ALTER TABLE {table} ADD CONSTRAINT {name} CHECK ({new})",
        )
    ),
    *(
        statement
        for old_name, _old, _new_name, new in REPLACED_INDEXES
        for statement in (f"DROP INDEX {old_name}", new)
    ),
    *(
        f"COMMENT ON COLUMN {table}.{column} IS {_quoted(comment)}"
        for (table, column), comment in {**COLUMN_COMMENTS, **DERIVED_COMMENTS}.items()
    ),
    ALLOCATION_TOTALS_TABLE,
    ALLOCATION_TOTALS_BACKFILL,
]

# --------------------------------------------------------------------------------------
# Triggers
# --------------------------------------------------------------------------------------

REMOVED_V0001_TRIGGERS: tuple[tuple[str, str], ...] = (
    ("statement_versions", "statement_versions_append_only"),
    ("statement_versions", "statement_versions_no_delete"),
    ("statement_versions", "statement_versions_no_truncate"),
    ("repayments", "repayments_allocations_within_amount"),
    ("statements", "statements_allocations_same_currency_account"),
)
REMOVED_V0001_FUNCTIONS: tuple[str, ...] = (
    "forbid_amount_update()",
    "forbid_statement_version_delete()",
    "statements_allocation_check()",
)


def _derive_trigger(table: str, column: str, parent: str, key: str, source: str) -> str:
    name = f"{table}_{DERIVED_TRIGGER_SUFFIX[column]}"
    return (
        f"CREATE TRIGGER {name} BEFORE INSERT OR UPDATE OF {key}, {column} ON public.{table} "
        f"FOR EACH ROW EXECUTE FUNCTION public.derive_from_parent("
        f"'{column}', '{parent}', '{key}', '{source}')"
    )


def _column_guard(table: str, name: str, columns: Sequence[str], *, update_of: bool) -> str:
    event = f"UPDATE OF {', '.join(columns)}" if update_of else "UPDATE"
    arguments = ", ".join(f"'{column}'" for column in columns)
    return (
        f"CREATE TRIGGER {name} BEFORE {event} ON public.{table} "
        f"FOR EACH ROW EXECUTE FUNCTION public.forbid_column_update({arguments})"
    )


NEW_TRIGGERS: list[str] = [
    *(
        f"CREATE TRIGGER {table}_workspace_immutable BEFORE UPDATE OF workspace_id "
        f"ON public.{table} FOR EACH ROW EXECUTE FUNCTION public.forbid_workspace_change()"
        for table in WORKSPACE_GUARDED_TABLES
    ),
    *(
        f"CREATE TRIGGER {table}_row_version BEFORE UPDATE ON public.{table} "
        f"FOR EACH ROW EXECUTE FUNCTION public.bump_row_version()"
        for table in SYNCABLE_TABLES
    ),
    *(
        f"CREATE TRIGGER {table}_immutable BEFORE UPDATE ON public.{table} "
        f"FOR EACH ROW EXECUTE FUNCTION public.forbid_fact_rewrite()"
        for table in IMMUTABLE_FACT_TABLES
    ),
    *(
        _column_guard(table, f"{table}_amounts_immutable", columns, update_of=False)
        for table, columns in SNAPSHOT_IMMUTABLE_COLUMNS.items()
    ),
    _column_guard(
        "currency_accounts",
        "currency_accounts_identity_immutable",
        ("credit_account_id", "currency"),
        update_of=True,
    ),
    _column_guard(
        "cash_accounts", "cash_accounts_currency_immutable", ("currency",), update_of=True
    ),
    *(
        statement
        for table in PURGE_GUARDED_TABLES
        for statement in (
            f"CREATE TRIGGER {table}_no_delete BEFORE DELETE ON public.{table} "
            f"FOR EACH ROW EXECUTE FUNCTION public.forbid_fact_delete()",
            f"CREATE TRIGGER {table}_no_truncate BEFORE TRUNCATE ON public.{table} "
            f"FOR EACH STATEMENT EXECUTE FUNCTION public.forbid_fact_delete()",
        )
    ),
    *(
        _derive_trigger(table, column, parent, key, source)
        for table, column, _type, parent, key, source in DERIVED_COLUMNS
    ),
    "CREATE TRIGGER statement_lines_same_transaction BEFORE INSERT ON public.statement_lines "
    "FOR EACH ROW EXECUTE FUNCTION public.check_statement_line_transaction()",
    "CREATE TRIGGER credit_pools_no_cycle BEFORE INSERT OR UPDATE OF parent_pool_id "
    "ON public.credit_pools FOR EACH ROW EXECUTE FUNCTION public.check_credit_pool_cycle()",
    "CREATE TRIGGER cards_no_replacement_cycle BEFORE INSERT OR UPDATE OF replaced_by_card_id "
    "ON public.cards FOR EACH ROW EXECUTE FUNCTION public.check_card_replacement_cycle()",
    "CREATE TRIGGER repayment_allocations_totals "
    "AFTER INSERT OR UPDATE OF repayment_id, amount_minor, deleted_at OR DELETE "
    "ON public.repayment_allocations "
    "FOR EACH ROW EXECUTE FUNCTION public.maintain_repayment_allocation_totals()",
    # Re-created with the R2-15 columns: lowering the amount, reversing/failing or
    # tombstoning a repayment re-checks its allocations at COMMIT.
    """
CREATE CONSTRAINT TRIGGER repayments_allocations_within_amount
    AFTER UPDATE OF amount_minor, status, deleted_at ON public.repayments
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION public.repayments_allocation_check()
""",
]

NEW_FUNCTION_SIGNATURES: tuple[str, ...] = (
    "public.check_statement_line_transaction()",
    "public.check_card_replacement_cycle()",
    "public.check_credit_pool_cycle()",
    "public.maintain_repayment_allocation_totals()",
    "public.add_to_repayment_allocation_total(uuid, uuid, bigint)",
    "public.derive_from_parent()",
    "public.forbid_fact_delete()",
    "public.forbid_column_update()",
    "public.forbid_fact_rewrite()",
    "public.bump_row_version()",
    "public.inserted_by_current_transaction(xid)",
    "public.looks_like_pan(text)",
    "public.luhn_valid(text)",
)

UPGRADE: list[str] = [
    *PAN_FUNCTIONS,
    *NEW_FUNCTIONS,
    *HARDENED_FUNCTIONS,
    *(f"DROP TRIGGER {name} ON {table}" for table, name in REMOVED_V0001_TRIGGERS),
    *(f"DROP FUNCTION {signature}" for signature in REMOVED_V0001_FUNCTIONS),
    *SCHEMA,
    *NEW_TRIGGERS,
]


def _downgrade_statements() -> list[str]:
    def trigger_names() -> list[tuple[str, str]]:
        names = [(t, f"{t}_workspace_immutable") for t in WORKSPACE_GUARDED_TABLES]
        names += [(t, f"{t}_row_version") for t in SYNCABLE_TABLES]
        names += [(t, f"{t}_immutable") for t in IMMUTABLE_FACT_TABLES]
        names += [(t, f"{t}_amounts_immutable") for t in SNAPSHOT_IMMUTABLE_COLUMNS]
        names += [
            ("currency_accounts", "currency_accounts_identity_immutable"),
            ("cash_accounts", "cash_accounts_currency_immutable"),
        ]
        names += [(t, f"{t}_no_delete") for t in PURGE_GUARDED_TABLES]
        names += [(t, f"{t}_no_truncate") for t in PURGE_GUARDED_TABLES]
        names += [(t, f"{t}_{DERIVED_TRIGGER_SUFFIX[c]}") for t, c, *_rest in DERIVED_COLUMNS]
        names += [
            ("statement_lines", "statement_lines_same_transaction"),
            ("credit_pools", "credit_pools_no_cycle"),
            ("cards", "cards_no_replacement_cycle"),
            ("repayment_allocations", "repayment_allocations_totals"),
            ("repayments", "repayments_allocations_within_amount"),
        ]
        return names

    statements = [f"DROP TRIGGER {name} ON {table}" for table, name in trigger_names()]
    statements.append("DROP TABLE repayment_allocation_totals")
    statements += [
        f"COMMENT ON COLUMN {table}.{column} IS NULL" for table, column in COLUMN_COMMENTS
    ]  # derived columns (and their comments) are dropped below
    statements += [f"DROP INDEX ix_{table}_{column}" for table, column in reversed(FK_INDEXES)]
    statements += [
        "DROP INDEX ix_jobs_running_locked_until",
        "DROP INDEX uq_jobs_dedupe_key_active",
        "DROP INDEX ix_sync_changes_workspace_id_txid_seq",
        "DROP INDEX ix_idempotency_keys_created_at",
        "ALTER TABLE rule_bindings DROP CONSTRAINT ex_rule_bindings_account_period",
    ]
    for _old_name, old, new_name, _new in reversed(REPLACED_INDEXES):
        statements += [f"DROP INDEX {new_name}", old]
    for table, name, old, _new in reversed(REPLACED_CHECKS):
        statements += [
            f"ALTER TABLE {table} DROP CONSTRAINT {name}",
            f"ALTER TABLE {table} ADD CONSTRAINT {name} CHECK ({old})",
        ]
    statements += [
        f"ALTER TABLE {table} DROP CONSTRAINT {name}"
        for table, name, _expression in reversed(NEW_CHECKS)
    ]
    statements += [
        "ALTER TABLE source_documents ALTER COLUMN dek_wrapped SET NOT NULL",
        "ALTER TABLE source_documents ALTER COLUMN storage_key SET NOT NULL",
        "ALTER TABLE jobs DROP COLUMN dedupe_key",
        "ALTER TABLE sync_changes DROP COLUMN txid",
        "ALTER TABLE cash_events DROP COLUMN recorded_at",
        "ALTER TABLE cash_events DROP COLUMN event_tz",
        "ALTER TABLE transactions DROP COLUMN observed_at",
        "ALTER TABLE repayments DROP COLUMN recorded_at",
        "ALTER TABLE repayments DROP COLUMN credit_posted_precision",
        "ALTER TABLE repayments DROP COLUMN cash_debited_precision",
        "ALTER TABLE repayments DROP COLUMN event_tz",
    ]
    for name, (table, columns, was_constraint) in reversed(PARTIAL_UNIQUES.items()):
        statements.append(f"DROP INDEX {name}")
        if was_constraint:
            statements.append(f"ALTER TABLE {table} ADD CONSTRAINT {name} UNIQUE ({columns})")
    statements.append("ALTER TABLE plan_allocations ALTER COLUMN card_id DROP NOT NULL")
    for table, columns in NATURAL_PKS.items():
        statements += [
            f"ALTER TABLE {table} DROP CONSTRAINT pk_{table}",
            f"ALTER TABLE {table} ADD CONSTRAINT pk_{table} PRIMARY KEY ({columns})",
        ]
    statements += [
        f"ALTER TABLE {table} DROP CONSTRAINT {name}"
        for table, fks in NEW_FKS.items()
        for name in fks
    ]
    statements += [
        f"ALTER TABLE {table} ADD CONSTRAINT {name} {definition}"
        for table, fks in REPLACED_FKS.items()
        for name, definition in fks.items()
    ]
    statements += [
        f"ALTER TABLE {table} DROP CONSTRAINT {name}" for table, name, _cols in DERIVED_KEYS
    ]
    statements += [
        f"ALTER TABLE {table} DROP COLUMN {column}"
        for table, column, *_rest in reversed(DERIVED_COLUMNS)
    ]
    statements += [
        f"ALTER TABLE {table} DROP CONSTRAINT {name}" for table, name, _cols in PARENT_KEYS
    ]
    # Restore the 0001 functions and triggers exactly (CREATE OR REPLACE without a SET
    # clause also clears the pinned search_path).
    statements += [
        V0001_FUNCTIONS[name]
        for name in (
            "forbid_amount_update",
            "forbid_statement_version_delete",
            "statements_allocation_check",
        )
    ]
    statements += [
        V0001_FUNCTIONS[name].replace("CREATE FUNCTION", "CREATE OR REPLACE FUNCTION", 1)
        for name in (
            "check_repayment_allocations",
            "repayment_allocations_check",
            "repayments_allocation_check",
            "check_template_scope",
            "check_rule_subject_scope",
            "forbid_workspace_change",
        )
    ]
    statements += list(V0001_TRIGGERS.values())
    statements += [f"DROP FUNCTION {signature}" for signature in NEW_FUNCTION_SIGNATURES]
    return statements


DOWNGRADE: list[str] = _downgrade_statements()


def upgrade() -> None:
    """Apply the post-review fixes (data-model §10)."""
    for statement in UPGRADE:
        op.execute(statement)


def downgrade() -> None:
    """Return exactly to revision 0001 (fails loudly if live data no longer fits 0001)."""
    for statement in DOWNGRADE:
        op.execute(statement)
