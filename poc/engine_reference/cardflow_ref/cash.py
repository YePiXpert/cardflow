"""Per-account cash timeline with explicit snapshot-inclusion and same-day ordering semantics.

Fixes the prototype defect (Appendix B #4): events dated ON the snapshot day that the
snapshot balance does not yet include are applied, not dropped. Same-day events with
unknown order are applied conservatively (outflows before inflows) and the assumption is
recorded. No cross-account netting: account A never pays account B's debit.
"""
from __future__ import annotations

from dataclasses import dataclass, field, replace
from datetime import date, datetime, timedelta
from decimal import Decimal, ROUND_HALF_UP
from enum import Enum
from typing import Iterable, Optional


class EventClass(str, Enum):
    CONFIRMED = "confirmed"   # 已确认：已出账单、已约定固定支出、合同/到账确定的流入
    EXPECTED = "expected"     # 预计：工资、返现、退款等未到账流入或估计支出
    PLANNED = "planned"       # 由新消费计划注入的还款（引擎内部）


@dataclass(frozen=True)
class CashEvent:
    id: str
    account: str
    on: date
    amount: int                     # minor units; negative = outflow
    cls: EventClass
    category: str = ""              # income | bill | living | repayment | transfer_in | transfer_out | fee | other
    label: str = ""
    at: Optional[datetime] = None   # precise timestamp if known (enables timestamp ordering)


@dataclass(frozen=True)
class Snapshot:
    account: str
    balance: int
    as_of: date
    observed_at: Optional[datetime] = None
    includes_event_ids: frozenset = frozenset()   # same-day events ALREADY reflected in balance


@dataclass(frozen=True)
class CashAccount:
    id: str
    name: str
    currency: str = "CNY"
    reserve_floor: int = 0              # 用户最低储备（硬约束）
    usable_for_repayment: bool = True   # 理财/受限资金 = False


@dataclass(frozen=True)
class Scenario:
    id: str
    include_expected: bool = True
    income_delay_days: int = 0
    income_scale: Decimal = Decimal(1)
    expense_scale: Decimal = Decimal(1)          # applies to category == "living"
    event_overrides: dict = field(default_factory=dict)   # event_id -> {"on": date, "amount": int}
    same_day_order: str = "conservative"         # "conservative" | "timestamp"
    description: str = ""


@dataclass(frozen=True)
class Point:
    on: date
    phase: str                 # "snapshot" | "low" (after outflows, before inflows) | "end"
    balance: int
    event_ids: tuple = ()


@dataclass
class Timeline:
    account: str
    scenario: str
    snapshot: Snapshot
    points: list
    assumptions: list
    skipped_event_ids: list


def _scale(amount: int, factor: Decimal) -> int:
    sign = -1 if amount < 0 else 1
    return sign * int((Decimal(abs(amount)) * factor).to_integral_value(rounding=ROUND_HALF_UP))


def apply_scenario(events: Iterable[CashEvent], scenario: Scenario) -> list[CashEvent]:
    out = []
    for e in events:
        if e.cls == EventClass.EXPECTED and not scenario.include_expected:
            continue
        ov = scenario.event_overrides.get(e.id, {})
        on, amt = ov.get("on", e.on), ov.get("amount", e.amount)
        if e.cls == EventClass.EXPECTED and amt > 0:
            on = on + timedelta(days=scenario.income_delay_days)
            amt = _scale(amt, scenario.income_scale)
        if amt < 0 and e.category == "living":
            amt = _scale(amt, scenario.expense_scale)
        out.append(replace(e, on=on, amount=amt))
    return out


def build_timeline(account: CashAccount, snapshot: Snapshot, events: Iterable[CashEvent],
                   scenario: Scenario, horizon_end: date) -> Timeline:
    if snapshot.account != account.id:
        raise ValueError("snapshot/account mismatch")
    evs = [e for e in apply_scenario(events, scenario) if e.account == account.id and e.on <= horizon_end]
    pending, skipped, assumptions = [], [], []
    for e in evs:
        if e.on < snapshot.as_of:
            skipped.append(e.id)          # dated before the snapshot: assumed reflected in the balance
            continue
        if e.on == snapshot.as_of and e.id in snapshot.includes_event_ids:
            skipped.append(e.id)          # explicitly included in the snapshot balance
            continue
        pending.append(e)
    if any(e.on == snapshot.as_of for e in pending):
        assumptions.append(f"{snapshot.as_of}: 快照当天未标记为已包含的事件按未发生处理并计入当日")
    by_day: dict[date, list[CashEvent]] = {}
    for e in pending:
        by_day.setdefault(e.on, []).append(e)
    bal = snapshot.balance
    points = [Point(snapshot.as_of, "snapshot", bal)]
    for d in sorted(by_day):
        day = by_day[d]
        if scenario.same_day_order == "timestamp" and all(e.at is not None for e in day):
            running, low = bal, bal
            ids = []
            for e in sorted(day, key=lambda e: e.at):
                running += e.amount
                low = min(low, running)
                ids.append(e.id)
            out_ids = tuple(e.id for e in day if e.amount < 0)
            points.append(Point(d, "low", low, out_ids))      # event_ids on 'low' = that day's outflows
            points.append(Point(d, "end", running, tuple(ids)))
            bal = running
            continue
        outs = [e for e in day if e.amount < 0]
        ins = [e for e in day if e.amount > 0]
        if outs and ins:
            assumptions.append(f"{d}: 同日收支顺序未知，按保守顺序（先支出后收入）校验")
        low = bal + sum(e.amount for e in outs)
        end = low + sum(e.amount for e in ins)
        points.append(Point(d, "low", low, tuple(e.id for e in outs)))
        points.append(Point(d, "end", end, tuple(e.id for e in day)))
        bal = end
    return Timeline(account.id, scenario.id, snapshot, points, assumptions, skipped)


@dataclass(frozen=True)
class Breach:
    on: date
    phase: str
    balance: int
    gap_to_zero: int
    gap_to_reserve: int
    event_ids: tuple


@dataclass
class CashReport:
    account: str
    scenario: str
    ok: bool                      # no reserve breach
    ok_zero: bool                 # no sub-zero point
    min_balance: int
    min_on: Optional[date]
    breaches: list                # every reserve breach point, chronological (never only the first)
    first_breach: Optional[Breach]
    first_zero_breach: Optional[Breach]
    end_balance: int
    assumptions: list
    timeline: Timeline


def evaluate(timeline: Timeline, reserve_floor: int) -> CashReport:
    breaches, first_zero = [], None
    min_bal, min_on = None, None
    for p in timeline.points:
        if p.phase == "end":
            continue                                   # 'end' >= 'low' on the same day; never the binding point
        if min_bal is None or p.balance < min_bal:
            min_bal, min_on = p.balance, p.on
        if p.balance < reserve_floor:
            b = Breach(p.on, p.phase, p.balance, max(0, -p.balance), max(0, reserve_floor - p.balance), p.event_ids)
            # A breach point is (a) the snapshot itself already below the floor, or (b) a day whose OUTFLOWS
            # push/keep the balance below the floor. Inflow-only days do not add a new breach entry: the
            # shortfall is already on record and the remaining state is visible in min/end balances.
            if p.phase == "snapshot" or (p.phase == "low" and p.event_ids):
                breaches.append(b)
            if p.balance < 0 and first_zero is None:
                first_zero = b
    end_bal = timeline.points[-1].balance
    return CashReport(timeline.account, timeline.scenario, not breaches, first_zero is None, min_bal, min_on,
                      breaches, breaches[0] if breaches else None, first_zero, end_bal,
                      list(timeline.assumptions), timeline)


def evaluate_accounts(accounts: list[CashAccount], snapshots: dict[str, Snapshot], events: Iterable[CashEvent],
                      scenario: Scenario, horizon_end: date) -> dict[str, CashReport]:
    events = list(events)
    out = {}
    for a in accounts:
        if a.id not in snapshots:
            raise LookupError(f"NEEDS_DATA: no balance snapshot for cash account {a.id}")
        tl = build_timeline(a, snapshots[a.id], events, scenario, horizon_end)
        out[a.id] = evaluate(tl, a.reserve_floor)
    return out
