"""TC-DB-10: concurrent claiming with ``FOR UPDATE SKIP LOCKED`` never hands a job out twice.

Two levels:

* claimers -- 8 threads, each with its own database connection, call ``claim_jobs`` in
  random batch sizes on 400 queued jobs as fast as they can, and finish each claimed job;
* workers -- 3 complete :class:`Worker` instances (separate engines/connection pools,
  4 job threads each) drain 150 inline and 6 subprocess jobs.

Both print their statistics (run with ``-s``): claims, distinct jobs, duplicates.
"""

import random
import sys
import threading
import time
import uuid
from collections import Counter
from collections.abc import Callable, Iterator

import jobs_testkit
import pytest
from jobs_helpers import JobsHelper, RunningWorker, wait_for
from sqlalchemy import text
from sqlalchemy.engine import URL, Engine

from cardflow.db import create_engine, create_session_factory
from cardflow.jobs.queue import claim_jobs, lock_lease, mark_succeeded

pytestmark = pytest.mark.db

CLAIMERS = 8
CLAIM_JOBS = 400
WORKERS = 3
WORKER_INLINE_JOBS = 150
WORKER_SUBPROCESS_JOBS = 6


def test_tc_db_10_concurrent_claimers_never_share_a_job(jobs: JobsHelper) -> None:
    with jobs.session_factory.begin() as session:
        session.execute(
            text(
                "INSERT INTO jobs (kind, payload, status) "
                "SELECT 'test.noop', jsonb_build_object('i', g), 'queued' "
                "FROM generate_series(1, :n) AS g"
            ),
            {"n": CLAIM_JOBS},
        )
    claims: list[tuple[str, uuid.UUID]] = []
    claims_lock = threading.Lock()
    empty_rounds: Counter[str] = Counter()
    errors: list[BaseException] = []
    barrier = threading.Barrier(CLAIMERS)

    def claimer(name: str) -> None:
        rng = random.Random(name)  # noqa: S311 -- batch sizes, not security
        try:
            barrier.wait()
            idle = 0
            while idle < 3:
                claimed = claim_jobs(
                    jobs.session_factory,
                    worker_id=name,
                    slots={"test.noop": None},
                    limit=rng.randint(1, 5),
                    lease_s=60,
                )
                if not claimed:
                    idle += 1
                    empty_rounds[name] += 1
                    time.sleep(0.01)
                    continue
                idle = 0
                with claims_lock:
                    claims.extend((name, job.id) for job in claimed)
                for job in claimed:
                    with jobs.session_factory.begin() as session:
                        lock_lease(session, job_id=job.id, worker_id=name, attempt=1, mode="update")
                        mark_succeeded(session, job.id, '{"by":"' + name + '"}')
        except BaseException as exc:  # noqa: BLE001 -- surfaced by the assertion below
            errors.append(exc)

    threads = [
        threading.Thread(target=claimer, args=(f"claimer-{index}",)) for index in range(CLAIMERS)
    ]
    started = time.monotonic()
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(120)
    elapsed = time.monotonic() - started

    assert not errors, errors
    per_job = Counter(job_id for _, job_id in claims)
    duplicates = sum(count - 1 for count in per_job.values() if count > 1)
    per_claimer = Counter(name for name, _ in claims)
    with jobs.engine.connect() as connection:
        statuses = dict(
            connection.execute(text("SELECT status, count(*) FROM jobs GROUP BY status")).all()
        )
        attempts = dict(
            connection.execute(text("SELECT attempts, count(*) FROM jobs GROUP BY attempts")).all()
        )
        winners = dict(
            connection.execute(text("SELECT result->>'by', count(*) FROM jobs GROUP BY 1")).all()
        )
    sys.stdout.write(
        "\n[TC-DB-10 claimers] "
        f"jobs={CLAIM_JOBS} claimers={CLAIMERS} claims={len(claims)} distinct={len(per_job)} "
        f"duplicates={duplicates} elapsed_s={elapsed:.2f}\n"
        f"  claims per claimer: {dict(sorted(per_claimer.items()))}\n"
        f"  empty claim rounds per claimer: {dict(sorted(empty_rounds.items()))}\n"
        f"  final statuses: {statuses}; attempts histogram: {attempts}\n"
    )
    assert duplicates == 0
    assert len(claims) == len(per_job) == CLAIM_JOBS
    assert statuses == {"succeeded": CLAIM_JOBS}
    assert attempts == {1: CLAIM_JOBS}
    assert winners == dict(per_claimer)  # the recorded finisher is the one that claimed it
    assert len(per_claimer) >= 2  # really concurrent


@pytest.fixture
def worker_engines(test_database_url: URL) -> Iterator[list[Engine]]:
    """One engine (own pool) per worker, like separate processes would have."""
    engines = [create_engine(test_database_url) for _ in range(WORKERS)]
    yield engines
    for engine in engines:
        engine.dispose()


def test_tc_db_10_concurrent_workers_run_each_job_exactly_once(
    jobs: JobsHelper,
    run_worker: Callable[..., RunningWorker],
    worker_engines: list[Engine],
) -> None:
    inline = [jobs.enqueue("test.noop", {"i": index}) for index in range(WORKER_INLINE_JOBS)]
    children = [
        jobs.enqueue("test.sum", {"values": [index, 1]}) for index in range(WORKER_SUBPROCESS_JOBS)
    ]
    started = time.monotonic()
    workers = [
        run_worker(session_factory=create_session_factory(engine), concurrency=4)
        for engine in worker_engines
    ]

    def all_done() -> bool:
        with jobs.engine.connect() as connection:
            return (
                connection.execute(
                    text("SELECT count(*) FROM jobs WHERE status <> 'succeeded'")
                ).scalar_one()
                == 0
            )

    wait_for(all_done, timeout=120, what="all jobs succeeded")
    elapsed = time.monotonic() - started
    stats = [worker.stop() for worker in workers]

    executions = [jobs_testkit.EXECUTIONS[str(job_id)] for job_id in inline]
    with jobs.engine.connect() as connection:
        attempts = dict(
            connection.execute(text("SELECT attempts, count(*) FROM jobs GROUP BY attempts")).all()
        )
        sums = sorted(
            connection.execute(
                text("SELECT (result->>'sum')::int FROM jobs WHERE id = ANY(:ids)"),
                {"ids": children},
            ).scalars()
        )
    claimed_per_worker = [s.claimed for s in stats]
    sys.stdout.write(
        "\n[TC-DB-10 workers] "
        f"workers={WORKERS}x4 threads jobs={len(inline) + len(children)} "
        f"(inline={len(inline)}, subprocess={len(children)}) "
        f"claims={sum(claimed_per_worker)} per_worker={claimed_per_worker} "
        f"inline executions: max={max(executions)} min={min(executions)} "
        f"duplicates={sum(count - 1 for count in executions)} attempts histogram={attempts} "
        f"elapsed_s={elapsed:.2f}\n"
    )
    assert executions == [1] * WORKER_INLINE_JOBS
    assert attempts == {1: WORKER_INLINE_JOBS + WORKER_SUBPROCESS_JOBS}
    assert sum(claimed_per_worker) == WORKER_INLINE_JOBS + WORKER_SUBPROCESS_JOBS
    assert sums == [index + 1 for index in range(WORKER_SUBPROCESS_JOBS)]
    assert sum(1 for count in claimed_per_worker if count) >= 2
