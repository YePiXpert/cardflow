"""Engine robustness fixes (T-004b), each written as a failing test first.

1. a value outside what the CP-SAT model can represent never escapes as an exception: model
   construction errors (ValueError / TypeError / OverflowError) become a MODEL_INVALID result
   whose note names the error class only (no input value) -- every case of
   ``evidence/m0/T-004/engine-limits-probe.txt`` is covered here on the ENGINE path (the
   protocol path is ``tests/protocol/test_limits.py``). Since model 1.1.0 (T-004c, engine-spec
   §12.10, R3E-15) this fallback covers model building and solving only: an error in another
   phase (e.g. a date beyond the supported range in the data checks) surfaces as an exception;
2. a card whose cash repayment would fall before the transaction date is rejected before
   modelling (REPAY_BEFORE_TXN_DATE), and the verifier applies -- and flags -- a planned
   repayment dated before the account snapshot instead of silently skipping it;
3. a shared pool with available <= 0 is clamped to zero: its cards get no capacity
   (NO_CAPACITY), cards outside the pool stay usable;
4. the verifier refuses non-integer amounts instead of truncating them with int().
"""

from collections.abc import Callable
from dataclasses import replace
from datetime import date
from decimal import Decimal
from pathlib import Path
from typing import Any

import pytest

from cardflow.planner.engine.allocation import (
    ModelInputs,
    derive_card_info,
    feasibility_status,
    max_affordable_amount,
    min_extra_cash,
    solve,
)
from cardflow.planner.engine.billing import BillingRule, DueRule
from cardflow.planner.engine.cash import Scenario
from cardflow.planner.engine.fixture import load_fixture
from cardflow.planner.engine.plan import PlanOutcome, plan
from cardflow.planner.engine.verifier import verify

FIX = (
    Path(__file__).resolve().parents[4]
    / "packages"
    / "rules-protocol"
    / "fixtures"
    / "regression_2026-10-16_10000.json"
)
I63 = 2**63 - 1

type Fx = tuple[ModelInputs, dict[str, Scenario], dict[str, Any]]
type Mutation = Callable[[ModelInputs], ModelInputs]


@pytest.fixture(scope="module")
def fx() -> Fx:
    return load_fixture(FIX)


def _card(i: int, **changes: Any) -> Mutation:  # noqa: ANN401
    def mutate(inputs: ModelInputs) -> ModelInputs:
        cards = list(inputs.cards)
        cards[i] = replace(cards[i], **changes)
        return replace(inputs, cards=cards)

    return mutate


def _request(**changes: Any) -> Mutation:  # noqa: ANN401
    return lambda inputs: replace(inputs, request=replace(inputs.request, **changes))


def _balance(value: int) -> Mutation:
    def mutate(inputs: ModelInputs) -> ModelInputs:
        snap = inputs.snapshots["cash-main"]
        return replace(inputs, snapshots={"cash-main": replace(snap, balance=value)})

    return mutate


def _event0(amount: int) -> Mutation:
    def mutate(inputs: ModelInputs) -> ModelInputs:
        events = list(inputs.events)
        events[0] = replace(events[0], amount=amount)
        return replace(inputs, events=events)

    return mutate


def _build_error_notes(outcome: PlanOutcome) -> list[str]:
    notes = list(outcome.notes) + (list(outcome.solve.notes) if outcome.solve else [])
    return [n for n in notes if n.startswith("MODEL_BUILD_ERROR")]


# --- 1. every case of engine-limits-probe.txt, on the engine path ---------------------------

PROBE = [
    # (probe line, mutation, expected business status, MODEL_BUILD_ERROR note expected)
    ("raw_available = 2^63-1", _card(0, raw_available=I63), "MODEL_INVALID", False),
    ("amount = 2^62", _request(amount=2**62), "INFEASIBLE", False),
    ("amount = 2^63-1", _request(amount=I63), "MODEL_INVALID", True),
    ("balance = -2^63", _balance(-(2**63)), "BASELINE_SHORTFALL", False),
    ("balance = 2^63-1", _balance(I63), "MODEL_INVALID", True),
    ("event amount = 2^63-1", _event0(I63), "MODEL_INVALID", True),
    ("balance = 10^13", _balance(10**13), "FEASIBLE_ROBUST", False),
    ("fee_rate = 0.006", _card(0, fee_rate=Decimal("0.006")), "CONDITIONALLY_FEASIBLE", False),
    ("fee_rate = 0.1234567891", _card(0, fee_rate=Decimal("0.1234567891")), "MODEL_INVALID", False),
    (
        "fee_rate = 9999999999.9999999999",
        _card(0, fee_rate=Decimal("9999999999.9999999999")),
        "MODEL_INVALID",
        True,
    ),
    ("payment_lead_days = 60", _request(payment_lead_days=60), "INFEASIBLE", False),
]


@pytest.mark.parametrize(
    ("mutate", "status", "build_error"),
    [case[1:] for case in PROBE],
    ids=[case[0] for case in PROBE],
)
def test_probe_cases_never_raise_and_end_in_a_business_status(
    fx: Fx, mutate: Mutation, status: str, build_error: bool
) -> None:
    inputs, scenarios, _ = fx
    out = plan(mutate(inputs), scenarios, "baseline", "cash_safety", time_limit_s=10)
    assert out.business_status == status
    notes = _build_error_notes(out)
    assert bool(notes) is build_error, out.notes
    # the note names the error class only -- never an input value
    assert not any(ch.isdigit() for note in notes for ch in note), notes


def test_fee_rate_case_of_the_probe_pays_the_fee_from_cash_r3e_07(fx: Fx) -> None:
    """R3E-07 (engine-spec §12.6): the fee is paid with the repayment. Before model 1.1.0 this
    probe expected A 5,000 + C 5,000, which assumed fee-free cash; the derivation of the new
    optimum is in ``test_review_wave3_fixes.py`` (``test_fee_probe_allocation_pays_the_fee_from_
    cash_r3e_07``)."""
    inputs, scenarios, _ = fx
    out = plan(
        _card(0, fee_rate=Decimal("0.006"))(inputs), scenarios, "baseline", "cash_safety", 10
    )
    assert out.allocation == {"A": 497166, "C": 502834}


@pytest.mark.parametrize(
    "mutate",
    [_request(amount=I63), _balance(I63), _event0(I63)],
    ids=["amount", "balance", "event"],
)
def test_solver_and_sensitivity_helpers_report_model_invalid_instead_of_raising(
    fx: Fx, mutate: Mutation
) -> None:
    inputs, scenarios, _ = fx
    broken = mutate(inputs)
    stress = scenarios["stress_income_delay"]
    res = solve(broken, scenarios["baseline"], "cash_safety", time_limit_s=10)
    assert res.status == "MODEL_INVALID"
    assert any(n.startswith("MODEL_BUILD_ERROR") for n in res.notes), res.notes
    infos = [derive_card_info(c, broken.request) for c in broken.cards]
    for result in (
        min_extra_cash(broken, stress, infos),
        max_affordable_amount(broken, stress, infos),
    ):
        # R3E-16: the detail is always there (no default that lets the check pass vacuously):
        # either OR-Tools refused a coefficient while the model was built, or CP-SAT's own
        # validation rejected the built model (the review's case: max_affordable_amount with
        # amount = 2^63-1 used to return a bare {"status": "MODEL_INVALID"}).
        assert result["status"] == "MODEL_INVALID"
        assert result["detail"] in (
            "MODEL_VALIDATION_FAILED: CP-SAT rejected the model (no plan is shown)",
            *(
                f"MODEL_BUILD_ERROR: {cls} while building the CP-SAT model (no plan is shown)"
                for cls in ("ValueError", "TypeError", "OverflowError")
            ),
        ), result
    assert feasibility_status(broken, stress, infos) == "MODEL_INVALID"


def test_a_date_beyond_the_supported_range_is_not_disguised_r3e_15(fx: Fx) -> None:
    """R3E-15 (engine-spec §12.10): the data checks are not model building. A date past the
    calendar (outside the engine's documented range 1970..2999, which the protocol enforces)
    surfaces as the exception it is instead of 'MODEL_INVALID: outside the supported range'
    (T-004b reported it as MODEL_INVALID during data checks)."""
    inputs, scenarios, _ = fx
    last = date(9999, 12, 31)
    # statement on 9999-12-31 itself, due 20 days later: the date arithmetic overflows
    rule = BillingRule("r31", 31, DueRule("days_after_statement", days=20))
    late = replace(
        inputs,
        request=replace(inputs.request, txn_date=last),
        snapshots={"cash-main": replace(inputs.snapshots["cash-main"], as_of=last)},
        cards=[replace(inputs.cards[0], billing_rule=rule), *inputs.cards[1:]],
        horizon_end=last,
    )
    with pytest.raises(OverflowError):
        plan(late, scenarios, "baseline", "cash_safety", time_limit_s=10)


# --- 2. repayment before the transaction / snapshot -----------------------------------------


def test_a_card_whose_repayment_would_precede_the_transaction_is_rejected(fx: Fx) -> None:
    inputs, scenarios, _ = fx
    # 30 days early: A pays 10-29, C pays 10-26, but B (due 11-08) would pay 10-09 < 10-16
    early = _request(payment_lead_days=30)(inputs)
    out = plan(early, scenarios, "baseline", "cash_safety", time_limit_s=10)
    reasons = {r["card"]: r["reason"] for r in out.rejections}
    assert reasons["B"] == "REPAY_BEFORE_TXN_DATE"
    assert out.solve is not None
    assert "B: excluded (REPAY_BEFORE_TXN_DATE)" in out.solve.notes


def test_no_card_left_after_the_repayment_date_check_is_explained(fx: Fx) -> None:
    inputs, scenarios, _ = fx
    out = plan(_request(payment_lead_days=60)(inputs), scenarios, "baseline", "cash_safety", 10)
    # No card left is a business answer (INFEASIBLE + rejections), not a model defect.
    assert out.business_status == "INFEASIBLE"
    assert out.solve is None  # the solver is not run
    assert any(note.startswith("NO_ELIGIBLE_CARDS") for note in out.notes)
    assert {r["card"]: r["reason"] for r in out.rejections} == {
        "A": "REPAY_BEFORE_TXN_DATE",
        "B": "REPAY_BEFORE_TXN_DATE",
        "C": "REPAY_BEFORE_TXN_DATE",
    }


def test_verifier_applies_and_flags_a_planned_repayment_dated_before_the_snapshot(
    fx: Fx,
) -> None:
    inputs, scenarios, _ = fx
    early = _request(payment_lead_days=60)(inputs)  # A pays 09-29, C pays 09-26 < 10-16
    v = verify(early, {"A": 800000, "C": 200000}, scenarios, "baseline")
    assert not v.ok
    flagged = [m for m in v.violations if m.startswith("PLANNED_REPAYMENT_BEFORE_SNAPSHOT")]
    assert len(flagged) == 2
    assert any(m.startswith("A: ineligible (REPAY_BEFORE_TXN_DATE)") for m in v.violations)
    # the 10,000.00 of repayments is applied on the snapshot day, not skipped:
    # 5,000 - 10,000 = -5,000 on 10-16, lowest -7,000 on 10-28 (the old verifier saw 3,000 / ok)
    chk = v.checks["baseline"]
    assert not chk.ok
    assert chk.min_balance_by_account["cash-main"] == -700000
    assert chk.breaches[0]["on"] == date(2026, 10, 16)
    assert chk.breaches[0]["balance"] == -500000
    assert sorted(chk.breaches[0]["events"]) == ["plan_repay_A", "plan_repay_C"]


# --- 3. exhausted shared pools ---------------------------------------------------------------


@pytest.mark.parametrize("available", [0, -100])
def test_an_exhausted_pool_is_clamped_to_zero_and_other_cards_stay_usable(
    fx: Fx, available: int
) -> None:
    inputs, scenarios, _ = fx
    pooled = replace(
        _card(1, pool_id="pool-B")(inputs), pools={"pool-B": available}
    )  # card B alone in a pool with nothing left
    out = plan(pooled, scenarios, "baseline", "cash_safety", time_limit_s=10)
    assert out.business_status == "CONDITIONALLY_FEASIBLE"
    assert out.allocation == {"A": 800000, "C": 200000}
    assert {r["card"]: r["reason"] for r in out.rejections} == {"B": "NO_CAPACITY"}
    res = solve(pooled, scenarios["baseline"], "cash_safety", time_limit_s=10)
    assert res.status == "OPTIMAL"
    assert res.allocation == {"A": 800000, "C": 200000}


def test_any_amount_on_a_card_of_an_exhausted_pool_is_a_violation(fx: Fx) -> None:
    inputs, scenarios, _ = fx
    pooled = replace(_card(1, pool_id="pool-B")(inputs), pools={"pool-B": -100})
    v = verify(pooled, {"A": 800000, "B": 200000}, scenarios, "baseline")
    assert not v.structural_ok
    assert "pool pool-B: 200000 exceeds shared capacity 0" in v.violations
    assert "B: ineligible (NO_CAPACITY)" in v.violations


# --- 4. non-integer amounts ------------------------------------------------------------------


@pytest.mark.parametrize(
    "amount",
    [800000.0, 800000.5, True, Decimal("800000"), "800000"],
    ids=["integral-float", "float", "bool", "decimal", "string"],
)
def test_verifier_refuses_non_integer_amounts(fx: Fx, amount: object) -> None:
    inputs, scenarios, _ = fx
    with pytest.raises(TypeError, match="must be an int"):
        verify(inputs, {"A": amount, "C": 200000}, scenarios, "baseline")
