"""Periodic tasks inside the worker (apscheduler 3.x, ADR-003).

Every worker process runs a ``BackgroundScheduler`` (UTC, in-memory job store) with the
system tasks below. Each task must be safe to run concurrently in several workers:

* ``system.reclaim_leases`` -- requeue or bury jobs whose lease expired
  (:func:`cardflow.jobs.queue.reclaim_expired`, ``FOR UPDATE SKIP LOCKED``);
* ``system.purge_heartbeats`` -- delete ``worker_heartbeats`` rows of workers that stopped
  long ago (idempotent ``DELETE``).

Business periodic tasks are not implemented here. Per ADR-003 they should *enqueue* a job
rather than do the work on the scheduler thread; :func:`enqueue_periodic` builds such a task
on top of :func:`cardflow.jobs.queue.enqueue_unique`, which coalesces the simultaneous
firings of several workers into one pending job.

Task failures are logged with the exception type only and never stop the scheduler;
apscheduler's own INFO lines (job added, job run) are muted: its loggers are
``cardflow.jobs.scheduler`` and ``cardflow.jobs.scheduler.runs``, capped at WARNING.
"""

import logging
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Final

from apscheduler.executors.pool import ThreadPoolExecutor
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.interval import IntervalTrigger
from sqlalchemy.orm import Session, sessionmaker

from cardflow.jobs.backoff import Backoff
from cardflow.jobs.codec import JsonValue
from cardflow.jobs.errors import JobErrorCode
from cardflow.jobs.queue import enqueue_unique, purge_heartbeats, reclaim_expired
from cardflow.jobs.registry import Registry

log = logging.getLogger("cardflow.jobs.periodic")
_scheduler_log = logging.getLogger("cardflow.jobs.scheduler")
_runs_log = logging.getLogger("cardflow.jobs.scheduler.runs")

RECLAIM_TASK: Final = "system.reclaim_leases"
PURGE_HEARTBEATS_TASK: Final = "system.purge_heartbeats"
SCHEDULER_THREADS: Final = 2


@dataclass(frozen=True, slots=True)
class PeriodicContext:
    """What a periodic task gets."""

    session_factory: sessionmaker[Session]
    worker_id: str
    backoff: Backoff
    heartbeat_max_age_s: float


@dataclass(frozen=True, slots=True)
class PeriodicTask:
    """``func(ctx)`` right after the scheduler starts, then every ``interval_s`` seconds."""

    name: str
    interval_s: float
    func: Callable[[PeriodicContext], None]
    jitter_s: float = 0.0


def reclaim_task(ctx: PeriodicContext) -> None:
    """System task: take back jobs whose worker stopped renewing the lease."""
    reclaimed = reclaim_expired(ctx.session_factory, backoff=ctx.backoff)
    for job in reclaimed:
        log.warning(
            "reclaimed expired lease job_id=%s kind=%s attempts=%d error=%s next=%s",
            job.id,
            job.kind,
            job.attempts,
            JobErrorCode.LEASE_EXPIRED.value,
            job.outcome.status.value,
        )


def purge_heartbeats_task(ctx: PeriodicContext) -> None:
    """System task: drop heartbeat rows not refreshed for ``heartbeat_max_age_s``."""
    with ctx.session_factory.begin() as session:
        removed = purge_heartbeats(session, max_age_s=ctx.heartbeat_max_age_s)
    if removed:
        log.info("purged stale worker heartbeats rows=%d", removed)


def system_tasks(*, reclaim_interval_s: float, purge_interval_s: float) -> tuple[PeriodicTask, ...]:
    """The two system tasks every worker runs."""
    return (
        PeriodicTask(RECLAIM_TASK, reclaim_interval_s, reclaim_task, jitter_s=0.0),
        PeriodicTask(PURGE_HEARTBEATS_TASK, purge_interval_s, purge_heartbeats_task),
    )


def enqueue_periodic(
    name: str,
    interval_s: float,
    kind: str,
    payload: JsonValue,
    *,
    registry: Registry | None = None,
) -> PeriodicTask:
    """A periodic task that enqueues one ``kind`` job per period (unless one is pending)."""

    def func(ctx: PeriodicContext) -> None:
        with ctx.session_factory.begin() as session:
            job_id = enqueue_unique(session, kind, payload, workspace_id=None, registry=registry)
        if job_id is not None:
            log.info("periodic task enqueued name=%s kind=%s job_id=%s", name, kind, job_id)

    return PeriodicTask(name, interval_s, func)


def run_task(task: PeriodicTask, ctx: PeriodicContext) -> bool:
    """Run ``task`` once; log (type only) and swallow failures. True on success."""
    try:
        task.func(ctx)
    except Exception:
        log.warning("periodic task failed name=%s", task.name, exc_info=True)
        return False
    return True


class _QuietThreadPool(ThreadPoolExecutor):
    """apscheduler thread pool whose per-run log lines go to a muted cardflow logger."""

    def start(self, scheduler: object, alias: str) -> None:
        super().start(scheduler, alias)
        self._logger = _runs_log


class PeriodicScheduler:
    """apscheduler wrapper running :class:`PeriodicTask` objects on background threads."""

    def __init__(self, tasks: Sequence[PeriodicTask], ctx: PeriodicContext) -> None:
        """Prepare (not start) a scheduler for ``tasks``."""
        names = [task.name for task in tasks]
        if len(set(names)) != len(names):
            raise ValueError("periodic task names must be unique")
        self._tasks = tuple(tasks)
        self._ctx = ctx
        _scheduler_log.setLevel(logging.WARNING)
        _runs_log.setLevel(logging.WARNING)
        self._scheduler = BackgroundScheduler(
            timezone=UTC,
            logger=_scheduler_log,
            executors={"default": _QuietThreadPool(max_workers=SCHEDULER_THREADS)},
            job_defaults={"coalesce": True, "max_instances": 1, "misfire_grace_time": None},
        )

    @property
    def tasks(self) -> tuple[PeriodicTask, ...]:
        """The scheduled tasks."""
        return self._tasks

    def start(self) -> None:
        """Start the scheduler thread; every task runs once right away, then periodically."""
        for task in self._tasks:
            self._scheduler.add_job(
                run_task,
                IntervalTrigger(
                    seconds=task.interval_s, jitter=task.jitter_s or None, timezone=UTC
                ),
                args=(task, self._ctx),
                id=task.name,
                name=task.name,
                next_run_time=datetime.now(UTC),
            )
        self._scheduler.start()
        log.info(
            "periodic tasks scheduled %s",
            " ".join(f"{task.name}={task.interval_s:g}s" for task in self._tasks),
        )

    def shutdown(self) -> None:
        """Stop scheduling and wait for running tasks to finish."""
        if self._scheduler.running:
            self._scheduler.shutdown(wait=True)

    def run_all_once(self) -> None:
        """Run every task once on the calling thread (``cardflow worker --once``)."""
        for task in self._tasks:
            run_task(task, self._ctx)
