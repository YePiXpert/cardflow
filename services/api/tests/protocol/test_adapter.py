"""The stdlib-only protocol adapter ``cardflow.planner.engine.protocol`` (T-004, A.4/A.6).

* round trip PlanInput -> engine -> PlanInput is lossless, and the engine inputs equal those of
  the T-003 hand-written-fixture loader;
* running F-18 through the adapter and through the T-003 loader gives the same outcome, field
  by field (every profile x every decision scenario);
* outcome documents of every business status validate against ``PlanOutcome.schema.json``;
* canonical JSON / ``protocol_input_hash`` follow the documented rules (the F-18 hash is pinned
  for the Dart port), and strict JSON parsing rejects what JSON allows but v1 does not;
* the adapter does not pull JSON Schema (or any non-stdlib package) into the engine.
"""

import hashlib
import json
import subprocess
import sys
import uuid
from dataclasses import replace
from datetime import date
from types import ModuleType
from typing import Any

import pytest
from referencing import Registry

import cardflow.planner.engine.plan as plan_module
from cardflow.planner.engine.allocation import SolveResult, TierResult
from cardflow.planner.engine.fixture import load_fixture
from cardflow.planner.engine.plan import plan
from cardflow.planner.engine.protocol import (
    ProtocolError,
    canonical_json,
    inputs_from_protocol,
    inputs_to_protocol,
    outcome_to_protocol,
    parse_json,
    plan_from_protocol,
    protocol_input_hash,
    verify_from_protocol,
)

type Doc = dict[str, Any]

# protocol_input_hash of the F-18 PlanInput (fixture input, options cash_safety / baseline).
# The Dart port (T-022) must reproduce this value from the same document.
F18_INPUT_HASH = "ea990327f08b42d476fa157d9bb8ddff6a1d8eb4e41ff60b1e498c5861a91ee8"
PROFILES = ("cash_safety", "verified_benefit", "fewer_cards")
DECISIONS = ("baseline", "confirmed", "stress_income_delay")
VOLATILE = ("run_id", "created_at", "wall_time_s", "input_hash")


def _stable(outcome: Doc) -> Doc:
    """An outcome without per-run values (ids, clock times, input hash)."""
    out = {k: v for k, v in outcome.items() if k not in VOLATILE}
    out["tiers"] = [{k: v for k, v in t.items() if k != "wall_time_s"} for t in out["tiers"]]
    return out


def _with_options(doc: Doc, profile: str, decision: str) -> Doc:
    out = json.loads(json.dumps(doc))
    out["options"]["profile"] = profile
    out["options"]["decision_scenario"] = decision
    return out


@pytest.fixture(scope="module")
def legacy(paths: Any) -> tuple[Any, Any, Any]:  # noqa: ANN401
    return load_fixture(paths.legacy_fixture)


# --- round trip and the T-003 loader --------------------------------------------------------


def test_round_trip_is_lossless(plan_input: Doc) -> None:
    inputs, scenarios, options = inputs_from_protocol(plan_input)
    again = inputs_to_protocol(inputs, scenarios, options)
    assert again == plan_input
    assert inputs_from_protocol(again) == (inputs, scenarios, options)


def test_engine_inputs_equal_those_of_the_t003_loader(
    plan_input: Doc,
    legacy: tuple[Any, Any, Any],
) -> None:
    inputs, scenarios, options = inputs_from_protocol(plan_input)
    legacy_inputs, legacy_scenarios, raw = legacy
    assert inputs == legacy_inputs
    assert scenarios == legacy_scenarios
    assert list(scenarios) == list(legacy_scenarios)  # same order (outputs follow it)
    assert inputs.input_hash() == legacy_inputs.input_hash()
    assert options.decision_scenario == raw["decision_scenario"]


def test_defaults_of_optional_members(plan_input: Doc) -> None:
    del plan_input["cards"][0]["name"]
    del plan_input["cash_accounts"][0]["name"]
    del plan_input["events"][0]["label"]
    del plan_input["scenarios"][0]["description"]
    for card in plan_input["cards"]:
        del card["billing_rule"]["source"], card["billing_rule"]["status"]
    inputs, scenarios, _ = inputs_from_protocol(plan_input)
    assert inputs.cards[0].name == "A"
    assert inputs.accounts[0].name == "cash-main"
    assert inputs.events[0].label == ""
    assert scenarios["confirmed"].description == ""
    assert {c.billing_rule.source for c in inputs.cards} == {""}
    assert {c.billing_rule.status for c in inputs.cards} == {"user_declared"}
    assert inputs.cards[0].pool_id is None
    assert inputs.snapshots["cash-main"].observed_at is None


@pytest.mark.parametrize("decision", DECISIONS)
@pytest.mark.parametrize("profile", PROFILES)
def test_adapter_and_t003_loader_runs_agree_field_by_field(
    plan_input: Doc,
    legacy: tuple[Any, Any, Any],
    profile: str,
    decision: str,
) -> None:
    doc = _with_options(plan_input, profile, decision)
    via_protocol = plan_from_protocol(doc)
    legacy_inputs, legacy_scenarios, _ = legacy
    via_loader = outcome_to_protocol(
        plan(legacy_inputs, legacy_scenarios, decision, profile, 10, 7, workers=8, seed=0)
    )
    assert _stable(via_protocol) == _stable(via_loader)
    # the two hashes differ by design: language-neutral document hash vs engine hash; since
    # model 1.1.0 the engine's default covers scenarios and options too (T-004c, R3E-15)
    from cardflow.planner.engine.plan import run_input_hash

    assert via_protocol["input_hash"] == protocol_input_hash(doc)
    assert via_loader["input_hash"] == run_input_hash(
        legacy_inputs, legacy_scenarios, decision, profile, 10, 7, 8, 0
    )


# --- outcome documents ----------------------------------------------------------------------


def _outcome_errors(runner: ModuleType, registry: Registry, outcome: Doc) -> list[str]:
    return runner.schema_errors(registry, "PlanOutcome.schema.json", outcome)


def test_outcomes_of_every_business_status_validate(
    runner: ModuleType,
    registry: Registry,
    plan_input: Doc,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    seen = {}

    def record(doc: Doc) -> Doc:
        outcome = plan_from_protocol(doc)
        assert _outcome_errors(runner, registry, outcome) == [], outcome["business_status"]
        seen[outcome["business_status"]] = outcome
        return outcome

    record(plan_input)  # CONDITIONALLY_FEASIBLE
    record(_with_options(plan_input, "cash_safety", "confirmed"))  # BASELINE_SHORTFALL
    record(_with_options(plan_input, "cash_safety", "stress_income_delay"))  # INFEASIBLE
    stale = json.loads(json.dumps(plan_input))
    stale["request"]["txn_date"] = "2026-10-30"
    record(stale)  # NEEDS_DATA
    unknown_decision = _with_options(plan_input, "cash_safety", "nope")
    record(unknown_decision)  # NEEDS_DATA (UNKNOWN_DECISION_SCENARIO)
    no_card = json.loads(json.dumps(plan_input))
    for card in no_card["cards"]:
        card["status_ok"] = False
    no_card_outcome = record(no_card)  # INFEASIBLE: every card excluded before modelling
    assert no_card_outcome["business_status"] == "INFEASIBLE"
    assert no_card_outcome["solver_status"] == "NOT_RUN"
    assert {r["reason"] for r in no_card_outcome["rejections"]} == {"CARD_STATUS"}
    rich = json.loads(json.dumps(plan_input))
    rich["snapshots"][0]["balance_minor"] = 5000000
    record(rich)  # FEASIBLE_ROBUST

    # UNKNOWN and a verifier-rejected solution cannot be produced on demand by CP-SAT on this
    # small model; the solver's / verifier's answer is replaced here to exercise the MAPPING.
    real_solve, real_verify = plan_module.solve, plan_module.verify

    def unknown_solve(*args: Any, **kwargs: Any) -> SolveResult:  # noqa: ANN401
        res = real_solve(*args, **kwargs)
        tier = TierResult("min_margin", "max", "UNKNOWN", None, None, 0.01)
        return replace(res, status="UNKNOWN", allocation={}, tiers=[tier], proven_optimal=False)

    monkeypatch.setattr(plan_module, "solve", unknown_solve)
    record(plan_input)  # UNKNOWN
    monkeypatch.setattr(plan_module, "solve", real_solve)

    def rejecting_verify(*args: Any, **kwargs: Any) -> Any:  # noqa: ANN401
        ver = real_verify(*args, **kwargs)
        return replace(ver, ok=False, structural_ok=False, violations=["injected by the test"])

    monkeypatch.setattr(plan_module, "verify", rejecting_verify)
    record(plan_input)  # MODEL_INVALID (VERIFIER_REJECTED_SOLVER_SOLUTION)
    assert "VERIFIER_REJECTED_SOLVER_SOLUTION" in seen["MODEL_INVALID"]["notes"]
    assert set(seen) == {
        "CONDITIONALLY_FEASIBLE",
        "BASELINE_SHORTFALL",
        "INFEASIBLE",
        "NEEDS_DATA",
        "MODEL_INVALID",
        "FEASIBLE_ROBUST",
        "UNKNOWN",
    }
    assert seen["UNKNOWN"]["solver_status"] == "UNKNOWN"
    assert seen["BASELINE_SHORTFALL"]["solver_status"] == "NOT_RUN"
    assert seen["BASELINE_SHORTFALL"]["wall_time_s"] is None


def test_f18_outcome_matches_api_52(plan_input: Doc) -> None:
    run_id = str(uuid.uuid4())
    out = plan_from_protocol(plan_input, run_id=run_id)
    assert out["protocol_version"] == "1"
    assert out["run_id"] == run_id
    assert out["input_hash"] == F18_INPUT_HASH
    assert (out["solver_status"], out["business_status"]) == ("OPTIMAL", "CONDITIONALLY_FEASIBLE")
    assert (out["time_limit_s"], out["workers"], out["seed"]) == (10, 8, 0)
    first = out["allocation"][0]
    assert {k: first[k] for k in ("card_id", "amount_minor", "statement_date", "due_date")} == {
        "card_id": "A",
        "amount_minor": 800000,
        "statement_date": "2026-11-10",
        "due_date": "2026-11-28",
    }
    assert first["repay_on"] == "2026-11-28"
    assert first["repay_from_cash_account_id"] == "cash-main"
    assert first["buffer_days"] == 43
    assert first["cycle_assumptions"] == ["posting delay 0d -> posting 2026-10-16"]
    assert out["verification"]["weighted_buffer_days"] == "42.4"
    assert out["verification"]["checks"]["baseline"]["min_balance_by_account"] == {
        "cash-main": 300000
    }
    assert out["failing_scenarios"] == ["confirmed", "stress_income_delay"]
    assert out["rejections"][0]["card_id"] == "B"
    assert out["rejections"][0]["reason"] == "CASH_BREACH_ALONE"
    assert out["rejections"][0]["first_breach"]["on"] == "2026-11-08"
    assert out["rejections"][0]["first_breach"]["balance"] == -350000
    shift = out["sensitivity"]["stress_income_delay"]["first_feasible_date_shift"]
    assert shift == {"shift_days": 5, "txn_date": "2026-10-21", "status": "OPTIMAL"}


def test_verify_from_protocol_reports_an_unknown_card(
    runner: ModuleType, registry: Registry, plan_input: Doc
) -> None:
    result = verify_from_protocol(
        plan_input, [{"card_id": "Z", "amount_minor": 1000000}], "baseline"
    )
    assert (
        runner.schema_errors(registry, "PlanOutcome.schema.json#/$defs/VerificationResult", result)
        == []
    )
    assert result["verification"]["ok"] is False
    assert result["verification"]["violations"][0].startswith("UNKNOWN_CARD")
    assert result["allocation"] == []


def test_verify_from_protocol_rejects_invalid_requests(plan_input: Doc) -> None:
    alloc = [{"card_id": "A", "amount_minor": 1000000}]
    with pytest.raises(ProtocolError, match="unknown scenario"):
        verify_from_protocol(plan_input, alloc, "nope")
    with pytest.raises(ProtocolError, match="duplicate card_id"):
        verify_from_protocol(plan_input, alloc + alloc, "baseline")
    with pytest.raises(ProtocolError, match="expected an integer"):
        verify_from_protocol(plan_input, [{"card_id": "A", "amount_minor": 1e6}], "baseline")


# --- canonical JSON and the input hash ------------------------------------------------------


def test_f18_input_hash_is_pinned(plan_input: Doc) -> None:
    assert protocol_input_hash(plan_input) == F18_INPUT_HASH
    expected = hashlib.sha256(canonical_json(plan_input)).hexdigest()
    assert protocol_input_hash(plan_input) == expected


def test_without_float_tokens_canonical_json_equals_sorted_compact_json_dumps(
    plan_input: Doc,
) -> None:
    compact = json.dumps(plan_input, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    assert canonical_json(plan_input) == compact.encode("utf-8")


def test_hash_ignores_member_order_and_whitespace_but_not_values(plan_input: Doc) -> None:
    reordered = json.loads(json.dumps(plan_input, sort_keys=True))
    reordered = dict(reversed(list(reordered.items())))
    pretty = json.loads(json.dumps(plan_input, indent=4))
    assert protocol_input_hash(reordered) == protocol_input_hash(pretty) == F18_INPUT_HASH
    changed = json.loads(json.dumps(plan_input))
    changed["request"]["amount_minor"] += 1
    assert protocol_input_hash(changed) != F18_INPUT_HASH
    swapped = json.loads(json.dumps(plan_input))
    swapped["cards"].reverse()  # array order is significant
    assert protocol_input_hash(swapped) != F18_INPUT_HASH


@pytest.mark.parametrize(
    ("value", "expected"),
    [
        ({"b": 1, "a": [True, False, None]}, '{"a":[true,false,null],"b":1}'),
        ({"金额": "卡A", "z": "€"}, '{"z":"€","金额":"卡A"}'),
        ('"\\/\b\f\n\r\t\x00\x1f\x7f\u2028', '"\\"\\\\/\\b\\f\\n\\r\\t\\u0000\\u001f\x7f\u2028"'),
        ({"\U0001f600": 1, "\ufb01": 2}, '{"\U0001f600":1,"\ufb01":2}'),  # UTF-16 order
        (2**63 - 1, "9223372036854775807"),
        (-(2**63), "-9223372036854775808"),
        (10**30, "1000000000000000000000000000000"),
        (10.0, "10"),
        (0.5, "0.5"),
        (-0.0, "0"),
        (1e-6, "0.000001"),
        (1e-7, "1e-7"),
        (1e21, "1e+21"),
        (1e20, "100000000000000000000"),
        (123.456, "123.456"),
        (5e-324, "5e-324"),
        (1.7976931348623157e308, "1.7976931348623157e+308"),
        (2.0**68, "295147905179352830000"),
        (9.999999999999997e22, "9.999999999999997e+22"),
        (1e23, "1e+23"),
        (9.999999999999997e-7, "9.999999999999997e-7"),
        (333333333.3333333, "333333333.3333333"),
        (999999999999999900000.0, "999999999999999900000"),
    ],
)
def test_canonical_json_serialisation(value: object, expected: str) -> None:
    assert canonical_json(value) == expected.encode("utf-8")


@pytest.mark.parametrize(
    "value",
    [float("nan"), float("inf"), {"a": float("-inf")}, "\ud800", {1: "x"}, date(2026, 1, 1)],
    ids=["nan", "inf", "nested-inf", "lone-surrogate", "int-key", "date"],
)
def test_canonical_json_rejects_non_json(value: object) -> None:
    with pytest.raises(ProtocolError):
        canonical_json(value)


@pytest.mark.parametrize(
    "text",
    [
        b'{"a": 1, "a": 2}',
        b'{"a": NaN}',
        b'{"a": Infinity}',
        b'{"a": -Infinity}',
        b'{"a": 1e400}',
        b'\xef\xbb\xbf{"a": 1}',
        b'{"a": "\xff"}',
        b'{"a": 1',
        b'{"a": ' + b"9" * 5000 + b"}",
        b"[" * 100000 + b"]" * 100000,
    ],
    ids=[
        "duplicate-key",
        "nan",
        "infinity",
        "minus-infinity",
        "overflow",
        "bom",
        "not-utf8",
        "eof",
        "integer-literal-too-long",
        "nested-too-deeply",
    ],
)
def test_parse_json_is_strict(text: bytes) -> None:
    with pytest.raises(ProtocolError):
        parse_json(text)


def test_parse_json_keeps_integers_exact() -> None:
    assert parse_json(b'{"a": 9223372036854775807, "b": -1}') == {"a": 2**63 - 1, "b": -1}


# --- dependency boundary --------------------------------------------------------------------


def test_the_adapter_imports_no_json_schema_library() -> None:
    probe = "import sys, cardflow.planner.engine.protocol\nprint('\\n'.join(sorted(sys.modules)))\n"
    result = subprocess.run(  # noqa: S603 -- fixed argv: this interpreter + a constant probe
        [sys.executable, "-c", probe], capture_output=True, text=True, check=True
    )
    loaded = {name.partition(".")[0] for name in result.stdout.split()}
    assert loaded.isdisjoint({"jsonschema", "referencing", "pydantic", "fastapi", "sqlalchemy"})
