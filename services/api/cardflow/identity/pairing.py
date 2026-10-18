"""Pairing codes (API-01, ADR-011): format, hashing, TTL and creation by the operator CLI.

A pairing code is 12 symbols of Crockford's base32 alphabet drawn with ``secrets`` -- 60
bits of entropy (the minimum is 50) -- displayed once as ``XXXX-XXXX-XXXX``. Input is
normalised the Crockford way (case-insensitive; ``O`` reads as ``0``, ``I``/``L`` as ``1``;
spaces and hyphens ignored), so a code read aloud or retyped still matches. Only
``pairing_code_hash()`` -- SHA-256 over a domain label and the normalised code -- is stored
(``pairing_codes.code_hash``); with 60 bits and a lifetime of at most 24 hours (10 minutes by
default) even a leaked hash cannot be brute-forced while the code is still usable.

``create_pairing_code`` is what ``cardflow pairing create`` runs. It connects with the
migration (superuser) credentials, like ``cardflow migrate`` and ``cardflow db-provision``:
no LOGIN role of a long-running process (API, worker, admin console) may mint codes,
because a code grants device access to a workspace -- an API or admin console compromised
through SQL injection could otherwise create itself a persistent device in any workspace.
The operator who runs the command on the host already holds those credentials.
"""

import hashlib
import re
import secrets
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Final

from sqlalchemy import func, insert, select
from sqlalchemy.engine import Connection
from sqlalchemy.exc import IntegrityError

from cardflow.audit.records import AuditEntry, append_audit
from cardflow.identity.models import PairingCode
from cardflow.workspaces.models import Workspace

CROCKFORD_ALPHABET: Final = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
CODE_LENGTH: Final = 12
CODE_GROUP: Final = 4
CODE_ENTROPY_BITS: Final = 60  # 12 symbols x log2(32)
MAX_CODE_INPUT_LENGTH: Final = 64

BOOTSTRAP_WORKSPACE: Final = "bootstrap_workspace"
JOIN_WORKSPACE: Final = "join_workspace"
CREATED_VIA_CLI: Final = "cli"

DEFAULT_TTL: Final = timedelta(minutes=10)
MIN_TTL: Final = timedelta(minutes=1)
MAX_TTL: Final = timedelta(hours=24)  # also a CHECK on pairing_codes (migration 0004)

_HASH_LABEL: Final = b"cardflow-pairing-code:v1:"
_SEPARATORS: Final = re.compile(r"[\s-]+")
_ALIASES: Final = str.maketrans({"O": "0", "I": "1", "L": "1"})
_TTL: Final = re.compile(r"(?:(\d{1,3})h)?(?:(\d{1,4})m)?(?:(\d{1,6})s)?")
_UNIQUE_VIOLATION: Final = "23505"
_CREATE_ATTEMPTS: Final = 3

_CODES: Final = PairingCode.__table__
_WORKSPACES: Final = Workspace.__table__


def generate_pairing_code() -> str:
    """A new normalised code: 12 random Crockford base32 symbols (60 bits)."""
    return "".join(secrets.choice(CROCKFORD_ALPHABET) for _ in range(CODE_LENGTH))


def format_pairing_code(code: str) -> str:
    """Display form ``XXXX-XXXX-XXXX`` of a normalised code."""
    return "-".join(code[start : start + CODE_GROUP] for start in range(0, len(code), CODE_GROUP))


def normalize_pairing_code(raw: str) -> str | None:
    """The normalised code for user input, or ``None`` if it cannot be a pairing code."""
    if not isinstance(raw, str) or len(raw) > MAX_CODE_INPUT_LENGTH:
        return None
    compact = _SEPARATORS.sub("", raw).upper().translate(_ALIASES)
    if len(compact) != CODE_LENGTH or any(char not in CROCKFORD_ALPHABET for char in compact):
        return None
    return compact


def pairing_code_hash(code: str) -> str:
    """SHA-256 (hex) stored for a normalised code; the code itself is never stored."""
    return hashlib.sha256(_HASH_LABEL + code.encode("ascii")).hexdigest()


def parse_ttl(text: str) -> timedelta:
    """``90s``, ``10m``, ``2h``, ``1h30m`` ... -> timedelta within [1 minute, 24 hours].

    Raises ``ValueError`` (message safe to print) for anything else.
    """
    match = _TTL.fullmatch(text.strip().lower()) if isinstance(text, str) else None
    if match is None or not any(match.groups()):
        raise ValueError("TTL must look like 90s, 10m, 2h or 1h30m")
    hours, minutes, seconds = (int(part or 0) for part in match.groups())
    ttl = timedelta(hours=hours, minutes=minutes, seconds=seconds)
    if not MIN_TTL <= ttl <= MAX_TTL:
        raise ValueError("TTL must be between 1 minute and 24 hours")
    return ttl


class UnknownWorkspaceError(LookupError):
    """``--workspace`` names no live workspace."""


@dataclass(frozen=True)
class NewPairingCode:
    """A freshly created code; ``code`` (display form) is shown once and never stored."""

    code: str = field(repr=False)
    pairing_code_id: uuid.UUID
    purpose: str
    workspace_id: uuid.UUID | None
    expires_at: datetime


def create_pairing_code(
    connection: Connection,
    *,
    workspace_id: uuid.UUID | None,
    ttl: timedelta = DEFAULT_TTL,
    created_via: str = CREATED_VIA_CLI,
) -> NewPairingCode:
    """Create a bootstrap code (``workspace_id`` None) or a join code, plus its audit row,
    in the caller's transaction (see the module docstring for the connection to use)."""
    if not MIN_TTL <= ttl <= MAX_TTL:
        raise ValueError("TTL must be between 1 minute and 24 hours")
    if workspace_id is not None:
        live = connection.execute(
            select(_WORKSPACES.c.id)
            .where(_WORKSPACES.c.id == workspace_id, _WORKSPACES.c.deleted_at.is_(None))
            .with_for_update(read=True)
        ).first()
        if live is None:
            raise UnknownWorkspaceError("no live workspace with this id")
    purpose = BOOTSTRAP_WORKSPACE if workspace_id is None else JOIN_WORKSPACE
    for attempt in range(_CREATE_ATTEMPTS):
        code = generate_pairing_code()
        try:
            with connection.begin_nested():
                row = connection.execute(
                    insert(_CODES)
                    .values(
                        purpose=purpose,
                        workspace_id=workspace_id,
                        code_hash=pairing_code_hash(code),
                        created_via=created_via,
                        expires_at=func.now() + ttl,
                    )
                    .returning(_CODES.c.id, _CODES.c.expires_at)
                ).one()
        except IntegrityError as exc:  # a 60-bit collision: practically never
            if getattr(exc.orig, "sqlstate", None) != _UNIQUE_VIOLATION or (
                attempt == _CREATE_ATTEMPTS - 1
            ):
                raise
            continue
        break
    append_audit(
        connection,
        AuditEntry(
            action="pairing_code.created",
            actor_kind=created_via,
            workspace_id=workspace_id,
            target_table="pairing_codes",
            target_id=row.id,
        ),
    )
    return NewPairingCode(
        code=format_pairing_code(code),
        pairing_code_id=row.id,
        purpose=purpose,
        workspace_id=workspace_id,
        expires_at=row.expires_at,
    )
