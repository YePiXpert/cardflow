"""Liveness ``GET /healthz`` (T-002) and readiness ``GET /readyz`` (T-012, deployment-ops §4).

``/healthz`` says the process is up and checks no dependency.

``/readyz`` answers 200 when all four checks pass and 503 otherwise, with the same body
either way (a probe result, not an API error, so not the error envelope)::

    {"checks": {"database": true, "migrations": true, "worker": true, "attachments": true},
     "version": "0.1.0-1a2b3c4d5e6f", "head": "0003"}

* ``database`` -- a NEW connection with the API's own ``DATABASE_URL`` and password (in
  Compose the LOGIN role ``cardflow_api``) answers ``SELECT 1``. A fresh connection per probe
  (``NullPool``) is deliberate: it proves that sessions can still be opened (password,
  ``max_connections``, pg_hba), which a warm pooled connection would hide.
* ``migrations`` -- :func:`cardflow.db.migrations.migration_status` on that connection: the
  database revision equals the code head (``alembic_version`` is readable by cardflow_app).
* ``worker`` -- ``worker_heartbeats`` has a row refreshed within the last two minutes (database
  clock; a worker refreshes it every <= 30 s and deletes it on a clean stop).
* ``attachments`` -- a temporary file can be created, written and removed in
  ``ATTACHMENTS_DIR``.

``version`` is ``CARDFLOW_VERSION`` (the image tag in Compose) and ``head`` the code's Alembic
head; the body carries nothing else -- no connection string, host name or exception text.

Time limits: the database checks share one connection opened with ``connect_timeout`` 2 s
(libpq's minimum) and run every query under a 500 ms ``statement_timeout`` and
``lock_timeout``, inside an overall deadline of 2.5 s; the attachment check has 1 s. Both
groups run concurrently, so a probe answers within about 2.5 s even when the database or the
volume hangs (the brief allows 3 s). A check that misses its deadline counts as failed; its
thread finishes on its own, bounded by the same timeouts. Concurrent requests share the probe
in flight (single flight), so a burst of ``/readyz`` requests opens one database connection
at a time instead of one per request.

Failed checks are logged as ``readiness check failed check=<name>`` with the exception type
and SQLSTATE only (:mod:`cardflow.log` never writes exception messages either).
"""

import asyncio
import logging
import os
import tempfile
from collections.abc import Callable
from pathlib import Path
from typing import Final, Literal

from fastapi import APIRouter, FastAPI, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.engine import Connection, Engine
from sqlalchemy.pool import NullPool

from cardflow.db.engine import create_engine, database_url_from_settings
from cardflow.db.migrations import head_revisions, migration_status
from cardflow.settings import Settings

router = APIRouter(tags=["health"])
log = logging.getLogger("cardflow.api.readiness")

READINESS_DEADLINE_S: Final = 2.5
"""Deadline of the database checks; the attachment check runs alongside with its own 1 s."""
DB_CONNECT_TIMEOUT_S: Final = 2
"""libpq ``connect_timeout`` in whole seconds (2 is libpq's minimum)."""
DB_STATEMENT_TIMEOUT_MS: Final = 500
"""``statement_timeout`` and ``lock_timeout`` of every readiness query."""
ATTACHMENTS_TIMEOUT_S: Final = 1.0
WORKER_HEARTBEAT_MAX_AGE_S: Final = 120.0
"""A worker counts as alive while its ``worker_heartbeats.last_seen_at`` is this recent."""
READINESS_APPLICATION_NAME: Final = "cardflow-readyz"
"""``application_name`` of the probe's connections (visible in ``pg_stat_activity``)."""
PROBE_FILE_PREFIX: Final = ".readyz-"
"""Prefix of the short-lived file the attachment check writes into ``ATTACHMENTS_DIR``."""

type CheckName = Literal["database", "migrations", "worker", "attachments"]
DATABASE_CHECKS: Final[tuple[CheckName, ...]] = ("database", "migrations", "worker")

_SESSION_LIMITS: Final = text(
    "SELECT set_config('statement_timeout', :ms, false), set_config('lock_timeout', :ms, false)"
)
_PING: Final = text("SELECT 1")
_FRESH_HEARTBEAT: Final = text(
    "SELECT EXISTS (SELECT 1 FROM worker_heartbeats "
    "WHERE last_seen_at >= now() - make_interval(secs => :max_age_s))"
)


class Health(BaseModel):
    """Liveness payload."""

    status: Literal["ok"]


class ReadinessChecks(BaseModel):
    """Outcome of each readiness check (``true`` = passed)."""

    database: bool
    migrations: bool
    worker: bool
    attachments: bool


class Readiness(BaseModel):
    """``/readyz`` body, identical for 200 and 503."""

    checks: ReadinessChecks
    version: str
    head: str

    @property
    def ready(self) -> bool:
        """True when every check passed."""
        return all(self.checks.model_dump().values())


def _error_label(exc: BaseException) -> str:
    """Exception type plus SQLSTATE when there is one -- never the message."""
    sqlstate = getattr(getattr(exc, "orig", None), "sqlstate", None)
    return f"{type(exc).__name__} [{sqlstate}]" if sqlstate else type(exc).__name__


def _failed(check: CheckName, detail: str) -> None:
    log.warning("readiness check failed check=%s %s", check, detail)


def _attempt(check: CheckName, action: Callable[[], bool]) -> bool:
    """Run one check; any exception means "not ready" and is logged without its message."""
    try:
        passed = action()
    except Exception as exc:  # noqa: BLE001 - a readiness probe reports every failure as false
        _failed(check, f"error={_error_label(exc)}")
        return False
    return passed


def _migrations_at_head(connection: Connection) -> bool:
    status = migration_status(connection)
    if not status.up_to_date:
        current = ",".join(status.current) or "none"
        _failed("migrations", f"database={current} head={','.join(status.heads)}")
    return status.up_to_date


def _worker_alive(connection: Connection) -> bool:
    alive = bool(
        connection.execute(_FRESH_HEARTBEAT, {"max_age_s": WORKER_HEARTBEAT_MAX_AGE_S}).scalar()
    )
    if not alive:
        _failed("worker", f"reason=no heartbeat within {WORKER_HEARTBEAT_MAX_AGE_S:g} s")
    return alive


def _ping(connection: Connection) -> bool:
    connection.execution_options(isolation_level="AUTOCOMMIT")
    connection.execute(_SESSION_LIMITS, {"ms": str(DB_STATEMENT_TIMEOUT_MS)})
    connection.execute(_PING)
    return True


def database_checks(engine: Engine, results: dict[CheckName, bool]) -> None:
    """Fill ``results`` for :data:`DATABASE_CHECKS`, one key at a time (runs in a thread).

    Autocommit: every query is its own transaction, so a failing or timed-out query does not
    abort the next one. The session timeouts die with the connection (``NullPool``).
    """
    try:
        connection = engine.connect()
    except Exception as exc:  # noqa: BLE001 - a readiness probe reports every failure as false
        _failed("database", f"error={_error_label(exc)}")
        return
    with connection:
        results["database"] = _attempt("database", lambda: _ping(connection))
        if results["database"]:
            results["migrations"] = _attempt("migrations", lambda: _migrations_at_head(connection))
            results["worker"] = _attempt("worker", lambda: _worker_alive(connection))


def attachments_writable(directory: Path) -> bool:
    """Create, write and remove a temporary file in ``directory`` (runs in a thread)."""
    descriptor, name = tempfile.mkstemp(prefix=PROBE_FILE_PREFIX, dir=directory)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(b"cardflow readiness probe\n")
    finally:
        Path(name).unlink()
    return True


class ReadinessProbe:
    """Runs the readiness checks for one application; concurrent callers share one run."""

    def __init__(self, settings: Settings) -> None:
        """Remember ``settings``; no connection is opened before the first probe."""
        self._settings = settings
        self._engine: Engine | None = None
        self._inflight: asyncio.Task[Readiness] | None = None

    def _database_engine(self) -> Engine:
        if self._engine is None:
            self._engine = create_engine(
                database_url_from_settings(self._settings),
                application_name=READINESS_APPLICATION_NAME,
                connect_timeout_s=DB_CONNECT_TIMEOUT_S,
                poolclass=NullPool,
            )
        return self._engine

    async def run(self) -> Readiness:
        """Probe now, or join the probe already in flight on this event loop."""
        loop = asyncio.get_running_loop()
        task = self._inflight
        if task is None or task.done() or task.get_loop() is not loop:
            task = loop.create_task(self._probe())
            self._inflight = task
        # shield: a client that disconnects must not cancel the probe other callers await.
        return await asyncio.shield(task)

    async def _probe(self) -> Readiness:
        results: dict[CheckName, bool] = dict.fromkeys(DATABASE_CHECKS, False)
        attachments = False
        try:
            engine = self._database_engine()
            database_run = asyncio.wait_for(
                asyncio.to_thread(database_checks, engine, results), READINESS_DEADLINE_S
            )
            attachments_run = asyncio.wait_for(
                asyncio.to_thread(attachments_writable, self._settings.attachments_dir),
                ATTACHMENTS_TIMEOUT_S,
            )
            database_outcome, attachments_outcome = await asyncio.gather(
                database_run, attachments_run, return_exceptions=True
            )
            if isinstance(database_outcome, TimeoutError):
                pending = [name for name in DATABASE_CHECKS if not results[name]]
                _failed("database", f"reason=deadline {READINESS_DEADLINE_S:g} s for {pending}")
            elif isinstance(database_outcome, BaseException):
                _failed("database", f"error={_error_label(database_outcome)}")
            if isinstance(attachments_outcome, BaseException):
                _failed("attachments", f"error={_error_label(attachments_outcome)}")
            else:
                attachments = attachments_outcome
        except Exception as exc:  # noqa: BLE001 - never turn a probe failure into a 500
            _failed("database", f"error={_error_label(exc)}")
        checks = ReadinessChecks(
            database=results["database"],
            migrations=results["migrations"],
            worker=results["worker"],
            attachments=attachments,
        )
        return Readiness(checks=checks, version=self._settings.cardflow_version, head=_head())


def _head() -> str:
    try:
        return ",".join(head_revisions())
    except Exception:  # noqa: BLE001 - the probe must answer even without migration scripts
        return "unknown"


def readiness_probe(app: FastAPI) -> ReadinessProbe:
    """The application's probe, created on first use (keeps ``create_app`` unchanged)."""
    probe = getattr(app.state, "readiness_probe", None)
    if probe is None:
        probe = ReadinessProbe(app.state.settings)
        app.state.readiness_probe = probe
    return probe


@router.get("/healthz", summary="Process liveness")
async def healthz() -> Health:
    """Return 200 while the API process is up; checks no dependencies."""
    return Health(status="ok")


@router.get(
    "/readyz",
    summary="Readiness: database, migration head, worker heartbeat, attachment volume",
    response_model=Readiness,
    responses={503: {"model": Readiness, "description": "At least one check failed"}},
)
async def readyz(request: Request) -> JSONResponse:
    """200 when every check passes, else 503; the body lists each check as true/false."""
    readiness = await readiness_probe(request.app).run()
    return JSONResponse(
        readiness.model_dump(mode="json"),
        status_code=200 if readiness.ready else 503,
        headers={"Cache-Control": "no-store"},
    )
