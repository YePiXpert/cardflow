#!/usr/bin/env bash
# Generate the Compose secrets of the CardFlow stack in deploy/secrets/ (T-012).
#
#   tools/gen-secrets.sh
#
# Creates every missing file and NEVER overwrites an existing one (O_EXCL), so it is safe to
# re-run: new secrets appear, existing ones are only checked (non-empty, valid format) and get
# their permissions fixed. Values are never printed. What each file is for and how to rotate
# it: deploy/secrets/README.md.
#
#   file                 content                                       read by
#   db_password          PostgreSQL superuser, 64 hex chars            db, migrate, provision, backup
#   db_api_password      LOGIN role cardflow_api, 64 hex chars         provision, api
#   db_worker_password   LOGIN role cardflow_worker_login, 64 hex      provision, worker
#   db_admin_password    LOGIN role cardflow_admin_login, 64 hex       provision (admin, T-031)
#   jwt_key              JWT signing key, 64 random bytes base64url    api
#   kek                  KEK, 32 random bytes, standard base64         api, worker, backup
#   backup_passphrase    backup encryption passphrase, 64 hex chars    backup (T-013)
#
# Permissions: directory 0700, files 0600. The containers run as uid/gid 10001 and Compose
# bind-mounts each file read-only at /run/secrets/<name> with its host owner and mode, so the
# files belong to 10001:10001 (override with CARDFLOW_SECRETS_UID/GID); the directory stays
# with the operator. Run as root (or with sudo) so that chown works.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
readonly SECRETS_DIR="$ROOT/deploy/secrets"
readonly OWNER_UID="${CARDFLOW_SECRETS_UID:-10001}"
readonly OWNER_GID="${CARDFLOW_SECRETS_GID:-10001}"
readonly MIN_PASSWORD_LENGTH=16
readonly KEK_BYTES=32

PASSWORDS=(db_password db_api_password db_worker_password db_admin_password)
readonly PASSWORDS

die() {
  echo "gen-secrets: $*" >&2
  exit 1
}

random_hex() { # bytes
  od -An -N"$1" -tx1 /dev/urandom | tr -d ' \n'
}

random_base64() { # bytes
  head -c "$1" /dev/urandom | base64 -w0
}

random_base64url() { # bytes
  head -c "$1" /dev/urandom | base64 -w0 | tr '+/' '-_' | tr -d '='
}

new_value() { # name
  case "$1" in
    db_password | db_api_password | db_worker_password | db_admin_password) random_hex 32 ;;
    jwt_key) random_base64url 64 ;;
    kek) random_base64 "$KEK_BYTES" ;;
    backup_passphrase) random_hex 32 ;;
    *) die "unknown secret $1" ;;
  esac
}

# Problems of an existing file, without ever printing its content.
check_existing() { # name path
  local name="$1" path="$2" length
  [[ -f "$path" && ! -L "$path" ]] || die "$path exists but is not a regular file"
  [[ -s "$path" ]] || die "$path is empty; remove it and re-run to generate a new value"
  length="$(tr -d '\n' <"$path" | wc -c)"
  case "$name" in
    kek)
      local decoded
      decoded="$(tr -d '\n' <"$path" | base64 -d 2>/dev/null | wc -c)" || decoded=0
      [[ "$decoded" -eq "$KEK_BYTES" ]] \
        || die "$path is not the base64 encoding of $KEK_BYTES bytes (see deploy/secrets/README.md)"
      ;;
    *)
      [[ "$length" -ge "$MIN_PASSWORD_LENGTH" ]] \
        || die "$path is shorter than $MIN_PASSWORD_LENGTH characters"
      ;;
  esac
}

fix_permissions() { # path
  chmod 600 "$1"
  if [[ "$(id -u)" -eq 0 ]]; then
    chown "$OWNER_UID:$OWNER_GID" "$1"
  elif [[ "$(stat -c %u "$1")" != "$OWNER_UID" ]]; then
    echo "gen-secrets: warning: $1 is not owned by uid $OWNER_UID; the containers cannot read" \
      "it. Run: sudo chown $OWNER_UID:$OWNER_GID $1" >&2
  fi
}

main() {
  [[ $# -eq 0 ]] || die "usage: tools/gen-secrets.sh (no arguments)"
  [[ ! -L "$SECRETS_DIR" ]] || die "$SECRETS_DIR is a symbolic link; refusing"
  (umask 077 && mkdir -p "$SECRETS_DIR")
  chmod 700 "$SECRETS_DIR"

  local name path value
  for name in "${PASSWORDS[@]}" jwt_key kek backup_passphrase; do
    path="$SECRETS_DIR/$name"
    if [[ -e "$path" || -L "$path" ]]; then
      check_existing "$name" "$path"
      fix_permissions "$path"
      echo "gen-secrets: kept     $name (exists, not overwritten)"
      continue
    fi
    value="$(new_value "$name")"
    [[ -n "$value" ]] || die "could not generate $name"
    # noclobber: the redirection uses O_EXCL, so a file created meanwhile is never replaced.
    (umask 077 && set -o noclobber && printf '%s' "$value" >"$path") \
      || die "could not create $path"
    value=""
    check_existing "$name" "$path"
    fix_permissions "$path"
    echo "gen-secrets: created  $name"
  done
  echo "gen-secrets: $SECRETS_DIR (mode $(stat -c %a "$SECRETS_DIR")):"
  # Names, modes and owners only -- never the content.
  (cd "$SECRETS_DIR" && stat -c '  %n mode=%a owner=%u:%g size=%s' -- *)
  echo "gen-secrets: store a copy of backup_passphrase (and kek) outside this server;" \
    "without them backups and attachments cannot be decrypted."
}

main "$@"
