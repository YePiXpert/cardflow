"""Database roles (migrations 0003/0004) and the LOGIN roles of ``cardflow db-provision``.

Migration 0003 creates five NOLOGIN group roles and grants every privilege to them, 0004
(T-011) a sixth, ``cardflow_auth_lookup``; no process ever logs in as one of them, nor as
the migration superuser. The processes log in with LOGIN roles that are members of the
groups (:data:`LOGIN_ROLES`)::

    login role             member of                                   used by
    cardflow_api           cardflow_app     (INHERIT)                  cardflow api
    cardflow_worker_login  cardflow_worker  (INHERIT)                  cardflow worker
                           cardflow_purge   (NOINHERIT, SET ROLE only)
    cardflow_admin_login   cardflow_admin   (INHERIT)                  admin console (T-031)

``cardflow_purge`` is granted WITH INHERIT FALSE, SET TRUE: its DELETE privileges apply only
after an explicit ``SET LOCAL ROLE cardflow_purge`` in the purge transaction.
``cardflow_admin_views`` owns the ``admin.*`` views and ``cardflow_auth_lookup`` the SECURITY
DEFINER lookup functions resolve_pairing_code / resolve_refresh_token (0004); neither may
ever have members: a member could act with their cross-workspace read access.

:func:`provision_login_role` creates or updates one login role idempotently: attributes
(LOGIN, NOSUPERUSER, NOCREATEDB, NOCREATEROLE, NOREPLICATION, NOBYPASSRLS), the password
and exactly the memberships of its spec (anything else is revoked). The password is turned
into a SCRAM-SHA-256 verifier on the client (libpq ``PQencryptPasswordConn``, as psql's
``\\password`` does), so neither the server log (``log_statement``) nor any error message
can contain it; this module never logs or returns it. Run it as a superuser (or a role with
CREATEROLE and ADMIN on the groups), after ``cardflow migrate``.
"""

from dataclasses import dataclass, field
from typing import Any, Final

import psycopg
from psycopg import sql
from sqlalchemy import text
from sqlalchemy.engine import Connection

APP_ROLE: Final = "cardflow_app"
WORKER_ROLE: Final = "cardflow_worker"
ADMIN_ROLE: Final = "cardflow_admin"
PURGE_ROLE: Final = "cardflow_purge"
ADMIN_VIEWS_ROLE: Final = "cardflow_admin_views"
AUTH_LOOKUP_ROLE: Final = "cardflow_auth_lookup"
GROUP_ROLES: Final = (
    APP_ROLE,
    WORKER_ROLE,
    ADMIN_ROLE,
    PURGE_ROLE,
    ADMIN_VIEWS_ROLE,
    AUTH_LOOKUP_ROLE,
)
MEMBERLESS_ROLES: Final = (ADMIN_VIEWS_ROLE, AUTH_LOOKUP_ROLE)
"""Group roles that own objects reading across workspaces; nobody may be their member."""

MIN_PASSWORD_LENGTH: Final = 16
LOGIN_ATTRIBUTES: Final = (
    "LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS INHERIT"
)
_EXPECTED_FLAGS: Final = {
    "rolcanlogin": True,
    "rolsuper": False,
    "rolcreatedb": False,
    "rolcreaterole": False,
    "rolreplication": False,
    "rolbypassrls": False,
    "rolinherit": True,
}


class ProvisionError(RuntimeError):
    """Provisioning refused or impossible; the message never contains a password."""


@dataclass(frozen=True, slots=True)
class Membership:
    """Membership of a login role in a group role (PostgreSQL 16+ grant options)."""

    group: str
    inherit: bool
    set_role: bool


@dataclass(frozen=True, slots=True)
class LoginRole:
    """A LOGIN role and the setting that holds its password (``<SETTING>_FILE``)."""

    name: str
    memberships: tuple[Membership, ...]
    password_setting: str
    purpose: str


API_LOGIN: Final = LoginRole(
    "cardflow_api",
    (Membership(APP_ROLE, inherit=True, set_role=False),),
    "database_api_password",
    "API (cardflow api)",
)
WORKER_LOGIN: Final = LoginRole(
    "cardflow_worker_login",
    (
        Membership(WORKER_ROLE, inherit=True, set_role=False),
        Membership(PURGE_ROLE, inherit=False, set_role=True),
    ),
    "database_worker_password",
    "job worker (cardflow worker); SET ROLE cardflow_purge for physical deletion",
)
ADMIN_LOGIN: Final = LoginRole(
    "cardflow_admin_login",
    (Membership(ADMIN_ROLE, inherit=True, set_role=False),),
    "database_admin_password",
    "admin console (T-031)",
)
LOGIN_ROLES: Final = {"api": API_LOGIN, "worker": WORKER_LOGIN, "admin": ADMIN_LOGIN}


@dataclass(frozen=True, slots=True)
class ProvisionResult:
    """What :func:`provision_login_role` did (no secret in here)."""

    role: str
    created: bool
    attributes_changed: tuple[str, ...] = ()
    granted: tuple[str, ...] = ()
    revoked: tuple[str, ...] = ()
    memberships: tuple[str, ...] = field(default=())

    def describe(self) -> str:
        """One printable line; the password is shown as ``********``."""
        parts = ["created" if self.created else "updated", "password ******** (scram-sha-256)"]
        if self.attributes_changed:
            parts.append(f"attributes fixed: {', '.join(self.attributes_changed)}")
        if self.granted:
            parts.append(f"granted: {', '.join(self.granted)}")
        if self.revoked:
            parts.append(f"revoked: {', '.join(self.revoked)}")
        parts.append(f"member of: {', '.join(self.memberships) or '-'}")
        return f"{self.role}: " + "; ".join(parts)


def _describe_membership(membership: Membership) -> str:
    inherit = "inherit" if membership.inherit else "noinherit"
    set_role = "set" if membership.set_role else "noset"
    return f"{membership.group} ({inherit}, {set_role})"


_MEMBERSHIPS: Final = text(
    """
    SELECT g.rolname AS grp, m.inherit_option, m.set_option, m.admin_option,
           gr.rolname AS grantor
      FROM pg_catalog.pg_auth_members AS m
      JOIN pg_catalog.pg_roles AS g ON g.oid = m.roleid
      JOIN pg_catalog.pg_roles AS r ON r.oid = m.member
      JOIN pg_catalog.pg_roles AS gr ON gr.oid = m.grantor
     WHERE r.rolname = :name
     ORDER BY g.rolname, gr.rolname
    """
)
_ROLE: Final = text(
    """
    SELECT rolcanlogin, rolsuper, rolcreatedb, rolcreaterole, rolreplication, rolbypassrls,
           rolinherit
      FROM pg_catalog.pg_roles WHERE rolname = :name
    """
)
_GROUPS: Final = text(
    """
    SELECT rolname, rolcanlogin, rolsuper, rolbypassrls, rolcreaterole, rolcreatedb,
           rolreplication
      FROM pg_catalog.pg_roles WHERE rolname = ANY (:names)
    """
)
_MEMBERS_OF: Final = text(
    """
    SELECT g.rolname AS grp, r.rolname AS member, m.inherit_option
      FROM pg_catalog.pg_auth_members AS m
      JOIN pg_catalog.pg_roles AS g ON g.oid = m.roleid
      JOIN pg_catalog.pg_roles AS r ON r.oid = m.member
     WHERE g.rolname = ANY (:groups) OR r.rolname = ANY (:groups)
    """
)


def group_role_problems(connection: Connection) -> list[str]:
    """Why the group roles of migrations 0003/0004 are not in a safe state (empty = fine).

    Missing roles (run ``cardflow migrate`` first); a group role that can log in, is a
    superuser or has BYPASSRLS/CREATEROLE/CREATEDB/REPLICATION; a group role that is itself
    a member of something; any member of cardflow_admin_views or cardflow_auth_lookup
    (:data:`MEMBERLESS_ROLES`); a member that inherits cardflow_purge (its privileges must
    need an explicit SET ROLE).
    """
    problems: list[str] = []
    found = {row.rolname: row for row in connection.execute(_GROUPS, {"names": list(GROUP_ROLES)})}
    missing = [name for name in GROUP_ROLES if name not in found]
    if missing:
        problems.append(f"missing group roles {', '.join(missing)} (run cardflow migrate first)")
    for name, row in sorted(found.items()):
        flags = [
            flag
            for flag in ("rolcanlogin", "rolsuper", "rolbypassrls", "rolcreaterole", "rolcreatedb")
            if getattr(row, flag)
        ]
        if row.rolreplication:
            flags.append("rolreplication")
        if flags:
            problems.append(f"group role {name} must not have {', '.join(flags)}")
    for row in connection.execute(_MEMBERS_OF, {"groups": list(GROUP_ROLES)}):
        if row.member in GROUP_ROLES:
            problems.append(f"group role {row.member} must not be a member of {row.grp}")
        elif row.grp in MEMBERLESS_ROLES:
            problems.append(f"{row.member} must not be a member of {row.grp}")
        elif row.grp == PURGE_ROLE and row.inherit_option:
            problems.append(f"{row.member} inherits {PURGE_ROLE}; grant it WITH INHERIT FALSE")
    return problems


def _raw_connection(connection: Connection) -> "psycopg.Connection[Any]":
    raw = connection.connection.dbapi_connection
    if not isinstance(raw, psycopg.Connection):
        raise ProvisionError("provisioning needs the psycopg driver")
    return raw


def _execute(connection: Connection, statement: sql.Composable) -> None:
    with _raw_connection(connection).cursor() as cursor:
        cursor.execute(statement)


def _grant(connection: Connection, role: str, membership: Membership) -> None:
    _execute(
        connection,
        sql.SQL("GRANT {group} TO {role} WITH INHERIT {inherit}, SET {set_role}").format(
            group=sql.Identifier(membership.group),
            role=sql.Identifier(role),
            inherit=sql.SQL("TRUE" if membership.inherit else "FALSE"),
            set_role=sql.SQL("TRUE" if membership.set_role else "FALSE"),
        ),
    )


def _revoke(connection: Connection, role: str, group: str, grantor: str) -> None:
    _execute(
        connection,
        sql.SQL("REVOKE {group} FROM {role} GRANTED BY {grantor}").format(
            group=sql.Identifier(group),
            role=sql.Identifier(role),
            grantor=sql.Identifier(grantor),
        ),
    )


def provision_login_role(
    connection: Connection, login: LoginRole, password: str
) -> ProvisionResult:
    """Create or update ``login`` in the caller's transaction (see the module docstring).

    Refuses a password shorter than :data:`MIN_PASSWORD_LENGTH` and an existing role that is
    a superuser (never demotes the account it may be running as).
    """
    if len(password) < MIN_PASSWORD_LENGTH:
        raise ProvisionError(
            f"password for {login.name} is shorter than {MIN_PASSWORD_LENGTH} characters"
        )
    existing = connection.execute(_ROLE, {"name": login.name}).first()
    if existing is not None and existing.rolsuper:
        raise ProvisionError(f"{login.name} exists and is a superuser; refusing to change it")
    verifier = (
        _raw_connection(connection)
        .pgconn.encrypt_password(password.encode(), login.name.encode(), b"scram-sha-256")
        .decode()
    )
    command = "CREATE ROLE" if existing is None else "ALTER ROLE"
    _execute(
        connection,
        sql.SQL("{command} {role} WITH {attributes} PASSWORD {verifier}").format(
            command=sql.SQL(command),
            role=sql.Identifier(login.name),
            attributes=sql.SQL(LOGIN_ATTRIBUTES),
            verifier=sql.Literal(verifier),
        ),
    )
    attributes_changed: tuple[str, ...] = ()
    if existing is not None:
        attributes_changed = tuple(
            flag for flag, wanted in _EXPECTED_FLAGS.items() if getattr(existing, flag) != wanted
        )

    expected = {membership.group: membership for membership in login.memberships}
    current = connection.execute(_MEMBERSHIPS, {"name": login.name}).all()
    revoked: list[str] = []
    stale_groups = {
        row.grp
        for row in current
        if row.grp not in expected
        or row.admin_option
        or row.inherit_option != expected[row.grp].inherit
        or row.set_option != expected[row.grp].set_role
    }
    kept_groups = {row.grp for row in current} - stale_groups
    for row in current:
        if row.grp in stale_groups:
            _revoke(connection, login.name, row.grp, row.grantor)
            if row.grp not in expected:
                revoked.append(row.grp)
    granted: list[str] = []
    for group, membership in expected.items():
        if group not in kept_groups:
            _grant(connection, login.name, membership)
            granted.append(_describe_membership(membership))
    return ProvisionResult(
        role=login.name,
        created=existing is None,
        attributes_changed=attributes_changed,
        granted=tuple(granted),
        revoked=tuple(sorted(set(revoked))),
        memberships=tuple(_describe_membership(m) for m in login.memberships),
    )
