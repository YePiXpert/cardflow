"""The ``cardflow worker`` process: claim jobs, run them, keep leases alive, stop cleanly.

Threads of one worker process:

* main thread -- the claim loop: whenever a slot is free (``--concurrency`` overall, the
  handler's ``concurrency`` per kind) it leases due jobs with ``FOR UPDATE SKIP LOCKED``
  and hands them to the job threads; it also enforces inline timeouts;
* job threads -- a pool of ``concurrency`` daemon threads; each runs one inline handler or
  supervises one subprocess child at a time;
* heartbeat thread -- every ``heartbeat_interval_s`` (<= 30 s) renews the leases of the
  running jobs (``locked_until``, ``heartbeat_at``) and upserts this worker's
  ``worker_heartbeats`` row with ``running_jobs``; a lease that cannot be renewed for a
  whole ``lease_s`` is given up (its subprocess child is killed);
* scheduler threads -- apscheduler with the system periodic tasks
  (:mod:`cardflow.jobs.periodic`).

Shutdown (SIGTERM/SIGINT, :meth:`Worker.request_stop`): claiming stops at once, running
jobs get up to ``shutdown_timeout_s`` to finish. Jobs still running after that are stopped
(subprocess children killed) and *released*: back to ``queued``, ``attempts`` decremented,
``last_error = INTERRUPTED``. The interrupted attempt is not counted because the operator
caused the interruption, not the job: counting it would push long jobs towards ``dead``
through routine deploys. A crash is different -- no release happens, the lease expires and
the reclaim counts the attempt (``LEASE_EXPIRED``), so a job that keeps killing its worker
still ends ``dead`` after ``max_attempts``. A second signal skips the rest of the grace
period. Inline handler threads cannot be killed; one that ignores cancellation is left
behind (daemon thread) and its row is released, or -- if it is inside a transaction --
left to lease expiry.
"""

import logging
import os
import queue
import secrets
import signal
import socket
import threading
import time
import uuid
from collections import Counter, deque
from collections.abc import Callable, Sequence
from contextlib import AbstractContextManager
from dataclasses import dataclass, field, replace
from datetime import UTC, datetime
from types import FrameType
from typing import TYPE_CHECKING, Final

from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session, sessionmaker

from cardflow.db.engine import create_engine, create_session_factory, database_url_from_settings
from cardflow.jobs.backoff import Backoff
from cardflow.jobs.codec import (
    MAX_RESULT_BYTES,
    MAX_TRANSPORT_BYTES,
    JsonRejected,
    encode_stored,
    encode_transport,
)
from cardflow.jobs.context import JobContext, fenced_tx
from cardflow.jobs.errors import (
    JobError,
    JobErrorCode,
    JobTimeout,
    LeaseBusy,
    LeaseLost,
    handler_error,
)
from cardflow.jobs.periodic import PeriodicContext, PeriodicScheduler, PeriodicTask, system_tasks
from cardflow.jobs.queue import (
    ClaimedJob,
    FailureOutcome,
    JobStatus,
    LockMode,
    WorkerIdentity,
    claim_jobs,
    delete_heartbeat,
    mark_failed,
    mark_succeeded,
    release,
    renew_leases,
    upsert_heartbeat,
)
from cardflow.jobs.registry import HandlerSpec, Mode, Registry, production_registry
from cardflow.jobs.subproc import ChildStatus, run_child

if TYPE_CHECKING:
    from cardflow.settings import Settings

log = logging.getLogger("cardflow.jobs.worker")

WORKER_APPLICATION_NAME: Final = "cardflow-worker"
EXIT_OK: Final = 0
EXIT_FAILED: Final = 1
"""``cardflow worker`` exit code: database unusable at start, or an unexpected crash."""
MAX_CONCURRENCY: Final = 10
"""Bounded by the default SQLAlchemy pool (5 + 10 overflow) minus the worker's own threads."""
MAX_HEARTBEAT_INTERVAL_S: Final = 30.0
HEARTBEAT_LOCK_TIMEOUT_MS: Final = 5000
SHUTDOWN_POLL_S: Final = 0.1
SIGNAL_POLL_S: Final = 0.2
"""The main thread notices a received SIGTERM/SIGINT within this time."""
RELEASE_SETTLE_S: Final = 1.0

_SET_LOCK_TIMEOUT: Final = text("SELECT set_config('lock_timeout', :value, true)")
_CHECK_SCHEMA: Final = (
    text("SELECT 1 FROM jobs LIMIT 0"),
    text("SELECT 1 FROM worker_heartbeats LIMIT 0"),
)

# Reasons an attempt is cancelled by the worker (JobContext.cancelled becomes true).
TIMEOUT: Final = "timeout"
LEASE_LOST: Final = "lease_lost"
SHUTDOWN: Final = "shutdown"


class WorkerStartupError(RuntimeError):
    """The database is unreachable or not migrated; the worker did not start."""


@dataclass(frozen=True, slots=True, kw_only=True)
class WorkerConfig:
    """Worker tuning; defaults match deployment-ops (``--concurrency 2``)."""

    concurrency: int = 2
    lease_s: float = 60.0
    """A running job's ``locked_until`` is kept at ``now() + lease_s`` by the heartbeat."""
    heartbeat_interval_s: float = 10.0
    poll_interval_s: float = 1.0
    shutdown_timeout_s: float = 20.0
    terminate_grace_s: float = 2.0
    """Subprocess: time between SIGTERM and SIGKILL."""
    phase_timeout_s: float = 30.0
    """``statement_timeout`` of the prepare/persist/finish transactions."""
    reclaim_interval_s: float = 30.0
    heartbeat_purge_interval_s: float = 600.0
    heartbeat_max_age_s: float = 3600.0
    db_retry_base_s: float = 1.0
    db_retry_max_s: float = 30.0
    """Claiming failed (database down): wait 1, 2, 4, ... seconds, at most 30."""
    backoff: Backoff = field(default_factory=Backoff)
    version: str = "dev"
    log_level: str = "info"
    log_format: str = "json"
    """Logging setup handed to subprocess children (they configure their own handler)."""

    def __post_init__(self) -> None:
        """Validate ranges and the timing relations the lease protocol relies on."""
        if not 1 <= self.concurrency <= MAX_CONCURRENCY:
            raise ValueError(f"concurrency must be between 1 and {MAX_CONCURRENCY}")
        for name in (
            "lease_s",
            "heartbeat_interval_s",
            "poll_interval_s",
            "terminate_grace_s",
            "phase_timeout_s",
            "reclaim_interval_s",
            "heartbeat_purge_interval_s",
            "heartbeat_max_age_s",
            "db_retry_base_s",
            "db_retry_max_s",
        ):
            if not getattr(self, name) > 0:
                raise ValueError(f"{name} must be positive")
        if self.shutdown_timeout_s < 0:
            raise ValueError("shutdown_timeout_s must be >= 0")
        if self.heartbeat_interval_s > MAX_HEARTBEAT_INTERVAL_S:
            raise ValueError(f"heartbeat_interval_s must be <= {MAX_HEARTBEAT_INTERVAL_S:g}")
        if self.lease_s < 3 * self.heartbeat_interval_s:
            raise ValueError("lease_s must be at least three heartbeat intervals")


@dataclass(slots=True)
class WorkerStats:
    """Counters of one :meth:`Worker.run`."""

    claimed: int = 0
    succeeded: int = 0
    retried: int = 0
    failed: int = 0
    dead: int = 0
    timed_out: int = 0
    released: int = 0
    abandoned: int = 0


@dataclass(eq=False, slots=True)
class _Running:
    job: ClaimedJob
    spec: HandlerSpec
    timeout_s: int
    cancel: threading.Event
    last_renewed: float
    started: float
    deadline: float | None = None
    leased: bool = True
    """Still holds the lease: renewed by the heartbeat and counted in ``running_jobs``."""
    finishing: bool = False
    cancel_reason: str | None = None
    timeout_recorded: bool = False


@dataclass(frozen=True, slots=True)
class _Success:
    output: object


@dataclass(frozen=True, slots=True)
class _Failure:
    error: str
    permanent: bool = False
    timeout: bool = False


@dataclass(frozen=True, slots=True)
class _Abandoned:
    reason: str


type _Outcome = _Success | _Failure | _Abandoned


class Worker:
    """Runs jobs of the kinds in ``registry`` until stopped."""

    def __init__(
        self,
        session_factory: sessionmaker[Session],
        registry: Registry,
        config: WorkerConfig | None = None,
        *,
        periodic_tasks: Sequence[PeriodicTask] = (),
    ) -> None:
        """``periodic_tasks`` run in addition to the system tasks."""
        self._sf = session_factory
        self._registry = registry
        self._config = config if config is not None else WorkerConfig()
        hostname = socket.gethostname()
        pid = os.getpid()
        self._identity = WorkerIdentity(
            worker_id=f"{hostname}:{pid}:{secrets.token_hex(3)}",
            hostname=hostname,
            pid=pid,
            version=self._config.version,
            started_at=datetime.now(UTC),
        )
        self._lock = threading.Lock()
        self._running: dict[uuid.UUID, _Running] = {}
        self._stats = WorkerStats()
        self._stop = threading.Event()
        self._force = threading.Event()
        self._wake = threading.Event()
        self._heartbeat_stop = threading.Event()
        self._dispatch: queue.SimpleQueue[_Running | None] = queue.SimpleQueue()
        self._threads: list[threading.Thread] = []
        self._signal: int | None = None
        self._pending_signals: deque[int] = deque()
        self._started = False
        self._once = False
        tasks = system_tasks(
            reclaim_interval_s=self._config.reclaim_interval_s,
            purge_interval_s=self._config.heartbeat_purge_interval_s,
        )
        self._scheduler = PeriodicScheduler(
            (*tasks, *periodic_tasks),
            PeriodicContext(
                session_factory=session_factory,
                worker_id=self._identity.worker_id,
                backoff=self._config.backoff,
                heartbeat_max_age_s=self._config.heartbeat_max_age_s,
            ),
        )

    # ------------------------------------------------------------------ public API

    @property
    def worker_id(self) -> str:
        """``hostname:pid:random`` -- written to ``jobs.locked_by`` and ``worker_heartbeats``."""
        return self._identity.worker_id

    @property
    def config(self) -> WorkerConfig:
        """The configuration in use."""
        return self._config

    def stats(self) -> WorkerStats:
        """A snapshot of the counters."""
        with self._lock:
            return replace(self._stats)

    def running_jobs(self) -> int:
        """Jobs this worker currently holds a lease for."""
        with self._lock:
            return sum(1 for running in self._running.values() if running.leased)

    def request_stop(self, *, force: bool = False) -> None:
        """Stop claiming and shut down; a second request (or ``force``) skips the grace."""
        if force or self._stop.is_set():
            self._force.set()
        self._stop.set()
        self._wake.set()

    def install_signal_handlers(self) -> Callable[[], None]:
        """SIGTERM/SIGINT -> :meth:`request_stop` (main thread only); returns a restorer."""
        signals = (signal.SIGTERM, signal.SIGINT)
        previous = {signum: signal.getsignal(signum) for signum in signals}

        def handle(signum: int, frame: FrameType | None) -> None:
            # Runs on the main thread between two bytecodes -- possibly while that thread
            # holds the internal (non-reentrant) lock of one of our Events, which
            # Event.set/clear/wait all take. Acquiring any lock here could deadlock the
            # process, so only record the signal (deque.append takes no lock); the main
            # thread turns it into request_stop() within SIGNAL_POLL_S (_poll_signals).
            del frame
            self._pending_signals.append(signum)

        for signum in signals:
            signal.signal(signum, handle)

        def restore() -> None:
            for signum, handler in previous.items():
                signal.signal(signum, handler)

        return restore

    def run(self, *, once: bool = False) -> WorkerStats:
        """Run until stopped (``once``: one claim round, wait for it, then stop).

        Raises :class:`WorkerStartupError` if the database is not usable at start.
        """
        if self._started:
            raise RuntimeError("a Worker can only run once")
        self._started = True
        self._once = once
        self._startup()
        self._start_threads()
        try:
            if once:
                self._scheduler.run_all_once()
                try:
                    self._claim_round()
                except SQLAlchemyError:
                    log.error("claiming jobs failed", exc_info=True)
                self._wait_for_jobs()
            else:
                self._scheduler.start()
                self._loop()
        finally:
            self._shutdown()
        return self.stats()

    # ------------------------------------------------------------------ lifecycle

    def _startup(self) -> None:
        try:
            with self._sf.begin() as session:
                for statement in _CHECK_SCHEMA:
                    session.execute(statement)
                upsert_heartbeat(session, self._identity, running_jobs=0)
        except SQLAlchemyError:
            log.error("worker cannot start: database unavailable or not migrated", exc_info=True)
            raise WorkerStartupError("database unavailable or not migrated") from None
        log.info(
            "worker started worker_id=%s concurrency=%d kinds=%s lease_s=%g heartbeat_s=%g "
            "version=%s",
            self.worker_id,
            self._config.concurrency,
            ",".join(self._registry.kinds()) or "-",
            self._config.lease_s,
            self._config.heartbeat_interval_s,
            self._config.version,
        )

    def _start_threads(self) -> None:
        for index in range(self._config.concurrency):
            thread = threading.Thread(
                target=self._job_thread, name=f"cardflow-job-{index}", daemon=True
            )
            thread.start()
            self._threads.append(thread)
        heartbeat = threading.Thread(
            target=self._heartbeat_loop, name="cardflow-heartbeat", daemon=True
        )
        heartbeat.start()
        self._threads.append(heartbeat)

    def _poll_signals(self) -> None:
        """Main thread: act on signals recorded by the handler (stop, then force)."""
        while self._pending_signals:
            self._signal = self._pending_signals.popleft()
            self.request_stop()

    def _idle(self, seconds: float) -> None:
        """Wait up to ``seconds`` for a wake-up (slot freed, stop), polling for signals."""
        deadline = time.monotonic() + seconds
        while True:
            self._poll_signals()
            remaining = deadline - time.monotonic()
            if remaining <= 0 or self._wake.is_set() or self._stop.is_set():
                return
            self._wake.wait(min(remaining, SIGNAL_POLL_S))

    def _loop(self) -> None:
        db_failures = 0
        while True:
            self._poll_signals()
            if self._stop.is_set():
                return
            self._wake.clear()
            self._enforce_inline_timeouts()
            try:
                claimed = self._claim_round()
            except SQLAlchemyError:
                db_failures += 1
                delay = min(
                    self._config.db_retry_max_s,
                    self._config.db_retry_base_s * 2.0 ** min(db_failures - 1, 30),
                )
                log.warning("claiming jobs failed; retrying in %gs", delay, exc_info=True)
                self._idle(delay)
                continue
            db_failures = 0
            if not claimed:
                self._idle(self._config.poll_interval_s)

    def _wait_for_jobs(self) -> None:
        while True:
            self._poll_signals()
            if self._stop.is_set():
                return
            with self._lock:
                if not self._running:
                    return
            self._wake.clear()
            self._enforce_inline_timeouts()
            self._wake.wait(SHUTDOWN_POLL_S)

    def _shutdown(self) -> None:
        self._scheduler.shutdown()
        with self._lock:
            running = len(self._running)
        if self._signal is not None:
            reason = signal.Signals(self._signal).name
        else:
            reason = "once" if self._once and not self._stop.is_set() else "request"
        log.info(
            "worker stopping reason=%s running=%d shutdown_timeout_s=%g",
            reason,
            running,
            self._config.shutdown_timeout_s,
        )
        deadline = time.monotonic() + self._config.shutdown_timeout_s
        while True:
            self._poll_signals()  # a second signal forces the stop
            with self._lock:
                active = list(self._running.values())
            if not active or self._force.is_set() or time.monotonic() >= deadline:
                break
            self._wake.clear()
            self._enforce_inline_timeouts()
            self._wake.wait(SHUTDOWN_POLL_S)
        if active:
            self._release_all(active)
        for _ in range(self._config.concurrency):
            self._dispatch.put(None)
        self._heartbeat_stop.set()
        for thread in self._threads:
            thread.join(timeout=self._config.terminate_grace_s + RELEASE_SETTLE_S)
        try:
            with self._sf.begin() as session:
                delete_heartbeat(session, self.worker_id)
        except SQLAlchemyError:
            log.warning("could not delete the worker heartbeat row", exc_info=True)
        stats = self.stats()
        log.info(
            "worker stopped worker_id=%s claimed=%d succeeded=%d retried=%d failed=%d dead=%d "
            "timed_out=%d released=%d abandoned=%d",
            self.worker_id,
            stats.claimed,
            stats.succeeded,
            stats.retried,
            stats.failed,
            stats.dead,
            stats.timed_out,
            stats.released,
            stats.abandoned,
        )

    def _release_all(self, active: list[_Running]) -> None:
        log.warning("grace period over: stopping running jobs count=%d", len(active))
        for running in active:
            self._cancel(running, SHUTDOWN)
        # Subprocess supervisors kill their child and release the job themselves; so do
        # inline handlers that honour cancellation. Give them a moment.
        settle_until = time.monotonic() + self._config.terminate_grace_s + RELEASE_SETTLE_S
        while time.monotonic() < settle_until:
            with self._lock:
                if not self._running:
                    return
            self._wake.clear()
            self._wake.wait(SHUTDOWN_POLL_S)
        with self._lock:
            stuck = [running for running in self._running.values() if running.leased]
        for running in stuck:
            log.warning(
                "inline handler did not stop job_id=%s kind=%s", running.job.id, running.job.kind
            )
            self._release(running, lock="update_skip")

    # ------------------------------------------------------------------ claiming

    def _claim_round(self) -> int:
        if self._stop.is_set():
            return 0
        with self._lock:
            free = self._config.concurrency - len(self._running)
            per_kind = Counter(running.job.kind for running in self._running.values())
        if free <= 0:
            return 0
        slots = {
            spec.kind: None if spec.concurrency is None else spec.concurrency - per_kind[spec.kind]
            for spec in self._registry.specs()
        }
        claimed = claim_jobs(
            self._sf,
            worker_id=self.worker_id,
            slots=slots,
            limit=free,
            lease_s=self._config.lease_s,
        )
        now = time.monotonic()
        for job in claimed:
            spec = self._registry[job.kind]
            running = _Running(
                job=job,
                spec=spec,
                timeout_s=job.timeout_s if job.timeout_s is not None else spec.timeout_s,
                cancel=threading.Event(),
                last_renewed=now,
                started=now,
            )
            with self._lock:
                self._running[job.id] = running
                self._stats.claimed += 1
            log.info(
                "job claimed job_id=%s kind=%s attempt=%d/%d mode=%s timeout_s=%d",
                job.id,
                job.kind,
                job.attempt,
                job.max_attempts,
                spec.mode.value,
                running.timeout_s,
            )
            self._dispatch.put(running)
        return len(claimed)

    # ------------------------------------------------------------------ job threads

    def _job_thread(self) -> None:
        while True:
            running = self._dispatch.get()
            if running is None:
                return
            try:
                self._settle(running, self._execute(running))
            except BaseException:
                # A bug or a database outage while finishing: the lease runs out and the
                # reclaim takes the job back. The thread itself must survive.
                log.error(
                    "worker error while finishing job job_id=%s kind=%s",
                    running.job.id,
                    running.job.kind,
                    exc_info=True,
                )
                self._end_lease(running)
            finally:
                with self._lock:
                    self._running.pop(running.job.id, None)
                self._wake.set()

    def _context(self, running: _Running, deadline: float) -> JobContext:
        job = running.job
        return JobContext(
            job_id=job.id,
            kind=job.kind,
            payload=job.payload,
            attempt=job.attempt,
            max_attempts=job.max_attempts,
            workspace_id=job.workspace_id,
            timeout_s=running.timeout_s,
            worker_id=self.worker_id,
            session_factory=self._sf,
            deadline=deadline,
            cancel_event=running.cancel,
        )

    def _phase_deadline(self) -> float:
        return time.monotonic() + self._config.phase_timeout_s

    def _execute(self, running: _Running) -> _Outcome:
        if running.spec.mode is Mode.INLINE:
            return self._run_inline(running)
        return self._run_subprocess(running)

    def _run_inline(self, running: _Running) -> _Outcome:
        running.deadline = time.monotonic() + running.timeout_s
        ctx = self._context(running, running.deadline)
        try:
            outcome: _Outcome = _Success(running.spec.func(ctx))
        except LeaseLost:
            outcome = _Abandoned(running.cancel_reason or LEASE_LOST)
        except JobTimeout:
            outcome = _Failure(JobErrorCode.TIMEOUT.value, timeout=True)
        except JobError as exc:
            outcome = _Failure(exc.code, permanent=exc.permanent)
        except BaseException as exc:  # SystemExit from a handler must not end the thread
            log.warning(
                "job handler raised job_id=%s kind=%s",
                running.job.id,
                running.job.kind,
                exc_info=True,
            )
            outcome = _Failure(handler_error(exc))
        if running.cancel_reason == TIMEOUT:
            # The attempt was declared timed out; whatever the handler did afterwards is void.
            if running.timeout_recorded:
                return _Abandoned(TIMEOUT)
            return _Failure(JobErrorCode.TIMEOUT.value, timeout=True)
        return outcome

    def _run_subprocess(self, running: _Running) -> _Outcome:
        spec = running.spec
        job = running.job
        if spec.prepare is not None:
            try:
                with self._fenced(running, lock="share") as session:
                    child_input = spec.prepare(
                        self._context(running, self._phase_deadline()), session
                    )
            except LeaseLost:
                return _Abandoned(running.cancel_reason or LEASE_LOST)
            except JobError as exc:
                return _Failure(exc.code, permanent=exc.permanent)
            except Exception as exc:
                log.warning(
                    "job prepare hook raised job_id=%s kind=%s", job.id, job.kind, exc_info=True
                )
                return _Failure(handler_error(exc))
        else:
            child_input = job.payload
        try:
            data = encode_transport(child_input)
        except JsonRejected:
            return _Failure(JobErrorCode.INPUT_INVALID.value)
        if len(data) > MAX_TRANSPORT_BYTES:
            return _Failure(JobErrorCode.INPUT_INVALID.value)
        module, qualname = spec.target
        running.deadline = time.monotonic() + running.timeout_s
        try:
            child = run_child(
                module=module,
                qualname=qualname,
                data=data,
                timeout_s=running.timeout_s,
                cancel=running.cancel,
                terminate_grace_s=self._config.terminate_grace_s,
                log_level=self._config.log_level,
                log_format=self._config.log_format,
                name=f"cardflow-job-{job.kind}",
            )
        except OSError:  # could not even start the child (fds, memory, process limit)
            log.error(
                "job subprocess could not start job_id=%s kind=%s", job.id, job.kind, exc_info=True
            )
            return _Failure(JobErrorCode.CRASHED.value)
        if child.stopped_with is not None:
            log.warning(
                "job subprocess stopped job_id=%s kind=%s pid=%s signal=%s status=%s",
                job.id,
                job.kind,
                child.pid,
                child.stopped_with,
                child.status.value,
            )
        if child.status is ChildStatus.OK:
            return _Success(child.output)
        if child.status is ChildStatus.ERROR:
            return _Failure(child.error or JobErrorCode.HANDLER_ERROR.value, child.permanent)
        if child.status is ChildStatus.TIMEOUT:
            return _Failure(JobErrorCode.TIMEOUT.value, timeout=True)
        if child.status is ChildStatus.CRASHED:
            log.warning(
                "job subprocess exited without a result job_id=%s kind=%s exitcode=%s",
                job.id,
                job.kind,
                child.exitcode,
            )
            return _Failure(JobErrorCode.CRASHED.value)
        return _Abandoned(running.cancel_reason or LEASE_LOST)  # ChildStatus.CANCELLED

    # ------------------------------------------------------------------ finishing

    def _fenced(self, running: _Running, *, lock: LockMode) -> AbstractContextManager[Session]:
        return fenced_tx(
            self._sf,
            job_id=running.job.id,
            worker_id=self.worker_id,
            attempt=running.job.attempt,
            workspace_id=running.job.workspace_id,
            lock=lock,
            statement_timeout_ms=int(self._config.phase_timeout_s * 1000),
        )

    def _settle(self, running: _Running, outcome: _Outcome) -> None:
        if isinstance(outcome, _Success):
            self._complete(running, outcome.output)
        elif isinstance(outcome, _Failure):
            self._record_failure(running, outcome, lock="update")
        elif outcome.reason == SHUTDOWN:
            self._release(running, lock="update")
        else:
            self._end_lease(running)
            with self._lock:
                self._stats.abandoned += 1
            log.warning(
                "job attempt abandoned job_id=%s kind=%s attempt=%d reason=%s",
                running.job.id,
                running.job.kind,
                running.job.attempt,
                outcome.reason,
            )

    def _complete(self, running: _Running, output: object) -> None:
        spec = running.spec
        job = running.job
        running.finishing = True
        try:
            with self._fenced(running, lock="update") as session:
                stored = output
                if spec.persist is not None:
                    ctx = self._context(running, self._phase_deadline())
                    stored = spec.persist(ctx, session, output)
                result_json = encode_stored(stored, what="result", max_bytes=MAX_RESULT_BYTES)
                mark_succeeded(session, job.id, result_json)
        except LeaseLost:
            self._settle(running, _Abandoned(running.cancel_reason or LEASE_LOST))
            return
        except JsonRejected:
            self._record_failure(
                running, _Failure(JobErrorCode.RESULT_INVALID.value), lock="update"
            )
            return
        except JobError as exc:
            self._record_failure(running, _Failure(exc.code, exc.permanent), lock="update")
            return
        except Exception as exc:
            log.warning(
                "job persist step raised job_id=%s kind=%s", job.id, job.kind, exc_info=True
            )
            self._record_failure(running, _Failure(handler_error(exc)), lock="update")
            return
        self._end_lease(running)
        with self._lock:
            self._stats.succeeded += 1
        log.info(
            "job succeeded job_id=%s kind=%s attempt=%d duration_ms=%d",
            job.id,
            job.kind,
            job.attempt,
            (time.monotonic() - running.started) * 1000,
        )

    def _record_failure(
        self, running: _Running, failure: _Failure, *, lock: LockMode
    ) -> FailureOutcome | None:
        """Record a failed attempt; ``update_skip`` raises :class:`LeaseBusy` instead of waiting."""
        job = running.job
        running.finishing = True
        try:
            with self._fenced(running, lock=lock) as session:
                outcome = mark_failed(
                    session,
                    job_id=job.id,
                    attempts=job.attempt,
                    max_attempts=job.max_attempts,
                    error=failure.error,
                    permanent=failure.permanent,
                    backoff=self._config.backoff,
                )
        except LeaseBusy:
            running.finishing = False
            raise
        except LeaseLost:
            self._end_lease(running)
            log.info(
                "job failure not recorded, lease already gone job_id=%s kind=%s error=%s",
                job.id,
                job.kind,
                failure.error,
            )
            return None
        self._end_lease(running)
        with self._lock:
            if failure.timeout:
                running.timeout_recorded = True
                self._stats.timed_out += 1
            if outcome.status is JobStatus.QUEUED:
                self._stats.retried += 1
            elif outcome.status is JobStatus.DEAD:
                self._stats.dead += 1
            else:
                self._stats.failed += 1
        level = logging.ERROR if outcome.status is JobStatus.DEAD else logging.WARNING
        retry = "" if outcome.delay_s is None else f" delay_s={outcome.delay_s:.1f}"
        log.log(
            level,
            "job failed job_id=%s kind=%s attempt=%d/%d error=%s next=%s%s",
            job.id,
            job.kind,
            job.attempt,
            job.max_attempts,
            failure.error,
            outcome.status.value,
            retry,
        )
        return outcome

    def _release(self, running: _Running, *, lock: LockMode) -> None:
        job = running.job
        try:
            with self._fenced(running, lock=lock) as session:
                release(session, job.id)
        except LeaseBusy:
            log.warning("job row busy, left to lease expiry job_id=%s kind=%s", job.id, job.kind)
        except LeaseLost:
            pass  # finished or taken over meanwhile
        except SQLAlchemyError:
            log.warning("releasing job failed job_id=%s kind=%s", job.id, job.kind, exc_info=True)
        else:
            with self._lock:
                self._stats.released += 1
            log.warning(
                "job released on shutdown job_id=%s kind=%s attempt=%d error=%s",
                job.id,
                job.kind,
                job.attempt,
                JobErrorCode.INTERRUPTED.value,
            )
        finally:
            self._end_lease(running)

    def _end_lease(self, running: _Running) -> None:
        with self._lock:
            running.leased = False

    def _cancel(self, running: _Running, reason: str) -> None:
        with self._lock:
            if running.cancel_reason is None:
                running.cancel_reason = reason
            if reason == LEASE_LOST:
                running.leased = False
        running.cancel.set()

    # ------------------------------------------------------------------ timeouts, heartbeat

    def _enforce_inline_timeouts(self) -> None:
        now = time.monotonic()
        with self._lock:
            overdue = [
                running
                for running in self._running.values()
                if running.spec.mode is Mode.INLINE
                and running.leased
                and not running.timeout_recorded
                and running.deadline is not None
                and now >= running.deadline
            ]
        for running in overdue:
            self._cancel(running, TIMEOUT)
            if running.cancel_reason != TIMEOUT:
                continue
            try:
                self._record_failure(
                    running,
                    _Failure(JobErrorCode.TIMEOUT.value, timeout=True),
                    lock="update_skip",
                )
            except LeaseBusy:
                continue  # the handler is inside a transaction; statement_timeout ends it
            except SQLAlchemyError:
                log.warning("recording an inline timeout failed", exc_info=True)

    def _heartbeat_loop(self) -> None:
        while not self._heartbeat_stop.wait(self._config.heartbeat_interval_s):
            try:
                self._heartbeat_once()
            except Exception:
                log.error("worker heartbeat crashed", exc_info=True)

    def _heartbeat_once(self) -> None:
        with self._lock:
            leased = [running for running in self._running.values() if running.leased]
        now = time.monotonic()
        try:
            with self._sf.begin() as session:
                session.execute(_SET_LOCK_TIMEOUT, {"value": str(HEARTBEAT_LOCK_TIMEOUT_MS)})
                renewal = renew_leases(
                    session,
                    worker_id=self.worker_id,
                    leases=[(running.job.id, running.job.attempt) for running in leased],
                    lease_s=self._config.lease_s,
                )
                upsert_heartbeat(session, self._identity, running_jobs=len(renewal.held))
        except SQLAlchemyError:
            log.warning("worker heartbeat failed", exc_info=True)
            for running in leased:
                if now - running.last_renewed >= self._config.lease_s:
                    self._lose(running)
            return
        for running in leased:
            if running.job.id in renewal.renewed:
                running.last_renewed = now
            elif running.job.id not in renewal.busy and not running.finishing:
                self._lose(running)

    def _lose(self, running: _Running) -> None:
        with self._lock:
            if not running.leased:
                return
        log.warning(
            "job lease lost job_id=%s kind=%s attempt=%d",
            running.job.id,
            running.job.kind,
            running.job.attempt,
        )
        self._cancel(running, LEASE_LOST)


def serve(
    settings: "Settings",
    *,
    concurrency: int,
    once: bool,
    shutdown_timeout_s: float,
    registry: Registry | None = None,
) -> int:
    """``cardflow worker``: run a :class:`Worker` with SIGTERM/SIGINT handling; exit code."""
    engine = create_engine(
        database_url_from_settings(settings), application_name=WORKER_APPLICATION_NAME
    )
    restore: Callable[[], None] | None = None
    try:
        worker = Worker(
            create_session_factory(engine),
            registry if registry is not None else production_registry(),
            WorkerConfig(
                concurrency=concurrency,
                shutdown_timeout_s=shutdown_timeout_s,
                version=settings.cardflow_version,
                log_level=settings.log_level,
                log_format=settings.log_format,
            ),
        )
        restore = worker.install_signal_handlers()
        worker.run(once=once)
    except WorkerStartupError:
        return EXIT_FAILED
    except Exception:
        # Never let Python print the traceback: exception messages (SQL parameters,
        # library errors) may quote data. The log formatter keeps type and frames only.
        log.critical("worker crashed", exc_info=True)
        return EXIT_FAILED
    finally:
        if restore is not None:
            restore()
        engine.dispose()
    return EXIT_OK
