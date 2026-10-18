# README 本地启动步骤逐条执行（2026-10-16T15:11:28Z）；执行前已删除 services/api/.venv 与缓存，从干净环境开始
$ uv --version; python3.13 --version; docker compose version
uv 0.12.23 (x86_64-unknown-linux-gnu)
Python 3.13.5
Docker Compose version v5.6.0

## 步骤 1
$ tools/dev-db.sh up
 Container cardflow-dev-db-1 Running 
 Container cardflow-dev-db-1 Waiting 
 Container cardflow-dev-db-1 Healthy 
dev-db: ready on 127.0.0.1:18432 (compose project cardflow-dev)
exit=0

## 步骤 2
$ cd services/api && uv sync --locked
Using CPython 3.13.5 interpreter at: /usr/bin/python3.13
Creating virtual environment at: .venv
Resolved 86 packages in 0.64ms
Installed 84 packages in 30ms
 + absl-py==2.5.1
 + alembic==1.20.0
 + annotated-doc==0.0.5
 + annotated-types==0.8.0
 + anyio==4.15.1
 + apscheduler==3.11.3
 + argon2-cffi==25.1.0
 + argon2-cffi-bindings==26.1.0
 + attrs==26.1.0
 + boolean-py==5.0
 + cachecontrol==0.14.4
 + cardflow==0.1.0 (from file:///projects/cardflow/services/api)
 + certifi==2026.7.22
 + cffi==2.1.1
 + charset-normalizer==3.5.2
 + click==8.5.0
 + cryptography==50.0.2
 + cyclonedx-python-lib==11.12.0
 + defusedxml==0.7.1
 + fastapi==0.143.2
 + filelock==4.2.0
 + h11==0.16.0
 + httpcore==1.0.9
 + httpx==0.28.1
 + hypothesis==6.170.0
 + idna==3.20
 + immutabledict==4.3.1
 + iniconfig==2.3.1
 + jsonschema==4.26.0
 + jsonschema-specifications==2025.9.1
 + license-expression==30.4.4
 + mako==1.4.3
 + markdown-it-py==4.2.0
 + markupsafe==3.0.4
 + mdurl==0.1.2
 + msgpack==1.2.3
 + numpy==2.5.4
 + opentelemetry-api==1.45.1
 + ortools==9.15.6755
 + packageurl-python==0.17.6
 + packaging==26.3
 + pandas==3.0.6
 + pdfminer-six==20260107
 + pdfplumber==0.11.10
 + pillow==12.3.0
 + pip==26.2.1
 + pip-api==0.0.35
 + pip-audit==2.10.1
 + pip-requirements-parser==32.0.1
 + platformdirs==4.13.3
 + pluggy==1.7.0
 + protobuf==6.33.6
 + psycopg==3.3.6
 + psycopg-binary==3.3.6
 + py-serializable==2.1.0
 + pycparser==3.11
 + pydantic==2.14.1
 + pydantic-core==2.50.1
 + pydantic-settings==2.16.0
 + pygments==2.21.0
 + pyjwt==2.15.1
 + pyparsing==3.3.3
 + pypdf==6.20.1
 + pypdfium2==5.14.0
 + pytest==9.1.1
 + python-dateutil==2.9.0.post0
 + python-dotenv==1.2.4
 + python-multipart==0.0.32
 + referencing==0.37.0
 + requests==2.34.2
 + rich==15.0.0
 + rpds-py==2026.9.1
 + ruff==0.17.1
 + six==1.17.0
 + sortedcontainers==2.4.0
 + sqlalchemy==2.1.4
 + starlette==1.8.0
 + tomli==2.5.0
 + tomli-w==1.2.0
 + typing-extensions==4.16.0
 + typing-inspection==0.4.4
 + tzlocal==5.4.4
 + urllib3==2.8.0
 + uvicorn==0.54.0
exit=0

## 步骤 3
$ CARDFLOW_TEST_DATABASE_URL="$(../../tools/dev-db.sh url)" uv run pytest -q
..............................................                           [100%]
=============================== warnings summary ===============================
.venv/lib/python3.13/site-packages/fastapi/testclient.py:1
  /projects/cardflow/services/api/.venv/lib/python3.13/site-packages/fastapi/testclient.py:1: StarletteDeprecationWarning: Using `httpx` with `starlette.testclient` is deprecated; install `httpx2` instead.
    from starlette.testclient import TestClient as TestClient  # noqa

-- Docs: https://docs.pytest.org/en/stable/how-to/capture-warnings.html
46 passed, 1 warning in 0.76s
exit=0

## 步骤 4
$ uv run ruff check . && uv run ruff format --check .
All checks passed!
41 files already formatted
exit=0
