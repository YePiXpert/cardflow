"""Month-end clamping at the statement-day boundary (T-004, B.7).

``test_billing.py::test_month_end_clamp_and_leap_year`` (migrated verbatim from the PoC) checks
"posting on the clamped statement day" twice: its third and fourth assertions differ only by a
trailing comma. The duplicate most plausibly stood for the case the inclusive default cannot
show -- the EXCLUSIVE toggle on a clamped statement day, where a posting ON the clamped day
(04-30 for statement day 31) must roll to the next month's statement day, which is clamped
again (05-31, or 02-28/02-29). The migrated test is left unchanged so that it stays identical
to the PoC; this file covers that case and its neighbours.
"""

from datetime import date

from cardflow.planner.engine.billing import (
    BillingRule,
    DueRule,
    cycle_for_posting,
    statement_date_for_posting,
)

DUE = DueRule("days_after_statement", days=20)
INCLUSIVE = BillingRule("r31", 31, DUE)
EXCLUSIVE = BillingRule("r31x", 31, DUE, statement_day_inclusive=False)


def test_posting_on_a_clamped_statement_day_respects_the_inclusive_toggle() -> None:
    # April has 30 days: statement day 31 is clamped to 04-30.
    assert statement_date_for_posting(INCLUSIVE, date(2026, 4, 30)) == date(2026, 4, 30)
    assert statement_date_for_posting(EXCLUSIVE, date(2026, 4, 30)) == date(2026, 5, 31)
    # February, non-leap and leap year
    assert statement_date_for_posting(INCLUSIVE, date(2025, 2, 28)) == date(2025, 2, 28)
    assert statement_date_for_posting(EXCLUSIVE, date(2025, 2, 28)) == date(2025, 3, 31)
    assert statement_date_for_posting(INCLUSIVE, date(2024, 2, 29)) == date(2024, 2, 29)
    assert statement_date_for_posting(EXCLUSIVE, date(2024, 2, 29)) == date(2024, 3, 31)


def test_exclusive_roll_lands_on_the_next_months_clamped_day() -> None:
    assert statement_date_for_posting(EXCLUSIVE, date(2025, 1, 31)) == date(2025, 2, 28)
    assert statement_date_for_posting(EXCLUSIVE, date(2024, 1, 31)) == date(2024, 2, 29)
    # the day after a clamped statement day belongs to the next period either way
    assert statement_date_for_posting(INCLUSIVE, date(2026, 5, 1)) == date(2026, 5, 31)
    assert statement_date_for_posting(EXCLUSIVE, date(2026, 5, 1)) == date(2026, 5, 31)


def test_due_date_follows_the_rolled_statement_date() -> None:
    c = cycle_for_posting(EXCLUSIVE, date(2026, 4, 30))
    assert (c.statement_date, c.due_date) == (date(2026, 5, 31), date(2026, 6, 20))
    c = cycle_for_posting(INCLUSIVE, date(2026, 4, 30))
    assert (c.statement_date, c.due_date) == (date(2026, 4, 30), date(2026, 5, 20))
