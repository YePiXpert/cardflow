"""Protocol v1 revisions of T-004c (review wave 3, engine-spec §12).

Every test names the review finding it guards (R3E-nn) and was written before its fix
(``evidence/m0/T-004/c2-red.txt``). Schema and adapter must agree on every rule that JSON
Schema can express; rules beyond JSON Schema are adapter-only (Dart must implement them too).
"""

import copy
import json
import re
from dataclasses import replace
from decimal import Decimal
from types import ModuleType
from typing import Any

import pytest
from referencing import Registry

import cardflow.planner.engine.plan as plan_module
from cardflow.planner.engine.protocol import (
    ProtocolError,
    inputs_from_protocol,
    inputs_to_protocol,
    parse_json,
    plan_from_protocol,
    protocol_input_hash,
    verify_from_protocol,
)

type Doc = dict[str, Any]
SCHEMA = "PlanInput.schema.json"
OUTCOME = "PlanOutcome.schema.json"
F18_INPUT_HASH = "ea990327f08b42d476fa157d9bb8ddff6a1d8eb4e41ff60b1e498c5861a91ee8"


def _set(doc: Doc, path: tuple[str | int, ...], value: object) -> Doc:
    out = copy.deepcopy(doc)
    node: Any = out
    for key in path[:-1]:
        node = node[key]
    node[path[-1]] = value
    return out


def _accepted(runner: ModuleType, registry: Registry, doc: Doc) -> tuple[bool, bool]:
    schema_ok = runner.schema_errors(registry, SCHEMA, doc) == []
    try:
        inputs_from_protocol(doc)
    except ProtocolError:
        return schema_ok, False
    return schema_ok, True


def test_the_f18_input_and_its_hash_are_unchanged(plan_input: Doc) -> None:
    """The revisions add no input member: F-18's document and hash stay as pinned (T-022)."""
    assert protocol_input_hash(plan_input) == F18_INPUT_HASH


# --- R3E-02: non-actionable outcomes carry no allocation ------------------------------------


def _rejecting_verify(monkeypatch: pytest.MonkeyPatch) -> None:
    real = plan_module.verify

    def rejecting(*args: Any, **kwargs: Any) -> Any:  # noqa: ANN401
        return replace(real(*args, **kwargs), ok=False, structural_ok=False, violations=["x"])

    monkeypatch.setattr(plan_module, "verify", rejecting)


def test_a_rejected_solution_is_only_in_the_diagnostics_r3e_02(
    runner: ModuleType, registry: Registry, plan_input: Doc, monkeypatch: pytest.MonkeyPatch
) -> None:
    """R3E-02 (§12.1): MODEL_INVALID (verifier rejection) -> allocation [] and verification
    null; the rejected lines and their verification are under diagnostics."""
    _rejecting_verify(monkeypatch)
    out = plan_from_protocol(plan_input)
    assert out["business_status"] == "MODEL_INVALID"
    assert out["allocation"] == []
    assert out["verification"] is None
    diagnostics = out["diagnostics"]
    assert diagnostics["code"] == "VERIFIER_REJECTED_SOLVER_SOLUTION"
    lines = [(a["card_id"], a["amount_minor"]) for a in diagnostics["rejected_allocation"]]
    assert lines == [("A", 800000), ("C", 200000)]
    assert diagnostics["rejected_verification"]["violations"] == ["x"]
    assert runner.schema_errors(registry, OUTCOME, out) == []


def test_the_schema_refuses_an_allocation_outside_actionable_statuses_r3e_02(
    runner: ModuleType, registry: Registry, plan_input: Doc
) -> None:
    """R3E-02: PlanOutcome.schema.json ties allocation/verification/diagnostics to the status."""
    ok = plan_from_protocol(plan_input)
    assert ok["diagnostics"] is None
    assert runner.schema_errors(registry, OUTCOME, ok) == []
    for status in ("MODEL_INVALID", "INFEASIBLE", "UNKNOWN", "NEEDS_DATA", "BASELINE_SHORTFALL"):
        wrong = dict(ok, business_status=status)
        assert runner.schema_errors(registry, OUTCOME, wrong) != [], status
    empty = dict(ok, allocation=[], verification=None)
    assert runner.schema_errors(registry, OUTCOME, empty) != []  # actionable needs a plan
    leaked = dict(ok, diagnostics={"code": "VERIFIER_REJECTED_SOLVER_SOLUTION"})
    assert runner.schema_errors(registry, OUTCOME, leaked) != []


# --- R3E-04: credit-account consistency (adapter-only rules) --------------------------------


def _two_cards_of_one_account(plan_input: Doc) -> Doc:
    doc = copy.deepcopy(plan_input)
    doc["cards"][1]["credit_account_id"] = doc["cards"][0]["credit_account_id"]
    doc["cards"][1]["raw_available_minor"] = doc["cards"][0]["raw_available_minor"]
    return doc


def test_cards_of_one_credit_account_report_one_available_credit_r3e_04(
    runner: ModuleType, registry: Registry, plan_input: Doc
) -> None:
    """R3E-04 (§12.3): cards sharing credit_account_id carry the account's available credit
    (one value) and the same pool; otherwise ProtocolError. Schema cannot express it."""
    doc = _two_cards_of_one_account(plan_input)
    assert _accepted(runner, registry, doc) == (True, True)
    differs = _set(doc, ("cards", 1, "raw_available_minor"), 1)
    assert _accepted(runner, registry, differs) == (True, False)
    with pytest.raises(ProtocolError) as caught:
        inputs_from_protocol(differs)
    assert caught.value.path == "/cards/1/raw_available_minor"
    pooled = _set(doc, ("cards", 1, "pool_id"), "p")
    pooled["pools"] = [{"pool_id": "p", "available_minor": 1}]
    with pytest.raises(ProtocolError) as caught:
        inputs_from_protocol(pooled)
    assert caught.value.path == "/cards/1/pool_id"


# --- R3E-11: canonical rates ----------------------------------------------------------------


@pytest.mark.parametrize(
    ("stored", "text"),
    [
        (Decimal("0.0060000000"), "0.006"),
        (Decimal("0E-10"), "0"),
        (Decimal("1.0000000000"), "1"),
        (Decimal("0.12345"), "0.12345"),
        (Decimal("6E-3"), "0.006"),
    ],
)
def test_numeric_rates_from_the_database_enter_the_protocol_r3e_11(
    plan_input: Doc, stored: Decimal, text: str
) -> None:
    """R3E-11: NUMERIC(20,10) values (ADR-008) are written in the canonical form (no trailing
    zeros, '0' and '1' for the limits), so they are accepted and hash like the plain value."""
    inputs, scenarios, options = inputs_from_protocol(plan_input)
    cards = [replace(inputs.cards[0], fee_rate=stored), *inputs.cards[1:]]
    doc = inputs_to_protocol(replace(inputs, cards=cards), scenarios, options)
    assert doc["cards"][0]["fee_rate"] == text
    plain = inputs_to_protocol(
        replace(inputs, cards=[replace(inputs.cards[0], fee_rate=Decimal(text)), *cards[1:]]),
        scenarios,
        options,
    )
    assert protocol_input_hash(doc) == protocol_input_hash(plain)


@pytest.mark.parametrize(
    ("path", "value"),
    [
        (("cards", 0, "fee_rate"), "0.00600"),
        (("cards", 0, "fee_rate"), "0.0"),
        (("cards", 0, "fee_rate"), "1.0"),
        (("cards", 0, "fee_rate"), "1.00000"),
        (("cards", 0, "fee_rate"), "0."),
        (("scenarios", 0, "income_scale"), "1.0"),
        (("scenarios", 0, "expense_scale"), "10.0000000000"),
        (("scenarios", 0, "expense_scale"), "01"),
    ],
)
def test_only_canonical_rates_and_factors_are_valid_r3e_11(
    runner: ModuleType, registry: Registry, plan_input: Doc, path: tuple[str | int, ...], value: str
) -> None:
    """R3E-11: one value, one text: '0.006' is valid, '0.00600' is not (schema and adapter),
    so equal rates always give equal input hashes."""
    assert _accepted(runner, registry, _set(plan_input, path, value)) == (False, False)


def test_the_engine_hash_of_equal_rates_is_equal_r3e_11(plan_input: Doc) -> None:
    """R3E-11: the engine-internal hashes do not depend on the Decimal's exponent either."""
    from cardflow.planner.engine.plan import run_input_hash

    inputs, scenarios, _ = inputs_from_protocol(plan_input)
    padded = replace(
        inputs,
        cards=[replace(inputs.cards[0], fee_rate=Decimal("0.0060000000")), *inputs.cards[1:]],
    )
    plain = replace(
        inputs, cards=[replace(inputs.cards[0], fee_rate=Decimal("0.006")), *inputs.cards[1:]]
    )
    assert padded.input_hash() == plain.input_hash()
    args = ("baseline", "cash_safety", 10, 7, 8, 0)
    assert run_input_hash(padded, scenarios, *args) == run_input_hash(plain, scenarios, *args)


# --- R3E-12: errors name the path and the rule, never the value -----------------------------

ECHO = [
    (("request", "amount_minor"), 10**14, "100000000000000"),
    (("request", "amount_minor"), "1234567.89", "1234567"),
    (("events", 0, "cls"), 123456789, "123456789"),
    (("options", "profile"), {"balance_minor": 98765432}, "98765432"),
    (("protocol_version",), 31415926, "31415926"),
    (("options", "time_limit_s"), 98765.4321, "98765"),
    (("cards", 0, "card_id"), "6222 0212 3456 7890", "6222"),
    (("request", "currency"), "RMB-12345", "12345"),
    (("cards", 0, "fee_rate"), "0.123456", "123456"),
    (("request", "txn_date"), "2026-02-30", "2026-02-30"),
    (("request", "txn_date"), "1999-99-99", "99-99"),
    (("snapshots", 0, "observed_at"), "2026-10-16T09:00:00+99:00", "99:00"),
    (("cards", 0, "repay_from_cash_account_id"), "acct-998877", "998877"),
    (("snapshots", 0, "includes_event_ids"), ["e77665544"], "77665544"),
    (("scenarios", 2, "event_overrides", 0, "event_id"), "e55443322", "55443322"),
    (("cash_accounts", 0, "currency"), "USD", "USD"),
]


@pytest.mark.parametrize(("path", "value", "secret"), ECHO)
def test_protocol_errors_never_echo_the_value_r3e_12(
    plan_input: Doc, path: tuple[str | int, ...], value: object, secret: str
) -> None:
    """R3E-12: a ProtocolError names the JSON Pointer and the rule broken, no part of the value
    (a full card number in card_id, an amount in an enum field, dates, ids)."""
    with pytest.raises(ProtocolError) as caught:
        inputs_from_protocol(_set(plan_input, path, value))
    assert secret not in str(caught.value), str(caught.value)
    assert caught.value.path.startswith("/")


@pytest.mark.parametrize(
    ("text", "secret"),
    [
        (b'{"6222021234567890": 1, "6222021234567890": 2}', "6222021234567890"),
        (b'{"a": "\xff\xfe9876"}', "9876"),
        (b'{"a": 1e999999}', "999999"),
    ],
    ids=["duplicate-key", "not-utf8", "overflow"],
)
def test_strict_json_errors_never_echo_the_value_r3e_12(text: bytes, secret: str) -> None:
    """R3E-12: the strict reader's errors do not quote keys, bytes or numbers either."""
    with pytest.raises(ProtocolError) as caught:
        parse_json(text)
    assert secret not in str(caught.value)


# --- R3E-13: the solver-free verifier never raises for a valid document ---------------------


@pytest.mark.parametrize(
    ("mutate", "code"),
    [
        (lambda d: d.update(snapshots=[]), "MISSING_SNAPSHOT"),
        (
            lambda d: d["cards"][0]["billing_rule"].update(holiday_rollover="next_business_day"),
            "BILLING_RULE_INVALID",
        ),
        (lambda d: d["cards"][0].update(pool_id="p1"), "MISSING_POOL_SNAPSHOT"),
        (lambda d: d["request"].update(txn_date="2026-10-30"), "STALE_SNAPSHOT"),
    ],
    ids=["missing-snapshot", "needs-calendar", "missing-pool", "stale"],
)
def test_verify_reports_needs_data_instead_of_raising_r3e_13(
    runner: ModuleType,
    registry: Registry,
    plan_input: Doc,
    mutate: Any,  # noqa: ANN401
    code: str,
) -> None:
    """R3E-13: documents the protocol accepts but plan() answers with NEEDS_DATA give a
    structured result on the verifier path too (the review saw LookupError / ValueError)."""
    mutate(plan_input)
    alloc = [{"card_id": "A", "amount_minor": 800000}, {"card_id": "C", "amount_minor": 200000}]
    result = verify_from_protocol(plan_input, alloc, "baseline")
    assert code in [i["code"] for i in result["data_issues"]]
    assert result["verification"] is None
    assert result["allocation"] == []
    ref = f"{OUTCOME}#/$defs/VerificationResult"
    assert runner.schema_errors(registry, ref, result) == []
    assert plan_from_protocol(plan_input)["business_status"] == "NEEDS_DATA"


def test_a_verify_case_on_such_a_document_runs_in_the_fixture_runner_r3e_13(
    runner: ModuleType,
    v1_fixture_doc: Doc,
    tmp_path: Any,  # noqa: ANN401
) -> None:
    """R3E-13: the runner evaluates the case instead of exiting with a traceback."""
    doc = copy.deepcopy(v1_fixture_doc)
    doc["input"]["cards"][0]["billing_rule"]["holiday_rollover"] = "next_business_day"
    doc["expected"] = [
        {
            "name": "verify_needs_data",
            "kind": "verify",
            "allocation": [{"card_id": "A", "amount_minor": 1000000}],
            "decision_scenario": "baseline",
            "assertions": [
                {"path": "/data_issues/0/code", "equals": "BILLING_RULE_INVALID"},
                {"path": "/verification", "equals": None},
            ],
        }
    ]
    path = tmp_path / "needs_data.v1.json"
    path.write_text(json.dumps(doc), encoding="utf-8")
    lines: list[str] = []
    assert runner.main([str(path)], emit=lines.append) == runner.PASSED, "\n".join(lines)


# --- R3E-14: snapshot inclusion and timestamps ----------------------------------------------


def test_includes_may_only_list_events_up_to_the_snapshot_day_r3e_14(
    runner: ModuleType, registry: Registry, plan_input: Doc
) -> None:
    """R3E-14 (§12.2): a balance cannot already contain an event dated after as_of."""
    later = _set(plan_input, ("snapshots", 0, "includes_event_ids"), ["e1"])  # e1: 10-27
    assert _accepted(runner, registry, later) == (True, False)
    with pytest.raises(ProtocolError) as caught:
        inputs_from_protocol(later)
    assert caught.value.path == "/snapshots/0/includes_event_ids/0"
    earlier = _set(later, ("events", 0, "on"), "2026-10-15")
    assert _accepted(runner, registry, earlier) == (True, True)
    same_day = _set(later, ("events", 0, "on"), "2026-10-16")
    assert _accepted(runner, registry, same_day) == (True, True)


@pytest.mark.parametrize(
    ("at", "accepted"),
    [
        ("2026-10-27T09:00:00+08:00", True),
        ("2026-10-27T23:30:00-05:00", True),  # 10-28 in UTC: the event's own offset counts
        ("2026-10-26T23:30:00Z", False),
        ("2026-10-28T00:00:00+08:00", False),
    ],
)
def test_a_timestamp_lies_on_the_events_date_r3e_14(
    runner: ModuleType, registry: Registry, plan_input: Doc, at: str, accepted: bool
) -> None:
    """R3E-14: 'at' (in its own offset) must fall on 'on' (event e1 is dated 2026-10-27)."""
    doc = _set(plan_input, ("events", 0, "at"), at)
    assert _accepted(runner, registry, doc) == (True, accepted)
    if not accepted:
        with pytest.raises(ProtocolError) as caught:
            inputs_from_protocol(doc)
        assert caught.value.path == "/events/0/at"


# --- R3E-18: schema texts -------------------------------------------------------------------


def test_outcome_schema_documents_the_corrected_semantics_r3e_18(paths: Any) -> None:  # noqa: ANN401
    """R3E-18: solver_status NOT_RUN covers INFEASIBLE without an eligible card; the new
    rejection reasons and the diagnostics member are in the schema."""
    schema = json.loads((paths.schema_dir / OUTCOME).read_text(encoding="utf-8"))
    description = schema["properties"]["solver_status"]["description"]
    assert "INFEASIBLE" in description
    assert "eligible" in description
    assert "rejected allocation for diagnosis" not in schema["description"]
    reasons = schema["$defs"]["Rejection"]["properties"]["reason"]["enum"]
    assert {"REPAY_AFTER_HORIZON", "MIN_SPLIT_ABOVE_AMOUNT", "NOT_COMPARED"} <= set(reasons)
    assert "diagnostics" in schema["required"]
    assert "global_breaches" in schema["$defs"]["BaselineCheck"]["required"]


# --- R3E-20: timestamps -- schema (with the runner's format checker) and adapter agree -------


@pytest.mark.parametrize(
    ("value", "accepted"),
    [
        ("2026-10-16T09:00:00+08:00", True),
        ("2026-10-16T23:59:59.999999Z", True),
        ("2026-10-16T09:00:00+23:59", True),
        ("2026-10-16T23:59:60Z", False),
        ("2026-10-16T24:00:00Z", False),
        ("2026-10-16T99:99:99+99:99", False),
        ("2026-02-30T09:00:00Z", False),
        ("2026-10-16T09:00:00+24:00", False),
        ("2026-10-16T09:60:00Z", False),
        ("2026-10-16T09:00:00.1234567Z", False),
        ("2026-10-16t09:00:00z", False),
        ("2026-13-01T09:00:00Z", False),
    ],
)
def test_schema_and_adapter_agree_on_timestamps_r3e_20(
    runner: ModuleType, registry: Registry, plan_input: Doc, value: str, accepted: bool
) -> None:
    """R3E-20: the Timestamp pattern is tight (hours 00-23, minutes/seconds 00-59, offsets up
    to 23:59) and the runner checks the 'date-time' format with the standard library, so the
    schema accepts exactly what the adapter accepts."""
    doc = _set(plan_input, ("snapshots", 0, "observed_at"), value)
    assert _accepted(runner, registry, doc) == (accepted, accepted)


def test_the_runner_checks_the_date_time_format_r3e_20(runner: ModuleType) -> None:
    """R3E-20: 'date-time' is checked even without the optional rfc3339-validator package."""
    assert "date-time" in runner.FORMAT_CHECKER.checkers
    assert not runner.FORMAT_CHECKER.conforms("2026-02-30T09:00:00Z", "date-time")
    assert runner.FORMAT_CHECKER.conforms("2026-02-28T09:00:00Z", "date-time")


# --- R3E-21 / R3E-22: Dart-relevant rules, stated and tested ---------------------------------


@pytest.mark.parametrize(("count", "accepted"), [(1000, True), (1001, False)])
def test_text_length_counts_code_points_r3e_21(
    runner: ModuleType, registry: Registry, plan_input: Doc, count: int, accepted: bool
) -> None:
    """R3E-21: maxLength 1000 counts Unicode code points (an emoji is one, although it is two
    UTF-16 code units -- Dart must use runes.length, not String.length)."""
    doc = _set(plan_input, ("events", 0, "label"), "\U0001f600" * count)
    assert _accepted(runner, registry, doc) == (accepted, accepted)


def test_readme_states_the_dart_rules_r3e_21_r3e_22(paths: Any) -> None:  # noqa: ANN401
    """R3E-21/R3E-22: the README tells the Dart port how to count text and that an integral
    float such as 1000000.0 is not an integer."""
    readme = (paths.protocol_root / "README.md").read_text(encoding="utf-8")
    assert "runes.length" in readme
    assert re.search(r"1000000\.0", readme)
    assert "T-004c" in readme
