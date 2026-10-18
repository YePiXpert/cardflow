# 81 · 首个实施阶段（M0 架构与关键 PoC）任务清单

> 派发顺序、简报与状态跟踪见 `m0-execution-plan.md`。

版本 0.1 · 2026-10-16。每条任务：输入（文档）、输出（路径）、验收（命令/证据）、规模（S ≤0.5 天 / M 1–2 天 / L 3–5 天）、建议执行者。前置：本环境无 Flutter SDK 与 Mac；移动端任务需用户提供可运行 Flutter 的机器（Linux/Windows 可做 Android，iOS 需 Mac），否则这些任务标记"待环境"。

| ID | 任务 | 输入 | 输出 | 验收 | 规模 | 执行者 | 依赖 |
|---|---|---|---|---|---|---|---|
| T-001 | 初始化 monorepo 与目录约定 | architecture §4、WP-01 | `apps/mobile`、`services/api`、`apps/admin`、`packages/rules-protocol`、`evidence/`、根 README | 目录存在；README 启动步骤可执行 | S | Opus | — |
| T-002 | 服务端工程骨架（FastAPI、pydantic v2、SQLAlchemy 2.1、Alembic、psycopg 3、uv 锁） | ADR-002、版本表 | `services/api/pyproject.toml`、`uv.lock`、`cardflow/` 包、`/healthz` | `uv run pytest` 空测试通过；`/healthz` 200 | M | Opus | T-001 |
| T-003 | 迁移 PoC 引擎为 `planner/engine` 包并保留全部测试 | `poc/engine_reference/` | `services/api/cardflow/planner/engine/*`、`tests/engine/*` | 40 项测试通过（输出存 `evidence/m0/engine-tests.txt`） | M | Opus | T-002 |
| T-004 | 规则协议 v1 JSON Schema + Python 运行器 | engine-spec §2/§6、fixture | `packages/rules-protocol/schema/*.json`、`runner_py` | fixture F-18 经 schema 校验并通过 | M | Opus | T-003 |
| T-005 | 初始 Alembic 迁移：身份/空间、银行/账户/卡、额度、交易/账单/版本、现金、计划/运行、导入、同步、审计、jobs | data-model §4 | `alembic/versions/0001_*.py` | 空库 upgrade/downgrade/upgrade 通过 | L | Opus | T-002 |
| T-006 | RLS 策略 + 数据库角色 + 绕过测试 | data-model §6 | 迁移 `0002_rls.py`、`tests/db/test_rls.py` | TC-DB-04/05/06 全部"拒绝"通过 | M | Opus | T-005 |
| T-007 | 约束触发器：账单版本追加只读、分配和校验、幂等键 | data-model §4 | 迁移 + 测试 | TC-DB-01/07/09 通过 | M | Opus | T-005 |
| T-008 | jobs 表与 worker 循环（SKIP LOCKED、租约、重试、死信、硬超时子进程） | ADR-003 | `cardflow/jobs/*`、`cardflow worker` 命令、测试 | TC-DB-10；超时任务进入 failed/dead | M | Opus | T-005 |
| T-009 | 求解任务接入 worker（API-51/52 最小版） | engine-spec、api-contract | 端点 + 任务 + 运行记录表写入 | 提交 fixture 请求→202→运行记录 business_status=CONDITIONALLY_FEASIBLE | M | Opus | T-003/T-008 |
| T-010 | 幂等中间件与错误信封 | api-contract §1 | `cardflow/api/middleware/*`、测试 | 同键重放返回原响应；不同哈希 409 | S | Opus | T-002 |
| T-011 | 设备注册与令牌（API-01/02） | ADR-011 | identity 模块 + 测试 | 注册→访问→刷新→撤销链路通过 | M | Opus | T-005 |
| T-012 | Compose 隔离部署（api/worker/db/migrate/backup）、secrets、/readyz | deployment-ops §1–§4 | `deploy/compose.yaml`、`.env.example`、`secrets/README` | 本机 `docker compose up` 后 `/readyz` 200；端口仅 127.0.0.1:18080 | M | Opus | T-002/T-005 |
| T-013 | 备份脚本与恢复演练脚本 | deployment-ops §5 | `cardflow backup`/`restore-drill` | 演练报告 `evidence/m0/restore-drill.md`（行数/校验一致） | M | Opus | T-012 |
| T-014 | 日志 PII 扫描器与 CI 任务 | security §4 | `tools/pii_scan.py`、CI 配置 | 注入含金额的日志样本被检出 | S | Opus | T-001 |
| T-015 | CI 流水线（lint、测试、迁移往返、fixture、pip-audit） | test-plan §10 | `.github/workflows/*` 或等价 | 全绿一次记录 | M | Opus | T-003~T-007 |
| T-020 | Flutter 工程骨架：五 tab 导航、Riverpod、go_router、主题 token、金额组件；Bundle ID/applicationId 与签名配置参数化 | ADR-001、ADR-015、UI 规格 §设计规范 | `apps/mobile/` | `flutter analyze` 零警告；空页面可导航；仓库内无签名密钥、证书与团队 ID | M | Opus（待环境） | T-001 |
| T-021 | PoC-1 加密 drift（sqlite3 钩子 sqlite3mc）真机验证 | ADR-001、S20/S21 | `apps/mobile/lib/data/db/*`、`evidence/m0/poc1-*.md` | 真机 `PRAGMA cipher_version` 非空；10 万行冷启动 <1 s；失败则记录并切换回退 | L | Opus（待环境） | T-020 |
| T-022 | Dart 领域层移植：Money/EventTime、billing、cash timeline、verifier | PoC 代码、engine-spec §8 | `apps/mobile/packages/domain/` + 测试 | F-18 fixture 在 Dart 运行器通过 | L | Opus（待环境） | T-004/T-020 |
| T-023 | 有限搜索（K≤3，候选切点，≤2 s）与"非证明"标注 | engine-spec §8 | domain 包 | 样本返回 A8000+C2000 可行；K=1 返回"本地未找到" | M | Opus（待环境） | T-022 |
| T-024 | PoC-2 文件接入（file_picker、receive_sharing_intent 1.9.0 UIScene） | ADR-009、ADR-015 | `apps/mobile/lib/features/imports/intake/*`、证据 | iOS/Android 接收 PDF/.eml/图片进入导入中心；iOS 分享扩展在用户自签构建上验证，不可用则启用"用其他应用打开"回退并记录 | M | Opus（待环境） | T-020 |
| T-025 | PoC-3 ML Kit 中文 OCR 样本评估 | ADR-009、S27 | 评估脚本、样本集（合成账单截图）、报告 | 字段识别率 ≥90% 或记录差距；包体增量记录 | M | Opus（待环境） | T-024 |
| T-026 | PoC-4/5 本地通知与后台任务 | ADR-010 | 通知调度器、workmanager 注册、证据 | 撤销重排生效；静默时段不弹；iOS 后台"尽力而为"记录 | M | Opus（待环境） | T-020 |
| T-027 | 安全存储与应用锁（flutter_secure_storage、local_auth）+ 锁屏隐藏金额 | security §3 | settings/security 模块 | TC-SEC-M01/M02 | M | Opus（待环境） | T-021 |
| T-030 | 服务端解析管线骨架：pypdf/pdfplumber 文本层 + rapidocr 兜底 + 恶意样本隔离 | import-spec | `cardflow/imports/parsers/*`、F-47 样本集 | F-47 全部拒绝/隔离；文本层样本抽取候选带位置与解析器版本 | L | Opus | T-008 |
| T-031 | Web 后台骨架（React 19/Vite 8/TS 7）+ 登录/角色 + 系统状态页 | ADR-005、admin-console-spec AP-01/AP-07 | `apps/admin/` | 登录后显示 `/readyz` 与队列深度；operator 无账单正文路由 | M | Opus | T-011/T-012 |
| T-040 | 交叉审查：财务语义（T-003/T-005/T-007）与安全（T-006/T-010/T-011） | 本清单 | `evidence/m0/review-*.md` | 发现清单与处置记录 | M | Opus（审查者） | 对应任务 |
| T-041 | M0 验收与追踪矩阵更新 | 全部 | `requirements-traceability.md` 状态列更新 | 主会话核对工具输出 | S | Fable | 全部 |

执行顺序建议：T-001 → (T-002, T-020) → (T-003, T-005, T-010) → (T-004, T-006, T-007, T-008, T-011, T-021, T-024) → (T-009, T-012, T-022, T-026, T-027, T-030, T-031) → (T-013, T-014, T-015, T-023, T-025) → T-040 → T-041。

M0 退出条件回顾：PoC-1~8 退出条件达成或记录失败与回退；F-18 双端通过；TC-DB-01~10 通过；Compose 隔离启动 `/readyz` 绿；恢复演练报告存在；追踪矩阵更新。
