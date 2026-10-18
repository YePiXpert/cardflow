# Migrated from poc/engine_reference/tests/test_regression_sample.py (T-003): assertions and
# expected values unchanged; only imports, the fixture path, type annotations, formatting and
# `noqa` markers differ.
"""Acceptance tests for the 2026-10-16 / 10,000 CNY regression sample (任务书 §10)."""

from dataclasses import replace
from datetime import date
from decimal import Decimal
from pathlib import Path
from typing import Any

import pytest

from cardflow.planner.engine.allocation import ModelInputs, derive_card_info, solve
from cardflow.planner.engine.cash import Scenario
from cardflow.planner.engine.fixture import load_fixture
from cardflow.planner.engine.plan import plan
from cardflow.planner.engine.verifier import verify

# Golden fixture, located relative to this file (repository root = parents[4]).
FIX = (
    Path(__file__).resolve().parents[4]
    / "packages"
    / "rules-protocol"
    / "fixtures"
    / "regression_2026-10-16_10000.json"
)

type Fx = tuple[ModelInputs, dict[str, Scenario], dict[str, Any]]


@pytest.fixture(scope="module")
def fx() -> Fx:
    return load_fixture(FIX)


def test_cycles_match_acceptance(fx: Fx) -> None:
    inputs, scenarios, raw = fx  # noqa: RUF059
    for c in inputs.cards:
        info = derive_card_info(c, inputs.request)
        s, d = raw["expected"]["cycles"][c.id]
        assert info.cycle.statement_date == date.fromisoformat(s), c.id
        assert info.cycle.due_date == date.fromisoformat(d), c.id


def test_plan_A8000_C2000_baseline_min_cash_and_buffer(fx: Fx) -> None:  # noqa: N802
    inputs, scenarios, _ = fx
    v = verify(inputs, {"A": 800000, "C": 200000}, scenarios, "baseline")
    assert v.structural_ok and v.ok  # noqa: PT018
    chk = v.checks["baseline"]
    assert chk.min_balance_by_account["cash-main"] == 300000
    assert v.weighted_buffer_days == Decimal("42.4")


def test_plan_B_alone_reports_every_breach_not_only_the_first(fx: Fx) -> None:  # noqa: N802
    inputs, scenarios, _ = fx
    v = verify(inputs, {"B": 1000000}, scenarios, "baseline")
    chk = v.checks["baseline"]
    assert not chk.ok
    by_date = {b["on"]: b["balance"] for b in chk.breaches}
    assert by_date[date(2026, 11, 8)] == -350000
    assert by_date[date(2026, 11, 16)] == -700000
    assert by_date[date(2026, 11, 22)] == -200000
    assert len(chk.breaches) == 3
    assert chk.first_breach["on"] == date(2026, 11, 8)
    assert chk.min_balance_by_account["cash-main"] == -700000
    assert chk.min_on_by_account["cash-main"] == date(2026, 11, 16)


def test_income_delay_stress_on_A_C_distinguishes_zero_and_reserve_gap(fx: Fx) -> None:  # noqa: N802
    inputs, scenarios, _ = fx
    v = verify(inputs, {"A": 800000, "C": 200000}, scenarios, "baseline")
    chk = v.checks["stress_income_delay"]
    assert not chk.ok and len(chk.breaches) == 1  # noqa: PT018
    b = chk.breaches[0]
    assert b["on"] == date(2026, 11, 28) and b["balance"] == -200000  # noqa: PT018
    assert b["gap_to_zero"] == 200000 and b["gap_to_reserve"] == 400000  # noqa: PT018


def test_confirmed_scenario_is_baseline_shortfall_before_any_new_spend(fx: Fx) -> None:
    inputs, scenarios, _ = fx
    out = plan(inputs, scenarios, "confirmed", "cash_safety", time_limit_s=5)
    assert out.business_status == "BASELINE_SHORTFALL"
    acc = out.baseline["confirmed"]["accounts"]["cash-main"]
    assert (  # noqa: PT018
        acc["breaches"][0]["on"] == date(2026, 11, 8) and acc["breaches"][0]["balance"] == -200000
    )
    assert out.allocation == {} and out.solve is None  # noqa: PT018


def test_cash_safety_profile_returns_A8000_C2000_optimal(fx: Fx) -> None:  # noqa: N802
    inputs, scenarios, _ = fx
    res = solve(inputs, scenarios["baseline"], "cash_safety", time_limit_s=10)
    assert res.status == "OPTIMAL" and res.proven_optimal  # noqa: PT018
    assert res.allocation == {"A": 800000, "C": 200000}
    tiers = {t.name: t for t in res.tiers}
    assert tiers["min_margin"].value == 100000  # 3,000 min cash - 2,000 reserve
    assert tiers["buffer"].value == 800000 * 43 + 200000 * 40
    assert tiers["cards"].value == 2


def test_other_profiles_also_land_in_the_A_C_family_and_verify(fx: Fx) -> None:  # noqa: N802
    inputs, scenarios, _ = fx
    for profile in ("verified_benefit", "fewer_cards"):
        res = solve(inputs, scenarios["baseline"], profile, time_limit_s=10)
        assert res.status == "OPTIMAL", profile
        assert set(res.allocation) == {"A", "C"}, profile
        assert verify(inputs, res.allocation, scenarios, "baseline").ok


def test_full_plan_is_conditionally_feasible_with_sensitivity_and_rejections(fx: Fx) -> None:
    inputs, scenarios, _ = fx
    out = plan(inputs, scenarios, "baseline", "cash_safety", time_limit_s=10)
    assert out.business_status == "CONDITIONALLY_FEASIBLE"
    assert out.allocation == {"A": 800000, "C": 200000}
    assert set(out.failing_scenarios) == {"confirmed", "stress_income_delay"}
    s = out.sensitivity["stress_income_delay"]
    assert (  # noqa: PT018
        s["min_extra_confirmed_cash"]["status"] == "OPTIMAL"
        and s["min_extra_confirmed_cash"]["total"] == 400000
    )
    assert (  # noqa: PT018
        s["max_affordable_amount"]["status"] == "OPTIMAL"
        and s["max_affordable_amount"]["amount"] == 600000
    )
    # 2026-10-21: B posts to the 11-20 statement, due 12-08
    assert s["first_feasible_date_shift"]["shift_days"] == 5
    assert "baseline shortfall" in out.sensitivity["confirmed"]["note"]
    rej = {r["card"]: r for r in out.rejections}
    assert (  # noqa: PT018
        rej["B"]["reason"] == "CASH_BREACH_ALONE"
        and rej["B"]["first_breach"]["on"] == date(2026, 11, 8)
    )
    assert out.solve.run_id and out.solve.input_hash and out.solve.solver_version.startswith("9.")  # noqa: PT018
    assert out.verification.ok


def test_stress_as_decision_scenario_is_infeasible_with_explanations(fx: Fx) -> None:
    inputs, scenarios, _ = fx
    out = plan(inputs, scenarios, "stress_income_delay", "cash_safety", time_limit_s=10)
    assert out.business_status == "INFEASIBLE"
    s = out.sensitivity["stress_income_delay"]
    assert s["min_extra_confirmed_cash"]["total"] == 400000
    assert s["max_affordable_amount"]["amount"] == 600000
    assert s["first_feasible_date_shift"] == {
        "shift_days": 5,
        "txn_date": "2026-10-21",
        "status": "OPTIMAL",
    }
    reasons = {r["card"]: r["reason"] for r in out.rejections}
    assert reasons == {
        "A": "INSUFFICIENT_LIMIT_ALONE",
        "B": "CASH_BREACH_ALONE",
        "C": "INSUFFICIENT_LIMIT_ALONE",
    }


def test_card_input_order_does_not_change_result(fx: Fx) -> None:
    inputs, scenarios, _ = fx
    shuffled = replace(inputs, cards=list(reversed(inputs.cards)))
    res = solve(shuffled, scenarios["baseline"], "cash_safety", time_limit_s=10)
    assert res.allocation == {"A": 800000, "C": 200000}
    # input hash is order-sensitive on purpose (audit trail)
    assert shuffled.input_hash() != inputs.input_hash()


def test_no_split_is_infeasible_and_explained(fx: Fx) -> None:
    inputs, scenarios, _ = fx
    one = replace(inputs, request=replace(inputs.request, allow_split=False))
    out = plan(one, scenarios, "baseline", "cash_safety", time_limit_s=5)
    assert out.business_status == "INFEASIBLE"
    reasons = {r["card"]: r["reason"] for r in out.rejections}
    assert reasons == {
        "A": "INSUFFICIENT_LIMIT_ALONE",
        "B": "CASH_BREACH_ALONE",
        "C": "INSUFFICIENT_LIMIT_ALONE",
    }


def test_exact_to_the_fen(fx: Fx) -> None:
    inputs, scenarios, _ = fx
    odd = replace(inputs, request=replace(inputs.request, amount=1000001))
    res = solve(odd, scenarios["baseline"], "cash_safety", time_limit_s=10)
    assert res.status == "OPTIMAL" and sum(res.allocation.values()) == 1000001  # noqa: PT018
    assert verify(odd, res.allocation, scenarios, "baseline").ok


def test_min_split_constraint(fx: Fx) -> None:
    inputs, scenarios, _ = fx
    # each used card >= 3,000
    big = replace(inputs, request=replace(inputs.request, min_split=300000))
    res = solve(big, scenarios["baseline"], "cash_safety", time_limit_s=10)
    assert res.status == "OPTIMAL"
    assert all(v >= 300000 for v in res.allocation.values())
    assert verify(big, res.allocation, scenarios, "baseline").ok


def test_stale_snapshot_is_needs_data(fx: Fx) -> None:
    inputs, scenarios, _ = fx
    late = replace(inputs, request=replace(inputs.request, txn_date=date(2026, 10, 30)))
    out = plan(late, scenarios, "baseline", "cash_safety", time_limit_s=5, stale_after_days=7)
    assert out.business_status == "NEEDS_DATA" and out.data_issues[0]["code"] == "STALE_SNAPSHOT"  # noqa: PT018


def test_shared_pool_constraint(fx: Fx) -> None:
    inputs, scenarios, _ = fx
    cards = [replace(c, pool_id="pool-AC") if c.id in ("A", "C") else c for c in inputs.cards]
    pooled = replace(inputs, cards=cards, pools={"pool-AC": 900000})  # A and C share 9,000
    res = solve(pooled, scenarios["baseline"], "cash_safety", time_limit_s=10)
    assert res.status == "OPTIMAL"  # boundary: B takes exactly 1,000
    assert res.allocation["B"] == 100000 and res.allocation["A"] + res.allocation["C"] == 900000  # noqa: PT018
    v = verify(pooled, res.allocation, scenarios, "baseline")
    # sits exactly on the reserve line
    assert v.ok and v.checks["baseline"].min_balance_by_account["cash-main"] == 200000  # noqa: PT018
    # B would need 1,500 -> 11-16 at 1,500 < 2,000
    tight = replace(inputs, cards=cards, pools={"pool-AC": 850000})
    assert (
        solve(tight, scenarios["baseline"], "cash_safety", time_limit_s=10).status == "INFEASIBLE"
    )
    missing = replace(inputs, cards=cards, pools={})
    assert (
        solve(missing, scenarios["baseline"], "cash_safety", time_limit_s=5).status
        == "MODEL_INVALID"
    )


def test_zero_time_limit_never_claims_infeasible(fx: Fx) -> None:
    inputs, scenarios, _ = fx
    res = solve(inputs, scenarios["baseline"], "cash_safety", time_limit_s=1e-6)
    assert res.status in ("UNKNOWN", "FEASIBLE", "OPTIMAL")
    if res.status == "UNKNOWN":
        assert res.allocation == {} and any("NOT a proof" in n for n in res.notes)  # noqa: PT018
