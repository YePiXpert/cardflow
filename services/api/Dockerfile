# CardFlow server image (T-012): one image for every Compose service -- api, worker, migrate,
# provision and (T-013) backup; the command decides. Build it with tools/build-api-image.sh,
# which applies the version rule and tags cardflow/api:<version>. Build context: services/api
# (only the files allowed by .dockerignore).
#
# Source layout is kept on purpose: the project is installed *editable*, so cardflow/ sits next
# to alembic.ini and alembic/ in /app, which `cardflow migrate` needs (cardflow.db.migrations
# resolves alembic.ini as cardflow/../alembic.ini).

# python:3.13-slim-trixie (Python 3.13.16), pinned by digest (pulled 2026-10-17).
ARG PYTHON_IMAGE=python:3.13-slim-trixie@sha256:70729b46c69b4f1e97c4822c1af3df53a1476cf5ddc6c087c0c10bc3a5678c2f

# --------------------------------------------------------------------------- builder
FROM ${PYTHON_IMAGE} AS builder

# uv from PyPI, pinned by version and wheel hash (the version used on the development host).
ARG UV_VERSION=0.12.23
ARG UV_SHA256=565c6e2874dbeae86c02f3dea97255e878fec672659a73d4930c6b93fcab2fff
RUN printf 'uv==%s --hash=sha256:%s\n' "$UV_VERSION" "$UV_SHA256" > /tmp/uv-requirements.txt \
    && python -m pip install --no-cache-dir --disable-pip-version-check --root-user-action=ignore \
        --require-hashes -r /tmp/uv-requirements.txt

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_NO_CACHE=1 \
    UV_PYTHON_DOWNLOADS=never \
    UV_PYTHON=/usr/local/bin/python3.13 \
    UV_PROJECT_ENVIRONMENT=/app/.venv
WORKDIR /app

# 1) Third-party dependencies exactly as locked (no dev group); cached until uv.lock changes.
COPY pyproject.toml uv.lock .python-version ./
RUN uv sync --locked --no-dev --no-install-project

# 2) The project itself (editable, see above), then byte-compile it: the runtime filesystem
#    is read-only, so Python could not write __pycache__ later.
COPY alembic.ini ./
COPY alembic ./alembic
COPY cardflow ./cardflow
RUN uv sync --locked --no-dev \
    && .venv/bin/python -m compileall -q cardflow alembic \
    && .venv/bin/python -c "from cardflow.db.migrations import ALEMBIC_INI, head_revisions; \
assert ALEMBIC_INI.is_file(), ALEMBIC_INI; print('alembic head', head_revisions())"

# --------------------------------------------------------------------------- runtime
FROM ${PYTHON_IMAGE} AS runtime

ARG CARDFLOW_VERSION=dev
LABEL org.opencontainers.image.title="cardflow-api" \
      org.opencontainers.image.description="CardFlow API, job worker and CLI (FastAPI, Python 3.13)" \
      org.opencontainers.image.version="${CARDFLOW_VERSION}"

ENV PATH=/app/.venv/bin:${PATH} \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    CARDFLOW_VERSION=${CARDFLOW_VERSION} \
    ATTACHMENTS_DIR=/data/attachments

# Unprivileged runtime user 10001:10001 (no home, no login shell). The data directories are
# created here so that fresh named volumes mounted on them start out owned by 10001, mode 0700.
RUN groupadd --gid 10001 cardflow \
    && useradd --uid 10001 --gid 10001 --no-create-home --home-dir /nonexistent \
        --shell /usr/sbin/nologin cardflow \
    && install -d -o 10001 -g 10001 -m 0700 /data/attachments /data/backups

# Code and virtual environment stay owned by root: the runtime user can read, not modify them.
COPY --from=builder /app /app

# The runtime layer must not carry a compiler toolchain: fail the build if one is present.
RUN for tool in gcc cc c++ g++ clang make ld as; do \
        if command -v "$tool" >/dev/null 2>&1; then \
            echo "unexpected build tool in the runtime image: $tool" >&2; exit 1; \
        fi; \
    done

USER 10001:10001
WORKDIR /app
EXPOSE 8000
CMD ["cardflow", "api", "--host", "0.0.0.0", "--port", "8000"]
