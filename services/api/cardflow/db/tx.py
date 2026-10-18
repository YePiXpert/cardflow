"""Workspace-scoped transactions: the entry point for row-level security (RLS).

Every query that touches tenant data must run inside :func:`workspace_tx`, which binds
``app.workspace_id`` with ``set_config(..., is_local => true)``. The binding is
transaction-local (``SET LOCAL`` semantics): PostgreSQL discards it at COMMIT/ROLLBACK,
so a pooled connection never carries one workspace into the next request.

The policies of migration 0003 (T-006) compare against
``NULLIF(current_setting('app.workspace_id', true), '')::uuid``: once a connection has had
the setting bound and the transaction ended, ``current_setting`` returns ``''`` rather than
NULL. Without a binding no tenant row is visible or writable.

``app.user_id`` (optional, :data:`USER_GUC`) names the signed-in user: the ``users`` policies
let a session see and update that row even before a membership exists, which is what
registration needs (insert user, workspace, membership, device and session in one
transaction bound to the new workspace and user). ``app.pairing_code_id``
(:data:`PAIRING_CODE_GUC`, migration 0004) names the one pairing code a registration may
read and mark as used (:func:`set_pairing_code_id`). These settings are ordinary GUCs that
any session can set: RLS protects against application mistakes, not against SQL injection
(evidence/m0/T-006/rls-design.md).
"""

import uuid
from collections.abc import Iterator
from contextlib import contextmanager
from typing import Final

from sqlalchemy import text
from sqlalchemy.engine import Connection
from sqlalchemy.orm import Session, sessionmaker

WORKSPACE_GUC: Final = "app.workspace_id"
USER_GUC: Final = "app.user_id"
PAIRING_CODE_GUC: Final = "app.pairing_code_id"
_SET_WORKSPACE: Final = text("SELECT set_config('app.workspace_id', :workspace_id, true)")
_SET_USER: Final = text("SELECT set_config('app.user_id', :user_id, true)")
_SET_PAIRING_CODE: Final = text("SELECT set_config('app.pairing_code_id', :pairing_code_id, true)")


def _require_uuid(value: uuid.UUID, name: str = "workspace_id") -> str:
    if not isinstance(value, uuid.UUID):
        raise TypeError(f"{name} must be uuid.UUID, not {type(value).__name__}")
    return str(value)


def set_workspace_id(connection: Connection | Session, workspace_id: uuid.UUID) -> None:
    """Bind ``app.workspace_id`` for the current transaction of ``connection``.

    Low-level helper for Core connections (e.g. the worker); must be called inside an
    open transaction, otherwise PostgreSQL drops the setting immediately. Prefer
    :func:`workspace_tx` for ORM work.
    """
    connection.execute(_SET_WORKSPACE, {"workspace_id": _require_uuid(workspace_id)})


def set_user_id(connection: Connection | Session, user_id: uuid.UUID) -> None:
    """Bind ``app.user_id`` (the signed-in user) for the current transaction."""
    connection.execute(_SET_USER, {"user_id": _require_uuid(user_id, "user_id")})


def set_pairing_code_id(connection: Connection | Session, pairing_code_id: uuid.UUID) -> None:
    """Bind ``app.pairing_code_id`` for the current transaction (device registration only).

    Under the 0004 policies the API sees and may mark as used exactly this pairing code, and
    only inside the bound workspace.
    """
    connection.execute(
        _SET_PAIRING_CODE, {"pairing_code_id": _require_uuid(pairing_code_id, "pairing_code_id")}
    )


@contextmanager
def workspace_tx(
    session_factory: sessionmaker[Session],
    workspace_id: uuid.UUID,
    *,
    user_id: uuid.UUID | None = None,
) -> Iterator[Session]:
    """Open a session and one transaction bound to ``workspace_id`` (and ``user_id``).

    Commits when the block exits normally, rolls back on any exception, then closes the
    session. Do not call ``session.commit()``/``rollback()`` inside the block: the
    transaction belongs to this context manager, and SQLAlchemy raises
    ``InvalidRequestError`` for any statement issued after it was ended early, so no
    statement can run without the workspace binding.

    Usage::

        with workspace_tx(session_factory, workspace_id) as session:
            session.execute(...)
    """
    bound_id = _require_uuid(workspace_id)
    bound_user = None if user_id is None else _require_uuid(user_id, "user_id")
    with session_factory() as session, session.begin():
        session.execute(_SET_WORKSPACE, {"workspace_id": bound_id})
        if bound_user is not None:
            session.execute(_SET_USER, {"user_id": bound_user})
        yield session
