"""Planning orchestration: data checks -> baseline per scenario -> solve in the decision scenario ->
independent verification in every scenario -> business status, rejections, sensitivity."""
from __future__ import annotations

from dataclasses import dataclass, field, asdict, replace
from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Optional

from .allocation import (ModelInputs, SolveResult, derive_card_info, feasibility_status, first_feasible_date_shift,
                         ineligible_reason, max_affordable_amount, min_extra_cash, solve)
from .cash import Scenario, evaluate_accounts
from .verifier import Verification, verify

BUSINESS_STATUSES = ("NEEDS_DATA", "MODEL_INVALID", "BASELINE_SHORTFALL", "INFEASIBLE", "UNKNOWN",
                     "FEASIBLE_ROBUST", "CONDITIONALLY_FEASIBLE")


@dataclass
class PlanOutcome:
    business_status: str
    profile: str
    decision_scenario: str
    data_issues: list
    baseline: dict                      # scenario_id -> {ok, accounts: {aid: {min_balance, min_on, breaches}}}
    solve: Optional[SolveResult]
    allocation: dict
    verification: Optional[Verification]
    failing_scenarios: list
    rejections: list
    sensitivity: dict
    assumptions: list
    notes: list
    created_at: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())


def _json(o):
    if isinstance(o, (date, datetime)):
        return o.isoformat()
    if isinstance(o, Decimal):
        return str(o)
    if isinstance(o, (set, frozenset)):
        return sorted(o)
    if hasattr(o, "__dataclass_fields__"):
        return asdict(o)
    return str(o)


def baseline_check(inputs: ModelInputs, scenario: Scenario) -> dict:
    reports = evaluate_accounts(inputs.accounts, inputs.snapshots, inputs.events, scenario, inputs.horizon_end)
    out = {"ok": all(r.ok for r in reports.values()), "accounts": {}, "assumptions": []}
    for aid, r in reports.items():
        out["accounts"][aid] = {
            "min_balance": r.min_balance, "min_on": r.min_on, "end_balance": r.end_balance,
            "breaches": [{"on": b.on, "balance": b.balance, "gap_to_zero": b.gap_to_zero,
                          "gap_to_reserve": b.gap_to_reserve} for b in r.breaches],
        }
        out["assumptions"] += [f"{aid}: {a}" for a in r.assumptions]
    return out


def data_issues(inputs: ModelInputs, stale_after_days: int) -> list:
    issues = []
    req = inputs.request
    for a in inputs.accounts:
        s = inputs.snapshots.get(a.id)
        if s is None:
            issues.append({"code": "MISSING_SNAPSHOT", "account": a.id})
            continue
        if s.as_of > req.txn_date:
            issues.append({"code": "SNAPSHOT_AFTER_TXN_DATE", "account": a.id, "as_of": s.as_of})
        elif (req.txn_date - s.as_of).days > stale_after_days:
            issues.append({"code": "STALE_SNAPSHOT", "account": a.id, "as_of": s.as_of, "age_days": (req.txn_date - s.as_of).days})
    for c in inputs.cards:
        try:
            derive_card_info(c, req)
        except ValueError as e:
            issues.append({"code": "BILLING_RULE_INVALID", "card": c.id, "detail": str(e)})
        if c.pool_id and c.pool_id not in inputs.pools:
            issues.append({"code": "MISSING_POOL_SNAPSHOT", "card": c.id, "pool": c.pool_id})
    return issues


def rejection_reasons(inputs: ModelInputs, scenarios: dict, decision_id: str, allocation: dict,
                      chosen_margin: Optional[int]) -> list:
    req = inputs.request
    accounts = inputs.accounts_by_id()
    out = []
    for c in inputs.cards:
        if c.id in allocation:
            continue
        r = ineligible_reason(c, req, accounts)
        if r:
            out.append({"card": c.id, "reason": r})
            continue
        if c.capacity < req.amount:
            entry = {"card": c.id, "reason": "INSUFFICIENT_LIMIT_ALONE", "capacity": c.capacity, "amount": req.amount}
            if req.allow_split:
                entry["note"] = "could only be used in a split; split alternatives scored lower on the active objective tiers"
            out.append(entry)
            continue
        v = verify(inputs, {c.id: req.amount}, {decision_id: scenarios[decision_id]}, decision_id)
        chk = v.checks[decision_id]
        if not chk.ok:
            fb = chk.first_breach
            out.append({"card": c.id, "reason": "CASH_BREACH_ALONE", "first_breach": fb,
                        "all_breaches": chk.breaches, "min_balance": chk.min_balance_by_account})
        else:
            out.append({"card": c.id, "reason": "DOMINATED", "detail": "feasible alone but scored lower on the objective tiers",
                        "min_balance": chk.min_balance_by_account, "buffer_days": str(v.weighted_buffer_days)})
    return out


def plan(inputs: ModelInputs, scenarios: dict, decision_scenario_id: str, profile: str = "cash_safety",
         time_limit_s: float = 10.0, stale_after_days: int = 7, with_sensitivity: bool = True) -> PlanOutcome:
    notes, assumptions = [], []
    issues = data_issues(inputs, stale_after_days)
    if decision_scenario_id not in scenarios:
        issues.append({"code": "UNKNOWN_DECISION_SCENARIO", "scenario": decision_scenario_id})
    if issues:
        return PlanOutcome("NEEDS_DATA", profile, decision_scenario_id, issues, {}, None, {}, None, [], [], {}, [], notes)
    accounts = inputs.accounts_by_id()
    infos = [derive_card_info(c, inputs.request) for c in inputs.cards if ineligible_reason(c, inputs.request, accounts) is None]
    needed_horizon = max([inputs.horizon_end] + [i.repay_on for i in infos])
    if needed_horizon > inputs.horizon_end:
        notes.append(f"horizon extended from {inputs.horizon_end} to {needed_horizon} to cover all planned repayments")
        inputs = replace(inputs, horizon_end=needed_horizon)
    baseline = {sid: baseline_check(inputs, sc) for sid, sc in scenarios.items()}
    for sid, b in baseline.items():
        assumptions += b["assumptions"]
    decision = scenarios[decision_scenario_id]
    if not baseline[decision_scenario_id]["ok"]:
        return PlanOutcome("BASELINE_SHORTFALL", profile, decision_scenario_id, [], baseline, None, {}, None,
                           [sid for sid, b in baseline.items() if not b["ok"]], [], {}, sorted(set(assumptions)),
                           notes + ["baseline already breaches the reserve in the decision scenario; new spending not evaluated"])
    res = solve(inputs, decision, profile, time_limit_s)
    sens: dict = {}
    if res.status in ("INFEASIBLE", "UNKNOWN", "MODEL_INVALID"):
        if res.status == "INFEASIBLE" and with_sensitivity:
            sens[decision_scenario_id] = {
                "min_extra_confirmed_cash": min_extra_cash(inputs, decision, infos),
                "max_affordable_amount": max_affordable_amount(inputs, decision, infos),
                "first_feasible_date_shift": first_feasible_date_shift(inputs, decision),
            }
        rej = rejection_reasons(inputs, scenarios, decision_scenario_id, {}, None)
        return PlanOutcome(res.status, profile, decision_scenario_id, [], baseline, res, {}, None, [], rej, sens,
                           sorted(set(assumptions)), notes + res.notes)
    ver = verify(inputs, res.allocation, scenarios, decision_scenario_id)
    if not ver.ok:
        # solver/verifier disagreement is a defect, never silently accepted
        return PlanOutcome("MODEL_INVALID", profile, decision_scenario_id, [], baseline, res, res.allocation, ver, [], [],
                           {}, sorted(set(assumptions)), notes + ["VERIFIER_REJECTED_SOLVER_SOLUTION"] + ver.violations)
    failing = [sid for sid, chk in ver.checks.items() if not chk.ok]
    for sid, b in baseline.items():
        if not b["ok"] and sid not in failing:
            failing.append(sid)
    if with_sensitivity:
        for sid in failing:
            if baseline[sid]["ok"]:
                sens[sid] = {
                    "min_extra_confirmed_cash": min_extra_cash(inputs, scenarios[sid], infos),
                    "max_affordable_amount": max_affordable_amount(inputs, scenarios[sid], infos),
                    "first_feasible_date_shift": first_feasible_date_shift(inputs, scenarios[sid]),
                }
            else:
                sens[sid] = {"note": "baseline shortfall in this scenario; the gap is in baseline[].accounts[].breaches"}
    status = "FEASIBLE_ROBUST" if not failing else "CONDITIONALLY_FEASIBLE"
    for s in ver.checks.values():
        assumptions += s.assumptions
    rej = rejection_reasons(inputs, scenarios, decision_scenario_id, res.allocation, None)
    return PlanOutcome(status, profile, decision_scenario_id, [], baseline, res, res.allocation, ver, failing, rej, sens,
                       sorted(set(assumptions)), notes + res.notes)
