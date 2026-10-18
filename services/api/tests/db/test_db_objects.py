"""Golden fingerprints of every trigger and function (review R2-24, R2-30, R2-01).

The model-drift test cannot see triggers and functions, so a changed trigger event, column
list or function body went unnoticed before (review M5/M6/M8). Here every trigger
(``pg_get_triggerdef`` and its enabled state) and every own function (``md5(prosrc)`` plus
pinned settings) must match ``golden_objects.json`` for its revision. After an intentional
change run ``CARDFLOW_UPDATE_GOLDEN=1 uv run pytest tests/db/test_db_objects.py`` and review
the diff of the JSON file like any other code change. In that mode the mutation checks
and the coverage check are skipped (they would compare against the file being rewritten);
the other tests write their revision's entry.
"""

import json
import os
from collections.abc import Callable
from pathlib import Path
from typing import Final

import pytest
from sqlalchemy import text
from sqlalchemy.engine import URL, Connection, Engine
from sqlalchemy.pool import NullPool

from cardflow.db.engine import create_engine
from cardflow.db.migrations import head_revisions, upgrade

pytestmark = pytest.mark.db

UPDATE_ENV: Final = "CARDFLOW_UPDATE_GOLDEN"
GOLDEN_PATH: Final = Path(__file__).with_name("golden_objects.json")
PINNED_SEARCH_PATH: Final = "search_path=pg_catalog, public, pg_temp"

DbObjects = dict[str, dict[str, str]]


def updating() -> bool:
    """``CARDFLOW_UPDATE_GOLDEN=1``: the golden tests rewrite their entry instead of comparing."""
    return os.environ.get(UPDATE_ENV) == "1"


def check_or_update(golden: dict[str, DbObjects], revision: str, actual: DbObjects) -> None:
    """Compare with the golden file, or rewrite this revision's entry on request."""
    if updating():
        data = json.loads(GOLDEN_PATH.read_text(encoding="utf-8")) if GOLDEN_PATH.exists() else {}
        data[revision] = actual
        GOLDEN_PATH.write_text(json.dumps(data, indent=1, sort_keys=True) + "\n", encoding="utf-8")
        return
    compare(golden, revision, actual)


def compare(golden: dict[str, DbObjects], revision: str, actual: DbObjects) -> None:
    """Assert that ``actual`` equals the golden entry of ``revision`` (never writes)."""
    expected = golden[revision]
    for section in ("triggers", "functions"):
        missing = sorted(set(expected[section]) - set(actual[section]))
        unexpected = sorted(set(actual[section]) - set(expected[section]))
        changed = sorted(
            name
            for name in set(expected[section]) & set(actual[section])
            if expected[section][name] != actual[section][name]
        )
        assert (missing, unexpected, changed) == ([], [], []), (
            f"{section} differ from {GOLDEN_PATH.name} [{revision}]: "
            f"missing={missing} unexpected={unexpected} changed={changed}"
        )


def head_revision() -> str:
    (revision,) = head_revisions()
    return revision


def test_r2_24_triggers_and_functions_match_golden_at_head(
    db_engine: Engine,
    golden_objects: dict[str, DbObjects],
    read_database_objects: Callable[[Connection], DbObjects],
    require_head_schema: None,
) -> None:
    """R2-24: every trigger definition and function body at head is the reviewed one."""
    del require_head_schema
    with db_engine.connect() as connection:
        actual = read_database_objects(connection)

    check_or_update(golden_objects, head_revision(), actual)


def test_r2_24_revision_0001_matches_golden(
    engine_0001: Engine,
    golden_objects: dict[str, DbObjects],
    read_database_objects: Callable[[Connection], DbObjects],
) -> None:
    """R2-24: revision 0001 (frozen) still produces its recorded objects."""
    with engine_0001.connect() as connection:
        actual = read_database_objects(connection)

    check_or_update(golden_objects, "0001", actual)


def test_r2_24_golden_check_detects_a_changed_trigger(
    scratch_database_url: URL,
    golden_objects: dict[str, DbObjects],
    read_database_objects: Callable[[Connection], DbObjects],
) -> None:
    """R2-24: the review's undetected mutation M5 (guard fires on the wrong column) fails."""
    if updating():
        pytest.skip(f"{UPDATE_ENV}=1: the golden file is being rewritten, nothing to compare")
    upgrade(scratch_database_url, "head")
    engine = create_engine(scratch_database_url, poolclass=NullPool)
    try:
        with engine.begin() as connection:
            connection.execute(
                text("DROP TRIGGER card_products_workspace_immutable ON card_products")
            )
            connection.execute(
                text(
                    "CREATE TRIGGER card_products_workspace_immutable BEFORE UPDATE OF name "
                    "ON card_products FOR EACH ROW EXECUTE FUNCTION forbid_workspace_change()"
                )
            )
        with engine.connect() as connection:
            mutated = read_database_objects(connection)
    finally:
        engine.dispose()

    expected = golden_objects[head_revision()]["triggers"]
    name = "card_products.card_products_workspace_immutable"
    assert mutated["triggers"][name] != expected[name]
    with pytest.raises(AssertionError, match="card_products_workspace_immutable"):
        compare(golden_objects, head_revision(), mutated)


def test_r2_24_golden_check_detects_a_disabled_trigger(
    scratch_database_url: URL,
    golden_objects: dict[str, DbObjects],
    read_database_objects: Callable[[Connection], DbObjects],
) -> None:
    """R2-24: a trigger left disabled (e.g. by a migration step) changes its fingerprint."""
    if updating():
        pytest.skip(f"{UPDATE_ENV}=1: the golden file is being rewritten, nothing to compare")
    upgrade(scratch_database_url, "head")
    engine = create_engine(scratch_database_url, poolclass=NullPool)
    try:
        with engine.begin() as connection:
            connection.execute(
                text("ALTER TABLE statement_versions DISABLE TRIGGER statement_versions_immutable")
            )
        with engine.connect() as connection:
            mutated = read_database_objects(connection)
    finally:
        engine.dispose()

    with pytest.raises(AssertionError, match="statement_versions_immutable"):
        compare(golden_objects, head_revision(), mutated)


def test_r2_01_every_own_function_pins_its_search_path(
    db_engine: Engine, require_head_schema: None
) -> None:
    """R2-01: no trigger/check function resolves table names through the caller's path."""
    del require_head_schema
    with db_engine.connect() as connection:
        unpinned = connection.execute(
            text(
                """
                SELECT p.proname
                  FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
                 WHERE n.nspname = 'public'
                   AND NOT EXISTS (SELECT 1 FROM pg_depend AS d
                                    WHERE d.objid = p.oid AND d.deptype = 'e')
                   AND (p.proconfig IS NULL OR NOT (:pinned = ANY (p.proconfig)))
                """
            ),
            {"pinned": PINNED_SEARCH_PATH},
        ).scalars()
        unpinned_names = sorted(unpinned)

    assert unpinned_names == []


def test_golden_file_covers_every_revision(golden_objects: dict[str, DbObjects]) -> None:
    """R2-30: expectations come from the file per revision, including the current head."""
    if updating():
        pytest.skip(f"{UPDATE_ENV}=1: the golden file is being rewritten")
    assert {"0001", head_revision()} <= set(golden_objects)
    assert all(golden_objects[revision]["triggers"] for revision in golden_objects)
