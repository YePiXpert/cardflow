"""Reproducibility of the CP-SAT solve (T-004 B.5, T-004c R3E-06; engine-spec §11, §12.5).

With a fixed ``random_seed`` (ADR-004) every repetition must return the same solver status, the
same allocation (including card order) and the same value, bound and status for every objective
tier -- and, since model 1.1.0, the same allocation for ANY number of workers: ties left after
the last objective tier are broken deterministically (the lexicographically largest allocation
in card input order), in the main solve and in the sensitivity solves. F-18 has a unique
optimum; the tie-rich instances below (the wave-3 review's 30 near-identical cards, identical
small cards) are where multi-threaded CP-SAT used to return different allocations. The full
statistics (20 repetitions each, workers 8 and 1) are in
``evidence/m0/T-004/c2-determinism.txt``.
"""

import copy
import json
import random
from datetime import date, timedelta
from pathlib import Path
from typing import Any

import pytest

from cardflow.planner.engine.allocation import ModelInputs, solve
from cardflow.planner.engine.cash import Scenario
from cardflow.planner.engine.fixture import load_fixture
from cardflow.planner.engine.protocol import plan_from_protocol

FIX = (
    Path(__file__).resolve().parents[4]
    / "packages"
    / "rules-protocol"
    / "fixtures"
    / "regression_2026-10-16_10000.json"
)
REPETITIONS = 20

type Fx = tuple[ModelInputs, dict[str, Scenario], dict[str, Any]]
type Doc = dict[str, Any]


@pytest.fixture(scope="module")
def fx() -> Fx:
    return load_fixture(FIX)


@pytest.mark.parametrize("workers", [8, 1])
@pytest.mark.parametrize("profile", ["cash_safety", "verified_benefit", "fewer_cards"])
def test_repeated_solves_return_identical_allocations_and_tier_values(
    fx: Fx, profile: str, workers: int
) -> None:
    inputs, scenarios, _ = fx
    results = set()
    for _ in range(REPETITIONS):
        res = solve(inputs, scenarios["baseline"], profile, time_limit_s=10, workers=workers)
        results.add(
            (
                res.status,
                tuple(res.allocation.items()),
                tuple((t.name, t.sense, t.status, t.value, t.bound) for t in res.tiers),
            )
        )
    assert len(results) == 1, results
    ((status, alloc, _),) = results
    assert status == "OPTIMAL"
    assert alloc == (("A", 800000), ("C", 200000))  # golden: engine-spec §9


def thirty_near_identical_cards(profile: str, workers: int) -> Doc:
    """The review's P-DET instance (``probe_determinism_big.py``, event seed 5): 30 cards in
    three near-identical groups, 2 cash accounts, 60 events, spend 155.00 with up to 30 cards."""
    rng = random.Random(5)  # noqa: S311 -- seeded test data, not cryptography
    events = [
        {
            "event_id": f"e{k}",
            "cash_account_id": f"cash-{k % 2}",
            "on": (date(2026, 10, 17) + timedelta(days=rng.randint(0, 90))).isoformat(),
            "amount_minor": rng.choice([-1, 1]) * rng.randint(100, 3000),
            "cls": "confirmed",
            "category": "bill",
        }
        for k in range(60)
    ]
    cards = [
        {
            "card_id": f"c{i:02d}",
            "credit_account_id": f"acc-{i}",
            "raw_available_minor": 1000 + 100 * (i % 3),
            "holds_uncounted_minor": 0,
            "reservations_minor": 0,
            "billing_rule": {
                "rule_id": f"r{i}",
                "statement_day": [5, 10, 20][i % 3],
                "statement_day_inclusive": True,
                "due": {"kind": "fixed_day", "day": 25, "month_offset": 1},
                "holiday_rollover": "none",
            },
            "repay_from_cash_account_id": f"cash-{i % 2}",
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
        for i in range(30)
    ]
    return {
        "protocol_version": "1",
        "request": {
            "amount_minor": 15500,
            "currency": "CNY",
            "txn_date": "2026-10-16",
            "allow_split": True,
            "max_cards": 30,
            "min_split_minor": 1,
            "payment_lead_days": 0,
            "channel": "pos",
        },
        "cards": cards,
        "pools": [],
        "cash_accounts": [
            {
                "cash_account_id": f"cash-{j}",
                "currency": "CNY",
                "reserve_floor_minor": 0,
                "usable_for_repayment": True,
            }
            for j in range(2)
        ],
        "snapshots": [
            {
                "cash_account_id": f"cash-{j}",
                "balance_minor": 200000,
                "as_of": "2026-10-16",
                "includes_event_ids": [],
            }
            for j in range(2)
        ],
        "events": events,
        "scenarios": [
            {
                "scenario_id": "base",
                "include_expected": True,
                "income_delay_days": 0,
                "income_scale": "1",
                "expense_scale": "1",
                "event_overrides": [],
                "same_day_order": "conservative",
            }
        ],
        "horizon_end": "2027-03-31",
        "options": {
            "profile": profile,
            "decision_scenario": "base",
            "time_limit_s": 10,
            "workers": workers,
            "seed": 0,
            "stale_after_days": 7,
            "global_reserve_floor_minor": 0,
        },
    }


def _outcome_key(out: Doc) -> str:
    """Everything of an outcome except run id, clock times and the workers option itself."""
    keep = {
        k: v
        for k, v in out.items()
        if k not in ("run_id", "created_at", "wall_time_s", "input_hash", "workers")
    }
    keep["tiers"] = [{k: v for k, v in t.items() if k != "wall_time_s"} for t in out["tiers"]]
    return json.dumps(keep, sort_keys=True)


@pytest.mark.parametrize("profile", ["cash_safety", "fewer_cards"])
def test_tied_optima_give_one_allocation_for_any_workers_r3e_06(profile: str) -> None:
    """R3E-06 (§12.5): on the review's 30-card instance (4 different allocations in 20 runs
    with 8 workers before the fix) every run, with 8 or 1 worker, returns the same outcome; the
    allocation is the canonical one: each card, in input order, takes as much as the optimum
    allows."""
    outcomes = set()
    allocations = set()
    for workers in (8, 8, 8, 8, 1, 1):
        out = plan_from_protocol(thirty_near_identical_cards(profile, workers))
        assert out["business_status"] == "FEASIBLE_ROBUST"
        outcomes.add(_outcome_key(out))
        allocations.add(tuple((a["card_id"], a["amount_minor"]) for a in out["allocation"]))
    assert len(outcomes) == 1
    assert len(allocations) == 1


def _identical_cards(n: int, avail: int, amount: int, profile: str, workers: int) -> Doc:
    doc = thirty_near_identical_cards(profile, workers)
    template = copy.deepcopy(doc["cards"][0])
    doc["cards"] = [
        dict(
            copy.deepcopy(template),
            card_id=c,
            credit_account_id=f"acc-{c}",
            raw_available_minor=avail,
        )
        for c in "ABCD"[:n]
    ]
    doc["events"] = []
    doc["request"].update(amount_minor=amount, max_cards=n)
    return doc


@pytest.mark.parametrize(
    ("n", "avail", "amount", "expected"),
    [
        (2, 5000, 1000, {"A": 1000}),
        (3, 10000, 15000, {"A": 10000, "B": 5000}),
        (4, 10000, 30000, {"A": 10000, "B": 10000, "C": 10000}),
    ],
)
@pytest.mark.parametrize("profile", ["cash_safety", "fewer_cards"])
def test_identical_cards_fill_in_input_order_r3e_06(
    n: int, avail: int, amount: int, expected: dict[str, int], profile: str
) -> None:
    """R3E-06 (§12.5): identical cards tie on every tier; the earlier card takes the most."""
    seen = set()
    for workers in (8, 8, 1):
        out = plan_from_protocol(_identical_cards(n, avail, amount, profile, workers))
        seen.add(tuple((a["card_id"], a["amount_minor"]) for a in out["allocation"]))
    assert seen == {tuple(expected.items())}
