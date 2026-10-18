"""The Python fixture runner ``packages/rules-protocol/runner_py/run_fixtures.py`` (T-004, A.5).

Exit status: 0 = every assertion of every fixture holds (F-18), 1 = a mismatch (tampered
expected value), 2 = invalid input (schema / protocol / JSON). The CLI is run as a subprocess
from an unrelated working directory; the assertion semantics are unit-tested in process.
"""

import json
import subprocess
import sys
from pathlib import Path
from types import ModuleType
from typing import Any

import pytest

type Doc = dict[str, Any]


def _run(runner_path: Path, *args: Path, cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(  # noqa: S603 -- fixed argv: this interpreter + repository files
        [sys.executable, str(runner_path), *map(str, args)],
        capture_output=True,
        text=True,
        check=False,
        cwd=cwd,
    )


def _write(tmp_path: Path, doc: Doc, name: str = "case.v1.json") -> Path:
    path = tmp_path / name
    path.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return path


def test_f18_passes_with_exit_0(paths: Any, tmp_path: Path) -> None:  # noqa: ANN401
    result = _run(paths.runner, paths.v1_fixture, cwd=tmp_path)
    assert result.returncode == 0, result.stdout + result.stderr
    assert result.stderr == ""
    assert "result: PASS (23/23 assertions hold, 0 output schema violation(s))" in result.stdout
    assert "FAIL" not in result.stdout
    assert result.stdout.rstrip().endswith("1 passed, 0 failed, 0 invalid -> exit 0")


def test_default_target_is_every_v1_fixture(paths: Any, tmp_path: Path) -> None:  # noqa: ANN401
    result = _run(paths.runner, cwd=tmp_path)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "regression_2026-10-16_10000.v1.json" in result.stdout


def test_a_tampered_expected_value_fails_with_exit_1(
    paths: Any,  # noqa: ANN401
    v1_fixture_doc: Doc,
    tmp_path: Path,
) -> None:
    doc = json.loads(json.dumps(v1_fixture_doc))
    optimum = next(c for c in doc["expected"] if c["name"] == "cash_safety_optimum")
    optimum["assertions"][2]["equals"] = 800001  # A: 8,000.01 instead of 8,000.00
    result = _run(paths.runner, _write(tmp_path, doc), cwd=tmp_path)
    assert result.returncode == 1, result.stdout + result.stderr
    assert (
        '     FAIL /allocation[card_id="A"]/amount_minor == 800001; found 800000'
        "  <- cash_safety_optimum.A"
    ) in result.stdout
    assert "result: FAIL (22/23 assertions hold" in result.stdout


@pytest.mark.parametrize(
    ("mutate", "message"),
    [
        (
            lambda d: d["input"]["request"].update(amount_minor=1000000.0),
            "schema violations",
        ),
        (lambda d: d["input"]["cards"][1].update(card_id="A"), "duplicate card_id"),
        (lambda d: d["expected"][0].update(kind="other"), "schema violations"),
        (lambda d: d["expected"][1].update(decision_scenario="nope"), "unknown scenario"),
        (lambda d: d["expected"][0]["assertions"][0].update(equals=1.5), "JSON floats"),
    ],
    ids=["float-amount", "duplicate-card", "bad-case-kind", "unknown-verify-scenario", "float"],
)
def test_invalid_input_exits_2(
    runner: ModuleType,
    v1_fixture_doc: Doc,
    tmp_path: Path,
    mutate: Any,  # noqa: ANN401
    message: str,
) -> None:
    doc = json.loads(json.dumps(v1_fixture_doc))
    mutate(doc)
    lines: list[str] = []
    status = runner.main([str(_write(tmp_path, doc))], emit=lines.append)
    assert status == runner.INVALID, "\n".join(lines)
    assert message in "\n".join(lines)


def test_invalid_input_exits_2_from_the_command_line(paths: Any, tmp_path: Path) -> None:  # noqa: ANN401
    broken = tmp_path / "broken.v1.json"
    broken.write_bytes(b'{"protocol_version": "1", "protocol_version": "1"}')
    result = _run(paths.runner, broken, paths.v1_fixture, cwd=tmp_path)
    assert result.returncode == 2, result.stdout + result.stderr  # 2 wins over 0
    assert "INVALID: not strict JSON" in result.stdout


# --- assertion semantics --------------------------------------------------------------------

OUTPUT = {
    "allocation": [{"card_id": "A", "amount_minor": 5}, {"card_id": "C", "amount_minor": 7}],
    "flags": {"ok": True, "n": 1},
    "a/b": {"~x": 3},
}


@pytest.mark.parametrize(
    ("assertion", "holds"),
    [
        ({"path": "/flags/ok", "equals": True}, True),
        ({"path": "/flags/ok", "equals": 1}, False),  # a boolean is not a number
        ({"path": "/flags/n", "equals": True}, False),
        ({"path": "/flags/n", "equals": 1.0}, False),  # an integer is not a float
        ({"path": "/a~1b/~0x", "equals": 3}, True),  # RFC 6901 escapes
        ({"path": "/allocation/1/card_id", "equals": "C"}, True),
        ({"path": "/allocation/01/card_id", "equals": "C"}, False),  # no leading zeros
        ({"path": "/allocation/2", "equals": None}, False),  # missing is not null
        ({"path": "/allocation", "length": 2}, True),
        ({"path": "/flags", "length": 2}, True),
        (
            {
                "path": "/allocation",
                "where": {"card_id": "C"},
                "then": "/amount_minor",
                "equals": 7,
            },
            True,
        ),
        ({"path": "/allocation", "where": {"card_id": "Z"}, "equals": {}}, False),  # no match
        (
            {
                "path": "/allocation",
                "where": {"amount_minor": 5},
                "equals": OUTPUT["allocation"][0],
            },
            True,
        ),
        ({"path": "/flags", "where": {"ok": True}, "equals": {}}, False),  # not an array
    ],
)
def test_assertion_semantics(runner: ModuleType, assertion: Doc, holds: bool) -> None:
    assert runner.check(assertion, OUTPUT)[0] is holds


def test_where_must_select_exactly_one_element(runner: ModuleType) -> None:
    output = {"rows": [{"k": 1}, {"k": 1}]}
    assertion = {"path": "/rows", "where": {"k": 1}, "equals": {"k": 1}}
    assert runner.check(assertion, output) == (False, "2 elements match")
