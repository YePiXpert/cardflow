#!/usr/bin/env bash
# T-008 evidence run. Working dir services/api; dev DB cardflow-dev on 127.0.0.1:18432.
set -u
cd /projects/cardflow/services/api
EV=/projects/cardflow/evidence/m0/T-008
URL="$(../../tools/dev-db.sh url)"
unset CARDFLOW_TEST_MIGRATION_TARGET
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
head_rev() { uv run python -c "from cardflow.db.migrations import head_revisions; print(','.join(head_revisions()))"; }

{
  echo "# T-008 ruff - $(now), working dir services/api"
  echo '$ uv run ruff check .'
  uv run ruff check .; echo "exit=$?"
  echo '$ uv run ruff format --check .'
  uv run ruff format --check .; echo "exit=$?"
} 2>&1 | tee "$EV/ruff.txt"

{
  echo "# T-008 jobs tests - $(now), working dir services/api, dev DB 127.0.0.1:18432, schema at Alembic head $(head_rev) (CARDFLOW_TEST_MIGRATION_TARGET unset)"
  echo '$ CARDFLOW_TEST_DATABASE_URL="$(../../tools/dev-db.sh url)" uv run pytest tests/jobs -v'
  CARDFLOW_TEST_DATABASE_URL="$URL" uv run pytest tests/jobs -v -p no:cacheprovider; echo "exit=$?"
} 2>&1 | tee "$EV/pytest-jobs.txt"

{
  echo "# T-008 TC-DB-10 concurrency statistics - $(now), working dir services/api, head $(head_rev)"
  echo '$ CARDFLOW_TEST_DATABASE_URL="$(../../tools/dev-db.sh url)" uv run pytest tests/jobs/test_concurrency.py -v -s'
  CARDFLOW_TEST_DATABASE_URL="$URL" uv run pytest tests/jobs/test_concurrency.py -v -s -p no:cacheprovider; echo "exit=$?"
} 2>&1 | tee "$EV/concurrency-stats.txt"

{
  echo "# T-008 timeouts, crashes and forced stops - $(now), working dir services/api, head $(head_rev)"
  echo "# subprocess hard timeout (SIGTERM, then SIGKILL for a child ignoring SIGTERM), crash, spawn failure,"
  echo "# inline cooperative/stuck timeouts, and shutdown-grace expiry (in-process and via SIGTERM/SIGINT)."
  echo '$ CARDFLOW_TEST_DATABASE_URL="$(../../tools/dev-db.sh url)" uv run pytest tests/jobs -v -s -k "timeout or sigterm or crash or cannot_start or grace or second"'
  CARDFLOW_TEST_DATABASE_URL="$URL" uv run pytest tests/jobs -v -s -p no:cacheprovider -k "timeout or sigterm or crash or cannot_start or grace or second"; echo "exit=$?"
} 2>&1 | tee "$EV/timeout.txt"

{
  echo "# T-008 full test suite - $(now), working dir services/api, dev DB 127.0.0.1:18432, schema at head $(head_rev)"
  echo '$ CARDFLOW_TEST_DATABASE_URL="$(../../tools/dev-db.sh url)" uv run pytest -q'
  CARDFLOW_TEST_DATABASE_URL="$URL" uv run pytest -q -p no:cacheprovider; echo "exit=$?"
  echo
  echo "# collected tests per directory/file (uv run pytest --co -q | aggregated):"
  uv run pytest --co -q -p no:cacheprovider 2>/dev/null | grep '::' | cut -d: -f1 | sed -E 's#^(tests/[^/]+)/.*#\1#' | sort | uniq -c
} 2>&1 | tee "$EV/pytest.txt"

{
  echo "# T-008 worker run on the development PostgreSQL - $(now), working dir services/api"
  echo "# real cardflow.cli.main (tests/jobs/worker_launcher.py registers the demo.* kinds in its own process only)"
  echo '$ CARDFLOW_TEST_DATABASE_URL="$(../../tools/dev-db.sh url)" uv run python tests/jobs/demo_worker_run.py'
  CARDFLOW_TEST_DATABASE_URL="$URL" uv run python tests/jobs/demo_worker_run.py; echo "exit=$?"
} 2>&1 | tee "$EV/worker-run.txt"
