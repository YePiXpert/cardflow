"""Row-level security, database roles and grants (T-006; data-model §6, §10).

Revision ID: 0003
Revises: 0002
Create Date: 2026-10-17

Deployment prerequisite: migrations run as a PostgreSQL superuser. Only a superuser can
create the roles below, revoke TEMPORARY on the database and own the tables; the three
SECURITY DEFINER trigger functions of the allocation check run as that owner. The
application, the worker and the admin console each log in with their own role, created
by ``cardflow db-provision`` (cardflow/db/roles.py) -- never as the migration superuser.
Design notes and the full matrix: evidence/m0/T-006/rls-design.md.

Group roles (NOLOGIN, NOSUPERUSER, NOBYPASSRLS; created only if missing):

* cardflow_app -- the API. Business tables of the bound workspace (RLS); enqueue and read
  its own jobs; append audit rows; read alembic_version / worker_heartbeats (/readyz).
* cardflow_worker -- the job worker. jobs and worker_heartbeats across workspaces; business
  tables like the API, bound by RLS to the job's workspace. Identity data read-only, no
  access to auth_sessions / idempotency_keys (it must not be able to mint API access).
* cardflow_admin -- the admin console. The admin.* metadata views, official templates
  (workspace_id IS NULL rows of banks / card_products / billing_rule_versions), audit_log
  read-only, job metadata without payload/result. Never a user's financial content.
* cardflow_purge -- physical deletion (workspace purge, tombstone compaction). SELECT and
  DELETE on the tenant tables of the bound workspace; the seven protected fact tables also
  need the transaction's purge token (0002). Granted to the worker login WITH INHERIT FALSE,
  SET TRUE, so its privileges apply only after an explicit SET ROLE.
* cardflow_admin_views -- owner of the admin.* views and nothing else (no members, no
  login). It reads the metadata columns of exactly the tables the views aggregate, through
  SELECT policies USING (true) on those tables: cross-workspace aggregation needs neither
  BYPASSRLS nor a superuser-owned view, and a view that named a content column would fail
  with "permission denied" at run time.

Roles are cluster-wide. downgrade() keeps them on purpose: every database of the cluster
(other deployments, test databases) shares them, DROP ROLE would fail while any database
still grants them something, and login roles that are members would lose their grants
mid-session. After downgrade they hold no privilege in this database.

Row-level security (ENABLE + FORCE) on every table with workspace_id plus workspaces (id)
and users. The binding is ``NULLIF(current_setting('app.workspace_id', true), '')::uuid``
(cardflow/db/tx.py; '' after an earlier transaction ended, data-model §6): no binding -> no
tenant row. users additionally uses ``app.user_id`` (self row; registration). Like
app.workspace_id it is a GUC every session may set: RLS guards against application bugs,
not against SQL injection -- there the composite foreign keys and the 0002 triggers are the
last line (review R2-01).

Privileges come from the declarative maps TABLE_ACCESS and POLICIES below
(tests/db/test_rls_grants.py compares them with the catalog column by column). Business
roles never UPDATE identity columns (id, workspace_id), derived columns, sync bookkeeping
(row_version, updated_at of syncable tables), creation provenance (created_at,
recorded_at), the references that place a row under its parent nor any currency column
(IMMUTABLE_COLUMNS); on the seven protected fact tables only deleted_at (tombstone). Nobody
gets TRUNCATE, REFERENCES, TRIGGER or MAINTAIN; DELETE only workspace_members (API) and
worker_heartbeats (worker) outside cardflow_purge. audit_log is append-only for everyone.

Further changes:

* Database hardening (R2-01 defence in depth): TEMPORARY on the database is revoked from
  PUBLIC and granted to nobody; USAGE on schema public only for the roles above; EXECUTE on
  every own function revoked from PUBLIC -- looks_like_pan / luhn_valid (CHECK constraints)
  and inserted_by_current_transaction (statement-line trigger) are granted to the writers.
* Allocation totals (R2-02): the trigger functions maintain_repayment_allocation_totals,
  repayment_allocations_check and repayments_allocation_check become SECURITY DEFINER
  (search_path already pinned by 0002). Business roles only read repayment_allocation_totals
  and cannot call add_to_repayment_allocation_total / check_repayment_allocations, so the
  sum cannot be rewritten to bypass the check. Trigger functions cannot be called directly,
  and nobody can create a table (no TEMP, no CREATE) to attach them to. The owner is the
  migration superuser, which RLS does not filter; with a non-superuser owner FORCE RLS would
  apply to it and allocations fail closed (tests/db/test_rls.py).
* jobs.status: 'canceled' -> 'cancelled' (data-model §10.12); existing rows are renamed.
* Schema admin with metadata views (admin-console-spec AP-05/07/08): counts, states and
  times only. The "<5" display rule for aggregate statistics belongs to the admin API.
"""

from collections.abc import Sequence
from dataclasses import dataclass

from alembic import op

revision: str = "0003"
down_revision: str | Sequence[str] | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

APP = "cardflow_app"
WORKER = "cardflow_worker"
ADMIN = "cardflow_admin"
PURGE = "cardflow_purge"
ADMIN_VIEWS = "cardflow_admin_views"
GROUP_ROLES: tuple[str, ...] = (APP, WORKER, ADMIN, PURGE, ADMIN_VIEWS)
BUSINESS_ROLES: tuple[str, ...] = (APP, WORKER)
SCHEMA_PUBLIC_USERS: tuple[str, ...] = (APP, WORKER, ADMIN, PURGE)

CURRENT_WORKSPACE = "NULLIF(current_setting('app.workspace_id', true), '')::uuid"
CURRENT_USER_ID = "NULLIF(current_setting('app.user_id', true), '')::uuid"
WORKER_ALIVE_INTERVAL = "interval '2 minutes'"  # deployment-ops §4 (/readyz)
BACKUP_JOB_KIND = "backup"  # ADR-003 job type; T-013 replaces the view if it differs

# --------------------------------------------------------------------------------------
# Tables
# --------------------------------------------------------------------------------------

# workspace_id NOT NULL (same list as 0002's WORKSPACE_GUARDED_TABLES).
TENANT_TABLES: tuple[str, ...] = (
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
# workspace_id NULL = official template, maintained by the admin console.
TEMPLATE_TABLES: tuple[str, ...] = ("banks", "card_products", "billing_rule_versions")
# Row-level security on: everything with a workspace_id, the tenant root and users.
RLS_TABLES: tuple[str, ...] = (
    "users",
    "workspaces",
    *TEMPLATE_TABLES,
    *TENANT_TABLES,
    "audit_log",
    "jobs",
)
# 0002's protected facts (whole row immutable / snapshot columns immutable, purge token).
PROTECTED_FACT_TABLES: tuple[str, ...] = (
    "statement_versions",
    "statement_lines",
    "plan_runs",
    "plan_allocations",
    "plan_run_checks",
    "limit_snapshots",
    "cash_balance_snapshots",
)
# cardflow_purge deletes these (bound workspace). deletion_tasks, audit_log and jobs outlive
# a purged workspace (data-model §9).
PURGEABLE_TABLES: tuple[str, ...] = (
    "workspaces",
    *TEMPLATE_TABLES,
    *(table for table in TENANT_TABLES if table != "deletion_tasks"),
)
TOMBSTONE = ("deleted_at",)

# Columns that business roles never UPDATE beyond the generic ones (id, workspace_id,
# derived columns, row_version/updated_at of syncable tables, created_at/recorded_at): the
# reference that places a row under its parent and every currency column (R2-04/05/11).
# tests/db/test_rls_grants.py checks that no role can update any of them.
IMMUTABLE_COLUMNS: dict[str, tuple[str, ...]] = {
    "workspaces": ("owner_user_id", "kind"),
    "workspace_members": ("user_id",),
    "devices": ("user_id", "platform", "public_key"),
    "auth_sessions": ("device_id", "refresh_token_hash", "rotated_from_id", "expires_at"),
    "consents": ("purpose",),
    "card_products": ("bank_id",),
    "credit_pools": ("bank_id",),
    "credit_accounts": ("bank_id",),
    "credit_pool_members": ("pool_id", "credit_account_id"),
    "currency_accounts": ("credit_account_id", "currency"),
    "cards": ("credit_account_id",),
    "billing_rule_versions": ("subject_kind", "subject_id", "version"),
    "rule_bindings": ("credit_account_id", "currency_account_id", "billing_rule_version_id"),
    "limit_adjustments": ("currency_account_id",),
    "transactions": ("currency_account_id", "currency"),
    "transaction_links": ("from_transaction_id", "to_transaction_id", "kind"),
    "preauth_holds": ("currency_account_id", "currency"),
    "statements": ("currency_account_id",),
    "statement_attributions": ("transaction_id", "statement_id"),
    "installment_plans": ("transaction_id",),
    "installment_schedule": ("plan_id", "period_no"),
    "charges": ("currency_account_id", "currency"),
    "cash_accounts": ("currency",),
    "recurring_items": ("cash_account_id",),
    "repayments": ("currency_account_id", "currency"),
    "repayment_allocations": ("repayment_id", "statement_id"),
    "repayment_allocation_totals": ("repayment_id", "allocated_minor"),
    "source_documents": ("sha256", "mime", "size_bytes", "uploaded_by_device_id"),
    "import_batches": ("kind",),
    "parse_jobs": ("source_document_id",),
    "extraction_candidates": (
        "parse_job_id",
        "field_path",
        "raw_value",
        "normalized_value",
        "raw_location",
        "parser_version",
        "confidence",
    ),
    "import_batch_items": ("import_batch_id", "item_no"),
    "scenarios": ("code",),
    "forecast_runs": ("scenario_id", "input_hash", "result"),
    "plans": ("currency",),
    "plan_invalidations": ("plan_id", "run_id", "cause", "caused_by_table", "caused_by_id"),
    "plan_reservations": ("plan_id", "run_id", "currency_account_id"),
    "cash_events": ("cash_account_id",),
    "snapshot_included_events": ("snapshot_id", "cash_event_id"),
    "cash_transfers": ("from_cash_account_id", "to_cash_account_id", "currency"),
    "reconciliation_items": ("kind", "refs", "source_kind"),
    "sync_conflicts": ("table_name", "row_id", "server_payload", "client_payload"),
    "deletion_tasks": ("requested_at", "grace_until"),
    "jobs": ("id", "kind", "payload", "workspace_id", "created_at"),
}

# UPDATE columns of the business roles (API and worker alike, bound workspace).
BUSINESS_UPDATE: dict[str, tuple[str, ...]] = {
    "users": ("email", "password_hash", "display_name", "updated_at", "deleted_at"),
    "workspaces": ("dek_wrapped", "deleted_at"),
    "workspace_members": ("role", "updated_at"),
    "devices": ("name", "last_seen_at", "revoked_at"),
    "auth_sessions": ("last_used_at", "revoked_at", "revoked_reason"),
    "consents": ("granted_at", "withdrawn_at", "details", "deleted_at", "origin_device_id"),
    "idempotency_keys": (),
    "banks": ("name", "country", "business_tz_default", "source", "deleted_at", "origin_device_id"),
    "card_products": ("name", "network", "source", "deleted_at", "origin_device_id"),
    "credit_pools": ("name", "parent_pool_id", "deleted_at", "origin_device_id"),
    "credit_accounts": (
        "product_id",
        "holder_alias",
        "business_tz",
        "status",
        "opened_on",
        "closed_on",
        "deleted_at",
        "origin_device_id",
    ),
    "credit_pool_members": ("deleted_at", "origin_device_id"),
    "currency_accounts": ("is_primary", "deleted_at", "origin_device_id"),
    "cards": (
        "last4",
        "network",
        "holder_kind",
        "status",
        "expires_ym",
        "replaced_by_card_id",
        "alias",
        "deleted_at",
        "origin_device_id",
    ),
    "billing_rule_versions": (
        "statement_day",
        "statement_day_inclusive",
        "due_kind",
        "due_day",
        "due_month_offset",
        "due_days",
        "due_day_kind",
        "holiday_rollover",
        "cutoff_time",
        "cutoff_tz",
        "source",
        "published_on",
        "effective_from",
        "effective_to",
        "verified_on",
        "review_status",
        "exceptions",
        "deleted_at",
        "origin_device_id",
    ),
    "rule_bindings": ("effective_from", "effective_to", "deleted_at", "origin_device_id"),
    "limit_snapshots": TOMBSTONE,
    "limit_adjustments": (
        "kind",
        "previous_limit_minor",
        "new_limit_minor",
        "effective_on",
        "expires_on",
        "purpose",
        "source_kind",
        "source_document_id",
        "observed_at",
        "confirmation_level",
        "deleted_at",
        "origin_device_id",
    ),
    "transactions": (
        "card_id",
        "txn_type",
        "amount_minor",
        "txn_at",
        "txn_tz",
        "time_precision",
        "posted_on",
        "merchant",
        "mcc",
        "category",
        "status",
        "bank_reference",
        "parent_transaction_id",
        "fingerprint",
        "source_kind",
        "source_document_id",
        "confirmation_level",
        "observed_at",
        "deleted_at",
        "origin_device_id",
    ),
    "transaction_links": ("confirmation_level", "deleted_at", "origin_device_id"),
    "preauth_holds": (
        "card_id",
        "amount_minor",
        "held_at",
        "held_tz",
        "time_precision",
        "expected_release_on",
        "merchant",
        "status",
        "transaction_id",
        "source_kind",
        "source_document_id",
        "confirmation_level",
        "deleted_at",
        "origin_device_id",
    ),
    "statements": (
        "statement_date",
        "due_date",
        "status",
        "current_version_id",
        "deleted_at",
        "origin_device_id",
    ),
    "statement_versions": TOMBSTONE,
    "statement_lines": TOMBSTONE,
    "statement_attributions": ("confirmation_level", "deleted_at", "origin_device_id"),
    "installment_plans": (
        "principal_minor",
        "periods",
        "per_period_rate",
        "fee_mode",
        "remainder_policy",
        "rounding",
        "status",
        "early_settled_at",
        "deleted_at",
        "origin_device_id",
    ),
    "installment_schedule": (
        "principal_minor",
        "interest_minor",
        "statement_date",
        "due_date",
        "status",
        "deleted_at",
        "origin_device_id",
    ),
    "charges": (
        "statement_id",
        "transaction_id",
        "kind",
        "amount_minor",
        "charged_on",
        "details",
        "source_kind",
        "confirmation_level",
        "deleted_at",
        "origin_device_id",
    ),
    "cash_accounts": (
        "name",
        "kind",
        "usable_for_repayment",
        "available_from",
        "reserve_floor_minor",
        "deleted_at",
        "origin_device_id",
    ),
    "cash_balance_snapshots": TOMBSTONE,
    "recurring_items": (
        "label",
        "category",
        "amount_minor",
        "cls",
        "recurrence",
        "starts_on",
        "ends_on",
        "deleted_at",
        "origin_device_id",
    ),
    "repayments": (
        "cash_account_id",
        "amount_minor",
        "status",
        "method",
        "payment_initiated_at",
        "cash_debited_at",
        "credit_posted_at",
        "bank_confirmed_at",
        "evidence_document_id",
        "event_tz",
        "cash_debited_precision",
        "credit_posted_precision",
        "deleted_at",
        "origin_device_id",
    ),
    "repayment_allocations": ("amount_minor", "deleted_at", "origin_device_id"),
    "repayment_allocation_totals": (),
    "source_documents": (
        "storage_key",
        "dek_wrapped",
        "retention_until",
        "deleted_at",
        "origin_device_id",
    ),
    "import_batches": (
        "status",
        "target_currency_account_id",
        "source_document_id",
        "failure_reason",
        "updated_at",
        "confirmed_at",
        "posted_at",
        "rolled_back_at",
    ),
    "parse_jobs": (
        "import_batch_id",
        "job_id",
        "parser",
        "parser_version",
        "status",
        "attempts",
        "failure_reason",
        "started_at",
        "finished_at",
        "updated_at",
    ),
    "extraction_candidates": ("validations", "confirmed_value", "confirmed_by", "confirmed_at"),
    "import_batch_items": (
        "entity_kind",
        "candidate_refs",
        "decision",
        "duplicate_of_id",
        "resulting_entity_kind",
        "resulting_entity_id",
        "updated_at",
    ),
    "dedupe_keys": ("entity_kind", "entity_id"),
    "scenarios": (
        "name",
        "include_expected",
        "income_delay_days",
        "income_scale",
        "expense_scale",
        "event_overrides",
        "same_day_order",
        "description",
        "deleted_at",
        "origin_device_id",
    ),
    "forecast_runs": ("deleted_at", "origin_device_id"),
    "plans": (
        "amount_minor",
        "txn_date",
        "allow_split",
        "max_cards",
        "min_split_minor",
        "payment_lead_days",
        "channel",
        "merchant",
        "category",
        "allow_installment",
        "status",
        "deleted_at",
        "origin_device_id",
    ),
    "plan_runs": TOMBSTONE,
    "plan_allocations": TOMBSTONE,
    "plan_run_checks": TOMBSTONE,
    "plan_invalidations": ("deleted_at", "origin_device_id"),
    "plan_reservations": (
        "cash_account_id",
        "amount_minor",
        "status",
        "linked_transaction_id",
        "deleted_at",
        "origin_device_id",
    ),
    "cash_events": (
        "event_on",
        "event_at",
        "amount_minor",
        "cls",
        "category",
        "label",
        "posting_status",
        "recurring_item_id",
        "linked_repayment_id",
        "linked_plan_run_id",
        "event_tz",
        "deleted_at",
        "origin_device_id",
    ),
    "snapshot_included_events": ("deleted_at", "origin_device_id"),
    "cash_transfers": (
        "amount_minor",
        "sent_on",
        "arrives_on",
        "out_event_id",
        "in_event_id",
        "deleted_at",
        "origin_device_id",
    ),
    "reconciliation_items": (
        "status",
        "suggested_action",
        "resolution",
        "resolved_by",
        "resolved_at",
        "deleted_at",
        "origin_device_id",
    ),
    "sync_changes": (),
    "sync_conflicts": ("status", "resolved_by", "resolved_at"),
    "deletion_tasks": ("status",),
}
# Official templates as the admin console maintains them (rows with workspace_id IS NULL).
ADMIN_TEMPLATE_UPDATE: dict[str, tuple[str, ...]] = {
    table: tuple(column for column in BUSINESS_UPDATE[table] if column != "origin_device_id")
    for table in TEMPLATE_TABLES
}

# INSERT limited to these columns (the rest comes from defaults or the database clock).
JOB_INSERT_COLUMNS = (
    "kind",
    "payload",
    "status",
    "run_after",
    "max_attempts",
    "timeout_s",
    "workspace_id",
    "dedupe_key",
)
SYNC_CHANGE_INSERT_COLUMNS = (
    "workspace_id",
    "table_name",
    "row_id",
    "op",
    "row_version",
    "payload",
    "origin_device_id",
)
AUDIT_INSERT_COLUMNS = (
    "id",
    "workspace_id",
    "actor_kind",
    "actor_id",
    "action",
    "target_table",
    "target_id",
    "before_hash",
    "after_hash",
    "ip",
)
# The worker's job transitions (cardflow/jobs/queue.py); never kind, payload, workspace_id.
WORKER_JOB_UPDATE = (
    "status",
    "run_after",
    "attempts",
    "locked_by",
    "locked_until",
    "heartbeat_at",
    "last_error",
    "result",
    "updated_at",
    "finished_at",
)
# Job metadata for the admin console (AP-05). last_error holds the safe error code that
# T-008 writes (CODE or CODE:ExceptionType, cardflow/jobs/errors.py), never a message.
ADMIN_JOB_COLUMNS = (
    "id",
    "kind",
    "status",
    "run_after",
    "attempts",
    "max_attempts",
    "locked_by",
    "locked_until",
    "heartbeat_at",
    "timeout_s",
    "last_error",
    "workspace_id",
    "created_at",
    "updated_at",
    "finished_at",
    "dedupe_key",
)
# What the owner of the admin.* views reads (metadata only; checked against the views).
ADMIN_VIEW_SOURCES: dict[str, tuple[str, ...]] = {
    "users": ("id", "created_at", "disabled_at", "deleted_at"),
    "workspaces": ("id", "owner_user_id", "kind", "created_at", "deleted_at"),
    "workspace_members": ("workspace_id", "user_id"),
    "devices": (
        "id",
        "workspace_id",
        "user_id",
        "platform",
        "created_at",
        "last_seen_at",
        "revoked_at",
    ),
    "auth_sessions": ("workspace_id", "device_id", "expires_at", "last_used_at", "revoked_at"),
    "deletion_tasks": (
        "id",
        "workspace_id",
        "status",
        "requested_at",
        "grace_until",
        "executed_at",
    ),
    "source_documents": ("workspace_id", "size_bytes", "deleted_at"),
    "sync_changes": ("seq", "workspace_id", "created_at"),
    "jobs": ("kind", "status", "attempts", "run_after", "created_at", "finished_at"),
    "worker_heartbeats": ("last_seen_at",),
    "alembic_version": ("version_num",),
}


@dataclass(frozen=True)
class Access:
    """Privileges of one role on one table: True = whole table, a tuple = those columns."""

    select: bool | tuple[str, ...] = False
    insert: bool | tuple[str, ...] = False
    update: tuple[str, ...] = ()
    delete: bool = False


def _business_access(table: str) -> Access:
    special: dict[str, Access] = {
        "users": Access(select=True, insert=True, update=BUSINESS_UPDATE["users"]),
        "idempotency_keys": Access(select=True, insert=True),
        "repayment_allocation_totals": Access(select=True),
        "sync_changes": Access(select=True, insert=SYNC_CHANGE_INSERT_COLUMNS),
        "workspace_members": Access(
            select=True, insert=True, update=BUSINESS_UPDATE["workspace_members"], delete=True
        ),
    }
    return special.get(table, Access(select=True, insert=True, update=BUSINESS_UPDATE[table]))


def _build_table_access() -> dict[str, dict[str, Access]]:
    access: dict[str, dict[str, Access]] = {}
    for table in ("users", "workspaces", *TEMPLATE_TABLES, *TENANT_TABLES):
        business = _business_access(table)
        access[table] = {APP: business, WORKER: business}
    # The worker writes business data only. Identity, credentials and request bookkeeping
    # stay with the API: a worker that could insert sessions, devices or memberships could
    # mint itself API access to any workspace.
    access["users"][WORKER] = Access(select=True)
    access["workspaces"][WORKER] = Access(select=True, update=("dek_wrapped", "deleted_at"))
    for table in ("workspace_members", "devices", "consents"):
        access[table][WORKER] = Access(select=True)
    for table in ("auth_sessions", "idempotency_keys"):
        del access[table][WORKER]
    access["deletion_tasks"][WORKER] = Access(select=True, update=("status", "executed_at"))
    for table in TEMPLATE_TABLES:
        access[table][ADMIN] = Access(select=True, insert=True, update=ADMIN_TEMPLATE_UPDATE[table])
    for table in PURGEABLE_TABLES:
        access[table][PURGE] = Access(select=True, delete=True)
    # System tables.
    access["jobs"] = {
        APP: Access(select=True, insert=JOB_INSERT_COLUMNS),
        WORKER: Access(select=True, insert=JOB_INSERT_COLUMNS, update=WORKER_JOB_UPDATE),
        ADMIN: Access(select=ADMIN_JOB_COLUMNS),
    }
    access["audit_log"] = {
        APP: Access(insert=AUDIT_INSERT_COLUMNS),
        WORKER: Access(insert=AUDIT_INSERT_COLUMNS),
        ADMIN: Access(select=True),
    }
    access["worker_heartbeats"] = {
        APP: Access(select=True),
        WORKER: Access(
            select=True, insert=True, update=("last_seen_at", "running_jobs"), delete=True
        ),
        ADMIN: Access(select=True),
    }
    for table in ("currencies", "alembic_version"):
        access[table] = {
            APP: Access(select=True),
            WORKER: Access(select=True),
            ADMIN: Access(select=True),
        }
    for table, columns in ADMIN_VIEW_SOURCES.items():
        access[table][ADMIN_VIEWS] = Access(select=columns)
    return access


TABLE_ACCESS: dict[str, dict[str, Access]] = _build_table_access()
SEQUENCE_USAGE: dict[str, tuple[str, ...]] = {"sync_changes_seq_seq": BUSINESS_ROLES}

# --------------------------------------------------------------------------------------
# Policies
# --------------------------------------------------------------------------------------


@dataclass(frozen=True)
class Policy:
    """CREATE POLICY <name> ON public.<table> FOR <command> TO <roles> USING / WITH CHECK."""

    table: str
    name: str
    command: str
    roles: tuple[str, ...]
    using: str | None = None
    check: str | None = None


WORKSPACE_ROW = f"workspace_id = {CURRENT_WORKSPACE}"
# users rows of the bound workspace's members (workspace_members is itself under RLS).
USER_IS_MEMBER = (
    "EXISTS (SELECT 1 FROM public.workspace_members AS m "  # noqa: S608 - constants only
    f"WHERE m.user_id = users.id AND m.workspace_id = {CURRENT_WORKSPACE})"
)


def _isolation_roles(table: str) -> tuple[str, ...]:
    return tuple(
        role for role in (APP, WORKER, PURGE) if TABLE_ACCESS.get(table, {}).get(role) is not None
    )


def _build_policies() -> list[Policy]:
    policies = [
        Policy(
            "workspaces",
            "workspace_isolation",
            "ALL",
            _isolation_roles("workspaces"),
            f"id = {CURRENT_WORKSPACE}",
            f"id = {CURRENT_WORKSPACE}",
        ),
        Policy(
            "users",
            "user_visibility",
            "SELECT",
            BUSINESS_ROLES,
            f"id = {CURRENT_USER_ID} OR {USER_IS_MEMBER}",
        ),
        Policy("users", "user_registration", "INSERT", (APP,), None, f"id = {CURRENT_USER_ID}"),
        Policy(
            "users",
            "user_self_update",
            "UPDATE",
            (APP,),
            f"id = {CURRENT_USER_ID}",
            f"id = {CURRENT_USER_ID}",
        ),
    ]
    for table in (*TEMPLATE_TABLES, *TENANT_TABLES):
        policies.append(
            Policy(
                table,
                "workspace_isolation",
                "ALL",
                _isolation_roles(table),
                WORKSPACE_ROW,
                WORKSPACE_ROW,
            )
        )
    for table in TEMPLATE_TABLES:
        policies += [
            Policy(
                table,
                "template_read",
                "SELECT",
                BUSINESS_ROLES,
                f"workspace_id IS NULL OR workspace_id = {CURRENT_WORKSPACE}",
            ),
            Policy(
                table,
                "template_maintenance",
                "ALL",
                (ADMIN,),
                "workspace_id IS NULL",
                "workspace_id IS NULL",
            ),
        ]
    policies += [
        Policy(
            "audit_log",
            "audit_append",
            "INSERT",
            BUSINESS_ROLES,
            None,
            f"workspace_id IS NULL OR workspace_id = {CURRENT_WORKSPACE}",
        ),
        Policy("audit_log", "audit_review", "SELECT", (ADMIN,), "true"),
        Policy("jobs", "jobs_worker", "ALL", (WORKER,), "true", "true"),
        Policy("jobs", "jobs_app_read", "SELECT", (APP,), WORKSPACE_ROW),
        Policy(
            "jobs",
            "jobs_app_enqueue",
            "INSERT",
            (APP,),
            None,
            f"{WORKSPACE_ROW} AND status = 'queued'",
        ),
        Policy("jobs", "jobs_admin_read", "SELECT", (ADMIN,), "true"),
    ]
    policies += [
        Policy(table, "admin_views_read", "SELECT", (ADMIN_VIEWS,), "true")
        for table in ADMIN_VIEW_SOURCES
        if table in RLS_TABLES
    ]
    return policies


POLICIES: list[Policy] = _build_policies()

# --------------------------------------------------------------------------------------
# Functions
# --------------------------------------------------------------------------------------

# Every function 0001/0002 created (none belongs to an extension).
OWN_FUNCTIONS: tuple[str, ...] = (
    "public.add_to_repayment_allocation_total(uuid, uuid, bigint)",
    "public.bump_row_version()",
    "public.check_card_replacement_cycle()",
    "public.check_credit_pool_cycle()",
    "public.check_repayment_allocations(uuid)",
    "public.check_rule_subject_scope()",
    "public.check_statement_line_transaction()",
    "public.check_template_scope()",
    "public.derive_from_parent()",
    "public.forbid_column_update()",
    "public.forbid_fact_delete()",
    "public.forbid_fact_rewrite()",
    "public.forbid_workspace_change()",
    "public.inserted_by_current_transaction(xid)",
    "public.looks_like_pan(text)",
    "public.luhn_valid(text)",
    "public.maintain_repayment_allocation_totals()",
    "public.repayment_allocations_check()",
    "public.repayments_allocation_check()",
)
# EXECUTE needed by the invoker: CHECK constraints call looks_like_pan (which calls
# luhn_valid); the statement-line trigger calls inserted_by_current_transaction.
FUNCTION_EXECUTE: dict[str, tuple[str, ...]] = {
    "public.looks_like_pan(text)": (APP, WORKER, ADMIN),
    "public.luhn_valid(text)": (APP, WORKER, ADMIN),
    "public.inserted_by_current_transaction(xid)": BUSINESS_ROLES,
}
SECURITY_DEFINER_FUNCTIONS: tuple[str, ...] = (
    "public.maintain_repayment_allocation_totals()",
    "public.repayment_allocations_check()",
    "public.repayments_allocation_check()",
)

# --------------------------------------------------------------------------------------
# Admin metadata views (schema admin, owned by cardflow_admin_views)
# --------------------------------------------------------------------------------------

ADMIN_VIEWS_SQL: dict[str, tuple[str, str]] = {
    "workspace_overview": (
        "One row per workspace: kind, times, member/device counts, last activity, storage, "
        "deletion request (AP-08). No content.",
        """
SELECT w.id AS workspace_id,
       w.kind,
       w.owner_user_id,
       w.created_at,
       w.deleted_at,
       m.member_count,
       d.device_count,
       d.active_device_count,
       greatest(d.last_seen_at, s.last_session_used_at) AS last_active_at,
       c.last_sync_at,
       f.document_count,
       f.document_bytes,
       t.status AS deletion_status,
       t.requested_at AS deletion_requested_at,
       t.grace_until AS deletion_grace_until,
       t.executed_at AS deletion_executed_at
  FROM public.workspaces AS w
 CROSS JOIN LATERAL (
       SELECT count(*) AS member_count
         FROM public.workspace_members AS wm
        WHERE wm.workspace_id = w.id) AS m
 CROSS JOIN LATERAL (
       SELECT count(*) AS device_count,
              count(*) FILTER (WHERE dv.revoked_at IS NULL) AS active_device_count,
              max(dv.last_seen_at) AS last_seen_at
         FROM public.devices AS dv
        WHERE dv.workspace_id = w.id) AS d
 CROSS JOIN LATERAL (
       SELECT max(a.last_used_at) AS last_session_used_at
         FROM public.auth_sessions AS a
        WHERE a.workspace_id = w.id) AS s
  LEFT JOIN LATERAL (
       SELECT sc.created_at AS last_sync_at
         FROM public.sync_changes AS sc
        WHERE sc.workspace_id = w.id
        ORDER BY sc.seq DESC
        LIMIT 1) AS c ON true
 CROSS JOIN LATERAL (
       SELECT count(*) AS document_count,
              coalesce(sum(sd.size_bytes), 0)::bigint AS document_bytes
         FROM public.source_documents AS sd
        WHERE sd.workspace_id = w.id AND sd.deleted_at IS NULL) AS f
  LEFT JOIN LATERAL (
       SELECT dt.status, dt.requested_at, dt.grace_until, dt.executed_at
         FROM public.deletion_tasks AS dt
        WHERE dt.workspace_id = w.id
        ORDER BY dt.requested_at DESC, dt.id DESC
        LIMIT 1) AS t ON true
""",
    ),
    "user_overview": (
        "One row per user: times, workspace and device counts, last device contact (AP-08). "
        "No e-mail, name or password hash.",
        """
SELECT u.id AS user_id,
       u.created_at,
       u.disabled_at,
       u.deleted_at,
       m.workspace_count,
       d.device_count,
       d.active_device_count,
       d.last_seen_at
  FROM public.users AS u
 CROSS JOIN LATERAL (
       SELECT count(*) AS workspace_count
         FROM public.workspace_members AS wm
        WHERE wm.user_id = u.id) AS m
 CROSS JOIN LATERAL (
       SELECT count(*) AS device_count,
              count(*) FILTER (WHERE dv.revoked_at IS NULL) AS active_device_count,
              max(dv.last_seen_at) AS last_seen_at
         FROM public.devices AS dv
        WHERE dv.user_id = u.id) AS d
""",
    ),
    "device_overview": (
        "One row per device: platform, times, revocation, live session count (AP-08). No "
        "device name, key or token.",
        """
SELECT dv.id AS device_id,
       dv.workspace_id,
       dv.user_id,
       dv.platform,
       dv.created_at,
       dv.last_seen_at,
       dv.revoked_at,
       s.active_session_count,
       s.last_session_used_at
  FROM public.devices AS dv
 CROSS JOIN LATERAL (
       SELECT count(*) FILTER (WHERE a.revoked_at IS NULL AND a.expires_at > now())
                  AS active_session_count,
              max(a.last_used_at) AS last_session_used_at
         FROM public.auth_sessions AS a
        WHERE a.workspace_id = dv.workspace_id AND a.device_id = dv.id) AS s
""",
    ),
    "deletion_requests": (
        "Workspace deletion requests with grace period and state (AP-08, R-SYS-09); kept "
        "after the workspace itself is purged.",
        """
SELECT dt.id AS deletion_task_id,
       dt.workspace_id,
       dt.status,
       dt.requested_at,
       dt.grace_until,
       dt.executed_at
  FROM public.deletion_tasks AS dt
""",
    ),
    "job_summary": (
        "Job counts per kind and status with due backlog and times (AP-05, AP-07). No "
        "payload, result or workspace.",
        """
SELECT j.kind,
       j.status,
       count(*) AS job_count,
       count(*) FILTER (WHERE j.status = 'queued' AND j.run_after <= now()) AS due_count,
       min(j.created_at) AS oldest_created_at,
       min(j.run_after) AS earliest_run_after,
       max(j.finished_at) AS last_finished_at,
       max(j.attempts) AS max_attempts_used
  FROM public.jobs AS j
 GROUP BY j.kind, j.status
""",
    ),
    "system_status": (
        "One row: schema revision, live workers, job backlog and the last backup job "
        f"(kind '{BACKUP_JOB_KIND}') for AP-07.",
        f"""
SELECT (SELECT string_agg(v.version_num, ',' ORDER BY v.version_num)
          FROM public.alembic_version AS v) AS schema_revision,
       (SELECT count(*) FROM public.worker_heartbeats AS h
         WHERE h.last_seen_at > now() - {WORKER_ALIVE_INTERVAL}) AS live_workers,
       (SELECT max(h.last_seen_at) FROM public.worker_heartbeats AS h) AS last_worker_seen_at,
       (SELECT count(*) FROM public.jobs AS j WHERE j.status = 'queued') AS queued_jobs,
       (SELECT count(*) FROM public.jobs AS j
         WHERE j.status = 'queued' AND j.run_after <= now()) AS due_jobs,
       (SELECT min(j.run_after) FROM public.jobs AS j
         WHERE j.status = 'queued' AND j.run_after <= now()) AS oldest_due_run_after,
       (SELECT count(*) FROM public.jobs AS j WHERE j.status = 'running') AS running_jobs,
       (SELECT count(*) FROM public.jobs AS j WHERE j.status = 'failed') AS failed_jobs,
       (SELECT count(*) FROM public.jobs AS j WHERE j.status = 'dead') AS dead_jobs,
       (SELECT max(j.finished_at) FROM public.jobs AS j
         WHERE j.kind = '{BACKUP_JOB_KIND}' AND j.status = 'succeeded')
           AS last_backup_succeeded_at,
       b.status AS last_backup_status,
       b.created_at AS last_backup_created_at,
       b.finished_at AS last_backup_finished_at
  FROM (SELECT 1) AS one
  LEFT JOIN LATERAL (
       SELECT j.status, j.created_at, j.finished_at
         FROM public.jobs AS j
        WHERE j.kind = '{BACKUP_JOB_KIND}'
        ORDER BY j.created_at DESC
        LIMIT 1) AS b ON true
""",  # noqa: S608 - constants only
    ),
}

# --------------------------------------------------------------------------------------
# jobs.status spelling (data-model §10.12)
# --------------------------------------------------------------------------------------

JOB_STATUSES_0002 = "('queued', 'running', 'succeeded', 'failed', 'dead', 'canceled')"
JOB_STATUSES_0003 = "('queued', 'running', 'succeeded', 'failed', 'dead', 'cancelled')"


def _job_status_statements(old: str, new: str, statuses: str) -> list[str]:
    return [
        "ALTER TABLE public.jobs DROP CONSTRAINT ck_jobs_status",
        f"UPDATE public.jobs SET status = '{new}' WHERE status = '{old}'",  # noqa: S608 - constants only
        f"ALTER TABLE public.jobs ADD CONSTRAINT ck_jobs_status CHECK (status IN {statuses})",
    ]


# --------------------------------------------------------------------------------------
# Statement builders
# --------------------------------------------------------------------------------------

_ROLE_FLAGS = "NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS"
_ROLE_ARRAY = "ARRAY[" + ", ".join(f"'{role}'" for role in GROUP_ROLES) + "]"
CREATE_ROLES = f"""
DO $$
DECLARE
    v_role text;
BEGIN
    FOREACH v_role IN ARRAY {_ROLE_ARRAY} LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = v_role) THEN
            BEGIN
                EXECUTE format('CREATE ROLE %I {_ROLE_FLAGS}', v_role);
            EXCEPTION WHEN duplicate_object OR unique_violation THEN
                NULL;  -- created concurrently by the migration of another database
            END;
        END IF;
    END LOOP;
    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_roles
         WHERE rolname = ANY ({_ROLE_ARRAY})
           AND (rolcanlogin OR rolsuper OR rolbypassrls OR rolcreaterole OR rolcreatedb
                OR rolreplication)
    ) THEN
        RAISE EXCEPTION 'cardflow group roles must be NOLOGIN NOSUPERUSER NOBYPASSRLS '
                        'NOCREATEROLE NOCREATEDB NOREPLICATION; fix the existing roles first'
            USING ERRCODE = 'insufficient_privilege';
    END IF;
END
$$
"""  # noqa: S608 - constants only


def _database_privilege(action: str) -> str:
    return (
        "DO $$ BEGIN EXECUTE format("
        f"'{action} TEMPORARY ON DATABASE %I {'FROM' if action == 'REVOKE' else 'TO'} PUBLIC', "
        "current_database()); END $$"
    )


def _columns(columns: tuple[str, ...]) -> str:
    return f" ({', '.join(columns)})"


def _grant_statements() -> list[str]:
    statements: list[str] = []
    for table, roles in TABLE_ACCESS.items():
        for role, access in roles.items():
            for privilege, value in (("SELECT", access.select), ("INSERT", access.insert)):
                if value is True:
                    statements.append(f"GRANT {privilege} ON public.{table} TO {role}")
                elif value:
                    statements.append(
                        f"GRANT {privilege}{_columns(value)} ON public.{table} TO {role}"
                    )
            if access.update:
                statements.append(
                    f"GRANT UPDATE{_columns(access.update)} ON public.{table} TO {role}"
                )
            if access.delete:
                statements.append(f"GRANT DELETE ON public.{table} TO {role}")
    for sequence, roles in SEQUENCE_USAGE.items():
        statements.append(f"GRANT USAGE ON SEQUENCE public.{sequence} TO {', '.join(roles)}")
    return statements


def _revoke_statements() -> list[str]:
    statements = [
        f"REVOKE ALL ON public.{table} FROM {', '.join(roles)}"
        for table, roles in TABLE_ACCESS.items()
    ]
    statements += [
        f"REVOKE ALL ON SEQUENCE public.{sequence} FROM {', '.join(roles)}"
        for sequence, roles in SEQUENCE_USAGE.items()
    ]
    return statements


def _policy_statement(policy: Policy) -> str:
    statement = (
        f"CREATE POLICY {policy.name} ON public.{policy.table} AS PERMISSIVE "
        f"FOR {policy.command} TO {', '.join(policy.roles)}"
    )
    if policy.using is not None:
        statement += f" USING ({policy.using})"
    if policy.check is not None:
        statement += f" WITH CHECK ({policy.check})"
    return statement


def _quoted(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def _view_statements() -> list[str]:
    statements = ["CREATE SCHEMA admin", f"GRANT USAGE ON SCHEMA admin TO {ADMIN}"]
    for name, (comment, body) in ADMIN_VIEWS_SQL.items():
        statements += [
            f"CREATE VIEW admin.{name} WITH (security_barrier = true) AS {body.strip()}",
            f"COMMENT ON VIEW admin.{name} IS {_quoted(comment)}",
            f"ALTER VIEW admin.{name} OWNER TO {ADMIN_VIEWS}",
            f"GRANT SELECT ON admin.{name} TO {ADMIN}",
        ]
    return statements


UPGRADE: list[str] = [
    CREATE_ROLES,
    # R2-01 defence in depth: nobody gets TEMP; schema public only for the roles.
    _database_privilege("REVOKE"),
    "REVOKE USAGE ON SCHEMA public FROM PUBLIC",
    f"GRANT USAGE ON SCHEMA public TO {', '.join(SCHEMA_PUBLIC_USERS)}",
    *_job_status_statements("canceled", "cancelled", JOB_STATUSES_0003),
    *(f"REVOKE EXECUTE ON FUNCTION {signature} FROM PUBLIC" for signature in OWN_FUNCTIONS),
    *(
        f"GRANT EXECUTE ON FUNCTION {signature} TO {', '.join(roles)}"
        for signature, roles in FUNCTION_EXECUTE.items()
    ),
    *(f"ALTER FUNCTION {signature} SECURITY DEFINER" for signature in SECURITY_DEFINER_FUNCTIONS),
    *_grant_statements(),
    *(f"ALTER TABLE public.{table} ENABLE ROW LEVEL SECURITY" for table in RLS_TABLES),
    *(f"ALTER TABLE public.{table} FORCE ROW LEVEL SECURITY" for table in RLS_TABLES),
    *(_policy_statement(policy) for policy in POLICIES),
    *_view_statements(),
]

DOWNGRADE: list[str] = [
    *(f"DROP VIEW admin.{name}" for name in reversed(ADMIN_VIEWS_SQL)),
    "DROP SCHEMA admin",
    *(f"DROP POLICY {policy.name} ON public.{policy.table}" for policy in reversed(POLICIES)),
    *(f"ALTER TABLE public.{table} NO FORCE ROW LEVEL SECURITY" for table in RLS_TABLES),
    *(f"ALTER TABLE public.{table} DISABLE ROW LEVEL SECURITY" for table in RLS_TABLES),
    *_revoke_statements(),
    *(f"ALTER FUNCTION {signature} SECURITY INVOKER" for signature in SECURITY_DEFINER_FUNCTIONS),
    *(
        f"REVOKE EXECUTE ON FUNCTION {signature} FROM {', '.join(roles)}"
        for signature, roles in FUNCTION_EXECUTE.items()
    ),
    *(f"GRANT EXECUTE ON FUNCTION {signature} TO PUBLIC" for signature in OWN_FUNCTIONS),
    *_job_status_statements("cancelled", "canceled", JOB_STATUSES_0002),
    f"REVOKE USAGE ON SCHEMA public FROM {', '.join(SCHEMA_PUBLIC_USERS)}",
    "GRANT USAGE ON SCHEMA public TO PUBLIC",
    _database_privilege("GRANT"),
    # The group roles stay (cluster-wide, see the module docstring).
]


def upgrade() -> None:
    """Create the roles, grants, row-level security, policies and admin views."""
    for statement in UPGRADE:
        op.execute(statement)


def downgrade() -> None:
    """Return exactly to revision 0002; the cluster-wide roles are kept."""
    for statement in DOWNGRADE:
        op.execute(statement)
