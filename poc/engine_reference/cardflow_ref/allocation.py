"""CP-SAT allocation model (OR-Tools) with lexicographic objective tiers and an explicit status contract.

Decision variables: x_i (integer minor units on card i), y_i (card used). Hard constraints: amount
conservation, per-card capacity, shared pools, max cards, min split, per-transaction caps, and
per-account cash floors at EVERY checkpoint of the hard scenario(s). Solver statuses are passed
through verbatim: OPTIMAL / FEASIBLE / INFEASIBLE / UNKNOWN / MODEL_INVALID. A time limit never
turns into "no combination available" -- it stays UNKNOWN.
"""
from __future__ import annotations

import hashlib
import json
import time
import uuid
from dataclasses import dataclass, field, asdict
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from fractions import Fraction
from typing import Optional

import ortools
from ortools.sat.python import cp_model

from . import MODEL_VERSION
from .billing import BillingRule, Cycle, cycles_for_transaction
from .cash import CashAccount, CashEvent, EventClass, Scenario, Snapshot, build_timeline

BIG = 10**13


class ModelInvalid(Exception):
    pass


@dataclass(frozen=True)
class CardOption:
    id: str
    account_id: str
    name: str
    raw_available: int                      # 银行口径可用额度快照；可为负/超限，原值保留
    billing_rule: BillingRule
    repay_from: str                         # cash account id that will fund the repayment
    uncounted_holds: int = 0                # 快照尚未包含的预授权/占用
    plan_reservations: int = 0              # 其他已采纳计划的预留
    pool_id: Optional[str] = None
    per_txn_cap: Optional[int] = None
    min_split: Optional[int] = None
    channel_ok: bool = True
    currency_ok: bool = True
    status_ok: bool = True
    fee_rate: Decimal = Decimal(0)
    fee_fixed: int = 0
    verified_benefit_rate: Decimal = Decimal(0)     # 已核实收益（进入目标函数）
    verified_benefit_cap: Optional[int] = None
    potential_benefit_rate: Decimal = Decimal(0)    # 潜在/未核实收益（仅展示，不进入目标函数）
    posting_delay_min: int = 0
    posting_delay_max: int = 0

    @property
    def capacity(self) -> int:
        """可供新增消费的容量。只有这里截为 0；raw_available 永远保留原值（含负数/超限）。"""
        return max(0, self.raw_available - self.uncounted_holds - self.plan_reservations)


@dataclass(frozen=True)
class PlanRequest:
    amount: int
    currency: str
    txn_date: date
    allow_split: bool = False
    max_cards: int = 1
    min_split: int = 1
    payment_lead_days: int = 0              # 建议提前发起还款的天数（现金扣款时点 = 到期日 - lead）
    channel: str = "pos"

    @property
    def k(self) -> int:
        return self.max_cards if self.allow_split else 1


@dataclass(frozen=True)
class CardPlanInfo:
    card: CardOption
    cycle: Cycle                 # conservative cycle (earliest due within posting window)
    all_cycles: tuple
    repay_on: date               # planned cash debit date
    buffer_days: int             # repay_on - txn_date


def derive_card_info(card: CardOption, request: PlanRequest) -> CardPlanInfo:
    cycles = cycles_for_transaction(card.billing_rule, request.txn_date, card.posting_delay_min, card.posting_delay_max)
    c = cycles[0]
    repay_on = c.due_date - timedelta(days=request.payment_lead_days)
    return CardPlanInfo(card, c, tuple(cycles), repay_on, (repay_on - request.txn_date).days)


def ineligible_reason(card: CardOption, request: PlanRequest, accounts: dict[str, CashAccount]) -> Optional[str]:
    if not card.status_ok:
        return "CARD_STATUS"
    if not card.currency_ok:
        return "CURRENCY_NOT_SUPPORTED"
    if not card.channel_ok:
        return "CHANNEL_NOT_SUPPORTED"
    acct = accounts.get(card.repay_from)
    if acct is None:
        return "REPAY_ACCOUNT_MISSING"
    if not acct.usable_for_repayment:
        return "REPAY_ACCOUNT_RESTRICTED"
    if card.capacity <= 0:
        return "NO_CAPACITY"
    return None


@dataclass
class ModelInputs:
    request: PlanRequest
    cards: list
    pools: dict                       # pool_id -> available capacity (minor units)
    accounts: list                    # CashAccount
    snapshots: dict                   # account_id -> Snapshot
    events: list                      # CashEvent (existing, without plan)
    horizon_end: date
    global_reserve_floor: int = 0     # 用户整体最低现金（跨账户合计），0 = 不启用

    def accounts_by_id(self) -> dict:
        return {a.id: a for a in self.accounts}

    def input_hash(self) -> str:
        def default(o):
            if isinstance(o, (date, datetime)):
                return o.isoformat()
            if isinstance(o, Decimal):
                return str(o)
            if isinstance(o, (set, frozenset)):
                return sorted(o)
            if hasattr(o, "__dataclass_fields__"):
                return asdict(o)
            if isinstance(o, EventClass):
                return o.value
            raise TypeError(str(type(o)))
        payload = json.dumps(asdict(self), default=default, sort_keys=True, ensure_ascii=False)
        return hashlib.sha256(payload.encode("utf-8")).hexdigest()


TIERS = {
    "cash_safety":      [("min_margin", "max"), ("fees", "min"), ("net_verified_benefit", "max"), ("buffer", "max"), ("cards", "min")],
    "verified_benefit": [("net_verified_benefit", "max"), ("min_margin", "max"), ("buffer", "max"), ("cards", "min")],
    "fewer_cards":      [("cards", "min"), ("min_margin", "max"), ("net_verified_benefit", "max"), ("buffer", "max")],
}


def _low_series(timeline, dates: list[date]) -> list[int]:
    """Intraday-low balance for each date in `dates` (carry-forward when the account has no event that day)."""
    by_day: dict[date, tuple[int, int]] = {}
    last_end = timeline.snapshot.balance
    for p in timeline.points:
        if p.phase == "low":
            by_day.setdefault(p.on, [None, None])[0] = p.balance
        elif p.phase == "end":
            by_day[p.on][1] = p.balance
    out, carry = [], timeline.snapshot.balance
    days_sorted = sorted(by_day)
    j = 0
    for d in dates:
        while j < len(days_sorted) and days_sorted[j] < d:
            carry = by_day[days_sorted[j]][1]
            j += 1
        if j < len(days_sorted) and days_sorted[j] == d:
            out.append(by_day[d][0])
        else:
            out.append(carry)
    return out


@dataclass
class BuiltModel:
    model: cp_model.CpModel
    x: dict
    y: dict
    exprs: dict
    infos: list
    checkpoints: int
    extra: dict = field(default_factory=dict)


def build_model(inputs: ModelInputs, hard_scenarios: list[Scenario], infos: list[CardPlanInfo],
                prior_bounds: list[tuple[str, str, int]] = (), amount_var: bool = False,
                extra_cash_vars: bool = False) -> BuiltModel:
    req = inputs.request
    accounts = inputs.accounts_by_id()
    if req.amount <= 0:
        raise ModelInvalid("amount must be positive")
    if req.k < 1:
        raise ModelInvalid("max_cards must be >= 1")
    m = cp_model.CpModel()
    x, y = {}, {}
    for info in infos:
        c = info.card
        cap = c.capacity
        if c.per_txn_cap is not None:
            cap = min(cap, c.per_txn_cap)
        x[c.id] = m.new_int_var(0, max(cap, 0), f"x_{c.id}")
        y[c.id] = m.new_bool_var(f"y_{c.id}")
        m.add(x[c.id] <= cap * y[c.id])
        ms = c.min_split if c.min_split is not None else req.min_split
        if ms > 0:
            m.add(x[c.id] >= ms * y[c.id])
    if not infos:
        raise ModelInvalid("no eligible cards")
    total = sum(x.values())
    if amount_var:
        mprime = m.new_int_var(0, req.amount, "amount_affordable")
        m.add(total == mprime)
    else:
        mprime = None
        m.add(total == req.amount)
    m.add(sum(y.values()) <= req.k)
    # shared credit pools (multi-layer: a card may belong to one pool here; production supports nested pools)
    pools: dict[str, list] = {}
    for info in infos:
        if info.card.pool_id:
            pools.setdefault(info.card.pool_id, []).append(x[info.card.id])
    for pid, members in pools.items():
        if pid not in inputs.pools:
            raise ModelInvalid(f"pool {pid} has no capacity snapshot")
        m.add(sum(members) <= inputs.pools[pid])
    # cash floors at every checkpoint of every hard scenario
    margin = m.new_int_var(-BIG, BIG, "min_margin")
    extra = {}
    if extra_cash_vars:
        for a in inputs.accounts:
            extra[a.id] = m.new_int_var(0, BIG, f"extra_cash_{a.id}")
    markers = [CashEvent(f"__marker_{i.card.id}", i.card.repay_from, i.repay_on, 0, EventClass.PLANNED, "marker")
               for i in infos]
    horizon = max([inputs.horizon_end] + [i.repay_on for i in infos])
    n_checkpoints = 0
    baseline_infeasible = False
    for sc in hard_scenarios:
        timelines = {}
        for a in inputs.accounts:
            timelines[a.id] = build_timeline(a, inputs.snapshots[a.id], inputs.events + markers, sc, horizon)
        all_dates = sorted({p.on for tl in timelines.values() for p in tl.points if p.phase == "low"})
        series = {aid: _low_series(tl, all_dates) for aid, tl in timelines.items()}
        for a in inputs.accounts:
            for d, base in zip(all_dates, series[a.id]):
                terms = [x[i.card.id] for i in infos if i.card.repay_from == a.id and i.repay_on <= d]
                lhs = base + (extra[a.id] if extra else 0) - sum(terms)
                n_checkpoints += 1
                if not terms and not extra:
                    if base < a.reserve_floor:
                        baseline_infeasible = True
                    m.add(margin <= base - a.reserve_floor)
                    continue
                m.add(lhs >= a.reserve_floor)
                m.add(margin <= lhs - a.reserve_floor)
        if inputs.global_reserve_floor > 0:
            for idx, d in enumerate(all_dates):
                terms = [x[i.card.id] for i in infos if i.repay_on <= d]
                base_total = sum(series[a.id][idx] for a in inputs.accounts)
                lhs = base_total + (sum(extra.values()) if extra else 0) - sum(terms)
                if not terms and not extra:
                    if base_total < inputs.global_reserve_floor:
                        baseline_infeasible = True
                    continue
                m.add(lhs >= inputs.global_reserve_floor)
    if baseline_infeasible:
        m.add(total <= -1)   # provably infeasible: the baseline already breaches the floor
    # fees (rounded UP) and verified benefits (rounded DOWN, capped)
    fee_terms, ben_terms = [], []
    for info in infos:
        c = info.card
        if c.fee_rate or c.fee_fixed:
            f = m.new_int_var(0, BIG, f"fee_{c.id}")
            if c.fee_rate:
                fr = Fraction(Decimal(str(c.fee_rate)))
                m.add(f * fr.denominator >= x[c.id] * fr.numerator + c.fee_fixed * fr.denominator * y[c.id])
            else:
                m.add(f == c.fee_fixed * y[c.id])
            fee_terms.append(f)
        if c.verified_benefit_rate:
            cap = c.verified_benefit_cap if c.verified_benefit_cap is not None else BIG
            b = m.new_int_var(0, cap, f"benefit_{c.id}")
            br = Fraction(Decimal(str(c.verified_benefit_rate)))
            m.add(b * br.denominator <= x[c.id] * br.numerator)
            ben_terms.append(b)
    fees = sum(fee_terms) if fee_terms else 0
    benefit = sum(ben_terms) if ben_terms else 0
    buffer = sum(x[i.card.id] * i.buffer_days for i in infos)
    exprs = {
        "min_margin": margin,
        "fees": fees,
        "verified_benefit": benefit,
        "net_verified_benefit": benefit - fees,
        "buffer": buffer,
        "cards": sum(y.values()),
    }
    if mprime is not None:
        exprs["amount_affordable"] = mprime
    if extra:
        exprs["extra_cash"] = sum(extra.values())
    for name, sense, value in prior_bounds:
        e = exprs[name]
        if isinstance(e, int):
            continue
        m.add(e >= value) if sense == "max" else m.add(e <= value)
    return BuiltModel(m, x, y, exprs, infos, n_checkpoints, extra)


@dataclass
class TierResult:
    name: str
    sense: str
    status: str
    value: Optional[int]
    bound: Optional[int]
    wall_time_s: float


@dataclass
class SolveResult:
    run_id: str
    status: str                       # OPTIMAL | FEASIBLE | INFEASIBLE | UNKNOWN | MODEL_INVALID
    profile: str
    scenario_id: str
    allocation: dict                  # card_id -> amount (only cards with amount > 0)
    tiers: list
    proven_optimal: bool
    wall_time_s: float
    solver_version: str
    model_version: str
    input_hash: str
    time_limit_s: float
    checkpoints: int
    notes: list = field(default_factory=list)
    created_at: str = ""


def _solver(time_limit_s: float, workers: int, seed: int) -> cp_model.CpSolver:
    s = cp_model.CpSolver()
    s.parameters.max_time_in_seconds = time_limit_s
    s.parameters.num_workers = workers
    s.parameters.random_seed = seed
    return s


def solve(inputs: ModelInputs, scenario: Scenario, profile: str, time_limit_s: float = 10.0,
          workers: int = 8, seed: int = 0, hard_scenarios: Optional[list] = None) -> SolveResult:
    t0 = time.monotonic()
    run_id = str(uuid.uuid4())
    base = dict(run_id=run_id, profile=profile, scenario_id=scenario.id, solver_version=ortools.__version__,
                model_version=MODEL_VERSION, input_hash=inputs.input_hash(), time_limit_s=time_limit_s,
                created_at=datetime.now(timezone.utc).isoformat())
    if profile not in TIERS:
        return SolveResult(status="MODEL_INVALID", allocation={}, tiers=[], proven_optimal=False,
                           wall_time_s=0.0, checkpoints=0, notes=[f"unknown profile {profile}"], **base)
    accounts = inputs.accounts_by_id()
    notes = []
    infos = []
    for c in inputs.cards:
        r = ineligible_reason(c, inputs.request, accounts)
        if r:
            notes.append(f"{c.id}: excluded ({r})")
            continue
        infos.append(derive_card_info(c, inputs.request))
    hard = hard_scenarios or [scenario]
    tiers_out, bounds, allocation = [], [], {}
    proven = True
    per_tier = time_limit_s / max(1, len(TIERS[profile]))
    checkpoints = 0
    try:
        for name, sense in TIERS[profile]:
            built = build_model(inputs, hard, infos, bounds)
            checkpoints = built.checkpoints
            err = built.model.validate() if hasattr(built.model, "validate") else ""
            if err:
                raise ModelInvalid(err)
            expr = built.exprs[name]
            if isinstance(expr, int):
                tiers_out.append(TierResult(name, sense, "SKIPPED_CONSTANT", expr, expr, 0.0))
                continue
            (built.model.maximize if sense == "max" else built.model.minimize)(expr)
            s = _solver(per_tier, workers, seed)
            st = s.solve(built.model)
            sname = s.status_name(st)
            if st in (cp_model.OPTIMAL, cp_model.FEASIBLE):
                val = int(round(s.objective_value))
                bnd = int(round(s.best_objective_bound))
                tiers_out.append(TierResult(name, sense, sname, val, bnd, s.wall_time))
                allocation = {i.card.id: s.value(built.x[i.card.id]) for i in infos if s.value(built.x[i.card.id]) > 0}
                bounds.append((name, sense, val))
                if st == cp_model.FEASIBLE:
                    proven = False
                    notes.append(f"tier {name}: time limit reached, value {val} not proven optimal (bound {bnd})")
            elif st == cp_model.INFEASIBLE:
                tiers_out.append(TierResult(name, sense, sname, None, None, s.wall_time))
                return SolveResult(status="INFEASIBLE", allocation={}, tiers=tiers_out, proven_optimal=False,
                                   wall_time_s=time.monotonic() - t0, checkpoints=checkpoints, notes=notes, **base)
            elif st == cp_model.MODEL_INVALID:
                raise ModelInvalid("solver reported MODEL_INVALID")
            else:  # UNKNOWN
                tiers_out.append(TierResult(name, sense, sname, None, None, s.wall_time))
                if not allocation:
                    notes.append("time limit reached before any solution; this is NOT a proof of infeasibility")
                    return SolveResult(status="UNKNOWN", allocation={}, tiers=tiers_out, proven_optimal=False,
                                       wall_time_s=time.monotonic() - t0, checkpoints=checkpoints, notes=notes, **base)
                notes.append(f"tier {name}: UNKNOWN (time limit); keeping best solution from earlier tiers")
                proven = False
                break
    except ModelInvalid as e:
        return SolveResult(status="MODEL_INVALID", allocation={}, tiers=tiers_out, proven_optimal=False,
                           wall_time_s=time.monotonic() - t0, checkpoints=checkpoints, notes=notes + [str(e)], **base)
    status = "OPTIMAL" if proven else "FEASIBLE"
    return SolveResult(status=status, allocation=allocation, tiers=tiers_out, proven_optimal=proven,
                       wall_time_s=time.monotonic() - t0, checkpoints=checkpoints, notes=notes, **base)


def feasibility_status(inputs: ModelInputs, scenario: Scenario, infos: list, time_limit_s: float = 2.0) -> str:
    try:
        built = build_model(inputs, [scenario], infos)
    except ModelInvalid:
        return "MODEL_INVALID"
    s = _solver(time_limit_s, 8, 0)
    return s.status_name(s.solve(built.model))


def min_extra_cash(inputs: ModelInputs, scenario: Scenario, infos: list, time_limit_s: float = 5.0):
    """Smallest additional CONFIRMED cash (per account, available from the snapshot date) that makes the plan feasible."""
    try:
        built = build_model(inputs, [scenario], infos, extra_cash_vars=True)
    except ModelInvalid as e:
        return {"status": "MODEL_INVALID", "detail": str(e)}
    built.model.minimize(built.exprs["extra_cash"])
    s = _solver(time_limit_s, 8, 0)
    st = s.solve(built.model)
    name = s.status_name(st)
    if st not in (cp_model.OPTIMAL, cp_model.FEASIBLE):
        return {"status": name}
    vals = {aid: s.value(v) for aid, v in built.extra.items()}
    return {"status": name, "extra_cash_by_account": vals, "total": int(round(s.objective_value)),
            "allocation": {i.card.id: s.value(built.x[i.card.id]) for i in infos if s.value(built.x[i.card.id]) > 0}}


def max_affordable_amount(inputs: ModelInputs, scenario: Scenario, infos: list, time_limit_s: float = 5.0):
    try:
        built = build_model(inputs, [scenario], infos, amount_var=True)
    except ModelInvalid as e:
        return {"status": "MODEL_INVALID", "detail": str(e)}
    built.model.maximize(built.exprs["amount_affordable"])
    s = _solver(time_limit_s, 8, 0)
    st = s.solve(built.model)
    name = s.status_name(st)
    if st not in (cp_model.OPTIMAL, cp_model.FEASIBLE):
        return {"status": name}
    return {"status": name, "amount": int(round(s.objective_value)),
            "allocation": {i.card.id: s.value(built.x[i.card.id]) for i in infos if s.value(built.x[i.card.id]) > 0}}


def first_feasible_date_shift(inputs: ModelInputs, scenario: Scenario, max_shift_days: int = 45,
                              time_limit_s: float = 1.0) -> Optional[dict]:
    """Earliest later transaction date (same amount) for which the hard scenario is feasible, if any within range."""
    from dataclasses import replace as _replace
    accounts = inputs.accounts_by_id()
    for k in range(1, max_shift_days + 1):
        req = _replace(inputs.request, txn_date=inputs.request.txn_date + timedelta(days=k))
        shifted = ModelInputs(req, inputs.cards, inputs.pools, inputs.accounts, inputs.snapshots, inputs.events,
                              inputs.horizon_end, inputs.global_reserve_floor)
        infos = [derive_card_info(c, req) for c in inputs.cards if ineligible_reason(c, req, accounts) is None]
        st = feasibility_status(shifted, scenario, infos, time_limit_s)
        if st in ("OPTIMAL", "FEASIBLE"):
            return {"shift_days": k, "txn_date": req.txn_date.isoformat(), "status": st}
        if st == "UNKNOWN":
            return {"shift_days": k, "txn_date": req.txn_date.isoformat(), "status": "UNKNOWN"}
    return None
