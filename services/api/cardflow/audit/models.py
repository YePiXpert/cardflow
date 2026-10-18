"""Audit log (security-privacy SEC-S-09, ADR-014): who did what to which row; hashes only.

``workspace_id`` is nullable (system/admin actions) and has no foreign key on purpose:
audit rows are kept (as hashes) after a workspace is purged (data-model §9).
"""

import uuid
from datetime import datetime

from sqlalchemy import CHAR, CheckConstraint, Index
from sqlalchemy.dialects.postgresql import INET
from sqlalchemy.orm import Mapped, mapped_column

from cardflow.db.base import SHA256_HEX, Base, now_default, uuid_pk


class AuditLog(Base):
    """One audited action; never stores record bodies, only before/after hashes."""

    __tablename__ = "audit_log"
    __table_args__ = (
        CheckConstraint(f"before_hash ~ {SHA256_HEX}", name="before_hash_hex"),
        CheckConstraint(f"after_hash ~ {SHA256_HEX}", name="after_hash_hex"),
        Index("ix_audit_log_workspace_id_at", "workspace_id", "at"),
        Index("ix_audit_log_at", "at"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID | None] = mapped_column()
    actor_kind: Mapped[str] = mapped_column(
        comment="Open set (user, device, admin, system ...); no CHECK by design."
    )
    actor_id: Mapped[uuid.UUID | None] = mapped_column()
    action: Mapped[str] = mapped_column()
    target_table: Mapped[str | None] = mapped_column()
    target_id: Mapped[uuid.UUID | None] = mapped_column()
    before_hash: Mapped[str | None] = mapped_column(CHAR(64))
    after_hash: Mapped[str | None] = mapped_column(CHAR(64))
    ip: Mapped[str | None] = mapped_column(INET)
    at: Mapped[datetime] = now_default()
