"""Workspace tables: workspaces, members, consents, idempotency keys, deletion tasks.

``workspaces`` is the tenant root (its ``id`` is the tenant key; row-level security for it
compares ``id``). ``dek_wrapped`` is the workspace data key wrapped by the server KEK
(security-privacy §5); it stays NULL until the crypto module provisions it.

``deletion_tasks.workspace_id`` deliberately has no foreign key: the task record (like
``audit_log``) must outlive the workspace it purges (data-model §9).
"""

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import (
    CHAR,
    CheckConstraint,
    ForeignKeyConstraint,
    Index,
    PrimaryKeyConstraint,
    SmallInteger,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import BYTEA, JSONB
from sqlalchemy.orm import Mapped, mapped_column

from cardflow.db.base import (
    EMPTY_JSON_OBJECT,
    NIL_UUID,
    SHA256_HEX,
    Base,
    SyncColumns,
    now_default,
    uuid_pk,
)


class Workspace(Base):
    """Tenant root; ``kind`` ``demo`` workspaces never sync."""

    __tablename__ = "workspaces"
    __table_args__ = (
        ForeignKeyConstraint(["owner_user_id"], ["users.id"]),
        CheckConstraint("kind IN ('real', 'demo')", name="kind"),
        CheckConstraint(f"id <> {NIL_UUID}", name="id_not_nil"),
        Index("ix_workspaces_owner_user_id", "owner_user_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    owner_user_id: Mapped[uuid.UUID] = mapped_column()
    kind: Mapped[str] = mapped_column()
    dek_wrapped: Mapped[bytes | None] = mapped_column(BYTEA)
    created_at: Mapped[datetime] = now_default()
    deleted_at: Mapped[datetime | None] = mapped_column()


class WorkspaceMember(Base):
    """Membership and role (ADR-011: owner / admin / member)."""

    __tablename__ = "workspace_members"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        UniqueConstraint("workspace_id", "user_id"),
        ForeignKeyConstraint(["workspace_id"], ["workspaces.id"]),
        ForeignKeyConstraint(["user_id"], ["users.id"]),
        CheckConstraint("role IN ('owner', 'admin', 'member')", name="role"),
        Index("ix_workspace_members_user_id", "user_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    user_id: Mapped[uuid.UUID] = mapped_column()
    role: Mapped[str] = mapped_column()
    created_at: Mapped[datetime] = now_default()
    updated_at: Mapped[datetime] = now_default()


class Consent(SyncColumns, Base):
    """Privacy-center consent record (purpose is open-ended: ai_extract, gmail, ...)."""

    __tablename__ = "consents"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(["workspace_id"], ["workspaces.id"]),
        CheckConstraint(
            "withdrawn_at IS NULL OR withdrawn_at >= granted_at", name="withdrawn_after_granted"
        ),
        Index("ix_consents_workspace_id_purpose", "workspace_id", "purpose"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    purpose: Mapped[str] = mapped_column(
        comment=(
            "Open set (ai_extract, gmail, server_sync, analytics ...), data-model §3; no CHECK "
            "by design."
        )
    )
    granted_at: Mapped[datetime] = mapped_column()
    withdrawn_at: Mapped[datetime | None] = mapped_column()
    details: Mapped[Any] = mapped_column(JSONB, server_default=EMPTY_JSON_OBJECT)


class IdempotencyKey(Base):
    """First response of an idempotent write (api-contract §1); PK (workspace_id, key)."""

    __tablename__ = "idempotency_keys"
    __table_args__ = (
        PrimaryKeyConstraint("workspace_id", "key"),
        ForeignKeyConstraint(["workspace_id"], ["workspaces.id"]),
        CheckConstraint(f"request_hash ~ {SHA256_HEX}", name="request_hash_hex"),
        CheckConstraint("response_status BETWEEN 100 AND 599", name="response_status_range"),
        Index("ix_idempotency_keys_created_at", "created_at"),
    )

    workspace_id: Mapped[uuid.UUID] = mapped_column()
    key: Mapped[str] = mapped_column()
    request_hash: Mapped[str] = mapped_column(CHAR(64))
    response_status: Mapped[int] = mapped_column(SmallInteger)
    response_body: Mapped[Any] = mapped_column(JSONB)
    created_at: Mapped[datetime] = now_default()


class DeletionTask(Base):
    """Workspace deletion request with grace period (API-94); outlives the workspace."""

    __tablename__ = "deletion_tasks"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        CheckConstraint("grace_until >= requested_at", name="grace_after_request"),
        CheckConstraint(
            "status IN ('pending', 'cancelled', 'executing', 'executed', 'failed')",
            name="status",
        ),
        Index("ix_deletion_tasks_status_grace_until", "status", "grace_until"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    requested_at: Mapped[datetime] = now_default()
    grace_until: Mapped[datetime] = mapped_column()
    status: Mapped[str] = mapped_column()
    executed_at: Mapped[datetime | None] = mapped_column()
