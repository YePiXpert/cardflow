"""API-01: ``POST /v1/devices/register`` -- pair a device with a one-time code, get tokens.

Public endpoint: the pairing code is the credential. The body carries the code, the
device's public key (base64 of a DER SubjectPublicKeyInfo), an optional name, the platform
and the app version; the response is the token pair (201). A bootstrap code creates a new
workspace with an anonymous owner, a join code adds the device to its workspace
(cardflow/identity/service.py).

Errors: 401 UNAUTHORIZED for an unknown, expired or used code (one answer for all three);
409 IDEMPOTENCY_MISMATCH for the same code and Idempotency-Key with a different request; 422
for invalid input (messages never echo the input); 429 RATE_LIMITED with ``Retry-After``
while the client is locked out after repeated failures (cardflow/identity/throttle.py).

Idempotency: the same code, Idempotency-Key and request within the replay window return the
same device and workspace with new tokens (the earlier, unreceived session is revoked) and
``Idempotent-Replayed: true``. Codes, keys and tokens are never logged or stored in clear.
"""

import base64
import logging
import math
from typing import Annotated, Final

from fastapi import APIRouter, Request, Response
from pydantic import BaseModel, ConfigDict, Field, field_validator

from cardflow.api.deps import (
    ENDPOINT_IDEMPOTENCY,
    client_audit_ip,
    client_key,
    identity_service,
    pairing_guard,
)
from cardflow.api.errors import ApiError, ErrorCode
from cardflow.api.routes.auth import IdempotencyKey, TokenResponse, token_response
from cardflow.identity.pairing import MAX_CODE_INPUT_LENGTH
from cardflow.identity.service import DeviceRegistration, IdempotencyConflict, RegistrationRejected
from cardflow.identity.validation import (
    APP_VERSION_PATTERN,
    MAX_DEVICE_NAME,
    MAX_PUBLIC_KEY_BASE64,
    PLATFORM_PATTERN,
    check_free_text,
    decode_public_key,
    has_card_number,
)

router = APIRouter(prefix="/v1/devices", tags=["devices"])
log = logging.getLogger("cardflow.api.devices")

REJECTED_MESSAGE: Final = "The pairing code is invalid, expired or already used"


class RegisterDeviceRequest(BaseModel):
    """API-01 body."""

    model_config = ConfigDict(extra="forbid")

    pairing_code: str = Field(min_length=1, max_length=MAX_CODE_INPUT_LENGTH)
    public_key: str = Field(
        min_length=44,
        max_length=MAX_PUBLIC_KEY_BASE64,
        description="base64 (RFC 4648 §4) of the DER SubjectPublicKeyInfo: EC P-256/P-384, "
        "Ed25519 or RSA 2048-4096",
    )
    name: Annotated[str | None, Field(max_length=MAX_DEVICE_NAME)] = None
    platform: str = Field(pattern=PLATFORM_PATTERN, description="ios, android ...")
    app_version: str = Field(pattern=APP_VERSION_PATTERN, max_length=64)

    @field_validator("public_key")
    @classmethod
    def _public_key(cls, value: str) -> str:
        decode_public_key(value)  # ValueError -> 422 without echoing the key
        return value

    @field_validator("name")
    @classmethod
    def _name(cls, value: str | None) -> str | None:
        return None if value is None else check_free_text(value, max_length=MAX_DEVICE_NAME)

    @field_validator("app_version")
    @classmethod
    def _app_version(cls, value: str) -> str:
        if has_card_number(value):
            raise ValueError("must not contain a card number or 13 or more digits")
        return value

    def registration(self) -> DeviceRegistration:
        """The validated request for :meth:`IdentityService.register`."""
        return DeviceRegistration(
            pairing_code=self.pairing_code,
            public_key=base64.b64decode(self.public_key, validate=True),
            platform=self.platform,
            app_version=self.app_version,
            name=self.name,
        )


@router.post(
    "/register",
    status_code=201,
    response_model=TokenResponse,
    summary="Register a device with a pairing code (API-01)",
    responses={
        401: {"description": "Invalid, expired or used pairing code"},
        409: {"description": "Same code and Idempotency-Key, different request"},
        429: {"description": "Too many failed attempts from this client"},
    },
    openapi_extra=ENDPOINT_IDEMPOTENCY,
)
def register_device(
    request: Request,
    response: Response,
    body: RegisterDeviceRequest,
    idempotency_key: IdempotencyKey,
) -> TokenResponse:
    """Pair this device and return its first token pair."""
    guard = pairing_guard(request)
    client = client_key(request)
    retry_after = guard.retry_after(client)
    if retry_after is not None:
        log.warning("pairing_locked_out")
        raise ApiError(
            429,
            ErrorCode.RATE_LIMITED,
            "Too many failed pairing attempts; try again later",
            headers={"Retry-After": str(max(1, math.ceil(retry_after)))},
        )
    try:
        grant = identity_service(request).register(
            body.registration(), idempotency_key, client_ip=client_audit_ip(request)
        )
    except RegistrationRejected:
        if guard.record_failure(client):
            log.warning("pairing_lockout_started")
        else:
            log.info("pairing_rejected")
        raise ApiError(401, ErrorCode.UNAUTHORIZED, REJECTED_MESSAGE) from None
    except IdempotencyConflict:
        guard.record_failure(client)
        raise ApiError(
            409,
            ErrorCode.IDEMPOTENCY_MISMATCH,
            "This Idempotency-Key was used with a different registration request",
        ) from None
    guard.reset(client)
    return token_response(response, grant)
