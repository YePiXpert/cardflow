"""Structured logging with a field whitelist (security-privacy SEC-S-08, deployment-ops §7).

* Only :data:`ALLOWED_FIELDS` are copied from a record's ``extra``; anything else (amounts,
  merchants, tokens, request bodies, headers, query strings) is dropped.
* Exception *messages* are never written, because they can carry user data (for example
  database constraint details). A logged exception is reduced to its type, the types of
  its cause chain and the code location of each traceback frame.
* ``request_id`` is attached to every record emitted while a request is being handled.
* Python warnings are logged as class and code location only: their text can quote
  runtime values (pydantic serialization warnings include the offending ``input_value``).
* Third-party loggers that write full URLs at INFO (:data:`QUIET_LOGGERS`) are capped at
  WARNING.
"""

import json
import logging
import sys
import traceback
import warnings
from contextvars import ContextVar
from datetime import UTC, datetime
from pathlib import Path
from types import TracebackType
from typing import Final, TextIO

from cardflow.settings import LogFormat, LogLevel

request_id_var: ContextVar[str | None] = ContextVar("cardflow_request_id", default=None)

ALLOWED_FIELDS: Final[tuple[str, ...]] = (
    "request_id",
    "method",
    "path",
    "status",
    "duration_ms",
)

QUIET_LOGGERS: Final[tuple[str, ...]] = ("httpx", "httpcore")
"""Loggers that record full request URLs (query strings included) at INFO."""

type ExcInfo = tuple[type[BaseException], BaseException, TracebackType | None]


def _type_name(exc_type: type[BaseException]) -> str:
    if exc_type.__module__ == "builtins":
        return exc_type.__qualname__
    return f"{exc_type.__module__}.{exc_type.__qualname__}"


def describe_exception(exc_info: ExcInfo) -> dict[str, object]:
    """Reduce an exception to log-safe fields: type, cause-chain types, frame locations."""
    exc_type, exc, tb = exc_info
    frames = [
        f"{'/'.join(Path(frame.filename).parts[-2:])}:{frame.lineno}:{frame.name}"
        for frame in traceback.StackSummary.extract(traceback.walk_tb(tb), lookup_lines=False)
    ]
    chain: list[str] = []
    seen = {id(exc)}
    linked = exc.__cause__ or (None if exc.__suppress_context__ else exc.__context__)
    while linked is not None and id(linked) not in seen:
        seen.add(id(linked))
        chain.append(_type_name(type(linked)))
        linked = linked.__cause__ or (None if linked.__suppress_context__ else linked.__context__)
    fields: dict[str, object] = {"exc_type": _type_name(exc_type), "exc_frames": frames}
    if chain:
        fields["exc_chain"] = chain
    return fields


def record_fields(record: logging.LogRecord) -> dict[str, object]:
    """Whitelisted, JSON-ready view of ``record``."""
    fields: dict[str, object] = {
        "ts": datetime.fromtimestamp(record.created, tz=UTC).isoformat(timespec="milliseconds"),
        "level": record.levelname.lower(),
        "logger": record.name,
        "message": record.getMessage(),
    }
    for name in ALLOWED_FIELDS:
        value = record.__dict__.get(name)
        if value is not None:
            fields[name] = value
    if record.exc_info is not None and record.exc_info[1] is not None:
        exc_type, exc, tb = record.exc_info
        if exc_type is not None:
            fields.update(describe_exception((exc_type, exc, tb)))
    return fields


def log_warning(
    message: Warning | str,
    category: type[Warning],
    filename: str,
    lineno: int,
    file: TextIO | None = None,
    line: str | None = None,
) -> None:
    """``warnings.showwarning`` replacement: log the warning class and location, never its text.

    Used instead of ``logging.captureWarnings``, which writes the formatted warning text
    verbatim into the record message.
    """
    del message, file, line
    location = "/".join(Path(filename).parts[-2:])
    logging.getLogger("py.warnings").warning("%s at %s:%d", _type_name(category), location, lineno)


class JsonFormatter(logging.Formatter):
    """One JSON object per line."""

    def format(self, record: logging.LogRecord) -> str:
        """Render the whitelisted fields of ``record`` as compact JSON."""
        return json.dumps(
            record_fields(record), ensure_ascii=False, default=str, separators=(",", ":")
        )


class TextFormatter(logging.Formatter):
    """Human-readable single line for local development (same whitelist as JSON)."""

    def format(self, record: logging.LogRecord) -> str:
        """Render ``ts LEVEL logger: message key=value ...`` on one line."""
        fields = record_fields(record)
        message = str(fields.pop("message")).replace("\r", "\\r").replace("\n", "\\n")
        head = f"{fields.pop('ts')} {str(fields.pop('level')).upper():<8} {fields.pop('logger')}:"
        tail = " ".join(
            f"{key}={json.dumps(value, ensure_ascii=False, default=str)}"
            for key, value in fields.items()
        )
        return f"{head} {message} {tail}".rstrip()


class RequestIdFilter(logging.Filter):
    """Attach the current request id (if any) to records that do not carry one."""

    def filter(self, record: logging.LogRecord) -> bool:
        """Never drops records; only annotates them."""
        if record.__dict__.get("request_id") is None:
            record.request_id = request_id_var.get()
        return True


def configure_logging(
    level: LogLevel = "info", fmt: LogFormat = "json", stream: TextIO | None = None
) -> None:
    """Install the single root handler used by ``cardflow`` processes.

    uvicorn's loggers are routed through it, and ``uvicorn.access`` is disabled: its
    lines contain the raw URL including the query string. Access lines come from
    ``cardflow.access`` instead and carry only the route template. Warnings go through
    :func:`log_warning`; :data:`QUIET_LOGGERS` are capped at WARNING.
    """
    handler = logging.StreamHandler(stream if stream is not None else sys.stderr)
    handler.setFormatter(JsonFormatter() if fmt == "json" else TextFormatter())
    handler.addFilter(RequestIdFilter())
    root = logging.getLogger()
    for existing in list(root.handlers):
        root.removeHandler(existing)
    root.addHandler(handler)
    root.setLevel(level.upper())
    for name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        uvicorn_logger = logging.getLogger(name)
        uvicorn_logger.handlers.clear()
        uvicorn_logger.propagate = True
    logging.getLogger("uvicorn.access").disabled = True
    for name in QUIET_LOGGERS:
        logging.getLogger(name).setLevel(logging.WARNING)
    warnings.showwarning = log_warning
