"""Device tokens (ADR-011; security-privacy §4 SEC-S-03, §5): access JWTs and refresh tokens.

Access token
    A JWT signed with HS256 under ``JWT_KEY``. Header ``kid``; claims ``sub`` (device id),
    ``wsp`` (workspace id), ``sid`` (session id), ``iat``, ``exp`` (``ACCESS_TOKEN_TTL_S``,
    15 minutes by default) and ``typ`` = ``access``. A token is accepted only with a known
    ``kid``, the HS256 algorithm, a valid signature, every claim present, ``typ`` access and
    ``iat <= now < exp``. The API additionally checks the session and the device in the
    database on every request (cardflow/identity/service.py), so revocation takes effect
    at once.

Key rotation (security-privacy §5: both keys accepted for 7 days)
    The key id is derived from the key (HMAC-SHA256 under the key, 96 bits, base64url), so
    rotating needs no separate configuration: move the current secret to
    ``JWT_PREVIOUS_KEY(_FILE)``, put a new one into ``JWT_KEY(_FILE)`` and restart. New
    tokens are signed with the new key; tokens of the previous key verify until it is
    removed. Access tokens live 15 minutes and refresh tokens are not JWTs, so the previous
    key is technically needed only that long; the 7 days are the operational rule. Both
    secrets must be at least 32 bytes (RFC 7518 §3.2).

Refresh token
    256 random bits as unpadded base64url (43 characters). Only its SHA-256 is stored
    (``auth_sessions.refresh_token_hash``); it is not a JWT and carries no claims.

Nothing here logs; :class:`InvalidAccessToken` carries an internal reason for tests only and
is never shown to clients.
"""

import base64
import hashlib
import hmac
import re
import secrets
import uuid
from collections.abc import Mapping
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from typing import TYPE_CHECKING, Final

import jwt

if TYPE_CHECKING:
    from cardflow.settings import Settings

JWT_ALGORITHM: Final = "HS256"
ACCESS_TOKEN_TYPE: Final = "access"  # noqa: S105 - the ``typ`` claim, not a secret
MIN_KEY_BYTES: Final = 32
MAX_ACCESS_TOKEN_LENGTH: Final = 4096
REQUIRED_CLAIMS: Final = ("sub", "wsp", "sid", "iat", "exp", "typ")
REFRESH_TOKEN_BYTES: Final = 32
REFRESH_TOKEN_LENGTH: Final = 43
_REFRESH_TOKEN: Final = re.compile(r"[A-Za-z0-9_-]{43}")
_KID_LABEL: Final = b"cardflow jwt key id v1"
_KID_BYTES: Final = 12


class AuthConfigurationError(RuntimeError):
    """JWT_KEY (or JWT_PREVIOUS_KEY) is missing or too short; never contains the secret."""


class InvalidAccessToken(Exception):  # noqa: N818 - reads as "raise InvalidAccessToken"
    """The access token is not acceptable; ``reason`` is for tests, never for clients."""

    def __init__(self, reason: str) -> None:
        """``reason``: short internal label such as ``expired`` or ``unknown_kid``."""
        super().__init__(reason)
        self.reason = reason


@dataclass(frozen=True, slots=True)
class SigningKey:
    """An HMAC secret and its derived key id."""

    kid: str
    secret: bytes = field(repr=False)


def key_id(secret: bytes) -> str:
    """Key id of ``secret``: 96 bits of HMAC-SHA256(secret, label), base64url (16 chars)."""
    digest = hmac.new(secret, _KID_LABEL, hashlib.sha256).digest()[:_KID_BYTES]
    return base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")


def signing_key(secret: str | bytes, *, setting: str = "JWT_KEY") -> SigningKey:
    """Wrap ``secret`` (UTF-8 text or bytes); at least :data:`MIN_KEY_BYTES` bytes."""
    raw = secret.encode("utf-8") if isinstance(secret, str) else bytes(secret)
    if len(raw) < MIN_KEY_BYTES:
        raise AuthConfigurationError(f"{setting} must be at least {MIN_KEY_BYTES} bytes")
    return SigningKey(key_id(raw), raw)


class KeyRing:
    """The signing key (current) and the keys accepted for verification (current, previous)."""

    def __init__(self, current: SigningKey, previous: SigningKey | None = None) -> None:
        """``previous`` only verifies, during a rotation."""
        self.current = current
        self._verification: dict[str, SigningKey] = {current.kid: current}
        if previous is not None:
            self._verification.setdefault(previous.kid, previous)

    @classmethod
    def from_secrets(cls, current: str | bytes | None, previous: str | bytes | None) -> "KeyRing":
        """Key ring from the two secrets; ``current`` is required."""
        if current is None:
            raise AuthConfigurationError("JWT_KEY is not configured")
        return cls(
            signing_key(current),
            None if previous is None else signing_key(previous, setting="JWT_PREVIOUS_KEY"),
        )

    @classmethod
    def from_settings(cls, settings: "Settings") -> "KeyRing":
        """Key ring from ``JWT_KEY`` / ``JWT_PREVIOUS_KEY`` (or their ``_FILE`` variants)."""
        current = None if settings.jwt_key is None else settings.jwt_key.get_secret_value()
        previous = settings.jwt_previous_key
        return cls.from_secrets(current, None if previous is None else previous.get_secret_value())

    @property
    def kids(self) -> tuple[str, ...]:
        """Key ids accepted for verification (current first)."""
        return tuple(self._verification)

    def verification_key(self, kid: object) -> SigningKey | None:
        """The key for ``kid``, or ``None`` if unknown."""
        return self._verification.get(kid) if isinstance(kid, str) else None


@dataclass(frozen=True, slots=True)
class AccessClaims:
    """The verified claims of an access token."""

    device_id: uuid.UUID
    workspace_id: uuid.UUID
    session_id: uuid.UUID
    issued_at: datetime
    expires_at: datetime


def issue_access_token(
    keys: KeyRing,
    *,
    device_id: uuid.UUID,
    workspace_id: uuid.UUID,
    session_id: uuid.UUID,
    ttl: timedelta,
    now: datetime | None = None,
    signing: SigningKey | None = None,
) -> tuple[str, datetime]:
    """A signed access token and its expiry. ``now`` and ``signing`` exist for tests."""
    issued = (now or datetime.now(UTC)).replace(microsecond=0)
    expires = issued + ttl
    key = signing or keys.current
    token = jwt.encode(
        {
            "sub": str(device_id),
            "wsp": str(workspace_id),
            "sid": str(session_id),
            "iat": int(issued.timestamp()),
            "exp": int(expires.timestamp()),
            "typ": ACCESS_TOKEN_TYPE,
        },
        key.secret,
        algorithm=JWT_ALGORITHM,
        headers={"kid": key.kid},
    )
    return token, expires


def _uuid_claim(payload: Mapping[str, object], name: str) -> uuid.UUID:
    value = payload.get(name)
    if not isinstance(value, str):
        raise InvalidAccessToken(f"bad_{name}")
    try:
        return uuid.UUID(value)
    except ValueError:
        raise InvalidAccessToken(f"bad_{name}") from None


def verify_access_token(keys: KeyRing, token: str) -> AccessClaims:
    """Verify ``token`` (see the module docstring) or raise :class:`InvalidAccessToken`."""
    if not isinstance(token, str) or not token or len(token) > MAX_ACCESS_TOKEN_LENGTH:
        raise InvalidAccessToken("malformed")
    try:
        header = jwt.get_unverified_header(token)
    except jwt.PyJWTError:
        raise InvalidAccessToken("malformed") from None
    key = keys.verification_key(header.get("kid"))
    if key is None:
        raise InvalidAccessToken("unknown_kid")
    try:
        payload = jwt.decode(
            token,
            key.secret,
            algorithms=[JWT_ALGORITHM],
            options={"require": list(REQUIRED_CLAIMS)},
        )
    except jwt.ExpiredSignatureError:
        raise InvalidAccessToken("expired") from None
    except jwt.InvalidSignatureError:
        raise InvalidAccessToken("bad_signature") from None
    except jwt.PyJWTError:
        raise InvalidAccessToken("invalid") from None
    if payload.get("typ") != ACCESS_TOKEN_TYPE:
        raise InvalidAccessToken("wrong_type")
    issued_at, expires_at = payload["iat"], payload["exp"]
    if not all(type(value) is int for value in (issued_at, expires_at)):
        raise InvalidAccessToken("bad_times")
    return AccessClaims(
        device_id=_uuid_claim(payload, "sub"),
        workspace_id=_uuid_claim(payload, "wsp"),
        session_id=_uuid_claim(payload, "sid"),
        issued_at=datetime.fromtimestamp(issued_at, UTC),
        expires_at=datetime.fromtimestamp(expires_at, UTC),
    )


def new_refresh_token() -> str:
    """A new refresh token: 256 random bits, unpadded base64url (43 characters)."""
    return base64.urlsafe_b64encode(secrets.token_bytes(REFRESH_TOKEN_BYTES)).rstrip(b"=").decode()


def refresh_token_hash(token: object) -> str | None:
    """SHA-256 (hex) stored for a refresh token, or ``None`` if ``token`` cannot be one."""
    if not isinstance(token, str) or _REFRESH_TOKEN.fullmatch(token) is None:
        return None
    return hashlib.sha256(token.encode("ascii")).hexdigest()
