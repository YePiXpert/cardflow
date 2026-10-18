#!/usr/bin/env bash
# T-006 (migration 0003: roles, grants, row-level security, admin views) - evidence run.
# Working dir services/api; dev DB cardflow-dev on 127.0.0.1:18432 (never 5432). Every
# output passes through mask(), which replaces the superuser password and the demo login
# passwords with ***. Temporary databases (cardflow_test_t006_*) and the demo login roles
# are dropped at the end of their section; the group roles of 0003 stay (cluster-wide by
# design, see the migration docstring).
set -u
cd /projects/cardflow/services/api
EV=/projects/cardflow/evidence/m0/T-006
URL="$(../../tools/dev-db.sh url)"
PW="$(cat ../../deploy/secrets.dev/db_password)"
DEMO_DIR="$(mktemp -d)"
trap 'rm -rf "$DEMO_DIR"' EXIT
chmod 700 "$DEMO_DIR"
for name in api worker admin; do
  (umask 077 && od -An -N18 -tx1 /dev/urandom | tr -d ' \n' >"$DEMO_DIR/db_${name}_password")
done
DEMO_PW_API="$(cat "$DEMO_DIR/db_api_password")"
DEMO_PW_WORKER="$(cat "$DEMO_DIR/db_worker_password")"
DEMO_PW_ADMIN="$(cat "$DEMO_DIR/db_admin_password")"
mask() {
  sed -e "s#${PW}#***#g" -e "s#${DEMO_PW_API}#***#g" -e "s#${DEMO_PW_WORKER}#***#g" \
      -e "s#${DEMO_PW_ADMIN}#***#g"
}
unset CARDFLOW_TEST_MIGRATION_TARGET
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
head_rev() { uv run python -c "from cardflow.db.migrations import head_revisions; print(','.join(head_revisions()))"; }
export EVIDENCE_ADMIN_URL="$URL"

# ---------------------------------------------------------------------------------- ruff
{
  echo "# T-006 ruff - $(now), working dir services/api"
  echo '$ uv run ruff check .'
  uv run ruff check .; echo "exit=$?"
  echo '$ uv run ruff format --check .'
  uv run ruff format --check .; echo "exit=$?"
} 2>&1 | mask | tee "$EV/ruff.txt"

# ------------------------------------------------------------------------------- alembic
{
  echo "# T-006 migration round trips - $(now), working dir services/api, dev DB 127.0.0.1:18432"
  echo "# scratch database cardflow_test_t006_evidence (dropped at the end); catalog = the same"
  echo "# normalised snapshot the tests compare (tests/db/conftest.py: catalog()), incl. RLS flags,"
  echo "# policies, ACLs of relations/columns/functions/schemas/database (NULL ACL == default), views."
  uv run python - <<'PY'
import importlib.util
import os
import sys
from pathlib import Path

from sqlalchemy import text
from sqlalchemy.pool import NullPool

from cardflow.db.engine import create_engine, normalize_database_url
from cardflow.db.migrations import downgrade, upgrade

spec = importlib.util.spec_from_file_location("t006_conftest", Path("tests/db/conftest.py"))
conftest = importlib.util.module_from_spec(spec)
sys.modules["t006_conftest"] = conftest
spec.loader.exec_module(conftest)

admin_url = normalize_database_url(os.environ["EVIDENCE_ADMIN_URL"])
name = "cardflow_test_t006_evidence"
admin = create_engine(admin_url, poolclass=NullPool).execution_options(isolation_level="AUTOCOMMIT")
with admin.connect() as c:
    c.execute(text(f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)'))
    c.execute(text(f'CREATE DATABASE "{name}" TEMPLATE template0'))
url = admin_url.set(database=name)
engine = create_engine(url, poolclass=NullPool)


def state():
    with engine.connect() as c:
        snapshot = {
            section: {k: v for k, v in entries.items() if not k.startswith("alembic_version.")}
            for section, entries in conftest.catalog(c).items()
        }
        tables = set(c.execute(text("SELECT tablename FROM pg_tables WHERE schemaname='public'")).scalars())
        revision = ",".join(c.execute(text("SELECT version_num FROM alembic_version")).scalars()) if "alembic_version" in tables else "(none)"
    snapshot["meta"] = {"revision": revision}
    return snapshot


def sizes(snapshot):
    return ", ".join(f"{k}={len(v)}" for k, v in snapshot.items() if k != "meta")


def diff(a, b):
    found = {}
    for section in sorted(set(a) | set(b)):
        x, y = a.get(section, {}), b.get(section, {})
        delta = (sorted(set(x) - set(y)), sorted(set(y) - set(x)), sorted(k for k in set(x) & set(y) if x[k] != y[k]))
        if any(delta):
            found[section] = delta
    return found or "none"


def summary(label):
    with engine.connect() as c:
        q = lambda sql: c.execute(text(sql)).all()  # noqa: E731
        print(f"--- {label}")
        print("revision:", ",".join(r[0] for r in q("SELECT version_num FROM alembic_version")) if q("SELECT to_regclass('alembic_version') IS NOT NULL")[0][0] else "(none)")
        print("extensions:", ",".join(sorted(r[0] for r in q("SELECT extname FROM pg_extension"))))
        print("cardflow group roles (cluster):", ", ".join(f"{r[0]}(login={r[1]},super={r[2]},bypassrls={r[3]})" for r in q("SELECT rolname, rolcanlogin, rolsuper, rolbypassrls FROM pg_roles WHERE rolname IN ('cardflow_app','cardflow_worker','cardflow_admin','cardflow_purge','cardflow_admin_views') ORDER BY 1")))
        print("tables with RLS enabled+forced:", q("SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r' AND c.relrowsecurity AND c.relforcerowsecurity")[0][0])
        print("policies:", q("SELECT count(*) FROM pg_policies")[0][0])
        print("schema admin views:", ",".join(r[0] for r in q("SELECT viewname FROM pg_views WHERE schemaname='admin' ORDER BY 1")) or "-")
        print("PUBLIC TEMP on database:", q("SELECT has_database_privilege('public', current_database(), 'TEMPORARY')")[0][0])
        print("PUBLIC USAGE on schema public:", q("SELECT has_schema_privilege('public', 'public', 'USAGE')")[0][0])
        if q("SELECT to_regclass('jobs') IS NOT NULL")[0][0]:
            print("ck_jobs_status:", q("SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname='ck_jobs_status'")[0][0])
            print("jobs rows by status:", dict(q("SELECT status, count(*) FROM jobs GROUP BY status ORDER BY 1")))


try:
    print("$ upgrade 0002"); upgrade(url, "0002")
    with engine.begin() as c:  # a job row with 0002's spelling, to show the rename both ways
        c.execute(text("INSERT INTO jobs (kind, payload, status) VALUES ('evidence.probe', '{}', 'canceled')"))
    summary("at 0002"); s2 = state(); print("catalog sections:", sizes(s2))
    print("$ upgrade 0003 (head)"); upgrade(url, "0003")
    summary("at 0003"); s3 = state(); print("catalog sections:", sizes(s3))
    for round_no in (1, 2):
        print(f"$ downgrade 0002 (round {round_no})"); downgrade(url, "0002")
        print("  differences vs the 0002 catalog:", diff(state(), s2))
        print(f"$ upgrade 0003 (round {round_no})"); upgrade(url, "0003")
        print("  differences vs the first 0003 catalog:", diff(state(), s3))
    summary("after 0002<->0003 x2")
    with engine.begin() as c:  # 0001 knows no 'cancelled'/'canceled' job: remove the probe first
        c.execute(text("DELETE FROM jobs WHERE kind = 'evidence.probe'"))
    print("$ downgrade base"); downgrade(url, "base"); summary("at base (extensions are an environment prerequisite, R2-23)")
    with engine.connect() as c:
        print("public tables at base:", sorted(c.execute(text("SELECT tablename FROM pg_tables WHERE schemaname='public'")).scalars()))
    print("$ upgrade head"); upgrade(url, "head")
    print("  differences vs the first 0003 catalog (jobs row gone with the table):", diff(state(), s3))
    print("$ downgrade base / upgrade head (repeat)"); downgrade(url, "base"); upgrade(url, "head")
    print("  differences vs the first 0003 catalog:", diff(state(), s3))
finally:
    engine.dispose()
PY
  echo "exit=$?"
  echo
  NOPW="${URL/:${PW}@/@}"
  echo "\$ DATABASE_URL=<superuser, no password>/cardflow_test_t006_evidence DATABASE_PASSWORD_FILE=<secret> uv run cardflow migrate --check"
  DATABASE_URL="${NOPW%/*}/cardflow_test_t006_evidence" DATABASE_PASSWORD_FILE=../../deploy/secrets.dev/db_password LOG_FORMAT=text uv run cardflow migrate --check; echo "exit=$?"
  uv run python - <<'PY'
import os
from sqlalchemy import text
from sqlalchemy.pool import NullPool
from cardflow.db.engine import create_engine, normalize_database_url
admin = create_engine(normalize_database_url(os.environ["EVIDENCE_ADMIN_URL"]), poolclass=NullPool).execution_options(isolation_level="AUTOCOMMIT")
with admin.connect() as c:
    c.execute(text('DROP DATABASE IF EXISTS "cardflow_test_t006_evidence" WITH (FORCE)'))
    print("scratch database dropped; remaining:", sorted(c.execute(text("SELECT datname FROM pg_database")).scalars()))
PY
} 2>&1 | mask | tee "$EV/alembic.txt"

# ------------------------------------------------------------------------- golden update
{
  echo "# T-006 golden manifest update - $(now), working dir services/api, head $(head_rev)"
  echo "# golden_objects.json before T-006 (T-005 revision round): sha256 $(sha256sum /projects/cardflow/evidence/m0/T-006/golden_objects.before-T-006.json | cut -d' ' -f1)"
  echo '$ CARDFLOW_UPDATE_GOLDEN=1 CARDFLOW_TEST_DATABASE_URL="$(../../tools/dev-db.sh url)" uv run pytest tests/db/test_db_objects.py -q -rs'
  CARDFLOW_UPDATE_GOLDEN=1 CARDFLOW_TEST_DATABASE_URL="$URL" uv run pytest tests/db/test_db_objects.py -q -rs -p no:cacheprovider; echo "exit=$?"
  echo "# golden_objects.json after: sha256 $(sha256sum tests/db/golden_objects.json | cut -d' ' -f1)"
  echo '$ CARDFLOW_TEST_DATABASE_URL="$(../../tools/dev-db.sh url)" uv run pytest tests/db/test_db_objects.py -q   # compare mode'
  CARDFLOW_TEST_DATABASE_URL="$URL" uv run pytest tests/db/test_db_objects.py -q -p no:cacheprovider; echo "exit=$?"
  echo "# entry-by-entry difference (before -> after):"
  uv run python - <<'PY'
import json
before = json.load(open("/projects/cardflow/evidence/m0/T-006/golden_objects.before-T-006.json"))
after = json.load(open("tests/db/golden_objects.json"))
print("revisions before:", sorted(before), "after:", sorted(after))
for revision in sorted(set(before) | set(after)):
    b = before.get(revision, {"triggers": {}, "functions": {}})
    a = after.get(revision, {"triggers": {}, "functions": {}})
    for section in ("triggers", "functions"):
        added = sorted(set(a[section]) - set(b[section]))
        removed = sorted(set(b[section]) - set(a[section]))
        changed = sorted(k for k in set(a[section]) & set(b[section]) if a[section][k] != b[section][k])
        print(f"[{revision}] {section}: added {len(added)}, removed {len(removed)}, changed {len(changed)}")
print("new entry 0003 compared with 0002 (what revision 0003 changes in triggers/functions):")
for section in ("triggers", "functions"):
    x, y = after["0002"][section], after["0003"][section]
    print(f"  {section}: only in 0003 {sorted(set(y) - set(x))}; only in 0002 {sorted(set(x) - set(y))}")
    for key in sorted(set(x) & set(y)):
        if x[key] != y[key]:
            print(f"  changed {key}:\n      0002: {x[key]}\n      0003: {y[key]}")
print("format change: a SECURITY DEFINER function's fingerprint now ends with ' security_definer'"
      " (tests/db/conftest.py database_objects); 0001/0002 have none, so their entries are unchanged.")
PY
} 2>&1 | mask | tee "$EV/golden-update.txt"

# ----------------------------------------------------------------------------- coverage
{
  uv run python - <<'PY'
import importlib.util
import os
import sys
from collections import defaultdict
from datetime import UTC, datetime
from pathlib import Path

from sqlalchemy import text
from sqlalchemy.pool import NullPool

from cardflow.db.engine import create_engine, normalize_database_url
from cardflow.db.migrations import head_revisions, upgrade

ROLES = ["cardflow_app", "cardflow_worker", "cardflow_admin", "cardflow_purge", "cardflow_admin_views"]
SHORT = {"cardflow_app": "app", "cardflow_worker": "worker", "cardflow_admin": "admin", "cardflow_purge": "purge", "cardflow_admin_views": "admin_views"}
admin_url = normalize_database_url(os.environ["EVIDENCE_ADMIN_URL"])
name = "cardflow_test_t006_coverage"
admin = create_engine(admin_url, poolclass=NullPool).execution_options(isolation_level="AUTOCOMMIT")
with admin.connect() as c:
    c.execute(text(f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)'))
    c.execute(text(f'CREATE DATABASE "{name}" TEMPLATE template0'))
url = admin_url.set(database=name)
out = []
try:
    upgrade(url, "head")
    engine = create_engine(url, poolclass=NullPool)
    with engine.connect() as c:
        q = lambda sql, **p: c.execute(text(sql), p).all()  # noqa: E731
        columns = defaultdict(list)
        for t, col in q("SELECT c.relname, a.attname FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r' AND a.attnum>0 AND NOT a.attisdropped ORDER BY 1, a.attnum"):
            columns[t].append(col)
        rls = {t: (e, f) for t, e, f in q("SELECT c.relname, c.relrowsecurity, c.relforcerowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r'")}
        policies = defaultdict(list)
        for t, pname, cmd, roles, qual, check in q("SELECT tablename, policyname, cmd, roles, qual, with_check FROM pg_policies WHERE schemaname='public' ORDER BY 1, 2"):
            policies[t].append((pname, cmd, [SHORT.get(r, r) for r in roles], qual, check))
        priv = {}
        for role in ROLES:
            for t, col, s, i, u in q("SELECT c.relname, a.attname, has_column_privilege(:r, c.oid, a.attnum, 'SELECT'), has_column_privilege(:r, c.oid, a.attnum, 'INSERT'), has_column_privilege(:r, c.oid, a.attnum, 'UPDATE') FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r' AND a.attnum>0 AND NOT a.attisdropped", r=role):
                priv[(role, t, col)] = (s, i, u)
            for t, d, tr in q("SELECT c.relname, has_table_privilege(:r, c.oid, 'DELETE'), has_table_privilege(:r, c.oid, 'TRUNCATE') FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r'", r=role):
                priv[(role, t, "(delete)")] = d
                assert not tr, (role, t)
        functions = q("SELECT 'public.' || p.proname || '(' || oidvectortypes(p.proargtypes) || ')', p.prosecdef, has_function_privilege('public', p.oid, 'EXECUTE'), ARRAY(SELECT g FROM unnest(CAST(:roles AS text[])) g WHERE has_function_privilege(g, p.oid, 'EXECUTE') ORDER BY g) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid=p.oid AND d.deptype='e') ORDER BY 1", roles=ROLES)
        views = q("SELECT v.viewname, v.viewowner, c.reloptions FROM pg_views v JOIN pg_class c ON c.relname=v.viewname JOIN pg_namespace n ON n.oid=c.relnamespace AND n.nspname=v.schemaname WHERE v.schemaname='admin' ORDER BY 1")
        view_cols = defaultdict(list)
        for v, col in q("SELECT table_name, column_name FROM information_schema.columns WHERE table_schema='admin' ORDER BY table_name, ordinal_position"):
            view_cols[v].append(col)
        seq = q("SELECT r, has_sequence_privilege(r, 'public.sync_changes_seq_seq', 'USAGE') FROM unnest(CAST(:roles AS text[])) r", roles=ROLES)
        dbpriv = q("SELECT r, has_database_privilege(r, current_database(), 'TEMPORARY'), has_database_privilege(r, current_database(), 'CREATE') FROM unnest(CAST(:roles AS text[])) r", roles=["public", *ROLES])
        schema = q("SELECT r, has_schema_privilege(r, 'public', 'USAGE'), has_schema_privilege(r, 'public', 'CREATE'), has_schema_privilege(r, 'admin', 'USAGE') FROM unnest(CAST(:roles AS text[])) r", roles=["public", *ROLES])
    engine.dispose()
finally:
    with admin.connect() as c:
        c.execute(text(f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)'))

def cell(role, t):
    cols = columns[t]
    marks = []
    for idx, letter in ((0, "S"), (1, "I"), (2, "U")):
        granted = [c for c in cols if priv[(role, t, c)][idx]]
        if not granted:
            continue
        marks.append(letter if len(granted) == len(cols) else f"{letter}({len(granted)}/{len(cols)})")
    if priv[(role, t, "(delete)")]:
        marks.append("D")
    return " ".join(marks) or "–"

o = out.append
o("# T-006 · RLS 覆盖清单（表 → RLS 状态 → 策略 → 授权）")
o("")
o(f"由 `evidence/m0/T-006/commands.sh` 在临时库（迁移到 head {','.join(head_revisions())}，生成后删除）上读取系统目录生成，{datetime.now(UTC).strftime('%Y-%m-%dT%H:%M:%SZ')}。权限取 `has_column_privilege` / `has_table_privilege`（即实际生效的权限）。")
o("")
o("图例：S/I/U = SELECT/INSERT/UPDATE；整表授权只写字母，列级授权写“字母(已授列数/总列数)”；D = DELETE；– = 无任何权限。所有角色在所有表上都没有 TRUNCATE（生成时已断言）。RLS 列：E = ENABLE，F = FORCE。策略的角色缩写：app=cardflow_app、worker=cardflow_worker、admin=cardflow_admin、purge=cardflow_purge、admin_views=cardflow_admin_views。")
o("")
o("## 1. 逐表总览")
o("")
o("| 表 | RLS | 策略（命令 → 角色） | app | worker | admin | purge | admin_views |")
o("|---|---|---|---|---|---|---|---|")
for t in sorted(columns):
    e, f = rls[t]
    flag = ("E" if e else "") + ("F" if f else "") or "无"
    pol = "<br>".join(f"`{p}` {cmd} → {', '.join(r)}" for p, cmd, r, _q, _c in policies.get(t, [])) or "（无策略）"
    o(f"| `{t}` | {flag} | {pol} | " + " | ".join(cell(r, t) for r in ROLES) + " |")
o("")
o("无 RLS 的表只有 `currencies`、`worker_heartbeats`、`alembic_version`（无 workspace_id 的全局/系统表，理由见 rls-design.md §3.6；`tests/db/test_rls_grants.py` 的 NO_RLS_TABLES 逐一列出，新表漏加 RLS 会让测试失败）。")
o("")
o("## 2. 列级授权明细")
o("")
for role in ROLES:
    o(f"### {role}")
    o("")
    any_line = False
    for t in sorted(columns):
        cols = columns[t]
        for idx, label in ((0, "SELECT"), (1, "INSERT"), (2, "UPDATE")):
            granted = [c for c in cols if priv[(role, t, c)][idx]]
            if granted and len(granted) != len(cols):
                o(f"- `{t}` {label}: {', '.join(granted)}")
                any_line = True
    if not any_line:
        o("- （只有整表授权或无授权）")
    o("")
o("## 3. 策略表达式")
o("")
seen = {}
for t in sorted(policies):
    for p, cmd, r, qual, check in policies[t]:
        seen.setdefault((p, cmd, tuple(r), qual, check), []).append(t)
o("| 策略 | 命令 | 角色 | USING | WITH CHECK | 表 |")
o("|---|---|---|---|---|---|")
for (p, cmd, r, qual, check), tables in sorted(seen.items(), key=lambda kv: (kv[0][0], len(kv[1]))):
    tables_text = ", ".join(f"`{x}`" for x in tables) if len(tables) <= 6 else f"{len(tables)} 张表：" + ", ".join(f"`{x}`" for x in tables)
    flat = lambda value: " ".join((value or "–").split())  # noqa: E731
    o(f"| `{p}` | {cmd} | {', '.join(r)} | `{flat(qual)}` | `{flat(check)}` | {tables_text} |")
o("")
o("## 4. 函数 EXECUTE 与 SECURITY DEFINER")
o("")
o("| 函数 | SECURITY DEFINER | PUBLIC 可执行 | 可执行的组角色 |")
o("|---|---|---|---|")
for sig, secdef, public, roles in functions:
    o(f"| `{sig}` | {'是' if secdef else '否'} | {'是' if public else '否'} | {', '.join(SHORT[x] for x in roles) or '–'} |")
o("")
o("## 5. 序列、数据库与 schema 权限")
o("")
o("- `sync_changes_seq_seq` USAGE：" + ", ".join(f"{SHORT[r]}={'是' if u else '否'}" for r, u in seq))
o("- 数据库 TEMPORARY / CREATE：" + "; ".join(f"{SHORT.get(r, 'PUBLIC')}: TEMP={'是' if t else '否'}, CREATE={'是' if c else '否'}" for r, t, c in dbpriv))
o("- schema public USAGE / CREATE，schema admin USAGE：" + "; ".join(f"{SHORT.get(r, 'PUBLIC')}: {'U' if u else '-'}{'C' if cr else '-'} / admin {'U' if au else '-'}" for r, u, cr, au in schema))
o("")
o("## 6. 后台元数据视图（schema admin）")
o("")
o("| 视图 | 属主 | 选项 | 列 |")
o("|---|---|---|---|")
for v, owner, options in views:
    o(f"| `admin.{v}` | {owner} | {', '.join(options or [])} | {', '.join(view_cols[v])} |")
o("")
Path("/projects/cardflow/evidence/m0/T-006/rls-coverage.md").write_text("\n".join(out) + "\n", encoding="utf-8")
print(f"rls-coverage.md written: {len(columns)} tables, {sum(len(v) for v in policies.values())} policies, {len(functions)} functions, {len(views)} views; scratch database dropped")
PY
  echo "exit=$?"
} 2>&1 | mask | tee "$EV/rls-coverage.log"

# ---------------------------------------------------------------------------- provision
{
  echo "# T-006 cardflow db-provision demo - $(now), working dir services/api, dev cluster 127.0.0.1:18432"
  echo "# Scratch database cardflow_test_t006_provision migrated to head (the group roles are cluster-wide);"
  echo "# demo passwords are random 36-hex strings in a mode-700 temp dir (shown as ***); the three demo"
  echo "# login roles and the scratch database are dropped at the end."
  NOPW="${URL/:${PW}@/@}"
  export DATABASE_URL="${NOPW%/*}/cardflow_test_t006_provision"
  export DATABASE_PASSWORD_FILE=../../deploy/secrets.dev/db_password
  export LOG_FORMAT=text
  uv run python - <<'PY'
import os
from sqlalchemy import text
from sqlalchemy.pool import NullPool
from cardflow.db.engine import create_engine, normalize_database_url
from cardflow.db.migrations import upgrade
admin_url = normalize_database_url(os.environ["EVIDENCE_ADMIN_URL"])
admin = create_engine(admin_url, poolclass=NullPool).execution_options(isolation_level="AUTOCOMMIT")
with admin.connect() as c:
    existing = sorted(c.execute(text("SELECT rolname FROM pg_roles WHERE rolname IN ('cardflow_api','cardflow_worker_login','cardflow_admin_login')")).scalars())
    print("login roles before the demo:", existing or "none")
    c.execute(text('DROP DATABASE IF EXISTS "cardflow_test_t006_provision" WITH (FORCE)'))
    c.execute(text('CREATE DATABASE "cardflow_test_t006_provision" TEMPLATE template0'))
upgrade(admin_url.set(database="cardflow_test_t006_provision"), "head")
print("scratch database migrated to head")
PY
  echo
  echo '$ cardflow db-provision        # no *_PASSWORD_FILE set yet'
  uv run cardflow db-provision; echo "exit=$?"
  export DATABASE_API_PASSWORD_FILE="$DEMO_DIR/db_api_password"
  export DATABASE_WORKER_PASSWORD_FILE="$DEMO_DIR/db_worker_password"
  export DATABASE_ADMIN_PASSWORD_FILE="$DEMO_DIR/db_admin_password"
  echo
  echo '$ DATABASE_{API,WORKER,ADMIN}_PASSWORD_FILE=<secret files> cardflow db-provision    # create'
  uv run cardflow db-provision; echo "exit=$?"
  echo
  echo '$ cardflow db-provision        # second run: idempotent'
  uv run cardflow db-provision; echo "exit=$?"
  echo
  echo '# drift: someone gives cardflow_api an extra membership and CREATEDB; provisioning repairs it'
  ../../tools/dev-db.sh psql -q -c "GRANT cardflow_admin TO cardflow_api" -c "ALTER ROLE cardflow_api CREATEDB" -c "SELECT 'drift applied'"
  echo '$ cardflow db-provision --role api'
  uv run cardflow db-provision --role api; echo "exit=$?"
  echo
  echo '# roles and memberships now (pg_roles / pg_auth_members):'
  ../../tools/dev-db.sh psql -c "SELECT rolname, rolcanlogin AS login, rolsuper AS super, rolbypassrls AS bypassrls, rolcreatedb AS createdb, rolcreaterole AS createrole, rolinherit AS inherit FROM pg_roles WHERE rolname LIKE 'cardflow\_%' ORDER BY 1" \
    -c "SELECT r.rolname AS member, g.rolname AS group_role, m.inherit_option, m.set_option, m.admin_option FROM pg_auth_members m JOIN pg_roles g ON g.oid = m.roleid JOIN pg_roles r ON r.oid = m.member WHERE r.rolname IN ('cardflow_api','cardflow_worker_login','cardflow_admin_login') ORDER BY 1, 2" \
    -c "SELECT rolname, left(rolpassword, 14) || '...' AS stored_verifier_prefix FROM pg_authid WHERE rolname IN ('cardflow_api','cardflow_worker_login','cardflow_admin_login') ORDER BY 1"
  echo
  echo '# logging in as each role on the scratch database:'
  uv run python - <<'PY'
import os
from pathlib import Path
from sqlalchemy import text
from sqlalchemy.pool import NullPool
from cardflow.db.engine import create_engine, normalize_database_url
base = normalize_database_url(os.environ["EVIDENCE_ADMIN_URL"]).set(database="cardflow_test_t006_provision")

def as_role(name, secret, statements):
    engine = create_engine(base.set(username=name, password=Path(os.environ[secret]).read_text().strip()), poolclass=NullPool)
    for label, sql in statements:
        with engine.connect() as c:
            try:
                *setup, query = sql.split("; ")
                for statement in setup:
                    c.execute(text(statement))
                value = c.execute(text(query)).all()
                print(f"[{name}] {label}: {value}")
            except Exception as exc:  # noqa: BLE001
                orig = getattr(exc, "orig", None)
                print(f"[{name}] {label}: ERROR {getattr(orig, 'sqlstate', None)} {getattr(getattr(orig, 'diag', None), 'message_primary', type(exc).__name__)}")
    engine.dispose()

as_role("cardflow_api", "DATABASE_API_PASSWORD_FILE", [
    ("current_user / readyz version", "SELECT current_user, (SELECT version_num FROM alembic_version)"),
    ("workers seen (readyz)", "SELECT count(*) FROM worker_heartbeats"),
    ("unbound: tenant rows visible", "SELECT count(*) FROM workspaces"),
    ("temp table", "CREATE TEMP TABLE probe (i int)"),
    ("admin view", "SELECT * FROM admin.system_status"),
])
as_role("cardflow_worker_login", "DATABASE_WORKER_PASSWORD_FILE", [
    ("current_user", "SELECT current_user"),
    ("jobs across workspaces", "SELECT count(*) FROM jobs"),
    ("DELETE without SET ROLE", "DELETE FROM statement_lines"),
    ("SET ROLE cardflow_purge", "SET ROLE cardflow_purge; SELECT current_user"),
])
as_role("cardflow_admin_login", "DATABASE_ADMIN_PASSWORD_FILE", [
    ("current_user", "SELECT current_user"),
    ("admin.system_status", "SELECT schema_revision, live_workers, queued_jobs FROM admin.system_status"),
    ("content table", "SELECT * FROM transactions"),
])
PY
  echo
  echo '# cleanup: drop the demo login roles and the scratch database'
  uv run python - <<'PY'
import os
from sqlalchemy import text
from sqlalchemy.pool import NullPool
from cardflow.db.engine import create_engine, normalize_database_url
admin = create_engine(normalize_database_url(os.environ["EVIDENCE_ADMIN_URL"]), poolclass=NullPool).execution_options(isolation_level="AUTOCOMMIT")
with admin.connect() as c:
    c.execute(text('DROP DATABASE IF EXISTS "cardflow_test_t006_provision" WITH (FORCE)'))
    for role in ("cardflow_api", "cardflow_worker_login", "cardflow_admin_login"):
        c.execute(text(f"DROP ROLE IF EXISTS {role}"))
    print("roles now:", sorted(c.execute(text("SELECT rolname FROM pg_roles WHERE rolname !~ '^pg_'")).scalars()))
    print("databases now:", sorted(c.execute(text("SELECT datname FROM pg_database")).scalars()))
PY
} 2>&1 | mask | tee "$EV/provision.txt"
unset DATABASE_URL DATABASE_PASSWORD_FILE LOG_FORMAT DATABASE_API_PASSWORD_FILE DATABASE_WORKER_PASSWORD_FILE DATABASE_ADMIN_PASSWORD_FILE

# -------------------------------------------------------------------------------- pytest
{
  echo "# T-006 full test suite - $(now), working dir services/api, dev DB 127.0.0.1:18432, schema at head $(head_rev) (CARDFLOW_TEST_MIGRATION_TARGET unset)"
  echo '$ CARDFLOW_TEST_DATABASE_URL="$(../../tools/dev-db.sh url)" uv run pytest -q'
  CARDFLOW_TEST_DATABASE_URL="$URL" uv run pytest -q -p no:cacheprovider; echo "exit=$?"
  echo
  echo "# collected tests per directory/file (uv run pytest --co -q | aggregated):"
  uv run pytest --co -q -p no:cacheprovider 2>/dev/null | grep '::' | cut -d: -f1 | sed -E 's#^(tests/[^/]+)/.*#\1#' | sort | uniq -c
  echo
  echo "# T-006 tests, verbose:"
  echo '$ CARDFLOW_TEST_DATABASE_URL="$(../../tools/dev-db.sh url)" uv run pytest -v tests/db/test_rls.py tests/db/test_rls_grants.py tests/db/test_db_provision.py tests/db/test_jobs_schema.py'
  CARDFLOW_TEST_DATABASE_URL="$URL" uv run pytest -v -p no:cacheprovider tests/db/test_rls.py tests/db/test_rls_grants.py tests/db/test_db_provision.py tests/db/test_jobs_schema.py; echo "exit=$?"
  echo '$ ... uv run pytest -v tests/db/test_migrations.py tests/db/test_r2_fixes.py tests/db/test_model_drift.py tests/db/test_db_objects.py tests/test_cli.py tests/test_settings.py tests/test_db.py -k "steps_down or round_trip or r2_23 or r2_01 or outside_the_models or golden or db_provision or login_role or user_id or workspace"'
  CARDFLOW_TEST_DATABASE_URL="$URL" uv run pytest -v -p no:cacheprovider tests/db/test_migrations.py tests/db/test_r2_fixes.py tests/db/test_model_drift.py tests/db/test_db_objects.py tests/test_cli.py tests/test_settings.py tests/test_db.py -k "steps_down or round_trip or r2_23 or r2_01 or outside_the_models or golden or db_provision or login_role or user_id or workspace"; echo "exit=$?"
  echo
  echo "# leftovers in the dev cluster after the run (temporary databases and roles must be gone):"
  ../../tools/dev-db.sh psql -At -c "SELECT 'roles: ' || string_agg(rolname, ', ' ORDER BY rolname) FROM pg_roles WHERE rolname !~ '^pg_'" -c "SELECT 'databases: ' || string_agg(datname, ', ' ORDER BY datname) FROM pg_database"
} 2>&1 | mask | tee "$EV/pytest.txt"

# ---------------------------------------------------------------------------- mutations
# Each mutation patches a COPY of services/api (/tmp, without .venv) and runs the T-006
# tests there with the project's interpreter (PYTHONPATH puts the copy first); the working
# tree is never modified. Expected: every mutation makes at least one test fail.
{
  echo "# T-006 mutation experiments - $(now); copy of services/api in /tmp/t006-mutations (deleted at the end)"
  echo "# tests run per mutation: tests/db/test_rls.py tests/db/test_rls_grants.py"
  echo "#   tests/db/test_migrations.py::test_every_revision_steps_down_and_up_exactly"
  PY_BIN=/projects/cardflow/services/api/.venv/bin/python
  MUT=/tmp/t006-mutations
  run_mutation() {
    local label="$1" patch="$2"
    rm -rf "$MUT" && mkdir -p "$MUT"
    (cd /projects/cardflow/services/api && tar --exclude=.venv --exclude=.pytest_cache --exclude=.ruff_cache \
      --exclude=__pycache__ --exclude=.hypothesis -cf - .) | tar -xf - -C "$MUT"
    if ! (cd "$MUT" && "$PY_BIN" -c "$patch"); then echo "=== mutation $label: PATCH FAILED"; return; fi
    local result
    result="$(cd "$MUT" && PYTHONPATH="$MUT" PYTHONDONTWRITEBYTECODE=1 CARDFLOW_TEST_DATABASE_URL="$URL" \
      "$PY_BIN" -m pytest -q -p no:cacheprovider tests/db/test_rls.py tests/db/test_rls_grants.py \
      "tests/db/test_migrations.py::test_every_revision_steps_down_and_up_exactly" 2>&1)"
    echo "=== mutation $label: $(printf '%s\n' "$result" | tail -n 1)"
    printf '%s\n' "$result" | grep -E '^FAILED' | sed -E 's/ - .*//' | sed 's/^/    /'
  }
  P='from pathlib import Path
p = Path("alembic/versions/0003_rls.py"); s = p.read_text()
def sub(old, new):
    global s
    assert old in s, old
    s = s.replace(old, new, 1)
'
  W='p.write_text(s)'
  run_mutation "none (unpatched copy)" "$P
$W"
  run_mutation "M1 downgrade forgets the grants of cash_events" "$P
sub('for table, roles in TABLE_ACCESS.items()\n    ]', 'for table, roles in TABLE_ACCESS.items()\n        if table != \"cash_events\"\n    ]')
$W"
  run_mutation "M2 cash_events not FORCE ROW LEVEL SECURITY" "$P
sub('FORCE ROW LEVEL SECURITY\" for table in RLS_TABLES)', 'FORCE ROW LEVEL SECURITY\" for table in RLS_TABLES if table != \"cash_events\")')
$W"
  run_mutation "M3 transactions.currency_account_id declared updatable" "$P
sub('    \"transactions\": (\n        \"card_id\",', '    \"transactions\": (\n        \"currency_account_id\",\n        \"card_id\",')
$W"
  run_mutation "M4 undeclared extra grant UPDATE (workspace_id) ON cash_events" "$P
sub('    *_view_statements(),\n]', '    *_view_statements(),\n    \"GRANT UPDATE (workspace_id) ON public.cash_events TO cardflow_app\",\n]')
$W"
  run_mutation "M5 policies compare current_setting(...)::uuid without NULLIF" "$P
sub('CURRENT_WORKSPACE = \"NULLIF(current_setting(\'app.workspace_id\', true), \'\')::uuid\"', 'CURRENT_WORKSPACE = \"current_setting(\'app.workspace_id\', true)::uuid\"')
$W"
  run_mutation "M6 TEMPORARY not revoked from PUBLIC" "$P
sub('    _database_privilege(\"REVOKE\"),\n', '')
$W"
  run_mutation "M7 allocation trigger functions stay SECURITY INVOKER" "$P
sub('SECURITY_DEFINER_FUNCTIONS: tuple[str, ...] = (', 'SECURITY_DEFINER_FUNCTIONS: tuple[str, ...] = () and (')
$W"
  run_mutation "M8 admin may read statement_versions" "$P
sub('    *_view_statements(),\n]', '    *_view_statements(),\n    \"GRANT SELECT ON public.statement_versions TO cardflow_admin\",\n    \"CREATE POLICY m8 ON public.statement_versions FOR SELECT TO cardflow_admin USING (true)\",\n]')
$W"
  run_mutation "M9 users visible to every business session" "$P
sub('f\"id = {CURRENT_USER_ID} OR {USER_IS_MEMBER}\",', '\"true\",')
$W"
  run_mutation "M10 worker keeps INSERT on auth_sessions/devices/members" "$P
sub('    for table in (\"workspace_members\", \"devices\", \"consents\"):\n        access[table][WORKER] = Access(select=True)\n    for table in (\"auth_sessions\", \"idempotency_keys\"):\n        del access[table][WORKER]\n', '')
$W"
  rm -rf "$MUT"
  echo "copy removed; databases now: $(../../tools/dev-db.sh psql -At -c "SELECT string_agg(datname, ', ' ORDER BY datname) FROM pg_database")"
  echo "roles now: $(../../tools/dev-db.sh psql -At -c "SELECT string_agg(rolname, ', ' ORDER BY rolname) FROM pg_roles WHERE rolname !~ '^pg_'")"
} 2>&1 | mask | tee "$EV/mutations.txt"
