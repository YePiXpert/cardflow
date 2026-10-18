# 卡序 CardFlow

多信用卡管理 App（iOS/Android + 自托管后端 + Web 后台）的规划工作区。规划轮产出于 2026-10-16。

- `docs/` — 完整规划文档集（入口：`docs/README.md`；追踪矩阵：`docs/requirements-traceability.md`）
- `poc/engine_reference/` — 参考引擎 PoC（账期、现金时间线、CP-SAT 分配、独立验证器；40 项测试，证据见 `EVIDENCE.md`）

本仓库不含真实金融数据；所有样本为合成数据。下一步：按 `docs/80-delivery/phase-1-tasks.md` 启动 M0。

## 目录结构

| 路径 | 内容 | 状态 |
|---|---|---|
| `docs/` | 规划文档（唯一事实来源） | 已完成 |
| `poc/engine_reference/` | 参考引擎 PoC（golden-fixture 预言机，非生产代码） | 已验证 |
| `services/api/` | 服务端：FastAPI 模块化单体 + worker + CLI；Python 3.13，uv 管理，包 `cardflow`（平铺布局，模块划分见 architecture §4） | M0 骨架（T-002） |
| `apps/mobile/` | Flutter 移动端（占位：待 Flutter 环境，见 external-dependencies B-06、ADR-015） | 未实现 |
| `apps/admin/` | Web 后台 React SPA（占位，T-031） | 未实现 |
| `packages/rules-protocol/` | 规则协议 v1 JSON Schema 与运行器（占位，T-004） | 未实现 |
| `deploy/` | Compose 文件：`compose.dev.yaml` = 开发库（项目名 `cardflow-dev`，仅 127.0.0.1:18432）；`compose.yaml` = 自托管部署（项目名 `cardflow`，仅 127.0.0.1:18080，见下文"部署"）；`.env.example`；`secrets/`（只有 README 入库） | 开发库可用；部署可用（T-012） |
| `tools/` | 开发脚本：`dev-db.sh`（开发库管理）、`build-api-image.sh`（构建 `cardflow/api` 镜像）、`gen-secrets.sh`（生成部署 secret）、`pii_scan.py`（日志 PII 扫描） | |
| `evidence/m0/<任务ID>/` | M0 验收证据：工具输出原文（用 `tee` 保存）；不得含口令、令牌或真实金融数据 | |

## 本地启动（服务端，到"测试通过"为止）

前置：Python 3.13、uv ≥ 0.12、Docker + Compose v2。在仓库根目录执行；只占用 127.0.0.1 端口（开发库 18432，API 示例 18081）。

1. 启动开发数据库。首次运行会生成 `deploy/secrets.dev/db_password`（权限 600，已在 `.gitignore` 中）：
   ```bash
   tools/dev-db.sh up
   ```
2. 安装服务端依赖（只装进 `services/api/.venv`，版本由 `uv.lock` 锁定）：
   ```bash
   cd services/api
   uv sync --locked
   ```
3. 运行测试。DB 测试使用开发库的 superuser URL，在临时库 `cardflow_test_<随机>` 中运行，结束后删除；未设置该变量或连不上数据库时，DB 测试**报错**而不是跳过：
   ```bash
   CARDFLOW_TEST_DATABASE_URL="$(../../tools/dev-db.sh url)" uv run pytest -q
   ```
   没有数据库时显式排除：`uv run pytest -q -m "not db"`。
4. 代码检查：
   ```bash
   uv run ruff check . && uv run ruff format --check .
   ```
5. （可选）启动 API：`uv run cardflow api --port 18081`，另开终端执行 `curl -sS 127.0.0.1:18081/healthz`，返回 `{"status":"ok"}`；Ctrl+C 停止。

开发库其他命令：`tools/dev-db.sh status | psql | url | down`（`down` 保留数据卷）；`tools/dev-db.sh reset` 删除 `cardflow-dev` 的数据卷后重建空库。
数据库迁移（T-005）：Alembic 脚本在 `services/api/alembic/`，测试会把临时库自动迁移到 head（`CARDFLOW_TEST_MIGRATION_TARGET=0001` 可临时固定到某个修订，仅供开发期使用）。手工迁移开发库（在 `services/api` 下）：
`DATABASE_URL=postgresql+psycopg://cardflow@127.0.0.1:18432/cardflow DATABASE_PASSWORD_FILE=../../deploy/secrets.dev/db_password uv run cardflow migrate`
（`--lock` 在 PostgreSQL advisory lock 下升级；`--check` 只比较库版本与 head，一致退出 0，否则 1）。触发器与函数的指纹按修订登记在 `services/api/tests/db/golden_objects.json`；有意修改触发器/函数或新增修订后，在 `services/api` 下执行 `CARDFLOW_UPDATE_GOLDEN=1 uv run pytest tests/db/test_db_objects.py` 重新生成，并像代码一样审阅该文件的差异。
后台任务 worker（T-008，ADR-003）：`cardflow worker [--concurrency N] [--once] [--shutdown-timeout 秒]`，环境变量同上（`DATABASE_URL` + `DATABASE_PASSWORD_FILE`，库须已迁移）；SIGTERM/Ctrl+C 优雅退出（第二次信号立即停止），设计说明见 `services/api/cardflow/jobs/worker.py` 模块文档。`cardflow backup` 尚未实现（T-013），运行时以退出码 2 结束。
数据库角色与行级安全（T-006，迁移 0003）：迁移必须以 PostgreSQL 超级用户运行，它创建 NOLOGIN 组角色 `cardflow_app`/`cardflow_worker`/`cardflow_admin`/`cardflow_purge`/`cardflow_admin_views`（集群级，降级时保留），并对所有带 `workspace_id` 的表启用 FORCE RLS。各进程用各自的 LOGIN 角色连接：在 `cardflow migrate` 之后执行 `cardflow db-provision`（连接参数同 migrate；口令从 `DATABASE_API_PASSWORD_FILE`、`DATABASE_WORKER_PASSWORD_FILE`、`DATABASE_ADMIN_PASSWORD_FILE` 读取，至少 16 个字符；幂等，口令不输出；`--role api|worker|admin` 只处理指定角色），它建立或更新 `cardflow_api`、`cardflow_worker_login`、`cardflow_admin_login`；之后 api/worker 的 `DATABASE_URL` 换成对应用户名，`DATABASE_PASSWORD_FILE` 指向对应口令文件。设计、授权矩阵与威胁模型见 `evidence/m0/T-006/rls-design.md`。

## 部署（自托管 Compose，T-012）

前置：Docker 29 与 Compose v2（实测 Compose v5.6），以 root 在仓库根目录执行。

**隔离约定**：
- 每条命令都写 `-p cardflow -f deploy/compose.yaml`；
- 宿主上只发布 `127.0.0.1:${CARDFLOW_API_PORT:-18080}`，数据库不发布端口；
- 网络、卷都归本项目所有：`cardflow_backend` 是 internal 网络，`cardflow_edge` 只承载 api 的回环端口；卷为 `cardflow_pgdata`、`cardflow_attachments`；
- 不使用宿主的 PostgreSQL（5432），也不动其他项目。

1. **构建镜像**：
   ```bash
   tools/build-api-image.sh
   ```
   - 最后一行输出版本号，镜像标签为 `cardflow/api:<版本>`。
   - **版本规则**：`<pyproject 版本>-<源码摘要前 12 位>`，例如 `0.1.0-3166fe6bf311`。摘要按路径排序，对 Dockerfile、.dockerignore、pyproject.toml、uv.lock、.python-version、alembic.ini、alembic/、cardflow/ 逐文件计算 SHA-256。源码相同则标签相同，源码有任何改动都得到新标签。
   - 脚本先把这些文件复制到临时快照里，再从快照计算摘要并构建，所以标签描述的正是镜像里的内容。`--source DIR` 可以指定其他源码目录，`--version` 只打印版本号。
   - 镜像说明：
     - 多阶段构建，基础镜像是按 digest 固定的 `python:3.13-slim-trixie`；
     - 依赖按 `uv.lock --locked` 安装，不含 dev 组；
     - 保留源码布局（`/app/cardflow` 与 `/app/alembic.ini` 相邻），`cardflow migrate` 在容器内可用；
     - 运行层没有编译工具链，以 uid/gid 10001 运行。
2. **配置**：
   ```bash
   cp deploy/.env.example deploy/.env
   ```
   把 `CARDFLOW_VERSION=` 设为上一步输出的版本号。其余都是非敏感配置，默认值见 deployment-ops §2。
3. **生成 secret**：
   ```bash
   tools/gen-secrets.sh
   ```
   - 在 `deploy/secrets/` 下生成 7 个文件：数据库超级用户口令、三个登录角色口令、`jwt_key`、`kek`、`backup_passphrase`。
   - 已有文件不覆盖。目录 0700，文件 0600，属主为容器用户 10001。
   - 每个文件的用途和轮换方法见 `deploy/secrets/README.md`。
   - **`backup_passphrase` 和 `kek` 必须另行离线保存。**
   - 口令和密钥只通过 Compose secrets（`/run/secrets/*`）进入容器，环境变量里只有文件路径。
4. **启动**：
   ```bash
   docker compose -p cardflow -f deploy/compose.yaml up -d
   ```
   启动顺序为：
   - `db` 健康；
   - `migrate`：以超级用户执行 `cardflow migrate --lock`；
   - `provision`：以超级用户执行 `cardflow db-provision`，建立 `cardflow_api`、`cardflow_worker_login`、`cardflow_admin_login`；
   - `api`（以 `cardflow_api` 连接）与 `worker`（以 `cardflow_worker_login` 连接，`--concurrency 2`，停止宽限 30 s）。

   常驻进程都不以超级用户连接。api、worker 的文件系统只读，`/tmp` 为 tmpfs，丢弃全部 capability。
5. **检查**：
   ```bash
   docker compose -p cardflow -f deploy/compose.yaml ps        # api (healthy)；migrate、provision 为 Exited (0)
   curl -sS -i 127.0.0.1:18080/readyz                          # 200，四项检查都为 true
   curl -sS 127.0.0.1:18080/healthz                            # {"status":"ok"}
   docker compose -p cardflow -f deploy/compose.yaml logs --no-color | python3 tools/pii_scan.py -   # 0 命中
   ```
   - `/readyz` 返回 `{"checks":{"database":…,"migrations":…,"worker":…,"attachments":…},"version":"<CARDFLOW_VERSION>","head":"<Alembic head>"}`，任一项为 false 时返回 503。四项含义：
     - `database`：以 api 自己的角色新建连接；
     - `migrations`：库版本等于代码 head；
     - `worker`：2 分钟内有 worker 心跳；
     - `attachments`：附件卷可写。
   - 整个检查在 3 s 内返回。api 容器的健康检查就是 `/readyz`。
   - `/docs`、`/redoc`、`/openapi.json` 在生产环境关闭，开发时可用 `API_DOCS_ENABLED=true` 打开；`create_app().openapi()` 在代码里始终可用。
6. **升级**：
   - 重新构建，得到新版本号；
   - 更新 `deploy/.env` 中的 `CARDFLOW_VERSION`；
   - 执行 `docker compose -p cardflow -f deploy/compose.yaml up -d`，`migrate` 会带锁先行。

   回滚时把 `CARDFLOW_VERSION` 改回旧值（迁移的回滚见 deployment-ops §3）。
7. **停止**：
   ```bash
   docker compose -p cardflow -f deploy/compose.yaml down
   ```
   停止并删除本项目的容器和网络，**保留数据卷**。不要加 `-v`，除非确实要删除数据库与附件。

备份服务 `backup` 放在 profile `backup` 下，普通的 `up` 不会启动它。`cardflow backup` 由 T-013 实现。部署证据见 `evidence/m0/T-012/`。
