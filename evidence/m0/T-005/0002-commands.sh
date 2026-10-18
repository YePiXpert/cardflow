#!/usr/bin/env bash
# T-005/T-007 revision round (migration 0002) - evidence run.
# Working dir services/api; dev DB cardflow-dev on 127.0.0.1:18432. Every output passes
# through mask(), which replaces the database password with ***.
set -u
cd /projects/cardflow/services/api
EV=/projects/cardflow/evidence/m0/T-005
URL="$(../../tools/dev-db.sh url)"
PW="$(cat ../../deploy/secrets.dev/db_password)"
mask() { sed -e "s#${PW}#***#g"; }
unset CARDFLOW_TEST_MIGRATION_TARGET
DB=cardflow_test_t005_0002_evidence
DB_URL="${URL%/*}/${DB}"
SHOWN_URL="$(printf '%s' "$DB_URL" | mask)"
NOPW_URL="${DB_URL/:${PW}@/@}"
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
head_rev() { uv run python -c "from cardflow.db.migrations import head_revisions; print(','.join(head_revisions()))"; }
STATE_DIR="$(mktemp -d)"
trap 'rm -rf "$STATE_DIR"' EXIT

# state LABEL [OTHER_LABEL]: catalog summary of $DB; with OTHER_LABEL, compare with that state.
state() {
  EVIDENCE_DB_URL="$DB_URL" uv run python - "$STATE_DIR" "$@" <<'PY'
import hashlib
import json
import os
import sys
from pathlib import Path

from sqlalchemy import text
from sqlalchemy.pool import NullPool

from cardflow.db import normalize_database_url
from cardflow.db.engine import create_engine

state_dir, label, *other = sys.argv[1:]
SECTIONS = {
    "constraints": """SELECT c.relname || '.' || con.conname,
        con.contype::text || ' ' || pg_get_constraintdef(con.oid)
        FROM pg_constraint con JOIN pg_class c ON c.oid = con.conrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public'""",
    "indexes": """SELECT tablename || '.' || indexname, indexdef
        FROM pg_indexes WHERE schemaname = 'public'""",
    "columns": """SELECT c.relname || '.' || a.attname, format_type(a.atttypid, a.atttypmod)
        || ' ' || a.attnotnull::text || ' ' || coalesce(pg_get_expr(d.adbin, d.adrelid), '')
        || ' / ' || coalesce(col_description(c.oid, a.attnum), '')
        FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
        WHERE n.nspname = 'public' AND c.relkind = 'r' AND a.attnum > 0
          AND NOT a.attisdropped""",
    "triggers": """SELECT c.relname || '.' || t.tgname,
        pg_get_triggerdef(t.oid) || ' -- enabled=' || t.tgenabled::text
        FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND NOT t.tgisinternal""",
    "functions": """SELECT p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
        md5(p.prosrc) || ' ' || coalesce(array_to_string(p.proconfig, ','), '')
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND NOT EXISTS
          (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e')""",
}
engine = create_engine(normalize_database_url(os.environ["EVIDENCE_DB_URL"]), poolclass=NullPool)
with engine.connect() as connection:
    catalog = {
        name: {k: v for k, v in connection.execute(text(sql)) if not k.startswith("alembic_version.")}
        for name, sql in SECTIONS.items()
    }
    tables = sorted(
        connection.execute(
            text("SELECT tablename FROM pg_tables WHERE schemaname = 'public'")
        ).scalars()
    )
    extensions = sorted(connection.execute(text("SELECT extname FROM pg_extension")).scalars())
    revision = "(no alembic_version table)"
    if "alembic_version" in tables:
        found = connection.execute(text("SELECT version_num FROM alembic_version")).scalars()
        revision = ",".join(found) or "(empty)"
    seed = (
        connection.execute(text("SELECT code, minor_digits FROM currencies ORDER BY code")).all()
        if "currencies" in tables
        else []
    )
engine.dispose()
catalog["meta"] = {
    "revision": revision,
    "extensions": ",".join(extensions),
    "currencies": json.dumps([list(row) for row in seed]),
}
Path(state_dir, f"{label}.json").write_text(json.dumps(catalog, sort_keys=True))
fingerprint = hashlib.md5(json.dumps(catalog, sort_keys=True).encode(), usedforsecurity=False)
user_tables = [t for t in tables if t != "alembic_version"]
counts = "  ".join(f"{name} {len(catalog[name])}" for name in SECTIONS)
print(f"## state {label}: alembic_version {revision}")
print(f"   tables {len(user_tables)} (+alembic_version: {'yes' if 'alembic_version' in tables else 'no'})  {counts}")
print(f"   extensions {','.join(extensions)}  currencies {len(seed)} rows")
print(f"   catalog fingerprint {fingerprint.hexdigest()}")
if other:
    theirs = json.loads(Path(state_dir, f"{other[0]}.json").read_text())
    differences = {
        section: sorted(
            key
            for key in set(catalog[section]) | set(theirs[section])
            if catalog[section].get(key) != theirs[section].get(key)
        )
        for section in catalog
    }
    differences = {section: keys for section, keys in differences.items() if keys}
    bookkeeping = {catalog["meta"]["revision"], theirs["meta"]["revision"]}
    if differences == {"meta": ["revision"]} and bookkeeping == {
        "(empty)",
        "(no alembic_version table)",
    }:
        print(f"   identical to state {other[0]}: yes, apart from the empty alembic_version")
        print("   table that Alembic keeps after downgrade base")
    elif differences:
        print(f"   identical to state {other[0]}: NO -> {json.dumps(differences)[:2000]}")
    else:
        print(f"   identical to state {other[0]}: yes (every constraint, index, column, trigger,")
        print("   function, extension, version row and seed row)")
PY
}

alembic_step() {
  echo "\$ uv run alembic -x url=$SHOWN_URL $*"
  uv run alembic -x "url=$DB_URL" "$@"
  echo "exit=$?"
}

# --- 1. Alembic round trips 0001 <-> 0002 and base <-> head on a fresh database -------------
{
  echo "# T-005 0002-alembic.txt - generated $(now) on cardflow-dev (127.0.0.1:18432), working dir services/api"
  echo "# Fresh database $DB; the database password is masked as *** everywhere."
  echo "\$ tools/dev-db.sh psql -c 'CREATE DATABASE $DB TEMPLATE template0'"
  ../../tools/dev-db.sh psql -c "CREATE DATABASE $DB TEMPLATE template0"
  state empty
  echo '$ uv run alembic heads'
  uv run alembic heads
  echo '$ uv run alembic history --verbose'
  uv run alembic history --verbose
  echo
  echo "# --- 0001 <-> 0002 ---"
  alembic_step upgrade 0001
  state at-0001
  alembic_step upgrade 0002
  state at-0002
  alembic_step downgrade 0001
  state back-at-0001 at-0001
  alembic_step upgrade 0002
  state again-at-0002 at-0002
  echo
  echo "# --- base <-> head (twice) ---"
  alembic_step downgrade base
  state at-base empty
  alembic_step upgrade head
  state head-from-base at-0002
  alembic_step downgrade base
  state at-base-again at-base
  alembic_step upgrade head
  state head-again at-0002
  alembic_step current
  echo
  echo "# --- cardflow migrate (settings from env: DATABASE_URL without password + DATABASE_PASSWORD_FILE) ---"
  echo "\$ export DATABASE_URL=$NOPW_URL DATABASE_PASSWORD_FILE=../../deploy/secrets.dev/db_password LOG_FORMAT=text"
  export DATABASE_URL="$NOPW_URL" DATABASE_PASSWORD_FILE=../../deploy/secrets.dev/db_password LOG_FORMAT=text
  echo '$ uv run cardflow migrate --check        # database at head'
  uv run cardflow migrate --check; echo "exit=$?"
  alembic_step downgrade -1
  echo '$ uv run cardflow migrate --check        # one revision below head'
  uv run cardflow migrate --check; echo "exit=$?"
  echo '$ uv run cardflow migrate --lock         # upgrade under the advisory lock'
  uv run cardflow migrate --lock; echo "exit=$?"
  echo '$ uv run cardflow migrate --check        # back at head'
  uv run cardflow migrate --check; echo "exit=$?"
  unset DATABASE_URL DATABASE_PASSWORD_FILE LOG_FORMAT
  state final at-0002
} 2>&1 | mask | tee "$EV/0002-alembic.txt"

{
  echo "-- \$ docker exec cardflow-dev-db-1 pg_dump -U cardflow --schema-only -d $DB"
  echo "-- (temporary database at head $(head_rev), built by evidence/m0/T-005/0002-commands.sh; dropped afterwards)"
  docker exec cardflow-dev-db-1 pg_dump -U cardflow --schema-only -d "$DB"
} 2>&1 | mask >"$EV/0002-schema.sql"
{
  echo "\$ tools/dev-db.sh psql -c 'DROP DATABASE $DB'"
  ../../tools/dev-db.sh psql -c "DROP DATABASE $DB"
} 2>&1 | mask | tee -a "$EV/0002-alembic.txt"

# --- 2. ruff -------------------------------------------------------------------------------
{
  echo "# T-005 0002-ruff.txt - $(now), working dir services/api"
  echo '$ uv run ruff check .'
  uv run ruff check .; echo "exit=$?"
  echo '$ uv run ruff format --check .'
  uv run ruff format --check .; echo "exit=$?"
} 2>&1 | mask | tee "$EV/0002-ruff.txt"

# --- 3. full test suite at head, tests/db verbose, and the 0001 development switch ----------
{
  echo "# T-005 0002-pytest.txt - $(now), working dir services/api, dev DB 127.0.0.1:18432, schema at Alembic head $(head_rev) (CARDFLOW_TEST_MIGRATION_TARGET unset)"
  echo '$ CARDFLOW_TEST_DATABASE_URL="$(../../tools/dev-db.sh url)" uv run pytest -q -p no:cacheprovider'
  CARDFLOW_TEST_DATABASE_URL="$URL" uv run pytest -q -p no:cacheprovider; echo "exit=$?"
  echo
  echo "# collected tests per directory/file (uv run pytest --co -q | aggregated):"
  uv run pytest --co -q -p no:cacheprovider 2>/dev/null | grep '::' | cut -d: -f1 | sed -E 's#^(tests/[^/]+)/.*#\1#' | sort | uniq -c
} 2>&1 | mask | tee "$EV/0002-pytest.txt"

{
  echo "# T-005 0002-pytest-db.txt - $(now), working dir services/api, schema at Alembic head $(head_rev): every schema test by name"
  echo '$ CARDFLOW_TEST_DATABASE_URL="$(../../tools/dev-db.sh url)" uv run pytest tests/db -v -p no:cacheprovider'
  CARDFLOW_TEST_DATABASE_URL="$URL" uv run pytest tests/db -v -p no:cacheprovider; echo "exit=$?"
} 2>&1 | mask | tee "$EV/0002-pytest-db.txt"

{
  echo "# T-005 0002-pytest-target-0001.txt - $(now), working dir services/api: development switch CARDFLOW_TEST_MIGRATION_TARGET=0001"
  echo "# (session schema at 0001; tests bound to head are SKIPPED with their reason, -rs)"
  echo '$ CARDFLOW_TEST_MIGRATION_TARGET=0001 CARDFLOW_TEST_DATABASE_URL="$(../../tools/dev-db.sh url)" uv run pytest -q -rs -p no:cacheprovider'
  CARDFLOW_TEST_MIGRATION_TARGET=0001 CARDFLOW_TEST_DATABASE_URL="$URL" uv run pytest -q -rs -p no:cacheprovider; echo "exit=$?"
} 2>&1 | mask | tee "$EV/0002-pytest-target-0001.txt"

# --- 4. T-008: the tests/jobs blocks of evidence/m0/T-008/commands.sh, re-run at head -------
{
  echo "# T-008 tests/jobs re-run at Alembic head $(head_rev) for the 0002 round - $(now), working dir services/api, dev DB 127.0.0.1:18432"
  echo "# (the tests/jobs blocks of evidence/m0/T-008/commands.sh; CARDFLOW_TEST_MIGRATION_TARGET unset)"
  echo '$ CARDFLOW_TEST_DATABASE_URL="$(../../tools/dev-db.sh url)" uv run pytest tests/jobs -v'
  CARDFLOW_TEST_DATABASE_URL="$URL" uv run pytest tests/jobs -v -p no:cacheprovider; echo "exit=$?"
  echo
  echo '$ CARDFLOW_TEST_DATABASE_URL="$(../../tools/dev-db.sh url)" uv run pytest tests/jobs/test_concurrency.py -v -s'
  CARDFLOW_TEST_DATABASE_URL="$URL" uv run pytest tests/jobs/test_concurrency.py -v -s -p no:cacheprovider; echo "exit=$?"
  echo
  echo '$ CARDFLOW_TEST_DATABASE_URL="$(../../tools/dev-db.sh url)" uv run pytest tests/jobs -v -s -k "timeout or sigterm or crash or cannot_start or grace or second"'
  CARDFLOW_TEST_DATABASE_URL="$URL" uv run pytest tests/jobs -v -s -p no:cacheprovider -k "timeout or sigterm or crash or cannot_start or grace or second"; echo "exit=$?"
} 2>&1 | mask | tee "$EV/0002-t008-jobs.txt"

# --- 5. Query plans of the worker's claim and reclaim queries at 0001 and at head -----------
{
  echo "# T-005 0002-jobs-plans.txt - $(now): EXPLAIN (COSTS OFF) of cardflow.jobs.queue claim/reclaim"
  echo "# queries on fresh databases at 0001 and at head, sequential and bitmap scans disabled"
  echo '$ CARDFLOW_TEST_DATABASE_URL="$(../../tools/dev-db.sh url)" uv run python - <<PY ... (inline in 0002-commands.sh)'
  CARDFLOW_TEST_DATABASE_URL="$URL" uv run python - <<'PY'
import os
import secrets
import sys

from sqlalchemy import text
from sqlalchemy.pool import NullPool

from cardflow.db import normalize_database_url
from cardflow.db.engine import create_engine
from cardflow.db.migrations import upgrade
from cardflow.jobs.queue import _SELECT_CLAIMABLE, _SELECT_EXPIRED

admin_url = normalize_database_url(os.environ["CARDFLOW_TEST_DATABASE_URL"])
admin = create_engine(admin_url, poolclass=NullPool).execution_options(isolation_level="AUTOCOMMIT")
QUERIES = (
    ("claim", _SELECT_CLAIMABLE, {"kinds": "ARRAY['demo.echo']::text[]", "limit": "10"}),
    ("reclaim", _SELECT_EXPIRED, {"limit": "10"}),
)
for target in ("0001", "head"):
    name = f"cardflow_test_{secrets.token_hex(6)}"
    with admin.connect() as connection:
        connection.execute(text(f"CREATE DATABASE {name} TEMPLATE template0"))
    try:
        url = admin_url.set(database=name)
        upgrade(url, target)
        engine = create_engine(url, poolclass=NullPool)
        for label, query, values in QUERIES:
            sql = query.text
            for key, literal in values.items():
                sql = sql.replace(f":{key}", literal)
            with engine.connect() as connection, connection.begin() as transaction:
                connection.execute(text("SET LOCAL enable_seqscan = off"))
                connection.execute(text("SET LOCAL enable_bitmapscan = off"))
                plan = connection.execute(text(f"EXPLAIN (COSTS OFF) {sql}")).scalars().all()
                transaction.rollback()
            sys.stdout.write(f"--- {label} query at {target}:\n{sql.strip()}\n")
            sys.stdout.write("\n".join(plan) + "\n\n")
        engine.dispose()
    finally:
        with admin.connect() as connection:
            connection.execute(text(f"DROP DATABASE {name}"))
admin.dispose()
PY
  echo "exit=$?"
} 2>&1 | grep -v "^INFO  \[alembic" | mask | tee "$EV/0002-jobs-plans.txt"

# --- 6. R2-24 mutation run: the review's undetected mutations M5/M6/M8 at head --------------
{
  echo "# T-005 0002-mutations.txt - $(now): each mutation is applied to a throw-away copy of services/api"
  echo "# (appended to 0002's UPGRADE list, or patched into the function body) and tests/db runs there."
  echo "# The review found M5/M6/M8 undetected by the 0001 suite (77 passed); every one must fail now."
  CARDFLOW_TEST_DATABASE_URL="$URL" uv run python - <<'PY'
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SOURCE = Path.cwd()
MUTATIONS = {
    "none": None,
    "M5 card_products workspace guard fires on UPDATE OF name": [
        "DROP TRIGGER card_products_workspace_immutable ON card_products",
        "CREATE TRIGGER card_products_workspace_immutable BEFORE UPDATE OF name ON card_products "
        "FOR EACH ROW EXECUTE FUNCTION forbid_workspace_change()",
    ],
    "M6 credit_pools scope trigger only on INSERT": [
        "DROP TRIGGER credit_pools_bank_scope ON credit_pools",
        "CREATE TRIGGER credit_pools_bank_scope BEFORE INSERT ON credit_pools "
        "FOR EACH ROW EXECUTE FUNCTION check_template_scope('bank_id', 'banks')",
    ],
    "M8 currency_account subject branch without workspace check": (
        "SELECT 1 FROM public.currency_accounts AS c\n"
        "             WHERE c.id = NEW.subject_id AND c.workspace_id = NEW.workspace_id",
        "SELECT 1 FROM public.currency_accounts AS c\n             WHERE c.id = NEW.subject_id",
    ),
}
ignore = shutil.ignore_patterns(".venv", "__pycache__", ".pytest_cache", ".ruff_cache")
for label, mutation in MUTATIONS.items():
    with tempfile.TemporaryDirectory(prefix="cardflow-t005-mut-") as tmp:
        root = Path(tmp) / "api"
        shutil.copytree(SOURCE, root, ignore=ignore)
        migration = root / "alembic" / "versions" / "0002_schema_fixes.py"
        source = migration.read_text(encoding="utf-8")
        if isinstance(mutation, list):
            source += f"\nUPGRADE.extend({mutation!r})\n"
        elif isinstance(mutation, tuple):
            assert source.count(mutation[0]) == 1
            source = source.replace(mutation[0], mutation[1])
        migration.write_text(source, encoding="utf-8")
        result = subprocess.run(  # noqa: S603
            [sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider", "-rf", "tests/db"],
            cwd=root,
            env=dict(os.environ, PYTHONPATH=str(root)),
            capture_output=True,
            text=True,
            check=False,
        )
        lines = result.stdout.strip().splitlines()
        failed = sorted(set(re.findall(r"^FAILED (\S+)", result.stdout, re.MULTILINE)))
        sys.stdout.write(f"=== mutation {label}: {lines[-1] if lines else '(no output)'}\n")
        for test in failed:
            sys.stdout.write(f"    FAILED {test}\n")
        sys.stdout.flush()
PY
  echo "exit=$?"
} 2>&1 | mask | tee "$EV/0002-mutations.txt"

# --- 7. Privileges a writing role needs at head (input for T-006) ---------------------------
{
  echo "# T-005 0002-privileges.txt - $(now): scratch database at head + temporary non-superuser LOGIN"
  echo "# role (random name and password, dropped at the end); each attempt grants exactly the listed"
  echo "# privileges, then runs one write as that role in its own transaction."
  CARDFLOW_TEST_DATABASE_URL="$URL" uv run python - <<'PY'
import os
import secrets
import sys
from collections.abc import Callable
from datetime import date

from sqlalchemy import text
from sqlalchemy.engine import Connection
from sqlalchemy.exc import DBAPIError
from sqlalchemy.pool import NullPool

from cardflow.db import normalize_database_url
from cardflow.db.engine import create_engine
from cardflow.db.migrations import upgrade

admin_url = normalize_database_url(os.environ["CARDFLOW_TEST_DATABASE_URL"])
admin = create_engine(admin_url, poolclass=NullPool).execution_options(isolation_level="AUTOCOMMIT")
name = f"cardflow_test_{secrets.token_hex(6)}"
role = f"cardflow_test_role_{secrets.token_hex(4)}"
password = secrets.token_hex(16)
with admin.connect() as c:
    c.execute(text(f"CREATE DATABASE {name} TEMPLATE template0"))
    c.execute(text(f"CREATE ROLE {role} LOGIN PASSWORD '{password}' NOSUPERUSER NOBYPASSRLS"))
url = admin_url.set(database=name)
try:
    upgrade(url, "head")
    owner = create_engine(url, poolclass=NullPool)
    with owner.begin() as c:
        def one(sql: str, **params: object) -> object:
            return c.execute(text(sql), params).scalar_one()

        user = one("INSERT INTO users DEFAULT VALUES RETURNING id")
        ws = one("INSERT INTO workspaces (owner_user_id, kind) VALUES (:u, 'real') RETURNING id", u=user)
        bank = one("INSERT INTO banks (name) VALUES ('b') RETURNING id")
        ca = one(
            "INSERT INTO credit_accounts (workspace_id, bank_id, holder_alias, status) "
            "VALUES (:w, :b, 'me', 'active') RETURNING id", w=ws, b=bank,
        )
        cur = one(
            "INSERT INTO currency_accounts (workspace_id, credit_account_id, currency) "
            "VALUES (:w, :c, 'CNY') RETURNING id", w=ws, c=ca,
        )
        st = one(
            "INSERT INTO statements (workspace_id, currency_account_id, statement_date, due_date, "
            "status) VALUES (:w, :c, :d, :e, 'issued') RETURNING id",
            w=ws, c=cur, d=date(2026, 11, 10), e=date(2026, 11, 28),
        )
        rp = one(
            "INSERT INTO repayments (workspace_id, currency_account_id, amount_minor, currency, "
            "status) VALUES (:w, :c, 1000, 'CNY', 'recorded') RETURNING id", w=ws, c=cur,
        )
        c.execute(text(f"GRANT USAGE ON SCHEMA public TO {role}"))

    def allocate(c: Connection) -> None:
        c.execute(
            text(
                "INSERT INTO repayment_allocations (workspace_id, repayment_id, statement_id, "
                "amount_minor) VALUES (:w, :r, :s, 100)"
            ),
            {"w": ws, "r": rp, "s": st},
        )

    def rename(alias: str) -> Callable[[Connection], None]:
        def action(c: Connection) -> None:
            c.execute(
                text("UPDATE credit_accounts SET holder_alias = :v WHERE id = :c"),
                {"v": alias, "c": ca},
            )

        return action

    def version_with_line(version_no: int) -> Callable[[Connection], None]:
        def action(c: Connection) -> None:
            version = c.execute(
                text(
                    "INSERT INTO statement_versions (workspace_id, statement_id, version_no, "
                    "source_kind, previous_balance_minor, new_balance_minor, min_due_minor, "
                    "payments_minor, credits_minor, fees_minor, interest_minor, "
                    "installment_due_minor, credit_balance_minor, due_date, recorded_by) "
                    "VALUES (:w, :s, :n, 'pdf', 0, 100, 10, 0, 0, 0, 0, 0, 0, :d, 'import') "
                    "RETURNING id"
                ),
                {"w": ws, "s": st, "n": version_no, "d": date(2026, 11, 28)},
            ).scalar_one()
            c.execute(
                text(
                    "INSERT INTO statement_lines (workspace_id, statement_version_id, line_no, "
                    "kind, description, amount_minor) VALUES (:w, :v, 1, 'purchase', 'COFFEE', 100)"
                ),
                {"w": ws, "v": version},
            )

        return action

    def attempt(
        label: str,
        grants: list[str],
        revoke_execute: list[str],
        action: Callable[[Connection], None],
    ) -> None:
        with owner.begin() as c:
            c.execute(text(f"REVOKE ALL ON ALL TABLES IN SCHEMA public FROM {role}"))
            c.execute(text("GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO PUBLIC"))
            for grant in grants:
                c.execute(text(f"{grant} TO {role}"))
            for signature in revoke_execute:
                c.execute(text(f"REVOKE EXECUTE ON FUNCTION {signature} FROM PUBLIC"))
        engine = create_engine(url.set(username=role, password=password), poolclass=NullPool)
        outcome = "OK (committed)"
        try:
            with engine.begin() as c:
                action(c)
        except DBAPIError as exc:
            outcome = f"{exc.orig.sqlstate}: {str(exc.orig).splitlines()[0]}"
        finally:
            engine.dispose()
        sys.stdout.write(f"{label}\n    -> {outcome}\n")
        with owner.begin() as c:
            c.execute(text("DELETE FROM repayment_allocations"))

    base = [
        "GRANT SELECT, INSERT ON repayment_allocations",
        "GRANT SELECT ON repayments, statements, currency_accounts",
    ]
    totals = "GRANT SELECT, INSERT, UPDATE ON repayment_allocation_totals"
    everything = "GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public"
    sys.stdout.write("## table privileges for INSERT INTO repayment_allocations\n")
    attempt("1) INSERT on allocations, SELECT on repayments; nothing on repayment_allocation_totals",
            base, [], allocate)
    attempt("2) + SELECT, INSERT, UPDATE on repayment_allocation_totals; no UPDATE on repayments",
            [*base, totals], [], allocate)
    attempt("3) + UPDATE on repayments (row lock SELECT ... FOR NO KEY UPDATE in the check)",
            [*base, totals, "GRANT UPDATE ON repayments"], [], allocate)
    attempt("4) as 3) with column-level UPDATE (status) on repayments only",
            [*base, totals, "GRANT UPDATE (status) ON repayments"], [], allocate)
    attempt("5) as 3) but INSERT, UPDATE on repayment_allocation_totals without SELECT",
            [*base, "GRANT INSERT, UPDATE ON repayment_allocation_totals", "GRANT UPDATE ON repayments"],
            [], allocate)
    sys.stdout.write("## EXECUTE privileges (role has SELECT, INSERT, UPDATE on every table)\n")
    attempt("A) EXECUTE on every function (default PUBLIC grant)", [everything], [], allocate)
    attempt("B) no EXECUTE on the trigger function maintain_repayment_allocation_totals()",
            [everything], ["public.maintain_repayment_allocation_totals()"], allocate)
    attempt("C) no EXECUTE on add_to_repayment_allocation_total(uuid, uuid, bigint) (called by B)",
            [everything], ["public.add_to_repayment_allocation_total(uuid, uuid, bigint)"], allocate)
    attempt("D) no EXECUTE on check_repayment_allocations(uuid) (called by the deferred check)",
            [everything], ["public.check_repayment_allocations(uuid)"], allocate)
    attempt("E) no EXECUTE on looks_like_pan(text) (CHECK on credit_accounts.holder_alias)",
            [everything], ["public.looks_like_pan(text)"], rename("me too"))
    attempt("F) no EXECUTE on luhn_valid(text) (called by looks_like_pan for a 16-digit run)",
            [everything], ["public.luhn_valid(text)"], rename("card 4111 1111 1111 1112"))
    attempt("G) EXECUTE everywhere, Luhn-valid 16-digit run",
            [everything], [], rename("card 4111 1111 1111 1111"))
    attempt("H) EXECUTE everywhere: statement version + its line in one transaction",
            [everything], [], version_with_line(1))
    attempt("I) no EXECUTE on inserted_by_current_transaction(xid) (called by the line trigger)",
            [everything], ["public.inserted_by_current_transaction(xid)"], version_with_line(2))
    owner.dispose()
finally:
    with admin.connect() as c:
        c.execute(text(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"))
        c.execute(text(f"DROP ROLE IF EXISTS {role}"))
    admin.dispose()
sys.stdout.write("scratch database and role dropped\n")
PY
  echo "exit=$?"
} 2>&1 | mask | tee "$EV/0002-privileges.txt"
