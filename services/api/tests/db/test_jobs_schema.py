"""Job-queue schema decisions folded into revisions 0002/0003 after the T-008 review.

* ``jobs.status`` admits ``cancelled`` (admin-console-spec AP-05 lists it; the cancel action
  itself comes later). 0002 spelled it ``canceled``; 0003 corrected the spelling
  (data-model §10.12).
* The claim index follows the worker's ``ORDER BY run_after, created_at``; the lease-reclaim
  index (R2-27) follows ``ORDER BY locked_until``.

Each test shows revision 0001 (``engine_0001``) first, then head. The queries are the
worker's own (``cardflow.jobs.queue``), imported inside the tests so that a change there is
checked against the indexes here.
"""

from typing import Final

import pytest
from sqlalchemy import insert, text
from sqlalchemy.engine import Engine
from sqlalchemy.exc import DBAPIError
from sqlalchemy.sql.elements import TextClause

from cardflow.db.models import metadata

pytestmark = [pytest.mark.db, pytest.mark.usefixtures("require_head_schema")]

T: Final = metadata.tables
CHECK_VIOLATION: Final = "23514"


def insert_job(engine: Engine, status: str) -> tuple[str | None, str | None]:
    """Insert a job with ``status`` (rolled back); return (SQLSTATE, constraint) or Nones."""
    with engine.connect() as connection, connection.begin() as transaction:
        try:
            connection.execute(
                insert(T["jobs"]).values(kind="test.kind", payload={}, status=status)
            )
        except DBAPIError as exc:
            diag = getattr(exc.orig, "diag", None)
            return getattr(exc.orig, "sqlstate", None), getattr(diag, "constraint_name", None)
        finally:
            transaction.rollback()
    return None, None


def test_jobs_status_admits_cancelled(engine_0001: Engine, db_engine: Engine) -> None:
    """Coordinator ruling (AP-05, data-model §10.12): 0001 knew neither spelling; head admits
    'cancelled' only (0002's 'canceled' was renamed by 0003)."""
    assert insert_job(engine_0001, "cancelled") == (CHECK_VIOLATION, "ck_jobs_status")
    assert insert_job(engine_0001, "canceled") == (CHECK_VIOLATION, "ck_jobs_status")
    assert insert_job(db_engine, "cancelled") == (None, None)
    assert insert_job(db_engine, "canceled") == (CHECK_VIOLATION, "ck_jobs_status")


def plan_of(engine: Engine, query: TextClause, values: dict[str, str]) -> str:
    """``EXPLAIN (COSTS OFF)`` of ``query`` with literal values, sequential and bitmap scans
    disabled so that the planner shows which index (and whether a sort) serves the order."""
    sql = query.text
    for name, literal in values.items():
        sql = sql.replace(f":{name}", literal)
    with engine.connect() as connection, connection.begin() as transaction:
        connection.execute(text("SET LOCAL enable_seqscan = off"))
        connection.execute(text("SET LOCAL enable_bitmapscan = off"))
        lines = connection.execute(text(f"EXPLAIN (COSTS OFF) {sql}")).scalars().all()
        transaction.rollback()
    return "\n".join(lines)


def test_claim_query_reads_the_queue_index_in_order(engine_0001: Engine, db_engine: Engine) -> None:
    """Coordinator ruling (T-008): the claim order run_after, created_at comes straight from
    ix_jobs_queued_run_after_created_at; 0001's (status, run_after) index needed a sort."""
    from cardflow.jobs.queue import _SELECT_CLAIMABLE

    values = {"kinds": "ARRAY['test.kind']::text[]", "limit": "10"}
    old = plan_of(engine_0001, _SELECT_CLAIMABLE, values)
    new = plan_of(db_engine, _SELECT_CLAIMABLE, values)

    assert "ix_jobs_status_run_after" in old
    assert "Sort" in old
    assert "ix_jobs_queued_run_after_created_at" in new
    assert "Sort" not in new


def test_r2_27_reclaim_query_reads_the_lease_index(engine_0001: Engine, db_engine: Engine) -> None:
    """R2-27: expired leases (ORDER BY locked_until) had no index at 0001."""
    from cardflow.jobs.queue import _SELECT_EXPIRED

    old = plan_of(engine_0001, _SELECT_EXPIRED, {"limit": "10"})
    new = plan_of(db_engine, _SELECT_EXPIRED, {"limit": "10"})

    assert "ix_jobs_running_locked_until" not in old
    assert "ix_jobs_running_locked_until" in new
    assert "Sort" not in new
