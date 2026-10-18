"""Job queue and worker heartbeats (ADR-003; used by T-008 worker and T-012 ``/readyz``).

``jobs`` is claimed with ``FOR UPDATE SKIP LOCKED`` in ``run_after, created_at`` order,
read in index order from the partial index ``ix_jobs_queued_run_after_created_at``
(``WHERE status = 'queued'``); expired leases are found through
``ix_jobs_running_locked_until`` (``WHERE status = 'running'``). ``dedupe_key`` (optional)
admits at most one queued or running job per key. Status ``cancelled`` is reserved for the
admin cancel action (admin-console-spec AP-05, not implemented yet; spelling per data-model
§10.12, revision 0003). A running job must
hold a lease (``locked_by`` + ``locked_until``; renewed via ``heartbeat_at``). ``timeout_s`` NULL
means "the default of the job kind". ``workspace_id`` is optional (ownership and admin
visibility) and has no foreign key, so purging a workspace never blocks on job history.

``worker_heartbeats`` is a global system table: one row per worker process, refreshed
periodically; ``/readyz`` treats a ``last_seen_at`` older than two minutes as unhealthy.
"""

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import CheckConstraint, Index, Integer, text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from cardflow.db.base import Base, now_default, uuid_pk

JOB_STATUSES = "('queued', 'running', 'succeeded', 'failed', 'dead', 'cancelled')"


class Job(Base):
    """Persistent background job."""

    __tablename__ = "jobs"
    __table_args__ = (
        CheckConstraint(f"status IN {JOB_STATUSES}", name="status"),
        CheckConstraint("attempts >= 0", name="attempts_non_negative"),
        CheckConstraint("max_attempts >= 1", name="max_attempts_positive"),
        CheckConstraint("timeout_s > 0", name="timeout_positive"),
        CheckConstraint(
            "status <> 'running' OR (locked_by IS NOT NULL AND locked_until IS NOT NULL)",
            name="running_has_lease",
        ),
        Index(
            "ix_jobs_queued_run_after_created_at",
            "run_after",
            "created_at",
            postgresql_where=text("status = 'queued'"),
        ),
        Index(
            "ix_jobs_running_locked_until",
            "locked_until",
            postgresql_where=text("status = 'running'"),
        ),
        Index(
            "uq_jobs_dedupe_key_active",
            "dedupe_key",
            unique=True,
            postgresql_where=text("dedupe_key IS NOT NULL AND status IN ('queued', 'running')"),
        ),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    kind: Mapped[str] = mapped_column(
        comment="Job type registered by the worker; no CHECK by design."
    )
    payload: Mapped[Any] = mapped_column(JSONB)
    status: Mapped[str] = mapped_column(server_default=text("'queued'"))
    run_after: Mapped[datetime] = now_default()
    attempts: Mapped[int] = mapped_column(Integer, server_default=text("0"))
    max_attempts: Mapped[int] = mapped_column(Integer, server_default=text("5"))
    locked_by: Mapped[str | None] = mapped_column()
    locked_until: Mapped[datetime | None] = mapped_column()
    heartbeat_at: Mapped[datetime | None] = mapped_column()
    timeout_s: Mapped[int | None] = mapped_column(Integer)
    last_error: Mapped[str | None] = mapped_column()
    result: Mapped[Any | None] = mapped_column(JSONB)
    workspace_id: Mapped[uuid.UUID | None] = mapped_column()
    created_at: Mapped[datetime] = now_default()
    updated_at: Mapped[datetime] = now_default()
    finished_at: Mapped[datetime | None] = mapped_column()
    dedupe_key: Mapped[str | None] = mapped_column(
        comment=(
            "Optional key; at most one queued or running job per key (e.g. one periodic tick)."
        )
    )


class WorkerHeartbeat(Base):
    """Liveness row of one worker process (system table, no workspace)."""

    __tablename__ = "worker_heartbeats"
    __table_args__ = (
        CheckConstraint("running_jobs >= 0", name="running_jobs_non_negative"),
        Index("ix_worker_heartbeats_last_seen_at", "last_seen_at"),
    )

    worker_id: Mapped[str] = mapped_column(primary_key=True)
    hostname: Mapped[str] = mapped_column()
    pid: Mapped[int] = mapped_column(Integer)
    version: Mapped[str] = mapped_column()
    started_at: Mapped[datetime] = now_default()
    last_seen_at: Mapped[datetime] = now_default()
    running_jobs: Mapped[int] = mapped_column(Integer, server_default=text("0"))
