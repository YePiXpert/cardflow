"""Uniform error envelope for every API error response (api-contract §1).

Body of every error response (and the same id in the ``X-Request-Id`` header)::

    {"error": {"code": "...", "message": "...", "details": {...}, "request_id": "..."}}

Route and service code raises :class:`ApiError` with a contract :class:`ErrorCode`.
Framework errors (unknown route, wrong method, request validation) and unexpected
exceptions are mapped here. T-010 extends this module (idempotency, full code table).
"""

import logging
from collections.abc import Mapping
from enum import StrEnum
from http import HTTPStatus
from types import MappingProxyType
from typing import Final

from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException
from starlette.requests import Request
from starlette.responses import JSONResponse, Response

from cardflow.api.request_id import REQUEST_ID_HEADER, get_request_id

logger = logging.getLogger("cardflow.api")


class ErrorCode(StrEnum):
    """Machine-readable ``error.code`` values."""

    # Listed in api-contract §1.
    VALIDATION_ERROR = "VALIDATION_ERROR"
    UNAUTHORIZED = "UNAUTHORIZED"
    FORBIDDEN = "FORBIDDEN"
    NOT_FOUND = "NOT_FOUND"
    VERSION_CONFLICT = "VERSION_CONFLICT"
    IDEMPOTENCY_MISMATCH = "IDEMPOTENCY_MISMATCH"
    NEEDS_DATA = "NEEDS_DATA"
    BASELINE_SHORTFALL = "BASELINE_SHORTFALL"
    RULE_INVALID = "RULE_INVALID"
    DUPLICATE_DOCUMENT = "DUPLICATE_DOCUMENT"
    FILE_REJECTED = "FILE_REJECTED"
    PARSE_TIMEOUT = "PARSE_TIMEOUT"
    SOLVER_UNKNOWN = "SOLVER_UNKNOWN"
    SOLVER_INFEASIBLE = "SOLVER_INFEASIBLE"
    MODEL_INVALID = "MODEL_INVALID"
    RATE_LIMITED = "RATE_LIMITED"
    DEMO_RESTRICTED = "DEMO_RESTRICTED"
    CONSENT_REQUIRED = "CONSENT_REQUIRED"
    # Added by T-002; not (yet) in api-contract §1.
    INTERNAL_ERROR = "INTERNAL_ERROR"  # unexpected server failure (500)
    METHOD_NOT_ALLOWED = "METHOD_NOT_ALLOWED"  # path exists, method does not (405)
    HTTP_ERROR = "HTTP_ERROR"  # other 4xx without a contract code (fallback only)


_CODE_BY_STATUS: Final[Mapping[int, ErrorCode]] = MappingProxyType(
    {
        400: ErrorCode.VALIDATION_ERROR,
        401: ErrorCode.UNAUTHORIZED,
        403: ErrorCode.FORBIDDEN,
        404: ErrorCode.NOT_FOUND,
        405: ErrorCode.METHOD_NOT_ALLOWED,
        422: ErrorCode.VALIDATION_ERROR,
        429: ErrorCode.RATE_LIMITED,
    }
)
_NO_BODY_STATUSES: Final = frozenset({204, 205, 304})
VALIDATION_MESSAGE: Final = "Request validation failed"
INTERNAL_MESSAGE: Final = "Internal server error"


def code_for_status(status_code: int) -> ErrorCode:
    """Contract code for a bare HTTP status (used for framework-raised HTTP errors)."""
    code = _CODE_BY_STATUS.get(status_code)
    if code is not None:
        return code
    return ErrorCode.INTERNAL_ERROR if status_code >= 500 else ErrorCode.HTTP_ERROR


def _status_phrase(status_code: int) -> str:
    try:
        return HTTPStatus(status_code).phrase
    except ValueError:
        return "HTTP error"


class ApiError(Exception):
    """Raise from route or service code to return a specific contract error."""

    def __init__(
        self,
        status_code: int,
        code: ErrorCode,
        message: str,
        *,
        details: Mapping[str, object] | None = None,
        headers: Mapping[str, str] | None = None,
    ) -> None:
        """``message`` is shown to clients: never put amounts, merchants or tokens in it."""
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message
        self.details: dict[str, object] = dict(details or {})
        self.headers: dict[str, str] = dict(headers or {})


def error_body(
    code: ErrorCode,
    message: str,
    request_id: str,
    details: Mapping[str, object] | None = None,
) -> dict[str, object]:
    """The ``{"error": {...}}`` envelope."""
    return {
        "error": {
            "code": code.value,
            "message": message,
            "details": dict(details or {}),
            "request_id": request_id,
        }
    }


def error_response(
    request_id: str,
    status_code: int,
    code: ErrorCode,
    message: str,
    *,
    details: Mapping[str, object] | None = None,
    headers: Mapping[str, str] | None = None,
) -> Response:
    """Build an envelope response that also carries ``X-Request-Id``."""
    merged_headers = {**(headers or {}), REQUEST_ID_HEADER: request_id}
    if status_code < 200 or status_code in _NO_BODY_STATUSES:
        return Response(status_code=status_code, headers=merged_headers)
    return JSONResponse(
        error_body(code, message, request_id, details),
        status_code=status_code,
        headers=merged_headers,
    )


def response_for_api_error(request_id: str, exc: ApiError) -> Response:
    """Envelope for an :class:`ApiError`."""
    return error_response(
        request_id,
        exc.status_code,
        exc.code,
        exc.message,
        details=exc.details,
        headers=exc.headers,
    )


def response_for_http_exception(request_id: str, exc: StarletteHTTPException) -> Response:
    """Envelope for Starlette/FastAPI ``HTTPException`` (404, 405, malformed bodies...)."""
    message = exc.detail if isinstance(exc.detail, str) and exc.detail else ""
    return error_response(
        request_id,
        exc.status_code,
        code_for_status(exc.status_code),
        message or _status_phrase(exc.status_code),
        headers=exc.headers,
    )


def _public_validation_error(error: Mapping[str, object]) -> dict[str, object]:
    # Location, type and message only. Pydantic's `input` (the submitted value) and
    # `ctx` are deliberately dropped so request data is never echoed back.
    location = error.get("loc", ())
    return {
        "loc": list(location) if isinstance(location, list | tuple) else [],
        "type": str(error.get("type", "")),
        "msg": str(error.get("msg", "")),
    }


def response_for_validation_error(request_id: str, exc: RequestValidationError) -> Response:
    """422 ``VALIDATION_ERROR`` with ``details.errors = [{loc, type, msg}, ...]``."""
    errors = [_public_validation_error(error) for error in exc.errors()]
    return error_response(
        request_id,
        422,
        ErrorCode.VALIDATION_ERROR,
        VALIDATION_MESSAGE,
        details={"errors": errors},
    )


def internal_error_response(request_id: str) -> Response:
    """500 ``INTERNAL_ERROR``; the exception itself is never described to the client."""
    return error_response(request_id, 500, ErrorCode.INTERNAL_ERROR, INTERNAL_MESSAGE)


def response_for_known_exception(request_id: str, exc: Exception) -> Response | None:
    """Envelope for an expected API exception, or ``None`` for anything unexpected."""
    if isinstance(exc, ApiError):
        return response_for_api_error(request_id, exc)
    if isinstance(exc, StarletteHTTPException):
        return response_for_http_exception(request_id, exc)
    if isinstance(exc, RequestValidationError):
        return response_for_validation_error(request_id, exc)
    return None


async def _handle_api_error(request: Request, exc: ApiError) -> Response:
    return response_for_api_error(get_request_id(request), exc)


async def _handle_http_exception(request: Request, exc: StarletteHTTPException) -> Response:
    return response_for_http_exception(get_request_id(request), exc)


async def _handle_validation_error(request: Request, exc: RequestValidationError) -> Response:
    return response_for_validation_error(get_request_id(request), exc)


async def _handle_unexpected(request: Request, exc: Exception) -> Response:
    # Normally unreachable: RequestContextMiddleware converts unexpected exceptions
    # first. This covers failures raised outside it (e.g. in an outer middleware).
    request_id = get_request_id(request)
    logger.error("unhandled_exception", exc_info=exc, extra={"request_id": request_id})
    return internal_error_response(request_id)


def install_error_handlers(app: FastAPI) -> None:
    """Register the envelope handlers on ``app`` (replacing FastAPI's defaults)."""
    app.add_exception_handler(ApiError, _handle_api_error)
    app.add_exception_handler(StarletteHTTPException, _handle_http_exception)
    app.add_exception_handler(RequestValidationError, _handle_validation_error)
    app.add_exception_handler(Exception, _handle_unexpected)
