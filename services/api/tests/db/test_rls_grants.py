"""Roles, grants and policies of revisions 0003/0004 checked against the catalog (T-006).

Expectations come from the revisions' declarative maps (``rls_declarations``: TABLE_ACCESS,
POLICIES, FUNCTION_EXECUTE ...) and from 0002's own constants (derived columns, syncable
tables, protected facts), never written down here. All checks read a pristine database at
head (``head_engine``) as the superuser, so tables other tests create in the shared session
database cannot interfere. Behaviour under the real roles is in tests/db/test_rls.py.

A new table fails :func:`test_every_table_is_under_rls_or_listed_as_an_exception` until it
gets row-level security and policies, or is listed in :data:`NO_RLS_TABLES` with a reason;
it fails :func:`test_privileges_match_the_declared_access` until its grants are declared.
"""

from collections import defaultdict
from collections.abc import Callable
from typing import TYPE_CHECKING, Final

import pytest
from sqlalchemy import text
from sqlalchemy.engine import Connection, Engine

from cardflow.db.roles import ADMIN_ROLE, ADMIN_VIEWS_ROLE, APP_ROLE, group_role_problems

if TYPE_CHECKING:
    from tests.db.conftest import Catalog, MigrationScripts, RlsDeclarations

pytestmark = [pytest.mark.db, pytest.mark.usefixtures("require_head_schema")]

# Tables without row-level security, each with the reason (everything else has RLS).
NO_RLS_TABLES: Final[dict[str, str]] = {
    "currencies": "global reference data (ISO 4217 minor units), no workspace; read-only "
    "for every role, writable by none",
    "worker_heartbeats": "system table without workspace (one row per worker process); the "
    "worker writes it, the API (/readyz) and the admin console read it",
    "alembic_version": "Alembic bookkeeping; read-only for every role (/readyz, migrate --check)",
}
GLOBAL_RLS_TABLES: Final[dict[str, str]] = {
    "workspaces": "the tenant root: its id is the workspace key",
    "users": "global identities: visible as the bound user or as members of the bound workspace",
}
TABLE_PRIVILEGES: Final = ("DELETE", "TRUNCATE", "REFERENCES", "TRIGGER", "MAINTAIN")
COLUMN_PRIVILEGES: Final = ("SELECT", "INSERT", "UPDATE")
WORKSPACE_BINDING: Final = "NULLIF(current_setting('app.workspace_id'::text, true), ''::text)"
PINNED_SEARCH_PATH: Final = "search_path=pg_catalog, public, pg_temp"

# Content columns that no admin role may read (review §5.7 plus the allocation total); the
# content tables themselves are not readable by the admin roles at all.
CONTENT_COLUMNS: Final[dict[str, tuple[str, ...]]] = {
    "transactions": ("amount_minor", "merchant"),
    "statement_lines": ("description", "amount_minor"),
    "extraction_candidates": ("raw_value", "normalized_value", "confirmed_value"),
    "idempotency_keys": ("response_body",),
    "sync_changes": ("payload",),
    "sync_conflicts": ("server_payload", "client_payload"),
    "plan_runs": ("result",),
    "jobs": ("payload", "result"),
    "source_documents": ("storage_key", "dek_wrapped"),
    "workspaces": ("dek_wrapped",),
    "users": ("password_hash",),
    "auth_sessions": ("refresh_token_hash", "idempotency_key_hash"),
    "repayment_allocation_totals": ("allocated_minor",),
    "pairing_codes": ("code_hash", "used_key_hash", "used_request_hash"),
}


def _rows(connection: Connection, sql: str, **params: object) -> list[tuple[object, ...]]:
    return [tuple(row) for row in connection.execute(text(sql), params)]


def _public_columns(connection: Connection) -> dict[str, list[str]]:
    columns: dict[str, list[str]] = defaultdict(list)
    for table, column in _rows(
        connection,
        """
        SELECT c.relname, a.attname FROM pg_attribute AS a
          JOIN pg_class AS c ON c.oid = a.attrelid
          JOIN pg_namespace AS n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public' AND c.relkind = 'r' AND a.attnum > 0 AND NOT a.attisdropped
         ORDER BY c.relname, a.attnum
        """,
    ):
        columns[str(table)].append(str(column))
    return dict(columns)


# --- coverage --------------------------------------------------------------------------------


def test_every_table_is_under_rls_or_listed_as_an_exception(
    head_engine: Engine, rls_declarations: "RlsDeclarations"
) -> None:
    """Every table with a workspace_id column (plus workspaces and users) has row-level
    security ENABLEd and FORCEd and at least one policy that applies to cardflow_app; every
    table without RLS is one of the listed exceptions."""
    with head_engine.connect() as connection:
        tables = {
            str(name): (bool(enabled), bool(forced), bool(has_workspace))
            for name, enabled, forced, has_workspace in _rows(
                connection,
                """
                SELECT c.relname, c.relrowsecurity, c.relforcerowsecurity,
                       EXISTS (SELECT 1 FROM pg_attribute AS a
                                WHERE a.attrelid = c.oid AND a.attname = 'workspace_id'
                                  AND NOT a.attisdropped)
                  FROM pg_class AS c JOIN pg_namespace AS n ON n.oid = c.relnamespace
                 WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
                """,
            )
        }
        app_policies = {
            str(table)
            for (table,) in _rows(
                connection,
                "SELECT tablename FROM pg_policies WHERE schemaname = 'public' "
                "AND roles && ARRAY[:app, 'public']::name[]",
                app=APP_ROLE,
            )
        }

    must_have_rls = {name for name, (_, _, has_workspace) in tables.items() if has_workspace} | set(
        GLOBAL_RLS_TABLES
    )
    missing = {
        name: {"enabled": enabled, "forced": forced, "app_policy": name in app_policies}
        for name, (enabled, forced, _) in tables.items()
        if name in must_have_rls and not (enabled and forced and name in app_policies)
    }
    assert missing == {}
    without_rls = {name for name, (enabled, forced, _) in tables.items() if not enabled}
    assert without_rls == set(NO_RLS_TABLES)
    assert {name for name, (enabled, _, _) in tables.items() if enabled} == set(
        rls_declarations.rls_tables
    )
    assert must_have_rls == set(rls_declarations.rls_tables)


# --- roles -----------------------------------------------------------------------------------


def test_group_roles_are_plain_nologin_roles(
    head_engine: Engine, rls_declarations: "RlsDeclarations"
) -> None:
    """No group role can log in, is a superuser, bypasses RLS or creates roles/databases;
    none owns a table, function or schema -- except that cardflow_admin_views owns the admin
    views and a dedicated lookup owner (FUNCTION_OWNERS, 0004) owns exactly its SECURITY
    DEFINER functions; no member of a business role bypasses RLS; cardflow_admin_views and
    cardflow_auth_lookup have no members and cardflow_purge is never inherited."""
    with head_engine.connect() as connection:
        flags = _rows(
            connection,
            """
            SELECT rolname, rolcanlogin, rolsuper, rolbypassrls, rolcreaterole, rolcreatedb,
                   rolreplication
              FROM pg_roles WHERE rolname = ANY (:roles)
            """,
            roles=list(rls_declarations.group_roles),
        )
        owned = _rows(
            connection,
            """
            SELECT 'relation', n.nspname || '.' || c.relname, pg_get_userbyid(c.relowner)
              FROM pg_class AS c JOIN pg_namespace AS n ON n.oid = c.relnamespace
             WHERE pg_get_userbyid(c.relowner) = ANY (:roles)
            UNION ALL
            SELECT 'function', p.proname, pg_get_userbyid(p.proowner) FROM pg_proc AS p
             WHERE pg_get_userbyid(p.proowner) = ANY (:roles)
            UNION ALL
            SELECT 'schema', n.nspname, pg_get_userbyid(n.nspowner) FROM pg_namespace AS n
             WHERE pg_get_userbyid(n.nspowner) = ANY (:roles)
            """,
            roles=list(rls_declarations.group_roles),
        )
        privileged_members = _rows(
            connection,
            """
            SELECT g.rolname, r.rolname
              FROM pg_auth_members AS m
              JOIN pg_roles AS g ON g.oid = m.roleid
              JOIN pg_roles AS r ON r.oid = m.member
             WHERE g.rolname = ANY (:roles) AND (r.rolsuper OR r.rolbypassrls)
            """,
            roles=list(rls_declarations.group_roles),
        )
        problems = group_role_problems(connection)

    relations = {(name, owner) for kind, name, owner in owned if kind == "relation"}
    functions = {(name, owner) for kind, name, owner in owned if kind == "function"}
    assert len(flags) == len(rls_declarations.group_roles)
    assert [row for row in flags if any(row[1:])] == []
    assert {kind for kind, _name, _owner in owned} <= {"relation", "function"}
    assert relations == {
        (f"admin.{view}", ADMIN_VIEWS_ROLE) for view in rls_declarations.admin_views
    }
    assert functions == {
        (signature.removeprefix("public.").split("(")[0], owner)
        for signature, owner in rls_declarations.function_owners.items()
    }
    assert privileged_members == []
    assert problems == []


# --- table and column privileges ---------------------------------------------------------------


def _expected_columns(value: object, columns: list[str]) -> set[str]:
    if value is True:
        return set(columns)
    if not value:
        return set()
    assert isinstance(value, tuple)
    return set(value)


def test_privileges_match_the_declared_access(
    head_engine: Engine, rls_declarations: "RlsDeclarations"
) -> None:
    """For every group role, table and column, the effective SELECT/INSERT/UPDATE column
    privileges and the DELETE/TRUNCATE/REFERENCES/TRIGGER/MAINTAIN table privileges are
    exactly what TABLE_ACCESS declares (TRUNCATE, REFERENCES, TRIGGER, MAINTAIN: nobody);
    sequence USAGE as SEQUENCE_USAGE declares."""
    mismatches: list[str] = []
    with head_engine.connect() as connection:
        columns = _public_columns(connection)
        for role in rls_declarations.group_roles:
            actual: dict[tuple[str, str], set[str]] = defaultdict(set)
            for table, column, *granted in _rows(
                connection,
                """
                SELECT c.relname, a.attname,
                       has_column_privilege(:role, c.oid, a.attnum, 'SELECT'),
                       has_column_privilege(:role, c.oid, a.attnum, 'INSERT'),
                       has_column_privilege(:role, c.oid, a.attnum, 'UPDATE')
                  FROM pg_attribute AS a
                  JOIN pg_class AS c ON c.oid = a.attrelid
                  JOIN pg_namespace AS n ON n.oid = c.relnamespace
                 WHERE n.nspname = 'public' AND c.relkind = 'r' AND a.attnum > 0
                   AND NOT a.attisdropped
                """,
                role=role,
            ):
                for privilege, has_it in zip(COLUMN_PRIVILEGES, granted, strict=True):
                    if has_it:
                        actual[(str(table), privilege)].add(str(column))
            table_level = {
                str(table): dict(zip(TABLE_PRIVILEGES, granted, strict=True))
                for table, *granted in _rows(
                    connection,
                    """
                    SELECT c.relname, has_table_privilege(:role, c.oid, 'DELETE'),
                           has_table_privilege(:role, c.oid, 'TRUNCATE'),
                           has_table_privilege(:role, c.oid, 'REFERENCES'),
                           has_table_privilege(:role, c.oid, 'TRIGGER'),
                           has_table_privilege(:role, c.oid, 'MAINTAIN')
                      FROM pg_class AS c JOIN pg_namespace AS n ON n.oid = c.relnamespace
                     WHERE n.nspname = 'public' AND c.relkind = 'r'
                    """,
                    role=role,
                )
            }
            for table, table_columns in columns.items():
                access = rls_declarations.table_access.get(table, {}).get(role)
                wanted = {
                    "SELECT": _expected_columns(access and access.select, table_columns),
                    "INSERT": _expected_columns(access and access.insert, table_columns),
                    "UPDATE": set(access.update) if access else set(),
                }
                for privilege in COLUMN_PRIVILEGES:
                    got = actual.get((table, privilege), set())
                    if got != wanted[privilege]:
                        mismatches.append(
                            f"{role} {privilege} {table}: missing {sorted(wanted[privilege] - got)}"
                            f" unexpected {sorted(got - wanted[privilege])}"
                        )
                for privilege, has_it in table_level[table].items():
                    expected = privilege == "DELETE" and bool(access and access.delete)
                    if has_it != expected:
                        mismatches.append(f"{role} {privilege} {table}: {has_it} != {expected}")
            for sequence, roles in rls_declarations.sequence_usage.items():
                has_usage = connection.execute(
                    text("SELECT has_sequence_privilege(:role, :sequence, 'USAGE')"),
                    {"role": role, "sequence": f"public.{sequence}"},
                ).scalar_one()
                if has_usage != (role in roles):
                    mismatches.append(f"{role} USAGE {sequence}: {has_usage}")

    assert mismatches == []


def test_updatable_columns_respect_the_immutability_rules(
    head_engine: Engine,
    rls_declarations: "RlsDeclarations",
    migration_scripts: "MigrationScripts",
) -> None:
    """No role may UPDATE id or workspace_id (jobs.workspace_id included), 0002's derived
    columns, row_version/updated_at of syncable tables, created_at/recorded_at, any currency
    column, the declared immutable references, or the snapshot amount/time columns; on the
    seven protected fact tables only deleted_at (the tombstone)."""
    schema_0002 = migration_scripts.modules["0002"]
    derived: dict[str, set[str]] = defaultdict(set)
    for table, column, *_rest in schema_0002.DERIVED_COLUMNS:
        derived[table].add(column)
    syncable = set(schema_0002.SYNCABLE_TABLES)
    snapshot_columns = {
        table: set(columns) for table, columns in schema_0002.SNAPSHOT_IMMUTABLE_COLUMNS.items()
    }
    protected = set(schema_0002.PURGE_GUARDED_TABLES)
    assert protected == rls_declarations.protected_fact_tables
    assert sum(len(columns) for columns in derived.values()) == 11

    violations: list[str] = []
    with head_engine.connect() as connection:
        for role, table, column in _rows(
            connection,
            """
            SELECT r.rolname, c.relname, a.attname
              FROM pg_attribute AS a
              JOIN pg_class AS c ON c.oid = a.attrelid
              JOIN pg_namespace AS n ON n.oid = c.relnamespace
             CROSS JOIN pg_roles AS r
             WHERE n.nspname = 'public' AND c.relkind = 'r' AND a.attnum > 0
               AND NOT a.attisdropped AND r.rolname = ANY (:roles)
               AND has_column_privilege(r.oid, c.oid, a.attnum, 'UPDATE')
            """,
            roles=list(rls_declarations.group_roles),
        ):
            table, column = str(table), str(column)
            forbidden = {"id", "workspace_id", "created_at", "recorded_at", "currency"}
            forbidden |= derived.get(table, set())
            forbidden |= rls_declarations.immutable_columns.get(table, frozenset())
            forbidden |= snapshot_columns.get(table, set())
            if table in syncable:
                forbidden |= {"row_version", "updated_at"}
            if column in forbidden or (table in protected and column != "deleted_at"):
                violations.append(f"{role} may UPDATE {table}.{column}")

    assert violations == []


def test_no_role_holds_temp_or_create_and_public_schema_is_restricted(
    head_engine: Engine, rls_declarations: "RlsDeclarations"
) -> None:
    """R2-01 defence in depth: neither PUBLIC nor any group role has TEMP (or CREATE) on the
    database; schema public is usable only by the roles that need it and nobody of ours may
    create in it; schema admin is usable only by cardflow_admin."""
    with head_engine.connect() as connection:
        database = connection.execute(text("SELECT current_database()")).scalar_one()
        database_rights = _rows(
            connection,
            """
            SELECT r, has_database_privilege(r, :db, 'TEMPORARY'),
                   has_database_privilege(r, :db, 'CREATE')
              FROM unnest(CAST(:roles AS text[])) AS r
            """,
            db=database,
            roles=["public", *rls_declarations.group_roles],
        )
        schema_grants = {
            (str(schema), str(grantee), str(privilege))
            for schema, grantee, privilege in _rows(
                connection,
                """
                SELECT n.nspname,
                       CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END,
                       a.privilege_type
                  FROM pg_namespace AS n,
                       aclexplode(coalesce(n.nspacl, acldefault('n', n.nspowner))) AS a
                 WHERE n.nspname IN ('public', 'admin')
                   AND a.grantee <> n.nspowner
                """,
            )
        }

    assert [row for row in database_rights if row[1] or row[2]] == []
    usage_public = {grantee for schema, grantee, p in schema_grants if schema == "public"}
    assert usage_public == set(rls_declarations.schema_public_users)
    assert usage_public == {
        "cardflow_app",
        "cardflow_worker",
        "cardflow_admin",
        "cardflow_purge",
        "cardflow_auth_lookup",  # 0004: its SQL lookup functions resolve public.* at run time
    }
    assert {grantee for schema, grantee, _ in schema_grants if schema == "admin"} == {ADMIN_ROLE}
    assert {privilege for _, _, privilege in schema_grants} == {"USAGE"}


def test_own_functions_are_executable_only_where_needed(
    head_engine: Engine, rls_declarations: "RlsDeclarations"
) -> None:
    """No own function is executable by PUBLIC; the group roles hold EXECUTE exactly as
    FUNCTION_EXECUTE declares (CHECK helpers, statement-line trigger helper, the 0004 lookup
    functions); exactly the declared functions are SECURITY DEFINER, owned by a superuser or
    -- the 0004 lookup functions -- by their declared dedicated owner role, and every own
    function is pinned to ``pg_catalog, public, pg_temp``; every own function is declared."""
    with head_engine.connect() as connection:
        functions = _rows(
            connection,
            """
            SELECT 'public.' || p.proname || '(' || oidvectortypes(p.proargtypes) || ')',
                   p.prosecdef, r.rolsuper, coalesce(array_to_string(p.proconfig, ','), ''),
                   has_function_privilege('public', p.oid, 'EXECUTE'),
                   ARRAY(SELECT g FROM unnest(CAST(:roles AS text[])) AS g
                          WHERE has_function_privilege(g, p.oid, 'EXECUTE') ORDER BY g),
                   r.rolname
              FROM pg_proc AS p
              JOIN pg_namespace AS n ON n.oid = p.pronamespace
              JOIN pg_roles AS r ON r.oid = p.proowner
             WHERE n.nspname = 'public'
               AND NOT EXISTS (SELECT 1 FROM pg_depend AS d
                                WHERE d.objid = p.oid AND d.deptype = 'e')
            """,
            roles=list(rls_declarations.group_roles),
        )
    by_signature = {str(row[0]): row[1:] for row in functions}

    assert set(by_signature) == set(rls_declarations.own_functions)
    assert {name for name, row in by_signature.items() if row[3]} == set()  # PUBLIC
    assert {name: list(row[4]) for name, row in by_signature.items() if row[4]} == {
        name: sorted(roles) for name, roles in rls_declarations.function_execute.items()
    }
    definers = {name for name, row in by_signature.items() if row[0]}
    assert definers == set(rls_declarations.security_definer)
    # Owner of each SECURITY DEFINER function: its declared dedicated role (never a
    # superuser), otherwise the migration superuser.
    declared = rls_declarations.function_owners
    owners = {name: (str(by_signature[name][5]), bool(by_signature[name][1])) for name in definers}
    assert {name: owner for name, (owner, _) in owners.items() if name in declared} == declared
    misowned = [name for name, (_, superuser) in owners.items() if (name in declared) == superuser]
    assert misowned == []
    assert all(PINNED_SEARCH_PATH in by_signature[name][2] for name in by_signature)


def test_policies_match_the_declared_list(
    head_engine: Engine, rls_declarations: "RlsDeclarations"
) -> None:
    """pg_policies holds exactly the declared policies (command, roles, permissive); every
    workspace policy binds through NULLIF(current_setting('app.workspace_id', true), '')."""
    with head_engine.connect() as connection:
        policies = {
            (str(table), str(name)): (str(permissive), str(cmd), sorted(roles), qual, check)
            for table, name, permissive, cmd, roles, qual, check in _rows(
                connection,
                "SELECT tablename, policyname, permissive, cmd, roles, qual, with_check "
                "FROM pg_policies WHERE schemaname = 'public'",
            )
        }

    declared = {
        key: ("PERMISSIVE", policy.command, sorted(policy.roles))
        for key, policy in rls_declarations.policies.items()
    }
    assert {key: value[:3] for key, value in policies.items()} == declared
    isolation = {key: value for key, value in policies.items() if key[1] == "workspace_isolation"}
    assert isolation
    for (table, _name), (_, _, _, qual, check) in isolation.items():
        assert WORKSPACE_BINDING in str(qual), table
        assert WORKSPACE_BINDING in str(check), table


# --- admin metadata --------------------------------------------------------------------------


def test_admin_roles_cannot_read_content(
    head_engine: Engine, rls_declarations: "RlsDeclarations"
) -> None:
    """TC-DB-06 (catalog): neither cardflow_admin nor the owner of the admin views may read
    any content column (review §5.7, the allocation total, every money column ``*_minor``) or
    any column of a business table; cardflow_admin reads job metadata incl. last_error (the
    safe error code AP-05 shows) but not payload/result. The views read only declared
    metadata columns, are security barriers owned by cardflow_admin_views, which has no
    members."""
    content_tables = (rls_declarations.tenant_tables | {"users", "workspaces"}) - {"deletion_tasks"}
    with head_engine.connect() as connection:
        readable = {
            (str(role), str(table), str(column))
            for role, table, column in _rows(
                connection,
                """
                SELECT r.rolname, c.relname, a.attname
                  FROM pg_attribute AS a
                  JOIN pg_class AS c ON c.oid = a.attrelid
                  JOIN pg_namespace AS n ON n.oid = c.relnamespace
                 CROSS JOIN pg_roles AS r
                 WHERE n.nspname = 'public' AND c.relkind = 'r' AND a.attnum > 0
                   AND NOT a.attisdropped AND r.rolname IN (:admin, :views)
                   AND has_column_privilege(r.oid, c.oid, a.attnum, 'SELECT')
                """,
                admin=ADMIN_ROLE,
                views=ADMIN_VIEWS_ROLE,
            )
        }
        used = {
            (str(table), str(column))
            for table, column in _rows(
                connection,
                "SELECT table_name, column_name FROM information_schema.view_column_usage "
                "WHERE view_schema = 'admin'",
            )
        }
        views = _rows(
            connection,
            """
            SELECT c.relname, pg_get_userbyid(c.relowner), c.reloptions
              FROM pg_class AS c JOIN pg_namespace AS n ON n.oid = c.relnamespace
             WHERE n.nspname = 'admin'
            """,
        )
        members = _rows(
            connection,
            "SELECT m.member FROM pg_auth_members AS m WHERE m.roleid = CAST(:role AS regrole)",
            role=ADMIN_VIEWS_ROLE,
        )

    content = {(table, column) for table, columns in CONTENT_COLUMNS.items() for column in columns}
    assert {(t, c) for _, t, c in readable} & content == set()
    assert {(t, c) for _, t, c in readable if c.endswith("_minor")} == set()
    admin_business = {
        (t, c) for role, t, c in readable if role == ADMIN_ROLE and t in content_tables
    }
    assert admin_business == set()
    assert (ADMIN_ROLE, "jobs", "last_error") in readable
    assert (ADMIN_VIEWS_ROLE, "jobs", "last_error") not in readable
    sources = {
        (table, column)
        for table, columns in rls_declarations.admin_view_sources.items()
        for column in columns
    }
    assert used <= sources
    assert used & content == set()
    assert {str(name) for name, _, _ in views} == set(rls_declarations.admin_views)
    assert {(str(owner), tuple(options or ())) for _, owner, options in views} == {
        (ADMIN_VIEWS_ROLE, ("security_barrier=true",))
    }
    assert members == []


def test_catalog_snapshot_sees_the_rls_objects(
    head_engine: Engine,
    read_catalog: Callable[[Connection], "Catalog"],
    rls_declarations: "RlsDeclarations",
) -> None:
    """The catalog snapshot that the exact round-trip test compares (tests/db/conftest.py)
    really contains policies, RLS flags, column grants and the admin views at head."""
    with head_engine.connect() as connection:
        catalog = read_catalog(connection)

    assert len(catalog["policies"]) == len(rls_declarations.policies)
    assert sum(value == "true true" for value in catalog["row_security"].values()) == len(
        rls_declarations.rls_tables
    )
    assert any("cardflow_app=UPDATE" in value for value in catalog["column_privileges"].values())
    assert any(
        "cardflow_purge=DELETE" in value for value in catalog["relation_privileges"].values()
    )
    assert {key.split(".")[1] for key in catalog["views"]} == set(rls_declarations.admin_views)
    assert "PUBLIC=TEMPORARY" not in catalog["database_privileges"]["(database)"]
    assert "PUBLIC=CONNECT" in catalog["database_privileges"]["(database)"]
