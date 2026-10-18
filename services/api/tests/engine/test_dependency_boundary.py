"""Dependency boundary of the planning engine (T-003).

``cardflow/planner/engine`` may import only the Python standard library, OR-Tools and its own
modules. Web framework, validation, ORM, migration and database-driver packages, and every
other ``cardflow`` subpackage, are forbidden: the engine stays a pure library that runs in a
worker subprocess without the server stack and remains portable to the Dart client.

The guard parses every ``.py`` file under the engine directory (``ast``; nothing is
imported), so it also sees imports inside functions. A runtime check additionally imports the
engine in a fresh interpreter, which catches dependencies pulled in by parent packages.
"""

import ast
import subprocess
import sys
from pathlib import Path
from typing import Final

import pytest

ENGINE_DIR: Final = Path(__file__).resolve().parents[2] / "cardflow" / "planner" / "engine"
ENGINE_PACKAGE: Final = "cardflow.planner.engine"
THIRD_PARTY_ALLOWED: Final = frozenset({"ortools"})
# Named explicitly for the error message; the allowlist above already rejects them.
FORBIDDEN: Final = frozenset(
    {
        "fastapi",
        "starlette",
        "pydantic",
        "pydantic_core",
        "pydantic_settings",
        "sqlalchemy",
        "alembic",
        "psycopg",
        "psycopg_binary",
        "psycopg2",
        "uvicorn",
    }
)
DYNAMIC_IMPORTS: Final = frozenset({"__import__", "import_module"})
MIGRATED_MODULES: Final = frozenset(
    {"__init__", "money", "billing", "cash", "allocation", "verifier", "plan", "fixture", "sample"}
)


def classify(module: str, level: int = 0) -> str | None:
    """Why importing ``module`` breaks the boundary, or ``None`` if it is allowed."""
    if level:
        return "relative import (use the absolute cardflow.planner.engine path)"
    top = module.partition(".")[0]
    if top == "cardflow":
        if module == ENGINE_PACKAGE or module.startswith(f"{ENGINE_PACKAGE}."):
            return None
        return "other cardflow subpackage"
    if top in FORBIDDEN:
        return "framework/validation/ORM/database package"
    if top in sys.stdlib_module_names or top in THIRD_PARTY_ALLOWED:
        return None
    return "third-party package outside the allowlist (stdlib + ortools)"


def violations(source: str, filename: str = "<string>") -> list[str]:
    """Every boundary violation in ``source``: static imports anywhere and dynamic imports."""
    found = []
    for node in ast.walk(ast.parse(source, filename=filename)):
        if isinstance(node, ast.Import):
            targets = [(alias.name, 0) for alias in node.names]
        elif isinstance(node, ast.ImportFrom):
            targets = [(node.module or "", node.level)]
        elif isinstance(node, ast.Call):
            func = node.func
            name = func.id if isinstance(func, ast.Name) else getattr(func, "attr", None)
            if name in DYNAMIC_IMPORTS:
                found.append(f"{filename}:{node.lineno}: dynamic import via {name}()")
            continue
        else:
            continue
        for module, level in targets:
            reason = classify(module, level)
            if reason:
                shown = "." * level + module
                found.append(f"{filename}:{node.lineno}: {shown}: {reason}")
    return found


def engine_files() -> list[Path]:
    return sorted(ENGINE_DIR.rglob("*.py"))


def test_scan_covers_the_engine_package() -> None:
    names = {path.stem for path in engine_files()}
    assert names >= MIGRATED_MODULES, f"engine modules missing from the scan: {names}"


def test_engine_imports_only_stdlib_ortools_and_itself() -> None:
    found = [
        problem
        for path in engine_files()
        for problem in violations(
            path.read_text(encoding="utf-8"), str(path.relative_to(ENGINE_DIR.parents[2]))
        )
    ]
    assert found == [], "engine dependency boundary violated:\n" + "\n".join(found)


@pytest.mark.parametrize(
    "source",
    [
        "import fastapi",
        "from starlette.requests import Request",
        "from pydantic import BaseModel",
        "import sqlalchemy.orm",
        "from alembic import op",
        "import psycopg",
        "from cardflow.db import create_engine",
        "from cardflow.settings import Settings",
        "from cardflow import planner",
        "import cardflow.planner.service",
        "import numpy",
        "from .money import fmt",
        "def f():\n    from sqlalchemy import text\n",
        "import importlib\nimportlib.import_module('fastapi')",
        "__import__('sqlalchemy')",
    ],
)
def test_guard_rejects(source: str) -> None:
    assert violations(source)


@pytest.mark.parametrize(
    "source",
    [
        "from __future__ import annotations",
        "import json\nfrom datetime import date\nfrom decimal import Decimal",
        "import ortools\nfrom ortools.sat.python import cp_model",
        "from cardflow.planner.engine import MODEL_VERSION",
        "from cardflow.planner.engine.money import fmt",
    ],
)
def test_guard_accepts(source: str) -> None:
    assert violations(source) == []


def test_importing_the_engine_loads_no_forbidden_module() -> None:
    modules = ", ".join(
        f"{ENGINE_PACKAGE}.{path.stem}" for path in engine_files() if path.stem != "__init__"
    )
    probe = f"import sys, {modules}\nprint('\\n'.join(sorted(sys.modules)))\n"
    result = subprocess.run(  # noqa: S603 -- fixed argv: this interpreter + a constant probe
        [sys.executable, "-c", probe], capture_output=True, text=True, check=True
    )
    loaded = result.stdout.split()
    bad = [
        name
        for name in loaded
        if name.partition(".")[0] in FORBIDDEN
        or (
            name.partition(".")[0] == "cardflow"
            and name not in {"cardflow", "cardflow.planner"}
            and classify(name) is not None
        )
    ]
    assert bad == []
    assert ENGINE_PACKAGE in loaded
