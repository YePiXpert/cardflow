"""Identity tables: users, devices and refresh-token sessions (ADR-011, data-model §1 group 1).

* ``users`` is global (no workspace_id): an optional e-mail/password account; device-only
  installations get a user row without e-mail.
* ``devices`` belong to one workspace; ``public_key`` holds the device's public key
  (DER SubjectPublicKeyInfo recommended); revocation is ``revoked_at``.
* ``auth_sessions`` store only the SHA-256 hex of a refresh token. Rotation creates a new
  row with ``rotated_from_id`` = the old row; ``UNIQUE (rotated_from_id)`` makes a token
  rotatable at most once, so two concurrent refreshes with the same token cannot both win
  (reuse detection). ``idempotency_key_hash`` (0004) records the Idempotency-Key of the
  request that issued the session (cardflow/identity/service.py).
* ``pairing_codes`` (0004, T-011) hold the SHA-256 of one-time pairing codes; a code with
  ``workspace_id`` NULL bootstraps a new workspace, otherwise it joins that workspace.
"""

import uuid
from datetime import datetime

from sqlalchemy import (
    CHAR,
    CheckConstraint,
    ForeignKeyConstraint,
    Index,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import BYTEA
from sqlalchemy.orm import Mapped, mapped_column

from cardflow.db.base import SHA256_HEX, Base, not_pan, now_default, uuid_pk


class User(Base):
    """Global identity; e-mail and password are optional (device-first onboarding)."""

    __tablename__ = "users"
    __table_args__ = (
        UniqueConstraint("email"),
        CheckConstraint("email = lower(email)", name="email_lowercase"),
        CheckConstraint("password_hash IS NULL OR email IS NOT NULL", name="password_needs_email"),
        CheckConstraint(
            "password_hash IS NULL OR password_hash LIKE '$argon2id$%'", name="password_argon2id"
        ),
        CheckConstraint("email <> ''", name="email_not_empty"),
        not_pan("display_name"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    email: Mapped[str | None] = mapped_column()
    password_hash: Mapped[str | None] = mapped_column()
    display_name: Mapped[str | None] = mapped_column()
    created_at: Mapped[datetime] = now_default()
    updated_at: Mapped[datetime] = now_default()
    disabled_at: Mapped[datetime | None] = mapped_column()
    deleted_at: Mapped[datetime | None] = mapped_column()


class Device(Base):
    """A registered mobile device of one workspace."""

    __tablename__ = "devices"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(["workspace_id"], ["workspaces.id"]),
        ForeignKeyConstraint(["user_id"], ["users.id"]),
        CheckConstraint("octet_length(public_key) BETWEEN 32 AND 4096", name="public_key_length"),
        not_pan("name"),
        CheckConstraint("app_version ~ '^[0-9A-Za-z.+-]{1,64}$'", name="app_version_format"),
        not_pan("app_version"),
        Index("ix_devices_user_id", "user_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    user_id: Mapped[uuid.UUID | None] = mapped_column()
    name: Mapped[str | None] = mapped_column()
    platform: Mapped[str] = mapped_column(
        comment="Open set (ios, android ...); no CHECK by design."
    )
    public_key: Mapped[bytes] = mapped_column(BYTEA)
    created_at: Mapped[datetime] = now_default()
    last_seen_at: Mapped[datetime | None] = mapped_column()
    revoked_at: Mapped[datetime | None] = mapped_column()
    app_version: Mapped[str | None] = mapped_column(
        comment="App version reported at registration or refresh."
    )


class AuthSession(Base):
    """Refresh-token session of a device; the token itself is never stored."""

    __tablename__ = "auth_sessions"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        UniqueConstraint("refresh_token_hash"),
        UniqueConstraint("rotated_from_id"),
        ForeignKeyConstraint(["workspace_id", "device_id"], ["devices.workspace_id", "devices.id"]),
        ForeignKeyConstraint(
            ["workspace_id", "rotated_from_id"],
            ["auth_sessions.workspace_id", "auth_sessions.id"],
        ),
        CheckConstraint(f"refresh_token_hash ~ {SHA256_HEX}", name="refresh_token_hash_hex"),
        CheckConstraint("expires_at > created_at", name="expires_after_created"),
        CheckConstraint(
            "revoked_reason IS NULL OR revoked_at IS NOT NULL", name="reason_needs_revocation"
        ),
        CheckConstraint(
            "rotated_from_id IS NULL OR rotated_from_id <> id", name="not_rotated_from_self"
        ),
        CheckConstraint(f"idempotency_key_hash ~ {SHA256_HEX}", name="idempotency_key_hash_hex"),
        Index("ix_auth_sessions_device_id", "device_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    device_id: Mapped[uuid.UUID] = mapped_column()
    refresh_token_hash: Mapped[str] = mapped_column(CHAR(64))
    rotated_from_id: Mapped[uuid.UUID | None] = mapped_column()
    created_at: Mapped[datetime] = now_default()
    expires_at: Mapped[datetime] = mapped_column()
    last_used_at: Mapped[datetime | None] = mapped_column()
    revoked_at: Mapped[datetime | None] = mapped_column()
    revoked_reason: Mapped[str | None] = mapped_column()
    idempotency_key_hash: Mapped[str | None] = mapped_column(
        CHAR(64),
        comment=(
            "SHA-256 of the Idempotency-Key of the request that issued this session "
            "(registration or refresh); a retried request may replace a session whose response "
            "the client never received."
        ),
    )


class PairingCode(Base):
    """One-time pairing code (API-01); only its SHA-256 is stored (migration 0004)."""

    __tablename__ = "pairing_codes"
    __table_args__ = (
        UniqueConstraint("code_hash"),
        ForeignKeyConstraint(["workspace_id"], ["workspaces.id"]),
        ForeignKeyConstraint(
            ["used_workspace_id", "used_by_device_id"], ["devices.workspace_id", "devices.id"]
        ),
        CheckConstraint("purpose IN ('bootstrap_workspace', 'join_workspace')", name="purpose"),
        CheckConstraint(
            "(purpose = 'bootstrap_workspace') = (workspace_id IS NULL)",
            name="workspace_matches_purpose",
        ),
        CheckConstraint("created_via IN ('cli', 'admin', 'device')", name="created_via"),
        CheckConstraint(f"code_hash ~ {SHA256_HEX}", name="code_hash_hex"),
        CheckConstraint(f"used_key_hash ~ {SHA256_HEX}", name="used_key_hash_hex"),
        CheckConstraint(f"used_request_hash ~ {SHA256_HEX}", name="used_request_hash_hex"),
        CheckConstraint(
            "expires_at > created_at AND expires_at <= created_at + interval '24 hours'",
            name="lifetime",
        ),
        CheckConstraint(
            "num_nulls(used_at, used_workspace_id, used_by_device_id, used_key_hash, "
            "used_request_hash) IN (0, 5)",
            name="use_recorded_together",
        ),
        CheckConstraint("used_at <= expires_at", name="used_before_expiry"),
        CheckConstraint(
            "workspace_id IS NULL OR used_workspace_id = workspace_id",
            name="used_in_own_workspace",
        ),
        Index("ix_pairing_codes_workspace_id", "workspace_id"),
        Index(
            "ix_pairing_codes_used_workspace_id_used_by_device_id",
            "used_workspace_id",
            "used_by_device_id",
        ),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    purpose: Mapped[str] = mapped_column()
    workspace_id: Mapped[uuid.UUID | None] = mapped_column(
        comment=(
            "Workspace a join code adds a device to; NULL for a bootstrap code, which creates "
            "a new workspace."
        )
    )
    code_hash: Mapped[str] = mapped_column(
        CHAR(64),
        comment="SHA-256 (hex) of the normalised pairing code; the code itself is never stored.",
    )
    created_via: Mapped[str] = mapped_column(
        comment=(
            "Who created the code: cli (operator on the server); admin and device are reserved "
            "for the admin console and for invitations from an existing device."
        )
    )
    created_at: Mapped[datetime] = now_default()
    expires_at: Mapped[datetime] = mapped_column()
    used_at: Mapped[datetime | None] = mapped_column()
    used_workspace_id: Mapped[uuid.UUID | None] = mapped_column(
        comment=(
            "Workspace the code was used for: the new workspace of a bootstrap code, the code's "
            "own workspace of a join code."
        )
    )
    used_by_device_id: Mapped[uuid.UUID | None] = mapped_column()
    used_key_hash: Mapped[str | None] = mapped_column(
        CHAR(64),
        comment=(
            "SHA-256 of the Idempotency-Key of the registration that used the code (replay check)."
        ),
    )
    used_request_hash: Mapped[str | None] = mapped_column(
        CHAR(64),
        comment="SHA-256 of the canonical registration request without the code (replay check).",
    )
