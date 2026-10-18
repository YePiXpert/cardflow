"""Helpers shared by the T-008 tests and scripts (imported as ``jobs_helpers``)."""

import subprocess
import sys
import threading
import time
import uuid
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Final

import jobs_testkit
import pytest
from sqlalchemy import text
from sqlalchemy.engine import Engine, Row
from sqlalchemy.orm import Session, sessionmaker

from cardflow.jobs import Backoff, JsonValue, Registry, enqueue
from cardflow.jobs.worker import Worker, WorkerConfig, WorkerStats

TESTS_JOBS_DIR: Final = Path(__file__).resolve().parent
REPO_ROOT: Final = TESTS_JOBS_DIR.parents[3]
PII_SCAN: Final = REPO_ROOT / "tools" / "pii_scan.py"

TEST_BACKOFF: Final = Backoff(base_s=0.05, factor=2.0, cap_s=0.4, jitter=0.5)
TEST_CONFIG: Final = WorkerConfig(
    concurrency=4,
    lease_s=3.0,
    heartbeat_interval_s=0.2,
    poll_interval_s=0.05,
    shutdown_timeout_s=5.0,
    terminate_grace_s=1.0,
    phase_timeout_s=10.0,
    reclaim_interval_s=0.3,
    heartbeat_purge_interval_s=60.0,
    heartbeat_max_age_s=3600.0,
    db_retry_base_s=0.05,
    db_retry_max_s=0.5,
    backoff=TEST_BACKOFF,
)


def make_config(**overrides: object) -> WorkerConfig:
    """:data:`TEST_CONFIG` with ``overrides``."""
    settings = {name: getattr(TEST_CONFIG, name) for name in WorkerConfig.__dataclass_fields__}
    settings.update(overrides)
    return WorkerConfig(**settings)


def wait_for[T](
    predicate: Callable[[], T], *, timeout: float = 20.0, interval: float = 0.05, what: str = ""
) -> T:
    """Poll ``predicate`` until it returns a truthy value; fail after ``timeout`` seconds."""
    deadline = time.monotonic() + timeout
    while True:
        value = predicate()
        if value:
            return value
        if time.monotonic() >= deadline:
            pytest.fail(f"timed out after {timeout}s waiting for {what or 'condition'}")
        time.sleep(interval)


class JobsHelper:
    """Small database helpers bound to the session database."""

    def __init__(
        self, engine: Engine, session_factory: sessionmaker[Session], registry: Registry
    ) -> None:
        """Bind to ``engine``/``session_factory``; enqueue against ``registry``."""
        self.engine = engine
        self.session_factory = session_factory
        self.registry = registry

    def enqueue(
        self,
        kind: str,
        payload: JsonValue | None = None,
        *,
        workspace_id: uuid.UUID | None = None,
        run_after: datetime | None = None,
        max_attempts: int | None = None,
        timeout_s: int | None = None,
    ) -> uuid.UUID:
        """Enqueue and commit one job."""
        with self.session_factory.begin() as session:
            return enqueue(
                session,
                kind,
                payload if payload is not None else {},
                workspace_id=workspace_id,
                run_after=run_after,
                max_attempts=max_attempts,
                timeout_s=timeout_s,
                registry=self.registry,
            )

    def row(self, job_id: uuid.UUID) -> Row[Any]:
        """The ``jobs`` row of ``job_id`` (all columns)."""
        with self.engine.connect() as connection:
            return connection.execute(
                text("SELECT * FROM jobs WHERE id = :id"), {"id": job_id}
            ).one()

    def status(self, job_id: uuid.UUID) -> str:
        """Current ``jobs.status``."""
        return self.row(job_id).status

    def wait_status(self, job_id: uuid.UUID, *statuses: str, timeout: float = 20.0) -> Row[Any]:
        """Wait until the job is in one of ``statuses``; returns the row."""
        return wait_for(
            lambda: (row := self.row(job_id)).status in statuses and row,
            timeout=timeout,
            what=f"job {job_id} to reach {statuses}",
        )

    def effects(self) -> list[Row[Any]]:
        """Rows of the effects table."""
        with self.engine.connect() as connection:
            return list(
                connection.execute(
                    text(f"SELECT * FROM {jobs_testkit.EFFECTS_TABLE} ORDER BY note")  # noqa: S608
                )
            )

    def heartbeats(self) -> list[Row[Any]]:
        """Rows of ``worker_heartbeats``."""
        with self.engine.connect() as connection:
            return list(connection.execute(text("SELECT * FROM worker_heartbeats")))


@dataclass
class RunningWorker:
    """A worker running on a background thread."""

    worker: Worker
    thread: threading.Thread
    result: list[WorkerStats]

    def stop(self, *, force: bool = False, timeout: float = 30.0) -> WorkerStats:
        """Request a stop and wait for :meth:`Worker.run` to return."""
        self.worker.request_stop(force=force)
        self.thread.join(timeout)
        assert not self.thread.is_alive(), "worker did not stop"
        return self.result[0]


def pii_scan(
    content: str, tmp_path: Path, name: str = "scan.log"
) -> subprocess.CompletedProcess[str]:
    """Run ``tools/pii_scan.py`` (standard library only) on ``content``."""
    path = tmp_path / name
    path.write_text(content, encoding="utf-8")
    return subprocess.run(  # noqa: S603
        [sys.executable, "-I", str(PII_SCAN), str(path)],
        capture_output=True,
        text=True,
        check=False,
        timeout=60,
    )
