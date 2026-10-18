"""Independent plan verifier. Pure Python, no solver: recomputes every hard constraint and the
per-account cash timeline from the allocation. The solver's answer is never trusted unverified."""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from decimal import Decimal, ROUND_HALF_UP
from typing import Optional

from .allocation import CardPlanInfo, ModelInputs, _low_series, derive_card_info, ineligible_reason
from .cash import CashEvent, EventClass, Scenario, build_timeline, evaluate_accounts
from .money import apply_rate


@dataclass
class ScenarioCheck:
    scenario_id: str
    ok: bool                              # no reserve breach on any account, and global floor holds
    ok_zero: bool                         # no sub-zero balance on any account
    min_balance_by_account: dict
    min_on_by_account: dict
    end_balance_by_account: dict
    breaches: list                        # [{account, on, balance, gap_to_zero, gap_to_reserve, events}]
    first_breach: Optional[dict]
    global_breaches: list
    assumptions: list


@dataclass
class Verification:
    ok: bool                              # structural checks + decision-scenario cash
    structural_ok: bool
    violations: list
    decision_scenario: str
    checks: dict                          # scenario_id -> ScenarioCheck
    weighted_buffer_days: Decimal
    fees: int
    verified_benefit: int
    potential_benefit: int
    lines: list


def planned_repayment_events(infos: dict, allocation: dict) -> list:
    evs = []
    for cid, amt in allocation.items():
        i = infos[cid]
        evs.append(CashEvent(f"plan_repay_{cid}", i.card.repay_from, i.repay_on, -int(amt), EventClass.PLANNED,
                             "repayment", f"计划还款 {cid}"))
    return evs


def check_scenario(inputs: ModelInputs, infos: dict, allocation: dict, scenario: Scenario) -> ScenarioCheck:
    planned = planned_repayment_events(infos, allocation)
    horizon = max([inputs.horizon_end] + [i.repay_on for i in infos.values()])
    reports = evaluate_accounts(inputs.accounts, inputs.snapshots, inputs.events + planned, scenario, horizon)
    breaches, assumptions = [], []
    for aid, r in reports.items():
        assumptions += [f"{aid}: {a}" for a in r.assumptions]
        for b in r.breaches:
            breaches.append({"account": aid, "on": b.on, "balance": b.balance, "gap_to_zero": b.gap_to_zero,
                             "gap_to_reserve": b.gap_to_reserve, "events": list(b.event_ids)})
    breaches.sort(key=lambda b: (b["on"], b["account"]))
    global_breaches = []
    if inputs.global_reserve_floor > 0:
        tls = {aid: r.timeline for aid, r in reports.items()}
        dates = sorted({p.on for tl in tls.values() for p in tl.points if p.phase == "low"})
        series = {aid: _low_series(tl, dates) for aid, tl in tls.items()}
        for idx, d in enumerate(dates):
            total = sum(series[aid][idx] for aid in series)
            if total < inputs.global_reserve_floor:
                global_breaches.append({"on": d, "total": total, "gap": inputs.global_reserve_floor - total})
    ok = not breaches and not global_breaches
    return ScenarioCheck(scenario.id, ok, all(r.ok_zero for r in reports.values()),
                         {aid: r.min_balance for aid, r in reports.items()},
                         {aid: r.min_on for aid, r in reports.items()},
                         {aid: r.end_balance for aid, r in reports.items()},
                         breaches, breaches[0] if breaches else None, global_breaches, assumptions)


def verify(inputs: ModelInputs, allocation: dict, scenarios: dict, decision_scenario_id: str) -> Verification:
    req = inputs.request
    accounts = inputs.accounts_by_id()
    cards = {c.id: c for c in inputs.cards}
    violations = []
    alloc = {k: int(v) for k, v in allocation.items() if int(v) != 0}
    for cid, amt in alloc.items():
        if cid not in cards:
            violations.append(f"unknown card {cid}")
            continue
        if amt < 0:
            violations.append(f"{cid}: negative amount")
        r = ineligible_reason(cards[cid], req, accounts)
        if r:
            violations.append(f"{cid}: ineligible ({r})")
        if amt > cards[cid].capacity:
            violations.append(f"{cid}: amount {amt} exceeds capacity {cards[cid].capacity}")
        if cards[cid].per_txn_cap is not None and amt > cards[cid].per_txn_cap:
            violations.append(f"{cid}: amount {amt} exceeds per-transaction cap {cards[cid].per_txn_cap}")
        ms = cards[cid].min_split if cards[cid].min_split is not None else req.min_split
        if amt < ms:
            violations.append(f"{cid}: amount {amt} below minimum split {ms}")
    if sum(alloc.values()) != req.amount:
        violations.append(f"amount conservation violated: {sum(alloc.values())} != {req.amount}")
    if len(alloc) > req.k:
        violations.append(f"uses {len(alloc)} cards > allowed {req.k}")
    pool_sums: dict = {}
    for cid, amt in alloc.items():
        if cid in cards and cards[cid].pool_id:
            pool_sums[cards[cid].pool_id] = pool_sums.get(cards[cid].pool_id, 0) + amt
    for pid, s in pool_sums.items():
        cap = inputs.pools.get(pid)
        if cap is None:
            violations.append(f"pool {pid}: no capacity snapshot")
        elif s > cap:
            violations.append(f"pool {pid}: {s} exceeds shared capacity {cap}")
    structural_ok = not violations
    infos = {cid: derive_card_info(cards[cid], req) for cid in alloc if cid in cards}
    checks = {sid: check_scenario(inputs, infos, alloc, sc) for sid, sc in scenarios.items()}
    buffer_num = sum(alloc[cid] * infos[cid].buffer_days for cid in infos)
    wbuf = (Decimal(buffer_num) / Decimal(req.amount)).quantize(Decimal("0.1"), rounding=ROUND_HALF_UP) if req.amount else Decimal(0)
    fees = ben = pot = 0
    lines = []
    for cid, amt in alloc.items():
        c = cards[cid]
        fee = (apply_rate(amt, c.fee_rate, "UP") if c.fee_rate else 0) + (c.fee_fixed if amt > 0 else 0)
        b = apply_rate(amt, c.verified_benefit_rate, "DOWN") if c.verified_benefit_rate else 0
        if c.verified_benefit_cap is not None:
            b = min(b, c.verified_benefit_cap)
        p = apply_rate(amt, c.potential_benefit_rate, "DOWN") if c.potential_benefit_rate else 0
        fees += fee
        ben += b
        pot += p
        i = infos[cid]
        lines.append({"card": cid, "amount": amt, "statement_date": i.cycle.statement_date, "due_date": i.cycle.due_date,
                      "repay_on": i.repay_on, "repay_from": c.repay_from, "buffer_days": i.buffer_days, "fee": fee,
                      "verified_benefit": b, "potential_benefit": p,
                      "cycle_assumptions": list(i.cycle.assumptions),
                      "alternative_cycles": [(x.statement_date, x.due_date) for x in i.all_cycles[1:]]})
    ok = structural_ok and checks[decision_scenario_id].ok
    return Verification(ok, structural_ok, violations, decision_scenario_id, checks, wbuf, fees, ben, pot, lines)
