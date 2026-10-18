"""FastAPI dependencies: database sessions and device authentication (T-011, ADR-011).

Usage in a route (T-009, T-010, T-031 ...)::

    from cardflow.api.deps import Authenticated, session_factory
    from cardflow.db import workspace_tx

    @router.get("/v1/things")
    def list_things(request: Request, auth: Authenticated) -> ...:
        with workspace_tx(session_factory(request), auth.workspace_id) as session:
            ...  # row-level security binds every statement to auth.workspace_id

:data:`Authenticated` (``Annotated[AuthContext, Depends(require_device)]``) verifies the
``Authorization: Bearer <access token>`` header on every request -- signature, ``kid``,
``exp``, ``typ`` -- and then, in the token's workspace, that the session is neither revoked
nor expired, the device is not revoked and the device's user (if any) is still an active
member (:meth:`cardflow.identity.service.IdentityService.authenticate`). The
:class:`AuthContext` carries ``device_id``, ``workspace_id``, ``session_id`` and ``user_id``
(``None`` for devices without a user) and is also stored as ``request.state.auth`` (e.g. for
T-010's per-device rate limit). An ``X-Workspace-Id`` header, when present, must name the
token's workspace (otherwise 403 FORBIDDEN); the workspace always comes from the token, never
from the header. Failures are 401 UNAUTHORIZED in the error envelope with
``WWW-Authenticate: Bearer``; an unknown, revoked, expired or otherwise invalid token all get
the same answer.

The database engine is created on first use from ``DATABASE_URL`` / ``DATABASE_PASSWORD`` --
in production the LOGIN role ``cardflow_api`` (cardflow_app), never a superuser -- and kept on
``app.state.db_engine``; tests may preset ``app.state.session_factory``. Likewise the
:class:`IdentityService` (``app.state.identity_service``; needs ``JWT_KEY`` of at least 32
bytes, otherwise requests that need it fail with 500) and the pairing brute-force guard
(``app.state.pairing_guard``).

Endpoints that handle ``Idempotency-Key`` themselves (API-01/02: no workspace exists before
registration and tokens must never be stored) carry ``openapi_extra``
``{IDEMPOTENCY_EXTENSION: "endpoint"}`` and are listed in :data:`ENDPOINT_IDEMPOTENT_PATHS`
(usable by a middleware before routing); T-010's generic middleware must leave them alone.
"""

import threading
import uuid
from collections.abc import Callable
from typing import Annotated, Final

from fastapi import Depends, FastAPI, Header, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session, sessionmaker

from cardflow.api.errors import ApiError, ErrorCode
from cardflow.audit.records import audit_ip
from cardflow.db.engine import create_engine_from_settings, create_session_factory
from cardflow.identity.service import AuthContext, IdentityService, SessionInvalid, TokenPolicy
from cardflow.identity.throttle import FailureLimiter
from cardflow.identity.tokens import InvalidAccessToken, KeyRing
from cardflow.settings import Settings

IDEMPOTENCY_EXTENSION: Final = "x-cardflow-idempotency"
"""OpenAPI extension key; value ``endpoint`` = the route implements idempotency itself."""
ENDPOINT_IDEMPOTENCY: Final = {IDEMPOTENCY_EXTENSION: "endpoint"}
ENDPOINT_IDEMPOTENT_PATHS: Final = frozenset(
    {"/v1/devices/register", "/v1/auth/refresh", "/v1/auth/revoke"}
)
"""Paths whose routes implement idempotency themselves (checked against the OpenAPI)."""
WORKSPACE_HEADER: Final = "X-Workspace-Id"
AUTH_STATE_KEY: Final = "auth"
UNKNOWN_CLIENT: Final = "unknown"

_STATE_LOCK: Final = threading.RLock()  # re-entrant: identity_service builds session_factory
_bearer: Final = HTTPBearer(
    auto_error=False,
    bearerFormat="JWT",
    description="Device access token from POST /v1/devices/register or /v1/auth/refresh",
)

__all__ = [
    "AUTH_STATE_KEY",
    "ENDPOINT_IDEMPOTENCY",
    "ENDPOINT_IDEMPOTENT_PATHS",
    "IDEMPOTENCY_EXTENSION",
    "AuthContext",
    "Authenticated",
    "client_audit_ip",
    "client_key",
    "dispose_database",
    "identity_service",
    "pairing_guard",
    "require_device",
    "session_factory",
]


def _settings(app: FastAPI) -> Settings:
    settings = getattr(app.state, "settings", None)
    if not isinstance(settings, Settings):
        raise RuntimeError("app.state.settings is not set; build the app with create_app()")
    return settings


def _lazy[T](app: FastAPI, name: str, build: Callable[[], T]) -> T:
    """``app.state.<name>``, built once (thread-safe) on first use."""
    value = getattr(app.state, name, None)
    if value is None:
        with _STATE_LOCK:
            value = getattr(app.state, name, None)
            if value is None:
                value = build()
                setattr(app.state, name, value)
    return value


def session_factory(request: Request) -> sessionmaker[Session]:
    """Session factory of the API's database role (see the module docstring)."""
    app = request.app

    def build() -> sessionmaker[Session]:
        engine = create_engine_from_settings(_settings(app))
        app.state.db_engine = engine
        return create_session_factory(engine)

    return _lazy(app, "session_factory", build)


def identity_service(request: Request) -> IdentityService:
    """The :class:`IdentityService` of this application."""
    app = request.app
    return _lazy(
        app,
        "identity_service",
        lambda: IdentityService(
            session_factory(request),
            KeyRing.from_settings(_settings(app)),
            TokenPolicy.from_settings(_settings(app)),
        ),
    )


def pairing_guard(request: Request) -> FailureLimiter:
    """The pairing brute-force guard of this process (cardflow/identity/throttle.py)."""
    app = request.app
    return _lazy(app, "pairing_guard", lambda: FailureLimiter.from_settings(_settings(app)))


def dispose_database(app: FastAPI) -> None:
    """Close the engine created by :func:`session_factory`, if any (tests, shutdown)."""
    engine = getattr(app.state, "db_engine", None)
    if engine is not None:
        engine.dispose()


def client_key(request: Request) -> str:
    """The client address as uvicorn reports it (brute-force guard key)."""
    return request.client.host if request.client is not None else UNKNOWN_CLIENT


def client_audit_ip(request: Request) -> str | None:
    """The client IP for ``audit_log.ip`` (``None`` unless it is a valid address)."""
    return audit_ip(request.client.host if request.client is not None else None)


def _unauthorized(message: str, *, invalid_token: bool) -> ApiError:
    challenge = 'Bearer realm="cardflow"'
    if invalid_token:
        challenge += ', error="invalid_token"'
    return ApiError(401, ErrorCode.UNAUTHORIZED, message, headers={"WWW-Authenticate": challenge})


def require_device(
    request: Request,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
    workspace_header: Annotated[
        str | None,
        Header(
            alias=WORKSPACE_HEADER,
            description="Optional; must equal the workspace of the access token",
        ),
    ] = None,
) -> AuthContext:
    """Authenticate the calling device (see the module docstring)."""
    if credentials is None:
        raise _unauthorized("Authentication required", invalid_token=False)
    try:
        context = identity_service(request).authenticate(credentials.credentials)
    except (InvalidAccessToken, SessionInvalid):
        raise _unauthorized("Invalid or expired access token", invalid_token=True) from None
    if workspace_header is not None:
        try:
            requested = uuid.UUID(workspace_header.strip())
        except ValueError:
            requested = None
        if requested != context.workspace_id:
            raise ApiError(
                403, ErrorCode.FORBIDDEN, "X-Workspace-Id does not match the access token"
            )
    setattr(request.state, AUTH_STATE_KEY, context)
    return context


Authenticated = Annotated[AuthContext, Depends(require_device)]
"""Route parameter type of an authenticated device request."""
