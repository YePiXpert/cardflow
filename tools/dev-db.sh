#!/usr/bin/env bash
# Manage the CardFlow development PostgreSQL. Every command is scoped to the compose
# project "cardflow-dev" (deploy/compose.dev.yaml); nothing else on the host is touched.
#
#   tools/dev-db.sh up      start and wait until healthy (first run generates
#                           deploy/secrets.dev/db_password with mode 0600)
#   tools/dev-db.sh down    stop and remove the container; the data volume is KEPT
#   tools/dev-db.sh reset   remove the container AND the cardflow-dev data volume, start fresh
#   tools/dev-db.sh psql    run psql inside the container (extra arguments go to psql)
#   tools/dev-db.sh url     print the superuser SQLAlchemy URL (includes the password),
#                           e.g. CARDFLOW_TEST_DATABASE_URL="$(tools/dev-db.sh url)"
#   tools/dev-db.sh status  show the container state
set -euo pipefail

readonly PROJECT="cardflow-dev"
readonly HOST_ADDR="127.0.0.1"
readonly HOST_PORT="18432"
readonly DB_USER="cardflow"
readonly DB_NAME="cardflow"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
readonly COMPOSE_FILE="$ROOT/deploy/compose.dev.yaml"
readonly SECRET_DIR="$ROOT/deploy/secrets.dev"
readonly SECRET_FILE="$SECRET_DIR/db_password"

die() {
  echo "dev-db: $*" >&2
  exit 1
}

compose() {
  docker compose -p "$PROJECT" -f "$COMPOSE_FILE" "$@"
}

ensure_secret() {
  if [[ -s "$SECRET_FILE" ]]; then
    return
  fi
  (umask 077 && mkdir -p "$SECRET_DIR")
  chmod 700 "$SECRET_DIR"
  local password
  # 24 random bytes as 48 hex characters: URL-safe, so `url` needs no escaping.
  password="$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
  (umask 077 && printf '%s' "$password" >"$SECRET_FILE")
  chmod 600 "$SECRET_FILE"
  echo "dev-db: generated $SECRET_FILE (mode 600)" >&2
}

db_running() {
  [[ -n "$(compose ps --status running --quiet db 2>/dev/null)" ]]
}

ensure_port_free() {
  if db_running; then
    return
  fi
  if ss -tlnH "sport = :$HOST_PORT" | grep -q .; then
    die "port $HOST_PORT is already in use by another process; refusing to start"
  fi
}

cmd_up() {
  ensure_secret
  ensure_port_free
  compose up --detach --wait --wait-timeout 120 db
  echo "dev-db: ready on $HOST_ADDR:$HOST_PORT (compose project $PROJECT)" >&2
}

cmd_down() {
  compose down
}

cmd_reset() {
  echo "dev-db: removing container and data volume of project $PROJECT" >&2
  compose down --volumes
  cmd_up
}

cmd_psql() {
  if [[ -t 0 && -t 1 ]]; then
    compose exec db psql -U "$DB_USER" -d "$DB_NAME" "$@"
  else
    compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" "$@"
  fi
}

cmd_url() {
  [[ -s "$SECRET_FILE" ]] || die "no password file yet; run: tools/dev-db.sh up"
  printf 'postgresql+psycopg://%s:%s@%s:%s/%s\n' \
    "$DB_USER" "$(cat "$SECRET_FILE")" "$HOST_ADDR" "$HOST_PORT" "$DB_NAME"
}

cmd_status() {
  compose ps --all
}

usage() {
  # Print the header comment block (everything after the shebang up to the first code line).
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}" >&2
}

main() {
  local command="${1:-}"
  if [[ $# -gt 0 ]]; then
    shift
  fi
  case "$command" in
    up) cmd_up ;;
    down) cmd_down ;;
    reset) cmd_reset ;;
    psql) cmd_psql "$@" ;;
    url) cmd_url ;;
    status) cmd_status ;;
    *)
      usage
      exit 2
      ;;
  esac
}

main "$@"
