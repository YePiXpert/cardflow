"""Supported numeric range of protocol v1 (T-004b, item 1).

The limits are derived from the CP-SAT model (README "支持的数值范围"): money |v| <= 10^13
minor units (= the engine's variable bound BIG), rates in [0, 1] with at most 5 decimals,
scale factors in [0, 10], dates 1970-01-01..2999-12-31, at most 200 cards, 100 cash accounts
and 10,000 events. Checked here:

* schema and adapter accept the limit and reject the first value beyond it;
* every case of ``evidence/m0/T-004/engine-limits-probe.txt`` through the protocol: out of range
  -> ProtocolError (VALIDATION_ERROR), in range -> a business status;
* a document with EVERY value at its limit is valid and builds a CP-SAT model that passes
  CP-SAT's own overflow validation; one step beyond (a 6th rate decimal, money x10) does not.
"""

import copy
from dataclasses import replace
from datetime import date, timedelta
from decimal import Decimal
from types import ModuleType
from typing import Any

import pytest
from referencing import Registry

from cardflow.planner.engine import allocation, protocol
from cardflow.planner.engine.allocation import (
    TIERS,
    ModelInputs,
    build_model,
    derive_card_info,
)
from cardflow.planner.engine.billing import BillingRule, DueRule
from cardflow.planner.engine.cash import Scenario
from cardflow.planner.engine.fixture import load_fixture
from cardflow.planner.engine.protocol import (
    ProtocolError,
    card_cycles_to_protocol,
    inputs_from_protocol,
    plan_from_protocol,
)

type Doc = dict[str, Any]

LIMIT = 10**13
I63 = 2**63 - 1
SCHEMA = "PlanInput.schema.json"


def _set(doc: Doc, path: tuple[str | int, ...], value: object) -> Doc:
    out = copy.deepcopy(doc)
    node: Any = out
    for key in path[:-1]:
        node = node[key]
    node[path[-1]] = value
    return out


def _accepted(runner: ModuleType, registry: Registry, doc: Doc) -> tuple[bool, bool]:
    """(schema accepts, adapter accepts)."""
    schema_ok = runner.schema_errors(registry, SCHEMA, doc) == []
    try:
        inputs_from_protocol(doc)
    except ProtocolError:
        return schema_ok, False
    return schema_ok, True


def test_the_limits_are_the_engine_bounds() -> None:
    assert getattr(protocol, "MONEY_LIMIT", None) == allocation.BIG == LIMIT
    assert getattr(protocol, "MAX_CARDS", None) == 200
    assert getattr(protocol, "MAX_CASH_ACCOUNTS", None) == 100
    assert getattr(protocol, "MAX_EVENTS", None) == 10000


BOUNDARY = [
    ("amount-at-limit", ("request", "amount_minor"), LIMIT, True),
    ("amount-over-limit", ("request", "amount_minor"), LIMIT + 1, False),
    ("balance-at-negative-limit", ("snapshots", 0, "balance_minor"), -LIMIT, True),
    ("balance-under-negative-limit", ("snapshots", 0, "balance_minor"), -LIMIT - 1, False),
    ("available-at-limit", ("cards", 0, "raw_available_minor"), LIMIT, True),
    ("available-over-limit", ("cards", 0, "raw_available_minor"), LIMIT + 1, False),
    ("event-under-negative-limit", ("events", 0, "amount_minor"), -LIMIT - 1, False),
    ("floor-over-limit", ("cash_accounts", 0, "reserve_floor_minor"), LIMIT + 1, False),
    ("global-floor-over-limit", ("options", "global_reserve_floor_minor"), LIMIT + 1, False),
    ("rate-one", ("cards", 0, "fee_rate"), "1", True),
    # R3E-11 (T-004c): one canonical text per rate -- "1.00000" is "1" written differently
    ("rate-one-padded", ("cards", 0, "fee_rate"), "1.00000", False),
    ("rate-five-decimals", ("cards", 0, "fee_rate"), "0.99999", True),
    ("rate-six-decimals", ("cards", 0, "fee_rate"), "0.000001", False),
    ("rate-above-one", ("cards", 0, "fee_rate"), "1.00001", False),
    ("rate-two", ("cards", 0, "verified_benefit_rate"), "2", False),
    ("scale-ten", ("scenarios", 0, "income_scale"), "10", True),
    ("scale-ten-padded", ("scenarios", 0, "expense_scale"), "10.0000000000", False),  # R3E-11
    ("scale-below-ten", ("scenarios", 0, "expense_scale"), "9.9999999999", True),
    ("scale-above-ten", ("scenarios", 0, "income_scale"), "10.1", False),
    ("date-first", ("horizon_end",), "1970-01-01", True),
    ("date-before-first", ("horizon_end",), "1969-12-31", False),
    ("date-last", ("horizon_end",), "2999-12-31", True),
    ("date-after-last", ("horizon_end",), "3000-01-01", False),
    ("timestamp-in-range", ("snapshots", 0, "observed_at"), "2026-10-16T09:00:00+08:00", True),
    ("timestamp-after-last", ("snapshots", 0, "observed_at"), "3000-01-01T00:00:00Z", False),
]


@pytest.mark.parametrize(
    ("path", "value", "accepted"), [c[1:] for c in BOUNDARY], ids=[c[0] for c in BOUNDARY]
)
def test_schema_and_adapter_agree_on_the_supported_range(
    runner: ModuleType,
    registry: Registry,
    plan_input: Doc,
    path: tuple[str | int, ...],
    value: object,
    accepted: bool,
) -> None:
    assert _accepted(runner, registry, _set(plan_input, path, value)) == (accepted, accepted)


def _grow(doc: Doc, member: str, count: int) -> Doc:
    out = copy.deepcopy(doc)
    template = out[member][0]
    key = {"cards": "card_id", "cash_accounts": "cash_account_id", "events": "event_id"}[member]
    extra = [dict(template, **{key: f"x{i}"}) for i in range(count - len(out[member]))]
    out[member] = out[member] + extra
    return out


@pytest.mark.parametrize(
    ("member", "limit"), [("cards", 200), ("cash_accounts", 100), ("events", 10000)]
)
def test_array_sizes_are_limited(
    runner: ModuleType, registry: Registry, plan_input: Doc, member: str, limit: int
) -> None:
    assert _accepted(runner, registry, _grow(plan_input, member, limit)) == (True, True)
    over = _grow(plan_input, member, limit + 1)
    assert _accepted(runner, registry, over) == (False, False)
    with pytest.raises(ProtocolError) as caught:
        inputs_from_protocol(over)
    assert caught.value.path == f"/{member}"


# Every case of engine-limits-probe.txt through the protocol: a JSON Pointer = ProtocolError at
# that member (and the schema rejects too); otherwise the business status of the run.
PROBE = [
    (
        "raw_available = 2^63-1",
        ("cards", 0, "raw_available_minor"),
        I63,
        "/cards/0/raw_available_minor",
    ),
    ("amount = 2^62", ("request", "amount_minor"), 2**62, "/request/amount_minor"),
    ("amount = 2^63-1", ("request", "amount_minor"), I63, "/request/amount_minor"),
    ("balance = -2^63", ("snapshots", 0, "balance_minor"), -(2**63), "/snapshots/0/balance_minor"),
    ("balance = 2^63-1", ("snapshots", 0, "balance_minor"), I63, "/snapshots/0/balance_minor"),
    ("event amount = 2^63-1", ("events", 0, "amount_minor"), I63, "/events/0/amount_minor"),
    ("balance = 10^13", ("snapshots", 0, "balance_minor"), LIMIT, "FEASIBLE_ROBUST"),
    ("fee_rate = 0.006", ("cards", 0, "fee_rate"), "0.006", "CONDITIONALLY_FEASIBLE"),
    ("fee_rate = 0.1234567891", ("cards", 0, "fee_rate"), "0.1234567891", "/cards/0/fee_rate"),
    (
        "fee_rate = 9999999999.9999999999",
        ("cards", 0, "fee_rate"),
        "9999999999.9999999999",
        "/cards/0/fee_rate",
    ),
    ("payment_lead_days = 60", ("request", "payment_lead_days"), 60, "INFEASIBLE"),
]


@pytest.mark.parametrize(
    ("path", "value", "expected"), [c[1:] for c in PROBE], ids=[c[0] for c in PROBE]
)
def test_probe_cases_through_the_protocol(
    runner: ModuleType,
    registry: Registry,
    plan_input: Doc,
    path: tuple[str | int, ...],
    value: object,
    expected: str,
) -> None:
    doc = _set(plan_input, path, value)
    if expected.startswith("/"):
        assert runner.schema_errors(registry, SCHEMA, doc) != []
        with pytest.raises(ProtocolError) as caught:
            inputs_from_protocol(doc)
        assert caught.value.path == expected
        return
    outcome = plan_from_protocol(doc)
    assert outcome["business_status"] == expected
    assert runner.schema_errors(registry, "PlanOutcome.schema.json", outcome) == []
    if expected == "INFEASIBLE":  # payment_lead_days = 60: no card may repay before the txn
        assert {r["card_id"]: r["reason"] for r in outcome["rejections"]} == {
            "A": "REPAY_BEFORE_TXN_DATE",
            "B": "REPAY_BEFORE_TXN_DATE",
            "C": "REPAY_BEFORE_TXN_DATE",
        }


# --- the derivation: every value at its limit still builds a valid CP-SAT model ---------------


def _worst_case_document() -> Doc:
    """Every magnitude at its v1 limit: 200 cards with the largest capacity, fee, benefit and
    repayment buffer, 100 cash accounts, 10,000 'living' outflows of -10^13 scaled x10 on one
    account, the largest reserve floors and global floor."""
    rate = "0.99999"
    card = {
        "credit_account_id": "acc",
        "raw_available_minor": LIMIT,
        "holds_uncounted_minor": 0,
        "reservations_minor": 0,
        "billing_rule": {
            "rule_id": "r",
            "statement_day": 16,
            "statement_day_inclusive": True,
            "due": {"kind": "fixed_day", "day": 31, "month_offset": 2},
            "holiday_rollover": "none",
        },
        "repay_from_cash_account_id": "cash-0",
        "channel_ok": True,
        "currency_ok": True,
        "status_ok": True,
        "fee_rate": rate,
        "fee_fixed_minor": LIMIT,
        "verified_benefit_rate": rate,
        "verified_benefit_cap_minor": LIMIT,
        "potential_benefit_rate": rate,
        "posting_delay_min_days": 366,
        "posting_delay_max_days": 366,
    }
    start = date(2026, 10, 17)
    return {
        "protocol_version": "1",
        "request": {
            "amount_minor": LIMIT,
            "currency": "CNY",
            "txn_date": "2026-10-16",
            "allow_split": True,
            "max_cards": 200,
            "min_split_minor": 1,
            "payment_lead_days": 0,
            "channel": "pos",
        },
        "cards": [dict(card, card_id=f"c{i}") for i in range(200)],
        "pools": [],
        "cash_accounts": [
            {
                "cash_account_id": f"cash-{j}",
                "currency": "CNY",
                "reserve_floor_minor": LIMIT,
                "usable_for_repayment": True,
            }
            for j in range(100)
        ],
        "snapshots": [
            {
                "cash_account_id": f"cash-{j}",
                "balance_minor": LIMIT,
                "as_of": "2026-10-16",
                "includes_event_ids": [],
            }
            for j in range(100)
        ],
        "events": [
            {
                "event_id": f"e{k}",
                "cash_account_id": "cash-0",
                "on": (start + timedelta(days=k % 10)).isoformat(),
                "amount_minor": -LIMIT,
                "cls": "confirmed",
                "category": "living",
            }
            for k in range(10000)
        ],
        "scenarios": [
            {
                "scenario_id": "s",
                "include_expected": True,
                "income_delay_days": 0,
                "income_scale": "10",
                "expense_scale": "10",
                "event_overrides": [],
                "same_day_order": "conservative",
            }
        ],
        "horizon_end": "2028-12-31",
        "options": {
            "profile": "cash_safety",
            "decision_scenario": "s",
            "time_limit_s": 10,
            "workers": 8,
            "seed": 0,
            "stale_after_days": 7,
            "global_reserve_floor_minor": LIMIT,
        },
    }


def _validation_errors(inputs: ModelInputs, scenario: Scenario) -> list[str]:
    """CP-SAT's own model check (incl. its integer-overflow check) for the three model
    variants the engine builds, with every objective expression also used as a constraint."""
    infos = [derive_card_info(c, inputs.request) for c in inputs.cards]
    bounds = [(name, sense, 0) for tiers in TIERS.values() for name, sense in tiers]
    errors = []
    for variant in ({}, {"extra_cash_vars": True}, {"amount_var": True}):
        try:
            built = build_model(inputs, [scenario], infos, bounds, **variant)
            built.model.maximize(built.exprs["buffer"])
            errors.append(built.model.validate())
        except (TypeError, ValueError, OverflowError) as e:  # OR-Tools refused a coefficient
            errors.append(f"construction error: {type(e).__name__}")
    return errors


@pytest.fixture(scope="module")
def worst_case() -> tuple[ModelInputs, Scenario]:
    inputs, scenarios, _ = inputs_from_protocol(_worst_case_document())
    return inputs, scenarios["s"]


def test_a_document_with_every_value_at_its_limit_is_valid(
    runner: ModuleType, registry: Registry
) -> None:
    assert runner.schema_errors(registry, SCHEMA, _worst_case_document()) == []


def test_every_value_at_its_limit_still_builds_a_valid_cp_sat_model(
    worst_case: tuple[ModelInputs, Scenario],
) -> None:
    inputs, scenario = worst_case
    assert max(derive_card_info(c, inputs.request).buffer_days for c in inputs.cards) == 472
    assert _validation_errors(inputs, scenario) == ["", "", ""]


@pytest.mark.parametrize(
    ("rate", "money"),
    [(Decimal("0.999999"), LIMIT), (Decimal("0.99999"), 10 * LIMIT)],
    ids=["sixth-rate-decimal", "money-times-ten"],
)
def test_one_step_beyond_the_limits_overflows(
    worst_case: tuple[ModelInputs, Scenario], rate: Decimal, money: int
) -> None:
    inputs, scenario = worst_case
    beyond = replace(
        inputs.cards[0],
        raw_available=money,
        fee_rate=rate,
        fee_fixed=money,
        verified_benefit_rate=rate,
        verified_benefit_cap=money,
    )
    small = ModelInputs(
        inputs.request,
        [beyond],
        {},
        inputs.accounts[:1],
        {"cash-0": inputs.snapshots["cash-0"]},
        inputs.events[:1],
        inputs.horizon_end,
    )
    errors = _validation_errors(small, scenario)
    # not representable: CP-SAT's overflow check fails, or OR-Tools refuses a coefficient
    assert all("overflow" in e.lower() or e.startswith("construction error") for e in errors)
    assert all(errors), errors


def test_range_errors_name_the_bounds_but_never_echo_the_amount(plan_input: Doc) -> None:
    for value in (2**62, -(2**62), LIMIT + 1):
        with pytest.raises(ProtocolError) as caught:
            inputs_from_protocol(_set(plan_input, ("snapshots", 0, "balance_minor"), value))
        assert str(abs(value)) not in str(caught.value)
        assert caught.value.message == f"must be an integer in [{-LIMIT}, {LIMIT}]"


def test_card_cycles_report_an_unrepresentable_cycle_instead_of_raising(paths: Any) -> None:  # noqa: ANN401
    inputs, _, _ = load_fixture(paths.legacy_fixture)
    last = date(9999, 12, 31)  # outside the protocol's range: engine objects built directly
    rule = BillingRule("r31", 31, DueRule("days_after_statement", days=20))
    late = replace(
        inputs,
        request=replace(inputs.request, txn_date=last),
        cards=[replace(inputs.cards[0], billing_rule=rule), *inputs.cards[1:]],
    )
    cycles = card_cycles_to_protocol(late)
    assert cycles["A"] == {"error": "date value out of range"}
