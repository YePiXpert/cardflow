"""Fixtures for the job queue and worker tests (T-008).

* ``tests/jobs`` is put on ``sys.path`` so ``jobs_testkit`` and ``jobs_helpers`` are
  importable here and in the ``spawn`` children of subprocess jobs (they inherit
  ``sys.path``).
* ``jobs_db`` empties ``jobs``/``worker_heartbeats`` and the effects table before and after
  each test (the session database is shared) and resets the testkit bookkeeping.
* ``run_worker`` starts :class:`cardflow.jobs.worker.Worker` instances on background threads
  with short test timings and always stops them at teardown.
* ``captured_logs`` collects every ``cardflow.*`` record as JSON lines through the
  production formatter.
"""

import io
import logging
import sys
import threading
from collections.abc import Callable, Iterator
from pathlib import Path
from typing import Any, Final

import pytest
from sqlalchemy import text
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker

TESTS_JOBS_DIR: Final = Path(__file__).resolve().parent
if str(TESTS_JOBS_DIR) not in sys.path:
    sys.path.insert(0, str(TESTS_JOBS_DIR))

import jobs_testkit  # noqa: E402
from jobs_helpers import JobsHelper, RunningWorker, make_config  # noqa: E402

from cardflow.jobs import Registry  # noqa: E402
from cardflow.jobs.worker import Worker, WorkerStats  # noqa: E402
from cardflow.log import JsonFormatter  # noqa: E402


@pytest.fixture(scope="session")
def effects_table(db_engine: Engine) -> Iterator[str]:
    """Scratch business table written by test handlers; dropped at the end of the session."""
    with db_engine.begin() as connection:
        connection.execute(text(jobs_testkit.CREATE_EFFECTS))
    yield jobs_testkit.EFFECTS_TABLE
    with db_engine.begin() as connection:
        connection.execute(text(f"DROP TABLE IF EXISTS {jobs_testkit.EFFECTS_TABLE}"))


def _clean(engine: Engine) -> None:
    with engine.begin() as connection:
        connection.execute(text("DELETE FROM jobs"))
        connection.execute(text("DELETE FROM worker_heartbeats"))
        connection.execute(text(f"DELETE FROM {jobs_testkit.EFFECTS_TABLE}"))  # noqa: S608


@pytest.fixture
def jobs_db(db_engine: Engine, effects_table: str) -> Iterator[Engine]:
    """Empty job tables and testkit state around each test; yields the engine."""
    del effects_table
    _clean(db_engine)
    jobs_testkit.reset()
    yield db_engine
    jobs_testkit.reset()
    _clean(db_engine)


@pytest.fixture
def registry() -> Registry:
    """Registry with the testkit kinds (``test.*``) only."""
    return jobs_testkit.build_registry()


@pytest.fixture
def jobs(
    jobs_db: Engine, db_session_factory: sessionmaker[Session], registry: Registry
) -> JobsHelper:
    """Helpers on a clean job table."""
    return JobsHelper(jobs_db, db_session_factory, registry)


@pytest.fixture
def run_worker(
    jobs: JobsHelper, db_session_factory: sessionmaker[Session], registry: Registry
) -> Iterator[Callable[..., RunningWorker]]:
    """Start workers: ``run_worker(once=False, session_factory=..., worker_registry=...,
    periodic_tasks=(...), **WorkerConfig overrides)``; all are stopped at teardown."""
    del jobs  # the job tables are cleaned before the workers start and after they stop
    started: list[RunningWorker] = []

    def start(
        *,
        once: bool = False,
        session_factory: sessionmaker[Session] | None = None,
        worker_registry: Registry | None = None,
        periodic_tasks: tuple[Any, ...] = (),
        **config: object,
    ) -> RunningWorker:
        worker = Worker(
            session_factory or db_session_factory,
            worker_registry or registry,
            make_config(**config),
            periodic_tasks=periodic_tasks,
        )
        result: list[WorkerStats] = []
        thread = threading.Thread(
            target=lambda: result.append(worker.run(once=once)), name="test-worker", daemon=True
        )
        thread.start()
        running = RunningWorker(worker, thread, result)
        started.append(running)
        return running

    yield start
    for running in started:
        if running.thread.is_alive():
            running.worker.request_stop(force=True)
            running.thread.join(30)


@pytest.fixture
def captured_logs() -> Iterator[io.StringIO]:
    """All ``cardflow.*`` records (DEBUG and up) as JSON lines, via the production formatter."""
    stream = io.StringIO()
    handler = logging.StreamHandler(stream)
    handler.setFormatter(JsonFormatter())
    logger = logging.getLogger("cardflow")
    previous_level = logger.level
    logger.addHandler(handler)
    logger.setLevel(logging.DEBUG)
    yield stream
    logger.removeHandler(handler)
    logger.setLevel(previous_level)
