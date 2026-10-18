"""PostgreSQL-backed job queue (``FOR UPDATE SKIP LOCKED``) and the worker (ADR-003).

Enqueue in the same transaction as the business write it belongs to::

    from cardflow.jobs import enqueue

    with workspace_tx(session_factory, workspace_id) as session:
        plan_run = ...  # business rows
        job_id = enqueue(session, "plan.solve", {"plan_id": str(plan_id)},
                         workspace_id=workspace_id, timeout_s=time_limit_s + 5)

Poll with :func:`get_job` (``GET /v1/jobs/{id}``). Handlers are registered with
:func:`register` (see :mod:`cardflow.jobs.registry`); ``cardflow worker``
(:mod:`cardflow.jobs.worker`) runs them. This package's top level stays light (no worker,
apscheduler or multiprocessing imports) so the API process can import it.
"""

from cardflow.jobs.backoff import Backoff
from cardflow.jobs.codec import JsonRejected, JsonValue
from cardflow.jobs.context import JobContext
from cardflow.jobs.errors import JobError, JobErrorCode, JobTimeout, LeaseLost
from cardflow.jobs.queue import JobStatus, JobView, enqueue, enqueue_unique, get_job
from cardflow.jobs.registry import (
    REGISTRY,
    HandlerSpec,
    Mode,
    Registry,
    production_registry,
    register,
)

__all__ = [
    "REGISTRY",
    "Backoff",
    "HandlerSpec",
    "JobContext",
    "JobError",
    "JobErrorCode",
    "JobStatus",
    "JobTimeout",
    "JobView",
    "JsonRejected",
    "JsonValue",
    "LeaseLost",
    "Mode",
    "Registry",
    "enqueue",
    "enqueue_unique",
    "get_job",
    "production_registry",
    "register",
]
