"""Device registration, token refresh, revocation and per-request authentication (T-011).

Everything runs as the API's database role (``cardflow_app``) under row-level security; no
step needs a superuser. A workspace is unknown until the pairing code or refresh token has
been looked up, so two SECURITY DEFINER functions of migration 0004 map the *hash* of the
secret to (row id, workspace id); every further read and write happens in
:func:`cardflow.db.workspace_tx` bound to that workspace.

Registration (API-01)
    ``resolve_pairing_code`` -> bind the workspace (a fresh one for a bootstrap code, plus the
    new owner's ``app.user_id``) and ``app.pairing_code_id`` -> lock the code row -> check it
    is unused and unexpired -> insert user, workspace (kind real) and owner membership
    (bootstrap only), the device and its first session -> mark the code used -> audit. All in
    one transaction: a concurrent registration with the same code waits for the row lock and
    then sees it used. Devices of a join code get no user (``devices.user_id`` NULL): under
    ADR-011 the device is the credential and a user identity comes only from bootstrapping
    (anonymous owner) or, later, from an optional account; a join code therefore never grants
    owner rights.

Idempotent registration (review R2-26)
    API-01 has no workspace yet, so ``idempotency_keys`` cannot hold it, and tokens must not
    be stored. Instead the code row records the SHA-256 of the Idempotency-Key and of the
    canonical request. A request with the same code, key and request hash within
    ``TOKEN_REPLAY_WINDOW_S`` of the first use gets the same device and workspace with NEW
    tokens; the sessions issued before are revoked (``replaced``). It is refused (401) once
    any session of the device was used, refreshed or revoked otherwise -- the client then
    evidently had its tokens -- or the device is revoked. Same code and key with another
    request hash: 409 IDEMPOTENCY_MISMATCH.

Refresh (API-02) and reuse detection
    ``resolve_refresh_token`` -> bind -> lock the session. A live session is rotated: a new
    session with ``rotated_from_id`` = old (sliding ``REFRESH_TOKEN_TTL_S``), the old one
    revoked as ``rotated``. A token whose session was already rotated is a reuse: every
    session of the device is revoked (``reuse_detected``) and audited -- committed, then
    401. Exception (API-02 is idempotent): the same Idempotency-Key within the replay window
    while the session issued by that refresh was never used -- the response was lost; that
    session is replaced by a new one (rotated from it), so the chain stays linear and the
    lost token stays dead.

Authentication (every request)
    Signature, ``kid``, ``exp`` and ``typ`` of the JWT, then in the token's workspace: the
    session is not revoked or expired, the device is not revoked, and a device's user (if
    any) is still a member and neither disabled nor deleted. Hence revocation takes effect
    at once; an access token also dies when its session is rotated. ``last_used_at`` /
    ``last_seen_at`` are refreshed at most once a minute.

Audit rows (IDs and hashes only): device.registered, device.registration_replayed,
auth_session.reuse_detected, auth_session.revoked, device.sessions_revoked. Log lines are
constant event names (``cardflow.identity``); no token, code or key ever reaches a log.
"""

import base64
import hashlib
import json
import logging
import uuid
from dataclasses import dataclass, replace
from datetime import datetime, timedelta
from typing import TYPE_CHECKING, Any, Final, Literal

from sqlalchemy import and_, exists, func, insert, literal, or_, select, text, update
from sqlalchemy.engine import Row
from sqlalchemy.orm import Session, aliased, sessionmaker

from cardflow.audit.records import AuditEntry, append_audit, sha256_hex
from cardflow.db.ids import uuid7
from cardflow.db.tx import set_pairing_code_id, workspace_tx
from cardflow.identity.models import AuthSession, Device, PairingCode, User
from cardflow.identity.pairing import (
    BOOTSTRAP_WORKSPACE,
    JOIN_WORKSPACE,
    normalize_pairing_code,
    pairing_code_hash,
)
from cardflow.identity.tokens import (
    KeyRing,
    issue_access_token,
    new_refresh_token,
    refresh_token_hash,
    verify_access_token,
)
from cardflow.workspaces.models import Workspace, WorkspaceMember

if TYPE_CHECKING:
    from cardflow.settings import Settings

log = logging.getLogger("cardflow.identity")

ROTATED: Final = "rotated"
REPLACED: Final = "replaced"
REUSE_DETECTED: Final = "reuse_detected"
LOGOUT: Final = "logout"
DEVICE_LOGOUT: Final = "device_logout"
REVOKED_REASONS: Final = (ROTATED, REPLACED, REUSE_DETECTED, LOGOUT, DEVICE_LOGOUT)
"""``auth_sessions.revoked_reason`` values written here (the column is an open set)."""
TOUCH_INTERVAL: Final = timedelta(minutes=1)

RevokeScope = Literal["session", "device"]

_S: Final = AuthSession.__table__
_D: Final = Device.__table__
_P: Final = PairingCode.__table__
_U: Final = User.__table__
_W: Final = Workspace.__table__
_M: Final = WorkspaceMember.__table__
_RESOLVE_PAIRING_CODE: Final = text(
    "SELECT pairing_code_id, workspace_id FROM public.resolve_pairing_code(:code_hash)"
)
_RESOLVE_REFRESH_TOKEN: Final = text(
    "SELECT session_id, workspace_id FROM public.resolve_refresh_token(:token_hash)"
)
_IDEMPOTENCY_LABEL: Final = "cardflow-idempotency-key:v1"


class RegistrationRejected(Exception):  # noqa: N818 - "raise RegistrationRejected"
    """The pairing code is unknown, expired or used (one answer for all three)."""


class IdempotencyConflict(Exception):  # noqa: N818 - "raise IdempotencyConflict"
    """Same pairing code and Idempotency-Key, different request (409)."""


class InvalidRefreshToken(Exception):  # noqa: N818 - "raise InvalidRefreshToken"
    """The refresh token is unknown, revoked, expired, rotated or its device revoked."""


class SessionInvalid(Exception):  # noqa: N818 - "raise SessionInvalid"
    """The access token's session, device or user no longer allows access."""


class _Retry(Exception):  # noqa: N818 - internal control flow
    """The pairing code changed state between lookup and lock; look it up again."""


@dataclass(frozen=True, slots=True)
class AuthContext:
    """Who is calling: the device, its workspace and session, and its user if it has one."""

    device_id: uuid.UUID
    workspace_id: uuid.UUID
    session_id: uuid.UUID
    user_id: uuid.UUID | None


@dataclass(frozen=True, slots=True)
class TokenPolicy:
    """Token lifetimes and the replay window (settings ``*_TTL_S``, ``TOKEN_REPLAY_WINDOW_S``)."""

    access_ttl: timedelta = timedelta(minutes=15)
    refresh_ttl: timedelta = timedelta(days=30)
    replay_window: timedelta = timedelta(minutes=10)

    @classmethod
    def from_settings(cls, settings: "Settings") -> "TokenPolicy":
        """Policy from the settings."""
        return cls(
            access_ttl=timedelta(seconds=settings.access_token_ttl_s),
            refresh_ttl=timedelta(seconds=settings.refresh_token_ttl_s),
            replay_window=timedelta(seconds=settings.token_replay_window_s),
        )


@dataclass(frozen=True, slots=True)
class DeviceRegistration:
    """A validated API-01 request (``public_key`` as canonical DER)."""

    pairing_code: str
    public_key: bytes
    platform: str
    app_version: str
    name: str | None = None

    def request_hash(self) -> str:
        """SHA-256 of the canonical request without the pairing code (replay check)."""
        canonical = {
            "app_version": self.app_version,
            "name": self.name,
            "platform": self.platform,
            "public_key": base64.b64encode(self.public_key).decode("ascii"),
        }
        return sha256_hex(json.dumps(canonical, sort_keys=True, separators=(",", ":")).encode())


@dataclass(frozen=True, slots=True)
class TokenGrant:
    """Tokens issued by registration or refresh; ``replayed`` for an idempotent retry."""

    device_id: uuid.UUID
    workspace_id: uuid.UUID
    session_id: uuid.UUID
    access_token: str
    access_expires_at: datetime
    refresh_token: str
    refresh_expires_at: datetime
    replayed: bool = False

    def __repr__(self) -> str:
        """Never show the tokens."""
        return (
            f"TokenGrant(device_id={self.device_id}, workspace_id={self.workspace_id}, "
            f"session_id={self.session_id}, replayed={self.replayed})"
        )


def idempotency_key_hash(purpose: str, key: uuid.UUID) -> str:
    """SHA-256 stored for an Idempotency-Key, separated by purpose (register / refresh)."""
    return hashlib.sha256(f"{_IDEMPOTENCY_LABEL}:{purpose}:{key}".encode()).hexdigest()


class IdentityService:
    """Registration, refresh, revocation and authentication against one session factory.

    ``session_factory`` must connect as the API role (cardflow_api / cardflow_app), never as
    a superuser: the code relies on row-level security for its workspace scoping.
    """

    def __init__(
        self,
        session_factory: sessionmaker[Session],
        keys: KeyRing,
        policy: TokenPolicy | None = None,
    ) -> None:
        """Bind the service to a session factory, the JWT keys and the token policy."""
        self._factory = session_factory
        self._keys = keys
        self._policy = policy or TokenPolicy()

    @property
    def keys(self) -> KeyRing:
        """The JWT key ring (current signing key and verification keys)."""
        return self._keys

    # --- registration (API-01) ---------------------------------------------------------------

    def register(
        self,
        registration: DeviceRegistration,
        idempotency_key: uuid.UUID,
        *,
        client_ip: str | None = None,
    ) -> TokenGrant:
        """Register a device with a pairing code (see the module docstring)."""
        code = normalize_pairing_code(registration.pairing_code)
        if code is None:
            raise RegistrationRejected
        code_hash = pairing_code_hash(code)
        key_hash = idempotency_key_hash("register", idempotency_key)
        for _attempt in range(2):
            with self._factory() as session, session.begin():
                found = session.execute(_RESOLVE_PAIRING_CODE, {"code_hash": code_hash}).first()
            if found is None:
                raise RegistrationRejected
            try:
                grant = self._register_with(
                    registration, found.pairing_code_id, found.workspace_id, key_hash, client_ip
                )
            except _Retry:
                continue
            log.info("device_registration_replayed" if grant.replayed else "device_registered")
            return grant
        raise RegistrationRejected

    def _register_with(
        self,
        registration: DeviceRegistration,
        pairing_code_id: uuid.UUID,
        workspace_id: uuid.UUID | None,
        key_hash: str,
        client_ip: str | None,
    ) -> TokenGrant:
        bootstrap = workspace_id is None
        bound_workspace = uuid7() if workspace_id is None else workspace_id
        owner = uuid7() if bootstrap else None
        with workspace_tx(self._factory, bound_workspace, user_id=owner) as session:
            set_pairing_code_id(session, pairing_code_id)
            code = session.execute(
                select(
                    _P.c.purpose,
                    _P.c.used_at,
                    _P.c.used_by_device_id,
                    _P.c.used_key_hash,
                    _P.c.used_request_hash,
                    (_P.c.expires_at > func.now()).label("live"),
                    (_P.c.used_at > func.now() - self._policy.replay_window).label("replayable"),
                )
                .where(_P.c.id == pairing_code_id)
                .with_for_update()
            ).one_or_none()
            if code is None:
                # Used for another workspace since the lookup: RLS now hides the row.
                raise _Retry
            if code.used_at is not None:
                if bootstrap:
                    raise _Retry
                return self._replay_registration(
                    session, code, bound_workspace, registration, key_hash, client_ip
                )
            expected = BOOTSTRAP_WORKSPACE if bootstrap else JOIN_WORKSPACE
            if code.purpose != expected or not code.live:
                raise RegistrationRejected
            if not bootstrap and not self._workspace_is_live(session, bound_workspace):
                raise RegistrationRejected  # no new devices for a workspace being deleted
            if owner is not None:
                session.execute(insert(_U).values(id=owner))
                session.execute(
                    insert(_W).values(id=bound_workspace, owner_user_id=owner, kind="real")
                )
                session.execute(
                    insert(_M).values(workspace_id=bound_workspace, user_id=owner, role="owner")
                )
            device_id = uuid7()
            session.execute(
                insert(_D).values(
                    id=device_id,
                    workspace_id=bound_workspace,
                    user_id=owner,
                    name=registration.name,
                    platform=registration.platform,
                    public_key=registration.public_key,
                    app_version=registration.app_version,
                    last_seen_at=func.now(),
                )
            )
            grant = self._new_session(session, bound_workspace, device_id, key_hash)
            claimed = session.execute(
                update(_P)
                .where(
                    _P.c.id == pairing_code_id,
                    _P.c.used_at.is_(None),
                    _P.c.expires_at > func.now(),
                )
                .values(
                    used_at=func.now(),
                    used_workspace_id=bound_workspace,
                    used_by_device_id=device_id,
                    used_key_hash=key_hash,
                    used_request_hash=registration.request_hash(),
                )
            ).rowcount
            if claimed != 1:  # cannot happen while we hold the row lock; fail closed
                raise RegistrationRejected
            append_audit(
                session,
                AuditEntry(
                    action="device.registered",
                    actor_kind="device",
                    actor_id=device_id,
                    workspace_id=bound_workspace,
                    target_table="devices",
                    target_id=device_id,
                    after_hash=sha256_hex(registration.public_key),
                    ip=client_ip,
                ),
            )
        return grant

    @staticmethod
    def _workspace_is_live(session: Session, workspace_id: uuid.UUID) -> bool:
        return (
            session.execute(
                select(literal(1)).where(_W.c.id == workspace_id, _W.c.deleted_at.is_(None))
            ).first()
            is not None
        )

    def _replay_registration(
        self,
        session: Session,
        code: Row[Any],
        workspace_id: uuid.UUID,
        registration: DeviceRegistration,
        key_hash: str,
        client_ip: str | None,
    ) -> TokenGrant:
        if code.used_key_hash != key_hash or not code.replayable:
            raise RegistrationRejected
        if code.used_request_hash != registration.request_hash():
            raise IdempotencyConflict
        device_id: uuid.UUID = code.used_by_device_id
        device = session.execute(select(_D.c.revoked_at).where(_D.c.id == device_id)).one_or_none()
        if device is None or device.revoked_at is not None:
            raise RegistrationRejected
        # Any sign that the client got its tokens (a session used, refreshed or revoked for
        # another reason than a replay) ends the replay window early.
        touched = session.execute(
            select(literal(1))
            .where(
                _S.c.device_id == device_id,
                or_(
                    _S.c.idempotency_key_hash.is_distinct_from(key_hash),
                    _S.c.last_used_at.is_not(None),
                    and_(
                        _S.c.revoked_at.is_not(None),
                        _S.c.revoked_reason.is_distinct_from(REPLACED),
                    ),
                ),
            )
            .limit(1)
        ).first()
        if touched is not None:
            raise RegistrationRejected
        session.execute(
            update(_S)
            .where(_S.c.device_id == device_id, _S.c.revoked_at.is_(None))
            .values(revoked_at=func.now(), revoked_reason=REPLACED)
        )
        grant = self._new_session(session, workspace_id, device_id, key_hash)
        append_audit(
            session,
            AuditEntry(
                action="device.registration_replayed",
                actor_kind="device",
                actor_id=device_id,
                workspace_id=workspace_id,
                target_table="devices",
                target_id=device_id,
                after_hash=sha256_hex(registration.public_key),
                ip=client_ip,
            ),
        )
        return replace(grant, replayed=True)

    def _new_session(
        self,
        session: Session,
        workspace_id: uuid.UUID,
        device_id: uuid.UUID,
        key_hash: str,
        rotated_from: uuid.UUID | None = None,
    ) -> TokenGrant:
        refresh_token = new_refresh_token()
        session_id = uuid7()
        refresh_expires_at = session.execute(
            insert(_S)
            .values(
                id=session_id,
                workspace_id=workspace_id,
                device_id=device_id,
                refresh_token_hash=refresh_token_hash(refresh_token),
                rotated_from_id=rotated_from,
                expires_at=func.now() + self._policy.refresh_ttl,
                idempotency_key_hash=key_hash,
            )
            .returning(_S.c.expires_at)
        ).scalar_one()
        access_token, access_expires_at = issue_access_token(
            self._keys,
            device_id=device_id,
            workspace_id=workspace_id,
            session_id=session_id,
            ttl=self._policy.access_ttl,
        )
        return TokenGrant(
            device_id=device_id,
            workspace_id=workspace_id,
            session_id=session_id,
            access_token=access_token,
            access_expires_at=access_expires_at,
            refresh_token=refresh_token,
            refresh_expires_at=refresh_expires_at,
        )

    # --- refresh (API-02) --------------------------------------------------------------------

    def refresh(
        self,
        refresh_token: str,
        idempotency_key: uuid.UUID,
        *,
        client_ip: str | None = None,
        app_version: str | None = None,
    ) -> TokenGrant:
        """Rotate a refresh token (see the module docstring)."""
        token_hash = refresh_token_hash(refresh_token)
        if token_hash is None:
            raise InvalidRefreshToken
        with self._factory() as session, session.begin():
            found = session.execute(_RESOLVE_REFRESH_TOKEN, {"token_hash": token_hash}).first()
        if found is None:
            raise InvalidRefreshToken
        key_hash = idempotency_key_hash("refresh", idempotency_key)
        grant: TokenGrant | None = None
        with workspace_tx(self._factory, found.workspace_id) as session:
            current = session.execute(
                select(
                    _S.c.device_id,
                    _S.c.revoked_at,
                    _S.c.revoked_reason,
                    (_S.c.expires_at > func.now()).label("live"),
                    _D.c.revoked_at.label("device_revoked_at"),
                )
                .join(_D, and_(_D.c.workspace_id == _S.c.workspace_id, _D.c.id == _S.c.device_id))
                .where(_S.c.id == found.session_id)
                .with_for_update(of=_S)
            ).one_or_none()
            if current is None:
                raise InvalidRefreshToken
            child = aliased(_S)
            successor = session.execute(
                select(
                    _S.c.id,
                    _S.c.idempotency_key_hash,
                    _S.c.last_used_at,
                    _S.c.revoked_at,
                    (_S.c.created_at > func.now() - self._policy.replay_window).label("recent"),
                    exists().where(child.c.rotated_from_id == _S.c.id).label("rotated"),
                )
                .where(_S.c.rotated_from_id == found.session_id)
                .with_for_update(of=_S)
            ).one_or_none()
            if successor is None:
                if (
                    current.revoked_at is not None
                    or not current.live
                    or current.device_revoked_at is not None
                ):
                    raise InvalidRefreshToken
                grant = self._new_session(
                    session, found.workspace_id, current.device_id, key_hash, found.session_id
                )
                session.execute(
                    update(_S)
                    .where(_S.c.id == found.session_id)
                    .values(revoked_at=func.now(), revoked_reason=ROTATED, last_used_at=func.now())
                )
            elif (
                successor.idempotency_key_hash == key_hash
                and successor.recent
                and successor.last_used_at is None
                and successor.revoked_at is None
                and not successor.rotated
                and current.revoked_reason == ROTATED
                and current.device_revoked_at is None
            ):
                # A retry whose first response was lost: replace the unreceived session.
                session.execute(
                    update(_S)
                    .where(_S.c.id == successor.id)
                    .values(revoked_at=func.now(), revoked_reason=REPLACED)
                )
                grant = replace(
                    self._new_session(
                        session, found.workspace_id, current.device_id, key_hash, successor.id
                    ),
                    replayed=True,
                )
            else:
                session.execute(
                    update(_S)
                    .where(_S.c.device_id == current.device_id, _S.c.revoked_at.is_(None))
                    .values(revoked_at=func.now(), revoked_reason=REUSE_DETECTED)
                )
                append_audit(
                    session,
                    AuditEntry(
                        action="auth_session.reuse_detected",
                        actor_kind="device",
                        actor_id=current.device_id,
                        workspace_id=found.workspace_id,
                        target_table="auth_sessions",
                        target_id=found.session_id,
                        ip=client_ip,
                    ),
                )
            if grant is not None:
                session.execute(
                    update(_D)
                    .where(_D.c.id == current.device_id)
                    .values(
                        last_seen_at=func.now(),
                        app_version=func.coalesce(app_version, _D.c.app_version),
                    )
                )
        if grant is None:  # the revocation above is committed; the caller gets 401
            log.warning("refresh_token_reuse_detected")
            raise InvalidRefreshToken
        return grant

    # --- revocation (API-02) -----------------------------------------------------------------

    def revoke(
        self, context: AuthContext, scope: RevokeScope = "session", *, client_ip: str | None = None
    ) -> int:
        """Revoke the caller's session, or (``device``) every session of its device."""
        with workspace_tx(self._factory, context.workspace_id) as session:
            if scope == "device":
                target = _S.c.device_id == context.device_id
                reason, action = DEVICE_LOGOUT, "device.sessions_revoked"
                target_table, target_id = "devices", context.device_id
            else:
                target = _S.c.id == context.session_id
                reason, action = LOGOUT, "auth_session.revoked"
                target_table, target_id = "auth_sessions", context.session_id
            revoked = session.execute(
                update(_S)
                .where(target, _S.c.revoked_at.is_(None))
                .values(revoked_at=func.now(), revoked_reason=reason)
            ).rowcount
            append_audit(
                session,
                AuditEntry(
                    action=action,
                    actor_kind="device",
                    actor_id=context.device_id,
                    workspace_id=context.workspace_id,
                    target_table=target_table,
                    target_id=target_id,
                    ip=client_ip,
                ),
            )
        log.info("sessions_revoked")
        return revoked

    # --- authentication (every request) ------------------------------------------------------

    def authenticate(self, access_token: str) -> AuthContext:
        """Verify the access token and its session/device in the database, or raise
        :class:`cardflow.identity.tokens.InvalidAccessToken` / :class:`SessionInvalid`."""
        claims = verify_access_token(self._keys, access_token)
        stale = func.now() - TOUCH_INTERVAL
        member = (
            select(literal(1))
            .select_from(_M.join(_U, _U.c.id == _M.c.user_id))
            .where(
                _M.c.workspace_id == _S.c.workspace_id,
                _M.c.user_id == _D.c.user_id,
                _U.c.disabled_at.is_(None),
                _U.c.deleted_at.is_(None),
            )
            .exists()
        )
        with workspace_tx(self._factory, claims.workspace_id) as session:
            row = session.execute(
                select(
                    _D.c.user_id,
                    or_(_S.c.last_used_at.is_(None), _S.c.last_used_at < stale).label(
                        "touch_session"
                    ),
                    or_(_D.c.last_seen_at.is_(None), _D.c.last_seen_at < stale).label(
                        "touch_device"
                    ),
                )
                .select_from(
                    _S.join(
                        _D, and_(_D.c.workspace_id == _S.c.workspace_id, _D.c.id == _S.c.device_id)
                    )
                )
                .where(
                    _S.c.id == claims.session_id,
                    _S.c.device_id == claims.device_id,
                    _S.c.workspace_id == claims.workspace_id,
                    _S.c.revoked_at.is_(None),
                    _S.c.expires_at > func.now(),
                    _D.c.revoked_at.is_(None),
                    or_(_D.c.user_id.is_(None), member),
                )
            ).one_or_none()
            if row is None:
                raise SessionInvalid
            if row.touch_session:
                session.execute(
                    update(_S).where(_S.c.id == claims.session_id).values(last_used_at=func.now())
                )
            if row.touch_device:
                session.execute(
                    update(_D).where(_D.c.id == claims.device_id).values(last_seen_at=func.now())
                )
        return AuthContext(
            device_id=claims.device_id,
            workspace_id=claims.workspace_id,
            session_id=claims.session_id,
            user_id=row.user_id,
        )
