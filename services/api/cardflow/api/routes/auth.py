"""API-02: ``POST /v1/auth/refresh`` (token rotation) and ``POST /v1/auth/revoke``.

Refresh takes the refresh token in the body (never in a URL or header) and an
``Idempotency-Key``; it returns a new token pair and revokes the presented one (rotation).
Presenting an already rotated token revokes every session of the device (reuse detection);
the same Idempotency-Key within the replay window after a lost response gets a fresh pair
instead (cardflow/identity/service.py). Any unusable token -- unknown, revoked, expired,
rotated, malformed -- gets the same 401.

Revoke needs the access token and ends the calling session (``scope`` ``session``, the
default) or every session of the calling device (``device``); the access token stops
working at once. It is idempotent by nature: a repeated call finds the session revoked and
gets 401, which a client treats as "already logged out".

Token responses carry ``Cache-Control: no-store`` (RFC 6749 §5.1); a replayed response also
``Idempotent-Replayed: true``.
"""

import logging
import uuid
from datetime import datetime
from typing import Annotated, Final, Literal

from fastapi import APIRouter, Body, Header, Request, Response
from pydantic import BaseModel, ConfigDict, Field

from cardflow.api.deps import (
    ENDPOINT_IDEMPOTENCY,
    Authenticated,
    client_audit_ip,
    identity_service,
)
from cardflow.api.errors import ApiError, ErrorCode
from cardflow.identity.service import InvalidRefreshToken, TokenGrant
from cardflow.identity.validation import APP_VERSION_PATTERN

router = APIRouter(prefix="/v1/auth", tags=["auth"])
log = logging.getLogger("cardflow.api.auth")

MAX_REFRESH_TOKEN_INPUT: Final = 512
REPLAYED_HEADER: Final = "Idempotent-Replayed"
IdempotencyKey = Annotated[
    uuid.UUID,
    Header(alias="Idempotency-Key", description="UUID; a retry repeats the same key"),
]


class TokenResponse(BaseModel):
    """Tokens of API-01 and API-02 refresh (times are ISO-8601 UTC)."""

    device_id: uuid.UUID
    workspace_id: uuid.UUID
    access_token: str
    access_expires_at: datetime
    refresh_token: str
    refresh_expires_at: datetime


def token_response(response: Response, grant: TokenGrant) -> TokenResponse:
    """The response body for ``grant``; marks ``response`` uncacheable (and replayed)."""
    response.headers["Cache-Control"] = "no-store"
    response.headers["Pragma"] = "no-cache"
    if grant.replayed:
        response.headers[REPLAYED_HEADER] = "true"
    return TokenResponse(
        device_id=grant.device_id,
        workspace_id=grant.workspace_id,
        access_token=grant.access_token,
        access_expires_at=grant.access_expires_at,
        refresh_token=grant.refresh_token,
        refresh_expires_at=grant.refresh_expires_at,
    )


class RefreshRequest(BaseModel):
    """API-02 refresh body."""

    model_config = ConfigDict(extra="forbid")

    refresh_token: str = Field(min_length=1, max_length=MAX_REFRESH_TOKEN_INPUT)
    app_version: str | None = Field(default=None, pattern=APP_VERSION_PATTERN, max_length=64)


class RevokeRequest(BaseModel):
    """API-02 revoke body (optional)."""

    model_config = ConfigDict(extra="forbid")

    scope: Literal["session", "device"] = "session"


class RevokeResponse(BaseModel):
    """How many sessions the call revoked (0 if they already were)."""

    revoked_sessions: int


_UNAUTHORIZED: Final = {401: {"description": "Unknown, revoked, expired or rotated token"}}


@router.post(
    "/refresh",
    response_model=TokenResponse,
    summary="Rotate the refresh token (API-02)",
    responses=_UNAUTHORIZED,
    openapi_extra=ENDPOINT_IDEMPOTENCY,
)
def refresh(
    request: Request, response: Response, body: RefreshRequest, idempotency_key: IdempotencyKey
) -> TokenResponse:
    """Exchange a refresh token for a new access/refresh token pair."""
    try:
        grant = identity_service(request).refresh(
            body.refresh_token,
            idempotency_key,
            client_ip=client_audit_ip(request),
            app_version=body.app_version,
        )
    except InvalidRefreshToken:
        raise ApiError(
            401,
            ErrorCode.UNAUTHORIZED,
            "Invalid or expired refresh token",
            headers={"WWW-Authenticate": 'Bearer realm="cardflow", error="invalid_token"'},
        ) from None
    return token_response(response, grant)


@router.post(
    "/revoke",
    response_model=RevokeResponse,
    summary="Revoke the current session or all sessions of this device (API-02)",
    responses=_UNAUTHORIZED,
    openapi_extra=ENDPOINT_IDEMPOTENCY,
)
def revoke(
    request: Request,
    auth: Authenticated,
    idempotency_key: IdempotencyKey,
    body: Annotated[RevokeRequest | None, Body()] = None,
) -> RevokeResponse:
    """Revoke the caller's session (default) or every session of its device."""
    del idempotency_key  # naturally idempotent: see the module docstring
    scope = body.scope if body is not None else "session"
    revoked = identity_service(request).revoke(auth, scope, client_ip=client_audit_ip(request))
    return RevokeResponse(revoked_sessions=revoked)
