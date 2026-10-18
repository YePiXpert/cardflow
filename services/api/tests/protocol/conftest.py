"""Fixtures for the rules-protocol v1 tests (T-004).

The runner and the converter live in ``packages/rules-protocol/runner_py/`` (outside the
``cardflow`` package) and are loaded from their files, so these tests exercise exactly the
code the documented command runs.
"""

import copy
import importlib.util
import sys
from dataclasses import dataclass
from pathlib import Path
from types import ModuleType
from typing import Any

import pytest
from referencing import Registry

from cardflow.planner.engine.protocol import parse_json

REPO_ROOT = Path(__file__).resolve().parents[4]
PROTOCOL_ROOT = REPO_ROOT / "packages" / "rules-protocol"
LEGACY_NAME = "regression_2026-10-16_10000.json"


@dataclass(frozen=True)
class ProtocolPaths:
    repo_root: Path
    protocol_root: Path
    schema_dir: Path
    runner: Path
    converter: Path
    legacy_fixture: Path
    v1_fixture: Path
    poc_fixture: Path


@pytest.fixture(scope="session")
def paths() -> ProtocolPaths:
    fixtures = PROTOCOL_ROOT / "fixtures"
    return ProtocolPaths(
        repo_root=REPO_ROOT,
        protocol_root=PROTOCOL_ROOT,
        schema_dir=PROTOCOL_ROOT / "schema" / "v1",
        runner=PROTOCOL_ROOT / "runner_py" / "run_fixtures.py",
        converter=PROTOCOL_ROOT / "runner_py" / "convert_legacy_fixture.py",
        legacy_fixture=fixtures / LEGACY_NAME,
        v1_fixture=fixtures / "regression_2026-10-16_10000.v1.json",
        poc_fixture=REPO_ROOT / "poc" / "engine_reference" / "fixtures" / LEGACY_NAME,
    )


def _load_module(name: str, path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="session")
def runner(paths: ProtocolPaths) -> ModuleType:
    return _load_module("rules_protocol_run_fixtures", paths.runner)


@pytest.fixture(scope="session")
def converter(paths: ProtocolPaths) -> ModuleType:
    return _load_module("rules_protocol_convert_legacy_fixture", paths.converter)


@pytest.fixture(scope="session")
def registry(runner: ModuleType) -> Registry:
    return runner.load_registry()


@pytest.fixture(scope="session")
def v1_fixture_doc(paths: ProtocolPaths) -> dict[str, Any]:
    return parse_json(paths.v1_fixture.read_bytes())


@pytest.fixture
def plan_input(v1_fixture_doc: dict[str, Any]) -> dict[str, Any]:
    """A fresh, mutable copy of the F-18 PlanInput document."""
    return copy.deepcopy(v1_fixture_doc["input"])
