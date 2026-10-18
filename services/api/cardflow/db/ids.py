"""Client-side UUIDv7 (RFC 9562 §5.7) for rows whose id is needed before the INSERT.

The database default is ``uuidv7()`` (PostgreSQL 18); Python 3.13 has no ``uuid.uuid7``.
Registration needs the new workspace and user ids up front, to bind ``app.workspace_id`` /
``app.user_id`` before inserting (cardflow/db/tx.py), so it generates them here with the
same layout: 48-bit Unix time in milliseconds, version 7, 74 random bits from ``secrets``.
"""

import secrets
import time
import uuid
from typing import Final

_VERSION: Final = 0x7
_VARIANT: Final = 0b10
_MS_MASK: Final = (1 << 48) - 1


def uuid7() -> uuid.UUID:
    """A new time-ordered UUID (version 7, RFC 9562 variant)."""
    milliseconds = time.time_ns() // 1_000_000
    rand_a = secrets.randbits(12)
    rand_b = secrets.randbits(62)
    value = (milliseconds & _MS_MASK) << 80
    value |= _VERSION << 76
    value |= rand_a << 64
    value |= _VARIANT << 62
    value |= rand_b
    return uuid.UUID(int=value)
