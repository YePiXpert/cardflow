"""Password hashing for the optional e-mail/password accounts (ADR-011): Argon2id.

Library only -- no account endpoint exists yet (M0 T-011 reserves it). Defaults follow the
OWASP Password Storage Cheat Sheet's minimum configuration for Argon2id: 19 MiB of memory,
2 iterations, 1 degree of parallelism (m=19456, t=2, p=1), with a 16-byte random salt and a
32-byte hash. They are configurable (``PASSWORD_ARGON2_*`` settings) and recorded in every
hash, so hashes made with older parameters still verify and :func:`needs_rehash` tells when
to upgrade them after a successful login.

Hashes are PHC strings ``$argon2id$v=19$m=...,t=...,p=...$<salt>$<hash>``, which the
``users.password_hash`` CHECK of revision 0001 (``LIKE '$argon2id$%'``) accepts; anything
else (other Argon2 variants, bcrypt ...) never verifies. Passwords are never logged.
"""

from dataclasses import dataclass
from typing import TYPE_CHECKING, Final

from argon2 import PasswordHasher, Type
from argon2.exceptions import InvalidHashError, VerificationError

if TYPE_CHECKING:
    from cardflow.settings import Settings

ARGON2ID_PREFIX: Final = "$argon2id$"
MAX_PASSWORD_BYTES: Final = 4096
"""Upper bound on the UTF-8 length of a password (cheap denial-of-service guard)."""


@dataclass(frozen=True, slots=True)
class Argon2Parameters:
    """Argon2id cost parameters (OWASP minimum configuration by default)."""

    time_cost: int = 2
    memory_kib: int = 19_456
    parallelism: int = 1
    hash_len: int = 32
    salt_len: int = 16

    @classmethod
    def from_settings(cls, settings: "Settings") -> "Argon2Parameters":
        """Parameters from ``PASSWORD_ARGON2_TIME_COST`` / ``_MEMORY_KIB`` / ``_PARALLELISM``."""
        return cls(
            time_cost=settings.password_argon2_time_cost,
            memory_kib=settings.password_argon2_memory_kib,
            parallelism=settings.password_argon2_parallelism,
        )

    def hasher(self) -> PasswordHasher:
        """An argon2-cffi hasher producing Argon2id hashes with these parameters."""
        return PasswordHasher(
            time_cost=self.time_cost,
            memory_cost=self.memory_kib,
            parallelism=self.parallelism,
            hash_len=self.hash_len,
            salt_len=self.salt_len,
            type=Type.ID,
        )


DEFAULT_PARAMETERS: Final = Argon2Parameters()


def _check_password(password: str) -> None:
    if not isinstance(password, str) or not password:
        raise ValueError("password must be a non-empty string")
    if len(password.encode("utf-8")) > MAX_PASSWORD_BYTES:
        raise ValueError(f"password must be at most {MAX_PASSWORD_BYTES} bytes")


def hash_password(password: str, parameters: Argon2Parameters = DEFAULT_PARAMETERS) -> str:
    """Argon2id hash (PHC string, random salt) of ``password``."""
    _check_password(password)
    return parameters.hasher().hash(password)


def verify_password(
    password_hash: str, password: str, parameters: Argon2Parameters = DEFAULT_PARAMETERS
) -> bool:
    """True if ``password`` matches the Argon2id ``password_hash``; False otherwise, also for
    malformed or non-Argon2id hashes and for unacceptable passwords (never raises for them)."""
    if not isinstance(password_hash, str) or not password_hash.startswith(ARGON2ID_PREFIX):
        return False
    try:
        _check_password(password)
        return parameters.hasher().verify(password_hash, password)
    except (ValueError, VerificationError, InvalidHashError):
        return False


def needs_rehash(password_hash: str, parameters: Argon2Parameters = DEFAULT_PARAMETERS) -> bool:
    """True if ``password_hash`` was made with other parameters than ``parameters``."""
    try:
        return parameters.hasher().check_needs_rehash(password_hash)
    except (ValueError, InvalidHashError):
        return True
