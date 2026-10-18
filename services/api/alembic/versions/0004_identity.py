"""Device pairing codes, identity lookups and the snapshot tombstone rule (T-011).

Revision ID: 0004
Revises: 0003
Create Date: 2026-10-18

Run as the PostgreSQL superuser, like 0003. Design notes: services/api/cardflow/identity/
(module docstrings) and evidence/m0/T-011/.

pairing_codes (API-01, ADR-011)
    One-time codes an operator creates on the server (``cardflow pairing create``). A
    bootstrap code (``workspace_id`` NULL) registers a device into a NEW workspace with an
    anonymous owner; a join code registers a device into its workspace. Only the SHA-256 of
    the normalised code is stored (``code_hash``); the code is shown once. A code expires
    after its TTL (at most 24 hours, CHECK) and is used once: the registration records
    ``used_*`` in the same transaction that creates the device, and from then on those
    columns are frozen (trigger ``pairing_codes_single_use``); the identity columns never
    change (``pairing_codes_immutable``). Both triggers reuse 0002's forbid_column_update().
    ``used_key_hash`` / ``used_request_hash`` (Idempotency-Key and canonical request, hashed)
    let a retried registration be recognised without storing any token (review R2-26).

    Row-level security: the API (cardflow_app) sees a code only while
    ``app.pairing_code_id`` names it -- the registration binds it after resolving the code --
    and only within the bound workspace: a join code's own workspace, a used bootstrap
    code's new workspace, or (unused bootstrap code) the workspace being created. It may
    record the use (UPDATE of the used_* columns), nothing else; it cannot insert codes. Codes
    are created by the operator CLI with the migration (superuser) credentials. cardflow_purge
    deletes the codes of the workspace it purges.

Lookups before a workspace is known (evidence/m0/T-006/rls-design.md §8)
    resolve_pairing_code(code_hash) and resolve_refresh_token(token_hash) are SECURITY
    DEFINER functions owned by the new group role cardflow_auth_lookup: NOLOGIN, no members,
    no attributes; it holds USAGE on schema public, SELECT on exactly the columns the two
    functions read and a SELECT policy USING (true) on those two tables -- no BYPASSRLS, no
    superuser owner. They match only the hash of an unguessable secret and return the
    minimum needed to bind a workspace: (row id, workspace id). search_path is pinned, table
    names are qualified with ``public.``. EXECUTE is revoked from PUBLIC (and from the owner
    itself) and granted to cardflow_app only. Like 0003's roles the group role is
    cluster-wide and survives the downgrade, without any privilege in this database.

Other changes
    * devices.app_version (API-01 input, AP-08 "App 版本"): optional, format-checked, never a
      card number; the API may update it.
    * auth_sessions.idempotency_key_hash: SHA-256 of the Idempotency-Key of the request that
      issued the session (registration or refresh), so a retried request can replace a
      session whose response the client never received instead of tripping reuse detection.
    * limit_snapshots / cash_balance_snapshots (data-model §10.13): deleted_at can go from
      NULL to a value once; a tombstoned snapshot row is frozen like the five immutable fact
      tables (trigger ``<table>_tombstone_once`` runs 0002's forbid_fact_rewrite() only for
      rows that are already tombstoned).

Declarations (tests/db/test_rls_grants.py merges them with 0003's, revision by revision):
TABLE_ACCESS, POLICIES, RLS_TABLES, IMMUTABLE_COLUMNS, OWN_FUNCTIONS, FUNCTION_EXECUTE,
SECURITY_DEFINER_FUNCTIONS, FUNCTION_OWNERS, GROUP_ROLES, BUSINESS_ROLES,
SCHEMA_PUBLIC_USERS and PURGEABLE_TABLES list what this revision adds or changes.
"""

from collections.abc import Sequence
from dataclasses import dataclass

from alembic import op

revision: str = "0004"
down_revision: str | Sequence[str] | None = "0003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

APP = "cardflow_app"
WORKER = "cardflow_worker"
ADMIN = "cardflow_admin"
PURGE = "cardflow_purge"
ADMIN_VIEWS = "cardflow_admin_views"
AUTH_LOOKUP = "cardflow_auth_lookup"
GROUP_ROLES: tuple[str, ...] = (APP, WORKER, ADMIN, PURGE, ADMIN_VIEWS, AUTH_LOOKUP)
NEW_GROUP_ROLES: tuple[str, ...] = (AUTH_LOOKUP,)
BUSINESS_ROLES: tuple[str, ...] = (APP, WORKER)
SCHEMA_PUBLIC_USERS: tuple[str, ...] = (AUTH_LOOKUP,)  # 0003 granted APP, WORKER, ADMIN, PURGE

CURRENT_WORKSPACE = "NULLIF(current_setting('app.workspace_id', true), '')::uuid"
CURRENT_PAIRING_CODE = "NULLIF(current_setting('app.pairing_code_id', true), '')::uuid"
SHA256_HEX = "'^[0-9a-f]{64}$'"
PAIRING_CODE_MAX_LIFETIME = "interval '24 hours'"

# --------------------------------------------------------------------------------------
# Tables and columns
# --------------------------------------------------------------------------------------

PAIRING_CODES_TABLE = f"""
CREATE TABLE public.pairing_codes (
    id UUID NOT NULL DEFAULT uuidv7(),
    purpose TEXT NOT NULL,
    workspace_id UUID,
    code_hash CHAR(64) NOT NULL,
    created_via TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,
    used_workspace_id UUID,
    used_by_device_id UUID,
    used_key_hash CHAR(64),
    used_request_hash CHAR(64),
    CONSTRAINT pk_pairing_codes PRIMARY KEY (id),
    CONSTRAINT uq_pairing_codes_code_hash UNIQUE (code_hash),
    CONSTRAINT fk_pairing_codes_workspace_id
        FOREIGN KEY (workspace_id) REFERENCES public.workspaces (id),
    CONSTRAINT fk_pairing_codes_used_workspace_id_used_by_device_id
        FOREIGN KEY (used_workspace_id, used_by_device_id)
        REFERENCES public.devices (workspace_id, id),
    CONSTRAINT ck_pairing_codes_purpose
        CHECK (purpose IN ('bootstrap_workspace', 'join_workspace')),
    CONSTRAINT ck_pairing_codes_workspace_matches_purpose
        CHECK ((purpose = 'bootstrap_workspace') = (workspace_id IS NULL)),
    CONSTRAINT ck_pairing_codes_created_via CHECK (created_via IN ('cli', 'admin', 'device')),
    CONSTRAINT ck_pairing_codes_code_hash_hex CHECK (code_hash ~ {SHA256_HEX}),
    CONSTRAINT ck_pairing_codes_used_key_hash_hex CHECK (used_key_hash ~ {SHA256_HEX}),
    CONSTRAINT ck_pairing_codes_used_request_hash_hex CHECK (used_request_hash ~ {SHA256_HEX}),
    CONSTRAINT ck_pairing_codes_lifetime
        CHECK (expires_at > created_at AND expires_at <= created_at + {PAIRING_CODE_MAX_LIFETIME}),
    CONSTRAINT ck_pairing_codes_use_recorded_together
        CHECK (num_nulls(used_at, used_workspace_id, used_by_device_id, used_key_hash,
                         used_request_hash) IN (0, 5)),
    CONSTRAINT ck_pairing_codes_used_before_expiry CHECK (used_at <= expires_at),
    CONSTRAINT ck_pairing_codes_used_in_own_workspace
        CHECK (workspace_id IS NULL OR used_workspace_id = workspace_id)
)
"""
PAIRING_CODE_INDEXES: tuple[str, ...] = (
    "CREATE INDEX ix_pairing_codes_workspace_id ON public.pairing_codes (workspace_id)",
    "CREATE INDEX ix_pairing_codes_used_workspace_id_used_by_device_id "
    "ON public.pairing_codes (used_workspace_id, used_by_device_id)",
)

# (table, column) -> comment; tests/db/test_model_drift.py compares them with the models.
COLUMN_COMMENTS: dict[tuple[str, str], str] = {
    ("pairing_codes", "workspace_id"): (
        "Workspace a join code adds a device to; NULL for a bootstrap code, which creates "
        "a new workspace."
    ),
    ("pairing_codes", "code_hash"): (
        "SHA-256 (hex) of the normalised pairing code; the code itself is never stored."
    ),
    ("pairing_codes", "created_via"): (
        "Who created the code: cli (operator on the server); admin and device are reserved "
        "for the admin console and for invitations from an existing device."
    ),
    ("pairing_codes", "used_workspace_id"): (
        "Workspace the code was used for: the new workspace of a bootstrap code, the code's "
        "own workspace of a join code."
    ),
    ("pairing_codes", "used_key_hash"): (
        "SHA-256 of the Idempotency-Key of the registration that used the code (replay check)."
    ),
    ("pairing_codes", "used_request_hash"): (
        "SHA-256 of the canonical registration request without the code (replay check)."
    ),
    ("devices", "app_version"): "App version reported at registration or refresh.",
    ("auth_sessions", "idempotency_key_hash"): (
        "SHA-256 of the Idempotency-Key of the request that issued this session "
        "(registration or refresh); a retried request may replace a session whose response "
        "the client never received."
    ),
}

NEW_COLUMNS: tuple[str, ...] = (
    "ALTER TABLE public.devices ADD COLUMN app_version TEXT",
    "ALTER TABLE public.devices ADD CONSTRAINT ck_devices_app_version_format "
    "CHECK (app_version ~ '^[0-9A-Za-z.+-]{1,64}$')",
    "ALTER TABLE public.devices ADD CONSTRAINT ck_devices_app_version_not_pan "
    "CHECK (NOT looks_like_pan(app_version))",
    "ALTER TABLE public.auth_sessions ADD COLUMN idempotency_key_hash CHAR(64)",
    "ALTER TABLE public.auth_sessions ADD CONSTRAINT ck_auth_sessions_idempotency_key_hash_hex "
    f"CHECK (idempotency_key_hash ~ {SHA256_HEX})",
)
DROPPED_COLUMNS: tuple[str, ...] = (
    "ALTER TABLE public.auth_sessions DROP COLUMN idempotency_key_hash",
    "ALTER TABLE public.devices DROP COLUMN app_version",
)

# --------------------------------------------------------------------------------------
# Triggers (reuse 0002's guard functions)
# --------------------------------------------------------------------------------------

PAIRING_IDENTITY_COLUMNS: tuple[str, ...] = (
    "id",
    "purpose",
    "workspace_id",
    "code_hash",
    "created_via",
    "created_at",
    "expires_at",
)
PAIRING_USE_COLUMNS: tuple[str, ...] = (
    "used_at",
    "used_workspace_id",
    "used_by_device_id",
    "used_key_hash",
    "used_request_hash",
)
# data-model §10.13: the two snapshot tables take the tombstone once, like 0002's facts.
TOMBSTONE_ONCE_TABLES: tuple[str, ...] = ("limit_snapshots", "cash_balance_snapshots")


def _arguments(columns: Sequence[str]) -> str:
    return ", ".join(f"'{column}'" for column in columns)


NEW_TRIGGERS: dict[str, tuple[str, str]] = {
    "pairing_codes_immutable": (
        "pairing_codes",
        "CREATE TRIGGER pairing_codes_immutable BEFORE UPDATE ON public.pairing_codes "
        "FOR EACH ROW EXECUTE FUNCTION "
        f"public.forbid_column_update({_arguments(PAIRING_IDENTITY_COLUMNS)})",
    ),
    "pairing_codes_single_use": (
        "pairing_codes",
        "CREATE TRIGGER pairing_codes_single_use BEFORE UPDATE ON public.pairing_codes "
        "FOR EACH ROW WHEN (OLD.used_at IS NOT NULL) EXECUTE FUNCTION "
        f"public.forbid_column_update({_arguments(PAIRING_USE_COLUMNS)})",
    ),
    **{
        f"{table}_tombstone_once": (
            table,
            f"CREATE TRIGGER {table}_tombstone_once BEFORE UPDATE ON public.{table} "
            "FOR EACH ROW WHEN (OLD.deleted_at IS NOT NULL) "
            "EXECUTE FUNCTION public.forbid_fact_rewrite()",
        )
        for table in TOMBSTONE_ONCE_TABLES
    },
}

# --------------------------------------------------------------------------------------
# Lookup functions (SECURITY DEFINER, owned by cardflow_auth_lookup)
# --------------------------------------------------------------------------------------

RESOLVE_PAIRING_CODE = "public.resolve_pairing_code(character)"
RESOLVE_REFRESH_TOKEN = "public.resolve_refresh_token(character)"  # noqa: S105 - a signature
FUNCTION_SQL: dict[str, str] = {
    RESOLVE_PAIRING_CODE: """
CREATE FUNCTION public.resolve_pairing_code(p_code_hash CHAR(64))
RETURNS TABLE (pairing_code_id uuid, workspace_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
    -- Exact match on the hash of an unguessable code; returns the row and the workspace to
    -- bind (NULL: an unused bootstrap code). The caller checks expiry and use under RLS.
    SELECT p.id, coalesce(p.workspace_id, p.used_workspace_id)
      FROM public.pairing_codes AS p
     WHERE p.code_hash = p_code_hash
$$
""",
    RESOLVE_REFRESH_TOKEN: """
CREATE FUNCTION public.resolve_refresh_token(p_token_hash CHAR(64))
RETURNS TABLE (session_id uuid, workspace_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
    -- Exact match on the hash of a 256-bit refresh token; returns the session and its
    -- workspace. Revocation, expiry and rotation are checked by the caller under RLS.
    SELECT s.id, s.workspace_id
      FROM public.auth_sessions AS s
     WHERE s.refresh_token_hash = p_token_hash
$$
""",
}
OWN_FUNCTIONS: tuple[str, ...] = tuple(FUNCTION_SQL)
FUNCTION_EXECUTE: dict[str, tuple[str, ...]] = {
    RESOLVE_PAIRING_CODE: (APP,),
    RESOLVE_REFRESH_TOKEN: (APP,),
}
SECURITY_DEFINER_FUNCTIONS: tuple[str, ...] = (RESOLVE_PAIRING_CODE, RESOLVE_REFRESH_TOKEN)
FUNCTION_OWNERS: dict[str, str] = {
    RESOLVE_PAIRING_CODE: AUTH_LOOKUP,
    RESOLVE_REFRESH_TOKEN: AUTH_LOOKUP,
}

# --------------------------------------------------------------------------------------
# Privileges and policies (declarative, as in 0003)
# --------------------------------------------------------------------------------------


@dataclass(frozen=True)
class Access:
    """Privileges of one role on one table: True = whole table, a tuple = those columns."""

    select: bool | tuple[str, ...] = False
    insert: bool | tuple[str, ...] = False
    update: tuple[str, ...] = ()
    delete: bool = False


@dataclass(frozen=True)
class Policy:
    """CREATE POLICY <name> ON public.<table> FOR <command> TO <roles> USING / WITH CHECK."""

    table: str
    name: str
    command: str
    roles: tuple[str, ...]
    using: str | None = None
    check: str | None = None


RLS_TABLES: tuple[str, ...] = ("pairing_codes",)
PURGEABLE_TABLES: tuple[str, ...] = ("pairing_codes",)
TENANT_TABLES: tuple[str, ...] = ()  # pairing_codes.workspace_id is nullable (bootstrap codes)

PAIRING_APP_READ: tuple[str, ...] = (
    "id",
    "purpose",
    "workspace_id",
    "created_via",
    "created_at",
    "expires_at",
    *PAIRING_USE_COLUMNS,
)
PAIRING_LOOKUP_READ: tuple[str, ...] = ("id", "workspace_id", "used_workspace_id", "code_hash")
SESSION_LOOKUP_READ: tuple[str, ...] = ("id", "workspace_id", "refresh_token_hash")
DEVICE_APP_UPDATE: tuple[str, ...] = ("name", "last_seen_at", "revoked_at", "app_version")

# Merged over 0003's map: a (table, role) entry here replaces 0003's.
TABLE_ACCESS: dict[str, dict[str, Access]] = {
    "pairing_codes": {
        APP: Access(select=PAIRING_APP_READ, update=PAIRING_USE_COLUMNS),
        PURGE: Access(select=True, delete=True),
        AUTH_LOOKUP: Access(select=PAIRING_LOOKUP_READ),
    },
    "auth_sessions": {AUTH_LOOKUP: Access(select=SESSION_LOOKUP_READ)},
    "devices": {APP: Access(select=True, insert=True, update=DEVICE_APP_UPDATE)},
}
SEQUENCE_USAGE: dict[str, tuple[str, ...]] = {}
# Replaces 0003's entry for auth_sessions (its four columns plus the new one).
IMMUTABLE_COLUMNS: dict[str, tuple[str, ...]] = {
    "pairing_codes": ("purpose", "code_hash", "created_via", "expires_at"),
    "auth_sessions": (
        "device_id",
        "refresh_token_hash",
        "rotated_from_id",
        "expires_at",
        "idempotency_key_hash",
    ),
}

PAIRING_ROW_VISIBLE = (
    f"id = {CURRENT_PAIRING_CODE} "
    f"AND coalesce(workspace_id, used_workspace_id, {CURRENT_WORKSPACE}) = {CURRENT_WORKSPACE}"
)
PAIRING_ROW_WRITABLE = (
    f"id = {CURRENT_PAIRING_CODE} "
    f"AND coalesce(workspace_id, used_workspace_id) = {CURRENT_WORKSPACE}"
)
POLICIES: list[Policy] = [
    Policy(
        "pairing_codes",
        "pairing_registration",
        "ALL",
        (APP,),
        PAIRING_ROW_VISIBLE,
        PAIRING_ROW_WRITABLE,
    ),
    Policy(
        "pairing_codes",
        "purge_scope",
        "ALL",
        (PURGE,),
        f"coalesce(workspace_id, used_workspace_id) = {CURRENT_WORKSPACE}",
    ),
    Policy("pairing_codes", "auth_lookup_read", "SELECT", (AUTH_LOOKUP,), "true"),
    Policy("auth_sessions", "auth_lookup_read", "SELECT", (AUTH_LOOKUP,), "true"),
]

# --------------------------------------------------------------------------------------
# Statement builders
# --------------------------------------------------------------------------------------

_ROLE_FLAGS = "NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS"
_NEW_ROLE_ARRAY = "ARRAY[" + ", ".join(f"'{role}'" for role in NEW_GROUP_ROLES) + "]"
CREATE_ROLES = f"""
DO $$
DECLARE
    v_role text;
BEGIN
    FOREACH v_role IN ARRAY {_NEW_ROLE_ARRAY} LOOP
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
         WHERE rolname = ANY ({_NEW_ROLE_ARRAY})
           AND (rolcanlogin OR rolsuper OR rolbypassrls OR rolcreaterole OR rolcreatedb
                OR rolreplication)
    ) OR EXISTS (
        SELECT 1 FROM pg_catalog.pg_auth_members AS m
          JOIN pg_catalog.pg_roles AS r ON r.oid = m.roleid
         WHERE r.rolname = ANY ({_NEW_ROLE_ARRAY})
    ) THEN
        RAISE EXCEPTION 'cardflow_auth_lookup must be NOLOGIN NOSUPERUSER NOBYPASSRLS '
                        'NOCREATEROLE NOCREATEDB NOREPLICATION without members; fix it first'
            USING ERRCODE = 'insufficient_privilege';
    END IF;
END
$$
"""  # noqa: S608 - constants only


def _columns(columns: tuple[str, ...]) -> str:
    return f" ({', '.join(columns)})"


def _quoted(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def _grant(table: str, role: str, access: Access) -> list[str]:
    statements: list[str] = []
    for privilege, value in (("SELECT", access.select), ("INSERT", access.insert)):
        if value is True:
            statements.append(f"GRANT {privilege} ON public.{table} TO {role}")
        elif value:
            statements.append(f"GRANT {privilege}{_columns(value)} ON public.{table} TO {role}")
    if access.update:
        statements.append(f"GRANT UPDATE{_columns(access.update)} ON public.{table} TO {role}")
    if access.delete:
        statements.append(f"GRANT DELETE ON public.{table} TO {role}")
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


def _function_statements() -> list[str]:
    statements: list[str] = []
    for signature, body in FUNCTION_SQL.items():
        statements += [
            body,
            f"ALTER FUNCTION {signature} OWNER TO {FUNCTION_OWNERS[signature]}",
            # The owner keeps no EXECUTE of its own: only the declared callers may run it.
            f"REVOKE ALL ON FUNCTION {signature} FROM PUBLIC, {FUNCTION_OWNERS[signature]}",
            f"GRANT EXECUTE ON FUNCTION {signature} TO {', '.join(FUNCTION_EXECUTE[signature])}",
        ]
    return statements


UPGRADE: list[str] = [
    CREATE_ROLES,
    f"GRANT USAGE ON SCHEMA public TO {', '.join(SCHEMA_PUBLIC_USERS)}",
    PAIRING_CODES_TABLE,
    *PAIRING_CODE_INDEXES,
    *NEW_COLUMNS,
    *(
        f"COMMENT ON COLUMN public.{table}.{column} IS {_quoted(comment)}"
        for (table, column), comment in COLUMN_COMMENTS.items()
    ),
    *(statement for _table, statement in NEW_TRIGGERS.values()),
    # Grants: the whole new table, the lookup role's columns, the API's new device column.
    *_grant("pairing_codes", APP, TABLE_ACCESS["pairing_codes"][APP]),
    *_grant("pairing_codes", PURGE, TABLE_ACCESS["pairing_codes"][PURGE]),
    *_grant("pairing_codes", AUTH_LOOKUP, TABLE_ACCESS["pairing_codes"][AUTH_LOOKUP]),
    *_grant("auth_sessions", AUTH_LOOKUP, TABLE_ACCESS["auth_sessions"][AUTH_LOOKUP]),
    f"GRANT UPDATE (app_version) ON public.devices TO {APP}",
    *(f"ALTER TABLE public.{table} ENABLE ROW LEVEL SECURITY" for table in RLS_TABLES),
    *(f"ALTER TABLE public.{table} FORCE ROW LEVEL SECURITY" for table in RLS_TABLES),
    *(_policy_statement(policy) for policy in POLICIES),
    *_function_statements(),
]

DOWNGRADE: list[str] = [
    *(f"DROP FUNCTION {signature}" for signature in reversed(FUNCTION_SQL)),
    *(
        f"DROP POLICY {policy.name} ON public.{policy.table}"
        for policy in reversed(POLICIES)
        if policy.table not in RLS_TABLES  # the new table's policies go with the table
    ),
    f"REVOKE ALL ON public.auth_sessions FROM {AUTH_LOOKUP}",
    *(f"DROP TRIGGER {name} ON public.{table}" for name, (table, _sql) in NEW_TRIGGERS.items()),
    "DROP TABLE public.pairing_codes",
    *DROPPED_COLUMNS,  # their constraints, comments and column grants go with them
    f"REVOKE USAGE ON SCHEMA public FROM {', '.join(SCHEMA_PUBLIC_USERS)}",
    # cardflow_auth_lookup stays (cluster-wide, like 0003's group roles); it now holds no
    # privilege in this database.
]


def upgrade() -> None:
    """Create pairing_codes, the lookup role and functions, the new columns and triggers."""
    for statement in UPGRADE:
        op.execute(statement)


def downgrade() -> None:
    """Return exactly to revision 0003; the cluster-wide role cardflow_auth_lookup is kept."""
    for statement in DOWNGRADE:
        op.execute(statement)
