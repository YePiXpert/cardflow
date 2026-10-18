"""Declarative base, naming convention and shared column helpers for the ORM models.

Every ``cardflow/<module>/models.py`` imports :class:`Base` from here and
:mod:`cardflow.db.models` imports all of those modules, so ``Base.metadata`` describes the
whole schema. The Alembic migrations (``services/api/alembic/versions``) are the source of
truth: they spell out every constraint and index name explicitly, and
``tests/db/test_model_drift.py`` proves that these models -- through
:data:`NAMING_CONVENTION` -- produce the same tables, columns, types, defaults and names.

Conventions (data-model §3/§4, ADR-008, architecture §6):

* Primary keys are ``UUID DEFAULT uuidv7()`` (PostgreSQL 18 native function).
* Money is ``*_minor BIGINT`` plus a currency (on the row or on its parent); rates and
  scale factors are ``NUMERIC(20,10)``. No float/double/real/money column exists.
* Timestamps are ``TIMESTAMPTZ``.
* Tenant tables carry ``workspace_id`` and ``UNIQUE (workspace_id, id)``; children
  reference parents through composite foreign keys ``(workspace_id, parent_id)``.
* Syncable tables carry :class:`SyncColumns`; their row_version/updated_at are maintained
  by the database (trigger ``<table>_row_version``, migration 0002).
* Free-text columns carry :func:`not_pan` (no card numbers, data-model §10.9).
"""

import uuid
from datetime import date, datetime, time
from decimal import Decimal
from typing import Any, ClassVar, Final

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKeyConstraint,
    MetaData,
    Numeric,
    Text,
    Time,
    Uuid,
    text,
)
from sqlalchemy.dialects.postgresql.base import ischema_names
from sqlalchemy.orm import DeclarativeBase, Mapped, MappedColumn, mapped_column
from sqlalchemy.sql.elements import TextClause
from sqlalchemy.sql.schema import Constraint, Table
from sqlalchemy.types import UserDefinedType

UUIDV7: Final[TextClause] = text("uuidv7()")
NOW: Final[TextClause] = text("now()")
EMPTY_JSON_OBJECT: Final[TextClause] = text("'{}'::jsonb")
EMPTY_JSON_ARRAY: Final[TextClause] = text("'[]'::jsonb")

# Value sets shared by several tables (data-model §4).
CONFIRMATION_LEVELS: Final = "('system_estimated', 'user_confirmed', 'bank_confirmed')"
TIME_PRECISIONS: Final = "('datetime', 'date', 'month')"
CASH_EVENT_CATEGORIES: Final = (
    "('income', 'bill', 'living', 'repayment', 'transfer_in', 'transfer_out', 'fee', 'other')"
)
CASH_EVENT_CLASSES: Final = "('confirmed', 'expected', 'planned')"
LIMIT_SOURCE_KINDS: Final = "('bank_app', 'statement', 'user', 'import')"
SHA256_HEX: Final = "'^[0-9a-f]{64}$'"
NIL_UUID: Final = "'00000000-0000-0000-0000-000000000000'::uuid"
LIVE_ROWS: Final[TextClause] = text("deleted_at IS NULL")
"""Predicate of the partial unique indexes on natural keys (tombstones excluded)."""
OPEN_SOURCES_COMMENT: Final = (
    "Open set of data sources (manual, csv, pdf, email, screenshot, sms, bank_app, "
    "import ...); no CHECK by design."
)


class Xid8(UserDefinedType[int]):
    """PostgreSQL ``xid8`` (64-bit transaction id), used by ``sync_changes.txid``."""

    cache_ok = True

    def get_col_spec(self, **kw: object) -> str:
        """DDL type name."""
        del kw
        return "xid8"


# Let reflection (model-drift test, Alembic) recognise the type instead of NullType.
ischema_names.setdefault("xid8", Xid8)


def not_pan(column: str) -> CheckConstraint:
    """``CHECK (NOT looks_like_pan(<column>))`` -- no card numbers in free text (R2-09).

    ``looks_like_pan()`` is created by migration 0002.
    """
    return CheckConstraint(f"NOT looks_like_pan({column})", name=f"{column}_not_pan")


def _fk_columns(constraint: Constraint, table: Table) -> str:
    """Naming-convention token: the local FK columns, without ``workspace_id``.

    Composite tenant keys always start with ``workspace_id``; leaving it out keeps names
    short and still unique per table (``fk_cash_transfers_from_cash_account_id``). A
    plain ``workspace_id -> workspaces.id`` key keeps its only column.
    """
    del table
    if not isinstance(constraint, ForeignKeyConstraint):
        raise TypeError(f"fk_columns token used for {type(constraint).__name__}")
    names = [element.parent.name for element in constraint.elements if element.parent is not None]
    return "_".join(name for name in names if name != "workspace_id") or "workspace_id"


NAMING_CONVENTION: Final[dict[str, Any]] = {
    "fk_columns": _fk_columns,
    "pk": "pk_%(table_name)s",
    "uq": "uq_%(table_name)s_%(column_0_N_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(fk_columns)s",
    "ix": "ix_%(table_name)s_%(column_0_N_name)s",
}


class Base(DeclarativeBase):
    """Declarative base for every CardFlow table."""

    metadata = MetaData(naming_convention=NAMING_CONVENTION)
    type_annotation_map: ClassVar[dict[Any, Any]] = {
        uuid.UUID: Uuid(),
        datetime: DateTime(timezone=True),
        date: Date(),
        time: Time(),
        str: Text(),
        bool: Boolean(),
        Decimal: Numeric(20, 10),
    }


def uuid_pk() -> MappedColumn[Any]:
    """``id UUID PRIMARY KEY DEFAULT uuidv7()``."""
    return mapped_column(Uuid, primary_key=True, server_default=UUIDV7)


def uuid_id() -> MappedColumn[Any]:
    """``id UUID NOT NULL DEFAULT uuidv7()`` for tables whose primary key is natural."""
    return mapped_column(Uuid, server_default=UUIDV7)


def minor(default: int | None = None) -> MappedColumn[Any]:
    """Money in integer minor units (``BIGINT``); nullability follows the annotation."""
    return mapped_column(BigInteger, server_default=None if default is None else text(str(default)))


def now_default() -> MappedColumn[Any]:
    """``TIMESTAMPTZ DEFAULT now()``; nullability follows the annotation."""
    return mapped_column(server_default=NOW)


class SyncColumns:
    """Columns of every syncable table (architecture §6, ADR-007).

    ``row_version`` is incremented by the server on every accepted change; ``deleted_at``
    is the tombstone; ``origin_device_id`` records the device that produced the row.
    """

    row_version: Mapped[int] = mapped_column(BigInteger, server_default=text("1"))
    updated_at: Mapped[datetime] = mapped_column(server_default=NOW)
    deleted_at: Mapped[datetime | None] = mapped_column()
    origin_device_id: Mapped[uuid.UUID | None] = mapped_column()
