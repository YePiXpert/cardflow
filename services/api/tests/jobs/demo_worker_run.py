"""T-008 evidence: run the real worker for about 30 s on the development PostgreSQL.

What it does (all output on stdout, meant to be tee'd into ``evidence/m0/T-008/``):

1. creates the database ``cardflow_t008_demo`` on the development server (cardflow-dev,
   127.0.0.1:18432 only -- anything else is refused) and migrates it to head;
2. starts ``worker_launcher.py worker --concurrency 2 --shutdown-timeout 15``: the real
   ``cardflow.cli.main`` with the ``demo.*`` kinds of ``jobs_testkit`` registered in that
   process only; the password comes from ``DATABASE_PASSWORD_FILE`` as in production;
3. enqueues demo jobs (successes, a subprocess hard timeout, a handler error with personal
   data in its message, a crash, a permanent failure, a job left behind by a "crashed"
   worker) and prints heartbeat rows and job states every 5 s;
4. enqueues a 16 s job, waits for a heartbeat reporting it (``running_jobs=1``), sends
   SIGTERM at about 30 s while it runs, and checks the worker finishes it and exits 0;
5. prints the final job table and the worker's complete log, scans the log with
   ``tools/pii_scan.py`` and drops the demo database.

Usage, from ``services/api``::

    CARDFLOW_TEST_DATABASE_URL="$(../../tools/dev-db.sh url)" \\
        uv run python tests/jobs/demo_worker_run.py
"""

import os
import secrets
import signal
import subprocess
import sys
import time
from datetime import UTC, datetime
from pathlib import Path
from typing import Final

sys.path.insert(0, str(Path(__file__).resolve().parent))

import jobs_testkit
from jobs_helpers import PII_SCAN, REPO_ROOT, TESTS_JOBS_DIR
from sqlalchemy import text
from sqlalchemy.engine import URL, Engine
from sqlalchemy.pool import NullPool

from cardflow.db import create_engine, create_session_factory, normalize_database_url
from cardflow.db.migrations import head_revisions, upgrade
from cardflow.jobs import enqueue

DEMO_DATABASE: Final = "cardflow_t008_demo"
ALLOWED_HOST: Final = ("127.0.0.1", 18432)
PASSWORD_FILE: Final = REPO_ROOT / "deploy" / "secrets.dev" / "db_password"
LAUNCHER: Final = TESTS_JOBS_DIR / "worker_launcher.py"
RUN_SECONDS: Final = 30
RUN_MARKER_NAME: Final = "CARDFLOW_T008_DEMO_RUN"
RUN_MARKER: Final = secrets.token_hex(6)
REGISTRY: Final = jobs_testkit.build_registry("demo")


def say(message: str) -> None:
    """One transcript line with a UTC timestamp."""
    stamp = datetime.now(UTC).strftime("%H:%M:%S.%f")[:-3]
    sys.stdout.write(f"[{stamp}] {message}\n")
    sys.stdout.flush()


def admin_url() -> URL:
    raw = os.environ.get("CARDFLOW_TEST_DATABASE_URL", "")
    if not raw:
        raise SystemExit("set CARDFLOW_TEST_DATABASE_URL (tools/dev-db.sh url)")
    url = normalize_database_url(raw)
    if (url.host, url.port) != ALLOWED_HOST:
        raise SystemExit("refusing: the demo only runs against cardflow-dev on 127.0.0.1:18432")
    return url


def recreate_database(admin: URL) -> URL:
    engine = create_engine(admin, poolclass=NullPool).execution_options(
        isolation_level="AUTOCOMMIT"
    )
    with engine.connect() as connection:
        connection.execute(text(f'DROP DATABASE IF EXISTS "{DEMO_DATABASE}" WITH (FORCE)'))
        connection.execute(
            text(f"CREATE DATABASE \"{DEMO_DATABASE}\" TEMPLATE template0 ENCODING 'UTF8'")
        )
    engine.dispose()
    url = admin.set(database=DEMO_DATABASE)
    upgrade(url, "head")
    return url


def drop_database(admin: URL) -> None:
    engine = create_engine(admin, poolclass=NullPool).execution_options(
        isolation_level="AUTOCOMMIT"
    )
    with engine.connect() as connection:
        connection.execute(text(f'DROP DATABASE IF EXISTS "{DEMO_DATABASE}" WITH (FORCE)'))
    engine.dispose()


def worker_env(url: URL) -> dict[str, str]:
    env = {
        key: value
        for key, value in os.environ.items()
        if not key.upper().startswith(("DATABASE_", "LOG_", "CARDFLOW_"))
    }
    without_password = URL.create(
        drivername=url.drivername,
        username=url.username,
        host=url.host,
        port=url.port,
        database=url.database,
    )
    env.update(
        DATABASE_URL=without_password.render_as_string(hide_password=False),
        DATABASE_PASSWORD_FILE=str(PASSWORD_FILE),
        LOG_FORMAT="json",
        LOG_LEVEL="info",
        CARDFLOW_VERSION="t008-demo",
        CARDFLOW_TESTKIT_PREFIX="demo",
    )
    env[RUN_MARKER_NAME] = RUN_MARKER
    return env


def enqueue_demo_jobs(engine: Engine) -> dict[str, object]:
    factory = create_session_factory(engine)
    jobs: dict[str, object] = {}
    with factory.begin() as session:

        def add(label: str, kind: str, payload: dict[str, object], **options: object) -> None:
            jobs[label] = enqueue(
                session, kind, payload, workspace_id=None, registry=REGISTRY, **options
            )

        add("inline noop #1", "demo.noop", {})
        add("inline noop #2", "demo.noop", {})
        add("subprocess sum 1..10", "demo.sum", {"values": list(range(1, 11))})
        add("subprocess sleep 4 s", "demo.sleep", {"ms": 4000})
        add(
            "subprocess 60 s, timeout 2 s",
            "demo.sleep",
            {"ms": 60_000},
            timeout_s=2,
            max_attempts=2,
        )
        add("inline error with PII message", "demo.fail_pii", {}, max_attempts=2)
        add("fails once then succeeds", "demo.fail_then_succeed", {"succeed_on": 2})
        add("subprocess crash (os._exit)", "demo.crash", {}, max_attempts=1)
        add("permanent JobError", "demo.child_job_error", {})
        add("left by a crashed worker", "demo.noop", {})
    with engine.begin() as connection:  # make the last one look abandoned by a dead worker
        connection.execute(
            text(
                "UPDATE jobs SET status = 'running', attempts = 1, "
                "locked_by = 'crashed-host:4242:dead', heartbeat_at = now() - interval '5 min', "
                "locked_until = now() - interval '4 min' WHERE id = :id"
            ),
            {"id": jobs["left by a crashed worker"]},
        )
    return jobs


def show_state(engine: Engine) -> None:
    with engine.connect() as connection:
        beats = connection.execute(
            text(
                "SELECT worker_id, pid, version, running_jobs, "
                "round(extract(epoch FROM now() - last_seen_at)::numeric, 1) AS age_s, "
                "to_char(last_seen_at AT TIME ZONE 'UTC', 'HH24:MI:SS') AS last_seen "
                "FROM worker_heartbeats ORDER BY worker_id"
            )
        ).all()
        counts = connection.execute(
            text("SELECT status, count(*) FROM jobs GROUP BY status ORDER BY status")
        ).all()
    for beat in beats:
        say(
            f"  heartbeat worker_id={beat.worker_id} pid={beat.pid} version={beat.version} "
            f"running_jobs={beat.running_jobs} last_seen_at={beat.last_seen}Z "
            f"(age {beat.age_s} s)"
        )
    if not beats:
        say("  heartbeat: no worker_heartbeats row")
    say("  jobs by status: " + ", ".join(f"{row.status}={row.count}" for row in counts))


def running_jobs_reported(engine: Engine) -> int:
    with engine.connect() as connection:
        value = connection.execute(
            text("SELECT coalesce(max(running_jobs), 0) FROM worker_heartbeats")
        ).scalar_one()
    return int(value)


def show_jobs(engine: Engine, labels: dict[object, str]) -> None:
    with engine.connect() as connection:
        rows = connection.execute(
            text(
                "SELECT id, kind, status, attempts, max_attempts, last_error, result "
                "FROM jobs ORDER BY created_at"
            )
        ).all()
    say(f"  {'job':32} {'kind':24} {'status':10} {'att':5} {'last_error':26} result")
    for row in rows:
        result = "" if row.result is None else str(row.result)
        say(
            f"  {labels.get(row.id, '?'):32} {row.kind:24} {row.status:10} "
            f"{row.attempts}/{row.max_attempts:<3} {row.last_error or '-':26} {result}"
        )


def own_processes_running() -> list[int]:
    """PIDs of processes carrying this run's environment marker: the demo worker and any
    job child it spawned (children inherit the environment)."""
    marker = f"{RUN_MARKER_NAME}={RUN_MARKER}".encode()
    found = []
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit() or int(entry.name) == os.getpid():
            continue
        try:
            environ = (entry / "environ").read_bytes()
        except OSError:
            continue
        if marker in environ.split(b"\0"):
            found.append(int(entry.name))
    return found


def main() -> int:
    admin = admin_url()
    say(f"development server {admin.host}:{admin.port}; demo database {DEMO_DATABASE}")
    url = recreate_database(admin)
    say(f"migrated {DEMO_DATABASE} to head {','.join(head_revisions())}")
    engine = create_engine(url)
    log_path = Path(f"/tmp/{DEMO_DATABASE}.worker.log")  # noqa: S108 -- local demo transcript
    exit_code = 1
    try:
        jobs = enqueue_demo_jobs(engine)
        labels = {job_id: label for label, job_id in jobs.items()}
        say(f"enqueued {len(jobs)} demo jobs (one made to look abandoned by a dead worker)")
        argv = [
            sys.executable,
            str(LAUNCHER),
            "worker",
            "--concurrency",
            "2",
            "--shutdown-timeout",
            "15",
        ]
        say("starting: python tests/jobs/worker_launcher.py " + " ".join(argv[2:]))
        with log_path.open("w", encoding="utf-8") as log_file:
            worker = subprocess.Popen(  # noqa: S603
                argv, env=worker_env(url), stdout=log_file, stderr=subprocess.STDOUT
            )
            say(f"worker process pid={worker.pid}")
            started = time.monotonic()
            while time.monotonic() - started < RUN_SECONDS - 12:
                time.sleep(5)
                say(f"t+{time.monotonic() - started:.0f}s")
                show_state(engine)
            factory = create_session_factory(engine)
            with factory.begin() as session:
                last = enqueue(
                    session, "demo.sleep", {"ms": 16_000}, workspace_id=None, registry=REGISTRY
                )
            labels[last] = "in flight at SIGTERM (16 s)"
            say(f"t+{time.monotonic() - started:.0f}s enqueued a 16 s subprocess job")
            wait_until = time.monotonic() + 15
            while time.monotonic() < wait_until and running_jobs_reported(engine) < 1:
                time.sleep(0.5)
            say(f"t+{time.monotonic() - started:.0f}s a heartbeat reports the running job:")
            show_state(engine)
            time.sleep(max(0.0, RUN_SECONDS - (time.monotonic() - started)))
            say(f"t+{time.monotonic() - started:.0f}s")
            show_state(engine)
            say(f"sending SIGTERM to pid {worker.pid}")
            signal_sent = time.monotonic()
            worker.send_signal(signal.SIGTERM)
            returncode = worker.wait(timeout=60)
            say(
                f"worker exited with code {returncode} "
                f"{time.monotonic() - signal_sent:.1f} s after SIGTERM "
                f"(total run {time.monotonic() - started:.1f} s)"
            )
        remaining = own_processes_running()
        say(f"processes of this run still alive (worker, job children): {remaining or 'none'}")
        say("after shutdown:")
        show_state(engine)
        say("final job table:")
        show_jobs(engine, labels)
        log_text = log_path.read_text(encoding="utf-8")
        say(f"worker log ({len(log_text.splitlines())} lines, JSON, stderr+stdout of the worker):")
        sys.stdout.write(log_text)
        say(f"PII scan: python3 -I tools/pii_scan.py {log_path}")
        scan = subprocess.run(  # noqa: S603
            [sys.executable, "-I", str(PII_SCAN), str(log_path)],
            capture_output=True,
            text=True,
            check=False,
        )
        sys.stdout.write(scan.stdout)
        sys.stdout.write(scan.stderr)
        say(f"pii_scan exit code {scan.returncode} (0 = no hits)")
        markers = [marker for marker in jobs_testkit.PII_MARKERS if marker in log_text]
        say(f"synthetic PII markers found in the log: {markers or 'none'}")
        ok = returncode == 0 and scan.returncode == 0 and not markers and not remaining
        exit_code = 0 if ok else 1
    finally:
        engine.dispose()
        drop_database(admin)
        say(f"dropped database {DEMO_DATABASE}")
        log_path.unlink(missing_ok=True)
    say("RESULT: " + ("OK" if exit_code == 0 else "FAILED"))
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
