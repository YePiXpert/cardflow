#!/usr/bin/env bash
# Build the CardFlow server image cardflow/api:<version> (T-012).
#
#   tools/build-api-image.sh [--source DIR]            build, then print the version
#   tools/build-api-image.sh [--source DIR] --version  only print the version
#
# DIR defaults to services/api. The inputs are first copied into a private snapshot directory;
# the version is computed from, and the image built from, that snapshot, so the tag always
# describes exactly what went into the image even while the working tree keeps changing.
#
# Version rule: <project version in pyproject.toml>-<source digest>, e.g. 0.1.0-3f2a9c1b7d4e.
# The source digest is the first 12 hex digits of a SHA-256 over the sorted "sha256  path"
# list of every file that goes into the image: Dockerfile, .dockerignore, pyproject.toml,
# uv.lock, .python-version, alembic.ini, alembic/ and cardflow/ (__pycache__ and *.pyc
# excluded, as .dockerignore drops them). Same sources -> same tag; any change -> new tag.
# Once the repository is under git, "g<short commit>" may replace the digest
# (deployment-ops §2: "git sha/tag").
#
# Put the printed version into deploy/.env as CARDFLOW_VERSION=<version>. The build creates
# only the image cardflow/api:<version> (and pulls the pinned base image if it is missing);
# it never removes or retags other images.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
readonly IMAGE="cardflow/api"
readonly INPUTS=(Dockerfile .dockerignore pyproject.toml uv.lock .python-version alembic.ini alembic cardflow)

die() {
  echo "build-api-image: $*" >&2
  exit 1
}

usage() {
  die "usage: tools/build-api-image.sh [--source DIR] [--version]"
}

snapshot() { # source_dir target_dir
  tar -C "$1" --exclude='__pycache__' --exclude='*.py[cod]' -cf - "${INPUTS[@]}" \
    | tar -C "$2" -xf -
}

project_version() { # dir
  python3 - "$1/pyproject.toml" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as handle:
    print(tomllib.load(handle)["project"]["version"])
PY
}

source_digest() { # dir
  (
    cd "$1"
    find "${INPUTS[@]}" -type f -print0 \
      | LC_ALL=C sort -z \
      | xargs -0 sha256sum \
      | sha256sum \
      | cut -c1-12
  )
}

main() {
  local source_dir="$ROOT/services/api" only_version=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --source)
        [[ $# -ge 2 ]] || usage
        source_dir="$2"
        shift 2
        ;;
      --version)
        only_version=true
        shift
        ;;
      *) usage ;;
    esac
  done
  [[ -d "$source_dir" ]] || die "no such directory: $source_dir"
  source_dir="$(cd "$source_dir" && pwd)"

  local stage version digest
  stage="$(mktemp -d "${TMPDIR:-/tmp}/cardflow-api-build.XXXXXX")"
  # shellcheck disable=SC2064 # expand now: the trap must remove this very directory
  trap "rm -rf '$stage'" EXIT
  snapshot "$source_dir" "$stage"
  version="$(project_version "$stage")"
  digest="$(source_digest "$stage")"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "unexpected project version '$version'"
  [[ "$digest" =~ ^[0-9a-f]{12}$ ]] || die "could not compute the source digest"
  version="$version-$digest"
  if [[ "$only_version" == true ]]; then
    echo "$version"
    return
  fi

  echo "build-api-image: building $IMAGE:$version from $source_dir (snapshot $stage)" >&2
  docker build \
    --file "$stage/Dockerfile" \
    --build-arg "CARDFLOW_VERSION=$version" \
    --label "org.opencontainers.image.revision=$digest" \
    --provenance=false \
    --progress=plain \
    --tag "$IMAGE:$version" \
    "$stage"
  echo "build-api-image: built $IMAGE:$version; set CARDFLOW_VERSION=$version in deploy/.env" >&2
  echo "$version"
}

main "$@"
