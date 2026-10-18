"""The derived v1 golden fixture (T-004, A.3).

* the hand-written fixture is unchanged (sha256 pinned; byte-identical to the PoC oracle);
* regenerating the v1 fixture with the converter reproduces the committed file byte for byte;
* the v1 fixture is a valid Fixture document without any JSON float;
* its PlanInput equals what the T-003 loader + ``inputs_to_protocol`` produce from the
  hand-written file (two independent conversion paths);
* the converter refuses sub-minor-unit precision, floats and members it has no rule for.
"""

import copy
import hashlib
import json
import subprocess
import sys
from pathlib import Path
from types import ModuleType
from typing import Any

import pytest
from referencing import Registry

from cardflow.planner.engine.fixture import load_fixture
from cardflow.planner.engine.protocol import PlanOptions, inputs_to_protocol, parse_json

LEGACY_SHA256 = "d7e64809b11642a615102596adefcf3d21f538e25dd7c9db99b546e3fe555d6e"
LEGACY_RELATIVE = "fixtures/regression_2026-10-16_10000.json"


def _floats(value: object) -> int:
    if isinstance(value, float):
        return 1
    if isinstance(value, dict):
        return sum(_floats(v) for v in value.values())
    if isinstance(value, list):
        return sum(_floats(v) for v in value)
    return 0


def test_hand_written_fixture_is_unchanged(paths: Any) -> None:  # noqa: ANN401
    data = Path(paths.legacy_fixture).read_bytes()
    assert hashlib.sha256(data).hexdigest() == LEGACY_SHA256
    assert data == Path(paths.poc_fixture).read_bytes()  # the PoC oracle copy


def test_v1_fixture_is_regenerated_byte_for_byte(paths: Any, converter: ModuleType) -> None:  # noqa: ANN401
    legacy = Path(paths.legacy_fixture).read_bytes()
    regenerated = converter.serialise(converter.convert(legacy, LEGACY_RELATIVE))
    assert regenerated == Path(paths.v1_fixture).read_bytes()


def test_v1_fixture_records_its_source(v1_fixture_doc: dict[str, Any]) -> None:
    assert v1_fixture_doc["source"] == {
        "path": LEGACY_RELATIVE,
        "sha256": LEGACY_SHA256,
        "converter": "runner_py/convert_legacy_fixture.py",
    }


def test_v1_file_is_normalised_json(paths: Any) -> None:  # noqa: ANN401
    text = Path(paths.v1_fixture).read_text(encoding="utf-8")
    doc = json.loads(text)
    assert text == json.dumps(doc, sort_keys=True, indent=2, ensure_ascii=False) + "\n"
    assert "\\u" not in text  # UTF-8, nothing escaped


def test_v1_fixture_is_a_valid_fixture_without_floats(
    runner: ModuleType, registry: Registry, v1_fixture_doc: dict[str, Any]
) -> None:
    assert runner.schema_errors(registry, "Fixture.schema.json", v1_fixture_doc) == []
    assert _floats(v1_fixture_doc) == 0


def test_converter_and_loader_paths_produce_the_same_plan_input(
    paths: Any,  # noqa: ANN401
    v1_fixture_doc: dict[str, Any],
) -> None:
    inputs, scenarios, raw = load_fixture(paths.legacy_fixture)
    options = PlanOptions("cash_safety", raw["decision_scenario"], 10, 8, 0, 7)
    assert inputs_to_protocol(inputs, scenarios, options) == v1_fixture_doc["input"]


def test_every_expected_key_became_exactly_one_case(
    paths: Any,  # noqa: ANN401
    v1_fixture_doc: dict[str, Any],
) -> None:
    raw = parse_json(Path(paths.legacy_fixture).read_bytes())
    assert [case["name"] for case in v1_fixture_doc["expected"]] == list(raw["expected"])
    sources = {a["from"].split(" ")[0] for c in v1_fixture_doc["expected"] for a in c["assertions"]}
    leaves = {f"{k}.{m}" for k, v in raw["expected"].items() if k != "cycles" for m in v}
    leaves |= {f"cycles.{card}[{i}]" for card in raw["expected"]["cycles"] for i in (0, 1)}
    assert leaves <= sources  # every hand-written expectation is asserted


@pytest.mark.parametrize(
    ("mutate", "message"),
    [
        (lambda raw: raw["request"].update(amount="10000.001"), "more precision than CNY"),
        (lambda raw: raw["cards"][0].update(available=8000.0), "not a plain decimal string"),
        (lambda raw: raw["cards"][0].update(available="8e3"), "not a plain decimal string"),
        (lambda raw: raw["cards"][0].update(daily_cap="100.00"), "no conversion rule"),
        (lambda raw: raw["cards"][0]["due"].update(day_kind="business"), "no conversion rule"),
        (lambda raw: raw["expected"].update(new_check={"x": "1"}), "no conversion rule"),
        (lambda raw: raw["expected"]["plan_B10000"].update(odd="1"), "no conversion rule"),
        (lambda raw: raw["cash_accounts"][0].update(currency="USD"), "single-currency"),
    ],
)
def test_converter_refuses_what_it_cannot_convert_faithfully(
    paths: Any,  # noqa: ANN401
    converter: ModuleType,
    mutate: Any,  # noqa: ANN401
    message: str,
) -> None:
    raw = copy.deepcopy(parse_json(Path(paths.legacy_fixture).read_bytes()))
    mutate(raw)
    data = json.dumps(raw, ensure_ascii=False).encode("utf-8")
    with pytest.raises(converter.ConversionError, match=message):
        converter.convert(data, LEGACY_RELATIVE)


def test_converter_check_mode_confirms_the_committed_file(paths: Any) -> None:  # noqa: ANN401
    result = subprocess.run(  # noqa: S603 -- fixed argv: this interpreter + repository files
        [sys.executable, str(paths.converter), str(paths.legacy_fixture), "--check"],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "regenerated output is identical" in result.stdout
