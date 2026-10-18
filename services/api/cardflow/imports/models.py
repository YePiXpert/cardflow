"""Source documents, parse jobs, extraction candidates, import batches, dedupe keys.

Data-model §1 group 6 (import-spec §2-§5). ``source_documents`` is unique per
(workspace, sha256) among live rows and capped at 25 MiB; the blob itself lives on the
attachments volume under ``storage_key`` encrypted with a per-file key (``dek_wrapped``).
Purging a document wipes ``storage_key`` and ``dek_wrapped`` and tombstones the row, which
stays as the target of the composite foreign keys from attachment references (R2-20).
Every extracted field keeps its raw value, location, parser version and confidence
(``extraction_candidates``) so each posted value can be traced back (R-IMP-04).
"""

import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Any

from sqlalchemy import (
    CHAR,
    BigInteger,
    CheckConstraint,
    ForeignKeyConstraint,
    Index,
    Integer,
    Numeric,
    PrimaryKeyConstraint,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import BYTEA, JSONB
from sqlalchemy.orm import Mapped, mapped_column

from cardflow.db.base import (
    EMPTY_JSON_ARRAY,
    LIVE_ROWS,
    NOW,
    SHA256_HEX,
    Base,
    not_pan,
    now_default,
    uuid_pk,
)

MAX_DOCUMENT_BYTES = 26_214_400  # 25 MiB, import-spec §2


class SourceDocument(Base):
    """Uploaded attachment metadata (synced; the blob stays server-side, encrypted)."""

    __tablename__ = "source_documents"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(["workspace_id"], ["workspaces.id"]),
        CheckConstraint(f"sha256 ~ {SHA256_HEX}", name="sha256_hex"),
        CheckConstraint(
            f"size_bytes > 0 AND size_bytes <= {MAX_DOCUMENT_BYTES}", name="size_limit"
        ),
        CheckConstraint(
            "deleted_at IS NOT NULL OR (storage_key IS NOT NULL AND dek_wrapped IS NOT NULL)",
            name="blob_while_live",
        ),
        Index(
            "uq_source_documents_workspace_id_sha256",
            "workspace_id",
            "sha256",
            unique=True,
            postgresql_where=LIVE_ROWS,
        ),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    sha256: Mapped[str] = mapped_column(CHAR(64))
    mime: Mapped[str] = mapped_column()
    size_bytes: Mapped[int] = mapped_column(BigInteger)
    storage_key: Mapped[str | None] = mapped_column()
    dek_wrapped: Mapped[bytes | None] = mapped_column(BYTEA)
    uploaded_by_device_id: Mapped[uuid.UUID | None] = mapped_column()
    retention_until: Mapped[date | None] = mapped_column()
    deleted_at: Mapped[datetime | None] = mapped_column()
    created_at: Mapped[datetime] = now_default()
    # Sync columns (deleted_at above doubles as the tombstone).
    row_version: Mapped[int] = mapped_column(BigInteger, server_default=text("1"))
    updated_at: Mapped[datetime] = mapped_column(server_default=NOW)
    origin_device_id: Mapped[uuid.UUID | None] = mapped_column()


class ImportBatch(Base):
    """Import batch (PRD §6.4 status) - server-side workflow, rolled back with tombstones."""

    __tablename__ = "import_batches"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(["workspace_id"], ["workspaces.id"]),
        ForeignKeyConstraint(
            ["workspace_id", "target_currency_account_id"],
            ["currency_accounts.workspace_id", "currency_accounts.id"],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "source_document_id"],
            ["source_documents.workspace_id", "source_documents.id"],
        ),
        CheckConstraint(
            "status IN ('uploaded', 'parsing', 'needs_review', 'confirmed', 'posted', 'failed', "
            "'rolled_back')",
            name="status",
        ),
        not_pan("failure_reason"),
        Index("ix_import_batches_target_currency_account_id", "target_currency_account_id"),
        Index("ix_import_batches_source_document_id", "source_document_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    kind: Mapped[str] = mapped_column(
        comment=(
            "Open set of import channels (csv, pdf, text, screenshot, eml, html, sms ...); no "
            "CHECK by design."
        )
    )
    status: Mapped[str] = mapped_column()
    target_currency_account_id: Mapped[uuid.UUID | None] = mapped_column()
    source_document_id: Mapped[uuid.UUID | None] = mapped_column()
    failure_reason: Mapped[str | None] = mapped_column()
    created_at: Mapped[datetime] = now_default()
    updated_at: Mapped[datetime] = now_default()
    confirmed_at: Mapped[datetime | None] = mapped_column()
    posted_at: Mapped[datetime | None] = mapped_column()
    rolled_back_at: Mapped[datetime | None] = mapped_column()


class ParseJob(Base):
    """One parse attempt chain of a document (the queue entry itself is in ``jobs``)."""

    __tablename__ = "parse_jobs"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(
            ["workspace_id", "source_document_id"],
            ["source_documents.workspace_id", "source_documents.id"],
        ),
        ForeignKeyConstraint(
            ["workspace_id", "import_batch_id"],
            ["import_batches.workspace_id", "import_batches.id"],
        ),
        CheckConstraint("attempts >= 0", name="attempts_non_negative"),
        CheckConstraint(
            "status IN ('queued', 'running', 'succeeded', 'failed', 'quarantined')", name="status"
        ),
        not_pan("failure_reason"),
        Index("ix_parse_jobs_source_document_id", "source_document_id"),
        Index("ix_parse_jobs_import_batch_id", "import_batch_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    source_document_id: Mapped[uuid.UUID] = mapped_column()
    import_batch_id: Mapped[uuid.UUID | None] = mapped_column()
    job_id: Mapped[uuid.UUID | None] = mapped_column()
    parser: Mapped[str | None] = mapped_column()
    parser_version: Mapped[str | None] = mapped_column()
    status: Mapped[str] = mapped_column()
    attempts: Mapped[int] = mapped_column(Integer, server_default=text("0"))
    failure_reason: Mapped[str | None] = mapped_column()
    started_at: Mapped[datetime | None] = mapped_column()
    finished_at: Mapped[datetime | None] = mapped_column()
    created_at: Mapped[datetime] = now_default()
    updated_at: Mapped[datetime] = now_default()


class ExtractionCandidate(Base):
    """One extracted field with provenance (import-spec §3)."""

    __tablename__ = "extraction_candidates"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        ForeignKeyConstraint(
            ["workspace_id", "parse_job_id"], ["parse_jobs.workspace_id", "parse_jobs.id"]
        ),
        CheckConstraint("confidence BETWEEN 0 AND 1", name="confidence_range"),
        CheckConstraint(
            "field_path ~ '(^|[.])bank_reference$' OR NOT (looks_like_pan(raw_value)"
            " OR looks_like_pan(normalized_value) OR looks_like_pan(confirmed_value))",
            name="values_not_pan",
        ),
        Index("ix_extraction_candidates_parse_job_id", "parse_job_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    parse_job_id: Mapped[uuid.UUID] = mapped_column()
    field_path: Mapped[str] = mapped_column()
    raw_value: Mapped[str | None] = mapped_column()
    normalized_value: Mapped[str | None] = mapped_column()
    raw_location: Mapped[Any] = mapped_column(JSONB)
    parser_version: Mapped[str] = mapped_column()
    confidence: Mapped[Decimal] = mapped_column(Numeric(5, 4))
    validations: Mapped[Any] = mapped_column(JSONB, server_default=EMPTY_JSON_ARRAY)
    confirmed_value: Mapped[str | None] = mapped_column()
    confirmed_by: Mapped[str | None] = mapped_column()
    confirmed_at: Mapped[datetime | None] = mapped_column()
    created_at: Mapped[datetime] = now_default()


class ImportBatchItem(Base):
    """One reviewed item of a batch: decision and the entity it produced."""

    __tablename__ = "import_batch_items"
    __table_args__ = (
        UniqueConstraint("workspace_id", "id"),
        UniqueConstraint("import_batch_id", "item_no"),
        ForeignKeyConstraint(
            ["workspace_id", "import_batch_id"],
            ["import_batches.workspace_id", "import_batches.id"],
        ),
        CheckConstraint("item_no >= 1", name="item_no_positive"),
        CheckConstraint("decision IN ('new', 'duplicate', 'new_version', 'skip')", name="decision"),
        CheckConstraint(
            "decision IS DISTINCT FROM 'duplicate' OR duplicate_of_id IS NOT NULL",
            name="duplicate_needs_target",
        ),
        CheckConstraint(
            "(resulting_entity_kind IS NULL) = (resulting_entity_id IS NULL)",
            name="resulting_entity_pair",
        ),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    workspace_id: Mapped[uuid.UUID] = mapped_column()
    import_batch_id: Mapped[uuid.UUID] = mapped_column()
    item_no: Mapped[int] = mapped_column(Integer)
    entity_kind: Mapped[str] = mapped_column()
    candidate_refs: Mapped[Any] = mapped_column(JSONB, server_default=EMPTY_JSON_ARRAY)
    decision: Mapped[str | None] = mapped_column()
    duplicate_of_id: Mapped[uuid.UUID | None] = mapped_column()
    resulting_entity_kind: Mapped[str | None] = mapped_column()
    resulting_entity_id: Mapped[uuid.UUID | None] = mapped_column()
    created_at: Mapped[datetime] = now_default()
    updated_at: Mapped[datetime] = now_default()


class DedupeKey(Base):
    """Idempotent-import key (import-spec §5); PK (workspace_id, key_hash)."""

    __tablename__ = "dedupe_keys"
    __table_args__ = (
        PrimaryKeyConstraint("workspace_id", "key_hash"),
        ForeignKeyConstraint(["workspace_id"], ["workspaces.id"]),
        CheckConstraint(f"key_hash ~ {SHA256_HEX}", name="key_hash_hex"),
    )

    workspace_id: Mapped[uuid.UUID] = mapped_column()
    key_hash: Mapped[str] = mapped_column(CHAR(64))
    entity_kind: Mapped[str] = mapped_column(
        comment="Table name of the deduplicated entity; no CHECK by design."
    )
    entity_id: Mapped[uuid.UUID] = mapped_column()
    created_at: Mapped[datetime] = now_default()
