"""CP-SAT allocation model (OR-Tools) with lexicographic objective tiers and an explicit status
contract.

Decision variables: x_i (integer minor units on card i), y_i (card used). Hard constraints: amount
conservation, per-card capacity, shared capacity layers (credit account, pool), max cards, min
split, per-transaction caps, and per-account cash floors at EVERY checkpoint of the hard
scenario(s), the repayment of card i being x_i plus its fee. Solver statuses are passed through
verbatim: OPTIMAL / FEASIBLE / INFEASIBLE / UNKNOWN / MODEL_INVALID. A time limit never turns
into "no combination available" -- it stays UNKNOWN.

Model 1.1.0 (engine-spec §12): only the input decides the checked horizon (a card repaying
after ``horizon_end`` is excluded, REPAY_AFTER_HORIZON); cards sharing a credit account share
its available credit, and a pool's capacity is net of its members' holds and reservations; fees
leave cash with the repayment; ties left after the last objective tier are broken by the
lexicographically largest allocation in card input order, in the main solve and in the
sensitivity solves, so one input gives one answer for any number of workers; every solver call
of a run ends within the run's time limit; the build-error fallback covers model building and
solving only.
"""

from __future__ import annotations

import hashlib
import json
import time
import uuid
from collections.abc import Sequence
from dataclasses import asdict, dataclass, field, replace
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from fractions import Fraction
from typing import Any

import ortools
from ortools.sat.python import cp_model

from cardflow.planner.engine import MODEL_VERSION
from cardflow.planner.engine.billing import (
    BillingRule,
    BillingRuleError,
    Cycle,
    cycles_for_transaction,
)
from cardflow.planner.engine.cash import EventClass, Scenario, Timeline, build_timeline
from cardflow.planner.engine.money import decimal_text

BIG = 10**13

# Raised by OR-Tools while a model is built when a value cannot be represented in it; the
# engine turns them into a MODEL_INVALID result instead of letting them escape (T-004b). Since
# model 1.1.0 (engine-spec §12.10) only model building and solving are covered: an error in any
# other phase is a defect and propagates.
BUILD_ERRORS = (ValueError, TypeError, OverflowError)

VALIDATION_FAILED = "MODEL_VALIDATION_FAILED: CP-SAT rejected the model (no plan is shown)"


class ModelInvalid(Exception):  # noqa: N818
    pass


def model_build_error(exc: BaseException, where: str) -> str:
    """Note for a model that could not be built: the error CLASS and the phase only, never the
    message (which may quote input values), and no claim about the cause."""
    return f"MODEL_BUILD_ERROR: {type(exc).__name__} {where} (no plan is shown)"


@dataclass(frozen=True)
class CardOption:
    id: str
    account_id: str
    name: str
    raw_available: int  # 银行口径可用额度快照；可为负/超限，原值保留  # noqa: RUF003
    billing_rule: BillingRule
    repay_from: str  # cash account id that will fund the repayment
    uncounted_holds: int = 0  # 快照尚未包含的预授权/占用
    plan_reservations: int = 0  # 其他已采纳计划的预留
    pool_id: str | None = None
    per_txn_cap: int | None = None
    min_split: int | None = None
    channel_ok: bool = True
    currency_ok: bool = True
    status_ok: bool = True
    fee_rate: Decimal = Decimal(0)
    fee_fixed: int = 0
    verified_benefit_rate: Decimal = Decimal(0)  # 已核实收益（进入目标函数）  # noqa: RUF003
    verified_benefit_cap: int | None = None
    potential_benefit_rate: Decimal = Decimal(0)  # 潜在/未核实收益（仅展示，不进入目标函数）  # noqa: RUF003
    posting_delay_min: int = 0
    posting_delay_max: int = 0

    @property
    def capacity(self) -> int:
        """可供新增消费的容量（卡这一层），截为 0；信用账户与池两层同样逐层截零（capacity_layers）。
        raw_available 永远保留原值（含负数/超限）。"""  # noqa: RUF002
        return max(0, self.raw_available - self.uncounted_holds - self.plan_reservations)


@dataclass(frozen=True)
class PlanRequest:
    amount: int
    currency: str
    txn_date: date
    allow_split: bool = False
    max_cards: int = 1
    min_split: int = 1
    payment_lead_days: int = 0  # 建议提前发起还款的天数（现金扣款时点 = 到期日 - lead）  # noqa: RUF003
    channel: str = "pos"

    @property
    def k(self) -> int:
        return self.max_cards if self.allow_split else 1


@dataclass(frozen=True)
class CardPlanInfo:
    card: CardOption
    cycle: Cycle  # conservative cycle (earliest due within posting window)
    all_cycles: tuple
    repay_on: date  # planned cash debit date
    buffer_days: int  # repay_on - txn_date


def derive_card_info(card: CardOption, request: PlanRequest) -> CardPlanInfo:
    cycles = cycles_for_transaction(
        card.billing_rule, request.txn_date, card.posting_delay_min, card.posting_delay_max
    )
    c = cycles[0]
    repay_on = c.due_date - timedelta(days=request.payment_lead_days)
    return CardPlanInfo(card, c, tuple(cycles), repay_on, (repay_on - request.txn_date).days)


def _hash_default(o: object) -> str | list[Any] | dict[str, Any]:
    if isinstance(o, (date, datetime)):
        return o.isoformat()
    if isinstance(o, Decimal):
        return decimal_text(o)  # 0.006 and 0.0060000000 are one value (R3E-11)
    if isinstance(o, (set, frozenset)):
        return sorted(o)
    if hasattr(o, "__dataclass_fields__"):
        return asdict(o)
    if isinstance(o, EventClass):
        return o.value
    raise TypeError(str(type(o)))


@dataclass
class ModelInputs:
    request: PlanRequest
    cards: list
    pools: dict  # pool_id -> available capacity (minor units)
    accounts: list  # CashAccount
    snapshots: dict  # account_id -> Snapshot
    events: list  # CashEvent (existing, without plan)
    horizon_end: date
    global_reserve_floor: int = 0  # 用户整体最低现金（跨账户合计），0 = 不启用  # noqa: RUF003

    def accounts_by_id(self) -> dict:
        return {a.id: a for a in self.accounts}

    def input_hash(self) -> str:
        """Hash of the DATA only (no scenarios, no options); see :func:`run_input_hash`."""
        payload = json.dumps(
            asdict(self), default=_hash_default, sort_keys=True, ensure_ascii=False
        )
        return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def run_input_hash(
    inputs: ModelInputs,
    scenarios: dict[str, Scenario],
    decision_scenario_id: str,
    profile: str,
    time_limit_s: float,
    stale_after_days: int | None,
    workers: int,
    seed: int,
) -> str:
    """Engine-internal hash of a whole run's input: data, scenarios (in order) and options --
    the default ``input_hash`` of :func:`plan` (review R3E-15). Runs entering through the
    protocol record the language-neutral ``protocol_input_hash`` of their document instead."""
    payload = {
        "inputs": asdict(inputs),
        "scenarios": [asdict(s) for s in scenarios.values()],
        "options": {
            "decision_scenario": decision_scenario_id,
            "profile": profile,
            "time_limit_s": repr(float(time_limit_s)),  # 10 and 10.0 are one time limit
            "stale_after_days": stale_after_days,
            "workers": workers,
            "seed": seed,
        },
    }
    text = json.dumps(payload, default=_hash_default, sort_keys=True, ensure_ascii=False)
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


# --- capacity layers and eligibility -----------------------------------------------------------


@dataclass(frozen=True)
class CapacityLayers:
    """Shared capacity for new spending above the card layer (engine-spec §12.3; bank-rules-spec
    §5: card <= credit account <= pool, checked together).

    ``account``: credit accounts with two or more cards in the input -> the account's available
    credit (every card reports it; the smallest report counts) minus the holds and reservations
    of ALL its cards, clamped at 0. ``pool``: pool id -> the pool's available minus the holds and
    reservations of all its member cards, clamped at 0. One pool level (protocol v1)."""

    account: dict[str, int]
    pool: dict[str, int]


def capacity_layers(inputs: ModelInputs) -> CapacityLayers:
    members: dict[str, list[CardOption]] = {}
    for c in inputs.cards:
        members.setdefault(c.account_id, []).append(c)
    account = {
        aid: max(
            0,
            min(c.raw_available for c in cards)
            - sum(c.uncounted_holds + c.plan_reservations for c in cards),
        )
        for aid, cards in members.items()
        if len(cards) > 1
    }
    pool = {
        pid: max(
            0,
            raw
            - sum(
                c.uncounted_holds + c.plan_reservations for c in inputs.cards if c.pool_id == pid
            ),
        )
        for pid, raw in inputs.pools.items()
    }
    return CapacityLayers(account, pool)


def card_limit(card: CardOption, layers: CapacityLayers) -> tuple[int, str]:
    """The largest amount ``card`` can take in this plan, and the layer that sets it (on a tie,
    the outer layer: per-transaction cap, then credit account, then pool)."""
    cap, what = card.capacity, "the card's available credit"
    if card.per_txn_cap is not None and card.per_txn_cap <= cap:
        cap, what = card.per_txn_cap, "the per-transaction cap"
    shared = layers.account.get(card.account_id)
    if shared is not None and shared <= cap:
        cap, what = shared, f"credit account {card.account_id}"
    if card.pool_id and card.pool_id in layers.pool and layers.pool[card.pool_id] <= cap:
        cap, what = layers.pool[card.pool_id], f"pool {card.pool_id}"
    return cap, what


@dataclass(frozen=True)
class Exclusion:
    """Why a card cannot take part in the plan at all (engine-spec §3, hard constraint 6)."""

    code: str
    detail: str | None = None


DATE_DEPENDENT_EXCLUSIONS = frozenset({"REPAY_BEFORE_TXN_DATE"})  # a later date may lift it


def classify(
    card: CardOption,
    inputs: ModelInputs,
    *,
    request: PlanRequest | None = None,
    layers: CapacityLayers | None = None,
) -> tuple[CardPlanInfo | None, Exclusion | None]:
    """``(info, None)`` for a card that can take part, ``(info or None, exclusion)`` otherwise.
    Raises :class:`~cardflow.planner.engine.billing.BillingRuleError` when the card's rule gives
    no cycle for the (possibly shifted) transaction date of ``request``."""
    req = request if request is not None else inputs.request
    layers = layers if layers is not None else capacity_layers(inputs)
    if not card.status_ok:
        return None, Exclusion("CARD_STATUS")
    if not card.currency_ok:
        return None, Exclusion("CURRENCY_NOT_SUPPORTED")
    if not card.channel_ok:
        return None, Exclusion("CHANNEL_NOT_SUPPORTED")
    acct = next((a for a in inputs.accounts if a.id == card.repay_from), None)
    if acct is None:
        return None, Exclusion("REPAY_ACCOUNT_MISSING")
    if not acct.usable_for_repayment:
        return None, Exclusion("REPAY_ACCOUNT_RESTRICTED")
    # Capacity is clamped at zero layer by layer (R-RULE-08): an exhausted credit account or pool
    # leaves its cards nothing; cards outside it are unaffected.
    if card.capacity <= 0:
        return None, Exclusion("NO_CAPACITY", "the card has no capacity left")
    if layers.account.get(card.account_id, 1) <= 0:
        return None, Exclusion(
            "NO_CAPACITY", f"credit account {card.account_id} has no capacity left"
        )
    if card.pool_id and layers.pool.get(card.pool_id, 1) <= 0:
        return None, Exclusion("NO_CAPACITY", f"pool {card.pool_id} has no capacity left")
    min_split = card.min_split if card.min_split is not None else req.min_split
    if min_split > req.amount:
        return None, Exclusion(
            "MIN_SPLIT_ABOVE_AMOUNT", "the minimum part on this card exceeds the amount"
        )
    info = derive_card_info(card, req)
    # The cash repayment (due date - lead days) would precede the transaction itself: such a
    # cycle cannot be planned (and a repayment before the snapshot would look "already paid").
    if info.repay_on < req.txn_date:
        return info, Exclusion("REPAY_BEFORE_TXN_DATE")
    # The cash timeline is checked up to horizon_end and never extended (engine-spec §12.7).
    if info.repay_on > inputs.horizon_end:
        return info, Exclusion("REPAY_AFTER_HORIZON")
    return info, None


def eligible_infos(
    inputs: ModelInputs, *, request: PlanRequest | None = None, skip_rule_errors: bool = False
) -> list[CardPlanInfo]:
    """Cards that can take part, in input order. ``skip_rule_errors``: a card whose rule gives
    no cycle on this date is unavailable that day (the date-shift search, engine-spec §12.9)."""
    layers = capacity_layers(inputs)
    out = []
    for c in inputs.cards:
        try:
            info, exclusion = classify(c, inputs, request=request, layers=layers)
        except BillingRuleError:
            if skip_rule_errors:
                continue
            raise
        if exclusion is None and info is not None:
            out.append(info)
    return out


# --- the model ------------------------------------------------------------------------------

TIERS = {
    "cash_safety": [
        ("min_margin", "max"),
        ("fees", "min"),
        ("net_verified_benefit", "max"),
        ("buffer", "max"),
        ("cards", "min"),
    ],
    "verified_benefit": [
        ("net_verified_benefit", "max"),
        ("min_margin", "max"),
        ("buffer", "max"),
        ("cards", "min"),
    ],
    "fewer_cards": [
        ("cards", "min"),
        ("min_margin", "max"),
        ("net_verified_benefit", "max"),
        ("buffer", "max"),
    ],
}


def _low_series(timeline: Timeline, dates: list[date]) -> list[int]:
    """Intraday-low balance for each date in `dates` (carry-forward when the account has no
    event that day)."""
    by_day: dict[date, list[int | None]] = {}  # day -> [low, end]
    last_end = timeline.snapshot.balance  # noqa: F841
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
    caps: dict = field(default_factory=dict)  # card id -> upper bound of x (the card's limit)


def build_model(
    inputs: ModelInputs,
    hard_scenarios: list[Scenario],
    infos: list[CardPlanInfo],
    prior_bounds: Sequence[tuple[str, str, int]] = (),
    amount_var: bool = False,
    extra_cash_vars: bool = False,
) -> BuiltModel:
    req = inputs.request
    if req.amount <= 0:
        raise ModelInvalid("amount must be positive")
    if req.k < 1:
        raise ModelInvalid("max_cards must be >= 1")
    if not infos:
        raise ModelInvalid("no eligible cards")
    if any(i.repay_on > inputs.horizon_end for i in infos):
        raise ModelInvalid("a card repays after horizon_end")  # excluded by classify()
    layers = capacity_layers(inputs)
    m = cp_model.CpModel()
    x, y, caps = {}, {}, {}
    for info in infos:
        c = info.card
        cap = max(0, card_limit(c, layers)[0])
        caps[c.id] = cap
        x[c.id] = m.new_int_var(0, cap, f"x_{c.id}")
        y[c.id] = m.new_bool_var(f"y_{c.id}")
        m.add(x[c.id] <= cap * y[c.id])
        ms = c.min_split if c.min_split is not None else req.min_split
        if ms > 0:
            m.add(x[c.id] >= ms * y[c.id])
    total = sum(x.values())
    if amount_var:
        mprime = m.new_int_var(0, req.amount, "amount_affordable")
        m.add(total == mprime)
    else:
        mprime = None
        m.add(total == req.amount)
    m.add(sum(y.values()) <= req.k)
    # shared capacity layers (engine-spec §12.3): the credit account of cards that share one,
    # then the pool -- protocol v1 has one pool level
    by_account: dict[str, list] = {}
    by_pool: dict[str, list] = {}
    for info in infos:
        by_account.setdefault(info.card.account_id, []).append(x[info.card.id])
        if info.card.pool_id:
            by_pool.setdefault(info.card.pool_id, []).append(x[info.card.id])
    for aid, members in by_account.items():
        if aid in layers.account:
            m.add(sum(members) <= layers.account[aid])
    for pid, members in by_pool.items():
        if pid not in inputs.pools:
            raise ModelInvalid(f"pool {pid} has no capacity snapshot")
        m.add(sum(members) <= layers.pool[pid])
    # fees (rounded UP; paid in cash with the repayment, §12.6) and verified benefits (rounded
    # DOWN, capped; never cash)
    fee_of, fee_terms, ben_terms = {}, [], []
    for info in infos:
        c = info.card
        if c.fee_rate or c.fee_fixed:
            f = m.new_int_var(0, BIG, f"fee_{c.id}")
            if c.fee_rate:
                fr = Fraction(Decimal(str(c.fee_rate)))
                m.add(
                    f * fr.denominator
                    >= x[c.id] * fr.numerator + c.fee_fixed * fr.denominator * y[c.id]
                )
            else:
                m.add(f == c.fee_fixed * y[c.id])
            fee_of[c.id] = f
            fee_terms.append(f)
        if c.verified_benefit_rate:
            cap = c.verified_benefit_cap if c.verified_benefit_cap is not None else BIG
            b = m.new_int_var(0, cap, f"benefit_{c.id}")
            br = Fraction(Decimal(str(c.verified_benefit_rate)))
            m.add(b * br.denominator <= x[c.id] * br.numerator)
            ben_terms.append(b)
    repayment = {cid: x[cid] + fee_of[cid] if cid in fee_of else x[cid] for cid in x}
    # cash floors at every checkpoint of every hard scenario
    margin = m.new_int_var(-BIG, BIG, "min_margin")
    extra = {}
    if extra_cash_vars:
        for a in inputs.accounts:
            extra[a.id] = m.new_int_var(0, BIG, f"extra_cash_{a.id}")
    checkpoint_days: dict[str, set[date]] = {}
    for i in infos:  # every candidate repayment day is a checkpoint of its cash account
        checkpoint_days.setdefault(i.card.repay_from, set()).add(i.repay_on)
    n_checkpoints = 0
    baseline_infeasible = False
    for sc in hard_scenarios:
        timelines = {
            a.id: build_timeline(
                a,
                inputs.snapshots[a.id],
                inputs.events,
                sc,
                inputs.horizon_end,
                checkpoint_days=checkpoint_days.get(a.id, ()),
            )
            for a in inputs.accounts
        }
        all_dates = sorted(
            {p.on for tl in timelines.values() for p in tl.points if p.phase == "low"}
        )
        series = {aid: _low_series(tl, all_dates) for aid, tl in timelines.items()}
        for a in inputs.accounts:
            for d, base in zip(all_dates, series[a.id], strict=True):
                terms = [
                    repayment[i.card.id]
                    for i in infos
                    if i.card.repay_from == a.id and i.repay_on <= d
                ]
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
                terms = [repayment[i.card.id] for i in infos if i.repay_on <= d]
                base_total = sum(series[a.id][idx] for a in inputs.accounts)
                lhs = base_total + (sum(extra.values()) if extra else 0) - sum(terms)
                if not terms and not extra:
                    if base_total < inputs.global_reserve_floor:
                        baseline_infeasible = True
                    continue
                m.add(lhs >= inputs.global_reserve_floor)
    if baseline_infeasible:
        m.add(total <= -1)  # provably infeasible: the baseline already breaches the floor
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
    return BuiltModel(m, x, y, exprs, infos, n_checkpoints, extra, caps)


@dataclass
class TierResult:
    name: str
    sense: str
    status: str
    value: int | None
    bound: int | None
    wall_time_s: float


@dataclass
class SolveResult:
    run_id: str
    status: str  # OPTIMAL | FEASIBLE | INFEASIBLE | UNKNOWN | MODEL_INVALID
    profile: str
    scenario_id: str
    allocation: dict  # card_id -> amount (only cards with amount > 0)
    tiers: list
    proven_optimal: bool
    wall_time_s: float
    solver_version: str
    model_version: str
    input_hash: str
    time_limit_s: float
    workers: int  # CP-SAT num_workers used for every tier
    seed: int  # CP-SAT random_seed used for every tier
    checkpoints: int
    notes: list = field(default_factory=list)
    created_at: str = ""


def _solver(time_limit_s: float, workers: int, seed: int) -> cp_model.CpSolver:
    s = cp_model.CpSolver()
    s.parameters.max_time_in_seconds = time_limit_s
    s.parameters.num_workers = workers
    s.parameters.random_seed = seed
    return s


def _share(deadline: float, parts: int) -> float:
    """An equal share of the time left until ``deadline`` for one of ``parts`` solver calls (a
    call that finishes early leaves its rest to the later ones)."""
    return max(0.0, deadline - time.monotonic()) / max(1, parts)


def _validate(model: cp_model.CpModel) -> None:
    """CP-SAT's own model check (incl. integer overflow); its text may quote coefficients and
    constants, so only the fact is reported (review R3E-12)."""
    if model.validate():
        raise ModelInvalid(VALIDATION_FAILED)


def _hint(model: cp_model.CpModel, variables: dict[str, Any], values: dict[str, int]) -> None:
    model.clear_hints()
    for key, var in variables.items():
        if key in values:
            model.add_hint(var, values[key])


@dataclass
class _Group:
    """Variables fixed one after the other by :func:`_lex_max`, whose values sum to ``total``."""

    variables: dict[str, Any]  # key -> CP-SAT variable, in tie-break order
    upper: dict[str, int]
    total: int


def _lex_max(
    model: cp_model.CpModel,
    groups: list[_Group],
    values: dict[str, int],
    deadline: float,
    workers: int,
    seed: int,
) -> tuple[dict[str, int], bool]:
    """Deterministic tie-break among the optima the model still admits (engine-spec §12.5):
    fix the variables one by one, in order, each to the largest value the remaining optima
    allow. The result is unique whatever the search (workers, seed, threads), provided every
    step is proven optimal; ``values`` is a solution of the model (the incumbent). Returns the
    canonical values and whether every step completed within ``deadline``."""
    every = {k: v for g in groups for k, v in g.variables.items()}
    steps = len(every)
    for group in groups:
        fixed = 0
        for key, var in group.variables.items():
            left = group.total - fixed
            # x <= its upper bound and <= what the group has left: an incumbent already there
            # is the maximum, no solve needed
            if values[key] != min(group.upper[key], left):
                model.maximize(var)
                _hint(model, every, values)
                s = _solver(_share(deadline, steps), workers, seed)
                st = s.solve(model)
                if st not in (cp_model.OPTIMAL, cp_model.FEASIBLE):
                    return values, False
                values = {k: s.value(v) for k, v in every.items()}
                if st != cp_model.OPTIMAL:
                    return values, False
            model.add(var == values[key])
            fixed += values[key]
            steps -= 1
    return values, True


TIE_BREAK_INCOMPLETE = (
    "TIE_BREAK_INCOMPLETE: the time limit ended the tie-break; the allocation is optimal on "
    "every tier but another optimal allocation may be returned on a re-run"
)


def solve(
    inputs: ModelInputs,
    scenario: Scenario,
    profile: str,
    time_limit_s: float = 10.0,
    workers: int = 8,
    seed: int = 0,
    hard_scenarios: list | None = None,
    *,
    run_id: str | None = None,
    input_hash: str | None = None,
) -> SolveResult:
    """Lexicographic CP-SAT solve, then the deterministic tie-break (engine-spec §12.5).

    ``time_limit_s`` bounds every CP-SAT call of this solve: each objective tier gets an equal
    share of the time left, one share is kept for the tie-break. ``run_id``/``input_hash``
    default to a fresh uuid4 and :func:`run_input_hash` of this solve's input; ``plan()``
    passes its own so that one run carries one id and one hash."""
    t0 = time.monotonic()
    deadline = t0 + time_limit_s
    hard = hard_scenarios or [scenario]
    base = dict(  # noqa: C408
        run_id=run_id if run_id is not None else str(uuid.uuid4()),
        profile=profile,
        scenario_id=scenario.id,
        solver_version=ortools.__version__,
        model_version=MODEL_VERSION,
        input_hash=input_hash
        if input_hash is not None
        else run_input_hash(
            inputs, {s.id: s for s in hard}, scenario.id, profile, time_limit_s, None, workers, seed
        ),
        time_limit_s=time_limit_s,
        workers=workers,
        seed=seed,
        created_at=datetime.now(timezone.utc).isoformat(),  # noqa: UP017
    )

    def result(status: str, notes: list, **values: Any) -> SolveResult:  # noqa: ANN401
        values.setdefault("allocation", {})
        values.setdefault("proven_optimal", False)
        return SolveResult(
            status=status,
            tiers=tiers_out,
            wall_time_s=time.monotonic() - t0,
            checkpoints=checkpoints,
            notes=notes,
            **values,
            **base,
        )

    tiers_out: list[TierResult] = []
    checkpoints = 0
    if profile not in TIERS:
        return result("MODEL_INVALID", [f"unknown profile {profile}"])
    layers = capacity_layers(inputs)
    notes, infos = [], []
    for c in inputs.cards:
        info, exclusion = classify(c, inputs, layers=layers)
        if exclusion is not None or info is None:
            notes.append(f"{c.id}: excluded ({exclusion.code if exclusion else 'UNKNOWN'})")
            continue
        infos.append(info)
    tier_list = TIERS[profile]
    try:
        built = build_model(inputs, hard, infos)
        checkpoints = built.checkpoints
        _validate(built.model)
    except ModelInvalid as e:
        return result("MODEL_INVALID", [*notes, str(e)])
    except BUILD_ERRORS as e:
        return result(
            "MODEL_INVALID", [*notes, model_build_error(e, "while building the CP-SAT model")]
        )
    allocation: dict[str, int] = {}
    values: dict[str, int] | None = None
    proven = True
    for k, (name, sense) in enumerate(tier_list):
        expr = built.exprs[name]
        if isinstance(expr, int):
            tiers_out.append(TierResult(name, sense, "SKIPPED_CONSTANT", expr, expr, 0.0))
            continue
        try:
            (built.model.maximize if sense == "max" else built.model.minimize)(expr)
            _validate(built.model)
        except ModelInvalid as e:
            return result("MODEL_INVALID", [*notes, str(e)])
        except BUILD_ERRORS as e:
            return result(
                "MODEL_INVALID", [*notes, model_build_error(e, "while building the CP-SAT model")]
            )
        if values is not None:
            _hint(built.model, built.x, values)
        # an equal share of the time left; one share stays for the tie-break
        s = _solver(_share(deadline, len(tier_list) - k + 1), workers, seed)
        st = s.solve(built.model)
        sname = s.status_name(st)
        if st in (cp_model.OPTIMAL, cp_model.FEASIBLE):
            val = int(s.value(expr))
            bnd = int(round(s.best_objective_bound))  # noqa: RUF046
            tiers_out.append(TierResult(name, sense, sname, val, bnd, s.wall_time))
            values = {cid: s.value(v) for cid, v in built.x.items()}
            allocation = {cid: v for cid, v in values.items() if v > 0}
            built.model.add(expr >= val) if sense == "max" else built.model.add(expr <= val)
            if st == cp_model.FEASIBLE:
                proven = False
                notes.append(
                    f"tier {name}: time limit reached, value {val} not proven optimal (bound {bnd})"
                )
        elif st == cp_model.INFEASIBLE:
            tiers_out.append(TierResult(name, sense, sname, None, None, s.wall_time))
            return result("INFEASIBLE", notes)
        elif st == cp_model.MODEL_INVALID:
            return result("MODEL_INVALID", [*notes, "solver reported MODEL_INVALID"])
        else:  # UNKNOWN
            tiers_out.append(TierResult(name, sense, sname, None, None, s.wall_time))
            if not allocation:
                notes.append(
                    "time limit reached before any solution; this is NOT a proof of infeasibility"
                )
                return result("UNKNOWN", notes)
            notes.append(
                f"tier {name}: UNKNOWN (time limit); keeping best solution from earlier tiers"
            )
            proven = False
            break
    if proven and values is not None:
        group = _Group(dict(built.x), built.caps, inputs.request.amount)
        values, complete = _lex_max(built.model, [group], values, deadline, workers, seed)
        allocation = {cid: v for cid, v in values.items() if v > 0}
        if not complete:
            notes.append(TIE_BREAK_INCOMPLETE)
    status = "OPTIMAL" if proven else "FEASIBLE"
    return result(status, notes, allocation=allocation, proven_optimal=proven)


# --- sensitivity (engine-spec §5/§6); every function bounds its CP-SAT calls by time_limit_s ---


def _model_invalid(exc: BaseException) -> dict[str, Any]:
    if isinstance(exc, ModelInvalid):
        return {"status": "MODEL_INVALID", "detail": str(exc)}
    return {
        "status": "MODEL_INVALID",
        "detail": model_build_error(exc, "while building the CP-SAT model"),
    }


def feasibility_status(
    inputs: ModelInputs,
    scenario: Scenario,
    infos: list,
    time_limit_s: float = 2.0,
    *,
    workers: int = 8,
    seed: int = 0,
) -> str:
    try:
        built = build_model(inputs, [scenario], infos)
        _validate(built.model)
    except (ModelInvalid, *BUILD_ERRORS):
        return "MODEL_INVALID"
    s = _solver(time_limit_s, workers, seed)
    return s.status_name(s.solve(built.model))


def min_extra_cash(
    inputs: ModelInputs,
    scenario: Scenario,
    infos: list,
    time_limit_s: float = 5.0,
    *,
    workers: int = 8,
    seed: int = 0,
) -> dict[str, Any]:
    """Smallest additional CONFIRMED cash (per account, available from the snapshot date) that
    makes the plan feasible. Ties: the canonical allocation, then the extra cash on the earliest
    account in input order (engine-spec §12.5)."""
    deadline = time.monotonic() + time_limit_s
    try:
        built = build_model(inputs, [scenario], infos, extra_cash_vars=True)
        built.model.minimize(built.exprs["extra_cash"])
        _validate(built.model)
    except (ModelInvalid, *BUILD_ERRORS) as e:
        return _model_invalid(e)
    s = _solver(_share(deadline, 2), workers, seed)
    st = s.solve(built.model)
    name = s.status_name(st)
    if st not in (cp_model.OPTIMAL, cp_model.FEASIBLE):
        return {"status": name}
    total = int(s.value(built.exprs["extra_cash"]))
    xs = {f"x:{cid}": v for cid, v in built.x.items()}
    extras = {f"extra:{aid}": v for aid, v in built.extra.items()}
    values = {k: s.value(v) for k, v in (xs | extras).items()}
    out: dict[str, Any] = {"status": name}
    if st == cp_model.OPTIMAL:
        built.model.add(built.exprs["extra_cash"] <= total)
        groups = [
            _Group(xs, {f"x:{c}": built.caps[c] for c in built.x}, inputs.request.amount),
            _Group(extras, dict.fromkeys(extras, BIG), total),
        ]
        values, complete = _lex_max(built.model, groups, values, deadline, workers, seed)
        if not complete:
            out["detail"] = TIE_BREAK_INCOMPLETE
    out["extra_cash_by_account"] = {aid: values[f"extra:{aid}"] for aid in built.extra}
    out["total"] = total
    out["allocation"] = {c: values[f"x:{c}"] for c in built.x if values[f"x:{c}"] > 0}
    return out


def max_affordable_amount(
    inputs: ModelInputs,
    scenario: Scenario,
    infos: list,
    time_limit_s: float = 5.0,
    *,
    workers: int = 8,
    seed: int = 0,
) -> dict[str, Any]:
    """Largest amount (at most the request's) feasible in ``scenario``, with the canonical
    allocation among those that reach it (engine-spec §12.5)."""
    deadline = time.monotonic() + time_limit_s
    try:
        built = build_model(inputs, [scenario], infos, amount_var=True)
        built.model.maximize(built.exprs["amount_affordable"])
        _validate(built.model)
    except (ModelInvalid, *BUILD_ERRORS) as e:
        return _model_invalid(e)
    s = _solver(_share(deadline, 2), workers, seed)
    st = s.solve(built.model)
    name = s.status_name(st)
    if st not in (cp_model.OPTIMAL, cp_model.FEASIBLE):
        return {"status": name}
    amount = int(s.value(built.exprs["amount_affordable"]))
    values = {cid: s.value(v) for cid, v in built.x.items()}
    out: dict[str, Any] = {"status": name}
    if st == cp_model.OPTIMAL:
        built.model.add(built.exprs["amount_affordable"] >= amount)
        group = _Group(dict(built.x), built.caps, amount)
        values, complete = _lex_max(built.model, [group], values, deadline, workers, seed)
        if not complete:
            out["detail"] = TIE_BREAK_INCOMPLETE
    out["amount"] = amount
    out["allocation"] = {cid: v for cid, v in values.items() if v > 0}
    return out


def first_feasible_date_shift(
    inputs: ModelInputs,
    scenario: Scenario,
    max_shift_days: int = 45,
    time_limit_s: float = 45.0,
    *,
    workers: int = 8,
    seed: int = 0,
    step_limit_s: float = 1.0,
) -> dict | None:
    """Earliest later transaction date (same amount) for which the hard scenario is feasible,
    if any within range; ``None`` = none.

    Cards are re-classified on every shifted date; a card whose rule gives no cycle on that date
    (e.g. its version ended -- ``effective_to``) is unavailable that day (engine-spec §12.9).
    ``time_limit_s`` bounds the whole search, ``step_limit_s`` each date; a date the time left
    cannot decide is reported as UNKNOWN (not as "no feasible date")."""
    deadline = time.monotonic() + time_limit_s
    for k in range(1, max_shift_days + 1):
        req = replace(inputs.request, txn_date=inputs.request.txn_date + timedelta(days=k))
        shifted = replace(inputs, request=req)
        infos = eligible_infos(shifted, skip_rule_errors=True)
        if not infos:
            continue  # no card can take part on this date
        found = {"shift_days": k, "txn_date": req.txn_date.isoformat()}
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return {**found, "status": "UNKNOWN"}
        st = feasibility_status(
            shifted, scenario, infos, min(step_limit_s, remaining), workers=workers, seed=seed
        )
        if st in ("OPTIMAL", "FEASIBLE", "UNKNOWN"):
            return {**found, "status": st}
        if st == "MODEL_INVALID":
            return {
                "status": "MODEL_INVALID",
                "detail": "the CP-SAT model of a shifted date could not be built or solved",
            }
    return None
