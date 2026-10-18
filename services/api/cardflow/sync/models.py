"""Sync change log and conflicts (architecture §6, ADR-007, API-90/91/92).

``sync_changes.seq`` (BIGSERIAL) is taken at INSERT time, not at COMMIT, so neither seq
alone nor "stop at the first in-flight txid" is a lossless cursor (a transaction can hold a
lower seq than a committed one while being invisible). ``txid`` (xid8, the writer's
top-level transaction id, migration 0002) makes one: pull rows with
``txid < pg_snapshot_xmin(pg_current_snapshot())`` ordered by ``(txid, seq)`` and keep
``(txid, seq)`` as the cursor; every transaction below the snapshot xmin has finished, so
no row can appear behind the cursor later (see tests/db/test_r2_fixes.py, R2-07).
"""

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    ForeignKeyConstraint,
    Index,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from cardflow.db.base import EMPTY_JSON_ARRAY, Base, Xid8, now_default, uuid_pk


class SyncChange(Base):
    """One accepted change (insert/update/delete tombstone) in pull order."""

    __tablename__ = "sync_changes"
    __table_args__ = (
        ForeignKeyConstraint(["workspace_id"], ["workspaces.id"]),
        CheckConstraint("op IN ('insert', 'update', 'delete')", name="op"),
        Index("ix_sync_changes_workspace_id_seq", "workspace_id", "seq"),
        Index("ix_sync_changes_workspace_id_txid_seq", "workspace_id", "txid", "seq"),
    )

    seq: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    table_name: Mapped[str] = mapped_column()
    row_id: Mapped[uuid.UUID] = mapped_column()
    op: Mapped[str] = mapped_column()
    row_version: Mapped[int] = mapped_column(BigInteger)
    payload: Mapped[Any | None] = mapped_column(JSONB)
    origin_device_id: Mapped[uuid.UUID | None] = mapped_column()
    created_at: Mapped[datetime] = now_default()
    txid: Mapped[int] = mapped_column(
        Xid8(),
        server_default=text("pg_current_xact_id()"),
        comment=(
            "Top-level transaction id of the writer. Pull with cursor (txid, seq) over rows "
            "whose txid < pg_snapshot_xmin(pg_current_snapshot()); seq alone is assigned at "
            "INSERT, not at COMMIT."
        ),
    )


class SyncConflict(Base):
    """A pushed change rejected because money/date/status fields diverged (not written)."""

    __tablename__ = "sync_conflicts"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(["workspace_id"], ["workspaces.id"]),
        CheckConstraint("status IN ('open', 'resolved')", name="status"),
        Index(
            "ix_sync_conflicts_workspace_id_table_name_row_id",
            "workspace_id",
            "table_name",
            "row_id",
        ),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    origin_device_id: Mapped[uuid.UUID | None] = mapped_column()
    table_name: Mapped[str] = mapped_column()
    row_id: Mapped[uuid.UUID] = mapped_column()
    server_version: Mapped[int] = mapped_column(BigInteger)
    client_base_version: Mapped[int] = mapped_column(BigInteger)
    fields: Mapped[Any] = mapped_column(JSONB, server_default=EMPTY_JSON_ARRAY)
    server_payload: Mapped[Any] = mapped_column(JSONB)
    client_payload: Mapped[Any] = mapped_column(JSONB)
    status: Mapped[str] = mapped_column()
    resolved_by: Mapped[str | None] = mapped_column()
    resolved_at: Mapped[datetime | None] = mapped_column()
    created_at: Mapped[datetime] = now_default()
