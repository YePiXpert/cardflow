# T-002 · 锁定版本与 architecture §11 对照

生成于 2026-10-16。来源：`services/api/uv.lock`（lock version 1 / revision 5，`requires-python = ==3.13.*`，共 86 个包），
由 `python3 -I /tmp/.../lock_versions.py uv.lock <包名…>` 读取；原始输出见本文末尾。
解释器：CPython 3.13.5（`/usr/bin/python3.13`，`services/api/.python-version` = `3.13`）；uv 0.12.23。
PyPI 可用性于同日用 `https://pypi.org/pypi/<pkg>/json` 逐一核验：§11 列出的版本**全部存在**，因此没有任何"选最接近版本"的替代。

## 1. architecture §11 列出的后端组件

| 组件 | §11 版本 | 锁定版本 | 一致 | 说明 |
|---|---|---|---|---|
| Python | 3.13 | 3.13.5（requires-python `>=3.13,<3.14`） | 是 | |
| fastapi | 0.143.2 | 0.143.2 | 是 | PyPI 已有 0.143.3；按 §11 固定 0.143.2 |
| uvicorn | 0.54.0 | 0.54.0 | 是 | 未装 `[standard]` 额外依赖。许可证实为 BSD-3-Clause（§11 该行合写为 MIT，文档小误，未改文档） |
| pydantic | 2.14.1 | 2.14.1 | 是 | pydantic-core 2.50.1（传递） |
| sqlalchemy | 2.1.4 | 2.1.4 | 是 | |
| alembic | 1.20.0 | 1.20.0 | 是 | |
| psycopg（`[binary]`） | 3.3.6 | 3.3.6（psycopg-binary 3.3.6） | 是 | LGPL-3.0 |
| ortools | 9.15.6755 | 9.15.6755 | 是 | 传递：numpy 2.5.4、pandas 3.0.6、protobuf 6.33.6 |
| pypdf | 6.20.1 | 6.20.1 | 是 | PyPI 已有 6.21.0；按 §11 固定 6.20.1 |
| pdfplumber | 0.11.10 | 0.11.10 | 是 | 传递：pdfminer.six 20260107、pypdfium2 5.14.0、pillow 12.3.0 |
| rapidocr + onnxruntime | 3.10.0 + 1.31.0 | 未安装 | 按简报 | 简报要求不装，由 T-030 决定 |
| pyjwt | 2.15.1 | 2.15.1 | 是 | |
| argon2-cffi | 25.1.0 | 25.1.0 | 是 | |
| cryptography | 50.0.2 | 50.0.2 | 是 | |
| apscheduler | 3.11.3 | 3.11.3 | 是 | 3.x（4.x 为 alpha，不用） |
| pytest（dev） | 9.1.1 | 9.1.1 | 是 | |
| hypothesis（dev） | 6.170.0 | 6.170.0 | 是 | |
| PostgreSQL | 18.6（`postgres:18.6-trixie`） | 开发库镜像 `postgres:18.6-trixie`，`server_version` = 18.6 (Debian 18.6-1.pgdg13+2) | 是 | 见 `dev-db-check.txt` |

## 2. 简报要求但 §11 未列版本的包（取 2026-10-16 PyPI 最新稳定版并精确固定）

| 包 | 锁定版本 | 许可证 | 用途 |
|---|---|---|---|
| pydantic-settings | 2.16.0 | MIT | `cardflow/settings.py` |
| httpx | 0.28.1 | BSD-3-Clause | FastAPI TestClient；后续出站 HTTP |
| jsonschema | 4.26.0 | MIT | T-004 规则协议校验 |
| python-multipart | 0.0.32 | Apache-2.0 | multipart 上传（API-20） |
| ruff（dev） | 0.17.1 | MIT | lint/format |
| pip-audit（dev） | 2.10.1 | Apache-2.0 | 依赖漏洞审计（`pip-audit.txt`：No known vulnerabilities found） |

## 3. 值得注意的传递依赖

| 包 | 版本 | 来源 | 说明 |
|---|---|---|---|
| starlette | 1.8.0 | fastapi | 1.x 系列。其 TestClient 对 `httpx` 发出 `StarletteDeprecationWarning`，建议改用 `httpx2`（pydantic 维护的分支，PyPI 2.13.1）。简报只允许 `httpx`，故未引入 `httpx2`；测试输出中保留该警告，供后续决定 |
| opentelemetry-api | 1.45.1 | fastapi（必选依赖） | 只有 API、没有 SDK/导出器，默认无任何数据外发；`create_app()` 仍显式关闭 FastAPI 原生遥测（它会记录异常消息与校验输入） |
| python-dotenv | 1.2.4 | pydantic-settings | 未使用：Settings 不读取 .env 文件 |

## 4. 确认未引入

Redis、Celery、rapidocr、onnxruntime、pymupdf、uvicorn[standard] 系列（uvloop/httptools/watchfiles/websockets）均不在 `uv.lock` 中。

## 5. 原始输出

```
$ python3 -I lock_versions.py uv.lock fastapi uvicorn pydantic pydantic-settings sqlalchemy alembic psycopg psycopg-binary ortools pyjwt argon2-cffi cryptography pypdf pdfplumber apscheduler httpx jsonschema python-multipart pytest hypothesis ruff pip-audit starlette pydantic-core opentelemetry-api numpy pandas protobuf pdfminer-six pypdfium2 pillow rapidocr onnxruntime redis celery
lock version=1 revision=5 requires-python===3.13.* packages=86
fastapi                0.143.2
uvicorn                0.54.0
pydantic               2.14.1
pydantic-settings      2.16.0
sqlalchemy             2.1.4
alembic                1.20.0
psycopg                3.3.6
psycopg-binary         3.3.6
ortools                9.15.6755
pyjwt                  2.15.1
argon2-cffi            25.1.0
cryptography           50.0.2
pypdf                  6.20.1
pdfplumber             0.11.10
apscheduler            3.11.3
httpx                  0.28.1
jsonschema             4.26.0
python-multipart       0.0.32
pytest                 9.1.1
hypothesis             6.170.0
ruff                   0.17.1
pip-audit              2.10.1
starlette              1.8.0
pydantic-core          2.50.1
opentelemetry-api      1.45.1
numpy                  2.5.4
pandas                 3.0.6
protobuf               6.33.6
pdfminer-six           20260107
pypdfium2              5.14.0
pillow                 12.3.0
rapidocr               (not in lock)
onnxruntime            (not in lock)
redis                  (not in lock)
celery                 (not in lock)

$ uv tree --depth 1 --frozen
cardflow v0.1.0
├── alembic v1.20.0
├── apscheduler v3.11.3
├── argon2-cffi v25.1.0
├── cryptography v50.0.2
├── fastapi v0.143.2
├── httpx v0.28.1
├── jsonschema v4.26.0
├── ortools v9.15.6755
├── pdfplumber v0.11.10
├── psycopg[binary] v3.3.6
├── pydantic v2.14.1
├── pydantic-settings v2.16.0
├── pyjwt v2.15.1
├── pypdf v6.20.1
├── python-multipart v0.0.32
├── sqlalchemy v2.1.4
├── uvicorn v0.54.0
├── hypothesis v6.170.0 (group: dev)
├── pip-audit v2.10.1 (group: dev)
├── pytest v9.1.1 (group: dev)
└── ruff v0.17.1 (group: dev)
```
