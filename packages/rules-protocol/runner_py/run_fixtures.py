"""rules-protocol v1 golden-fixture runner (Python; CP-SAT engine).

Usage, from the repository root::

    uv run --project services/api python packages/rules-protocol/runner_py/run_fixtures.py \\
        [--dump DIR] [FIXTURE_OR_DIRECTORY ...]

Default: every ``fixtures/*.v1.json``; a directory means its ``*.v1.json`` files. For each
fixture: strict JSON parse -> JSON Schema ``Fixture.schema.json`` (Draft 2020-12 with the
format checker; integers must be integer tokens) -> no JSON float anywhere except
``input.options.time_limit_s`` -> protocol adapter (``cardflow.planner.engine.protocol``) ->
every case: ``cycles`` (billing cycles), ``verify`` (independent verifier, no solver) or
``plan`` (engine run with the case's profile and decision scenario; one run per pair) -> the
output is validated against its schema -> every assertion is evaluated and printed.

``--dump DIR`` additionally writes the output of every ``cycles`` and ``verify`` case as canonical
JSON plus a newline to ``DIR/<fixture file name without .v1.json>/<NN>-<case name>.<kind>.json``
(``NN`` = the case's two-digit position in ``expected``) -- the reference outputs the Dart runner
(``dart run cardflow_domain:run_fixtures --dump DIR``) is compared with byte for byte. ``plan``
outputs are not written: they carry a run id, a clock time and solver timings, and the Dart client
has no solver to compute them.

Exit status: 0 every assertion holds; 1 a mismatch (or an output that violates its schema);
2 invalid input (unreadable file, bad JSON, schema or protocol violation) -- 2 wins over 1.
"""

import copy
import json
import re
import sys
from collections.abc import Callable
from datetime import date
from pathlib import Path
from typing import Any

import ortools
from jsonschema import Draft202012Validator, FormatChecker, validators
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT202012

from cardflow.planner.engine import MODEL_VERSION
from cardflow.planner.engine.protocol import (
    PROTOCOL_VERSION,
    ProtocolError,
    canonical_json,
    card_cycles_to_protocol,
    inputs_from_protocol,
    parse_json,
    plan_from_protocol,
    protocol_input_hash,
    verify_from_protocol,
)

PROTOCOL_ROOT = Path(__file__).resolve().parents[1]  # packages/rules-protocol
REPO_ROOT = PROTOCOL_ROOT.parents[1]
SCHEMA_DIR = PROTOCOL_ROOT / "schema" / "v1"
FIXTURE_DIR = PROTOCOL_ROOT / "fixtures"
SCHEMA_BASE = "https://rules-protocol.cardflow.invalid/v1/"
FIXTURE_SCHEMA = "Fixture.schema.json"
OUTPUT_SCHEMAS = {
    "cycles": "PlanOutcome.schema.json#/$defs/CardCycles",
    "verify": "PlanOutcome.schema.json#/$defs/VerificationResult",
    "plan": "PlanOutcome.schema.json",
}
FLOAT_ALLOWED = frozenset({"/input/options/time_limit_s"})
PASSED, MISMATCH, INVALID = 0, 1, 2

type Json = Any
type Emit = Callable[[str], None]


class InvalidFixtureError(Exception):
    """The fixture itself is invalid (exit 2)."""


def _strict_integer(_checker: object, instance: object) -> bool:
    """Protocol v1 integers are JSON number tokens without fraction or exponent.

    Standard JSON Schema counts ``1.0`` as an integer (a mathematical integer); a Dart
    ``jsonDecode`` turns it into a ``double``. Rejecting it here keeps both runners equal and
    keeps floats out of every money field.
    """
    return isinstance(instance, int) and not isinstance(instance, bool)


StrictValidator = validators.extend(
    Draft202012Validator,
    type_checker=Draft202012Validator.TYPE_CHECKER.redefine("integer", _strict_integer),
)

# RFC 3339 date-time (section 5.6). jsonschema checks 'date-time' only with the optional
# rfc3339-validator package, which this project does not install; without a check the schema
# would accept 2026-02-30T09:00:00Z although every adapter refuses it (review R3E-20).
_RFC3339 = re.compile(
    r"([0-9]{4})-([0-9]{2})-([0-9]{2})[Tt]([0-9]{2}):([0-9]{2}):([0-9]{2})(\.[0-9]+)?"
    r"([Zz]|[+-]([0-9]{2}):([0-9]{2}))"
)
FORMAT_CHECKER = FormatChecker()


@FORMAT_CHECKER.checks("date-time", raises=ValueError)
def _date_time(instance: object) -> bool:
    """Standard-library RFC 3339 check: grammar, a real calendar day, hours 00-23, minutes
    00-59, seconds 00-60 (leap second; the v1 Timestamp pattern excludes it), offset < 24 h."""
    if not isinstance(instance, str):
        return True
    m = _RFC3339.fullmatch(instance)
    if m is None:
        return False
    year, month, day, hour, minute, second = (int(g) for g in m.groups()[:6])
    date(year, month, day)  # ValueError for an impossible day
    offset_ok = m.group(9) is None or (int(m.group(9)) < 24 and int(m.group(10)) < 60)
    return hour < 24 and minute < 60 and second <= 60 and offset_ok


# --- schemas -------------------------------------------------------------------------------


def load_registry(schema_dir: Path = SCHEMA_DIR) -> Registry:
    """All v1 schema files, addressed by their ``$id`` (no network access).

    The registered copies omit ``$schema`` and carry the Draft 2020-12 dialect explicitly:
    when jsonschema follows a ``$ref`` it re-selects the validator class from the target's
    ``$schema``, which would silently drop the strict integer check of :data:`StrictValidator`.
    (Every file declares 2020-12; ``tests/protocol/test_schemas.py`` checks that.)
    """
    registry: Registry = Registry()
    for path in sorted(schema_dir.glob("*.schema.json")):
        schema = parse_json(path.read_bytes())
        contents = {k: v for k, v in schema.items() if k != "$schema"}
        resource = Resource(contents=contents, specification=DRAFT202012)
        registry = registry.with_resource(schema["$id"], resource)
    return registry


def validator(registry: Registry, ref: str) -> Draft202012Validator:
    """Draft 2020-12 validator (strict integers) with the format checker for ``ref``
    (``file[#/fragment]``)."""
    return StrictValidator(
        {"$ref": SCHEMA_BASE + ref}, registry=registry, format_checker=FORMAT_CHECKER
    )


def schema_errors(registry: Registry, ref: str, instance: Json) -> list[str]:
    errors = validator(registry, ref).iter_errors(instance)
    return sorted(f"{e.json_path}: {e.message}" for e in errors)


def find_floats(value: Json, path: str = "") -> list[str]:
    """JSON Pointers of every float in ``value`` outside :data:`FLOAT_ALLOWED`."""
    if isinstance(value, float):
        return [] if path in FLOAT_ALLOWED else [path]
    if isinstance(value, dict):
        return [p for k, v in value.items() for p in find_floats(v, f"{path}/{_escape(k)}")]
    if isinstance(value, list):
        return [p for i, v in enumerate(value) for p in find_floats(v, f"{path}/{i}")]
    return []


# --- assertions ----------------------------------------------------------------------------


def _escape(key: str) -> str:
    return key.replace("~", "~0").replace("/", "~1")


def resolve(doc: Json, pointer: str) -> Json:
    """RFC 6901 JSON Pointer; raises LookupError if the target does not exist."""
    if pointer == "":
        return doc
    node = doc
    for raw in pointer.split("/")[1:]:
        segment = raw.replace("~1", "/").replace("~0", "~")
        if isinstance(node, dict):
            if segment not in node:
                raise LookupError(f"no member {segment!r}")
            node = node[segment]
        elif isinstance(node, list):
            if not re.fullmatch(r"0|[1-9][0-9]*", segment):
                raise LookupError(f"{segment!r} is not an array index")
            if int(segment) >= len(node):
                raise LookupError(f"index {segment} out of range ({len(node)} items)")
            node = node[int(segment)]
        else:
            raise LookupError(f"cannot descend into {type(node).__name__} with {segment!r}")
    return node


def json_equal(a: Json, b: Json) -> bool:
    """Strict JSON equality: booleans are not numbers and integers are not floats."""
    if type(a) is not type(b):
        return False
    if isinstance(a, dict):
        return a.keys() == b.keys() and all(json_equal(a[k], b[k]) for k in a)
    if isinstance(a, list):
        return len(a) == len(b) and all(json_equal(x, y) for x, y in zip(a, b, strict=True))
    return a == b


def _show(value: Json) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True)


def describe(assertion: dict[str, Json]) -> str:
    text = assertion["path"] or "<output>"
    if "where" in assertion:
        cond = ", ".join(f"{k}={_show(v)}" for k, v in sorted(assertion["where"].items()))
        text += f"[{cond}]{assertion.get('then', '')}"
    if "equals" in assertion:
        return f"{text} == {_show(assertion['equals'])}"
    return f"len({text}) == {assertion['length']}"


def check(assertion: dict[str, Json], output: Json) -> tuple[bool, str]:
    """Evaluate one assertion; returns (holds, what was found)."""
    try:
        value = resolve(output, assertion["path"])
        if "where" in assertion:
            if not isinstance(value, list):
                return False, f"not an array: {_show(value)}"
            where = assertion["where"]
            matches = [
                item
                for item in value
                if isinstance(item, dict)
                and all(k in item and json_equal(item[k], v) for k, v in where.items())
            ]
            if len(matches) != 1:
                return False, f"{len(matches)} elements match"
            value = resolve(matches[0], assertion.get("then", ""))
    except LookupError as e:
        return False, f"missing ({e})"
    if "equals" in assertion:
        return json_equal(value, assertion["equals"]), _show(value)
    if not isinstance(value, (list, dict)):
        return False, f"not an array/object: {_show(value)}"
    return len(value) == assertion["length"], f"length {len(value)}"


# --- running -------------------------------------------------------------------------------


def _relative(path: Path) -> str:
    try:
        return path.resolve().relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return str(path)


def _load(path: Path, registry: Registry) -> dict[str, Json]:
    try:
        doc = parse_json(path.read_bytes())
    except OSError as e:
        raise InvalidFixtureError(f"cannot read: {e}") from None
    except ProtocolError as e:
        raise InvalidFixtureError(f"not strict JSON: {e}") from None
    errors = schema_errors(registry, FIXTURE_SCHEMA, doc)
    if errors:
        raise InvalidFixtureError("schema violations:\n" + "\n".join(f"  {e}" for e in errors))
    floats = find_floats(doc)
    if floats:
        raise InvalidFixtureError(f"JSON floats outside time_limit_s: {floats}")
    try:
        inputs_from_protocol(doc["input"])
    except ProtocolError as e:
        raise InvalidFixtureError(f"protocol violation in input: {e}") from None
    return doc


def _case_input(doc: dict[str, Json], case: dict[str, Json]) -> dict[str, Json]:
    case_input = copy.deepcopy(doc["input"])
    case_input["options"]["profile"] = case["profile"]
    case_input["options"]["decision_scenario"] = case["decision_scenario"]
    return case_input


def _summary(outcome: dict[str, Json]) -> str:
    alloc = ", ".join(f"{a['card_id']}={a['amount_minor']}" for a in outcome["allocation"])
    failing = ",".join(outcome["failing_scenarios"]) or "-"
    return (
        f"business_status {outcome['business_status']}, solver {outcome['solver_status']}, "
        f"allocation {alloc or '-'}, failing {failing}, input_hash {outcome['input_hash'][:16]}"
    )


def fixture_stem(path: Path) -> str:
    """Directory name of a fixture's dumped outputs: the file name without ``.v1.json``."""
    name = path.name
    for suffix in (".v1.json", ".json"):
        if name.endswith(suffix):
            return name[: -len(suffix)]
    return name


def dump_output(dump: Path, path: Path, index: int, case: dict[str, Json], output: Json) -> Path:
    """Write one case output as canonical JSON plus a newline (``--dump``)."""
    target = dump / fixture_stem(path) / f"{index:02d}-{case['name']}.{case['kind']}.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(canonical_json(output) + b"\n")
    return target


def run_fixture(path: Path, registry: Registry, emit: Emit, dump: Path | None = None) -> int:
    """Run one fixture; returns PASSED, MISMATCH or INVALID. With ``dump``, every cycles and
    verify output is also written there (:func:`dump_output`)."""
    emit(f"== {_relative(path)}")
    try:
        doc = _load(path, registry)
    except InvalidFixtureError as e:
        emit(f"   INVALID: {e}")
        return INVALID
    emit(
        f"   fixture {doc['fixture_id']}: {FIXTURE_SCHEMA} OK (Draft 2020-12, format checker); "
        f"input_hash {protocol_input_hash(doc['input'])}"
    )
    plans: dict[tuple[str, str], dict[str, Json]] = {}
    total = failed = bad_outputs = 0
    for index, case in enumerate(doc["expected"]):
        kind = case["kind"]
        try:
            if kind == "cycles":
                inputs, _, _ = inputs_from_protocol(doc["input"])
                output = card_cycles_to_protocol(inputs)
                label = "cycles"
            elif kind == "verify":
                output = verify_from_protocol(
                    doc["input"], case["allocation"], case["decision_scenario"]
                )
                parts = ", ".join(f"{a['card_id']}={a['amount_minor']}" for a in case["allocation"])
                label = f"verify {parts} / {case['decision_scenario']}"
            else:
                key = (case["profile"], case["decision_scenario"])
                if key not in plans:
                    plans[key] = plan_from_protocol(_case_input(doc, case))
                output = plans[key]
                label = f"plan {key[0]} / {key[1]}"
        except ProtocolError as e:
            emit(f"   case {case['name']}: INVALID: {e}")
            return INVALID
        errors = schema_errors(registry, OUTPUT_SCHEMAS[kind], output)
        emit(f"   case {case['name']} [{label}]")
        if dump is not None and kind != "plan":
            emit(f"     dumped {dump_output(dump, path, index, case, output)}")
        if kind == "plan":
            emit(f"     {_summary(output)}")
        if errors:
            bad_outputs += 1
            emit(f"     FAIL output violates {OUTPUT_SCHEMAS[kind]}:")
            for error in errors:
                emit(f"       {error}")
        else:
            emit(f"     output schema OK ({OUTPUT_SCHEMAS[kind]})")
        for assertion in case["assertions"]:
            total += 1
            holds, found = check(assertion, output)
            source = f"  <- {assertion['from']}" if "from" in assertion else ""
            if holds:
                emit(f"     PASS {describe(assertion)}{source}")
            else:
                failed += 1
                emit(f"     FAIL {describe(assertion)}; found {found}{source}")
    ok = failed == 0 and bad_outputs == 0
    emit(
        f"   result: {'PASS' if ok else 'FAIL'} ({total - failed}/{total} assertions hold, "
        f"{bad_outputs} output schema violation(s))"
    )
    return PASSED if ok else MISMATCH


def _targets(args: list[str]) -> list[Path]:
    if not args:
        return sorted(FIXTURE_DIR.glob("*.v1.json"))
    out: list[Path] = []
    for arg in args:
        path = Path(arg)
        out.extend(sorted(path.glob("*.v1.json")) if path.is_dir() else [path])
    return out


def main(argv: list[str] | None = None, emit: Emit | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    write: Emit = emit or (lambda line: sys.stdout.write(line + "\n"))
    dump: Path | None = None
    if "--dump" in args:
        at = args.index("--dump")
        if at + 1 >= len(args):
            write(__doc__ or "")
            return INVALID
        dump = Path(args[at + 1])
        del args[at : at + 2]
    else:
        for at, arg in enumerate(args):
            if arg.startswith("--dump="):
                dump = Path(arg.removeprefix("--dump="))
                del args[at]
                break
    if any(a.startswith("-") for a in args):
        write(__doc__ or "")
        return INVALID
    write(
        f"rules-protocol runner: protocol v{PROTOCOL_VERSION}, engine model {MODEL_VERSION}, "
        f"OR-Tools {ortools.__version__}"
    )
    targets = _targets(args)
    if not targets:
        write("no *.v1.json fixtures found")
        return INVALID
    registry = load_registry()
    results = [run_fixture(path, registry, write, dump) for path in targets]
    status = max(results)
    write(
        f"summary: {len(results)} fixture(s): {results.count(PASSED)} passed, "
        f"{results.count(MISMATCH)} failed, {results.count(INVALID)} invalid -> exit {status}"
    )
    return status


if __name__ == "__main__":
    raise SystemExit(main())
