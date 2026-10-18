"""Planning orchestration: data checks -> baseline per scenario -> solve in the decision scenario ->
independent verification in every scenario -> business status, rejections, sensitivity.

Model 1.1.0 (engine-spec §12): only FEASIBLE_ROBUST / CONDITIONALLY_FEASIBLE carry an
allocation (a verifier-rejected one is kept under ``diagnostics`` only); the baseline check
includes the global floor; one time limit bounds every CP-SAT call of the run; a failing
sensitivity item is marked as such without failing the run; model-building errors are caught
where models are built -- an exception of any other phase is a defect and propagates.
"""

from __future__ import annotations

import time
import uuid
from collections.abc import Callable
from dataclasses import asdict, dataclass, field, replace
from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Any

import ortools

from cardflow.planner.engine import MODEL_VERSION
from cardflow.planner.engine.allocation import (
    DATE_DEPENDENT_EXCLUSIONS,
    ModelInputs,
    SolveResult,
    capacity_layers,
    card_limit,
    classify,
    derive_card_info,
    eligible_infos,
    first_feasible_date_shift,
    max_affordable_amount,
    min_extra_cash,
    run_input_hash,
    solve,
)
from cardflow.planner.engine.billing import BillingRuleError
from cardflow.planner.engine.cash import Scenario, evaluate_accounts
from cardflow.planner.engine.verifier import Verification, global_floor_breaches, verify

__all__ = [
    "ACTIONABLE_STATUSES",
    "BUSINESS_STATUSES",
    "PlanOutcome",
    "baseline_check",
    "data_issues",
    "plan",
    "rejection_reasons",
    "run_input_hash",
]

BUSINESS_STATUSES = (
    "NEEDS_DATA",
    "MODEL_INVALID",
    "BASELINE_SHORTFALL",
    "INFEASIBLE",
    "UNKNOWN",
    "FEASIBLE_ROBUST",
    "CONDITIONALLY_FEASIBLE",
)
# The only statuses that carry an executable plan (engine-spec §12.1).
ACTIONABLE_STATUSES = ("FEASIBLE_ROBUST", "CONDITIONALLY_FEASIBLE")
# The main solve (objective tiers and tie-break) may use this share of the run's time limit;
# the sensitivity solves share what is left of it (engine-spec §12.9).
MAIN_SOLVE_SHARE = 0.5
NO_CARD = "no card can take part on the transaction date"
NO_TIME = "the run's time limit was used up before this item"
NOT_COMPARED = {
    "UNKNOWN": "feasible alone; not compared: no solution was found within the time limit",
    "MODEL_INVALID": "feasible alone; not compared: the model could not be solved",
    "INFEASIBLE": "feasible alone; not compared: the solver reported the decision scenario "
    "infeasible",
}


@dataclass
class PlanOutcome:
    business_status: str
    profile: str
    decision_scenario: str
    data_issues: list
    baseline: dict  # scenario_id -> {ok, accounts: {...}, global_breaches, assumptions}
    solve: SolveResult | None
    allocation: dict  # empty unless business_status is actionable (engine-spec §12.1)
    verification: Verification | None  # None unless business_status is actionable
    failing_scenarios: list
    rejections: list
    sensitivity: dict
    assumptions: list
    notes: list
    created_at: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())  # noqa: UP017
    # Run record (engine-spec §6/§11), set by plan() on EVERY outcome -- also when no solver
    # ran (NEEDS_DATA, BASELINE_SHORTFALL). When a solver ran, ``solve`` repeats these values.
    run_id: str = field(kw_only=True)
    input_hash: str = field(kw_only=True)  # hash of the caller's input, before any adjustment
    model_version: str = field(kw_only=True)
    solver_version: str = field(kw_only=True)
    time_limit_s: float = field(kw_only=True)
    workers: int = field(kw_only=True)
    seed: int = field(kw_only=True)
    # Non-actionable outcomes only: what a defect report needs and nothing anyone may show or
    # adopt. VERIFIER_REJECTED_SOLVER_SOLUTION: {code, rejected_allocation, rejected_verification}.
    diagnostics: dict | None = field(default=None, kw_only=True)


def _json(o: object) -> str | list[Any] | dict[str, Any]:
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
    """The scenario's cash check WITHOUT the new spend: every account against its reserve and,
    since model 1.1.0, the sum of all accounts against the global floor (engine-spec §12.8, the
    verifier's rule)."""
    reports = evaluate_accounts(
        inputs.accounts, inputs.snapshots, inputs.events, scenario, inputs.horizon_end
    )
    global_breaches = global_floor_breaches(reports, inputs.global_reserve_floor)
    out = {
        "ok": all(r.ok for r in reports.values()) and not global_breaches,
        "accounts": {},
        "global_breaches": global_breaches,
        "assumptions": [],
    }
    for aid, r in reports.items():
        out["accounts"][aid] = {
            "min_balance": r.min_balance,
            "min_on": r.min_on,
            "end_balance": r.end_balance,
            "breaches": [
                {
                    "on": b.on,
                    "balance": b.balance,
                    "gap_to_zero": b.gap_to_zero,
                    "gap_to_reserve": b.gap_to_reserve,
                }
                for b in r.breaches
            ],
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
            issues.append(
                {
                    "code": "STALE_SNAPSHOT",
                    "account": a.id,
                    "as_of": s.as_of,
                    "age_days": (req.txn_date - s.as_of).days,
                }
            )
    for c in inputs.cards:
        try:
            derive_card_info(c, req)
        except BillingRuleError as e:
            issues.append({"code": "BILLING_RULE_INVALID", "card": c.id, "detail": str(e)})
        if c.pool_id and c.pool_id not in inputs.pools:
            issues.append({"code": "MISSING_POOL_SNAPSHOT", "card": c.id, "pool": c.pool_id})
    return issues


def rejection_reasons(
    inputs: ModelInputs,
    scenarios: dict,
    decision_id: str,
    allocation: dict,
    solver_status: str | None = None,
) -> list:
    """Why every card outside ``allocation`` is not in it (engine-spec §6). ``solver_status``
    is the main solve's: DOMINATED only when it produced a solution to compare with
    (OPTIMAL/FEASIBLE); a card feasible alone in any other case was NOT_COMPARED."""
    req = inputs.request
    layers = capacity_layers(inputs)
    out = []
    for c in inputs.cards:
        if c.id in allocation:
            continue
        _, exclusion = classify(c, inputs, layers=layers)
        if exclusion:
            entry: dict[str, Any] = {"card": c.id, "reason": exclusion.code}
            if exclusion.detail:
                entry["detail"] = exclusion.detail
            out.append(entry)
            continue
        cap, binding = card_limit(c, layers)  # card, per-transaction cap, account, pool
        if cap < req.amount:
            entry = {
                "card": c.id,
                "reason": "INSUFFICIENT_LIMIT_ALONE",
                "capacity": cap,
                "amount": req.amount,
                "detail": f"limited by {binding}",
            }
            if req.allow_split:
                entry["note"] = (
                    "could only be used in a split; split alternatives scored lower on the active "
                    "objective tiers"
                )
            out.append(entry)
            continue
        v = verify(inputs, {c.id: req.amount}, {decision_id: scenarios[decision_id]}, decision_id)
        chk = v.checks[decision_id]
        if not chk.ok:
            entry = {
                "card": c.id,
                "reason": "CASH_BREACH_ALONE",
                "first_breach": chk.first_breach,
                "all_breaches": chk.breaches,
                "min_balance": chk.min_balance_by_account,
            }
            if not chk.breaches:
                entry["detail"] = "the sum over all cash accounts falls below the global floor"
            out.append(entry)
        elif solver_status in ("OPTIMAL", "FEASIBLE"):
            out.append(
                {
                    "card": c.id,
                    "reason": "DOMINATED",
                    "detail": "feasible alone but scored lower on the objective tiers",
                    "min_balance": chk.min_balance_by_account,
                    "buffer_days": str(v.weighted_buffer_days),
                }
            )
        else:
            out.append(
                {
                    "card": c.id,
                    "reason": "NOT_COMPARED",
                    "detail": NOT_COMPARED.get(solver_status or "", NOT_COMPARED["UNKNOWN"]),
                    "min_balance": chk.min_balance_by_account,
                    "buffer_days": str(v.weighted_buffer_days),
                }
            )
    return out


def _item(compute: Callable[[float], Any], deadline: float, parts: int) -> Any:  # noqa: ANN401
    """One sensitivity item with an equal share of the time left (engine-spec §12.9)."""
    left = deadline - time.monotonic()
    if left <= 0:
        return {"status": "NOT_RUN", "detail": NO_TIME}
    return compute(left / parts)


def _sensitivity(
    inputs: ModelInputs, scenario: Scenario, infos: list, budget_s: float, cp: dict[str, int]
) -> dict[str, Any]:
    deadline = time.monotonic() + budget_s
    out: dict[str, Any] = {}
    out["min_extra_confirmed_cash"] = _item(
        lambda t: min_extra_cash(inputs, scenario, infos, t, **cp), deadline, 3
    )
    out["max_affordable_amount"] = _item(
        lambda t: max_affordable_amount(inputs, scenario, infos, t, **cp), deadline, 2
    )
    out["first_feasible_date_shift"] = _item(
        lambda t: first_feasible_date_shift(inputs, scenario, time_limit_s=t, **cp), deadline, 1
    )
    return out


def plan(
    inputs: ModelInputs,
    scenarios: dict,
    decision_scenario_id: str,
    profile: str = "cash_safety",
    time_limit_s: float = 10.0,
    stale_after_days: int = 7,
    with_sensitivity: bool = True,
    *,
    workers: int = 8,
    seed: int = 0,
    input_hash: str | None = None,
    run_id: str | None = None,
) -> PlanOutcome:
    """Plan one transaction (engine-spec §5, §12).

    ``workers``/``seed`` go to every CP-SAT call of the run (tiers, tie-break and sensitivity;
    ADR-004: 8 workers, fixed seed; the tie-break makes the answer independent of the workers).
    ``time_limit_s`` bounds every CP-SAT call of the run: the main solve gets at most
    ``MAIN_SOLVE_SHARE`` of it, the sensitivity solves share what is left until ``time_limit_s``
    has elapsed since the start. ``input_hash`` defaults to :func:`run_input_hash` of the
    caller's input (data, scenarios and options); protocol runs pass the language-neutral
    ``protocol_input_hash`` of their document instead. ``run_id`` defaults to a fresh uuid4
    (API-51 pre-allocates one and passes it). Both, with the versions, time limit, workers and
    seed, form the run record carried by every outcome.

    A value the CP-SAT model cannot represent ends the run as MODEL_INVALID (the note names the
    error class only); errors of any other phase propagate (engine-spec §12.10)."""
    started = time.monotonic()
    deadline = started + time_limit_s
    record: dict[str, Any] = {
        "run_id": run_id if run_id is not None else str(uuid.uuid4()),
        "input_hash": input_hash
        if input_hash is not None
        else run_input_hash(
            inputs,
            scenarios,
            decision_scenario_id,
            profile,
            time_limit_s,
            stale_after_days,
            workers,
            seed,
        ),
        "model_version": MODEL_VERSION,
        "solver_version": ortools.__version__,
        "time_limit_s": time_limit_s,
        "workers": workers,
        "seed": seed,
    }

    def outcome(status: str, **values: Any) -> PlanOutcome:  # noqa: ANN401
        parts: dict[str, Any] = {
            "data_issues": [],
            "baseline": {},
            "solve": None,
            "allocation": {},
            "verification": None,
            "failing_scenarios": [],
            "rejections": [],
            "sensitivity": {},
            "assumptions": [],
            "notes": [],
        }
        parts.update(values)
        return PlanOutcome(status, profile, decision_scenario_id, **parts, **record)

    issues = data_issues(inputs, stale_after_days)
    if decision_scenario_id not in scenarios:
        issues.append({"code": "UNKNOWN_DECISION_SCENARIO", "scenario": decision_scenario_id})
    if issues:
        return outcome("NEEDS_DATA", data_issues=issues)
    baseline = {sid: baseline_check(inputs, sc) for sid, sc in scenarios.items()}
    assumptions = [a for b in baseline.values() for a in b["assumptions"]]
    decision = scenarios[decision_scenario_id]
    if not baseline[decision_scenario_id]["ok"]:
        return outcome(
            "BASELINE_SHORTFALL",
            baseline=baseline,
            failing_scenarios=[sid for sid, b in baseline.items() if not b["ok"]],
            assumptions=sorted(set(assumptions)),
            notes=[
                "baseline already breaches the reserve in the decision scenario; "
                "new spending not evaluated"
            ],
        )
    infos = eligible_infos(inputs)
    cp = {"workers": workers, "seed": seed}  # every CP-SAT call uses the run's settings
    if not infos:
        # Every card was excluded before modelling (engine-spec §3, hard constraint 6): no plan
        # can exist. That is a business answer explained by the rejections (INFEASIBLE), not a
        # defect of the model or its input (MODEL_INVALID). The main solve does not run; a later
        # transaction date is still searched when an exclusion depends on the date (§12.9).
        rejections = rejection_reasons(inputs, scenarios, decision_scenario_id, {}, None)
        sensitivity = {}
        if with_sensitivity and any(r["reason"] in DATE_DEPENDENT_EXCLUSIONS for r in rejections):
            sensitivity[decision_scenario_id] = {
                "min_extra_confirmed_cash": {"status": "NOT_RUN", "detail": NO_CARD},
                "max_affordable_amount": {"status": "NOT_RUN", "detail": NO_CARD},
                "first_feasible_date_shift": _item(
                    lambda t: first_feasible_date_shift(inputs, decision, time_limit_s=t, **cp),
                    deadline,
                    1,
                ),
            }
        return outcome(
            "INFEASIBLE",
            baseline=baseline,
            rejections=rejections,
            sensitivity=sensitivity,
            assumptions=sorted(set(assumptions)),
            notes=["NO_ELIGIBLE_CARDS: every card was excluded before modelling (see rejections)"],
        )
    res = solve(
        inputs,
        decision,
        profile,
        time_limit_s * MAIN_SOLVE_SHARE,
        workers,
        seed,
        run_id=record["run_id"],
        input_hash=record["input_hash"],
    )
    res = replace(res, time_limit_s=time_limit_s)  # the run record's limit is the run's
    if res.status in ("INFEASIBLE", "UNKNOWN", "MODEL_INVALID"):
        sensitivity = {}
        if res.status == "INFEASIBLE" and with_sensitivity:
            budget = max(0.0, deadline - time.monotonic())
            sensitivity[decision_scenario_id] = _sensitivity(inputs, decision, infos, budget, cp)
        rejections = rejection_reasons(inputs, scenarios, decision_scenario_id, {}, res.status)
        return outcome(
            res.status,
            baseline=baseline,
            solve=res,
            rejections=rejections,
            sensitivity=sensitivity,
            assumptions=sorted(set(assumptions)),
            notes=list(res.notes),
        )
    ver = verify(inputs, res.allocation, scenarios, decision_scenario_id)
    if not ver.ok:
        # Solver/verifier disagreement is a defect, never silently accepted -- and the rejected
        # allocation is never shown as a plan: it stays in the diagnostics (engine-spec §12.1).
        return outcome(
            "MODEL_INVALID",
            baseline=baseline,
            solve=replace(res, allocation={}),
            assumptions=sorted(set(assumptions)),
            notes=["VERIFIER_REJECTED_SOLVER_SOLUTION", *ver.violations],
            diagnostics={
                "code": "VERIFIER_REJECTED_SOLVER_SOLUTION",
                "rejected_allocation": dict(res.allocation),
                "rejected_verification": ver,
            },
        )
    failing = [sid for sid, chk in ver.checks.items() if not chk.ok]
    for sid, b in baseline.items():
        if not b["ok"] and sid not in failing:
            failing.append(sid)
    sensitivity = {}
    if with_sensitivity:
        pending = [sid for sid in failing if baseline[sid]["ok"]]
        for sid in failing:
            if not baseline[sid]["ok"]:
                where = []
                if any(acc["breaches"] for acc in baseline[sid]["accounts"].values()):
                    where.append("baseline[].accounts[].breaches")
                if baseline[sid]["global_breaches"]:  # §12.8
                    where.append("baseline[].global_breaches")
                note = "baseline shortfall in this scenario; the gap is in " + " and ".join(where)
                sensitivity[sid] = {"note": note}
                continue
            # an equal share of the time left for each scenario still to explain
            budget = max(0.0, deadline - time.monotonic()) / len(pending)
            pending.remove(sid)
            sensitivity[sid] = _sensitivity(inputs, scenarios[sid], infos, budget, cp)
    status = "FEASIBLE_ROBUST" if not failing else "CONDITIONALLY_FEASIBLE"
    for s in ver.checks.values():
        assumptions += s.assumptions
    rejections = rejection_reasons(
        inputs, scenarios, decision_scenario_id, res.allocation, res.status
    )
    return outcome(
        status,
        baseline=baseline,
        solve=res,
        allocation=res.allocation,
        verification=ver,
        failing_scenarios=failing,
        rejections=rejections,
        sensitivity=sensitivity,
        assumptions=sorted(set(assumptions)),
        notes=list(res.notes),
    )
