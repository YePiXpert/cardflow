# Migrated from poc/engine_reference/tests/test_properties.py (T-003): assertions and expected
# values unchanged; only imports, the fixture path, type annotations, formatting and `noqa`
# markers differ.
"""Property tests (hypothesis): conservation, monotonicity, order invariance, no credit-as-cash."""

import random
from dataclasses import replace
from datetime import date, timedelta
from pathlib import Path

from hypothesis import HealthCheck, given, settings
from hypothesis import strategies as st

from cardflow.planner.engine.allocation import CardOption, ModelInputs, PlanRequest, solve
from cardflow.planner.engine.billing import BillingRule, DueRule
from cardflow.planner.engine.cash import (
    CashAccount,
    CashEvent,
    EventClass,
    Scenario,
    Snapshot,
    build_timeline,
    evaluate,
)
from cardflow.planner.engine.fixture import load_fixture
from cardflow.planner.engine.money import from_minor, split_installments, to_minor
from cardflow.planner.engine.verifier import verify

# Golden fixture, located relative to this file (repository root = parents[4]).
FIX = (
    Path(__file__).resolve().parents[4]
    / "packages"
    / "rules-protocol"
    / "fixtures"
    / "regression_2026-10-16_10000.json"
)
INPUTS, SCENARIOS, _ = load_fixture(FIX)
ACC = CashAccount("m", "main", reserve_floor=0)
SC = Scenario("s")

amounts = st.integers(min_value=-500000, max_value=500000)
days = st.integers(min_value=0, max_value=120)


def _events(pairs: list[tuple[int, int]]) -> list[CashEvent]:
    return [
        CashEvent(
            f"e{i}", "m", date(2026, 10, 16) + timedelta(days=d), a, EventClass.CONFIRMED, "bill"
        )
        for i, (d, a) in enumerate(pairs)
    ]


@given(
    st.integers(0, 1000000), st.lists(st.tuples(days, amounts), max_size=12), st.integers(0, 500000)
)
@settings(max_examples=150, deadline=None)
def test_more_confirmed_cash_never_hurts(
    balance: int, pairs: list[tuple[int, int]], extra: int
) -> None:
    evs = _events(pairs)
    r1 = evaluate(
        build_timeline(ACC, Snapshot("m", balance, date(2026, 10, 16)), evs, SC, date(2027, 3, 1)),
        0,
    )
    r2 = evaluate(
        build_timeline(
            ACC, Snapshot("m", balance + extra, date(2026, 10, 16)), evs, SC, date(2027, 3, 1)
        ),
        0,
    )
    assert r2.min_balance == r1.min_balance + extra
    assert r1.ok <= r2.ok


@given(
    st.integers(0, 1000000),
    st.lists(st.tuples(days, amounts), max_size=12),
    days,
    st.integers(1, 300000),
)
@settings(max_examples=150, deadline=None)
def test_known_outflow_never_raises_cash(
    balance: int, pairs: list[tuple[int, int]], d: int, out: int
) -> None:
    evs = _events(pairs)
    base = evaluate(
        build_timeline(ACC, Snapshot("m", balance, date(2026, 10, 16)), evs, SC, date(2027, 3, 1)),
        0,
    )
    more = evs + [  # noqa: RUF005
        CashEvent(
            "x", "m", date(2026, 10, 16) + timedelta(days=d), -out, EventClass.CONFIRMED, "bill"
        )
    ]
    r = evaluate(
        build_timeline(ACC, Snapshot("m", balance, date(2026, 10, 16)), more, SC, date(2027, 3, 1)),
        0,
    )
    assert r.min_balance <= base.min_balance and r.end_balance == base.end_balance - out  # noqa: PT018


@given(st.integers(0, 1000000), st.lists(st.tuples(days, amounts), max_size=12), st.randoms())
@settings(max_examples=100, deadline=None)
def test_event_order_invariance(
    balance: int, pairs: list[tuple[int, int]], rnd: random.Random
) -> None:
    evs = _events(pairs)
    shuffled = list(evs)
    rnd.shuffle(shuffled)
    a = evaluate(
        build_timeline(ACC, Snapshot("m", balance, date(2026, 10, 16)), evs, SC, date(2027, 3, 1)),
        0,
    )
    b = evaluate(
        build_timeline(
            ACC, Snapshot("m", balance, date(2026, 10, 16)), shuffled, SC, date(2027, 3, 1)
        ),
        0,
    )
    assert (a.min_balance, a.end_balance, [(x.on, x.balance) for x in a.breaches]) == (
        b.min_balance,
        b.end_balance,
        [(x.on, x.balance) for x in b.breaches],
    )


@given(
    st.integers(1, 2000000),
    st.lists(st.integers(1, 1500000), min_size=1, max_size=4),
    st.integers(1, 4),
    st.randoms(),
)
@settings(max_examples=40, deadline=None, suppress_health_check=[HealthCheck.too_slow])
def test_solver_conservation_bounds_and_card_order(
    amount: int, caps: list[int], k: int, rnd: random.Random
) -> None:
    rule = BillingRule("r", 10, DueRule("fixed_day", day=28))
    cards = [CardOption(f"c{i}", f"a{i}", f"c{i}", cap, rule, "cash") for i, cap in enumerate(caps)]
    acct = CashAccount("cash", "cash", reserve_floor=0)
    snap = {"cash": Snapshot("cash", 10**9, date(2026, 10, 16))}  # cash is not binding here
    req = PlanRequest(amount, "CNY", date(2026, 10, 16), allow_split=True, max_cards=k, min_split=1)
    inputs = ModelInputs(req, cards, {}, [acct], snap, [], date(2027, 1, 14))
    res = solve(inputs, SC, "fewer_cards", time_limit_s=5)
    shuffled = list(cards)
    rnd.shuffle(shuffled)
    res2 = solve(replace(inputs, cards=shuffled), SC, "fewer_cards", time_limit_s=5)
    assert res.status == res2.status
    if res.status in ("OPTIMAL", "FEASIBLE"):
        assert sum(res.allocation.values()) == amount
        assert all(
            0 < v <= next(c.capacity for c in cards if c.id == cid)
            for cid, v in res.allocation.items()
        )
        assert len(res.allocation) <= k
        assert len(res.allocation) == len(res2.allocation)
        assert verify(inputs, res.allocation, {"s": SC}, "s").ok
    else:
        assert res.status == "INFEASIBLE"
        # a feasible split must not exist: cheapest check = top-k capacities cannot reach the amount
        assert sum(sorted(caps, reverse=True)[:k]) < amount


def test_credit_limit_is_never_cash() -> None:
    """Raising card capacity must not change the cash timeline or rescue a cash-infeasible plan."""
    rich = replace(INPUTS, cards=[replace(c, raw_available=10**9) for c in INPUTS.cards])
    v = verify(rich, {"B": 1000000}, SCENARIOS, "baseline")
    assert (  # noqa: PT018
        not v.checks["baseline"].ok
        and v.checks["baseline"].min_balance_by_account["cash-main"] == -700000
    )


@given(st.integers(1, 10**9), st.integers(1, 36))
@settings(max_examples=200, deadline=None)
def test_installment_split_conserves_principal(principal: int, periods: int) -> None:
    parts = split_installments(principal, periods)
    assert sum(parts) == principal and len(parts) == periods  # noqa: PT018
    assert len(set(parts[:-1])) <= 1  # all periods equal except the last (CCB clause)


@given(st.integers(0, 10**12))
@settings(max_examples=200, deadline=None)
def test_minor_unit_roundtrip(n: int) -> None:
    assert to_minor(from_minor(n, "CNY"), "CNY") == n
    assert to_minor(from_minor(n, "JPY"), "JPY") == n
    assert to_minor(from_minor(n, "KWD"), "KWD") == n
