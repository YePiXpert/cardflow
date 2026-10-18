"""Per-account cash timeline with explicit snapshot-inclusion and same-day ordering semantics.

Fixes the prototype defect (Appendix B #4): events dated ON the snapshot day that the
snapshot balance does not yet include are applied, not dropped. Same-day events with
unknown order are applied conservatively (outflows before inflows) and the assumption is
recorded. No cross-account netting: account A never pays account B's debit.

Model 1.1.0 (engine-spec §12.2/§12.4):

* whether the snapshot already reflects an event is judged on the ORIGINAL event, before the
  scenario changes it; an event the scenario moves before the snapshot day is not in the
  balance and counts on the snapshot day;
* an event whose date the scenario changes loses its timestamp (its new day is ordered
  conservatively);
* a day is ordered by timestamp when the scenario asks for it and every existing event of the
  day has one. The plan's repayments (``planned``) and the model's checkpoint days do not take
  part in that decision; on a timestamp-ordered day the repayments come first, which is
  exactly how the CP-SAT model subtracts them from the day's low.
"""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass, field, replace
from datetime import date, datetime, timedelta
from decimal import ROUND_HALF_UP, Decimal
from enum import Enum


class EventClass(str, Enum):  # noqa: UP042
    CONFIRMED = "confirmed"  # 已确认：已出账单、已约定固定支出、合同/到账确定的流入  # noqa: RUF003
    EXPECTED = "expected"  # 预计：工资、返现、退款等未到账流入或估计支出  # noqa: RUF003
    PLANNED = "planned"  # 由新消费计划注入的还款（引擎内部）  # noqa: RUF003


@dataclass(frozen=True)
class CashEvent:
    id: str
    account: str
    on: date
    amount: int  # minor units; negative = outflow
    cls: EventClass
    # income | bill | living | repayment | transfer_in | transfer_out | fee | other
    category: str = ""
    label: str = ""
    at: datetime | None = None  # precise timestamp if known (enables timestamp ordering)


@dataclass(frozen=True)
class Snapshot:
    account: str
    balance: int
    as_of: date
    observed_at: datetime | None = None
    includes_event_ids: frozenset = frozenset()  # same-day events ALREADY reflected in balance


@dataclass(frozen=True)
class CashAccount:
    id: str
    name: str
    currency: str = "CNY"
    reserve_floor: int = 0  # 用户最低储备（硬约束）  # noqa: RUF003
    usable_for_repayment: bool = True  # 理财/受限资金 = False


@dataclass(frozen=True)
class Scenario:
    id: str
    include_expected: bool = True
    income_delay_days: int = 0
    income_scale: Decimal = Decimal(1)
    expense_scale: Decimal = Decimal(1)  # applies to category == "living"
    event_overrides: dict = field(default_factory=dict)  # event_id -> {"on": date, "amount": int}
    same_day_order: str = "conservative"  # "conservative" | "timestamp"
    description: str = ""


@dataclass(frozen=True)
class Point:
    on: date
    phase: str  # "snapshot" | "low" (after outflows, before inflows) | "end"
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


def scenario_event(e: CashEvent, scenario: Scenario) -> CashEvent | None:
    """``e`` as ``scenario`` sees it, or ``None`` if the scenario drops it. Overrides first,
    then the delay and scale of expected inflows and the scale of 'living' outflows. An event
    whose date changes loses its timestamp (engine-spec §12.4)."""
    if e.cls == EventClass.EXPECTED and not scenario.include_expected:
        return None
    ov = scenario.event_overrides.get(e.id, {})
    on, amt = ov.get("on", e.on), ov.get("amount", e.amount)
    if e.cls == EventClass.EXPECTED and amt > 0:
        on = on + timedelta(days=scenario.income_delay_days)
        amt = _scale(amt, scenario.income_scale)
    if amt < 0 and e.category == "living":
        amt = _scale(amt, scenario.expense_scale)
    return replace(e, on=on, amount=amt, at=e.at if on == e.on else None)


def apply_scenario(events: Iterable[CashEvent], scenario: Scenario) -> list[CashEvent]:
    return [t for e in events if (t := scenario_event(e, scenario)) is not None]


def reflected_in_snapshot(e: CashEvent, snapshot: Snapshot) -> bool:
    """Whether the snapshot balance already contains ``e``: dated before ``as_of``, or dated
    ``as_of`` and listed in ``includes_event_ids``. Judged on the ORIGINAL event -- no scenario
    can move an event into or out of the balance (engine-spec §12.2)."""
    return e.on < snapshot.as_of or (e.on == snapshot.as_of and e.id in snapshot.includes_event_ids)


def build_timeline(
    account: CashAccount,
    snapshot: Snapshot,
    events: Iterable[CashEvent],
    scenario: Scenario,
    horizon_end: date,
    *,
    planned: Iterable[CashEvent] = (),
    checkpoint_days: Iterable[date] = (),
) -> Timeline:
    """Timeline of ``account`` under ``scenario`` up to ``horizon_end``.

    ``planned``: the plan's repayments (the verifier's), dated on or after the snapshot day;
    outflows that are not part of the same-day order decision and come first on a
    timestamp-ordered day. ``checkpoint_days``: days that get a (low, end) point even without
    an event (the model's candidate repayment days)."""
    if snapshot.account != account.id:
        raise ValueError("snapshot/account mismatch")
    as_of = snapshot.as_of
    pending, skipped, assumptions = [], [], []
    on_snapshot_day = False
    for e in events:
        if e.account != account.id:
            continue
        if reflected_in_snapshot(e, snapshot):
            skipped.append(e.id)  # already in the balance, whatever the scenario does with it
            continue
        t = scenario_event(e, scenario)
        if t is None:
            continue
        if e.on == as_of:
            on_snapshot_day = True
        if t.on < as_of:  # moved before the snapshot by the scenario: not in the balance
            assumptions.append(f"{t.id}: 情景将其日期移到快照日之前，按快照日 {as_of} 计入")  # noqa: RUF001
            t = replace(t, on=as_of, at=None)
        if t.on <= horizon_end:
            pending.append(t)
    if on_snapshot_day:
        assumptions.append(f"{as_of}: 快照当天未标记为已包含的事件按未发生处理并计入当日")
    by_day: dict[date, tuple[list[CashEvent], list[CashEvent]]] = {}
    for e in pending:
        by_day.setdefault(e.on, ([], []))[0].append(e)
    for p in planned:
        if p.account == account.id and p.on <= horizon_end:
            by_day.setdefault(max(p.on, as_of), ([], []))[1].append(p)
    for d in checkpoint_days:
        if as_of <= d <= horizon_end:
            by_day.setdefault(d, ([], []))
    bal = snapshot.balance
    points = [Point(as_of, "snapshot", bal)]
    for d in sorted(by_day):
        day, plan_day = by_day[d]
        if scenario.same_day_order == "timestamp" and all(e.at is not None for e in day):
            in_order = sorted(day, key=lambda e: e.at)  # stable: equal instants keep input order
            running = bal + sum(p.amount for p in plan_day)  # the plan's repayments first
            low = min(bal, running)
            for e in in_order:
                running += e.amount
                low = min(low, running)
            if plan_day and any(e.amount > 0 for e in day):
                assumptions.append(f"{d}: 计划还款没有时间戳，按当日最先发生处理")  # noqa: RUF001
            outflows = [e for e in day + plan_day if e.amount < 0]
            # event_ids on 'low' = that day's outflows
            points.append(Point(d, "low", low, tuple(e.id for e in outflows)))
            end_ids = tuple(p.id for p in plan_day) + tuple(e.id for e in in_order)
            points.append(Point(d, "end", running, end_ids))
            bal = running
            continue
        outs = [e for e in day if e.amount < 0] + [p for p in plan_day if p.amount < 0]
        ins = [e for e in day if e.amount > 0] + [p for p in plan_day if p.amount > 0]
        if outs and ins:
            assumptions.append(f"{d}: 同日收支顺序未知，按保守顺序（先支出后收入）校验")  # noqa: RUF001
        low = bal + sum(e.amount for e in outs)
        end = low + sum(e.amount for e in ins)
        points.append(Point(d, "low", low, tuple(e.id for e in outs)))
        points.append(Point(d, "end", end, tuple(e.id for e in day + plan_day)))
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
    ok: bool  # no reserve breach
    ok_zero: bool  # no sub-zero point
    min_balance: int
    min_on: date | None
    breaches: list  # every reserve breach point, chronological (never only the first)
    first_breach: Breach | None
    first_zero_breach: Breach | None
    end_balance: int
    assumptions: list
    timeline: Timeline


def evaluate(timeline: Timeline, reserve_floor: int) -> CashReport:
    breaches, first_zero = [], None
    min_bal, min_on = None, None
    for p in timeline.points:
        if p.phase == "end":
            continue  # 'end' >= 'low' on the same day; never the binding point
        if min_bal is None or p.balance < min_bal:
            min_bal, min_on = p.balance, p.on
        if p.balance < reserve_floor:
            b = Breach(
                p.on,
                p.phase,
                p.balance,
                max(0, -p.balance),
                max(0, reserve_floor - p.balance),
                p.event_ids,
            )
            # A breach point is (a) the snapshot itself already below the floor, or (b) a day
            # whose OUTFLOWS push/keep the balance below the floor. Inflow-only days do not add
            # a new breach entry: the shortfall is already on record and the remaining state is
            # visible in min/end balances.
            if p.phase == "snapshot" or (p.phase == "low" and p.event_ids):
                breaches.append(b)
            if p.balance < 0 and first_zero is None:
                first_zero = b
    end_bal = timeline.points[-1].balance
    return CashReport(
        timeline.account,
        timeline.scenario,
        not breaches,
        first_zero is None,
        min_bal,
        min_on,
        breaches,
        breaches[0] if breaches else None,
        first_zero,
        end_bal,
        list(timeline.assumptions),
        timeline,
    )


def evaluate_accounts(
    accounts: list[CashAccount],
    snapshots: dict[str, Snapshot],
    events: Iterable[CashEvent],
    scenario: Scenario,
    horizon_end: date,
    *,
    planned: Iterable[CashEvent] = (),
) -> dict[str, CashReport]:
    events = list(events)
    planned = list(planned)
    out = {}
    for a in accounts:
        if a.id not in snapshots:
            raise LookupError(f"NEEDS_DATA: no balance snapshot for cash account {a.id}")
        tl = build_timeline(a, snapshots[a.id], events, scenario, horizon_end, planned=planned)
        out[a.id] = evaluate(tl, a.reserve_floor)
    return out
