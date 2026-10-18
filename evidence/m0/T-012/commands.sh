#!/usr/bin/env bash
# T-012 evidence: isolated Compose deployment on the shared host. Run from anywhere:
#   evidence/m0/T-012/commands.sh <step>
# Steps (in order): before | snapshot | build | secrets | up | readyz | nonroot | rls | logs |
#                   after | pytest | ruff
# Every docker compose call is `docker compose -p cardflow -f deploy/compose.yaml ...`.
# Nothing here stops, removes or modifies a resource outside the compose project "cardflow".
set -uo pipefail

readonly REPO=/projects/cardflow
readonly EV="$REPO/evidence/m0/T-012"
readonly WORK=/tmp/t012
readonly SNAPSHOT="$WORK/api-src"
cd "$REPO" || exit 1

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
dc() { docker compose -p cardflow -f deploy/compose.yaml "$@"; }
show() { # print a command, then run it
  printf '$ %s\n' "$*"
  "$@"
  local rc=$?
  echo "exit=$rc"
  return $rc
}
docker_ps() {
  docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
}
ps_names() {
  docker ps --format '{{.Names}} {{.Image}} {{.Ports}}' | sort
}

step_before() {
  mkdir -p "$WORK"
  {
    echo "# T-012 containers BEFORE deployment - $(now)"
    show docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
    echo
    show docker compose ls
  } 2>&1 | tee "$WORK/containers-before.txt"
  ps_names >"$WORK/ps-before.lst"
  {
    echo "# T-012 listening TCP sockets BEFORE deployment - $(now)"
    show ss -tlnH
  } 2>&1 | tee "$WORK/ports-before.txt"
  ss -tlnH | awk '{print $4}' | sort -u >"$WORK/ports-before.lst"
}

# The image must not contain work of tasks that are still in progress: T-011 is adding
# migration 0004 together with matching changes in cardflow/db and cardflow/identity, and
# applying an unreviewed revision to a real database is not acceptable. The first attempt
# (snapshot of the working tree minus 0004, evidence: build-attempt1.txt and
# compose-up-attempt1-failed.txt) failed in `provision` because cardflow/db/roles.py
# already expected 0004's group role. The deployed sources are therefore those of the trial
# image cardflow/api:0.1.0-435423c2aed4, built at 2026-10-17T22:59:59Z, before T-011's first
# change (23:03:46Z, 0004_identity.py): verified schema 0001-0003 plus the T-012 changes.
# Its build log is build-trial.txt. Only Dockerfile and .dockerignore come from the working
# tree (T-012 files; since the trial build the Dockerfile only dropped useradd --system).
readonly TRIAL_IMAGE_VERSION=0.1.0-435423c2aed4
step_snapshot() {
  {
    echo "# T-012 build snapshot - $(now)"
    echo "# sources of the trial image cardflow/api:$TRIAL_IMAGE_VERSION (built 2026-10-17T22:59:59Z)"
    rm -rf "$SNAPSHOT" && mkdir -p "$SNAPSHOT"
    printf '$ CARDFLOW_VERSION=%s docker compose -p cardflow -f deploy/compose.yaml run --rm --no-deps -T migrate tar -C /app --exclude=__pycache__ -cf - pyproject.toml uv.lock .python-version alembic.ini alembic cardflow | tar -C %s -xf -\n' "$TRIAL_IMAGE_VERSION" "$SNAPSHOT"
    CARDFLOW_VERSION="$TRIAL_IMAGE_VERSION" dc run --rm --no-deps -T migrate \
      tar -C /app --exclude=__pycache__ -cf - pyproject.toml uv.lock .python-version alembic.ini alembic cardflow \
      | tar -C "$SNAPSHOT" -xf -
    echo "exit=${PIPESTATUS[0]}/${PIPESTATUS[1]}"
    cp services/api/Dockerfile services/api/.dockerignore "$SNAPSHOT/"
    echo "# check: the snapshot reproduces the trial image's version except for the two T-012 files"
    echo "#   Dockerfile/.dockerignore changed since the trial build -> the digest differs"
    echo "migrations in the snapshot (= in the image):"
    ls -1 "$SNAPSHOT/alembic/versions/" | sed 's/^/  /'
    echo "files of the snapshot that differ from the current working tree (= in-progress work"
    echo "of T-011 / T-004c that is NOT deployed; T-012 files are identical):"
    diff -rq -x __pycache__ -x '*.pyc' -x '.venv' services/api/cardflow "$SNAPSHOT/cardflow" | sed 's/^/  /'
    diff -rq -x __pycache__ -x '*.pyc' services/api/alembic "$SNAPSHOT/alembic" | sed 's/^/  /'
    for f in pyproject.toml uv.lock .python-version alembic.ini Dockerfile .dockerignore; do
      cmp -s "services/api/$f" "$SNAPSHOT/$f" || echo "  differs: $f"
    done
    echo "(end of differences)"
    echo "T-012 files in the snapshot equal the working tree:"
    for f in cardflow/api/routes/health.py cardflow/api/app.py; do
      if cmp -s "services/api/$f" "$SNAPSHOT/$f"; then echo "  same: $f"; else echo "  DIFFERENT: $f"; fi
    done
    echo "  cardflow/settings.py: T-012 field present in the snapshot: $(grep -c 'api_docs_enabled: bool = False' "$SNAPSHOT/cardflow/settings.py")"
  } 2>&1 | tee "$WORK/snapshot.txt"
}

step_build() {
  {
    cat "$WORK/snapshot.txt"
    echo
    echo "# T-012 image build - $(now)"
    printf '$ tools/build-api-image.sh --source %s\n' "$SNAPSHOT"
    tools/build-api-image.sh --source "$SNAPSHOT" | tee "$WORK/version.txt"
    echo "exit=${PIPESTATUS[0]}"
    local version
    version="$(tail -n1 "$WORK/version.txt")"
    echo
    show docker image ls cardflow/api
    echo
    printf '$ docker image inspect cardflow/api:%s (selected fields)\n' "$version"
    docker image inspect "cardflow/api:$version" --format \
      'id={{.Id}}
created={{.Created}}
size_bytes={{.Size}}
user={{.Config.User}}
workdir={{.Config.WorkingDir}}
cmd={{json .Config.Cmd}}
exposed={{json .Config.ExposedPorts}}
labels={{json .Config.Labels}}'
    echo
    echo "# base image (pinned by digest in services/api/Dockerfile)"
    show docker image inspect python:3.13-slim-trixie --format '{{json .RepoDigests}}'
  } 2>&1 | tee "$EV/build.txt"
}

step_secrets() {
  local version
  version="$(tail -n1 "$WORK/version.txt")"
  {
    echo "# T-012 secrets and deploy/.env - $(now)"
    show tools/gen-secrets.sh
    echo
    echo "\$ cp -n deploy/.env.example deploy/.env; set CARDFLOW_VERSION=$version"
    cp -n deploy/.env.example deploy/.env
    chmod 600 deploy/.env
    sed -i "s/^CARDFLOW_VERSION=.*/CARDFLOW_VERSION=$version/" deploy/.env
    show grep -E '^(CARDFLOW_VERSION|CARDFLOW_API_PORT|LOG_LEVEL|API_DOCS_ENABLED)=' deploy/.env
    echo
    echo "# no secret value is in deploy/.env or in the rendered service environments:"
    printf '$ docker compose -p cardflow -f deploy/compose.yaml config | grep -qF -f deploy/secrets/<each file>\n'
    local name hits=0
    for name in deploy/secrets/*; do
      [[ "$name" == */README.md ]] && continue
      # grep -f reads the value from the file itself: it never appears on a command line.
      if dc config 2>/dev/null | grep -qF -f "$name"; then
        echo "  LEAK: value of $name appears in the rendered configuration"
        hits=$((hits + 1))
      fi
      if grep -qF -f "$name" deploy/.env; then
        echo "  LEAK: value of $name appears in deploy/.env"
        hits=$((hits + 1))
      fi
    done
    echo "  secret values found in config/.env: $hits"
    echo
    echo "# environment entries of the services that mention secrets: file paths only"
    dc config --format json | python3 -c '
import json, sys
config = json.load(sys.stdin)
for name, service in sorted(config["services"].items()):
    env = service.get("environment") or {}
    keys = sorted(k for k in env if any(w in k for w in ("PASSWORD", "KEY", "KEK", "PASSPHRASE", "SECRET")))
    print(f"  {name}: " + ", ".join(f"{k}={env[k]}" for k in keys))
'
  } 2>&1 | tee "$WORK/secrets.txt"
}

wait_healthy() {
  local deadline=$((SECONDS + 240)) api db worker migrate provision
  while ((SECONDS < deadline)); do
    db="$(docker inspect -f '{{.State.Health.Status}}' cardflow-db-1 2>/dev/null)"
    api="$(docker inspect -f '{{.State.Health.Status}}' cardflow-api-1 2>/dev/null)"
    worker="$(docker inspect -f '{{.State.Status}}' cardflow-worker-1 2>/dev/null)"
    migrate="$(docker inspect -f '{{.State.Status}}/{{.State.ExitCode}}' cardflow-migrate-1 2>/dev/null)"
    provision="$(docker inspect -f '{{.State.Status}}/{{.State.ExitCode}}' cardflow-provision-1 2>/dev/null)"
    echo "[$(now)] db=$db migrate=$migrate provision=$provision api=$api worker=$worker"
    if [[ "$db" == healthy && "$api" == healthy && "$worker" == running \
      && "$migrate" == exited/0 && "$provision" == exited/0 ]]; then
      echo "all services ready after ${SECONDS}s"
      return 0
    fi
    sleep 3
  done
  echo "TIMEOUT waiting for the services"
  return 1
}

step_up() {
  {
    cat "$WORK/secrets.txt"
    echo
    echo "# T-012 docker compose up - $(now)"
    show docker compose -p cardflow -f deploy/compose.yaml up -d
    echo
    echo "# waiting for: db healthy, migrate and provision exited 0, worker running, api healthy"
    SECONDS=0
    wait_healthy
    echo
    show docker compose -p cardflow -f deploy/compose.yaml ps -a
    echo
    show docker compose -p cardflow -f deploy/compose.yaml logs --no-color migrate provision
    echo
    echo "# published ports of the project (expect only 127.0.0.1:18080 -> api:8000)"
    for c in $(dc ps -a --format '{{.Name}}'); do
      printf '  %s: %s\n' "$c" "$(docker inspect -f '{{json .HostConfig.PortBindings}} network_mode={{.HostConfig.NetworkMode}}' "$c")"
    done
    echo
    echo "# networks of the project"
    show docker network ls --filter label=com.docker.compose.project=cardflow --format '{{.Name}} driver={{.Driver}} internal={{.Internal}}'
    echo
    echo "# volumes of the project"
    show docker volume ls --filter label=com.docker.compose.project=cardflow --format '{{.Name}}'
    echo
    echo "# secrets inside the containers: read-only bind mounts, owner 10001, mode 0600"
    for c in cardflow-api-1 cardflow-worker-1; do
      printf '$ docker exec %s stat -c "%%n %%U:%%G(%%u:%%g) %%a" /run/secrets/*\n' "$c"
      docker exec "$c" sh -c 'stat -c "%n %U:%G(%u:%g) %a" /run/secrets/*'
      printf '  mounts: %s\n' "$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/run/secrets/kek"}}{{.Type}} rw={{.RW}} {{.Destination}}{{end}}{{end}}' "$c")"
    done
    echo
    echo "# resource limits and hardening as applied by Docker"
    for c in cardflow-db-1 cardflow-api-1 cardflow-worker-1; do
      printf '  %s: %s\n' "$c" "$(docker inspect -f 'user={{.Config.User}} readonly_rootfs={{.HostConfig.ReadonlyRootfs}} memory={{.HostConfig.Memory}} nano_cpus={{.HostConfig.NanoCpus}} pids={{.HostConfig.PidsLimit}} cap_drop={{.HostConfig.CapDrop}} security_opt={{.HostConfig.SecurityOpt}} init={{index .HostConfig "Init"}} tmpfs={{json (index .HostConfig "Tmpfs")}} stop_timeout={{index .Config "StopTimeout"}}' "$c")"
    done
  } 2>&1 | tee "$EV/compose-up.txt"
}

step_readyz() {
  {
    echo "# T-012 readiness and liveness on the published loopback port - $(now)"
    show curl -sS -i 127.0.0.1:18080/readyz
    echo
    echo
    show curl -sS -i 127.0.0.1:18080/healthz
    echo
    echo
    echo "# interactive docs and the schema endpoint are off in production (API_DOCS_ENABLED=false)"
    for path in /docs /redoc /openapi.json; do
      printf '$ curl -sS -o /dev/null -w "%%{http_code}" 127.0.0.1:18080%s\n' "$path"
      curl -sS -o /dev/null -w "%{http_code}\n" "127.0.0.1:18080$path"
    done
    echo
    echo "# timing of /readyz (5 sequential requests)"
    for _ in 1 2 3 4 5; do
      curl -sS -o /dev/null -w "  status=%{http_code} time_total=%{time_total}s\n" 127.0.0.1:18080/readyz
    done
    echo
    show docker compose -p cardflow -f deploy/compose.yaml ps
    echo
    echo "# api container health log (last probes)"
    docker inspect -f '{{range .State.Health.Log}}  {{.Start.Format "15:04:05"}} exit={{.ExitCode}} {{.Output}}{{"\n"}}{{end}}' cardflow-api-1 | tail -n 5
  } 2>&1 | tee "$EV/readyz.txt"
}

step_nonroot() {
  {
    echo "# T-012 non-root containers - $(now)"
    show docker exec cardflow-api-1 id
    show docker exec cardflow-worker-1 id
    echo
    echo "# process owners inside the containers (uid of PID 1 = docker-init, and its child)"
    for c in cardflow-api-1 cardflow-worker-1; do
      printf '$ docker exec %s sh -c '"'"'for p in /proc/[0-9]*; do ...'"'"'\n' "$c"
      docker exec "$c" sh -c 'for p in /proc/[0-9]*; do [ -r "$p/status" ] || continue; printf "  pid=%s uid=%s cmd=%s\n" "${p#/proc/}" "$(awk "/^Uid:/{print \$2}" "$p/status")" "$(tr "\0" " " <"$p/cmdline" | cut -c1-80)"; done'
    done
    echo
    echo "# effective capabilities of the api process (all zero = cap_drop ALL)"
    show docker exec cardflow-api-1 sh -c 'grep -E "^Cap(Eff|Prm|Bnd)" /proc/1/status'
    echo
    echo "# root filesystem is read-only; only /tmp (tmpfs) and the attachment volume are writable"
    show docker exec cardflow-api-1 sh -c 'touch /app/probe 2>&1; touch /etc/probe 2>&1; true'
    show docker exec cardflow-api-1 sh -c 'f=$(mktemp -p /tmp) && echo "tmp writable: $f" && rm "$f"'
    show docker exec cardflow-api-1 sh -c 'stat -c "%n %U(%u):%G(%g) %a" /data/attachments /app /app/cardflow'
    echo
    echo "# the database container: PostgreSQL runs as the image's postgres user (uid 999)"
    printf '$ docker exec cardflow-db-1 sh -c '"'"'for p in /proc/[0-9]*; do ... postgres processes only'"'"'\n'
    docker exec cardflow-db-1 sh -c 'for p in /proc/[0-9]*; do [ -r "$p/cmdline" ] || continue; c="$(tr "\0" " " <"$p/cmdline" | cut -c1-60)"; case "$c" in postgres*) printf "  pid=%s uid=%s cmd=%s\n" "${p#/proc/}" "$(awk "/^Uid:/{print \$2}" "$p/status")" "$c";; esac; done'
    echo "exit=$?"
  } 2>&1 | tee "$EV/nonroot.txt"
}

step_rls() {
  local ws user other
  ws="$(cat /proc/sys/kernel/random/uuid)"
  user="$(cat /proc/sys/kernel/random/uuid)"
  other="$(cat /proc/sys/kernel/random/uuid)"
  {
    echo "# T-012 RLS in the deployed database - $(now)"
    echo "# 1) superuser (local socket inside the db container) creates synthetic tenant rows"
    echo "#    (demo workspace, no names, no e-mail; removed again in step 3)"
    cat <<SQL | dc exec -T db psql -X -a -v ON_ERROR_STOP=1 -U cardflow -d cardflow
BEGIN;
INSERT INTO users (id) VALUES ('$user');
INSERT INTO workspaces (id, owner_user_id, kind) VALUES ('$ws', '$user', 'demo');
INSERT INTO workspace_members (workspace_id, user_id, role) VALUES ('$ws', '$user', 'owner');
COMMIT;
SELECT current_user AS who, (SELECT count(*) FROM workspaces) AS workspaces,
       (SELECT count(*) FROM workspace_members) AS members, (SELECT count(*) FROM users) AS users;
SQL
    echo "exit=$?"
    echo
    echo "# 2) business role cardflow_api over TCP (host db, SCRAM password read from the secret"
    echo "#    file on stdin, never on a command line):"
    echo '$ { cat deploy/secrets/db_api_password; echo; cat <<SQL ... SQL; } | docker compose -p cardflow -f deploy/compose.yaml exec -T db sh -c '"'"'IFS= read -r PGPASSWORD; export PGPASSWORD; exec psql -X -a -h db -U cardflow_api -d cardflow'"'"
    {
      cat deploy/secrets/db_api_password
      echo
      cat <<SQL
SELECT current_user, session_user, inet_server_addr() IS NOT NULL AS over_tcp;
SELECT rolname, rolsuper, rolbypassrls, rolinherit FROM pg_roles WHERE rolname = current_user;
SELECT pg_has_role(current_user, 'cardflow_app', 'MEMBER') AS member_of_cardflow_app;
-- a) no workspace bound: no tenant row is visible
SELECT count(*) AS workspaces_visible FROM workspaces;
SELECT count(*) AS members_visible FROM workspace_members;
SELECT count(*) AS users_visible FROM users;
-- b) bound to some other workspace id: still nothing
BEGIN;
SELECT set_config('app.workspace_id', '$other', true) IS NOT NULL AS bound_other;
SELECT count(*) AS workspaces_visible FROM workspaces;
SELECT count(*) AS members_visible FROM workspace_members;
COMMIT;
-- c) bound to the demo workspace (what the API does after checking membership): RLS is the filter
BEGIN;
SELECT set_config('app.workspace_id', '$ws', true) IS NOT NULL AS bound_demo;
SELECT count(*) AS workspaces_visible FROM workspaces;
SELECT count(*) AS members_visible FROM workspace_members;
COMMIT;
-- d) writing a row outside the bound workspace is refused by the policy
INSERT INTO workspaces (owner_user_id, kind) VALUES ('$user', 'demo');
-- e) no TEMP privilege, no CREATE in schema public
SELECT has_database_privilege(current_user, current_database(), 'TEMPORARY') AS can_create_temp;
CREATE TEMP TABLE t012_probe (x int);
CREATE TABLE public.t012_probe (x int);
SQL
    } | dc exec -T db sh -c 'IFS= read -r PGPASSWORD; export PGPASSWORD; exec psql -X -a -h db -U cardflow_api -d cardflow'
    echo "exit=$? (psql continues after the expected errors)"
    echo
    echo "# 3) superuser removes the synthetic rows again"
    cat <<SQL | dc exec -T db psql -X -a -v ON_ERROR_STOP=1 -U cardflow -d cardflow
BEGIN;
DELETE FROM workspace_members WHERE workspace_id = '$ws';
DELETE FROM workspaces WHERE id = '$ws';
DELETE FROM users WHERE id = '$user';
COMMIT;
SELECT (SELECT count(*) FROM workspaces) AS workspaces, (SELECT count(*) FROM workspace_members) AS members,
       (SELECT count(*) FROM users) AS users;
SQL
    echo "exit=$?"
    echo
    echo "# 4) login roles in the deployed cluster: none is superuser or has BYPASSRLS"
    cat <<'SQL' | dc exec -T db psql -X -a -U cardflow -d cardflow
SELECT rolname, rolcanlogin, rolsuper, rolbypassrls, rolcreaterole, rolcreatedb
  FROM pg_roles WHERE rolname LIKE 'cardflow%' ORDER BY rolname;
SELECT r.rolname AS login, g.rolname AS member_of, m.inherit_option, m.set_option
  FROM pg_auth_members m JOIN pg_roles r ON r.oid = m.member JOIN pg_roles g ON g.oid = m.roleid
 WHERE r.rolname IN ('cardflow_api', 'cardflow_worker_login', 'cardflow_admin_login')
 ORDER BY 1, 2;
SELECT usename, application_name, client_addr IS NOT NULL AS tcp, count(*)
  FROM pg_stat_activity WHERE datname = 'cardflow' AND usename IS NOT NULL
 GROUP BY 1, 2, 3 ORDER BY 1, 2;
SQL
    echo "exit=$?"
  } 2>&1 | tee "$EV/rls-in-deploy.txt"
}

step_logs() {
  {
    echo "# T-012 PII scan of the deployment logs - $(now)"
    echo '$ docker compose -p cardflow -f deploy/compose.yaml logs --no-color > evidence/m0/T-012/compose-logs.txt'
    dc logs --no-color >"$EV/compose-logs.txt" 2>&1
    echo "exit=$? lines=$(wc -l <"$EV/compose-logs.txt")"
    echo "lines per service:"
    awk -F'|' '{gsub(/ +$/, "", $1); print "  " $1}' "$EV/compose-logs.txt" | sort | uniq -c
    echo
    echo '$ docker compose -p cardflow -f deploy/compose.yaml logs --no-color | python3 tools/pii_scan.py -'
    dc logs --no-color 2>&1 | python3 tools/pii_scan.py -
    echo "exit=$? (0 = no hits)"
    echo
    echo "# none of the secret values occurs in the logs"
    local name hits=0
    for name in deploy/secrets/*; do
      [[ "$name" == */README.md ]] && continue
      if grep -qF -f "$name" "$EV/compose-logs.txt"; then
        echo "  LEAK: $(basename "$name")"
        hits=$((hits + 1))
      fi
    done
    echo "  secret values found in the logs: $hits"
  } 2>&1 | tee "$EV/logs-pii-scan.txt"
}

step_after() {
  ps_names >"$WORK/ps-after.lst"
  ss -tlnH | awk '{print $4}' | sort -u >"$WORK/ports-after.lst"
  {
    cat "$WORK/containers-before.txt"
    echo
    echo "# T-012 containers AFTER deployment - $(now)"
    show docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
    echo
    show docker compose ls
    echo
    echo "# comparison (name image ports): lines only before (-) / only after (+)"
    diff "$WORK/ps-before.lst" "$WORK/ps-after.lst" | grep -E '^[<>]' | sed 's/^</-/; s/^>/+/'
    echo "# every container running before is still running:"
    local missing
    missing="$(comm -23 <(awk '{print $1}' "$WORK/ps-before.lst" | sort) <(awk '{print $1}' "$WORK/ps-after.lst" | sort))"
    if [[ -z "$missing" ]]; then echo "  yes (none missing)"; else echo "  MISSING: $missing"; fi
    echo "# containers that are not running at all (any project), docker ps -a --filter status=exited:"
    docker ps -a --filter status=exited --format '  {{.Names}} {{.Status}}'
  } 2>&1 | tee "$EV/containers-before-after.txt"
  {
    cat "$WORK/ports-before.txt"
    echo
    echo "# T-012 listening TCP sockets AFTER deployment - $(now)"
    show ss -tlnH
    echo
    echo "# listening addresses only before (-) / only after (+):"
    diff "$WORK/ports-before.lst" "$WORK/ports-after.lst" | grep -E '^[<>]' | sed 's/^</-/; s/^>/+/'
    echo "(end of differences)"
    echo
    echo "# the new socket belongs to docker-proxy on loopback:"
    show ss -tlnpH 'sport = :18080'
  } 2>&1 | tee "$EV/ports-before-after.txt"
}

step_pytest() {
  (
    cd services/api || exit 1
    local url
    url="$(../../tools/dev-db.sh url)"
    echo "# T-012 full test suite - $(now), working dir services/api, dev DB 127.0.0.1:18432 (cardflow-dev), head $(uv run python -c 'from cardflow.db.migrations import head_revisions; print(",".join(head_revisions()))')"
    echo '$ CARDFLOW_TEST_DATABASE_URL="$(../../tools/dev-db.sh url)" uv run pytest -q -p no:cacheprovider'
    CARDFLOW_TEST_DATABASE_URL="$url" uv run pytest -q -p no:cacheprovider
    echo "exit=$?"
    echo
    echo '# T-012 tests on their own (verbose):'
    echo '$ CARDFLOW_TEST_DATABASE_URL="$(../../tools/dev-db.sh url)" uv run pytest tests/test_health.py tests/test_smoke.py tests/test_settings.py -v -p no:cacheprovider'
    CARDFLOW_TEST_DATABASE_URL="$url" uv run pytest tests/test_health.py tests/test_smoke.py tests/test_settings.py -v -p no:cacheprovider
    echo "exit=$?"
  ) 2>&1 | tee "$EV/pytest.txt"
}

step_ruff() {
  (
    cd services/api || exit 1
    echo "# T-012 ruff - $(now), working dir services/api"
    show uv run ruff check .
    show uv run ruff format --check .
  ) 2>&1 | tee "$EV/ruff.txt"
}

case "${1:-}" in
  before | snapshot | build | secrets | up | readyz | nonroot | rls | logs | after | pytest | ruff)
    "step_$1"
    ;;
  *)
    echo "usage: $0 before|snapshot|build|secrets|up|readyz|nonroot|rls|logs|after|pytest|ruff" >&2
    exit 2
    ;;
esac
