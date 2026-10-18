"""Job handlers for the T-008 tests and the worker demo -- never registered in production.

This file is imported as the top-level module ``jobs_testkit``: ``tests/jobs`` is put on
``sys.path`` by ``tests/jobs/conftest.py`` and by ``worker_launcher.py``, and ``spawn``
children inherit that path, so they can import the subprocess handlers by name.

Kinds (``<prefix>.<name>``, see :func:`register_all`): inline ``noop``, ``track``,
``limited`` (per-kind concurrency 1), ``fail_pii``, ``fail_then_succeed``, ``job_error``,
``wait_gate``, ``sleep_stuck``, ``sleep_cooperative``, ``write_effect``, ``float_result``,
``persist_effect``, ``persist_fail``; subprocess ``sum``, ``sum_prepared``, ``sleep``,
``ignore_term``, ``crash``, ``child_fail_pii``, ``child_job_error``, ``fraction``,
``fraction_persisted``, ``not_json``.

Payloads use integers only (milliseconds, not seconds): stored job JSON has no floats.
"""

import os
import signal
import threading
import time
from collections import Counter
from decimal import Decimal
from pathlib import Path
from typing import Any, Final

from sqlalchemy import text
from sqlalchemy.orm import Session

from cardflow.jobs import JobContext, JobError, LeaseLost, Mode, Registry

PII_MESSAGE: Final = "卡号 4111111111111111 金额 12345元 邮箱 someone@example.com"
"""Synthetic personal data put into exception messages (public test card number)."""
PII_MARKERS: Final = ("4111111111111111", "12345元", "someone@example.com", "卡号", "金额")

EFFECTS_TABLE: Final = "t008_effects"
CREATE_EFFECTS: Final = (
    f"CREATE TABLE IF NOT EXISTS {EFFECTS_TABLE} "
    "(job_id uuid NOT NULL, attempt int NOT NULL, workspace_id uuid, note text NOT NULL)"
)
_INSERT_EFFECT: Final = text(
    f"INSERT INTO {EFFECTS_TABLE} (job_id, attempt, workspace_id, note) "  # noqa: S608
    "VALUES (:job_id, :attempt, "
    "NULLIF(current_setting('app.workspace_id', true), '')::uuid, :note)"
)

_lock = threading.Lock()
EXECUTIONS: Counter[str] = Counter()
"""job id -> number of times an inline handler started on it (this process only)."""
ACTIVE: Counter[str] = Counter()
MAX_ACTIVE: Counter[str] = Counter()
GATES: dict[str, threading.Event] = {}
FINISHED: dict[str, str] = {}
"""job id -> how an inline handler ended ('returned', 'lease_lost', ...)."""


def reset() -> None:
    """Forget all in-process bookkeeping (each test starts clean)."""
    with _lock:
        EXECUTIONS.clear()
        ACTIVE.clear()
        MAX_ACTIVE.clear()
        FINISHED.clear()
        for gate in GATES.values():
            gate.set()
        GATES.clear()


def gate(name: str) -> threading.Event:
    """The event a ``wait_gate`` job with ``{"gate": name}`` waits for."""
    with _lock:
        return GATES.setdefault(name, threading.Event())


def _started(ctx: JobContext) -> None:
    with _lock:
        EXECUTIONS[str(ctx.job_id)] += 1
        ACTIVE[ctx.kind] += 1
        MAX_ACTIVE[ctx.kind] = max(MAX_ACTIVE[ctx.kind], ACTIVE[ctx.kind])


def _ended(ctx: JobContext, how: str) -> None:
    with _lock:
        ACTIVE[ctx.kind] -= 1
        FINISHED[str(ctx.job_id)] = how


# --------------------------------------------------------------------------- inline


def noop(ctx: JobContext) -> dict[str, Any]:
    """Count the execution and return the attempt number."""
    _started(ctx)
    _ended(ctx, "returned")
    return {"ok": True, "attempt": ctx.attempt}


def track(ctx: JobContext) -> dict[str, Any]:
    """Stay busy for ``payload["ms"]`` milliseconds (concurrency measurements)."""
    _started(ctx)
    try:
        time.sleep(ctx.payload.get("ms", 100) / 1000)
    finally:
        _ended(ctx, "returned")
    return {"ok": True}


def fail_pii(ctx: JobContext) -> None:
    """Always raise with personal data in the message."""
    _started(ctx)
    _ended(ctx, "raised")
    raise ValueError(PII_MESSAGE)


def fail_then_succeed(ctx: JobContext) -> dict[str, Any]:
    """Fail (with personal data in the message) until attempt ``payload["succeed_on"]``."""
    _started(ctx)
    _ended(ctx, "returned")
    if ctx.attempt < ctx.payload["succeed_on"]:
        raise RuntimeError(PII_MESSAGE)
    return {"attempt": ctx.attempt}


def job_error(ctx: JobContext) -> None:
    """Raise :class:`JobError` with ``payload["code"]`` / ``payload["permanent"]``."""
    _started(ctx)
    _ended(ctx, "raised")
    raise JobError(ctx.payload["code"], permanent=ctx.payload.get("permanent", False))


def wait_gate(ctx: JobContext) -> dict[str, Any]:
    """Block until the test sets ``gate(payload["gate"])``, then optionally write a row.

    Honours cancellation (``ctx.check()``); records ``lease_lost`` when the lease is gone.
    """
    _started(ctx)
    event = gate(ctx.payload["gate"])
    try:
        while not event.wait(0.02):
            ctx.check()
        if ctx.payload.get("write"):
            with ctx.transaction() as session:
                session.execute(
                    _INSERT_EFFECT,
                    {"job_id": ctx.job_id, "attempt": ctx.attempt, "note": "after-gate"},
                )
    except LeaseLost:
        _ended(ctx, "lease_lost")
        raise
    except BaseException:
        _ended(ctx, "cancelled")
        raise
    _ended(ctx, "returned")
    return {"gate": ctx.payload["gate"]}


def sleep_stuck(ctx: JobContext) -> dict[str, Any]:
    """Sleep ``payload["ms"]`` ignoring cancellation (a handler that cannot be stopped)."""
    _started(ctx)
    time.sleep(ctx.payload["ms"] / 1000)
    _ended(ctx, "returned")
    return {"slept_ms": ctx.payload["ms"]}


def sleep_cooperative(ctx: JobContext) -> dict[str, Any]:
    """Work for ``payload["ms"]`` in small steps, calling ``ctx.check()`` between them."""
    _started(ctx)
    until = time.monotonic() + ctx.payload["ms"] / 1000
    try:
        while time.monotonic() < until:
            ctx.check()
            time.sleep(0.02)
    except BaseException:
        _ended(ctx, "cancelled")
        raise
    _ended(ctx, "returned")
    return {"slept_ms": ctx.payload["ms"]}


def write_effect(ctx: JobContext) -> dict[str, Any]:
    """Write one row to the effects table in a fenced, workspace-bound transaction."""
    _started(ctx)
    with ctx.transaction() as session:
        session.execute(
            _INSERT_EFFECT, {"job_id": ctx.job_id, "attempt": ctx.attempt, "note": "inline"}
        )
    _ended(ctx, "returned")
    return {"written": 1}


def float_result(ctx: JobContext) -> dict[str, Any]:
    """Return a fraction: not storable as ``jobs.result``."""
    _started(ctx)
    _ended(ctx, "returned")
    return {"ratio": 0.5}


# --------------------------------------------------------------------------- hooks


def persist_effect(ctx: JobContext, session: Session, output: dict[str, Any]) -> dict[str, Any]:
    """Persist hook: write a business row in the completion transaction."""
    session.execute(
        _INSERT_EFFECT, {"job_id": ctx.job_id, "attempt": ctx.attempt, "note": "persist"}
    )
    return {"stored": output.get("sum", 0)}


def persist_fail(ctx: JobContext, session: Session, output: object) -> None:
    """Persist hook: write a row, then fail -- the row must be rolled back."""
    del output
    session.execute(
        _INSERT_EFFECT, {"job_id": ctx.job_id, "attempt": ctx.attempt, "note": "persist-fail"}
    )
    raise ValueError(PII_MESSAGE)


def persist_fraction(ctx: JobContext, session: Session, output: dict[str, Any]) -> dict[str, Any]:
    """Persist hook: the child's fraction arrives as an exact Decimal; store it as a string."""
    del ctx, session
    ratio = output["ratio"]
    if not isinstance(ratio, Decimal):
        raise TypeError("fractions must arrive as Decimal")
    return {"ratio": str(ratio), "n": output["n"]}


def prepare_values(ctx: JobContext, session: Session) -> dict[str, Any]:
    """Prepare hook: read from the database (in the worker) what the child needs."""
    seen = session.execute(text(f"SELECT count(*) FROM {EFFECTS_TABLE}")).scalar_one()  # noqa: S608
    return {"values": [*ctx.payload["values"], seen]}


# --------------------------------------------------------------------------- subprocess


def child_sum(data: dict[str, Any]) -> dict[str, Any]:
    """Pure function: sum of ``values``, plus the child pid."""
    return {"sum": sum(data["values"]), "pid": os.getpid()}


def _write_pid(data: dict[str, Any]) -> None:
    pid_file = data.get("pid_file")
    if pid_file:
        Path(pid_file).write_text(str(os.getpid()), encoding="ascii")


def child_sleep(data: dict[str, Any]) -> dict[str, Any]:
    """Sleep ``ms`` milliseconds (records its pid first when ``pid_file`` is given)."""
    _write_pid(data)
    time.sleep(data["ms"] / 1000)
    return {"slept_ms": data["ms"]}


def child_ignore_term(data: dict[str, Any]) -> dict[str, Any]:
    """Ignore SIGTERM and sleep: the worker has to escalate to SIGKILL."""
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    _write_pid(data)
    time.sleep(data["ms"] / 1000)
    return {"slept_ms": data["ms"]}


def child_crash(data: dict[str, Any]) -> None:
    """Exit without a reply (like a segfault or an OOM kill would)."""
    del data
    os._exit(3)


def child_fail_pii(data: dict[str, Any]) -> None:
    """Raise with personal data in the message, inside the child."""
    del data
    raise ValueError(PII_MESSAGE)


def child_job_error(data: dict[str, Any]) -> None:
    """Raise a permanent :class:`JobError` in the child."""
    del data
    raise JobError("FILE_REJECTED", permanent=True)


def child_fraction(data: dict[str, Any]) -> dict[str, Any]:
    """Return a fraction (allowed in transit, decoded as Decimal by the worker)."""
    del data
    return {"ratio": 0.25, "n": 1}


def child_not_json(data: dict[str, Any]) -> dict[str, Any]:
    """Return something JSON cannot encode."""
    del data
    return {"set": {1, 2}}


# --------------------------------------------------------------------------- registry

_INLINE: Final = {
    "noop": noop,
    "track": track,
    "fail_pii": fail_pii,
    "fail_then_succeed": fail_then_succeed,
    "job_error": job_error,
    "wait_gate": wait_gate,
    "sleep_stuck": sleep_stuck,
    "sleep_cooperative": sleep_cooperative,
    "write_effect": write_effect,
    "float_result": float_result,
}
_SUBPROCESS: Final = {
    "sum": child_sum,
    "sleep": child_sleep,
    "ignore_term": child_ignore_term,
    "crash": child_crash,
    "child_fail_pii": child_fail_pii,
    "child_job_error": child_job_error,
    "fraction": child_fraction,
    "not_json": child_not_json,
}
DEFAULT_TIMEOUT_S: Final = 30
DEFAULT_MAX_ATTEMPTS: Final = 3


def register_all(registry: Registry, *, prefix: str = "test") -> Registry:
    """Register every test kind as ``<prefix>.<name>`` on ``registry`` and return it."""
    for name, func in _INLINE.items():
        registry.register(
            f"{prefix}.{name}",
            mode=Mode.INLINE,
            timeout_s=DEFAULT_TIMEOUT_S,
            max_attempts=DEFAULT_MAX_ATTEMPTS,
        )(func)
    for name, func in _SUBPROCESS.items():
        registry.register(
            f"{prefix}.{name}",
            mode=Mode.SUBPROCESS,
            timeout_s=DEFAULT_TIMEOUT_S,
            max_attempts=DEFAULT_MAX_ATTEMPTS,
        )(func)
    registry.register(
        f"{prefix}.limited",
        mode=Mode.INLINE,
        timeout_s=DEFAULT_TIMEOUT_S,
        max_attempts=DEFAULT_MAX_ATTEMPTS,
        concurrency=1,
    )(track)
    registry.register(
        f"{prefix}.persist_effect",
        mode=Mode.SUBPROCESS,
        timeout_s=DEFAULT_TIMEOUT_S,
        max_attempts=DEFAULT_MAX_ATTEMPTS,
        persist=persist_effect,
    )(child_sum)
    registry.register(
        f"{prefix}.persist_fail",
        mode=Mode.SUBPROCESS,
        timeout_s=DEFAULT_TIMEOUT_S,
        max_attempts=DEFAULT_MAX_ATTEMPTS,
        persist=persist_fail,
    )(child_sum)
    registry.register(
        f"{prefix}.sum_prepared",
        mode=Mode.SUBPROCESS,
        timeout_s=DEFAULT_TIMEOUT_S,
        max_attempts=DEFAULT_MAX_ATTEMPTS,
        prepare=prepare_values,
        persist=persist_effect,
    )(child_sum)
    registry.register(
        f"{prefix}.fraction_persisted",
        mode=Mode.SUBPROCESS,
        timeout_s=DEFAULT_TIMEOUT_S,
        max_attempts=DEFAULT_MAX_ATTEMPTS,
        persist=persist_fraction,
    )(child_fraction)
    return registry


def build_registry(prefix: str = "test") -> Registry:
    """A fresh registry holding only the test kinds."""
    return register_all(Registry(), prefix=prefix)
