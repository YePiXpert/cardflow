"""Invalid PlanInput documents are rejected (T-004, A.6).

Every case mutates the F-18 PlanInput. Rules JSON Schema can express are checked twice: by
the runner's validator (Draft 2020-12, format checker, strict integers) AND by the stdlib-only
adapter (``inputs_from_protocol``), which must not rely on prior schema validation. Rules
beyond JSON Schema (uniqueness, cross references, single currency, delay order) are schema-valid
but rejected by the adapter -- every v1 adapter (Python, Dart) must implement them.
"""

import copy
from collections.abc import Callable
from types import ModuleType
from typing import Any

import pytest
from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry

from cardflow.planner.engine.protocol import ProtocolError, inputs_from_protocol

type Doc = dict[str, Any]
type Mutation = Callable[[Doc], None]

SCHEMA = "PlanInput.schema.json"


def _set(*path: str | int, value: object) -> Mutation:
    def mutate(doc: Doc) -> None:
        node: Any = doc
        for key in path[:-1]:
            node = node[key]
        node[path[-1]] = value

    return mutate


def _delete(*path: str | int) -> Mutation:
    def mutate(doc: Doc) -> None:
        node: Any = doc
        for key in path[:-1]:
            node = node[key]
        del node[path[-1]]

    return mutate


def _append(*path: str | int, value: object) -> Mutation:
    def mutate(doc: Doc) -> None:
        node: Any = doc
        for key in path:
            node = node[key]
        node.append(copy.deepcopy(value))

    return mutate


def _duplicate_snapshot(doc: Doc) -> None:
    doc["snapshots"].append(copy.deepcopy(doc["snapshots"][0]))


def _other_accounts_event_included(doc: Doc) -> None:
    second = dict(doc["cash_accounts"][0], cash_account_id="cash-2", name="cash-2")
    doc["cash_accounts"].append(second)
    event = dict(doc["events"][0], event_id="e9", cash_account_id="cash-2", on="2026-10-16")
    doc["events"].append(event)
    doc["snapshots"][0]["includes_event_ids"] = ["e9"]


# (case id, mutation, JSON Pointer of the error the adapter must report)
BOTH = [
    ("float-amount", _set("request", "amount_minor", value=1000000.5), "/request/amount_minor"),
    (
        "integral-float-amount",
        _set("request", "amount_minor", value=1000000.0),
        "/request/amount_minor",
    ),
    ("float-balance", _set("snapshots", 0, "balance_minor", value=500000.0), "/snapshots/0"),
    ("float-rate", _set("cards", 0, "fee_rate", value=0.006), "/cards/0/fee_rate"),
    ("rate-exponent", _set("cards", 0, "fee_rate", value="6E-3"), "/cards/0/fee_rate"),
    ("rate-11-digits", _set("cards", 0, "fee_rate", value="0.00000000001"), "/cards/0/fee_rate"),
    ("bool-amount", _set("request", "amount_minor", value=True), "/request/amount_minor"),
    ("bool-count", _set("request", "max_cards", value=True), "/request/max_cards"),
    (
        "bool-floor",
        _set("cash_accounts", 0, "reserve_floor_minor", value=False),
        "/cash_accounts/0/reserve_floor_minor",
    ),
    ("string-amount", _set("request", "amount_minor", value="1000000"), "/request/amount_minor"),
    ("missing-currency", _delete("request", "currency"), "/request"),
    ("missing-fee-rate", _delete("cards", 0, "fee_rate"), "/cards/0"),
    ("missing-workers", _delete("options", "workers"), "/options"),
    ("missing-includes", _delete("snapshots", 0, "includes_event_ids"), "/snapshots/0"),
    ("missing-options", _delete("options"), ""),
    ("extra-top-level", _set("extra", value=1), "/extra"),
    ("extra-daily-cap", _set("cards", 0, "daily_cap_minor", value=0), "/cards/0/daily_cap_minor"),
    ("extra-merchant", _set("request", "merchant", value="shop"), "/request/merchant"),
    (
        "extra-due-member",
        _set("cards", 0, "billing_rule", "due", "days", value=3),
        "/cards/0/billing_rule/due/days",
    ),
    (
        "negative-holds",
        _set("cards", 0, "holds_uncounted_minor", value=-1),
        "/cards/0/holds_uncounted_minor",
    ),
    ("int64-overflow", _set("request", "amount_minor", value=2**63), "/request/amount_minor"),
    ("zero-amount", _set("request", "amount_minor", value=0), "/request/amount_minor"),
    ("impossible-date", _set("request", "txn_date", value="2026-02-30"), "/request/txn_date"),
    ("compact-date", _set("request", "txn_date", value="20261016"), "/request/txn_date"),
    (
        "naive-timestamp",
        _set("snapshots", 0, "observed_at", value="2026-10-16T09:00:00"),
        "/snapshots/0/observed_at",
    ),
    ("protocol-version", _set("protocol_version", value="2"), "/protocol_version"),
    ("unknown-profile", _set("options", "profile", value="max_benefit"), "/options/profile"),
    ("zero-workers", _set("options", "workers", value=0), "/options/workers"),
    ("zero-time-limit", _set("options", "time_limit_s", value=0), "/options/time_limit_s"),
    ("string-time-limit", _set("options", "time_limit_s", value="10"), "/options/time_limit_s"),
    (
        "reserved-event-id",
        _set("events", 0, "event_id", value="plan_repay_A"),
        "/events/0/event_id",
    ),
    ("empty-category", _set("events", 0, "category", value=""), "/events/0/category"),
    ("unknown-cls", _set("events", 0, "cls", value="maybe"), "/events/0/cls"),
    (
        "override-without-change",
        _set("scenarios", 2, "event_overrides", 0, value={"event_id": "e8"}),
        "/scenarios/2/event_overrides/0",
    ),
    ("lowercase-currency", _set("request", "currency", value="cny"), "/request/currency"),
]
ADAPTER_ONLY = [
    ("duplicate-card", _set("cards", 1, "card_id", value="A"), "/cards/1/card_id"),
    ("duplicate-event", _set("events", 1, "event_id", value="e1"), "/events/1/event_id"),
    (
        "duplicate-scenario",
        _set("scenarios", 1, "scenario_id", value="confirmed"),
        "/scenarios/1/scenario_id",
    ),
    ("duplicate-snapshot", _duplicate_snapshot, "/snapshots/1/cash_account_id"),
    (
        "duplicate-pool",
        _set(
            "pools",
            value=[{"pool_id": "p", "available_minor": 1}, {"pool_id": "p", "available_minor": 2}],
        ),
        "/pools/1/pool_id",
    ),
    (
        "currency-mismatch",
        _set("cash_accounts", 0, "currency", value="USD"),
        "/cash_accounts/0/currency",
    ),
    (
        "unknown-repay-account",
        _set("cards", 0, "repay_from_cash_account_id", value="cash-x"),
        "/cards/0/repay_from_cash_account_id",
    ),
    (
        "unknown-event-account",
        _set("events", 0, "cash_account_id", value="cash-x"),
        "/events/0/cash_account_id",
    ),
    (
        "unknown-snapshot-account",
        _set("snapshots", 0, "cash_account_id", value="cash-x"),
        "/snapshots/0/cash_account_id",
    ),
    (
        "includes-unknown-event",
        _set("snapshots", 0, "includes_event_ids", value=["e99"]),
        "/snapshots/0/includes_event_ids/0",
    ),
    (
        "includes-other-accounts-event",
        _other_accounts_event_included,
        "/snapshots/0/includes_event_ids/0",
    ),
    (
        "override-unknown-event",
        _set("scenarios", 2, "event_overrides", 0, "event_id", value="e99"),
        "/scenarios/2/event_overrides/0/event_id",
    ),
    (
        "override-twice",
        _append("scenarios", 2, "event_overrides", value={"event_id": "e8", "amount_minor": 1}),
        "/scenarios/2/event_overrides/1/event_id",
    ),
    (
        "posting-delay-inverted",
        _set("cards", 0, "posting_delay_min_days", value=3),
        "/cards/0/posting_delay_max_days",
    ),
]


def test_the_unmodified_document_is_valid(
    runner: ModuleType, registry: Registry, plan_input: Doc
) -> None:
    assert runner.schema_errors(registry, SCHEMA, plan_input) == []
    inputs_from_protocol(plan_input)


@pytest.mark.parametrize(("mutate", "pointer"), [c[1:] for c in BOTH], ids=[c[0] for c in BOTH])
def test_schema_and_adapter_both_reject(
    runner: ModuleType, registry: Registry, plan_input: Doc, mutate: Mutation, pointer: str
) -> None:
    mutate(plan_input)
    assert runner.schema_errors(registry, SCHEMA, plan_input) != []
    with pytest.raises(ProtocolError) as caught:
        inputs_from_protocol(plan_input)
    assert caught.value.path.startswith(pointer), caught.value


@pytest.mark.parametrize(
    ("mutate", "pointer"), [c[1:] for c in ADAPTER_ONLY], ids=[c[0] for c in ADAPTER_ONLY]
)
def test_rules_beyond_json_schema_are_enforced_by_the_adapter(
    runner: ModuleType, registry: Registry, plan_input: Doc, mutate: Mutation, pointer: str
) -> None:
    mutate(plan_input)
    assert runner.schema_errors(registry, SCHEMA, plan_input) == []  # not expressible
    with pytest.raises(ProtocolError) as caught:
        inputs_from_protocol(plan_input)
    assert caught.value.path == pointer, caught.value


def test_standard_json_schema_admits_an_integral_float_so_the_runner_is_stricter(
    runner: ModuleType, registry: Registry, plan_input: Doc
) -> None:
    plan_input["request"]["amount_minor"] = 1000000.0
    standard = Draft202012Validator(
        {"$ref": runner.SCHEMA_BASE + SCHEMA}, registry=registry, format_checker=FormatChecker()
    )
    assert list(standard.iter_errors(plan_input)) == []  # JSON Schema: 1.0 is an integer
    assert runner.schema_errors(registry, SCHEMA, plan_input) != []  # protocol v1: it is not
    assert runner.find_floats({"input": plan_input}) == ["/input/request/amount_minor"]
