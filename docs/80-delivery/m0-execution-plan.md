# 83 · M0 执行计划（派发版）

版本 0.1 · 2026-10-16 · 状态：**批次 A 于 2026-10-18 冻结**。已验证 10 项（T-001~T-008、T-014、T-006），T-011/T-012/T-030 在中断处冻结；后续安排见 `ios-first-plan.md`（iOS 优先、纯本地、GitHub Actions 出未签名 IPA）。原因：用户只需要 iOS 端且无 Mac；两天的实现全部在可选的后端上，用户没有可用之物；后端加固深度超出当前阶段。本文把 `phase-1-tasks.md` 的 27 项任务变成可直接派发给 Opus 子代理的执行顺序、简报、证据规则与退出条件。规划轮已结束；本文写入后，在收到"开始 M0"前不启动任何实现。

## 1. 前提与待决定项

| 编号 | 事项 | 默认处理（用户未另行指示时） |
|---|---|---|
| D-1 | 是否启动 M0 编码 | **已启动（2026-10-16，用户："继续开发"）**：先做批次 A |
| D-2 | 移动端环境：本机安装 Flutter + Android SDK，或用户另供机器 | 不安装；批次 B 标"待环境" |
| D-3 | 本地 `git init`（不建远程仓库） | 待确认；建议启动即初始化，便于审查 diff 与回滚 |
| D-4 | 招行页面文本（B-04） | 不阻塞 M0 |
| D-5 | VPS 域名/反代授权（B-05） | 不阻塞 M0；M0 只部署到 127.0.0.1 |
| D-6 | 真机（Android/iPhone） | 批次 B 的真机 PoC 需要；缺失则模拟器先行并标注 |
| D-7 | 移动端分发与签名 | **已决定（2026-10-16）**：用户自签安装，v1 不上架、不走 TestFlight（ADR-015）；不阻塞 M0 |

本机条件（已核验）：Python 3.13 + uv、OR-Tools 9.15.6755 可用、Node 24、Docker 29 + Compose v5.6；无 Flutter/Android SDK/Mac；端口 18080 未被占用。

## 2. 执行模型

- **主会话（Fable）**：拆分与派发、审查裁决、验收、更新追踪矩阵；不直接写大段实现代码。
- **实现子代理（Opus）**：一个任务一个代理；只在简报指定的路径内工作；交付物 + 测试输出 + 证据文件。
- **审查子代理（Opus，新上下文）**：拿到实现代理的产物与清单，不看实现代理的结论；输出"发现清单"（缺陷/偏离规格/缺证据），主会话裁决后回流修复。
- **证据规则**：所有"完成"声明必须对应 `evidence/m0/<task>/` 下的工具输出（测试日志、命令输出、哈希）；没有输出不计完成。
- **停止条件**：任一任务触及"禁止事项"（改金额语义、引入未核验依赖、用 float、跳过 fixture、把 mock 当完成）即停止并上报。
- **简报模板**（每次派发都用）：目标与 R-ID → 必读文档 → 交付物路径 → 验收命令与期望输出 → 禁止事项 → 证据路径 → 不要做的事（不改其他模块/协议/ADR）。

## 3. 批次与顺序

### 批次 A · 服务端与工程基础（本机可做，无外部凭证）

| 周 | 并行组 | 任务 | 前置 |
|---|---|---|---|
| 1 | A1 | T-001 仓库骨架；T-002 FastAPI 工程 | — |
| 1 | A2 | T-003 PoC 引擎迁入 `planner/engine`；T-004 规则协议 v1 | T-002 |
| 1 | A3 | T-005 初始 Alembic 迁移；T-010 幂等中间件 | T-002 |
| 2 | A4 | T-006 RLS + 绕过测试；T-007 约束触发器；T-008 jobs 表与 worker | T-005 |
| 2 | A5 | T-011 设备令牌；T-012 隔离 Compose + /readyz | T-005 |
| 2 | A6 | T-009 求解接口接入 worker | T-003/T-008 |
| 3 | A7 | T-013 备份与恢复演练；T-014 PII 扫描；T-015 CI | T-012 等 |
| 3 | A8 | T-030 解析管线骨架 + 恶意样本集；T-031 后台骨架 | T-008/T-011 |
| 3 | A9 | T-040 交叉审查（财务语义、安全）；T-041 验收与矩阵更新 | 全部 |

#### 实际执行波次（2026-10-16 按依赖调整）

| 波次 | 任务 | 调整原因 |
|---|---|---|
| 1 | T-001 + T-002 | — |
| 2 | T-003；T-005 + T-007（合并）；T-014 | T-007 的触发器属于初始迁移，合并可避免两个迁移并行产生多头；T-014 只依赖 T-001 |
| 3 | T-004；T-006；T-008 | T-004 依赖 T-003；T-006、T-008 依赖迁移 0001 |
| 4 | T-011；T-012；T-030 | T-011 的设备注册要在 RLS 下工作，排在 T-006 之后；T-030 依赖 T-008 |
| 5 | T-009；T-010；T-013；T-031 | T-009、T-010 需要 T-011 的鉴权依赖；T-013 依赖 T-012；T-031 依赖 T-011/T-012 |
| 6 | T-015 | CI 最后接入全部任务 |
| 7 | T-040 交叉审查 → 修复 → T-041 验收 | — |

每个波次结束：主会话复跑测试并核对证据 → 新上下文审查代理（财务/安全相关任务）→ 修复 → 进入下一波。迁移编号由主会话分配，避免并行任务产生多个 head：0001 初始（T-005/T-007）、0002 审查后的结构修订（T-005 修订轮）、0003 RLS 与角色（T-006），之后按需递增。尚无任何部署，修订仍以新迁移表达，避免与并行任务冲突。

### 批次 B · 移动端（待 D-2/D-6）

T-020 工程骨架 → T-021 加密库真机 PoC → T-022 Dart 领域层移植（F-18 双端通过）→ T-023 有限搜索 → T-024 文件接入 → T-025 中文 OCR 评估 → T-026 通知/后台任务 → T-027 安全存储与应用锁。Android 可在 Linux 完成；iOS 相关验证待 Mac。签名与分发按 ADR-015（用户自签）：T-020 起 Bundle ID/applicationId 与签名配置参数化，仓库不含密钥与团队 ID；iOS 真机 PoC 以用户自签的构建为准。

### 批次 C · 验收

T-040 两名审查代理（财务语义 / 安全与数据隔离）→ 主会话裁决 → T-041 更新 `requirements-traceability.md` 状态列与 `evidence/m0/INDEX.md`。

## 4. 派发简报（批次 A）

每条给出：目标 · 必读 · 产出 · 验收 · 禁止。

**T-001 仓库骨架** · 目标：建立 monorepo 目录与根 README、`evidence/` 约定。必读：`architecture.md` §4、`milestones-workpackages.md` WP-01。产出：`apps/mobile/`（占位）、`services/api/`、`apps/admin/`（占位）、`packages/rules-protocol/`、`deploy/`、`evidence/m0/`、根 `README.md`（启动步骤）。验收：目录存在；README 步骤可执行到"服务端测试通过"。禁止：不引入未列出的工具链。

**T-002 服务端工程** · 目标：FastAPI 0.143 + pydantic 2.14 + SQLAlchemy 2.1 + Alembic 1.20 + psycopg 3.3 + uv 锁文件；`cardflow` 包按 `architecture.md` §4 分模块；`/healthz`。验收：`uv run pytest` 通过（含一个 smoke 测试）；`uv run cardflow api` 启动后 `/healthz` 200。禁止：不装 Redis/Celery；版本以 `architecture.md` §11 为准。

**T-003 引擎迁入** · 目标：`poc/engine_reference/cardflow_ref` → `services/api/cardflow/planner/engine/`（无 FastAPI/SQLAlchemy 导入），测试与 fixture 一并迁入。验收：40 项测试通过，输出存 `evidence/m0/T-003/pytest.txt`；`run_sample.py` 输出与 `poc/engine_reference/EVIDENCE.md` 数值一致。禁止：不改任何语义；不改 fixture 期望值。

**T-004 规则协议 v1** · 目标：JSON Schema（BillingRule、Snapshot、CashEvent、Scenario、PlanRequest、CardOption、PlanOutcome）+ Python 运行器 `runner_py`；fixture 经 schema 校验后由运行器执行并与期望比对。验收：F-18 通过；schema 版本写入 PlanOutcome。禁止：schema 不得允许 float 金额。

**T-005 初始迁移** · 目标：按 `data-model.md` §3/§4 建表（10 组实体），`currencies` 种子数据。验收：空库 `upgrade head` → `downgrade base` → `upgrade head` 通过；`evidence/m0/T-005/alembic.txt`。禁止：金额列用浮点；缺 `workspace_id`。

**T-006 RLS** · 目标：所有带 `workspace_id` 的表启用并 FORCE RLS，`cardflow_app`/`cardflow_admin` 角色，模板表只读策略；测试 TC-DB-04/05/06。验收：错误 workspace 读/写/关联均失败；admin 读正文列失败。禁止：以注释代替策略。

**T-007 约束触发器** · 目标：`statement_versions` 金额列追加只读触发器；`repayment_allocations` 和不超过还款额（延迟约束触发器）；幂等键唯一。验收：TC-DB-01/07/09。

**T-008 jobs 与 worker** · 目标：`jobs` 表、`FOR UPDATE SKIP LOCKED` 领取、租约心跳、指数退避、死信、子进程硬超时；`cardflow worker` 命令。验收：TC-DB-10 并发不重复；超时任务进入 failed/dead；`evidence/m0/T-008/`。禁止：引入 Redis。

**T-009 求解接口** · 目标：API-50/51/52 最小版；求解在 worker 子进程执行；`plan_runs`/`plan_allocations`/`plan_run_checks` 写入。验收：提交 fixture 请求 → 202 → 运行记录 `business_status=CONDITIONALLY_FEASIBLE`、`allocation={A:800000,C:200000}`。禁止：在 API 进程内同步求解。

**T-010 幂等与错误信封** · 目标：`Idempotency-Key` 中间件（同键同哈希返回首次响应，不同哈希 409）、错误信封与错误码表。验收：集成测试。

**T-011 设备注册与令牌** · 目标：API-01/02；PyJWT 短期令牌 + 刷新轮换 + 撤销表；argon2id（预留账号口令）。验收：注册→访问→刷新→撤销→401。禁止：第三方登录。

**T-012 隔离 Compose** · 目标：`deploy/compose.yaml`（api/worker/db/migrate/backup）、secrets 文件约定、`/readyz`（DB + Alembic 版本 + worker 心跳 + 附件卷）。验收：`docker compose -p cardflow up -d` 后 `curl 127.0.0.1:18080/readyz` 200；`ss -tlnp` 仅回环端口；`evidence/m0/T-012/`。禁止：使用宿主 5432/6379；绑定 0.0.0.0。

**T-013 备份与恢复演练** · 目标：`cardflow backup`（pg_dump -Fc + 附件 tar + manifest + AES-GCM）、`cardflow restore-drill`（隔离项目恢复 + 一致性检查）。验收：演练报告 `evidence/m0/T-013/restore-drill.md`。

**T-014 PII 扫描** · 目标：`tools/pii_scan.py` 扫描日志样本中的金额/卡号片段/令牌；接入 CI。验收：注入样本被检出。

**T-015 CI** · 目标：lint、单元/性质、fixture、DB/API 集成（真实 Postgres）、迁移往返、pip-audit。验收：一次全绿记录。

**T-030 解析管线骨架** · 目标：pypdf/pdfplumber 文本层抽取 → 候选（含原始位置、解析器版本、校验）；rapidocr 兜底开关；类型嗅探/大小/超时/zip 不递归；F-47 恶意样本集（合成）。验收：F-47 全部拒绝或隔离；文本层样本产出候选。禁止：pymupdf、Syncfusion。

**T-031 后台骨架** · 目标：React 19 + Vite 8 + TS 7；AP-01 登录与角色、AP-07 系统状态；由 api 以 `/admin` 静态提供。验收：operator 登录后无正文入口，直接调正文接口 403 且有审计。

## 5. M0 退出条件（验收用）

1. PoC-7 达成：Alembic + RLS + jobs + CP-SAT 子进程硬超时 + 解析骨架集成测试通过。
2. F-18 在 Python 运行器通过；Dart 运行器通过或标"待环境"。
3. TC-DB-01~10 通过；RLS 绕过测试失败即阻断。
4. Compose 在 127.0.0.1:18080 启动，`/readyz` 绿，端口无冲突。
5. 恢复演练报告存在且一致性检查通过。
6. CI 全绿记录；日志 PII 扫描接入。
7. 批次 B 的 PoC-1~5 达成或逐项标"待环境/待真机"。
8. `requirements-traceability.md` 状态列更新；`evidence/m0/INDEX.md` 列出全部证据。
9. 规则协议 v1（`packages/rules-protocol/schema/v1/`）在 M0 验收时冻结：此后任何改变输入合法性或字段含义的修改都发 v2，v1 只做不改变语义的修正。

## 6. 风险与回退

| 风险 | 回退 |
|---|---|
| 加密库钩子真机失败（PoC-1） | sqflite_sqlcipher（ADR-001 备选） |
| 自建 jobs 复杂度超预期 | 保持范围（5 种任务类型），不扩展；规模增长再评估 procrastinate |
| CP-SAT 子进程在容器内 CPU 受限 | 调低 `num_workers`，记录到运行记录 |
| 无 Flutter 环境 | 批次 B 整体后移，不阻塞批次 A 验收 |

## 7. 状态跟踪表（随执行更新）

| 任务 | 状态 | 实现代理产出 | 审查结论 | 证据 |
|---|---|---|---|---|
| T-001 | 已验证 | 目录骨架、根 README 启动步骤、占位 README | 主会话复核（脚手架，未单独派审查） | `evidence/m0/T-001/` |
| T-002 | 已验证 | `services/api`（uv 锁 86 包、21 模块包、settings/db/错误信封/JSON 日志/CLI）、`deploy/compose.dev.yaml`、`tools/dev-db.sh` | 主会话复跑 46 passed（7 项真实 PG） | `evidence/m0/T-002/` |
| T-003 | 已验证 | `cardflow/planner/engine/`（7 模块与 PoC AST 一致）、`tests/engine/`（40 项迁移 + 23 项依赖边界）、fixture 复制到 `packages/rules-protocol/fixtures/`（sha256 一致）、`python -m cardflow.planner.engine.sample` | 主会话复跑 63 passed；样本输出屏蔽计时后与 PoC 一致。汇报的 PoC 缺陷（验证器未知卡号崩溃、input_hash 取自修改后输入、workers/seed 未透传）转入 T-004 一并修正 | `evidence/m0/T-003/` |
| T-004 | 已验证（引擎 1.1.0）。财务审查 `evidence/m0/review-wave3-engine.md`（无 blocker，8 major）→ T-004c 修正 R3E-01~22（裁决 engine-spec §12/§12.1）：主会话复跑 tests/engine+protocol 434 passed、F-18 23/23、fixture 哈希不变；差分测试默认 1,200 例、fuzz 12,000 例 0 失配（修正前同一测试有数百处失配）；证据 `c2-*`。此前（含 T-004b 健壮性修正：数值范围与建模异常兜底、还款日早于交易/快照、负额度池截零、验证器拒绝非整数；主会话追加"无可用卡 → INFEASIBLE"，证据 `c-no-eligible-cards.txt`；tests/engine + tests/protocol 310 passed） | `packages/rules-protocol/schema/v1/`（13 个 schema）、派生 fixture `*.v1.json`、`runner_py/`（转换器与运行器）、`cardflow/planner/engine/protocol.py`、引擎修正（验证器未知卡号、input_hash、workers/seed、MODEL_VERSION 1.0.0、run_id 透传）、`tests/protocol/`（158 项）、`tests/engine/` 新增 16 项 | 主会话复跑 283 passed（非 DB）；运行器 F-18 23/23、退出码 0；sample 仅版本与计时不同。T-004b：数值范围、还款日早于快照、负额度池截零、验证器拒绝非整数 | `evidence/m0/T-004/` |
| T-005 | 已验证（含修订轮：迁移 0002 处置 R2-01~R2-34，暂缓项见 data-model §10.11；R2-23 的扩展回滚问题转 T-006） | `alembic/versions/0001_initial.py`（58 张表 + worker_heartbeats、9 函数、15 触发器、currencies 种子）、各模块 `models.py`、`cardflow/db/migrations.py`、`cardflow migrate [--lock\|--check]`、`tests/db/`（77 项） | 审查 `evidence/m0/review-wave2-schema.md`（无 blocker；9 major/18 minor/9 nit）。修订后主会话复跑全量 633 passed（tests/db 139、tests/jobs 在 head 122）；0001↔0002、base↔head 往返目录逐项一致；金样清单守护触发器与函数 | `evidence/m0/T-005/`（含 `0002-*`、`0002-r2-map.md`）、`evidence/m0/T-007/` |
| T-006 | 已验证（迁移 0003） | 迁移 0003（5 个组角色、57 表 ENABLE+FORCE RLS、78 条策略、声明式列级授权、admin 视图 6 个、收回 TEMP/EXECUTE）；`cardflow db-provision`；`cardflow/db/roles.py`；`tests/db/test_rls*.py`、`test_db_provision.py`；role fixtures（app/worker/purge/admin engine） | 主会话复跑全量 722 passed；集群组角色均 NOLOGIN、无 BYPASSRLS。0002↔0003 往返目录（含策略与 ACL）一致；10 个安全变异全部被抓到。待 T-040 复核：分配合计触发器 SECURITY DEFINER 属主为超级用户 | `evidence/m0/T-006/`（含 `rls-design.md`） |
| T-007 | 已验证（并入 T-005） | 见 T-005 | 见 T-005 | `evidence/m0/T-007/` |
| T-008 | 已验证（基于 0001；0002 落地后在 head 复跑） | `cardflow/jobs/`（queue、worker、subproc/child、registry、context、periodic、backoff 等）、`cardflow worker [--concurrency\|--once\|--shutdown-timeout]`、`tests/jobs/`（122 项） | 主会话复跑 122 passed；生产注册表为空；并发 400 任务重复 0；真实 worker 运行 37 s、SIGTERM 退出码 0、日志 PII 0 命中。自查修复了信号处理死锁与退避单调性问题 | `evidence/m0/T-008/` |
| T-009 | 未开始 | | | |
| T-010 | 未开始 | | | |
| T-011 | 进行中（波次 4，迁移 0004：配对码、definer 查找函数、快照 tombstone 一次） | | | |
| T-012 | 进行中（波次 4，真实部署到 127.0.0.1:18080） | | | |
| T-013 | 未开始 | | | |
| T-014 | 已验证 | `tools/pii_scan.py`（12 条规则，仅标准库）、`tools/pii_log_probe.py`、`tools/pii_samples/`、`tools/tests/`（180 项）、`tools/README.md` | 主会话复跑 180 passed；clean 0 命中、dirty 12 条规则全命中且不回显原文。其发现的潜在泄露（警告原文入日志、httpx 记完整 URL）已由主会话修正：`log.py` 改用 `log_warning`、`QUIET_LOGGERS`，加回归测试 | `evidence/m0/T-014/`（含 `fix-warning-leak.txt`） |
| T-015 | 未开始 | | | |
| T-020~T-027 | 待环境（D-2/D-6） | | | |
| T-030 | 进行中（波次 4：解析器 + F-47 + 作业集成 + 最小信封加密） | | | |
| T-031 | 未开始 | | | |
| T-040 | 未开始 | | | |
| T-041 | 未开始 | | | |
