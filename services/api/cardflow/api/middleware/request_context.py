"""Request context: request id, ``X-Request-Id`` header, access log, last-resort 500.

Pure ASGI middleware (not ``BaseHTTPMiddleware``), so streaming responses and context
variables behave normally. ``create_app()`` adds it last, which makes it the outermost
user middleware: every response, including ones produced by other middleware (T-010
idempotency), carries ``X-Request-Id`` and gets exactly one access-log line.

The access line holds only ``request_id``, ``method``, the route *template*, ``status``
and ``duration_ms`` -- never the concrete URL, query string, headers or body.
"""

import logging
import time
from collections.abc import Mapping
from typing import Final

from starlette.types import ASGIApp, Message, Receive, Scope, Send

from cardflow.api.errors import internal_error_response, response_for_known_exception
from cardflow.api.request_id import REQUEST_ID_HEADER, REQUEST_ID_STATE_KEY, new_request_id
from cardflow.log import request_id_var

UNMATCHED_ROUTE: Final = "<unmatched>"
_HEADER_NAME: Final = REQUEST_ID_HEADER.lower().encode("latin-1")

access_logger = logging.getLogger("cardflow.access")
error_logger = logging.getLogger("cardflow.api")


def route_template(scope: Scope) -> str | None:
    """Return the matched route template (``/v1/plans/{plan_id}``) or ``None``."""
    # FastAPI 0.143 resolves included routers lazily: scope["route"] is then the
    # router-local route *without* the include prefix, and the full template lives in
    # FastAPI's effective route context (FastAPI's own telemetry reads it the same way).
    # tests/test_api_envelope.py pins this, so an upgrade that changes it fails loudly.
    fastapi_scope = scope.get("fastapi")
    if isinstance(fastapi_scope, Mapping):
        context = fastapi_scope.get("effective_route_context")
        if context is not None:
            template = getattr(getattr(context, "starlette_route", None), "path_format", None)
            template = template or getattr(context, "path_format", None)
            if isinstance(template, str) and template:
                return template
    template = getattr(scope.get("route"), "path_format", None)
    if isinstance(template, str) and template:
        return template
    return None


class RequestContextMiddleware:
    """Assign a request id, stamp responses, log access, convert unexpected errors."""

    def __init__(self, app: ASGIApp) -> None:
        """Wrap the inner ASGI ``app``."""
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        """Handle one ASGI connection; only ``http`` scopes are instrumented."""
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        request_id = new_request_id()
        scope.setdefault("state", {})[REQUEST_ID_STATE_KEY] = request_id
        token = request_id_var.set(request_id)
        started = time.perf_counter()
        status: int | None = None
        request_id_header = (_HEADER_NAME, request_id.encode("latin-1"))

        async def send_with_request_id(message: Message) -> None:
            nonlocal status
            if message["type"] == "http.response.start":
                status = int(message["status"])
                headers = [
                    (name, value)
                    for name, value in message.get("headers", ())
                    if name.lower() != _HEADER_NAME
                ]
                headers.append(request_id_header)
                message = {**message, "headers": headers}
            await send(message)

        try:
            await self.app(scope, receive, send_with_request_id)
        except Exception as exc:
            if status is not None:
                # Headers are already on the wire, so no envelope is possible. Re-raise:
                # the app's fallback handler logs it with this request id (the id is in
                # scope["state"]) and the server aborts the response.
                raise
            response = response_for_known_exception(request_id, exc)
            if response is None:
                # Logged here, with the request id; the client only sees INTERNAL_ERROR.
                error_logger.error(
                    "unhandled_exception", exc_info=exc, extra={"request_id": request_id}
                )
                response = internal_error_response(request_id)
            await response(scope, receive, send_with_request_id)
        finally:
            access_logger.info(
                "http_request",
                extra={
                    "request_id": request_id,
                    "method": scope.get("method"),
                    "path": route_template(scope) or UNMATCHED_ROUTE,
                    "status": status if status is not None else 500,
                    "duration_ms": round((time.perf_counter() - started) * 1000, 3),
                },
            )
            request_id_var.reset(token)
