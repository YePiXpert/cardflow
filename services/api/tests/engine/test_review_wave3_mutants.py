"""Boundary and rounding tests for the mutants that survived the wave-3 review (T-004c, R3E-16).

The review mutated one line at a time and ran ``tests/engine`` + ``tests/protocol``; six mutants
survived because no test looked at that boundary or rounding direction. Each test below names
the mutant it kills; ``evidence/m0/T-004/c2-mutants.txt`` re-applies the six mutations to the
model 1.1.0 code and shows every one of them failing the suite.

* M05 a repayment ON the transaction date is not "before" it (``<`` not ``<=``);
* M14 the verifier rounds a fee UP; M15 it rounds a verified benefit DOWN;
* M17 the CP-SAT model caps the verified benefit at ``verified_benefit_cap_minor``;
* M20 a snapshot exactly ``stale_after_days`` old is not stale;
* M26 the weighted buffer is rounded HALF_UP to 0.1 day.
"""

import copy
from dataclasses import replace
from decimal import Decimal
from pathlib import Path
from typing import Any

import pytest

from cardflow.planner.engine.allocation import ModelInputs
from cardflow.planner.engine.cash import Scenario
from cardflow.planner.engine.fixture import load_fixture
from cardflow.planner.engine.protocol import parse_json, plan_from_protocol, verify_from_protocol
from cardflow.planner.engine.verifier import verify

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


def _single_card(f18: Doc, **card: Any) -> Doc:  # noqa: ANN401
    """F-18's cash and scenarios, one card A with the given members, spend 1,000.00 alone."""
    doc = copy.deepcopy(f18)
    doc["cards"] = [dict(doc["cards"][0], **card)]
    doc["request"].update(amount_minor=100000, allow_split=False, max_cards=1)
    doc["snapshots"][0]["balance_minor"] = 10**8
    return doc


# --- M05 -----------------------------------------------------------------------------------


@pytest.mark.parametrize(("lead", "eligible"), [(5, True), (6, False)])
def test_a_repayment_on_the_transaction_date_is_allowed_m05_r3e_16(
    f18: Doc, lead: int, eligible: bool
) -> None:
    """M05: purchase 2026-12-31, statement day 31 (inclusive) -> statement 2026-12-31, due the
    5th of the next month = 2027-01-05. With 5 lead days the cash repayment is 2026-12-31, the
    purchase day itself (buffer 0): allowed. With 6 it is 2026-12-30: REPAY_BEFORE_TXN_DATE."""
    rule = dict(
        f18["cards"][0]["billing_rule"],
        statement_day=31,
        due={"kind": "fixed_day", "day": 5, "month_offset": 1},
    )
    doc = _single_card(f18, billing_rule=rule)
    doc["request"].update(txn_date="2026-12-31", payment_lead_days=lead)
    doc["snapshots"][0]["as_of"] = "2026-12-31"
    doc["events"] = []
    doc["horizon_end"] = "2027-06-30"
    for s in doc["scenarios"]:
        s["event_overrides"] = []
    out = plan_from_protocol(doc)
    if eligible:
        assert out["business_status"] == "FEASIBLE_ROBUST"
        line = out["allocation"][0]
        assert (line["due_date"], line["repay_on"], line["buffer_days"]) == (
            "2027-01-05",
            "2026-12-31",
            0,
        )
    else:
        assert out["business_status"] == "INFEASIBLE"
        assert [r["reason"] for r in out["rejections"]] == ["REPAY_BEFORE_TXN_DATE"]


# --- M14 / M15 -------------------------------------------------------------------------------


def test_the_verifier_rounds_a_fee_up_m14_r3e_16(f18: Doc) -> None:
    """M14: 0.6% of 10.01 is 0.06006 -> the fee is 0.07 (rounded UP), and the repayment that
    leaves cash on 11-28 is 10.01 + 0.07 = 10.08."""
    ends = []
    for fee_rate in ("0.006", "0"):
        doc = _single_card(f18, fee_rate=fee_rate)
        doc["request"]["amount_minor"] = 1001
        res = verify_from_protocol(doc, [{"card_id": "A", "amount_minor": 1001}], "baseline")
        check = res["verification"]["checks"]["confirmed"]
        ends.append(check["end_balance_by_account"]["cash-main"])
        if fee_rate != "0":
            assert res["allocation"][0]["fee_minor"] == 7
            assert res["verification"]["fees"] == 7
    assert ends[1] - ends[0] == 7  # the fee leaves cash with the repayment (§12.6)


def test_the_verifier_rounds_a_verified_benefit_down_m15_r3e_16(f18: Doc) -> None:
    """M15: 0.6% of 10.01 is 0.06006 -> the verified benefit is 0.06 (rounded DOWN); the
    potential benefit (same rate) as well."""
    doc = _single_card(f18, verified_benefit_rate="0.006", potential_benefit_rate="0.006")
    doc["request"]["amount_minor"] = 1001
    res = verify_from_protocol(doc, [{"card_id": "A", "amount_minor": 1001}], "baseline")
    line = res["allocation"][0]
    assert (line["verified_benefit_minor"], line["potential_benefit_minor"]) == (6, 6)
    assert res["verification"]["verified_benefit"] == 6


# --- M17 -------------------------------------------------------------------------------------


def test_the_model_caps_the_verified_benefit_m17_r3e_16(f18: Doc) -> None:
    """M17: verified_benefit profile, one card for 200.00. A earns 1% but at most 0.50; B earns
    0.5% without a cap = 1.00. With the cap B wins the benefit tier (1.00 > 0.50); a model that
    ignored the cap would take A (2.00)."""
    doc = copy.deepcopy(f18)
    a = dict(doc["cards"][0], verified_benefit_rate="0.01", verified_benefit_cap_minor=50)
    b = dict(doc["cards"][1], verified_benefit_rate="0.005")
    doc["cards"] = [a, b]
    doc["request"].update(amount_minor=20000, allow_split=False, max_cards=1)
    doc["snapshots"][0]["balance_minor"] = 10**8
    doc["options"]["profile"] = "verified_benefit"
    out = plan_from_protocol(doc)
    assert [(x["card_id"], x["verified_benefit_minor"]) for x in out["allocation"]] == [("B", 100)]
    tiers = {t["name"]: t["value"] for t in out["tiers"]}
    assert tiers["net_verified_benefit"] == 100


# --- M20 -------------------------------------------------------------------------------------


@pytest.mark.parametrize(("txn_date", "stale"), [("2026-10-23", False), ("2026-10-24", True)])
def test_a_snapshot_exactly_stale_after_days_old_is_not_stale_m20_r3e_16(
    f18: Doc, txn_date: str, stale: bool
) -> None:
    """M20: snapshot of 10-16, stale_after_days 7: a purchase on 10-23 (age 7) is planned, one
    on 10-24 (age 8) is NEEDS_DATA / STALE_SNAPSHOT."""
    f18["request"]["txn_date"] = txn_date
    out = plan_from_protocol(f18)
    codes = [i["code"] for i in out["data_issues"]]
    assert codes == (["STALE_SNAPSHOT"] if stale else [])
    assert (out["business_status"] == "NEEDS_DATA") is stale


# --- M26 -------------------------------------------------------------------------------------


def test_the_weighted_buffer_rounds_half_up_m26_r3e_16(fx: Fx) -> None:
    """M26: 0.01 on A (43 days) + 0.11 on C (40 days) = (43 + 440) / 12 = 40.25 days ->
    "40.3" (HALF_UP; HALF_EVEN would give 40.2)."""
    inputs, scenarios, _ = fx
    small = replace(inputs, request=replace(inputs.request, amount=12))
    v = verify(small, {"A": 1, "C": 11}, scenarios, "baseline")
    assert v.weighted_buffer_days == Decimal("40.3")
