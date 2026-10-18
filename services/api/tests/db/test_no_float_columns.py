"""No binary floating point or ``money`` anywhere in the schema (ADR-008, T-005).

Scans the migrated session database through ``information_schema`` (and ``pg_proc`` for
our own functions), so it checks what the migrations really created, not the models.
"""

import pytest
from sqlalchemy import text
from sqlalchemy.engine import Connection

pytestmark = pytest.mark.db

FORBIDDEN_UDT_NAMES = ("float4", "float8", "money", "_float4", "_float8", "_money")
RATE_COLUMNS = {
    ("installment_plans", "per_period_rate"),
    ("scenarios", "income_scale"),
    ("scenarios", "expense_scale"),
}
# Durations and scores with their own documented precision (data-model §4 / §3).
OTHER_NUMERIC_COLUMNS = {
    ("plan_runs", "time_limit_s"): (8, 3),
    ("plan_runs", "wall_time_s"): (10, 3),
    ("extraction_candidates", "confidence"): (5, 4),
}


def columns(conn: Connection) -> list[tuple[str, str, str, str, int | None, int | None]]:
    """(table, column, data_type, udt_name, numeric_precision, numeric_scale) in public."""
    result = conn.execute(
        text(
            """
            SELECT c.table_name, c.column_name, c.data_type, c.udt_name,
                   c.numeric_precision, c.numeric_scale
              FROM information_schema.columns AS c
              JOIN information_schema.tables AS t
                ON t.table_schema = c.table_schema AND t.table_name = c.table_name
             WHERE c.table_schema = 'public' AND t.table_type = 'BASE TABLE'
            """
        )
    )
    return [(t, c, d, u, p, s) for t, c, d, u, p, s in result]


def test_no_float_double_real_or_money_column(conn: Connection) -> None:
    found = columns(conn)
    forbidden = [
        (table, column, data_type)
        for table, column, data_type, udt, _, _ in found
        if data_type in ("real", "double precision", "money") or udt in FORBIDDEN_UDT_NAMES
    ]

    assert len(found) > 600  # the scan really covers the schema (759 in 0001)
    assert forbidden == []


def test_money_columns_are_bigint_minor_units(conn: Connection) -> None:
    minor = [(t, c, d) for t, c, d, _, _, _ in columns(conn) if c.endswith("_minor")]

    assert len(minor) > 30  # 38 in revision 0001
    assert [(t, c, d) for t, c, d in minor if d != "bigint"] == []


def test_numeric_columns_have_explicit_precision(conn: Connection) -> None:
    numeric = {
        (table, column): (precision, scale)
        for table, column, data_type, _, precision, scale in columns(conn)
        if data_type == "numeric"
    }

    assert numeric == {
        **dict.fromkeys(RATE_COLUMNS, (20, 10)),
        **OTHER_NUMERIC_COLUMNS,
    }


def test_timestamps_carry_a_time_zone(conn: Connection) -> None:
    timestamps = [
        (table, column, data_type)
        for table, column, data_type, _, _, _ in columns(conn)
        if column.endswith("_at") or column == "at" or data_type.startswith("timestamp")
    ]

    assert len(timestamps) > 100
    assert [row for row in timestamps if row[2] != "timestamp with time zone"] == []


def test_own_functions_do_not_use_float_types(conn: Connection) -> None:
    """Trigger/check functions of migration 0001 (extension functions excluded)."""
    offending = conn.execute(
        text(
            """
            SELECT p.proname
              FROM pg_proc AS p
              JOIN pg_namespace AS n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public'
               AND NOT EXISTS (
                   SELECT 1 FROM pg_depend AS d WHERE d.objid = p.oid AND d.deptype = 'e')
               AND (p.prorettype IN ('float4'::regtype, 'float8'::regtype, 'money'::regtype)
                    OR p.proargtypes::oid[] && ARRAY['float4'::regtype, 'float8'::regtype,
                                                     'money'::regtype]::oid[])
            """
        )
    ).all()
    own = conn.execute(
        text(
            """
            SELECT count(*) FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public'
               AND NOT EXISTS (
                   SELECT 1 FROM pg_depend AS d WHERE d.objid = p.oid AND d.deptype = 'e')
            """
        )
    ).scalar_one()

    assert own >= 9
    assert offending == []
