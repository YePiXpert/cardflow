"""Engine correctness fixes of T-004c (review wave 3, engine-spec §12; model 1.1.0).

Every test names the review finding it guards (R3E-nn) and was written before its fix (red run:
``evidence/m0/T-004/c2-red.txt``). The minimal reproductions of the review
(``evidence/m0/review-wave3-engine.md`` §2/§4) are rebuilt here as protocol documents; expected
values are derived by hand in the comments. F-18 golden values are never touched.
"""

import copy
import random
import time
from dataclasses import replace
from datetime import date
from decimal import Decimal
from pathlib import Path
from typing import Any

import pytest

import cardflow.planner.engine.plan as plan_module
from cardflow.planner.engine import MODEL_VERSION, allocation
from cardflow.planner.engine.allocation import ModelInputs, _low_series
from cardflow.planner.engine.cash import Scenario, build_timeline
from cardflow.planner.engine.fixture import load_fixture
from cardflow.planner.engine.plan import plan
from cardflow.planner.engine.protocol import (
    parse_json,
    plan_from_protocol,
    verify_from_protocol,
)

REPO = Path(__file__).resolve().parents[4]
FIXTURES = REPO / "packages" / "rules-protocol" / "fixtures"
FIX = FIXTURES / "regression_2026-10-16_10000.json"
V1 = FIXTURES / "regression_2026-10-16_10000.v1.json"

type Doc = dict[str, Any]
type Fx = tuple[ModelInputs, dict[str, Scenario], dict[str, Any]]


@pytest.fixture(scope="module")
def fx() -> Fx:
    return load_fixture(FIX)


@pytest.fixture
def f18() -> Doc:
    return copy.deepcopy(parse_json(V1.read_bytes())["input"])


def card(
    cid: str,
    *,
    stmt: int = 20,
    due_day: int = 8,
    offset: int = 1,
    avail: int = 1_000_000,
    account: str | None = None,
    pool: str | None = None,
    holds: int = 0,
    reservations: int = 0,
    repay: str = "cash",
    **extra: Any,  # noqa: ANN401
) -> Doc:
    """A card; default rule: statement day 20, due the 8th of the next month (a 2026-10-16
    purchase repays on 2026-11-08)."""
    c: Doc = {
        "card_id": cid,
        "credit_account_id": account or f"acc-{cid}",
        "raw_available_minor": avail,
        "holds_uncounted_minor": holds,
        "reservations_minor": reservations,
        "billing_rule": {
            "rule_id": f"r{cid}",
            "statement_day": stmt,
            "statement_day_inclusive": True,
            "due": {"kind": "fixed_day", "day": due_day, "month_offset": offset},
            "holiday_rollover": "none",
        },
        "repay_from_cash_account_id": repay,
        "channel_ok": True,
        "currency_ok": True,
        "status_ok": True,
        "fee_rate": "0",
        "fee_fixed_minor": 0,
        "verified_benefit_rate": "0",
        "potential_benefit_rate": "0",
        "posting_delay_min_days": 0,
        "posting_delay_max_days": 0,
    }
    if pool is not None:
        c["pool_id"] = pool
    c.update(extra)
    return c


def scenario(
    sid: str,
    *,
    order: str = "conservative",
    delay: int = 0,
    overrides: tuple[Doc, ...] = (),
    include_expected: bool = True,
) -> Doc:
    return {
        "scenario_id": sid,
        "include_expected": include_expected,
        "income_delay_days": delay,
        "income_scale": "1",
        "expense_scale": "1",
        "event_overrides": list(overrides),
        "same_day_order": order,
    }


def event(eid: str, on: str, amount: int, **extra: Any) -> Doc:  # noqa: ANN401
    e: Doc = {
        "event_id": eid,
        "cash_account_id": "cash",
        "on": on,
        "amount_minor": amount,
        "cls": "confirmed",
        "category": "bill" if amount < 0 else "income",
    }
    e.update(extra)
    return e


def document(
    cards: list[Doc],
    *,
    amount: int,
    balance: int,
    events: tuple[Doc, ...] = (),
    scenarios: tuple[Doc, ...] = (),
    decision: str = "base",
    includes: tuple[str, ...] = (),
    pools: tuple[tuple[str, int], ...] = (),
    split: bool = False,
    max_cards: int = 1,
    lead: int = 0,
    horizon: str = "2026-12-31",
    global_floor: int = 0,
    time_limit: float = 10,
    txn: str = "2026-10-16",
) -> Doc:
    return {
        "protocol_version": "1",
        "request": {
            "amount_minor": amount,
            "currency": "CNY",
            "txn_date": txn,
            "allow_split": split,
            "max_cards": max_cards,
            "min_split_minor": 1,
            "payment_lead_days": lead,
            "channel": "pos",
        },
        "cards": cards,
        "pools": [{"pool_id": p, "available_minor": v} for p, v in pools],
        "cash_accounts": [
            {
                "cash_account_id": "cash",
                "currency": "CNY",
                "reserve_floor_minor": 0,
                "usable_for_repayment": True,
            }
        ],
        "snapshots": [
            {
                "cash_account_id": "cash",
                "balance_minor": balance,
                "as_of": txn,
                "includes_event_ids": list(includes),
            }
        ],
        "events": list(events),
        "scenarios": list(scenarios) or [scenario("base")],
        "horizon_end": horizon,
        "options": {
            "profile": "cash_safety",
            "decision_scenario": decision,
            "time_limit_s": time_limit,
            "workers": 8,
            "seed": 0,
            "stale_after_days": 7,
            "global_reserve_floor_minor": global_floor,
        },
    }


def allocation_of(out: Doc) -> dict[str, int]:
    return {line["card_id"]: line["amount_minor"] for line in out["allocation"]}


def reasons(out: Doc) -> dict[str, str]:
    return {r["card_id"]: r["reason"] for r in out["rejections"]}


def test_model_version_is_1_1_0() -> None:
    """engine-spec §12: the corrected semantics are model 1.1.0."""
    assert MODEL_VERSION == "1.1.0"


# --- R3E-01: effective_to in the date-shift search -----------------------------------------


@pytest.mark.parametrize("decision", ["baseline", "stress_income_delay"])
def test_rule_version_ending_soon_keeps_the_plan_r3e_01(f18: Doc, decision: str) -> None:
    """R3E-01 (§12.9): card C's rule version ends 2026-10-18 (valid on the transaction date).
    The date-shift search treats C as unavailable from 10-18 on instead of failing the run:
    the plan and every sensitivity number stay as without the end date. Shift: 10-17 is like
    10-16; 10-18..10-20 have no C and B still repays 11-08; on 10-21 B moves to the 11-20
    statement (repays 12-08) and A <= 6,000 + B >= 4,000 passes the stress scenario."""
    f18["cards"][2]["billing_rule"]["effective_to"] = "2026-10-18"
    f18["options"]["decision_scenario"] = decision
    out = plan_from_protocol(f18)
    assert not any(n.startswith("MODEL_BUILD_ERROR") for n in out["notes"]), out["notes"]
    if decision == "baseline":
        assert out["business_status"] == "CONDITIONALLY_FEASIBLE"
        assert allocation_of(out) == {"A": 800000, "C": 200000}
    else:
        assert out["business_status"] == "INFEASIBLE"
    sens = out["sensitivity"]["stress_income_delay"]
    assert sens["min_extra_confirmed_cash"]["total"] == 400000
    assert sens["max_affordable_amount"]["amount"] == 600000
    assert sens["first_feasible_date_shift"] == {
        "shift_days": 5,
        "txn_date": "2026-10-21",
        "status": "OPTIMAL",
    }


def test_a_failing_sensitivity_item_is_marked_unavailable_r3e_01(
    fx: Fx, monkeypatch: pytest.MonkeyPatch
) -> None:
    """R3E-01 (§12.9): one sensitivity item that cannot be modelled is reported as such; the
    run keeps its status, plan and the other items."""
    inputs, scenarios, _ = fx
    real = allocation.build_model

    def failing_for_extra_cash(*args: Any, **kwargs: Any) -> Any:  # noqa: ANN401
        if kwargs.get("extra_cash_vars"):
            raise OverflowError("injected")
        return real(*args, **kwargs)

    monkeypatch.setattr(allocation, "build_model", failing_for_extra_cash)
    out = plan(inputs, scenarios, "baseline", "cash_safety", time_limit_s=10)
    assert out.business_status == "CONDITIONALLY_FEASIBLE"
    assert out.allocation == {"A": 800000, "C": 200000}
    sens = out.sensitivity["stress_income_delay"]
    assert sens["min_extra_confirmed_cash"] == {
        "status": "MODEL_INVALID",
        "detail": "MODEL_BUILD_ERROR: OverflowError while building the CP-SAT model "
        "(no plan is shown)",
    }
    assert sens["max_affordable_amount"]["amount"] == 600000


# --- R3E-02: only actionable statuses carry an allocation ----------------------------------


def _rejecting_verify(monkeypatch: pytest.MonkeyPatch) -> None:
    real = plan_module.verify

    def rejecting(*args: Any, **kwargs: Any) -> Any:  # noqa: ANN401
        return replace(real(*args, **kwargs), ok=False, structural_ok=False, violations=["x"])

    monkeypatch.setattr(plan_module, "verify", rejecting)


def test_a_verifier_rejected_plan_is_never_shown_r3e_02(
    fx: Fx, monkeypatch: pytest.MonkeyPatch
) -> None:
    """R3E-02 (§12.1): MODEL_INVALID carries no allocation and no verification; the rejected
    allocation is only in the diagnostics (and not in the solver record either)."""
    inputs, scenarios, _ = fx
    _rejecting_verify(monkeypatch)
    out = plan(inputs, scenarios, "baseline", "cash_safety", time_limit_s=10)
    assert out.business_status == "MODEL_INVALID"
    assert out.allocation == {}
    assert out.verification is None
    assert out.solve is not None
    assert out.solve.allocation == {}
    assert out.diagnostics is not None
    assert out.diagnostics["code"] == "VERIFIER_REJECTED_SOLVER_SOLUTION"
    assert out.diagnostics["rejected_allocation"] == {"A": 800000, "C": 200000}
    assert out.diagnostics["rejected_verification"].violations == ["x"]
    assert "VERIFIER_REJECTED_SOLVER_SOLUTION" in out.notes


def test_actionable_outcomes_have_no_diagnostics_r3e_02(fx: Fx) -> None:
    """R3E-02: an actionable outcome has its allocation and verification, no diagnostics."""
    inputs, scenarios, _ = fx
    out = plan(inputs, scenarios, "baseline", "cash_safety", time_limit_s=10)
    assert out.business_status == "CONDITIONALLY_FEASIBLE"
    assert out.diagnostics is None
    assert out.verification is not None


# --- R3E-03 / R3E-14: snapshot reflection before the scenario -------------------------------


def _double_count(includes: tuple[str, ...], salary_on: str, stress: Doc) -> Doc:
    salary = event("sal", salary_on, 200000, cls="expected")
    rent = event("rent", "2026-11-01", -40000)
    return document(
        [card("A")],
        amount=100000,
        balance=50000,
        events=(salary, rent),
        includes=includes,
        scenarios=(scenario("baseline"), stress),
        decision="stress",
    )


def _balances(out: Doc) -> dict[str, tuple[int, int]]:
    return {
        sid: (b["accounts"]["cash"]["min_balance"], b["accounts"]["cash"]["end_balance"])
        for sid, b in out["baseline"].items()
    }


@pytest.mark.parametrize(
    ("includes", "salary_on", "stress"),
    [
        (("sal",), "2026-10-16", scenario("stress", delay=3)),
        ((), "2026-10-14", scenario("stress", delay=3)),
        (
            ("sal",),
            "2026-10-16",
            scenario("stress", overrides=({"event_id": "sal", "on": "2026-10-20"},)),
        ),
    ],
    ids=["included-then-delayed", "before-snapshot-then-delayed", "included-then-moved"],
)
def test_a_reflected_inflow_is_not_counted_again_r3e_03(
    includes: tuple[str, ...], salary_on: str, stress: Doc
) -> None:
    """R3E-03 (§12.2): the 2,000.00 salary is already in the 500.00 balance (included on the
    snapshot day, or dated before it). A scenario that delays or moves it must not count it
    again: both scenarios end at 500 - 400 (rent) = 100.00, and the 1,000.00 repayment on
    11-08 (card A) is infeasible (the review saw 2,100.00 and a 'feasible' stress plan)."""
    out = plan_from_protocol(_double_count(includes, salary_on, stress))
    assert _balances(out) == {"baseline": (10000, 10000), "stress": (10000, 10000)}
    assert out["business_status"] == "INFEASIBLE"
    assert reasons(out) == {"A": "CASH_BREACH_ALONE"}
    assert out["sensitivity"]["stress"]["min_extra_confirmed_cash"]["total"] == 90000


def test_an_event_moved_before_the_snapshot_counts_on_the_snapshot_day_r3e_03() -> None:
    """R3E-03 (§12.2): a scenario moves the pending 400.00 bill of 11-01 to 10-10, before the
    snapshot of 10-16. It is not in the balance, so it is paid on the snapshot day (the review
    saw it vanish: 500.00 at the end instead of 100.00)."""
    bill = event("bill", "2026-11-01", -40000)
    early = scenario("early", overrides=({"event_id": "bill", "on": "2026-10-10"},))
    doc = document(
        [card("A")],
        amount=1000,
        balance=50000,
        events=(bill,),
        scenarios=(scenario("baseline"), early),
        decision="early",
    )
    out = plan_from_protocol(doc)
    early_base = out["baseline"]["early"]["accounts"]["cash"]
    assert (early_base["min_balance"], early_base["end_balance"]) == (10000, 10000)
    assert early_base["min_on"] == "2026-10-16"
    assert any("bill" in a for a in out["baseline"]["early"]["assumptions"])
    assert out["business_status"] == "FEASIBLE_ROBUST"


def _timeline(inputs: ModelInputs, sc: Scenario, account_id: str) -> Any:  # noqa: ANN401
    acct = next(a for a in inputs.accounts if a.id == account_id)
    return build_timeline(acct, inputs.snapshots[account_id], inputs.events, sc, inputs.horizon_end)


def test_delaying_or_shrinking_income_never_raises_a_balance_r3e_03() -> None:
    """R3E-03 property (review suggestion): a scenario that only delays expected inflows or
    scales them down never shows a higher balance than the baseline at any checkpoint. Seeded
    random documents from the differential generator (snapshot inclusion of same-day and
    earlier events, timestamps, events before the snapshot)."""
    from cardflow.planner.engine.protocol import inputs_from_protocol

    ref = _reference()
    rng = random.Random(3)  # noqa: S311 -- seeded test data, not cryptography
    checked = 0
    for _ in range(300):
        doc = ref.gen_doc(rng)
        if len(doc["snapshots"]) != len(doc["cash_accounts"]):
            continue
        inputs, scenarios, _ = inputs_from_protocol(doc)
        base = scenarios["baseline"]
        worse = replace(
            base,
            id="worse",
            income_delay_days=rng.choice([1, 3, 7]),
            income_scale=Decimal(rng.choice(["1", "0.5", "0"])),
        )
        for a in inputs.accounts:
            b, w = _timeline(inputs, base, a.id), _timeline(inputs, worse, a.id)
            # every checkpoint of either timeline: the day's low, or the balance carried from
            # the last earlier day (the model's checkpoint values)
            days = sorted({p.on for tl in (b, w) for p in tl.points if p.phase == "low"})
            for d, vb, vw in zip(days, _low_series(b, days), _low_series(w, days), strict=True):
                assert vw <= vb, (doc, a.id, d)
                checked += 1
    assert checked > 500


def _reference() -> Any:  # noqa: ANN401
    import importlib.util
    import sys

    name = "engine_diff_reference"
    if name not in sys.modules:
        spec = importlib.util.spec_from_file_location(
            name, Path(__file__).parent / "diff_reference.py"
        )
        assert spec is not None
        assert spec.loader is not None
        module = importlib.util.module_from_spec(spec)
        sys.modules[name] = module
        spec.loader.exec_module(module)
    return sys.modules[name]


# --- R3E-04: credit-account layer and pool deductions ---------------------------------------


def test_cards_of_one_credit_account_share_its_available_credit_r3e_04() -> None:
    """R3E-04 (§12.3): main and supplementary card of acc-1 both show the account's 6,000.00.
    Together they can take 6,000.00, not 12,000.00: a 10,000.00 spend is infeasible (the
    review saw FEASIBLE_ROBUST with 6,000 + 4,000), a 6,000.00 spend fits on one card."""
    cards = [
        card("main", avail=600000, account="acc-1"),
        card("supp", avail=600000, account="acc-1"),
    ]
    out = plan_from_protocol(
        document(cards, amount=1000000, balance=10**8, split=True, max_cards=3)
    )
    assert out["business_status"] == "INFEASIBLE"
    assert out["solver_status"] == "INFEASIBLE"
    for r in out["rejections"]:
        assert (r["reason"], r["capacity"]) == ("INSUFFICIENT_LIMIT_ALONE", 600000)
        assert r["detail"] == "limited by credit account acc-1"
    affordable = out["sensitivity"]["base"]["max_affordable_amount"]
    assert (affordable["amount"], affordable["allocation"]) == (600000, {"main": 600000})
    fits = plan_from_protocol(
        document(cards, amount=600000, balance=10**8, split=True, max_cards=3)
    )
    assert fits["business_status"] == "FEASIBLE_ROBUST"
    assert allocation_of(fits) == {"main": 600000}


def test_the_verifier_checks_the_credit_account_layer_r3e_04() -> None:
    """R3E-04: an allocation using both cards beyond the account's capacity is a violation."""
    cards = [
        card("main", avail=600000, account="acc-1"),
        card("supp", avail=600000, account="acc-1"),
    ]
    doc = document(cards, amount=1000000, balance=10**8, split=True, max_cards=3)
    items = [
        {"card_id": "main", "amount_minor": 600000},
        {"card_id": "supp", "amount_minor": 400000},
    ]
    res = verify_from_protocol(doc, items, "base")
    assert res["verification"]["ok"] is False
    assert (
        "credit account acc-1: 1000000 exceeds shared capacity 600000"
        in (res["verification"]["violations"])
    )


@pytest.mark.parametrize("member", ["reservations", "holds"])
def test_a_pool_deducts_its_members_reservations_and_holds_r3e_04(member: str) -> None:
    """R3E-04 (§12.3): pool p shows 10,000.00; card A carries 8,000.00 reserved by an adopted
    plan (or an uncounted hold). Only 2,000.00 is left for card B in the same pool: a 10,000.00
    spend is infeasible (the review saw B = 10,000.00)."""
    a = card("A", pool="p", **{member: 800000})
    b = card("B", pool="p")
    out = plan_from_protocol(
        document(
            [a, b], amount=1000000, balance=10**8, pools=(("p", 1000000),), split=True, max_cards=2
        )
    )
    assert out["business_status"] == "INFEASIBLE"
    assert {r["card_id"]: (r["reason"], r["capacity"]) for r in out["rejections"]} == {
        "A": ("INSUFFICIENT_LIMIT_ALONE", 200000),
        "B": ("INSUFFICIENT_LIMIT_ALONE", 200000),
    }
    ok = plan_from_protocol(
        document(
            [a, b], amount=200000, balance=10**8, pools=(("p", 1000000),), split=True, max_cards=2
        )
    )
    assert ok["business_status"] == "FEASIBLE_ROBUST"


# --- R3E-05: one same-day order for model and verifier --------------------------------------

TIMED = (
    event("inc", "2026-11-08", 20, at="2026-11-08T09:00:00+08:00"),
    event("exp", "2026-11-08", -25, at="2026-11-08T18:00:00+08:00"),
)


@pytest.mark.parametrize("cards", [["A"], ["A", "B"]], ids=["A", "A+B"])
def test_a_candidate_repayment_day_keeps_the_timestamp_order_r3e_05(cards: list[str]) -> None:
    """R3E-05 (§12.4): balance 0.10; on 11-08 +0.20 at 09:00 and -0.25 at 18:00 (timestamp
    order: low 0.05). Card A repays 11-28, card B 11-08. B's repayment day must not switch the
    day to the conservative order in the model only: with or without B, A = 0.03 is the plan
    (equal margins; A has the longer buffer). The review saw INFEASIBLE with B present."""
    all_cards = {
        "A": card("A", stmt=10, due_day=28, offset=0, avail=1000),
        "B": card("B", avail=1000),
    }
    doc = document(
        [all_cards[c] for c in cards],
        amount=3,
        balance=10,
        events=TIMED,
        scenarios=(scenario("ts", order="timestamp"),),
        decision="ts",
    )
    out = plan_from_protocol(doc)
    assert out["business_status"] == "FEASIBLE_ROBUST"
    assert allocation_of(out) == {"A": 3}
    if "B" in cards:
        assert reasons(out) == {"B": "DOMINATED"}


def test_a_planned_repayment_comes_first_on_a_timestamp_ordered_day_r3e_05() -> None:
    """R3E-05 (§12.4): on a timestamp-ordered day the plan's repayment (no timestamp) is applied
    first, exactly as the model subtracts it from the day's low: B = 0.03 repaid on 11-08 gives
    0.10 -> 0.07 -> 0.27 -> 0.02 (low 0.02), feasible; model and verifier agree."""
    b = card("B", avail=1000)
    doc = document(
        [b],
        amount=3,
        balance=10,
        events=TIMED,
        scenarios=(scenario("ts", order="timestamp"),),
        decision="ts",
    )
    res = verify_from_protocol(doc, [{"card_id": "B", "amount_minor": 3}], "ts")
    chk = res["verification"]["checks"]["ts"]
    assert (chk["ok"], chk["min_balance_by_account"]) == (True, {"cash": 2})
    out = plan_from_protocol(doc)
    assert out["business_status"] == "FEASIBLE_ROBUST"
    assert allocation_of(out) == {"B": 3}


def test_a_delayed_income_loses_its_timestamp_r3e_05() -> None:
    """R3E-05 (§12.4): expected salary +0.20 on 11-05 at 09:00, bill -0.15 on 11-08 at 10:00,
    balance 0.10; the stress scenario delays income by 3 days to 11-08. The re-dated salary has
    no timestamp, so 11-08 is ordered conservatively: low 0.10 - 0.15 = -0.05, the stress
    baseline fails (the review saw the salary sorted first: ok, FEASIBLE_ROBUST)."""
    events = (
        event("sal", "2026-11-05", 20, cls="expected", at="2026-11-05T09:00:00+08:00"),
        event("bill", "2026-11-08", -15, at="2026-11-08T10:00:00+08:00"),
    )
    doc = document(
        [card("A", stmt=10, due_day=28, offset=0, avail=1000)],
        amount=3,
        balance=10,
        events=events,
        scenarios=(
            scenario("base", order="timestamp"),
            scenario("stress", order="timestamp", delay=3),
        ),
        decision="stress",
    )
    out = plan_from_protocol(doc)
    assert out["baseline"]["stress"]["ok"] is False
    assert out["baseline"]["stress"]["accounts"]["cash"]["min_balance"] == -5
    assert out["business_status"] == "BASELINE_SHORTFALL"


# --- R3E-07: fees leave cash with the repayment ---------------------------------------------


def _fee_doc(balance: int) -> Doc:
    a = card("A", avail=100000, fee_rate="0.006", fee_fixed_minor=1000)
    return document([a], amount=10000, balance=balance)


def test_the_fee_is_paid_with_the_repayment_r3e_07() -> None:
    """R3E-07 (§12.6): spend 100.00 on A with 0.6% + 10.00 fee = 10.60; cash 100.00. The
    repayment on 11-08 is 110.60, so the plan is infeasible by exactly the fee (the review saw
    FEASIBLE_ROBUST with a minimum of 0)."""
    out = plan_from_protocol(_fee_doc(10000))
    assert out["business_status"] == "INFEASIBLE"
    assert reasons(out) == {"A": "CASH_BREACH_ALONE"}
    assert out["rejections"][0]["first_breach"]["balance"] == -1060
    assert out["sensitivity"]["base"]["min_extra_confirmed_cash"]["total"] == 1060
    res = verify_from_protocol(_fee_doc(10000), [{"card_id": "A", "amount_minor": 10000}], "base")
    breach = res["verification"]["checks"]["base"]["breaches"][0]
    assert (breach["on"], breach["balance"], breach["events"]) == (
        "2026-11-08",
        -1060,
        ["plan_repay_A"],
    )
    assert res["allocation"][0]["fee_minor"] == 1060
    ok = plan_from_protocol(_fee_doc(11060))
    assert ok["business_status"] == "FEASIBLE_ROBUST"
    assert ok["verification"]["checks"]["base"]["min_balance_by_account"] == {"cash": 0}


# --- R3E-08: the checked horizon depends on the input only ----------------------------------


def _horizon_doc(cards: list[str]) -> Doc:
    pool = {
        "A": card("A", avail=1000),  # repays 2026-11-08
        "B": card("B", stmt=1, due_day=28, offset=1, avail=50),  # would repay 2026-12-28
    }
    return document(
        [pool[c] for c in cards],
        amount=100,
        balance=500,
        events=(event("tax", "2026-12-15", -450),),
        horizon="2026-11-30",
    )


@pytest.mark.parametrize("cards", [["A", "B"], ["A"]], ids=["A+B", "A"])
def test_an_unusable_card_does_not_change_the_horizon_r3e_08(cards: list[str]) -> None:
    """R3E-08 (§12.7): horizon_end 11-30. B would repay 12-28, after it: B is excluded with
    REPAY_AFTER_HORIZON and the horizon is never extended, so the 12-15 bill stays outside and
    the answer is the same with or without B (the review saw INFEASIBLE with B present)."""
    out = plan_from_protocol(_horizon_doc(cards))
    assert out["business_status"] == "FEASIBLE_ROBUST"
    assert allocation_of(out) == {"A": 100}
    assert not any("horizon" in n for n in out["notes"])
    if "B" in cards:
        assert reasons(out) == {"B": "REPAY_AFTER_HORIZON"}
    res = verify_from_protocol(_horizon_doc(cards), [{"card_id": "A", "amount_minor": 100}], "base")
    assert res["verification"]["ok"] is True


def test_a_repayment_after_the_horizon_is_a_violation_in_the_verifier_r3e_08() -> None:
    """R3E-08: the solver-free verifier uses the same rule (no extension)."""
    res = verify_from_protocol(
        _horizon_doc(["A", "B"]), [{"card_id": "B", "amount_minor": 50}], "base"
    )
    assert "B: ineligible (REPAY_AFTER_HORIZON)" in res["verification"]["violations"]


def test_every_card_after_the_horizon_is_infeasible_without_extension_r3e_08(fx: Fx) -> None:
    """R3E-08: F-18 with horizon_end 11-01, before every repayment (11-08/11-25/11-28)."""
    inputs, scenarios, _ = fx
    out = plan(replace(inputs, horizon_end=date(2026, 11, 1)), scenarios, "baseline")
    assert out.business_status == "INFEASIBLE"
    assert out.solve is None
    assert {r["card"]: r["reason"] for r in out.rejections} == dict.fromkeys(
        "ABC", "REPAY_AFTER_HORIZON"
    )
    assert not any(n.startswith("horizon extended") for n in out.notes)


# --- R3E-09: the baseline checks the global floor -------------------------------------------


def test_the_baseline_checks_the_global_floor_r3e_09() -> None:
    """R3E-09 (§12.8): two accounts of 0.50 each, global floor 1.20; on 10-20 account 'cash'
    pays 0.01. Each account is fine, the total (1.00 on the snapshot day, 0.99 on 10-20) is
    below the global floor already without the new spend: BASELINE_SHORTFALL (the review saw
    INFEASIBLE with baseline ok)."""
    doc = document(
        [card("A")], amount=1, balance=50, events=(event("x", "2026-10-20", -1),), global_floor=120
    )
    doc["cash_accounts"].append(dict(doc["cash_accounts"][0], cash_account_id="cash-2"))
    doc["snapshots"].append(dict(doc["snapshots"][0], cash_account_id="cash-2"))
    out = plan_from_protocol(doc)
    assert out["business_status"] == "BASELINE_SHORTFALL"
    base = out["baseline"]["base"]
    assert base["ok"] is False
    assert base["global_breaches"] == [
        {"on": "2026-10-16", "total": 100, "gap": 20},
        {"on": "2026-10-20", "total": 99, "gap": 21},
    ]
    assert all(not a["breaches"] for a in base["accounts"].values())


def test_a_starting_total_below_the_global_floor_is_a_baseline_shortfall_r3e_09() -> None:
    """R3E-09 (§12.8): without any event the only checkpoint of the global floor is the
    snapshot day (as the snapshot is for an account's reserve): 0.10 against a floor of 0.40 is
    a shortfall before any spend, not an INFEASIBLE plan whose 'largest affordable amount' is
    infeasible even for 0 (found by the differential test)."""
    out = plan_from_protocol(document([card("A")], amount=1, balance=10, global_floor=40))
    assert out["business_status"] == "BASELINE_SHORTFALL"
    assert out["baseline"]["base"]["global_breaches"] == [
        {"on": "2026-10-16", "total": 10, "gap": 30}
    ]


# --- R3E-10: rejection reasons --------------------------------------------------------------


@pytest.mark.parametrize(
    ("changes", "pools", "detail"),
    [
        ({"pool_id": "p"}, (("p", 500000),), "limited by pool p"),
        ({"per_txn_cap_minor": 500000}, (), "limited by the per-transaction cap"),
    ],
    ids=["pool", "per-transaction-cap"],
)
def test_insufficient_limit_considers_every_layer_r3e_10(
    changes: Doc, pools: tuple[tuple[str, int], ...], detail: str
) -> None:
    """R3E-10: capacity 10,000.00 >= spend 8,000.00 but the pool (or the per-transaction cap)
    allows 5,000.00: INSUFFICIENT_LIMIT_ALONE with the binding layer, never 'DOMINATED'."""
    doc = document([card("A", **changes)], amount=800000, balance=10**8, pools=pools)
    out = plan_from_protocol(doc)
    assert out["business_status"] == "INFEASIBLE"
    (r,) = out["rejections"]
    assert (r["reason"], r["capacity"], r["amount"], r["detail"]) == (
        "INSUFFICIENT_LIMIT_ALONE",
        500000,
        800000,
        detail,
    )


def test_a_minimum_part_above_the_amount_is_its_own_reason_r3e_10() -> None:
    """R3E-10: the card's minimum part 9,000.00 exceeds the 8,000.00 spend."""
    out = plan_from_protocol(
        document([card("A", min_split_minor=900000)], amount=800000, balance=10**8)
    )
    assert out["business_status"] == "INFEASIBLE"
    assert out["solver_status"] == "NOT_RUN"
    assert reasons(out) == {"A": "MIN_SPLIT_ABOVE_AMOUNT"}


def test_no_capacity_names_the_exhausted_layer_r3e_10() -> None:
    """R3E-10: NO_CAPACITY says which layer is exhausted (card, credit account or pool)."""
    cards = [
        card("A", avail=0),
        card("B", pool="p"),
        card("C", account="acc-x", avail=500, reservations=300),
        card("D", account="acc-x", avail=500, holds=200),
        card("E"),
    ]
    out = plan_from_protocol(document(cards, amount=100, balance=10**6, pools=(("p", 0),)))
    details = {r["card_id"]: (r["reason"], r.get("detail")) for r in out["rejections"]}
    assert details == {
        "A": ("NO_CAPACITY", "the card has no capacity left"),
        "B": ("NO_CAPACITY", "pool p has no capacity left"),
        "C": ("NO_CAPACITY", "credit account acc-x has no capacity left"),
        "D": ("NO_CAPACITY", "credit account acc-x has no capacity left"),
    }


def test_unknown_does_not_claim_dominated_r3e_10(f18: Doc) -> None:
    """R3E-10: with no solution in time (UNKNOWN), a card that is feasible alone was never
    compared: NOT_COMPARED, not 'scored lower on the objective tiers'."""
    f18["snapshots"][0]["balance_minor"] = 5000000
    f18["options"]["time_limit_s"] = 1e-9
    out = plan_from_protocol(f18)
    assert out["business_status"] == "UNKNOWN"
    assert reasons(out) == {
        "A": "INSUFFICIENT_LIMIT_ALONE",
        "B": "NOT_COMPARED",
        "C": "INSUFFICIENT_LIMIT_ALONE",
    }


# --- R3E-15: default hash and the scope of the build-error fallback --------------------------


def test_the_default_hash_covers_scenarios_and_options_r3e_15(fx: Fx) -> None:
    """R3E-15 (a): a direct plan() call hashes data, scenarios and options; another decision
    scenario or profile is another input."""
    inputs, scenarios, _ = fx
    runs = [
        plan(inputs, scenarios, "baseline", "cash_safety", with_sensitivity=False),
        plan(inputs, scenarios, "baseline", "fewer_cards", with_sensitivity=False),
        plan(inputs, scenarios, "stress_income_delay", "cash_safety", with_sensitivity=False),
        plan(inputs, scenarios, "baseline", "cash_safety", time_limit_s=5, with_sensitivity=False),
    ]
    assert len({r.input_hash for r in runs}) == 4
    again = plan(inputs, scenarios, "baseline", "cash_safety", with_sensitivity=False)
    assert again.input_hash == runs[0].input_hash
    assert runs[0].input_hash != inputs.input_hash()


def test_errors_outside_modelling_are_not_disguised_r3e_15(
    fx: Fx, monkeypatch: pytest.MonkeyPatch
) -> None:
    """R3E-15 (b) (§12.10): the fallback covers model building and solving only; a defect in
    another phase surfaces as an exception, never as MODEL_INVALID 'outside the range'."""
    inputs, scenarios, _ = fx

    def broken(*args: Any, **kwargs: Any) -> Any:  # noqa: ANN401
        raise ValueError("defect in the rejection reasons")

    monkeypatch.setattr(plan_module, "rejection_reasons", broken)
    with pytest.raises(ValueError, match="defect in the rejection reasons"):
        plan(inputs, scenarios, "baseline", "cash_safety", time_limit_s=10)


# --- R3E-17: the run's time limit bounds the sensitivity solves -----------------------------


def test_every_solver_call_ends_within_the_runs_time_limit_r3e_17(
    fx: Fx, monkeypatch: pytest.MonkeyPatch
) -> None:
    """R3E-17 (§12.9): with time_limit_s = 2 every CP-SAT call of the run (tiers, tie-break,
    sensitivity, 45-day search) is given a limit that ends within 2 s of the run's start (the
    review: 5 s + 5 s + 45 x 1 s per failing scenario, unbounded)."""
    inputs, scenarios, _ = fx
    calls: list[tuple[float, float]] = []
    real = allocation._solver

    def spy(time_limit_s: float, workers: int, seed: int) -> Any:  # noqa: ANN401
        calls.append((time.monotonic(), time_limit_s))
        return real(time_limit_s, workers, seed)

    monkeypatch.setattr(allocation, "_solver", spy)
    started = time.monotonic()
    out = plan(inputs, scenarios, "stress_income_delay", "cash_safety", time_limit_s=2.0)
    assert out.business_status == "INFEASIBLE"
    assert len(calls) > 5
    # 0.25 s: scheduling jitter between computing a share and creating the solver (the review:
    # single calls of 5 s, and 45 x 1 s per failing scenario)
    assert all(at + limit <= started + 2.0 + 0.25 for at, limit in calls), calls


# --- R3E-19: no eligible card, date-dependent exclusions --------------------------------------


def test_no_eligible_card_still_searches_a_later_date_r3e_19() -> None:
    """R3E-19 (§12.9): card B would repay 11-08 - 25 days = 10-14, before the 10-16 purchase
    (REPAY_BEFORE_TXN_DATE). From 10-21 the purchase belongs to the 11-20 statement (due 12-08,
    pay 11-13): the date-shift search applies and finds 5 days; the amount-based items have no
    card to work with."""
    out = plan_from_protocol(document([card("B")], amount=100, balance=10**6, lead=25))
    assert (out["business_status"], out["solver_status"]) == ("INFEASIBLE", "NOT_RUN")
    assert reasons(out) == {"B": "REPAY_BEFORE_TXN_DATE"}
    sens = out["sensitivity"]["base"]
    assert sens["first_feasible_date_shift"] == {
        "shift_days": 5,
        "txn_date": "2026-10-21",
        "status": "OPTIMAL",
    }
    for key in ("min_extra_confirmed_cash", "max_affordable_amount"):
        assert sens[key]["status"] == "NOT_RUN"


def test_no_eligible_card_without_a_date_reason_has_no_sensitivity_r3e_19() -> None:
    """R3E-19: exclusions a later date cannot lift (card status) give no sensitivity."""
    out = plan_from_protocol(document([card("B", status_ok=False)], amount=100, balance=10**6))
    assert out["business_status"] == "INFEASIBLE"
    assert out["sensitivity"] == {}


# --- engine-direct path: the T-004b probe with a fee ----------------------------------------


def test_fee_probe_allocation_pays_the_fee_from_cash_r3e_07(fx: Fx) -> None:
    """R3E-07 (§12.6) on the T-004b probe 'fee_rate = 0.006' on card A of F-18 (the old expected
    A 5,000 + C 5,000 assumed fee-free cash). On 11-28 the cash after both repayments is
    13,000 - 10,000 - fee(A) = 3,000 - ceil(0.006 x_A) (in fen 300000 - ceil(0.006 x_A)), and on
    11-25 it is 8,000 - x_C. Maximising the smaller margin gives x_C in [502834, 502983] with
    margin 97017; fees are 2983 on that whole range; the longest buffer then takes the least
    C: x_C = 502834, x_A = 497166."""
    inputs, scenarios, _ = fx
    cards = list(inputs.cards)
    cards[0] = replace(cards[0], fee_rate=Decimal("0.006"))
    out = plan(replace(inputs, cards=cards), scenarios, "baseline", "cash_safety", 10)
    assert out.business_status == "CONDITIONALLY_FEASIBLE"
    assert out.allocation == {"A": 497166, "C": 502834}
    assert out.solve is not None
    tiers = {t.name: t.value for t in out.solve.tiers}
    assert (tiers["min_margin"], tiers["fees"]) == (97017, 2983)
    assert out.verification is not None
    assert out.verification.checks["baseline"].min_balance_by_account["cash-main"] == 297017
