"""``cardflow worker`` as a real process: start, heartbeat, SIGTERM, ``--once``, failures.

The plain console script runs with the production registry (no job kinds yet);
``worker_launcher.py`` runs the same ``cardflow.cli.main`` with the testkit kinds registered
in its own process, so jobs can be in flight when the signal arrives.
"""

import os
import signal
import subprocess
import sys
import time
from collections.abc import Iterator
from pathlib import Path
from typing import Any

import pytest
from jobs_helpers import TESTS_JOBS_DIR, JobsHelper, pii_scan, wait_for
from sqlalchemy.engine import URL

from cardflow.settings import SECRET_FIELDS, Settings

pytestmark = pytest.mark.db

CARDFLOW = Path(sys.executable).with_name("cardflow")
LAUNCHER = TESTS_JOBS_DIR / "worker_launcher.py"


@pytest.fixture
def worker_env(test_database_url: URL) -> dict[str, str]:
    """Environment for a worker process on the test database (password via its own variable)."""
    names = {name.upper() for name in Settings.model_fields}
    names |= {f"{name.upper()}_FILE" for name in SECRET_FIELDS}
    env = {key: value for key, value in os.environ.items() if key.upper() not in names}
    assert test_database_url.password is not None
    # URL.set(password=None) keeps the password; build the URL without it instead.
    without_password = URL.create(
        drivername=test_database_url.drivername,
        username=test_database_url.username,
        host=test_database_url.host,
        port=test_database_url.port,
        database=test_database_url.database,
    )
    env["DATABASE_URL"] = without_password.render_as_string(hide_password=False)
    env["DATABASE_PASSWORD"] = test_database_url.password
    env["LOG_FORMAT"] = "json"
    env["LOG_LEVEL"] = "info"
    env["CARDFLOW_VERSION"] = "t008-test"
    return env


class WorkerProcess:
    """A ``cardflow worker`` child process with captured output."""

    def __init__(self, argv: list[str], env: dict[str, str]) -> None:
        """Start ``argv`` with ``env``."""
        self.proc = subprocess.Popen(  # noqa: S603
            argv, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )

    def finish(self, timeout: float = 60) -> tuple[int, str]:
        """Wait for exit; returns ``(returncode, stdout + stderr)``."""
        out, err = self.proc.communicate(timeout=timeout)
        return self.proc.returncode, out + err

    def wait_heartbeat(self, jobs: JobsHelper, timeout: float = 30) -> list[Any]:
        """Wait for this worker's heartbeat row; fail with the output if the process died."""
        rows = wait_for(
            lambda: (
                [row for row in jobs.heartbeats() if row.pid == self.proc.pid]
                or self.proc.poll() is not None
            ),
            timeout=timeout,
            what="worker heartbeat row",
        )
        if rows is True:
            returncode, output = self.finish()
            pytest.fail(f"worker exited early with {returncode}:\n{output}")
        return rows

    def kill(self) -> None:
        """Last resort cleanup."""
        if self.proc.poll() is None:
            self.proc.kill()
            self.proc.communicate(timeout=30)


@pytest.fixture
def spawn_worker(worker_env: dict[str, str]) -> Iterator[type[WorkerProcess]]:
    """Factory starting worker processes; any left running is killed at teardown."""
    started: list[WorkerProcess] = []

    class Tracked(WorkerProcess):
        def __init__(self, argv: list[str], env: dict[str, str] | None = None) -> None:
            super().__init__(argv, env if env is not None else worker_env)
            started.append(self)

    yield Tracked
    for process in started:
        process.kill()


def test_console_script_worker_stops_gracefully_on_sigterm(
    jobs: JobsHelper, spawn_worker: type[WorkerProcess], tmp_path: Path
) -> None:
    worker = spawn_worker([str(CARDFLOW), "worker", "--concurrency", "2"])
    row = worker.wait_heartbeat(jobs)[0]
    assert row.pid == worker.proc.pid
    assert row.version == "t008-test"
    assert row.running_jobs == 0

    started = time.monotonic()
    worker.proc.send_signal(signal.SIGTERM)
    returncode, output = worker.finish(timeout=30)

    assert returncode == 0, output
    assert time.monotonic() - started < 10
    assert jobs.heartbeats() == []
    assert "worker started" in output
    assert "worker stopping reason=SIGTERM" in output
    assert "worker stopped" in output
    scan = pii_scan(output, tmp_path)
    assert scan.returncode == 0, scan.stdout + scan.stderr


def test_console_script_worker_once_exits_0(
    jobs: JobsHelper, spawn_worker: type[WorkerProcess]
) -> None:
    worker = spawn_worker([str(CARDFLOW), "worker", "--once"])

    returncode, output = worker.finish(timeout=60)

    assert returncode == 0, output
    assert "claimed=0" in output
    assert jobs.heartbeats() == []


def test_sigterm_lets_the_running_job_finish(
    jobs: JobsHelper, spawn_worker: type[WorkerProcess], tmp_path: Path
) -> None:
    inline = jobs.enqueue("test.sleep_cooperative", {"ms": 2500})
    child = jobs.enqueue("test.sleep", {"ms": 2500})
    worker = spawn_worker(
        [sys.executable, str(LAUNCHER), "worker", "--concurrency", "2", "--shutdown-timeout", "20"]
    )
    wait_for(
        lambda: jobs.status(inline) == "running" and jobs.status(child) == "running",
        timeout=30,
        what="jobs running",
    )
    worker.wait_heartbeat(jobs)

    worker.proc.send_signal(signal.SIGTERM)
    returncode, output = worker.finish(timeout=60)

    assert returncode == 0, output
    assert jobs.status(inline) == "succeeded"
    assert jobs.status(child) == "succeeded"
    assert "worker stopping reason=SIGTERM running=2" in output
    assert "succeeded=2" in output
    assert jobs.heartbeats() == []
    scan = pii_scan(output, tmp_path)
    assert scan.returncode == 0, scan.stdout + scan.stderr


def test_sigterm_after_the_grace_period_releases_the_job(
    jobs: JobsHelper, spawn_worker: type[WorkerProcess], tmp_path: Path
) -> None:
    pid_file = tmp_path / "child.pid"
    job_id = jobs.enqueue("test.sleep", {"ms": 120_000, "pid_file": str(pid_file)})
    worker = spawn_worker([sys.executable, str(LAUNCHER), "worker", "--shutdown-timeout", "1"])
    child_pid = int(
        wait_for(lambda: pid_file.exists() and pid_file.read_text(), timeout=30, what="child pid")
    )

    started = time.monotonic()
    worker.proc.send_signal(signal.SIGTERM)
    returncode, output = worker.finish(timeout=60)
    elapsed = time.monotonic() - started

    assert returncode == 0, output
    assert elapsed < 15
    row = jobs.row(job_id)
    assert (row.status, row.attempts, row.last_error, row.locked_by) == (
        "queued",
        0,
        "INTERRUPTED",
        None,
    )
    with pytest.raises(ProcessLookupError):
        os.kill(child_pid, 0)
    assert "job released on shutdown" in output


def test_second_signal_forces_the_stop(jobs: JobsHelper, spawn_worker: type[WorkerProcess]) -> None:
    job_id = jobs.enqueue("test.sleep", {"ms": 120_000})
    worker = spawn_worker([sys.executable, str(LAUNCHER), "worker", "--shutdown-timeout", "300"])
    jobs.wait_status(job_id, "running", timeout=30)
    time.sleep(1.0)

    worker.proc.send_signal(signal.SIGINT)
    time.sleep(0.5)
    started = time.monotonic()
    worker.proc.send_signal(signal.SIGINT)
    returncode, output = worker.finish(timeout=60)

    assert returncode == 0, output
    assert time.monotonic() - started < 15
    assert jobs.row(job_id).status == "queued"


def test_launcher_once_runs_the_due_jobs(
    jobs: JobsHelper, spawn_worker: type[WorkerProcess]
) -> None:
    ids = [jobs.enqueue("test.noop", {}), jobs.enqueue("test.sum", {"values": [4, 5]})]
    worker = spawn_worker([sys.executable, str(LAUNCHER), "worker", "--once", "--concurrency", "2"])

    returncode, output = worker.finish(timeout=60)

    assert returncode == 0, output
    assert [jobs.status(job_id) for job_id in ids] == ["succeeded", "succeeded"]
    assert jobs.row(ids[1]).result["sum"] == 9


def test_worker_exits_1_when_the_database_is_unreachable(
    worker_env: dict[str, str], spawn_worker: type[WorkerProcess]
) -> None:
    env = dict(worker_env)
    env["DATABASE_URL"] = "postgresql+psycopg://cardflow@127.0.0.1:1/cardflow"
    env["DATABASE_PASSWORD"] = "pw-must-not-leak-5f1"
    worker = spawn_worker([str(CARDFLOW), "worker"], env)

    returncode, output = worker.finish(timeout=60)

    assert returncode == 1
    assert "worker cannot start" in output
    assert "pw-must-not-leak-5f1" not in output
