# Migrated from poc/engine_reference/tests/test_billing.py (T-003): assertions and expected
# values unchanged; only imports, type annotations, formatting and `noqa` markers differ.
from datetime import date

import pytest

from cardflow.planner.engine.billing import (
    BillingRule,
    DueRule,
    IssuedStatement,
    cycle_for_posting,
    cycles_for_transaction,
    resolve_cycle,
    select_rule,
    statement_date_for_posting,
)


def rule(stmt_day: int, due: DueRule, inclusive: bool = True, rid: str = "r") -> BillingRule:
    return BillingRule(rid, stmt_day, due, statement_day_inclusive=inclusive)


def test_fixed_day_same_month_and_next_month() -> None:
    a = rule(10, DueRule("fixed_day", day=28, month_offset=0))
    b = rule(20, DueRule("fixed_day", day=8, month_offset=1))
    assert cycle_for_posting(a, date(2026, 10, 16)).statement_date == date(2026, 11, 10)
    assert cycle_for_posting(a, date(2026, 10, 16)).due_date == date(2026, 11, 28)
    assert cycle_for_posting(b, date(2026, 10, 16)).statement_date == date(2026, 10, 20)
    assert cycle_for_posting(b, date(2026, 10, 16)).due_date == date(2026, 11, 8)


def test_statement_day_inclusive_toggle() -> None:
    inc = rule(20, DueRule("fixed_day", day=8, month_offset=1), inclusive=True)
    exc = rule(20, DueRule("fixed_day", day=8, month_offset=1), inclusive=False)
    assert statement_date_for_posting(inc, date(2026, 10, 20)) == date(2026, 10, 20)
    assert statement_date_for_posting(exc, date(2026, 10, 20)) == date(2026, 11, 20)


def test_month_end_clamp_and_leap_year() -> None:
    r = rule(31, DueRule("days_after_statement", days=20))
    assert statement_date_for_posting(r, date(2024, 2, 10)) == date(2024, 2, 29)  # leap year
    assert statement_date_for_posting(r, date(2025, 2, 10)) == date(2025, 2, 28)
    # posting on clamped statement day
    assert statement_date_for_posting(r, date(2026, 4, 30)) == date(2026, 4, 30)
    assert statement_date_for_posting(
        r,
        date(2026, 4, 30),
    ) == date(2026, 4, 30)
    c = cycle_for_posting(r, date(2025, 2, 10))
    assert c.due_date == date(2025, 3, 20)


def test_cross_year() -> None:
    r = rule(25, DueRule("fixed_day", day=15, month_offset=1))
    c = cycle_for_posting(r, date(2026, 12, 26))
    assert (c.statement_date, c.due_date) == (date(2027, 1, 25), date(2027, 2, 15))
    c2 = cycle_for_posting(r, date(2026, 12, 20))
    assert (c2.statement_date, c2.due_date) == (date(2026, 12, 25), date(2027, 1, 15))


def test_due_before_statement_is_model_invalid() -> None:
    bad = rule(28, DueRule("fixed_day", day=25, month_offset=0))
    with pytest.raises(ValueError):  # noqa: PT011
        cycle_for_posting(bad, date(2026, 10, 16))


def test_posting_uncertainty_near_statement_day_yields_two_cycles_earliest_first() -> None:
    r = rule(20, DueRule("fixed_day", day=8, month_offset=1))
    cs = cycles_for_transaction(r, date(2026, 10, 19), posting_delay_min=0, posting_delay_max=3)
    assert len(cs) == 2
    assert cs[0].due_date == date(2026, 11, 8) and cs[1].due_date == date(2026, 12, 8)  # noqa: PT018


def test_business_day_due_and_rollover_require_calendar() -> None:
    r = BillingRule("r", 10, DueRule("days_after_statement", days=3, day_kind="business"))
    with pytest.raises(ValueError):  # noqa: PT011
        cycle_for_posting(r, date(2026, 10, 1))
    is_bd = lambda d: d.weekday() < 5  # noqa: E731
    # stmt Sat 2026-10-10 -> 3 business days -> Wed 10-14
    c = cycle_for_posting(r, date(2026, 10, 1), is_bd)
    assert c.due_date == date(2026, 10, 14)
    r2 = BillingRule(
        "r2", 10, DueRule("fixed_day", day=11, month_offset=0), holiday_rollover="next_business_day"
    )
    # 10-11 is Sunday
    assert cycle_for_posting(r2, date(2026, 10, 1), is_bd).due_date == date(2026, 10, 12)


def test_rule_versions_and_issued_statement_precedence() -> None:
    old = BillingRule("v1", 10, DueRule("fixed_day", day=28), effective_to=date(2026, 11, 1))
    new = BillingRule(
        "v2", 15, DueRule("fixed_day", day=5, month_offset=1), effective_from=date(2026, 11, 1)
    )
    assert select_rule([old, new], date(2026, 10, 16)).rule_id == "v1"
    assert select_rule([old, new], date(2026, 11, 1)).rule_id == "v2"
    # bank issued a different due date
    issued = [IssuedStatement(date(2026, 11, 10), date(2026, 11, 30))]
    c = resolve_cycle([old, new], issued, date(2026, 10, 16))
    assert c.due_date == date(2026, 11, 30) and c.rule_id.startswith("issued:")  # noqa: PT018
