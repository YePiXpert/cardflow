"""Worker behaviour on real PostgreSQL: execution modes, failures, timeouts, leases, shutdown.

Workers run on background threads with short timings (``jobs_helpers.TEST_CONFIG``:
heartbeat 0.2 s, lease 3 s, reclaim every 0.3 s, backoff 0.05-0.4 s).
"""

import io
import json
import os
import re
import sys
import time
import uuid
from collections.abc import Callable
from pathlib import Path
from typing import Protocol

import jobs_testkit
import pytest
from jobs_helpers import JobsHelper, RunningWorker, pii_scan, wait_for
from sqlalchemy import text
from sqlalchemy.engine import URL
from sqlalchemy.exc import OperationalError

from cardflow.db import create_engine, create_session_factory
from cardflow.jobs import Registry
from cardflow.jobs import worker as worker_module
from cardflow.jobs.periodic import enqueue_periodic
from cardflow.jobs.worker import Worker, WorkerStartupError

pytestmark = pytest.mark.db

type StartWorker = Callable[..., RunningWorker]


class DatabaseFactory(Protocol):
    """What the root ``temporary_databases`` fixture offers."""

    def create(self) -> URL:
        """Create an empty database."""
        ...

    def drop(self, url: URL) -> None:
        """Drop it again."""
        ...


def pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:  # pragma: no cover - exists, owned by someone else
        return True
    # A zombie still answers kill(0); it is dead for our purpose once reaped. The worker
    # joins its children, so a live pid here really is running.
    return True


def wait_pid_file(path: Path, timeout: float = 20.0) -> int:
    def read() -> str:
        return path.read_text() if path.exists() else ""

    return int(wait_for(read, timeout=timeout, what="pid file"))


def log_lines(stream: io.StringIO) -> list[dict[str, object]]:
    return [json.loads(line) for line in stream.getvalue().splitlines() if line.strip()]


# --------------------------------------------------------------------------- inline


def test_inline_job_runs_once_and_stores_result(jobs: JobsHelper, run_worker: StartWorker) -> None:
    job_id = jobs.enqueue("test.noop", {"n": 1})
    worker = run_worker()

    row = jobs.wait_status(job_id, "succeeded")
    stats = worker.stop()

    assert row.result == {"ok": True, "attempt": 1}
    assert (row.attempts, row.locked_by, row.locked_until, row.last_error) == (1, None, None, None)
    assert row.finished_at is not None
    assert jobs_testkit.EXECUTIONS[str(job_id)] == 1
    assert (stats.claimed, stats.succeeded) == (1, 1)


def test_inline_exception_message_never_reaches_last_error_or_logs(
    jobs: JobsHelper,
    run_worker: StartWorker,
    captured_logs: io.StringIO,
    tmp_path: Path,
) -> None:
    """An exception message with a card number, an amount and an e-mail address must not be
    stored in ``last_error`` or written to any log line; only the type is recorded."""
    job_id = jobs.enqueue("test.fail_pii", {}, max_attempts=2)
    worker = run_worker()

    row = jobs.wait_status(job_id, "dead")
    worker.stop()

    assert row.last_error == "HANDLER_ERROR:ValueError"
    assert row.attempts == 2
    output = captured_logs.getvalue()
    lines = log_lines(captured_logs)
    assert any(line.get("exc_type") == "ValueError" for line in lines)
    assert any("job failed" in str(line["message"]) for line in lines)
    for marker in jobs_testkit.PII_MARKERS:
        assert marker not in output
        assert marker not in row.last_error
    scan = pii_scan(output, tmp_path, "worker.log")
    assert scan.returncode == 0, scan.stdout + scan.stderr
    # Positive control: the scanner does flag the message the handler raised.
    control = pii_scan(jobs_testkit.PII_MESSAGE + "\n", tmp_path, "control.log")
    assert control.returncode == 1
    assert {"card_number", "amount", "email"} <= {
        hit.rsplit(":", 1)[-1] for hit in control.stdout.split()
    }


def test_retries_back_off_increasingly_then_dead(
    jobs: JobsHelper, run_worker: StartWorker, captured_logs: io.StringIO
) -> None:
    job_id = jobs.enqueue("test.fail_pii", {}, max_attempts=5)
    worker = run_worker()

    row = jobs.wait_status(job_id, "dead")
    stats = worker.stop()

    assert (row.attempts, row.last_error) == (5, "HANDLER_ERROR:ValueError")
    delays = [
        float(match.group(1))
        for line in log_lines(captured_logs)
        if (match := re.search(r"next=queued delay_s=([0-9.]+)", str(line["message"])))
    ]
    assert len(delays) == 4
    assert delays == sorted(delays)
    assert all(0.05 <= delay <= 0.4 for delay in delays)
    assert (stats.retried, stats.dead) == (4, 1)
    dead_lines = [line for line in log_lines(captured_logs) if "next=dead" in str(line["message"])]
    assert [line["level"] for line in dead_lines] == ["error"]


def test_failed_attempts_then_success_keeps_the_last_error(
    jobs: JobsHelper, run_worker: StartWorker
) -> None:
    job_id = jobs.enqueue("test.fail_then_succeed", {"succeed_on": 3}, max_attempts=5)
    worker = run_worker()

    row = jobs.wait_status(job_id, "succeeded")
    worker.stop()

    assert (row.attempts, row.result) == (3, {"attempt": 3})
    assert row.last_error == "HANDLER_ERROR:RuntimeError"


def test_job_error_codes_permanent_and_retryable(jobs: JobsHelper, run_worker: StartWorker) -> None:
    permanent = jobs.enqueue("test.job_error", {"code": "FILE_REJECTED", "permanent": True})
    retryable = jobs.enqueue("test.job_error", {"code": "UPSTREAM_DOWN"}, max_attempts=2)
    worker = run_worker()

    failed = jobs.wait_status(permanent, "failed")
    dead = jobs.wait_status(retryable, "dead")
    worker.stop()

    assert (failed.attempts, failed.last_error) == (1, "FILE_REJECTED")
    assert (dead.attempts, dead.last_error) == (2, "UPSTREAM_DOWN")


def test_inline_result_with_fraction_is_rejected(jobs: JobsHelper, run_worker: StartWorker) -> None:
    job_id = jobs.enqueue("test.float_result", {}, max_attempts=1)
    worker = run_worker()

    row = jobs.wait_status(job_id, "dead")
    worker.stop()

    assert (row.last_error, row.result) == ("RESULT_INVALID", None)


def test_inline_handler_writes_in_its_workspace_transaction(
    jobs: JobsHelper, run_worker: StartWorker
) -> None:
    with jobs.session_factory.begin() as session:
        user_id = session.execute(text("INSERT INTO users DEFAULT VALUES RETURNING id")).scalar()
        workspace_id = session.execute(
            text("INSERT INTO workspaces (owner_user_id, kind) VALUES (:u, 'real') RETURNING id"),
            {"u": user_id},
        ).scalar_one()
    job_id = jobs.enqueue("test.write_effect", {}, workspace_id=workspace_id)
    worker = run_worker()

    jobs.wait_status(job_id, "succeeded")
    worker.stop()

    effects = jobs.effects()
    assert [(row.job_id, row.attempt, row.workspace_id) for row in effects] == [
        (job_id, 1, workspace_id)
    ]


def take_over(jobs: JobsHelper, job_id: uuid.UUID) -> None:
    """Simulate another worker that reclaimed and re-claimed the job."""
    with jobs.engine.begin() as connection:
        connection.execute(
            text(
                "UPDATE jobs SET locked_by = 'other:2:xyz', attempts = attempts + 1 WHERE id = :id"
            ),
            {"id": job_id},
        )


def test_stale_attempt_cannot_write_after_losing_its_lease(
    jobs: JobsHelper, run_worker: StartWorker, captured_logs: io.StringIO
) -> None:
    """Fencing: once another worker owns the job, the old attempt's transaction is refused
    (slow heartbeat, so the handler's own transaction is what notices)."""
    job_id = jobs.enqueue("test.wait_gate", {"gate": "fence", "write": True})
    worker = run_worker(heartbeat_interval_s=5.0, lease_s=15.0)
    wait_for(lambda: jobs_testkit.EXECUTIONS[str(job_id)] == 1, what="handler start")
    take_over(jobs, job_id)
    jobs_testkit.gate("fence").set()

    wait_for(lambda: jobs_testkit.FINISHED.get(str(job_id)) == "lease_lost", what="lease lost")
    worker.stop()

    assert jobs.effects() == []
    row = jobs.row(job_id)
    assert (row.status, row.locked_by, row.attempts, row.result) == (
        "running",
        "other:2:xyz",
        2,
        None,
    )
    assert "job attempt abandoned" in captured_logs.getvalue()
    assert "reason=lease_lost" in captured_logs.getvalue()


def test_heartbeat_notices_a_lost_lease_and_cancels_the_attempt(
    jobs: JobsHelper, run_worker: StartWorker, captured_logs: io.StringIO
) -> None:
    job_id = jobs.enqueue("test.wait_gate", {"gate": "never-opened"})
    # A long lease: the row taken over below must not expire (and be reclaimed) before the
    # final assertion, however slow the stop is.
    worker = run_worker(lease_s=30.0)
    wait_for(lambda: jobs_testkit.EXECUTIONS[str(job_id)] == 1, what="handler start")

    take_over(jobs, job_id)

    wait_for(lambda: jobs_testkit.FINISHED.get(str(job_id)) == "lease_lost", what="cancellation")
    assert worker.worker.running_jobs() == 0
    worker.stop()
    assert "job lease lost" in captured_logs.getvalue()
    assert jobs.row(job_id).locked_by == "other:2:xyz"


# --------------------------------------------------------------------------- subprocess


def test_subprocess_job_runs_in_a_separate_process(
    jobs: JobsHelper, run_worker: StartWorker
) -> None:
    job_id = jobs.enqueue("test.sum", {"values": [1, 2, 39]})
    worker = run_worker()

    row = jobs.wait_status(job_id, "succeeded")
    worker.stop()

    assert row.result["sum"] == 42
    assert row.result["pid"] != os.getpid()


def test_subprocess_hard_timeout_kills_child_and_worker_keeps_going(
    jobs: JobsHelper, run_worker: StartWorker, tmp_path: Path, captured_logs: io.StringIO
) -> None:
    pid_file = tmp_path / "child.pid"
    slow = jobs.enqueue(
        "test.sleep", {"ms": 60_000, "pid_file": str(pid_file)}, timeout_s=2, max_attempts=1
    )
    worker = run_worker(concurrency=1)
    started = time.monotonic()
    child_pid = wait_pid_file(pid_file)

    row = jobs.wait_status(slow, "dead", timeout=30)
    elapsed = time.monotonic() - started
    after = [jobs.enqueue("test.noop", {}), jobs.enqueue("test.sum", {"values": [2, 3]})]
    finished = [jobs.wait_status(job_id, "succeeded") for job_id in after]
    stats = worker.stop()

    assert (row.last_error, row.attempts, row.status) == ("TIMEOUT", 1, "dead")
    assert elapsed < 15, "the 60 s child must be stopped at the 2 s timeout"
    assert not pid_alive(child_pid)
    assert finished[1].result["sum"] == 5
    assert (stats.timed_out, stats.dead, stats.succeeded) == (1, 1, 2)
    stopped = [
        line
        for line in log_lines(captured_logs)
        if "job subprocess stopped" in str(line["message"])
    ]
    assert len(stopped) == 1
    assert "signal=SIGTERM" in str(stopped[0]["message"])
    sys.stdout.write(
        f"\n[timeout] job={slow} timeout_s=2 child_pid={child_pid} "
        f"time_to_dead_s={elapsed:.2f} child_alive_after={pid_alive(child_pid)} "
        f"last_error={row.last_error} status={row.status} "
        f"following_jobs={[r.status for r in finished]}\n"
    )


def test_subprocess_ignoring_sigterm_is_killed(
    jobs: JobsHelper, run_worker: StartWorker, tmp_path: Path, captured_logs: io.StringIO
) -> None:
    pid_file = tmp_path / "stubborn.pid"
    job_id = jobs.enqueue(
        "test.ignore_term", {"ms": 60_000, "pid_file": str(pid_file)}, timeout_s=2, max_attempts=1
    )
    worker = run_worker(concurrency=1, terminate_grace_s=0.5)
    child_pid = wait_pid_file(pid_file)

    row = jobs.wait_status(job_id, "dead", timeout=30)
    worker.stop()

    assert row.last_error == "TIMEOUT"
    assert not pid_alive(child_pid)
    assert "signal=SIGKILL" in captured_logs.getvalue()
    sys.stdout.write(
        f"\n[timeout] child_pid={child_pid} ignored SIGTERM: killed with SIGKILL, "
        f"last_error={row.last_error} status={row.status}\n"
    )


def test_subprocess_crash_is_a_failed_attempt(jobs: JobsHelper, run_worker: StartWorker) -> None:
    job_id = jobs.enqueue("test.crash", {}, max_attempts=2)
    after = jobs.enqueue("test.noop", {})
    worker = run_worker(concurrency=1)

    row = jobs.wait_status(job_id, "dead")
    jobs.wait_status(after, "succeeded")
    worker.stop()

    assert (row.last_error, row.attempts) == ("CRASHED", 2)


def test_subprocess_exception_message_stays_out_of_last_error_and_logs(
    jobs: JobsHelper,
    run_worker: StartWorker,
    captured_logs: io.StringIO,
    capfd: pytest.CaptureFixture[str],
    tmp_path: Path,
) -> None:
    job_id = jobs.enqueue("test.child_fail_pii", {}, max_attempts=1)
    worker = run_worker()

    row = jobs.wait_status(job_id, "dead")
    worker.stop()
    child_output = capfd.readouterr()

    assert row.last_error == "HANDLER_ERROR:ValueError"
    combined = captured_logs.getvalue() + child_output.out + child_output.err
    assert "job subprocess handler raised" in child_output.err  # the child did log
    for marker in jobs_testkit.PII_MARKERS:
        assert marker not in combined
    scan = pii_scan(combined, tmp_path)
    assert scan.returncode == 0, scan.stdout + scan.stderr


def test_subprocess_that_cannot_start_is_a_crashed_attempt(
    jobs: JobsHelper, run_worker: StartWorker, monkeypatch: pytest.MonkeyPatch
) -> None:
    def no_more_processes(**kwargs: object) -> None:
        del kwargs
        raise BlockingIOError("Resource temporarily unavailable")

    monkeypatch.setattr("cardflow.jobs.worker.run_child", no_more_processes)
    job_id = jobs.enqueue("test.sum", {"values": [1]}, max_attempts=1)
    worker = run_worker()

    row = jobs.wait_status(job_id, "dead")
    worker.stop()

    assert (row.last_error, row.attempts) == ("CRASHED", 1)


def test_subprocess_permanent_job_error(jobs: JobsHelper, run_worker: StartWorker) -> None:
    job_id = jobs.enqueue("test.child_job_error", {}, max_attempts=3)
    worker = run_worker()

    row = jobs.wait_status(job_id, "failed")
    worker.stop()

    assert (row.last_error, row.attempts) == ("FILE_REJECTED", 1)


def test_subprocess_output_fractions_arrive_as_decimal_and_must_not_be_stored(
    jobs: JobsHelper, run_worker: StartWorker
) -> None:
    raw = jobs.enqueue("test.fraction", {}, max_attempts=1)
    persisted = jobs.enqueue("test.fraction_persisted", {})
    not_json = jobs.enqueue("test.not_json", {}, max_attempts=1)
    worker = run_worker()

    rejected = jobs.wait_status(raw, "dead")
    stored = jobs.wait_status(persisted, "succeeded")
    garbage = jobs.wait_status(not_json, "dead")
    worker.stop()

    assert rejected.last_error == "RESULT_INVALID"
    assert stored.result == {"ratio": "0.25", "n": 1}
    assert garbage.last_error == "RESULT_INVALID"


def test_prepare_and_persist_hooks_run_in_the_worker(
    jobs: JobsHelper, run_worker: StartWorker
) -> None:
    job_id = jobs.enqueue("test.sum_prepared", {"values": [10, 20]})
    worker = run_worker()

    row = jobs.wait_status(job_id, "succeeded")
    worker.stop()

    # prepare added count(effects) = 0; the child summed; persist wrote one effect row.
    assert row.result == {"stored": 30}
    assert [(effect.job_id, effect.note) for effect in jobs.effects()] == [(job_id, "persist")]


def test_persist_failure_rolls_back_the_business_write(
    jobs: JobsHelper, run_worker: StartWorker, captured_logs: io.StringIO
) -> None:
    job_id = jobs.enqueue("test.persist_fail", {"values": [1]}, max_attempts=2)
    worker = run_worker()

    row = jobs.wait_status(job_id, "dead")
    worker.stop()

    assert (row.last_error, row.attempts, row.result) == ("HANDLER_ERROR:ValueError", 2, None)
    assert jobs.effects() == []
    assert "4111111111111111" not in captured_logs.getvalue()


# --------------------------------------------------------------------------- inline timeouts


def test_inline_timeout_cooperative_handler(jobs: JobsHelper, run_worker: StartWorker) -> None:
    job_id = jobs.enqueue("test.sleep_cooperative", {"ms": 10_000}, timeout_s=1, max_attempts=1)
    worker = run_worker()

    row = jobs.wait_status(job_id, "dead", timeout=15)
    wait_for(lambda: jobs_testkit.FINISHED.get(str(job_id)) == "cancelled", what="cancellation")
    stats = worker.stop()

    assert row.last_error == "TIMEOUT"
    assert stats.timed_out == 1


def test_inline_timeout_stuck_handler_result_is_discarded(
    jobs: JobsHelper, run_worker: StartWorker
) -> None:
    """A handler that ignores cancellation keeps its thread, but its late result is void."""
    job_id = jobs.enqueue("test.sleep_stuck", {"ms": 2500}, timeout_s=1, max_attempts=1)
    worker = run_worker()

    row = jobs.wait_status(job_id, "dead", timeout=15)
    assert jobs_testkit.FINISHED.get(str(job_id)) is None  # still sleeping
    assert worker.worker.running_jobs() == 0  # no longer leased / counted
    wait_for(lambda: jobs_testkit.FINISHED.get(str(job_id)) == "returned", what="handler end")
    time.sleep(0.3)
    worker.stop()

    final = jobs.row(job_id)
    assert (row.last_error, final.status, final.result) == ("TIMEOUT", "dead", None)


# --------------------------------------------------------------------------- concurrency limits


def test_worker_concurrency_and_per_kind_limit(jobs: JobsHelper, run_worker: StartWorker) -> None:
    limited = [jobs.enqueue("test.limited", {"ms": 150}) for _ in range(4)]
    tracked = [jobs.enqueue("test.track", {"ms": 150}) for _ in range(8)]
    worker = run_worker(concurrency=3)

    for job_id in limited + tracked:
        jobs.wait_status(job_id, "succeeded")
    worker.stop()

    assert jobs_testkit.MAX_ACTIVE["test.limited"] == 1
    assert jobs_testkit.MAX_ACTIVE["test.track"] <= 3
    assert jobs_testkit.MAX_ACTIVE["test.track"] >= 2


# --------------------------------------------------------------------------- leases, crashes


def test_lease_is_renewed_while_a_long_job_runs(jobs: JobsHelper, run_worker: StartWorker) -> None:
    job_id = jobs.enqueue("test.wait_gate", {"gate": "long"})
    worker = run_worker(lease_s=1.5, heartbeat_interval_s=0.2)
    first = jobs.wait_status(job_id, "running")
    time.sleep(3.5)  # more than two leases; reclaim runs every 0.3 s meanwhile
    later = jobs.row(job_id)
    jobs_testkit.gate("long").set()
    done = jobs.wait_status(job_id, "succeeded")
    worker.stop()

    assert later.status == "running"
    assert later.locked_until > first.locked_until
    assert later.heartbeat_at > first.heartbeat_at
    assert done.attempts == 1  # never reclaimed despite the 1 s lease


def test_job_of_a_crashed_worker_is_reclaimed_and_run(
    jobs: JobsHelper, run_worker: StartWorker, captured_logs: io.StringIO
) -> None:
    orphan = jobs.enqueue("test.noop", {}, max_attempts=3)
    buried = jobs.enqueue("test.noop", {}, max_attempts=1)
    with jobs.engine.begin() as connection:
        connection.execute(
            text(
                "UPDATE jobs SET status = 'running', attempts = 1, locked_by = 'crashed:9:dead', "
                "locked_until = now() - interval '1 minute', heartbeat_at = now() - interval "
                "'2 minutes' WHERE id = ANY(:ids)"
            ),
            {"ids": [orphan, buried]},
        )
    worker = run_worker()

    done = jobs.wait_status(orphan, "succeeded")
    dead = jobs.wait_status(buried, "dead")
    worker.stop()

    assert (done.attempts, done.last_error, done.result) == (
        2,
        "LEASE_EXPIRED",
        {"ok": True, "attempt": 2},
    )
    assert (dead.attempts, dead.last_error) == (1, "LEASE_EXPIRED")
    assert "reclaimed expired lease" in captured_logs.getvalue()


def test_claim_failures_are_logged_and_retried(
    jobs: JobsHelper,
    run_worker: StartWorker,
    captured_logs: io.StringIO,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A database outage while claiming: the loop logs (type only), backs off, recovers."""
    real_claim = worker_module.claim_jobs
    failures = {"left": 3}

    def flaky_claim(*args: object, **kwargs: object) -> object:
        if failures["left"]:
            failures["left"] -= 1
            raise OperationalError("SELECT ... 4111111111111111", {}, ConnectionError())
        return real_claim(*args, **kwargs)

    monkeypatch.setattr(worker_module, "claim_jobs", flaky_claim)
    job_id = jobs.enqueue("test.noop", {})
    worker = run_worker()

    jobs.wait_status(job_id, "succeeded")
    worker.stop()

    output = captured_logs.getvalue()
    assert output.count("claiming jobs failed") == 3
    assert "sqlalchemy.exc.OperationalError" in output
    assert "4111111111111111" not in output


def test_lease_that_cannot_be_renewed_is_given_up(
    jobs: JobsHelper,
    run_worker: StartWorker,
    tmp_path: Path,
    captured_logs: io.StringIO,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Heartbeats failing for a whole lease: the worker stops the attempt (kills the child)
    instead of running on while another worker may take the job; reclaim then counts it."""

    def no_database(*args: object, **kwargs: object) -> object:
        raise OperationalError("UPDATE jobs ...", {}, ConnectionError())

    monkeypatch.setattr(worker_module, "renew_leases", no_database)
    pid_file = tmp_path / "child.pid"
    job_id = jobs.enqueue("test.sleep", {"ms": 60_000, "pid_file": str(pid_file)}, max_attempts=1)
    worker = run_worker(lease_s=1.0, heartbeat_interval_s=0.2, concurrency=1)
    child_pid = wait_pid_file(pid_file)

    row = jobs.wait_status(job_id, "dead", timeout=30)
    stats = worker.stop()

    assert (row.last_error, row.attempts) == ("LEASE_EXPIRED", 1)
    assert not pid_alive(child_pid)
    assert stats.abandoned == 1
    assert "worker heartbeat failed" in captured_logs.getvalue()
    assert "job lease lost" in captured_logs.getvalue()


# --------------------------------------------------------------------------- heartbeats


def test_worker_heartbeat_row_tracks_running_jobs(
    jobs: JobsHelper, run_worker: StartWorker
) -> None:
    worker = run_worker(concurrency=3)
    worker_id = worker.worker.worker_id
    first = wait_for(
        lambda: [row for row in jobs.heartbeats() if row.worker_id == worker_id],
        what="heartbeat row",
    )[0]
    assert first.running_jobs == 0
    assert first.pid == os.getpid()

    gated = [jobs.enqueue("test.wait_gate", {"gate": f"hb{i}"}) for i in range(2)]
    busy = wait_for(
        lambda: [row for row in jobs.heartbeats() if row.running_jobs == 2], what="running_jobs=2"
    )[0]
    assert busy.last_seen_at > first.last_seen_at
    jobs_testkit.gate("hb0").set()
    wait_for(lambda: jobs.heartbeats()[0].running_jobs == 1, what="running_jobs=1")
    jobs_testkit.gate("hb1").set()
    for job_id in gated:
        jobs.wait_status(job_id, "succeeded")
    idle = wait_for(
        lambda: [row for row in jobs.heartbeats() if row.running_jobs == 0], what="running_jobs=0"
    )[0]
    assert idle.started_at == first.started_at
    worker.stop()

    assert jobs.heartbeats() == []  # deleted on a clean stop


# --------------------------------------------------------------------------- shutdown


def test_stop_waits_for_running_jobs_and_claims_nothing_new(
    jobs: JobsHelper, run_worker: StartWorker
) -> None:
    inline = jobs.enqueue("test.sleep_cooperative", {"ms": 1500})
    child = jobs.enqueue("test.sleep", {"ms": 1500})
    waiting = jobs.enqueue("test.noop", {})
    worker = run_worker(concurrency=2)
    wait_for(
        lambda: jobs.status(inline) == "running" and jobs.status(child) == "running",
        what="both running",
    )

    stats = worker.stop()

    assert jobs.status(inline) == "succeeded"
    assert jobs.status(child) == "succeeded"
    assert jobs.status(waiting) == "queued"  # due, but the worker was stopping
    assert (stats.succeeded, stats.released) == (2, 0)


def test_stop_after_grace_releases_jobs_without_counting_the_attempt(
    jobs: JobsHelper, run_worker: StartWorker, tmp_path: Path
) -> None:
    pid_file = tmp_path / "long.pid"
    child = jobs.enqueue("test.sleep", {"ms": 60_000, "pid_file": str(pid_file)})
    inline = jobs.enqueue("test.wait_gate", {"gate": "never"})
    worker = run_worker(concurrency=2, shutdown_timeout_s=0.5)
    child_pid = wait_pid_file(pid_file)
    jobs.wait_status(inline, "running")

    started = time.monotonic()
    stats = worker.stop()
    elapsed = time.monotonic() - started

    for job_id in (child, inline):
        row = jobs.row(job_id)
        assert (row.status, row.attempts, row.last_error, row.locked_by) == (
            "queued",
            0,
            "INTERRUPTED",
            None,
        )
    assert stats.released == 2
    assert elapsed < 10
    assert not pid_alive(child_pid)
    assert jobs.heartbeats() == []


def test_second_stop_request_skips_the_grace_period(
    jobs: JobsHelper, run_worker: StartWorker
) -> None:
    job_id = jobs.enqueue("test.sleep", {"ms": 60_000})
    worker = run_worker(shutdown_timeout_s=60)
    jobs.wait_status(job_id, "running")
    time.sleep(0.5)  # the child is up

    worker.worker.request_stop()
    started = time.monotonic()
    stats = worker.stop()  # second request -> force

    assert time.monotonic() - started < 10
    assert stats.released == 1
    assert jobs.row(job_id).attempts == 0


def test_once_runs_one_round_and_exits(jobs: JobsHelper, run_worker: StartWorker) -> None:
    ids = [jobs.enqueue("test.noop", {"i": i}) for i in range(5)]
    worker = run_worker(once=True, concurrency=2)

    worker.thread.join(30)
    assert not worker.thread.is_alive()
    stats = worker.result[0]

    statuses = sorted(jobs.status(job_id) for job_id in ids)
    assert statuses == ["queued", "queued", "queued", "succeeded", "succeeded"]
    assert (stats.claimed, stats.succeeded) == (2, 2)
    assert jobs.heartbeats() == []


# --------------------------------------------------------------------------- periodic tasks


def test_periodic_enqueue_task_coalesces_across_workers(
    jobs: JobsHelper, run_worker: StartWorker, registry: Registry
) -> None:
    enqueue_registry = Registry(registry.specs())
    task = enqueue_periodic(
        "test.periodic_noop", 0.2, "test.wait_gate", {"gate": "periodic"}, registry=enqueue_registry
    )
    no_kinds = Registry()  # these workers only schedule; nobody runs the jobs
    first = run_worker(worker_registry=no_kinds, periodic_tasks=(task,))
    second = run_worker(worker_registry=no_kinds, periodic_tasks=(task,))
    time.sleep(1.5)
    first.stop()
    second.stop()

    with jobs.engine.connect() as connection:
        pending = connection.execute(
            text("SELECT count(*) FROM jobs WHERE kind = 'test.wait_gate'")
        ).scalar_one()
    assert pending == 1


def test_system_task_purges_stale_heartbeats(jobs: JobsHelper, run_worker: StartWorker) -> None:
    with jobs.engine.begin() as connection:
        connection.execute(
            text(
                "INSERT INTO worker_heartbeats (worker_id, hostname, pid, version, last_seen_at) "
                "VALUES ('gone:1:x', 'gone', 1, 'old', now() - interval '3 hours')"
            )
        )
    worker = run_worker(heartbeat_purge_interval_s=0.2, heartbeat_max_age_s=3600)
    wait_for(
        lambda: all(row.worker_id != "gone:1:x" for row in jobs.heartbeats()),
        what="stale heartbeat purge",
    )
    worker.stop()


def test_worker_refuses_to_start_without_database(registry: Registry) -> None:
    engine = create_engine(
        "postgresql+psycopg://cardflow@127.0.0.1:1/cardflow", connect_timeout_s=2
    )
    try:
        with pytest.raises(WorkerStartupError):
            Worker(create_session_factory(engine), registry).run()
    finally:
        engine.dispose()


def test_worker_refuses_to_start_on_an_unmigrated_database(
    registry: Registry, temporary_databases: DatabaseFactory
) -> None:
    url = temporary_databases.create()
    engine = create_engine(url)
    try:
        with pytest.raises(WorkerStartupError):
            Worker(create_session_factory(engine), registry).run()
    finally:
        engine.dispose()
        temporary_databases.drop(url)
