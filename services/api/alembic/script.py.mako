"""${message}

Revision ID: ${up_revision}
Revises: ${down_revision | comma,n}
Create Date: ${create_date}

Write explicit DDL (op.execute / op.create_table) with explicit constraint names that
match cardflow.db.base.NAMING_CONVENTION, update the models, and keep
tests/db/test_model_drift.py green. Every revision needs a complete downgrade and must
never UPDATE money values (data-model §7).
"""

from collections.abc import Sequence

from alembic import op
${imports if imports else ""}
revision: str = ${repr(up_revision)}
down_revision: str | Sequence[str] | None = ${repr(down_revision)}
branch_labels: str | Sequence[str] | None = ${repr(branch_labels)}
depends_on: str | Sequence[str] | None = ${repr(depends_on)}


def upgrade() -> None:
    """Upgrade schema."""
    ${upgrades if upgrades else "pass"}


def downgrade() -> None:
    """Downgrade schema."""
    ${downgrades if downgrades else "pass"}
