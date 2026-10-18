"""Request id generation and lookup shared by the middleware and the error envelope."""

import uuid
from typing import Final

from starlette.requests import Request

REQUEST_ID_HEADER: Final = "X-Request-Id"
REQUEST_ID_STATE_KEY: Final = "request_id"


def new_request_id() -> str:
    """Server-generated id (32 lowercase hex chars); client-supplied ids are never trusted."""
    return uuid.uuid4().hex


def get_request_id(request: Request) -> str:
    """Return the id assigned by ``RequestContextMiddleware``.

    Falls back to a fresh id (stored on the request) when the middleware did not run,
    e.g. for a failure raised outside it, so an error envelope always has a request id.
    """
    request_id = request.scope.get("state", {}).get(REQUEST_ID_STATE_KEY)
    if isinstance(request_id, str):
        return request_id
    request_id = new_request_id()
    request.scope.setdefault("state", {})[REQUEST_ID_STATE_KEY] = request_id
    return request_id
