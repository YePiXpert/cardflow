"""The v1 JSON Schema files themselves (T-004).

* every file is a valid Draft 2020-12 schema whose ``$id`` matches its file name, and every
  ``$ref`` resolves inside the set (no network);
* every object schema is closed (``additionalProperties: false``); maps (keyed by an id) have
  ``propertyNames`` and a value schema instead;
* "no float money" guard: ``"type": "number"`` appears only on the whitelisted timing fields;
  money fields reference the integer int64 minor-unit definitions and rates/factors the decimal
  string definition.

Each guard is also run against a deliberately broken copy (negative control).
"""

import copy
import json
from collections.abc import Iterator
from pathlib import Path
from typing import Any

import pytest
from jsonschema import Draft202012Validator
from referencing import Registry

SCHEMA_BASE = "https://rules-protocol.cardflow.invalid/v1/"
EXPECTED_FILES = {
    "common.schema.json",
    "BillingRule.schema.json",
    "Snapshot.schema.json",
    "CashEvent.schema.json",
    "CashAccount.schema.json",
    "Scenario.schema.json",
    "PlanRequest.schema.json",
    "CardOption.schema.json",
    "Pools.schema.json",
    "Options.schema.json",
    "PlanInput.schema.json",
    "PlanOutcome.schema.json",
    "Fixture.schema.json",
}
# The ONLY places where a JSON number that is not an integer may appear: timing fields.
NUMBER_WHITELIST = {
    ("Options.schema.json", "time_limit_s"),
    ("PlanOutcome.schema.json", "time_limit_s"),
    ("PlanOutcome.schema.json", "wall_time_s"),
}
# Input money: the supported range |v| <= 10^13 (T-004b); result money (sums): int64.
INPUT_MONEY_DEFS = {"MinorAmount", "NonNegativeMinorAmount", "PositiveMinorAmount"}
RESULT_MONEY_DEFS = {
    "ResultMinorAmount",
    "NonNegativeResultMinorAmount",
    "PositiveResultMinorAmount",
}
MONEY_DEFS = INPUT_MONEY_DEFS | RESULT_MONEY_DEFS
MONEY_LIMIT = 10**13
INT64_MIN, INT64_MAX = -(2**63), 2**63 - 1
OUTPUT_FILE = "PlanOutcome.schema.json"
# Output members that are money but keep the engine's names (API-52); *_minor are inputs and
# allocation lines.
OUTPUT_MONEY = {
    "balance",
    "gap_to_zero",
    "gap_to_reserve",
    "min_balance",
    "end_balance",
    "total",
    "gap",
    "fees",
    "verified_benefit",
    "potential_benefit",
    "capacity",
    "amount",
    "min_balance_by_account",
    "end_balance_by_account",
    "extra_cash_by_account",
}

type Schemas = dict[str, dict[str, Any]]
type Node = tuple[str, str, dict[str, Any]]  # (file, JSON pointer, schema node)


@pytest.fixture(scope="module")
def schemas(paths: Any) -> Schemas:  # noqa: ANN401 -- conftest.ProtocolPaths
    return {
        p.name: json.loads(p.read_text(encoding="utf-8"))
        for p in sorted(Path(paths.schema_dir).glob("*.json"))
    }


def walk(schemas: Schemas) -> Iterator[Node]:
    """Every JSON object inside the schema files, with its pointer."""

    def visit(file: str, pointer: str, node: object) -> Iterator[Node]:
        if isinstance(node, dict):
            yield file, pointer, node
            for key, value in node.items():
                yield from visit(file, f"{pointer}/{key}", value)
        elif isinstance(node, list):
            for i, value in enumerate(node):
                yield from visit(file, f"{pointer}/{i}", value)

    for file, schema in schemas.items():
        yield from visit(file, "", schema)


def _types(node: dict[str, Any]) -> set[str]:
    declared = node.get("type")
    if isinstance(declared, str):
        return {declared}
    if isinstance(declared, list):
        return {t for t in declared if isinstance(t, str)}
    return set()


def _property_name(pointer: str) -> str | None:
    parts = pointer.split("/")
    return parts[-1] if len(parts) > 1 and parts[-2] == "properties" else None


def number_violations(schemas: Schemas) -> list[str]:
    """``number`` outside the whitelist (by file and property name)."""
    found = []
    for file, pointer, node in walk(schemas):
        if "number" in _types(node) and (file, _property_name(pointer)) not in NUMBER_WHITELIST:
            found.append(f"{file}#{pointer}: 'number' outside the timing whitelist")
        if node.get("format") in {"float", "double", "decimal"}:
            found.append(f"{file}#{pointer}: floating format {node['format']!r}")
    return found


def number_occurrences(schemas: Schemas) -> list[str]:
    return [
        f"{file}#{pointer}" for file, pointer, node in walk(schemas) if "number" in _types(node)
    ]


# Keywords whose subschema only adds conditions to an object its parent already closes (it
# cannot open it: the parent's additionalProperties still applies). Nested object schemas
# inside them are checked like any other (T-004c: PlanOutcome ties allocation to the status).
CONDITIONAL = {"if", "then", "else"}


def _is_condition(pointer: str) -> bool:
    parts = pointer.split("/")
    return parts[-1] in CONDITIONAL and (len(parts) < 2 or parts[-2] != "properties")


def open_object_violations(schemas: Schemas) -> list[str]:
    found = []
    for file, pointer, node in walk(schemas):
        if _is_condition(pointer):
            continue
        if "object" not in _types(node) and not isinstance(node.get("properties"), dict):
            continue
        extra = node.get("additionalProperties")
        if "patternProperties" in node or "unevaluatedProperties" in node:
            found.append(f"{file}#{pointer}: patternProperties/unevaluatedProperties")
        elif extra is False:
            continue
        elif isinstance(extra, dict) and "propertyNames" in node and "properties" not in node:
            continue  # a map: constrained keys and values
        else:
            found.append(f"{file}#{pointer}: object without additionalProperties: false")
    return found


def _ref_target(node: dict[str, Any]) -> str | None:
    ref = node.get("$ref")
    return ref.rsplit("/", 1)[-1] if isinstance(ref, str) and "#/$defs/" in ref else None


def money_violations(schemas: Schemas) -> list[str]:
    found = []
    common = schemas["common.schema.json"]["$defs"]
    for name in sorted(MONEY_DEFS):
        d = common[name]
        low, high = d.get("minimum", INT64_MIN - 1), d.get("maximum", INT64_MAX + 1)
        lo, hi = (-MONEY_LIMIT, MONEY_LIMIT) if name in INPUT_MONEY_DEFS else (INT64_MIN, INT64_MAX)
        if d.get("type") != "integer" or not (lo <= low and high <= hi):
            found.append(f"common.schema.json#/$defs/{name}: not an integer within [{lo}, {hi}]")
    for file, pointer, node in walk(schemas):
        name = _property_name(pointer)
        if name is None:
            continue
        target = _ref_target(node)
        value_target = (
            _ref_target(node["additionalProperties"])
            if isinstance(node.get("additionalProperties"), dict)
            else None
        )
        expected = RESULT_MONEY_DEFS if file == OUTPUT_FILE else INPUT_MONEY_DEFS
        if (name.endswith("_minor") or name in OUTPUT_MONEY) and expected.isdisjoint(
            {target, value_target}
        ):
            found.append(f"{file}#{pointer}: money member {name!r} is not a minor-unit integer")
        if "rate" in name and target != "Rate":
            found.append(f"{file}#{pointer}: rate {name!r} is not a Rate decimal string")
        if name.endswith("_scale") and target != "ScaleFactor":
            found.append(f"{file}#{pointer}: factor {name!r} is not a ScaleFactor decimal string")
    return found


# --- tests ---------------------------------------------------------------------------------


def test_the_schema_set_is_complete(schemas: Schemas) -> None:
    assert set(schemas) == EXPECTED_FILES


def test_every_schema_is_valid_draft_2020_12_with_a_matching_id(schemas: Schemas) -> None:
    for file, schema in schemas.items():
        Draft202012Validator.check_schema(schema)
        assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema", file
        assert schema["$id"] == SCHEMA_BASE + file


def test_every_ref_resolves_inside_the_set(schemas: Schemas, registry: Registry) -> None:
    refs = 0
    for file, _, node in walk(schemas):
        ref = node.get("$ref")
        if isinstance(ref, str):
            registry.resolver(base_uri=SCHEMA_BASE + file).lookup(ref)
            refs += 1
    assert refs > 100


def test_object_schemas_are_closed(schemas: Schemas) -> None:
    assert open_object_violations(schemas) == []


def test_no_number_type_outside_the_timing_whitelist(schemas: Schemas) -> None:
    assert number_violations(schemas) == []
    # the whitelist is in use exactly where expected (and nowhere else)
    assert number_occurrences(schemas) == [
        "Options.schema.json#/properties/time_limit_s",
        "PlanOutcome.schema.json#/properties/time_limit_s",
        "PlanOutcome.schema.json#/properties/wall_time_s",
        "PlanOutcome.schema.json#/$defs/Tier/properties/wall_time_s",
    ]


def test_money_is_minor_units_in_range_and_rates_are_decimal_strings(schemas: Schemas) -> None:
    assert money_violations(schemas) == []


def test_conditions_are_not_objects_but_objects_inside_them_are_checked(
    schemas: Schemas,
) -> None:
    """The if/then/else of PlanOutcome is skipped by the closed-object guard; an open object
    schema nested inside a condition is still reported (negative control)."""
    outcome = schemas["PlanOutcome.schema.json"]
    assert {"if", "then", "else"} <= set(outcome["allOf"][0])
    broken = copy.deepcopy(schemas)
    then = broken["PlanOutcome.schema.json"]["allOf"][0]["then"]["properties"]
    then["allocation"] = {"type": "object", "properties": {"x": {"type": "string"}}}
    assert open_object_violations(broken) == [
        "PlanOutcome.schema.json#/allOf/0/then/properties/allocation: "
        "object without additionalProperties: false"
    ]


def test_guards_catch_a_float_money_field_and_an_open_object(schemas: Schemas) -> None:
    broken = copy.deepcopy(schemas)
    request = broken["PlanRequest.schema.json"]
    request["properties"]["amount_minor"] = {"type": "number"}
    del request["additionalProperties"]
    broken["CardOption.schema.json"]["properties"]["fee_rate"] = {"type": "number"}
    assert number_violations(broken) == [
        "CardOption.schema.json#/properties/fee_rate: 'number' outside the timing whitelist",
        "PlanRequest.schema.json#/properties/amount_minor: 'number' outside the timing whitelist",
    ]
    assert open_object_violations(broken) == [
        "PlanRequest.schema.json#: object without additionalProperties: false"
    ]
    assert sorted(money_violations(broken)) == [
        "CardOption.schema.json#/properties/fee_rate: rate 'fee_rate' is not a Rate decimal string",
        "PlanRequest.schema.json#/properties/amount_minor: money member 'amount_minor' is not a "
        "minor-unit integer",
    ]
    widened = copy.deepcopy(schemas)
    widened["common.schema.json"]["$defs"]["MinorAmount"]["maximum"] = INT64_MAX
    assert money_violations(widened) == [
        f"common.schema.json#/$defs/MinorAmount: not an integer within "
        f"[{-MONEY_LIMIT}, {MONEY_LIMIT}]"
    ]
