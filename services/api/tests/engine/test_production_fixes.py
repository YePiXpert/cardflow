"""Production fixes to the engine migrated from the PoC (T-004, part B).

Each test was written before its fix and failed against the T-003 engine (see
``evidence/m0/T-004/engine-fixes-red.txt``):

1. the verifier records an allocation line for a card that is not in the plan as an
   ``UNKNOWN_CARD`` violation instead of raising ``KeyError``;
2. ``plan()`` records the hash of the caller's input, taken before any internal adjustment,
   or a hash supplied by the caller (protocol runs); since model 1.1.0 (T-004c, R3E-15) the
   default hash covers the scenarios and options too, and the horizon is never extended
   (R3E-08), so the adjustment this item first guarded no longer exists;
3. ``plan()`` passes ``workers``/``seed`` to every CP-SAT call and records them;
4. ``MODEL_VERSION`` is a release version and is recorded on every run (read from the engine,
   never hard-coded here);
6. two annotations that contradicted the code (``build_model(prior_bounds=())`` and the local
   ``by_day`` table in ``_low_series``) are checked against the runtime values they describe.

Item 5 (determinism) is ``test_determinism.py``; item 7 is ``test_billing_clamp.py``.
"""

import ast
import dataclasses
import importlib
import inspect
import pkgutil
import re
import textwrap
import types
import typing
import uuid
from collections.abc import Iterator
from dataclasses import replace
from datetime import date
from pathlib import Path
from typing import Any

import pytest

import cardflow.planner.engine as engine_package
from cardflow.planner.engine import MODEL_VERSION, allocation
from cardflow.planner.engine.allocation import ModelInputs
from cardflow.planner.engine.cash import Scenario
from cardflow.planner.engine.fixture import load_fixture
from cardflow.planner.engine.plan import plan
from cardflow.planner.engine.verifier import verify

# Golden fixture, located relative to this file (repository root = parents[4]).
FIX = (
    Path(__file__).resolve().parents[4]
    / "packages"
    / "rules-protocol"
    / "fixtures"
    / "regression_2026-10-16_10000.json"
)
# Every module of the engine package (new modules are picked up automatically).
ENGINE_MODULES = tuple(
    importlib.import_module(f"{engine_package.__name__}.{info.name}")
    for info in pkgutil.iter_modules(engine_package.__path__)
)

type Fx = tuple[ModelInputs, dict[str, Scenario], dict[str, Any]]


@pytest.fixture(scope="module")
def fx() -> Fx:
    return load_fixture(FIX)


# --- 1. verifier: unknown card ------------------------------------------------------------


def test_verifier_reports_unknown_card_instead_of_raising(fx: Fx) -> None:
    inputs, scenarios, _ = fx
    v = verify(inputs, {"A": 800000, "Z": 200000}, scenarios, "baseline")
    assert not v.ok
    assert not v.structural_ok
    unknown = [m for m in v.violations if m.startswith("UNKNOWN_CARD")]
    assert len(unknown) == 1
    assert "'Z'" in unknown[0]
    # the known part is still verified and explained; the unknown card has no line
    assert [line["card"] for line in v.lines] == ["A"]
    assert set(v.checks) == set(scenarios)


def test_verifier_rejects_an_allocation_made_only_of_unknown_cards(fx: Fx) -> None:
    inputs, scenarios, _ = fx
    v = verify(inputs, {"Z": 1000000}, scenarios, "baseline")
    assert not v.ok
    assert not v.structural_ok
    assert [m for m in v.violations if m.startswith("UNKNOWN_CARD")] != []
    assert v.lines == []


# --- 2. input_hash ------------------------------------------------------------------------


def test_plan_records_the_hash_of_the_callers_input_r3e_15(fx: Fx) -> None:
    """R3E-15 / R3E-08: the default hash is that of the caller's input (data, scenarios,
    options); a horizon before every repayment is no longer extended (the cards are excluded
    with REPAY_AFTER_HORIZON), and the hash is recorded on that outcome as well."""
    from cardflow.planner.engine.plan import run_input_hash

    inputs, scenarios, _ = fx
    short = replace(inputs, horizon_end=date(2026, 11, 1))  # before every planned repayment
    expected = run_input_hash(short, scenarios, "baseline", "cash_safety", 10, 7, 8, 0)
    out = plan(short, scenarios, "baseline", "cash_safety", time_limit_s=10, with_sensitivity=False)
    assert not any(n.startswith("horizon extended") for n in out.notes)
    assert out.input_hash == expected
    assert out.solve is None  # nothing eligible: every card repays after horizon_end
    full = plan(inputs, scenarios, "baseline", "cash_safety", time_limit_s=10)
    assert full.solve is not None
    assert full.input_hash == full.solve.input_hash
    assert full.input_hash == run_input_hash(
        inputs, scenarios, "baseline", "cash_safety", 10, 7, 8, 0
    )


def test_plan_uses_a_caller_supplied_input_hash_verbatim(fx: Fx) -> None:
    inputs, scenarios, _ = fx
    supplied = "0123456789abcdef" * 4
    out = plan(
        inputs,
        scenarios,
        "baseline",
        "cash_safety",
        time_limit_s=10,
        with_sensitivity=False,
        input_hash=supplied,
    )
    assert out.solve is not None
    assert out.input_hash == supplied
    assert out.solve.input_hash == supplied
    # outcomes without a solver run carry it too
    late = replace(inputs, request=replace(inputs.request, txn_date=date(2026, 10, 30)))
    needs_data = plan(late, scenarios, "baseline", "cash_safety", input_hash=supplied)
    assert needs_data.business_status == "NEEDS_DATA"
    assert needs_data.solve is None
    assert needs_data.input_hash == supplied
    default = plan(late, scenarios, "baseline", "cash_safety")
    from cardflow.planner.engine.plan import run_input_hash

    # R3E-15: the engine's default hash covers scenarios and options as well
    assert default.input_hash == run_input_hash(
        late, scenarios, "baseline", "cash_safety", 10.0, 7, 8, 0
    )


# --- 3. workers / seed --------------------------------------------------------------------


@pytest.fixture
def solver_calls(monkeypatch: pytest.MonkeyPatch) -> list[tuple[int, int]]:
    """Record (workers, seed) of every CP-SAT solver the engine creates."""
    calls: list[tuple[int, int]] = []
    real = allocation._solver

    def spy(time_limit_s: float, workers: int, seed: int) -> Any:  # noqa: ANN401
        calls.append((workers, seed))
        return real(time_limit_s, workers, seed)

    monkeypatch.setattr(allocation, "_solver", spy)
    return calls


def test_plan_passes_workers_and_seed_to_every_solver_call(
    fx: Fx, solver_calls: list[tuple[int, int]]
) -> None:
    inputs, scenarios, _ = fx
    out = plan(inputs, scenarios, "baseline", "cash_safety", time_limit_s=10, workers=2, seed=7)
    # the golden result does not depend on these parameters
    assert out.business_status == "CONDITIONALLY_FEASIBLE"
    assert out.allocation == {"A": 800000, "C": 200000}
    assert out.solve is not None
    solved_tiers = [t for t in out.solve.tiers if t.status != "SKIPPED_CONSTANT"]
    assert len(solver_calls) > len(solved_tiers)  # sensitivity solves were made as well
    assert set(solver_calls) == {(2, 7)}
    assert (out.solve.workers, out.solve.seed) == (2, 7)
    assert (out.workers, out.seed) == (2, 7)


def test_plan_defaults_to_eight_workers_and_a_fixed_seed(
    fx: Fx, solver_calls: list[tuple[int, int]]
) -> None:
    inputs, scenarios, _ = fx
    out = plan(inputs, scenarios, "baseline", "cash_safety", time_limit_s=10)
    assert out.solve is not None
    assert set(solver_calls) == {(8, 0)}  # ADR-004: num_workers=8, fixed random_seed
    assert (out.solve.workers, out.solve.seed) == (8, 0)
    assert (out.workers, out.seed) == (8, 0)
    assert out.time_limit_s == 10


# --- 4. model version / run record --------------------------------------------------------


def test_model_version_is_a_release_version_recorded_on_every_run(fx: Fx) -> None:
    match = re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", MODEL_VERSION)
    assert match, MODEL_VERSION
    assert int(match.group(1)) >= 1  # the production engine is a 1.x model, not a PoC
    inputs, scenarios, _ = fx
    out = plan(inputs, scenarios, "baseline", "cash_safety", time_limit_s=10)
    assert out.solve is not None
    assert out.solve.model_version == MODEL_VERSION
    assert out.model_version == MODEL_VERSION
    shortfall = plan(inputs, scenarios, "confirmed", "cash_safety", time_limit_s=10)
    assert shortfall.solve is None
    assert shortfall.model_version == MODEL_VERSION


def test_plan_and_its_solver_record_share_one_run_id(fx: Fx) -> None:
    inputs, scenarios, _ = fx
    supplied = str(uuid.uuid4())
    out = plan(
        inputs,
        scenarios,
        "baseline",
        "cash_safety",
        time_limit_s=10,
        with_sensitivity=False,
        run_id=supplied,
    )
    assert out.solve is not None
    assert out.run_id == supplied
    assert out.solve.run_id == supplied
    generated = plan(
        inputs, scenarios, "baseline", "cash_safety", time_limit_s=10, with_sensitivity=False
    )
    assert generated.solve is not None
    assert uuid.UUID(generated.run_id)
    assert generated.solve.run_id == generated.run_id
    shortfall = plan(inputs, scenarios, "confirmed", "cash_safety", time_limit_s=10)
    assert uuid.UUID(shortfall.run_id)  # every run has an id, also without a solver run


# --- 6. annotations that contradicted the code --------------------------------------------


def _admits(hint: object, value: object) -> bool:
    """Whether ``value`` is an instance of the (evaluated) annotation ``hint``."""
    if hint is Any:
        return True
    if hint is type(None):
        return value is None
    origin = typing.get_origin(hint)
    args = typing.get_args(hint)
    if origin in (types.UnionType, typing.Union):
        return any(_admits(arg, value) for arg in args)
    if origin is typing.Literal:
        return value in args
    target = origin or hint
    if not isinstance(target, type):
        return True  # a typing construct without a runtime class: not checkable here
    if target is float and isinstance(value, int) and not isinstance(value, bool):
        return True  # int is acceptable where float is declared
    if not isinstance(value, target):
        return False
    if target is list and args:
        return all(_admits(args[0], item) for item in typing.cast("list[object]", value))
    if target is tuple and args and args[-1] is not Ellipsis:
        items = typing.cast("tuple[object, ...]", value)
        return len(items) == len(args) and all(map(_admits, args, items))
    return True


def _declared_defaults() -> Iterator[tuple[str, object, object]]:
    """(name, evaluated annotation, default) of every defaulted parameter/dataclass field."""
    for module in ENGINE_MODULES:
        for name, obj in vars(module).items():
            if getattr(obj, "__module__", None) != module.__name__:
                continue
            if inspect.isfunction(obj):
                hints = typing.get_type_hints(obj)
                for p in inspect.signature(obj).parameters.values():
                    if p.default is not inspect.Parameter.empty and p.name in hints:
                        yield f"{module.__name__}.{name}({p.name})", hints[p.name], p.default
            elif inspect.isclass(obj) and dataclasses.is_dataclass(obj):
                hints = typing.get_type_hints(obj)
                for f in dataclasses.fields(obj):
                    if f.default is not dataclasses.MISSING:
                        yield f"{module.__name__}.{name}.{f.name}", hints[f.name], f.default


def test_declared_defaults_match_their_annotations() -> None:
    checked = list(_declared_defaults())
    assert len(checked) > 40  # the scan reaches the engine's functions and dataclasses
    wrong = [
        f"{where}: default {default!r} is not a {hint}"
        for where, hint, default in checked
        if not _admits(hint, default)
    ]
    assert wrong == []


def test_low_series_by_day_annotation_admits_the_values_it_stores() -> None:
    fn = ast.parse(textwrap.dedent(inspect.getsource(allocation._low_series))).body[0]
    (annotated,) = [
        n
        for n in ast.walk(fn)
        if isinstance(n, ast.AnnAssign)
        and isinstance(n.target, ast.Name)
        and n.target.id == "by_day"
    ]
    (initialiser,) = [
        ast.literal_eval(n.args[1])
        for n in ast.walk(fn)
        if isinstance(n, ast.Call)
        and isinstance(n.func, ast.Attribute)
        and n.func.attr == "setdefault"
    ]
    assert initialiser == [None, None]  # by_day.setdefault(day, [low, end]) filled in later
    hint = eval(  # noqa: S307 -- evaluates the engine's own annotation in its module namespace
        compile(ast.Expression(annotated.annotation), "<by_day>", "eval"), vars(allocation)
    )
    assert typing.get_origin(hint) is dict
    _, value_type = typing.get_args(hint)
    assert _admits(value_type, initialiser)
    assert _admits(value_type, [-5, 7])  # (low, end) balances once filled
