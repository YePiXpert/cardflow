"""Job error codes and the exceptions job handlers may raise (admin-console-spec AP-05).

``jobs.last_error`` only ever holds ``CODE`` or ``CODE:Detail``:

* ``CODE`` is one of :class:`JobErrorCode` or a code a handler passed to :class:`JobError`
  (``FILE_REJECTED``); it is the "error code" column of AP-05;
* ``Detail`` is, for unexpected exceptions, the exception *type* (``HANDLER_ERROR:ValueError``).

Exception messages and payload values are never stored or logged: they can carry personal
data (amounts, card numbers, e-mail addresses). Everything written to ``last_error`` goes
through :func:`error_text`, which keeps only ``[A-Za-z0-9_.#]`` and replaces runs of four or
more digits with ``#`` (AP-05: error summaries carry no amounts, e-mail addresses or runs of
four or more digits).
"""

import re
from enum import StrEnum
from typing import Final

ERROR_CODE_PATTERN: Final = re.compile(r"[A-Z][A-Z0-9_]{1,63}")
_LONG_DIGITS: Final = re.compile(r"\d{4,}")
_DETAIL_UNSAFE: Final = re.compile(r"[^A-Za-z0-9_.#]")
MAX_DETAIL_CHARS: Final = 100


class JobErrorCode(StrEnum):
    """Error codes the queue itself writes to ``jobs.last_error``."""

    TIMEOUT = "TIMEOUT"
    """The attempt ran longer than its timeout (subprocess: killed by the worker)."""
    HANDLER_ERROR = "HANDLER_ERROR"
    """The handler (or its prepare/persist hook) raised; the detail is the exception type."""
    CRASHED = "CRASHED"
    """The job subprocess exited without sending a result (crash, os._exit, OOM kill)."""
    INPUT_INVALID = "INPUT_INVALID"
    """The subprocess input was not JSON-serializable or too large."""
    RESULT_INVALID = "RESULT_INVALID"
    """The handler result was not storable JSON (non-integer number, too large, not JSON)."""
    LEASE_EXPIRED = "LEASE_EXPIRED"
    """Reclaimed: the worker holding the job stopped renewing its lease (crash, partition)."""
    INTERRUPTED = "INTERRUPTED"
    """Released by a worker shutdown before it finished; the attempt is not counted."""


def check_error_code(code: str) -> str:
    """Return ``code`` if it is a valid error code, else raise :class:`ValueError`."""
    if (
        not isinstance(code, str)
        or ERROR_CODE_PATTERN.fullmatch(code) is None
        or _LONG_DIGITS.search(code) is not None
    ):
        raise ValueError("a job error code must match [A-Z][A-Z0-9_]{1,63} without 4+ digit runs")
    return code


class JobError(Exception):
    """Raised by a handler to end the attempt with one of *our* error codes.

    ``permanent=False`` (default): the attempt fails and is retried with backoff like any
    error, but ``last_error`` shows ``code`` instead of ``HANDLER_ERROR:<type>``.
    ``permanent=True``: retrying cannot help (e.g. ``FILE_REJECTED``); the job ends as
    ``failed`` at once. Only ``code`` is recorded -- never a message.
    """

    def __init__(self, code: str, *, permanent: bool = False) -> None:
        """``code``: ``[A-Z][A-Z0-9_]{1,63}``, no run of four or more digits."""
        super().__init__(check_error_code(code))
        self.code = code
        self.permanent = permanent


class LeaseLost(Exception):  # noqa: N818 -- a state, not an "error" the caller made
    """This attempt no longer holds the job's lease (reclaimed, timed out or released).

    Raised by :meth:`cardflow.jobs.JobContext.transaction`; handlers should let it
    propagate. Nothing is written for an attempt that lost its lease.
    """


class LeaseBusy(LeaseLost):
    """The lease is still ours, but another transaction holds the job row (worker-internal:
    a non-waiting transition found a handler transaction open and will retry later)."""


class JobTimeout(Exception):  # noqa: N818 -- mirrors the TIMEOUT error code
    """The attempt is past its deadline (raised by :class:`cardflow.jobs.JobContext`)."""


def type_label(exc_type: type[BaseException]) -> str:
    """``ValueError`` for builtins, ``module.QualName`` otherwise (same as the log formatter)."""
    if exc_type.__module__ == "builtins":
        return exc_type.__qualname__
    return f"{exc_type.__module__}.{exc_type.__qualname__}"


def error_text(code: str, detail: str | None = None) -> str:
    """``CODE`` or ``CODE:Detail``, with ``detail`` reduced to safe characters."""
    check_error_code(code)
    if not detail:
        return code
    clean = _LONG_DIGITS.sub("#", _DETAIL_UNSAFE.sub("_", detail))[:MAX_DETAIL_CHARS]
    return f"{code}:{clean}"


def handler_error(exc: BaseException) -> str:
    """``HANDLER_ERROR:<exception type>`` for an unexpected handler exception."""
    return error_text(JobErrorCode.HANDLER_ERROR, type_label(type(exc)))


def parse_error_text(text: str) -> str | None:
    """Re-validate an error text received from a job subprocess; ``None`` if malformed."""
    code, _, detail = text.partition(":")
    try:
        rebuilt = error_text(code, detail or None)
    except ValueError:
        return None
    return rebuilt if rebuilt == text else None
