"""Queue SQL on real PostgreSQL: enqueue atomicity, claim, lease fencing, failures, reclaim."""

import threading
import time
import uuid
from datetime import UTC, datetime, timedelta

import pytest
from jobs_helpers import TEST_BACKOFF, JobsHelper
from sqlalchemy import text
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session

from cardflow.db import workspace_tx
from cardflow.jobs import JobStatus, JsonRejected, enqueue, enqueue_unique, get_job
from cardflow.jobs.backoff import Backoff
from cardflow.jobs.queue import (
    LeaseState,
    WorkerIdentity,
    claim_jobs,
    delete_heartbeat,
    lock_lease,
    mark_failed,
    purge_heartbeats,
    reclaim_expired,
    release,
    renew_leases,
    upsert_heartbeat,
)

pytestmark = pytest.mark.db

ALL_TEST_KINDS = {"test.noop": None, "test.track": None, "test.limited": 1}


def new_workspace(session: Session) -> uuid.UUID:
    """Insert a user and a workspace (real business rows) and return the workspace id."""
    user_id = session.execute(text("INSERT INTO users DEFAULT VALUES RETURNING id")).scalar_one()
    return session.execute(
        text("INSERT INTO workspaces (owner_user_id, kind) VALUES (:u, 'real') RETURNING id"),
        {"u": user_id},
    ).scalar_one()


def count(engine: Engine, sql: str, **params: object) -> int:
    with engine.connect() as connection:
        return connection.execute(text(sql), params).scalar_one()


def claim(
    jobs: JobsHelper, worker_id: str = "w-test", limit: int = 10, lease_s: float = 30.0
) -> list[uuid.UUID]:
    claimed = claim_jobs(
        jobs.session_factory,
        worker_id=worker_id,
        slots=dict.fromkeys(jobs.registry.kinds()),
        limit=limit,
        lease_s=lease_s,
    )
    return [job.id for job in claimed]


# --------------------------------------------------------------------------- enqueue


def test_enqueue_commits_together_with_the_business_write(jobs: JobsHelper) -> None:
    with jobs.session_factory.begin() as session:
        workspace_id = new_workspace(session)
        job_id = enqueue(
            session, "test.noop", {"n": 1}, workspace_id=workspace_id, registry=jobs.registry
        )

    row = jobs.row(job_id)
    assert row.workspace_id == workspace_id
    assert (
        count(jobs.engine, "SELECT count(*) FROM workspaces WHERE id = :id", id=workspace_id) == 1
    )


def test_enqueue_rolls_back_together_with_the_business_write(jobs: JobsHelper) -> None:
    """ADR-003: a job enqueued in a transaction that rolls back does not exist."""
    session = jobs.session_factory()
    try:
        session.begin()
        workspace_id = new_workspace(session)
        job_id = enqueue(
            session, "test.noop", {"n": 1}, workspace_id=workspace_id, registry=jobs.registry
        )
        assert count(jobs.engine, "SELECT count(*) FROM jobs WHERE id = :id", id=job_id) == 0
        session.rollback()
    finally:
        session.close()

    assert count(jobs.engine, "SELECT count(*) FROM jobs WHERE id = :id", id=job_id) == 0
    assert (
        count(jobs.engine, "SELECT count(*) FROM workspaces WHERE id = :id", id=workspace_id) == 0
    )
    with jobs.session_factory() as session:
        assert get_job(session, job_id, workspace_id=None) is None


class ProbeError(Exception):
    """Raised inside a workspace transaction to force a rollback."""


def test_enqueue_inside_workspace_tx_rolls_back_on_error(jobs: JobsHelper) -> None:
    with jobs.session_factory.begin() as session:
        workspace_id = new_workspace(session)
    job_ids: list[uuid.UUID] = []

    def enqueue_then_fail() -> None:
        with workspace_tx(jobs.session_factory, workspace_id) as session:
            job_ids.append(
                enqueue(session, "test.noop", {}, workspace_id=workspace_id, registry=jobs.registry)
            )
            raise ProbeError

    with pytest.raises(ProbeError):
        enqueue_then_fail()

    assert count(jobs.engine, "SELECT count(*) FROM jobs WHERE id = :id", id=job_ids[0]) == 0


def test_enqueue_rejects_float_payload_and_writes_nothing(jobs: JobsHelper) -> None:
    with jobs.session_factory.begin() as session:
        with pytest.raises(JsonRejected, match=r"\$\.amount"):
            enqueue(
                session,
                "test.noop",
                {"amount": 123.45},
                workspace_id=None,
                registry=jobs.registry,
            )
        assert session.execute(text("SELECT count(*) FROM jobs")).scalar_one() == 0


def test_enqueue_validates_kind_and_options(jobs: JobsHelper) -> None:
    with jobs.session_factory.begin() as session:
        with pytest.raises(ValueError, match="not registered"):
            enqueue(session, "test.unknown", {}, workspace_id=None, registry=jobs.registry)
        with pytest.raises(ValueError, match="not registered"):
            enqueue(session, "test.noop", {}, workspace_id=None)  # production registry
        with pytest.raises(ValueError, match="timezone-aware"):
            enqueue(
                session,
                "test.noop",
                {},
                workspace_id=None,
                run_after=datetime(2026, 1, 1),  # noqa: DTZ001
                registry=jobs.registry,
            )
        with pytest.raises(ValueError, match="max_attempts"):
            enqueue(
                session, "test.noop", {}, workspace_id=None, max_attempts=0, registry=jobs.registry
            )
        with pytest.raises(ValueError, match="timeout_s"):
            enqueue(
                session, "test.noop", {}, workspace_id=None, timeout_s=0, registry=jobs.registry
            )
        with pytest.raises(TypeError, match="workspace_id"):
            enqueue(
                session,
                "test.noop",
                {},
                workspace_id="not-a-uuid",  # type: ignore[arg-type]
                registry=jobs.registry,
            )


def test_enqueue_defaults_come_from_the_handler_spec(jobs: JobsHelper) -> None:
    job_id = jobs.enqueue("test.noop", {"n": 1})
    later = datetime.now(UTC) + timedelta(hours=1)
    delayed = jobs.enqueue("test.noop", {}, run_after=later, max_attempts=7, timeout_s=9)

    row = jobs.row(job_id)
    assert row.status == "queued"
    assert row.attempts == 0
    assert row.max_attempts == jobs.registry["test.noop"].max_attempts
    assert row.timeout_s is None  # = the kind's default at run time
    assert row.payload == {"n": 1}
    assert row.locked_by is None
    other = jobs.row(delayed)
    assert (other.max_attempts, other.timeout_s) == (7, 9)
    assert abs((other.run_after - later).total_seconds()) < 1


def test_get_job_view_is_scoped_to_the_workspace(jobs: JobsHelper) -> None:
    with jobs.session_factory.begin() as session:
        mine = new_workspace(session)
        other = new_workspace(session)
        job_id = enqueue(session, "test.noop", {"n": 1}, workspace_id=mine, registry=jobs.registry)

    with jobs.session_factory() as session:
        view = get_job(session, job_id, workspace_id=mine)
        assert get_job(session, job_id, workspace_id=other) is None
        assert get_job(session, uuid.uuid4(), workspace_id=None) is None
        admin_view = get_job(session, job_id, workspace_id=None)

    assert view is not None
    assert view == admin_view
    assert view.status is JobStatus.QUEUED
    assert (view.kind, view.attempts, view.error_code, view.result) == ("test.noop", 0, None, None)
    assert not view.finished
    assert not hasattr(view, "payload")  # metadata only (AP-05)


def test_enqueue_unique_coalesces_pending_jobs(jobs: JobsHelper) -> None:
    with jobs.session_factory.begin() as session:
        first = enqueue_unique(session, "test.noop", {}, workspace_id=None, registry=jobs.registry)
        second = enqueue_unique(session, "test.noop", {}, workspace_id=None, registry=jobs.registry)
    assert first is not None
    assert second is None
    with jobs.engine.begin() as connection:
        connection.execute(
            text("UPDATE jobs SET status = 'succeeded' WHERE id = :id"), {"id": first}
        )
    with jobs.session_factory.begin() as session:
        third = enqueue_unique(session, "test.noop", {}, workspace_id=None, registry=jobs.registry)
    assert third is not None


# --------------------------------------------------------------------------- claim


def test_claim_leases_the_job(jobs: JobsHelper) -> None:
    job_id = jobs.enqueue("test.noop", {"n": 1})

    claimed = claim_jobs(
        jobs.session_factory,
        worker_id="w-1",
        slots={"test.noop": None},
        limit=5,
        lease_s=30,
    )

    assert [job.id for job in claimed] == [job_id]
    assert (claimed[0].attempt, claimed[0].payload, claimed[0].timeout_s) == (1, {"n": 1}, None)
    row = jobs.row(job_id)
    assert row.status == "running"
    assert row.attempts == 1
    assert row.locked_by == "w-1"
    assert row.heartbeat_at is not None
    lease = (row.locked_until - row.heartbeat_at).total_seconds()
    assert 29 <= lease <= 31
    assert claim(jobs) == []  # nothing left


def test_claim_honours_run_after_order_and_kinds(jobs: JobsHelper) -> None:
    now = datetime.now(UTC)
    late = jobs.enqueue("test.noop", {}, run_after=now - timedelta(seconds=1))
    early = jobs.enqueue("test.noop", {}, run_after=now - timedelta(seconds=10))
    future = jobs.enqueue("test.noop", {}, run_after=now + timedelta(hours=1))
    other_kind = jobs.enqueue("test.track", {}, run_after=now - timedelta(seconds=20))

    claimed = claim_jobs(
        jobs.session_factory, worker_id="w", slots={"test.noop": None}, limit=10, lease_s=30
    )

    assert [job.id for job in claimed] == [early, late]
    assert jobs.status(future) == "queued"
    assert jobs.status(other_kind) == "queued"


def test_claim_respects_per_kind_slots(jobs: JobsHelper) -> None:
    for _ in range(3):
        jobs.enqueue("test.limited", {})
    noop = jobs.enqueue("test.noop", {})

    first = claim_jobs(
        jobs.session_factory,
        worker_id="w",
        slots={"test.limited": 1, "test.noop": None},
        limit=10,
        lease_s=30,
    )
    second = claim_jobs(
        jobs.session_factory,
        worker_id="w",
        slots={"test.limited": 0, "test.noop": None},
        limit=10,
        lease_s=30,
    )

    assert sorted(job.kind for job in first) == ["test.limited", "test.noop"]
    assert noop in {job.id for job in first}
    assert second == []
    assert count(jobs.engine, "SELECT count(*) FROM jobs WHERE status = 'queued'") == 2


def test_claim_skips_rows_locked_by_another_transaction(jobs: JobsHelper) -> None:
    """SKIP LOCKED: a concurrent claimer is not blocked by, and does not take, locked rows."""
    ids = [jobs.enqueue("test.noop", {"i": i}) for i in range(4)]
    blocker = jobs.engine.connect()
    try:
        transaction = blocker.begin()
        locked = blocker.execute(
            text(
                "SELECT id FROM jobs WHERE status = 'queued' ORDER BY run_after, created_at "
                "LIMIT 2 FOR UPDATE"
            )
        ).scalars()
        locked_ids = set(locked)

        started = time.monotonic()
        claimed = set(claim(jobs))
        elapsed = time.monotonic() - started

        assert claimed == set(ids) - locked_ids
        assert elapsed < 2.0
        transaction.rollback()
    finally:
        blocker.close()
    assert set(claim(jobs)) == locked_ids


# --------------------------------------------------------------------------- lease fencing


def test_lease_is_fenced_by_worker_and_attempt(jobs: JobsHelper) -> None:
    job_id = jobs.enqueue("test.noop", {})
    claim(jobs, worker_id="w-a")

    with jobs.session_factory.begin() as session:
        assert (
            lock_lease(session, job_id=job_id, worker_id="w-a", attempt=1, mode="update")
            is LeaseState.HELD
        )
    with jobs.session_factory.begin() as session:
        assert (
            lock_lease(session, job_id=job_id, worker_id="w-a", attempt=2, mode="update")
            is LeaseState.GONE
        )
        assert (
            lock_lease(session, job_id=job_id, worker_id="w-b", attempt=1, mode="share")
            is LeaseState.GONE
        )


def test_key_share_fence_blocks_takeover_but_not_renewal(jobs: JobsHelper) -> None:
    job_id = jobs.enqueue("test.noop", {})
    claim(jobs, worker_id="w-a", lease_s=30)
    handler = jobs.session_factory()
    try:
        handler.begin()
        state = lock_lease(handler, job_id=job_id, worker_id="w-a", attempt=1, mode="share")
        assert state is LeaseState.HELD

        with jobs.session_factory.begin() as session:  # heartbeat: not blocked
            renewal = renew_leases(session, worker_id="w-a", leases=[(job_id, 1)], lease_s=30)
        assert renewal.renewed == {job_id}
        with jobs.session_factory.begin() as session:  # takeover: skipped, reported busy
            state = lock_lease(
                session, job_id=job_id, worker_id="w-a", attempt=1, mode="update_skip"
            )
        assert state is LeaseState.BUSY
        with jobs.engine.begin() as connection:
            connection.execute(
                text("UPDATE jobs SET locked_until = now() - interval '1 second' WHERE id = :id"),
                {"id": job_id},
            )
        assert reclaim_expired(jobs.session_factory, backoff=TEST_BACKOFF) == []
        handler.rollback()
    finally:
        handler.close()
    reclaimed = reclaim_expired(jobs.session_factory, backoff=TEST_BACKOFF)
    assert [job.id for job in reclaimed] == [job_id]


def test_renewal_skips_rows_locked_for_update_and_reports_them_busy(jobs: JobsHelper) -> None:
    first = jobs.enqueue("test.noop", {})
    second = jobs.enqueue("test.noop", {})
    claim(jobs, worker_id="w-a", lease_s=30)
    finisher = jobs.session_factory()
    try:
        finisher.begin()
        lock_lease(finisher, job_id=first, worker_id="w-a", attempt=1, mode="update")
        with jobs.session_factory.begin() as session:
            session.execute(text("SET LOCAL lock_timeout = '2s'"))
            renewal = renew_leases(
                session,
                worker_id="w-a",
                leases=[(first, 1), (second, 1), (uuid.uuid4(), 1)],
                lease_s=30,
            )
        finisher.rollback()
    finally:
        finisher.close()
    assert renewal.renewed == {second}
    assert renewal.busy == {first}
    assert renewal.held == {first, second}


# --------------------------------------------------------------------------- failures


def test_failures_back_off_increasingly_then_go_dead(jobs: JobsHelper) -> None:
    backoff = Backoff(base_s=10, factor=2, cap_s=35, jitter=0.5)
    job_id = jobs.enqueue("test.noop", {}, max_attempts=4)
    delays: list[float] = []
    for attempt in range(1, 5):
        with jobs.engine.begin() as connection:
            connection.execute(
                text("UPDATE jobs SET run_after = now() WHERE id = :id"), {"id": job_id}
            )
        assert claim(jobs) == [job_id]
        with jobs.session_factory.begin() as session:
            assert (
                lock_lease(
                    session, job_id=job_id, worker_id="w-test", attempt=attempt, mode="update"
                )
                is LeaseState.HELD
            )
            outcome = mark_failed(
                session,
                job_id=job_id,
                attempts=attempt,
                max_attempts=4,
                error="HANDLER_ERROR:ValueError",
                permanent=False,
                backoff=backoff,
            )
        row = jobs.row(job_id)
        if attempt < 4:
            assert outcome.status is JobStatus.QUEUED
            assert row.status == "queued"
            assert outcome.delay_s is not None
            delays.append(outcome.delay_s)
            assert abs((row.run_after - row.updated_at).total_seconds() - outcome.delay_s) < 0.01
        else:
            assert outcome.status is JobStatus.DEAD
            assert row.status == "dead"
            assert row.finished_at is not None
        assert row.locked_by is None
        assert row.locked_until is None
        assert row.last_error == "HANDLER_ERROR:ValueError"

    assert 10 <= delays[0] < 15
    assert 20 <= delays[1] < 30
    assert delays[2] == 35  # capped
    assert delays == sorted(delays)


def test_permanent_failure_ends_as_failed(jobs: JobsHelper) -> None:
    job_id = jobs.enqueue("test.noop", {}, max_attempts=5)
    claim(jobs)
    with jobs.session_factory.begin() as session:
        lock_lease(session, job_id=job_id, worker_id="w-test", attempt=1, mode="update")
        outcome = mark_failed(
            session,
            job_id=job_id,
            attempts=1,
            max_attempts=5,
            error="FILE_REJECTED",
            permanent=True,
            backoff=TEST_BACKOFF,
        )
    assert outcome.status is JobStatus.FAILED
    row = jobs.row(job_id)
    assert (row.status, row.last_error, row.attempts) == ("failed", "FILE_REJECTED", 1)


def test_release_returns_the_job_without_counting_the_attempt(jobs: JobsHelper) -> None:
    job_id = jobs.enqueue("test.noop", {})
    claim(jobs)
    with jobs.session_factory.begin() as session:
        lock_lease(session, job_id=job_id, worker_id="w-test", attempt=1, mode="update")
        release(session, job_id)
    row = jobs.row(job_id)
    assert (row.status, row.attempts, row.last_error, row.locked_by) == (
        "queued",
        0,
        "INTERRUPTED",
        None,
    )


# --------------------------------------------------------------------------- reclaim


def simulate_crashed_worker(engine: Engine, job_id: uuid.UUID, *, attempts: int) -> None:
    """The job looks like a worker died while running it: running, lease in the past."""
    with engine.begin() as connection:
        connection.execute(
            text(
                "UPDATE jobs SET status = 'running', attempts = :attempts, "
                "locked_by = 'crashed-worker:1:dead', heartbeat_at = now() - interval '5 minutes', "
                "locked_until = now() - interval '1 minute' WHERE id = :id"
            ),
            {"id": job_id, "attempts": attempts},
        )


def test_reclaim_requeues_expired_lease_and_counts_the_attempt(jobs: JobsHelper) -> None:
    job_id = jobs.enqueue("test.noop", {}, max_attempts=3)
    alive = jobs.enqueue("test.noop", {})
    simulate_crashed_worker(jobs.engine, job_id, attempts=1)
    claim(jobs, worker_id="alive-worker")  # takes `alive`, lease in the future

    reclaimed = reclaim_expired(jobs.session_factory, backoff=TEST_BACKOFF)

    assert [(job.id, job.outcome.status) for job in reclaimed] == [(job_id, JobStatus.QUEUED)]
    row = jobs.row(job_id)
    assert (row.status, row.attempts, row.last_error, row.locked_by) == (
        "queued",
        1,
        "LEASE_EXPIRED",
        None,
    )
    assert row.run_after > row.updated_at
    assert jobs.status(alive) == "running"


def test_reclaim_buries_job_whose_attempts_are_used_up(jobs: JobsHelper) -> None:
    job_id = jobs.enqueue("test.noop", {}, max_attempts=2)
    simulate_crashed_worker(jobs.engine, job_id, attempts=2)

    reclaimed = reclaim_expired(jobs.session_factory, backoff=TEST_BACKOFF)

    assert [job.outcome.status for job in reclaimed] == [JobStatus.DEAD]
    row = jobs.row(job_id)
    assert (row.status, row.last_error) == ("dead", "LEASE_EXPIRED")
    assert row.finished_at is not None


def test_concurrent_reclaimers_take_each_job_once(jobs: JobsHelper) -> None:
    ids = [jobs.enqueue("test.noop", {}, max_attempts=5) for _ in range(30)]
    for job_id in ids:
        simulate_crashed_worker(jobs.engine, job_id, attempts=1)
    results: list[list[uuid.UUID]] = []
    barrier = threading.Barrier(4)

    def reclaimer() -> None:
        barrier.wait()
        results.append(
            [job.id for job in reclaim_expired(jobs.session_factory, backoff=TEST_BACKOFF, limit=8)]
        )

    threads = [threading.Thread(target=reclaimer) for _ in range(4)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(30)
    taken = [job_id for result in results for job_id in result]
    assert len(taken) == len(set(taken))
    assert count(
        jobs.engine, "SELECT count(*) FROM jobs WHERE status = 'queued' AND attempts = 1"
    ) == len(taken)


# --------------------------------------------------------------------------- heartbeats


def test_heartbeat_upsert_purge_and_delete(jobs: JobsHelper) -> None:
    identity = WorkerIdentity(
        worker_id="host:1:abc",
        hostname="host",
        pid=1,
        version="test",
        started_at=datetime.now(UTC),
    )
    with jobs.session_factory.begin() as session:
        upsert_heartbeat(session, identity, running_jobs=2)
    first = jobs.heartbeats()[0]
    time.sleep(0.01)
    with jobs.session_factory.begin() as session:
        upsert_heartbeat(session, identity, running_jobs=0)
        session.execute(
            text(
                "INSERT INTO worker_heartbeats (worker_id, hostname, pid, version, last_seen_at) "
                "VALUES ('old:2:x', 'old', 2, 'test', now() - interval '2 hours')"
            )
        )
    rows = {row.worker_id: row for row in jobs.heartbeats()}
    assert rows["host:1:abc"].running_jobs == 0
    assert rows["host:1:abc"].last_seen_at > first.last_seen_at
    assert rows["host:1:abc"].started_at == first.started_at

    with jobs.session_factory.begin() as session:
        assert purge_heartbeats(session, max_age_s=3600) == 1
    assert [row.worker_id for row in jobs.heartbeats()] == ["host:1:abc"]
    with jobs.session_factory.begin() as session:
        delete_heartbeat(session, "host:1:abc")
    assert jobs.heartbeats() == []
