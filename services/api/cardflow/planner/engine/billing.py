"""Billing-cycle rules: statement date and due date from a posting date.

Transaction date, bank posting date, statement date, due date, planned repayment date,
actual cash debit date and bank-confirmed repayment date are DISTINCT. This module only
derives (statement_date, due_date) from a posting date and a versioned rule.
"""

from __future__ import annotations

import calendar
from collections.abc import Callable
from dataclasses import dataclass
from datetime import date, timedelta
from typing import Literal


def clamp_day(year: int, month: int, day: int) -> date:
    """Day-of-month with month-end truncation (31 -> 30/28/29)."""
    last = calendar.monthrange(year, month)[1]
    return date(year, month, min(day, last))


def add_months(d: date, n: int) -> tuple[int, int]:
    m0 = d.month - 1 + n
    return d.year + m0 // 12, m0 % 12 + 1


@dataclass(frozen=True)
class DueRule:
    kind: Literal["fixed_day", "days_after_statement"]
    day: int | None = None  # fixed_day: 1..31, clamped
    month_offset: int = 0  # fixed_day: 0 = 账单所在月, 1 = 次月
    days: int | None = None  # days_after_statement: N
    day_kind: Literal["calendar", "business"] = "calendar"


@dataclass(frozen=True)
class BillingRule:
    rule_id: str
    statement_day: int  # 1..31 (clamped to month end)
    due: DueRule
    statement_day_inclusive: bool = True  # 账单日当天入账是否计入本期（银行差异，需核验）  # noqa: RUF003
    holiday_rollover: Literal["none", "next_business_day"] = "none"
    effective_from: date | None = None
    effective_to: date | None = None  # exclusive
    source: str = ""  # 规则来源
    verified_on: date | None = None
    status: Literal["draft", "verified", "user_declared"] = "user_declared"

    def is_effective_on(self, d: date) -> bool:
        if self.effective_from and d < self.effective_from:
            return False
        if self.effective_to and d >= self.effective_to:  # noqa: SIM103
            return False
        return True


@dataclass(frozen=True)
class Cycle:
    statement_date: date
    due_date: date
    rule_id: str
    assumptions: tuple[str, ...] = ()


BusinessDayFn = Callable[[date], bool]


class BillingRuleError(ValueError):
    """The rule gives no cycle for a posting date: the version is not effective on it, it is
    misconfigured for that month (due not after the statement), or it needs a verified
    business-day calendar. A data issue (BILLING_RULE_INVALID) on the transaction date; on a
    shifted date of the date-shift search the card is unavailable that day (engine-spec
    §12.9). Raised only for the rule itself -- a date past the calendar stays an
    OverflowError/ValueError of the standard library."""


def statement_date_for_posting(rule: BillingRule, posting: date) -> date:
    this_stmt = clamp_day(posting.year, posting.month, rule.statement_day)
    if posting < this_stmt or (posting == this_stmt and rule.statement_day_inclusive):
        return this_stmt
    y, m = add_months(posting, 1)
    return clamp_day(y, m, rule.statement_day)


def due_date_for_statement(
    rule: BillingRule, stmt: date, is_business_day: BusinessDayFn | None = None
) -> date:
    r = rule.due
    if r.kind == "fixed_day":
        if r.day is None:
            raise BillingRuleError("fixed_day rule needs day")
        y, m = add_months(stmt, r.month_offset)
        due = clamp_day(y, m, r.day)
        if due <= stmt:
            raise BillingRuleError(
                f"rule {rule.rule_id}: due {due} is not after statement {stmt} "
                "(month_offset/day misconfigured)"
            )
    elif r.kind == "days_after_statement":
        if r.days is None:
            raise BillingRuleError("days_after_statement rule needs days")
        if r.day_kind == "calendar":
            due = stmt + timedelta(days=r.days)
        else:
            if is_business_day is None:
                raise BillingRuleError("business-day counting requires a verified calendar")
            due, n = stmt, 0
            while n < r.days:
                due += timedelta(days=1)
                if is_business_day(due):
                    n += 1
    else:
        raise BillingRuleError(f"unknown due rule kind {r.kind}")
    if rule.holiday_rollover == "next_business_day":
        if is_business_day is None:
            raise BillingRuleError("holiday_rollover requires a verified business-day calendar")
        while not is_business_day(due):
            due += timedelta(days=1)
    return due


def cycle_for_posting(
    rule: BillingRule, posting: date, is_business_day: BusinessDayFn | None = None
) -> Cycle:
    if not rule.is_effective_on(posting):
        raise BillingRuleError(f"rule {rule.rule_id} not effective on {posting}")
    stmt = statement_date_for_posting(rule, posting)
    return Cycle(stmt, due_date_for_statement(rule, stmt, is_business_day), rule.rule_id)


def cycles_for_transaction(
    rule: BillingRule,
    txn_date: date,
    posting_delay_min: int = 0,
    posting_delay_max: int = 0,
    is_business_day: BusinessDayFn | None = None,
) -> list[Cycle]:
    """All distinct cycles reachable within the posting-delay window, earliest due first.
    More than one entry = posting uncertainty near the statement day; the conservative
    scenario must assume the EARLIEST due date."""
    seen: dict[tuple[date, date], Cycle] = {}
    for delay in range(posting_delay_min, posting_delay_max + 1):
        c = cycle_for_posting(rule, txn_date + timedelta(days=delay), is_business_day)
        key = (c.statement_date, c.due_date)
        if key not in seen:
            note = f"posting delay {delay}d -> posting {txn_date + timedelta(days=delay)}"
            seen[key] = Cycle(c.statement_date, c.due_date, c.rule_id, (note,))
    return sorted(seen.values(), key=lambda c: c.due_date)


def select_rule(rules: list[BillingRule], on: date) -> BillingRule:
    """Pick the rule version effective on `on`. Issued statements are handled by the caller:
    an already-issued statement always wins over any prediction (see resolve_cycle)."""
    cands = [r for r in rules if r.is_effective_on(on)]
    if not cands:
        raise BillingRuleError(f"no billing rule effective on {on}")
    if len(cands) > 1:
        raise BillingRuleError(
            f"overlapping billing rule versions on {on}: {[r.rule_id for r in cands]}"
        )
    return cands[0]


@dataclass(frozen=True)
class IssuedStatement:
    statement_date: date
    due_date: date
    source: str = "bank_statement"


def resolve_cycle(
    rules: list[BillingRule],
    issued: list[IssuedStatement],
    posting: date,
    is_business_day: BusinessDayFn | None = None,
) -> Cycle:
    """Issued statement (bank fact) beats predicted cycle; prediction uses the rule version
    effective on posting."""
    predicted = cycle_for_posting(select_rule(rules, posting), posting, is_business_day)
    for s in issued:
        if s.statement_date == predicted.statement_date:
            return Cycle(
                s.statement_date,
                s.due_date,
                "issued:" + s.source,
                ("issued statement overrides prediction",),
            )
    return predicted
