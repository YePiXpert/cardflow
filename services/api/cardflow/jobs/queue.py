"""SQL layer of the job queue: enqueue, status view, claim, lease, finish, reclaim.

Lifecycle of a ``jobs`` row (ADR-003, data-model §3)::

    queued --claim--> running --success--> succeeded
                         |----failure, attempts < max_attempts--> queued (run_after = backoff)
                         |----failure, attempts >= max_attempts--> dead
                         |----JobError(permanent=True)----------> failed
                         |----lease expired (worker gone)-------> queued / dead  (reclaim)
                         '----worker shutdown, not finished-----> queued (attempt not counted)

A lease is identified by ``(id, locked_by, attempts)``: the worker id plus the attempt
number act as a fencing token, so a stale attempt (reclaimed, timed out, released) can never
write to the row again, even when the same worker has re-claimed the job meanwhile.

Row locks: handler transactions hold ``FOR KEY SHARE`` on their job row
(:func:`lock_lease` mode ``share``). That does not block lease renewals (``UPDATE`` of
non-key columns), but it does block the ``FOR UPDATE`` taken by every transition that
takes the job away from an attempt (reclaim, timeout, shutdown release), which therefore
use ``SKIP LOCKED`` and simply retry later. So a handler transaction that verified its lease
commits before anyone else can take the job over.

All timestamps come from the database clock (``now()``).
"""

import uuid
from collections.abc import Collection, Mapping
from dataclasses import dataclass
from datetime import datetime
from enum import Enum, StrEnum
from typing import Final, Literal

from sqlalchemy import text
from sqlalchemy.engine import Connection
from sqlalchemy.orm import Session, sessionmaker

from cardflow.jobs.backoff import Backoff
from cardflow.jobs.codec import MAX_PAYLOAD_BYTES, JsonValue, encode_stored
from cardflow.jobs.errors import JobErrorCode
from cardflow.jobs.registry import MAX_TIMEOUT_S, Registry, check_kind, production_registry

type Executor = Session | Connection


class JobStatus(StrEnum):
    """Values of ``jobs.status`` (api-contract §1)."""

    QUEUED = "queued"
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    DEAD = "dead"


FINISHED_STATUSES: Final = frozenset({JobStatus.SUCCEEDED, JobStatus.FAILED, JobStatus.DEAD})

# --------------------------------------------------------------------------- enqueue / view

_INSERT: Final = text(
    """
    INSERT INTO jobs (kind, payload, status, run_after, max_attempts, timeout_s, workspace_id)
    VALUES (:kind, CAST(:payload AS jsonb), 'queued',
            COALESCE(CAST(:run_after AS timestamptz), now()),
            :max_attempts, :timeout_s, :workspace_id)
    RETURNING id
    """
)


def enqueue(
    session: Executor,
    kind: str,
    payload: JsonValue,
    *,
    workspace_id: uuid.UUID | None,
    run_after: datetime | None = None,
    max_attempts: int | None = None,
    timeout_s: int | None = None,
    registry: Registry | None = None,
) -> uuid.UUID:
    """Insert a ``queued`` job in the caller's transaction and return its id.

    Nothing is committed: call it inside the transaction that writes the business rows
    the job belongs to (e.g. within ``workspace_tx``), so both commit or roll back together
    (ADR-003). ``kind`` must be registered (``registry``, default: the production registry).
    ``payload`` must be storable JSON -- integers, strings, booleans, null, lists, objects;
    floats are rejected (money is integer minor units). Keep it to identifiers and options.

    ``workspace_id``: owner of the job (``None`` for system jobs). ``run_after``: earliest
    start (timezone-aware; default now). ``max_attempts``: default from the handler spec.
    ``timeout_s``: per-job override of the handler's timeout (e.g. solver time limit + 5 s);
    ``None`` stores NULL = "the kind's default at run time".
    """
    check_kind(kind)
    spec = (registry if registry is not None else production_registry()).get(kind)
    if spec is None:
        raise ValueError(f"job kind {kind!r} is not registered")
    if workspace_id is not None and not isinstance(workspace_id, uuid.UUID):
        raise TypeError("workspace_id must be uuid.UUID or None")
    if run_after is not None and (
        not isinstance(run_after, datetime) or run_after.utcoffset() is None
    ):
        raise ValueError("run_after must be a timezone-aware datetime")
    attempts = spec.max_attempts if max_attempts is None else max_attempts
    if isinstance(attempts, bool) or not isinstance(attempts, int) or attempts < 1:
        raise ValueError("max_attempts must be an integer >= 1")
    if timeout_s is not None and (
        isinstance(timeout_s, bool)
        or not isinstance(timeout_s, int)
        or not 1 <= timeout_s <= MAX_TIMEOUT_S
    ):
        raise ValueError(f"timeout_s must be an integer in [1, {MAX_TIMEOUT_S}]")
    payload_json = encode_stored(payload, what="payload", max_bytes=MAX_PAYLOAD_BYTES)
    return session.execute(
        _INSERT,
        {
            "kind": kind,
            "payload": payload_json,
            "run_after": run_after,
            "max_attempts": attempts,
            "timeout_s": timeout_s,
            "workspace_id": workspace_id,
        },
    ).scalar_one()


_UNIQUE_LOCK: Final = text("SELECT pg_advisory_xact_lock(hashtextextended(:key, 0))")
_PENDING_OF_KIND: Final = text(
    """
    SELECT 1 FROM jobs
    WHERE kind = :kind AND status IN ('queued', 'running')
      AND workspace_id IS NOT DISTINCT FROM :workspace_id
    LIMIT 1
    """
)


def enqueue_unique(
    session: Executor,
    kind: str,
    payload: JsonValue,
    *,
    workspace_id: uuid.UUID | None,
    registry: Registry | None = None,
) -> uuid.UUID | None:
    """Enqueue ``kind`` unless a queued/running job of it (same workspace) already exists.

    For periodic triggers: every worker's scheduler may fire at the same time, and a
    transaction-scoped advisory lock per kind makes the check-then-insert atomic across
    them. Returns the new id, or ``None`` when one was already pending.
    """
    check_kind(kind)
    session.execute(_UNIQUE_LOCK, {"key": f"cardflow.jobs.unique:{kind}"})
    pending = session.execute(
        _PENDING_OF_KIND, {"kind": kind, "workspace_id": workspace_id}
    ).first()
    if pending is not None:
        return None
    return enqueue(session, kind, payload, workspace_id=workspace_id, registry=registry)


@dataclass(frozen=True, slots=True)
class JobView:
    """Status of a job for ``GET /v1/jobs/{id}`` and AP-05 (no payload: metadata only)."""

    id: uuid.UUID
    kind: str
    status: JobStatus
    workspace_id: uuid.UUID | None
    attempts: int
    max_attempts: int
    run_after: datetime
    """Earliest next start; for a queued job with ``attempts > 0`` the next retry time."""
    created_at: datetime
    updated_at: datetime
    finished_at: datetime | None
    last_error: str | None
    """``CODE`` or ``CODE:ExceptionType`` of the latest failed attempt (kept after success)."""
    result: JsonValue | None

    @property
    def error_code(self) -> str | None:
        """The code part of :attr:`last_error` (AP-05 lists it in its own column)."""
        return None if self.last_error is None else self.last_error.partition(":")[0]

    @property
    def finished(self) -> bool:
        """True for ``succeeded``, ``failed`` and ``dead``."""
        return self.status in FINISHED_STATUSES


_GET_JOB: Final = text(
    """
    SELECT id, kind, status, workspace_id, attempts, max_attempts, run_after, created_at,
           updated_at, finished_at, last_error, result
    FROM jobs
    WHERE id = :id AND (CAST(:any_workspace AS boolean) OR workspace_id = :workspace_id)
    """
)


def get_job(
    session: Executor, job_id: uuid.UUID, *, workspace_id: uuid.UUID | None
) -> JobView | None:
    """Status view of ``job_id``, or ``None`` if it does not exist.

    ``workspace_id`` is required on purpose: API code passes the caller's workspace and gets
    ``None`` for another workspace's job (and for system jobs); ``workspace_id=None`` means
    "any workspace" and is for system/admin code only.
    """
    row = session.execute(
        _GET_JOB,
        {"id": job_id, "any_workspace": workspace_id is None, "workspace_id": workspace_id},
    ).first()
    if row is None:
        return None
    return JobView(
        id=row.id,
        kind=row.kind,
        status=JobStatus(row.status),
        workspace_id=row.workspace_id,
        attempts=row.attempts,
        max_attempts=row.max_attempts,
        run_after=row.run_after,
        created_at=row.created_at,
        updated_at=row.updated_at,
        finished_at=row.finished_at,
        last_error=row.last_error,
        result=row.result,
    )


# --------------------------------------------------------------------------- claim / lease


@dataclass(frozen=True, slots=True)
class ClaimedJob:
    """A job this worker has just leased (``attempt`` = ``jobs.attempts`` after the claim)."""

    id: uuid.UUID
    kind: str
    payload: JsonValue
    attempt: int
    max_attempts: int
    timeout_s: int | None
    workspace_id: uuid.UUID | None


_SELECT_CLAIMABLE: Final = text(
    """
    SELECT id, kind FROM jobs
    WHERE status = 'queued' AND run_after <= now() AND kind = ANY(:kinds)
    ORDER BY run_after, created_at
    LIMIT :limit
    FOR UPDATE SKIP LOCKED
    """
)
_MARK_RUNNING: Final = text(
    """
    UPDATE jobs
    SET status = 'running', attempts = attempts + 1, locked_by = :worker_id,
        locked_until = now() + make_interval(secs => :lease_s), heartbeat_at = now(),
        updated_at = now()
    WHERE id = ANY(:ids)
    RETURNING id, kind, payload, attempts, max_attempts, timeout_s, workspace_id
    """
)


def claim_jobs(
    session_factory: sessionmaker[Session],
    *,
    worker_id: str,
    slots: Mapping[str, int | None],
    limit: int,
    lease_s: float,
) -> list[ClaimedJob]:
    """Lease up to ``limit`` due jobs in one short transaction and commit at once.

    ``slots`` maps each kind this worker may take now to its remaining per-kind capacity
    (``None``: no per-kind limit). Candidates are locked with ``FOR UPDATE SKIP LOCKED``
    (other workers skip them instead of waiting), filtered by the per-kind capacity in
    queue order, and marked ``running`` with ``attempts + 1``, ``locked_by``,
    ``locked_until = now() + lease`` and ``heartbeat_at``. Candidates that do not fit are
    left untouched and are unlocked by the commit.
    """
    kinds = [kind for kind, free in slots.items() if free is None or free > 0]
    if limit < 1 or not kinds:
        return []
    with session_factory.begin() as session:
        candidates = session.execute(_SELECT_CLAIMABLE, {"kinds": kinds, "limit": limit}).all()
        remaining = dict(slots)
        chosen: list[uuid.UUID] = []
        for job_id, kind in candidates:
            free = remaining.get(kind)
            if free is not None:
                if free <= 0:
                    continue
                remaining[kind] = free - 1
            chosen.append(job_id)
        if not chosen:
            return []
        rows = session.execute(
            _MARK_RUNNING, {"ids": chosen, "worker_id": worker_id, "lease_s": lease_s}
        ).all()
    order = {job_id: index for index, job_id in enumerate(chosen)}
    claimed = [
        ClaimedJob(
            id=row.id,
            kind=row.kind,
            payload=row.payload,
            attempt=row.attempts,
            max_attempts=row.max_attempts,
            timeout_s=row.timeout_s,
            workspace_id=row.workspace_id,
        )
        for row in rows
    ]
    return sorted(claimed, key=lambda job: order[job.id])


_LEASES_SELECT: Final = """
    SELECT j.id FROM jobs AS j
    JOIN unnest(CAST(:ids AS uuid[]), CAST(:attempts AS integer[])) AS lease(id, attempt)
      ON j.id = lease.id AND j.attempts = lease.attempt
    WHERE j.status = 'running' AND j.locked_by = :worker_id
"""
_LOCK_RENEWABLE: Final = text(f"{_LEASES_SELECT} FOR NO KEY UPDATE OF j SKIP LOCKED")
_STILL_OWNED: Final = text(_LEASES_SELECT)
_RENEW: Final = text(
    """
    UPDATE jobs
    SET locked_until = now() + make_interval(secs => :lease_s), heartbeat_at = now(),
        updated_at = now()
    WHERE id = ANY(:ids)
    """
)


@dataclass(frozen=True, slots=True)
class LeaseRenewal:
    """Result of :func:`renew_leases`."""

    renewed: frozenset[uuid.UUID]
    busy: frozenset[uuid.UUID]
    """Still ours but not renewed this time: another transaction holds the row (for example
    this worker finishing the job, or a reclaim looking at it)."""

    @property
    def held(self) -> frozenset[uuid.UUID]:
        """Every lease that is still ours."""
        return self.renewed | self.busy


def renew_leases(
    session: Session, *, worker_id: str, leases: Collection[tuple[uuid.UUID, int]], lease_s: float
) -> LeaseRenewal:
    """Extend ``locked_until``/``heartbeat_at`` of the given ``(id, attempt)`` leases.

    Rows locked ``FOR UPDATE`` by another transaction are skipped rather than waited for,
    so one slow transaction cannot hold up the renewal of every other lease; handler
    transactions (``FOR KEY SHARE``) do not conflict. A lease in neither
    :attr:`LeaseRenewal.renewed` nor :attr:`LeaseRenewal.busy` is lost (reclaimed after it
    expired, or ended by a timeout/shutdown transition).
    """
    if not leases:
        return LeaseRenewal(frozenset(), frozenset())
    params = {
        "ids": [job_id for job_id, _ in leases],
        "attempts": [attempt for _, attempt in leases],
        "worker_id": worker_id,
    }
    locked = list(session.execute(_LOCK_RENEWABLE, params).scalars())
    if locked:
        session.execute(_RENEW, {"ids": locked, "lease_s": lease_s})
    owned = set(session.execute(_STILL_OWNED, params).scalars())
    renewed = frozenset(locked)
    return LeaseRenewal(renewed, frozenset(owned - renewed))


class LeaseState(Enum):
    """Result of :func:`lock_lease`."""

    HELD = "held"
    """The row is locked by this transaction and the lease is ours."""
    BUSY = "busy"
    """The lease is ours, but another transaction holds a conflicting row lock (skip mode)."""
    GONE = "gone"
    """The lease is no longer ours."""


_LEASE_PREDICATE: Final = (
    "id = :id AND status = 'running' AND locked_by = :worker_id AND attempts = :attempt"
)
_LOCK_SQL: Final = {
    "share": text(f"SELECT 1 FROM jobs WHERE {_LEASE_PREDICATE} FOR KEY SHARE"),  # noqa: S608
    "update": text(f"SELECT 1 FROM jobs WHERE {_LEASE_PREDICATE} FOR UPDATE"),  # noqa: S608
    "update_skip": text(
        f"SELECT 1 FROM jobs WHERE {_LEASE_PREDICATE} FOR UPDATE SKIP LOCKED"  # noqa: S608
    ),
}
_LEASE_OWNED: Final = text(f"SELECT 1 FROM jobs WHERE {_LEASE_PREDICATE}")  # noqa: S608

type LockMode = Literal["share", "update", "update_skip"]


def lock_lease(
    session: Session, *, job_id: uuid.UUID, worker_id: str, attempt: int, mode: LockMode
) -> LeaseState:
    """Lock the job row for this transaction if ``(worker_id, attempt)`` still holds it.

    ``share`` (handler transactions) and ``update`` (finishing the job) wait for
    conflicting locks; ``update_skip`` does not wait and reports :attr:`LeaseState.BUSY`.
    """
    params = {"id": job_id, "worker_id": worker_id, "attempt": attempt}
    if session.execute(_LOCK_SQL[mode], params).first() is not None:
        return LeaseState.HELD
    if mode == "update_skip" and session.execute(_LEASE_OWNED, params).first() is not None:
        return LeaseState.BUSY
    return LeaseState.GONE


# --------------------------------------------------------------------------- finish

_SUCCEED: Final = text(
    """
    UPDATE jobs
    SET status = 'succeeded', result = CAST(:result AS jsonb), finished_at = now(),
        locked_by = NULL, locked_until = NULL, heartbeat_at = NULL, updated_at = now()
    WHERE id = :id
    """
)
_RETRY: Final = text(
    """
    UPDATE jobs
    SET status = 'queued', run_after = now() + make_interval(secs => :delay_s),
        last_error = :error, locked_by = NULL, locked_until = NULL, heartbeat_at = NULL,
        updated_at = now()
    WHERE id = :id
    """
)
_END: Final = text(
    """
    UPDATE jobs
    SET status = :status, last_error = :error, finished_at = now(),
        locked_by = NULL, locked_until = NULL, heartbeat_at = NULL, updated_at = now()
    WHERE id = :id
    """
)
_RELEASE: Final = text(
    """
    UPDATE jobs
    SET status = 'queued', attempts = attempts - 1, run_after = now(), last_error = :error,
        locked_by = NULL, locked_until = NULL, heartbeat_at = NULL, updated_at = now()
    WHERE id = :id AND attempts > 0
    """
)


def mark_succeeded(session: Session, job_id: uuid.UUID, result_json: str) -> None:
    """``succeeded`` with ``result`` (already validated JSON text); lease must be locked."""
    session.execute(_SUCCEED, {"id": job_id, "result": result_json})


@dataclass(frozen=True, slots=True)
class FailureOutcome:
    """What a failed attempt led to."""

    status: JobStatus
    """``queued`` (retry), ``dead`` (attempts exhausted) or ``failed`` (permanent)."""
    delay_s: float | None
    """Backoff before the retry (``queued`` only)."""


def mark_failed(
    session: Session,
    *,
    job_id: uuid.UUID,
    attempts: int,
    max_attempts: int,
    error: str,
    permanent: bool,
    backoff: Backoff,
) -> FailureOutcome:
    """Record a failed attempt on a locked row: retry with backoff, ``dead`` or ``failed``.

    ``error`` must already be a safe error text (:func:`cardflow.jobs.errors.error_text`).
    """
    if permanent:
        session.execute(_END, {"id": job_id, "status": JobStatus.FAILED.value, "error": error})
        return FailureOutcome(JobStatus.FAILED, None)
    if attempts >= max_attempts:
        session.execute(_END, {"id": job_id, "status": JobStatus.DEAD.value, "error": error})
        return FailureOutcome(JobStatus.DEAD, None)
    delay = backoff.delay_s(attempts)
    session.execute(_RETRY, {"id": job_id, "delay_s": delay, "error": error})
    return FailureOutcome(JobStatus.QUEUED, delay)


def release(session: Session, job_id: uuid.UUID) -> None:
    """Shutdown: give a locked, unfinished job back to the queue without counting the attempt."""
    session.execute(_RELEASE, {"id": job_id, "error": JobErrorCode.INTERRUPTED.value})


# --------------------------------------------------------------------------- reclaim

_SELECT_EXPIRED: Final = text(
    """
    SELECT id, kind, attempts, max_attempts FROM jobs
    WHERE status = 'running' AND locked_until < now()
    ORDER BY locked_until
    LIMIT :limit
    FOR UPDATE SKIP LOCKED
    """
)


@dataclass(frozen=True, slots=True)
class ReclaimedJob:
    """A job taken back from a worker that stopped renewing its lease."""

    id: uuid.UUID
    kind: str
    attempts: int
    outcome: FailureOutcome


def reclaim_expired(
    session_factory: sessionmaker[Session], *, backoff: Backoff, limit: int = 100
) -> list[ReclaimedJob]:
    """Requeue (or move to ``dead``) running jobs whose lease has expired.

    Such a job was left behind by a crashed or partitioned worker; the attempt it was on
    counts as failed (``LEASE_EXPIRED``), so a job that keeps crashing workers ends in
    ``dead`` after ``max_attempts``. ``SKIP LOCKED`` lets several workers run this at the
    same time and skips rows a live handler transaction still holds.
    """
    reclaimed: list[ReclaimedJob] = []
    with session_factory.begin() as session:
        rows = session.execute(_SELECT_EXPIRED, {"limit": limit}).all()
        for row in rows:
            outcome = mark_failed(
                session,
                job_id=row.id,
                attempts=row.attempts,
                max_attempts=row.max_attempts,
                error=JobErrorCode.LEASE_EXPIRED.value,
                permanent=False,
                backoff=backoff,
            )
            reclaimed.append(ReclaimedJob(row.id, row.kind, row.attempts, outcome))
    return reclaimed


# --------------------------------------------------------------------------- worker heartbeats

_UPSERT_HEARTBEAT: Final = text(
    """
    INSERT INTO worker_heartbeats
        (worker_id, hostname, pid, version, started_at, last_seen_at, running_jobs)
    VALUES (:worker_id, :hostname, :pid, :version, :started_at, now(), :running_jobs)
    ON CONFLICT (worker_id) DO UPDATE
    SET last_seen_at = now(), running_jobs = EXCLUDED.running_jobs
    """
)
_DELETE_HEARTBEAT: Final = text("DELETE FROM worker_heartbeats WHERE worker_id = :worker_id")
_PURGE_HEARTBEATS: Final = text(
    """
    DELETE FROM worker_heartbeats
    WHERE last_seen_at < now() - make_interval(secs => :max_age_s)
    """
)


@dataclass(frozen=True, slots=True)
class WorkerIdentity:
    """What a worker writes into ``worker_heartbeats``."""

    worker_id: str
    hostname: str
    pid: int
    version: str
    started_at: datetime


def upsert_heartbeat(session: Session, identity: WorkerIdentity, *, running_jobs: int) -> None:
    """Create or refresh this worker's ``worker_heartbeats`` row (``last_seen_at = now()``)."""
    session.execute(
        _UPSERT_HEARTBEAT,
        {
            "worker_id": identity.worker_id,
            "hostname": identity.hostname,
            "pid": identity.pid,
            "version": identity.version,
            "started_at": identity.started_at,
            "running_jobs": running_jobs,
        },
    )


def delete_heartbeat(session: Session, worker_id: str) -> None:
    """Remove this worker's row on a clean shutdown (``/readyz`` then sees no live worker)."""
    session.execute(_DELETE_HEARTBEAT, {"worker_id": worker_id})


def purge_heartbeats(session: Session, *, max_age_s: float) -> int:
    """Delete heartbeat rows not refreshed for ``max_age_s`` seconds; returns the count."""
    return session.execute(_PURGE_HEARTBEATS, {"max_age_s": max_age_s}).rowcount
