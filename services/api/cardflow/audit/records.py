"""Appending audit records: IDs and hashes only (security-privacy SEC-S-09, AP-06).

``audit_log`` is append-only for every role (migration 0003). The API and the worker have
INSERT on ten columns (not ``at``, which the database sets) and no SELECT, so the INSERT is
issued ``inline()``: without the implicit ``RETURNING id`` SQLAlchemy would otherwise add,
which needs SELECT. Rows of another workspace than the bound one are rejected by the
``audit_append`` policy; ``workspace_id`` NULL marks a system-wide entry.

Never put a token, pairing code, password, public key, amount or any other content into an
entry: use :func:`sha256_hex` for a fingerprint (``before_hash`` / ``after_hash``) and IDs for
the actor and the target.
"""

import hashlib
import ipaddress
import uuid
from dataclasses import dataclass
from typing import Final

from sqlalchemy import insert
from sqlalchemy.engine import Connection
from sqlalchemy.orm import Session

from cardflow.audit.models import AuditLog

_AUDIT_LOG: Final = AuditLog.__table__


@dataclass(frozen=True, slots=True)
class AuditEntry:
    """One audited action (``audit_log`` row without ``id`` and ``at``)."""

    action: str
    actor_kind: str
    workspace_id: uuid.UUID | None = None
    actor_id: uuid.UUID | None = None
    target_table: str | None = None
    target_id: uuid.UUID | None = None
    before_hash: str | None = None
    after_hash: str | None = None
    ip: str | None = None


def sha256_hex(data: bytes) -> str:
    """Lower-case hex SHA-256 of ``data`` (fits the ``*_hash`` CHECK constraints)."""
    return hashlib.sha256(data).hexdigest()


def audit_ip(host: str | None) -> str | None:
    """``host`` if it is an IP address (``audit_log.ip`` is INET), else ``None``.

    Test clients and unix sockets report names such as ``testclient``; those are dropped
    rather than failing the audited action.
    """
    if not host:
        return None
    try:
        return str(ipaddress.ip_address(host))
    except ValueError:
        return None


def append_audit(executor: Connection | Session, entry: AuditEntry) -> None:
    """Insert ``entry`` in the caller's transaction (no RETURNING, see the module docstring)."""
    executor.execute(
        insert(_AUDIT_LOG)
        .values(
            workspace_id=entry.workspace_id,
            actor_kind=entry.actor_kind,
            actor_id=entry.actor_id,
            action=entry.action,
            target_table=entry.target_table,
            target_id=entry.target_id,
            before_hash=entry.before_hash,
            after_hash=entry.after_hash,
            ip=entry.ip,
        )
        .inline()
    )
