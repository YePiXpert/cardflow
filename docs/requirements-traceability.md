# requirements-traceability.md · 需求追踪矩阵

版本 0.1 · 2026-10-16。列：需求 → 页面（P/AP）→ 数据表（T-）→ API/模块 → 测试（F/TC）→ 里程碑（M）→ 验收证据（E-）→ 当前状态。状态取值：**已规划**（本轮产出规格）、**PoC 已验证**（参考引擎有通过测试）、**待外部凭证**。实施阶段每完成一个工作包必须更新本表的状态列并附证据路径。

## 1. 证据登记（E-ID）

| E-ID | 证据 | 形式 | 产出里程碑 |
|---|---|---|---|
| E-01~E-09 | UF-1~UF-9 端到端验收 | 真机录屏/截图 + 测试日志 + DB 行计数 | M1~M4 |
| E-10 | 引擎 golden fixture 测试记录 | `poc/engine_reference/EVIDENCE.md`（现有）→ `evidence/<ver>/engine-tests.txt` | 现有 / M0 |
| E-11 | DB 约束/RLS 测试日志 | pytest 输出 | M0 |
| E-12 | API 集成测试日志 | pytest 输出 | M1~M4 |
| E-13 | Python/Dart fixture 一致性 | CI 任务输出 | M0/M2 |
| E-14 | 安全测试清单结果 | 报告 | M4 |
| E-15 | 性能基准报告 | `70-testing/benchmarks/` | M2/M4 |
| E-16 | 迁移往返日志 | CI 输出 | M0+ |
| E-17 | 同步/离线测试日志 | 双模拟器脚本输出 | M4 |
| E-18 | 设备端备份恢复核验 | 测试日志 + 截图 | M4 |
| E-20 | 自托管部署健康证据 | 版本、`/readyz` 输出、迁移版本 | M0/M5 |
| E-21 | Android 自签构建与安装记录 | 未签名 APK 哈希；测试密钥签名后的 `apksigner verify`、`adb install` 与覆盖升级保数据日志（TC-MOB-14）；用户自签安装确认 | M5 |
| E-22 | iOS 构建与自签安装记录 | Mac 构建日志与产物哈希；用户自签真机安装截图（含版本号） | M5（待外部凭证 B-01） |
| E-23 | 服务端恢复演练报告 | 报告 | M0/M5 |
| E-24 | 后台 RBAC/审计测试 | pytest 输出 | M3 |
| E-25 | 可访问性与主题检查 | 检查表 + 截图 | M4 |
| E-26 | 通知测试记录 | 真机日志 | M4 |

## 2. 产品需求（PRD）

| 需求 | 页面 | 数据表 | API/模块 | 测试 | M | 证据 | 状态 |
|---|---|---|---|---|---|---|---|
| R-CARD-01 建卡方式 | P-22, P-02, P-13 | credit_accounts, currency_accounts, cards, workspaces(demo) | API-10/12, cards | TC-MOB-01, TC-API-01 | M1 | E-01 | 已规划 |
| R-CARD-02 卡片字段集/禁敏感字段 | P-03, P-04 | cards(last4 CHECK) | API-12 | TC-DB-02, TC-SEC-M04 | M1 | E-11 | 已规划 |
| R-CARD-03 四层区分 | P-03, P-04 | credit_pools, credit_pool_members, currency_accounts | cards | F-21, F-22, F-23 | M1 | E-11/E-12 | PoC 已验证（F-23 单层） |
| R-CARD-04 卡片生命周期 | P-03 | cards(status, replaced_by) | API-12 | F-24 | M1 | E-12 | 已规划 |
| R-CARD-05 额度模型与快照 | P-04 | limit_snapshots, limit_adjustments, preauth_holds, plan_reservations | API-13 | F-25, F-26, F-27, TC-DB-08 | M1 | E-11 | PoC 已验证（F-26） |
| R-CARD-06 额度释放轨迹 | P-04, P-12 | repayments, limit_snapshots | cards/planner | F-28 | M1/M2 | E-12 | 已规划 |
| R-STMT-01 账单要素 | P-05 | statements, statement_versions, statement_lines, installment_schedule | API-31 | TC-API-01 | M1 | E-02 | 已规划 |
| R-STMT-02 负债四分法 | P-01, P-05 | 同上 + 投影 | statements | F-30 | M1 | E-12 | 已规划 |
| R-STMT-03 还款状态机 | P-06 | repayments(status) | API-33 | TC-API-03 | M1 | E-03 | 已规划 |
| R-STMT-04 还款双侧时间 | P-06, P-07 | repayments(时间列), cash_events | API-33, cash | F-31 | M1 | E-03 | 已规划 |
| R-STMT-05 冲突与分配 | P-06, P-13 | repayment_allocations, reconciliation_items | API-34/35 | F-32, F-33, TC-DB-09 | M1 | E-11/E-12 | 已规划 |
| R-STMT-06 退款三态 | P-05, P-13 | transactions(refund), reconciliation_items | statements | F-34 | M1 | E-12 | 已规划 |
| R-STMT-07 账单版本留痕 | P-05 | statement_versions(触发器) | API-32 | TC-DB-01 | M1 | E-11 | 已规划 |
| R-STMT-08 消费口径 | P-23 | transactions(txn_type) | stats | F-35 | M4 | E-12 | 已规划 |
| R-STMT-09 对账差异 | P-13 | reconciliation_items, audit_log | API-35, API-25 | TC-API-02 | M1 | E-02 | 已规划 |
| R-STMT-10 分期 | P-05 | installment_plans, installment_schedule | API-36, money.split_installments/irr | F-36, F-37 | M1 | E-10 | PoC 已验证（拆分/IRR 函数） |
| R-STMT-11 溢缴款 | P-05 | statement_versions(credit_balance_minor) | statements | F-38 | M1 | E-12 | 已规划 |
| R-CASH-01 现金账户 | P-08 | cash_accounts, cash_balance_snapshots | API-40 | TC-API-01 | M1 | E-05 | 已规划 |
| R-CASH-02 收支计划 | P-08 | cash_events, recurring_items | API-40 | TC-MOB-05 | M1 | E-05 | 已规划 |
| R-CASH-03 三口径 | P-07, P-09 | scenarios, cash_events(cls) | cash.apply_scenario | F-01 | M1 | E-10 | PoC 已验证 |
| R-CASH-04 情景与版本对比 | P-09 | scenarios, forecast_runs | API-41/42 | F-02 | M1 | E-05 | PoC 已验证（情景变换） |
| R-CASH-05 逐账户/调拨 | P-07 | cash_accounts, cash_transfers | cash.evaluate_accounts | F-03 | M1 | E-10 | PoC 已验证 |
| R-CASH-06 快照包含与同日顺序 | P-08 | snapshot_included_events, cash_events(event_at) | cash.build_timeline | F-04 | M1 | E-10 | PoC 已验证 |
| R-CASH-07 缺口输出 | P-07, P-12 | plan_run_checks, forecast_runs | cash.evaluate | F-05 | M1 | E-10 | PoC 已验证 |
| R-CASH-08 视图与覆盖 | P-07 | forecast_runs | API-42 | F-06 | M1 | E-05 | 已规划 |
| R-CASH-09 数据不足降级 | P-07, P-10 | — | plan.data_issues | F-07 | M1/M2 | E-10 | PoC 已验证 |
| R-CASH-10 先验基线 | P-07, P-11 | — | plan.baseline_check | F-08 | M2 | E-10 | PoC 已验证 |
| R-PLAN-01 输入 | P-10 | plans | API-50 | TC-MOB-04 | M2 | E-04 | 已规划 |
| R-PLAN-02 拆单默认关闭 | P-10 | plans(allow_split) | PlanRequest.k | F-09 | M2 | E-10 | PoC 已验证 |
| R-PLAN-03 金额口径 | P-10 | plans(原价/优惠/返现字段) | API-50 校验 | TC-API-04 | M2 | E-04 | 已规划 |
| R-PLAN-04 三类方案 | P-11 | plan_runs(profile) | allocation.TIERS | F-18 | M2 | E-10 | PoC 已验证 |
| R-PLAN-05 方案输出与拒绝原因 | P-12 | plan_allocations, plan_run_checks, plan_runs.result | plan.rejection_reasons | F-18 | M2 | E-10 | PoC 已验证 |
| R-PLAN-06 保存/采纳/预留/关联 | P-12 | plan_reservations, transactions | API-53/54/55 | F-10 | M2 | E-04 | 已规划 |
| R-PLAN-07 过期 | P-11 | plan_invalidations | planner.service | TC-API-05 | M2 | E-12 | 已规划 |
| R-PLAN-08 状态展示 | P-11, P-12 | plan_runs(solver_status, business_status) | UI 状态映射 | TC-MOB-04 | M2 | E-04 | PoC 已验证（状态产出） |
| R-PLAN-09 无解解释与敏感性 | P-12 | plan_runs.result.sensitivity | allocation.min_extra_cash 等 | F-11 | M2 | E-10 | PoC 已验证 |
| R-PROMO-01 闭环 | P-14, P-15 | promotions, promotion_enrollments, promotion_progress, reward_ledger | API-60~64 | TC-MOB-06 | M3 | E-06 | 已规划 |
| R-PROMO-02 来源策略 | AP-03 | promotion_sources, promotion_rule_versions | WP-34 | TC-SEC-S06 | M3 | E-14 | 已规划 |
| R-PROMO-03 字段集 | P-14, AP-03 | promotion_rule_versions(rule JSONB) | schema v1 | F-40 | M3 | E-12 | 已规划 |
| R-PROMO-04 三态资格 | P-14 | promotion_enrollments(eligibility, unknown_reasons) | promotions.eligibility | TC-API-06 | M3 | E-06 | 已规划 |
| R-PROMO-05 声明式规则 | AP-03 | 同上 | 解释器（无 eval） | F-41, F-42, F-43 | M3 | E-12 | 已规划 |
| R-PROMO-06 三层状态 | P-15 | reward_ledger(confirmation_level), cash_events(expected) | promotions | TC-API-06 | M3 | E-06 | 已规划 |
| R-PROMO-07 不诱导消费 | P-12, P-15 | — | planner/promotions（无"再消费"建议） | 代码审查 + TC-API-06 | M3 | E-24 | 已规划 |
| R-BEN-01 权益定义 | P-16 | benefit_definitions, benefit_grants | API-70 | TC-API-07 | M3 | E-07 | 已规划 |
| R-BEN-02 权益状态机 | P-16 | benefit_usages(status) | API-70 | F-66 | M3 | E-07 | 已规划 |
| R-BEN-03 保险权益 | P-16 | benefit_definitions(type=insurance) | 统计排除 | TC-API-07 | M3 | E-12 | 已规划 |
| R-BEN-04 积分 | P-17 | points_accounts, points_batches, points_events | API-71 | F-44 | M3 | E-07 | 已规划 |
| R-BEN-05 年费 | P-17 | annual_fee_rules, annual_fee_cycles | API-72 | F-45 | M3 | E-07 | 已规划 |
| R-BEN-06 保留分析 | P-17 | 投影 | benefits | TC-MOB-07 | M3 | E-07 | 已规划 |
| R-NOTIF-01 类型与提前天数 | P-18 | notification_rules | API-80 | TC-MOB-11 | M4 | E-26 | 已规划 |
| R-NOTIF-02 三通道与去重撤销静默 | P-18 | notifications(dedupe_key) | notifications | F-46 | M4 | E-26 | 已规划 |
| R-NOTIF-03 不承诺必达 | P-01, P-18 | — | UI | TC-MOB-11 | M4 | E-26 | 已规划 |
| R-NOTIF-04 锁屏隐私 | P-18 | notifications.payload(无金额) | notifications | TC-SEC-M01 | M4 | E-14 | 已规划 |
| R-STAT-01 指标口径 | P-23 | 投影 | stats | F-35 | M4 | E-12 | 已规划 |
| R-SYS-01 搜索筛选 | P-02, P-05, P-14 | transactions(pg_trgm) | settings/search | TC-MOB-13 | M4 | E-25 | 已规划 |
| R-SYS-02 深浅主题 | P-19 | — | 设计 token | TC-MOB-13 | M4 | E-25 | 已规划 |
| R-SYS-03 金额隐藏 | P-19, 全部 | — | settings | TC-MOB-10 | M4 | E-25 | 已规划 |
| R-SYS-04 锁屏保护 | P-19 | — | local_auth | TC-SEC-M01 | M4 | E-14 | 已规划 |
| R-SYS-05 备份恢复 | P-20 | — | backup 模块 | F-63 | M4 | E-18 | 已规划 |
| R-SYS-06 导出 | P-20 | — | API-93 | TC-API-09 | M4 | E-12 | 已规划 |
| R-SYS-07 设备管理 | P-20, AP-08 | devices, auth_sessions | API-02 | TC-API-13 | M4 | E-17 | 已规划 |
| R-SYS-08 同步状态 | P-20 | sync_changes, sync_conflicts | API-90~92 | TC-SYNC-01~06 | M4 | E-17 | 已规划 |
| R-SYS-09 数据删除 | P-20 | deletion_tasks, audit_log | API-94 | F-64 | M4 | E-12 | 已规划 |
| R-SYS-10 隐私授权中心 | P-19 | consents | API-03 | TC-SEC-M23 | M4 | E-14 | 已规划 |
| R-SYS-11 帮助与口径 | P-19 | — | UI | TC-MOB-13 | M4 | E-25 | 已规划 |
| R-SYS-12 后台与 RBAC | AP-01~AP-08 | billing_rule_versions, promotion_*, jobs, audit_log | API-A1 | TC-API-13, TC-SEC-S04 | M3 | E-24 | 已规划 |
| R-SYS-13 演示模式 | P-22 | workspaces(kind=demo) | DEMO_RESTRICTED | TC-MOB-12, TC-API-12 | M1 | E-01 | 已规划 |
| R-IMP-01 渠道 | P-13 | source_documents, import_batches | API-20/21 | TC-API-02 | M1 | E-02 | 已规划 |
| R-IMP-02 解析顺序/密码 | P-13 | parse_jobs | parsers | F-53 | M1 | E-14 | 已规划 |
| R-IMP-03 隔离与恢复 | P-13 | parse_jobs(status), jobs | parsers | F-47 | M1 | E-14 | 已规划 |
| R-IMP-04 字段溯源 | P-13 | extraction_candidates | API-22 | TC-API-02 | M1 | E-02 | 已规划 |
| R-IMP-05 校验门槛 | P-13 | import_batches(needs_review) | API-23/24 | F-48 | M1 | E-12 | 已规划 |
| R-IMP-06 幂等去重 | P-13 | dedupe_keys, transactions(fingerprint) | imports.dedupe | F-49, F-50, F-51, F-52 | M1 | E-12 | 已规划 |
| R-IMP-07 平台限制 | — | — | 工程配置（iOS 无短信权限；Android flavor） | TC-SEC-M04 | M1 | E-14 | 已规划 |
| R-IMP-08 邮件 | P-13, P-19 | consents | imports.eml | TC-API-02 | M1（OAuth 可选） | E-02 | 已规划 |
| R-IMP-09 覆盖矩阵 | P-19 帮助 | — | 文档 PRD §9 | 文档审查 | M1 | — | 已完成 |

## 3. 规则引擎、求解引擎、数据、架构、安全、测试、交付

| 需求 | 页面 | 数据表 | API/模块 | 测试 | M | 证据 | 状态 |
|---|---|---|---|---|---|---|---|
| R-RULE-01 时间点七分法 | P-05, P-06, P-12 | transactions, statements, repayments | billing | F-31 | M1 | E-12 | 已规划 |
| R-RULE-02 规则对象模型/版本 | P-04, AP-02 | billing_rule_versions(排除约束) | select_rule/resolve_cycle | F-14, TC-DB-03 | M1 | E-10/E-11 | PoC 已验证（版本选择） |
| R-RULE-03 账单归属/月末/闰年 | P-04, P-05 | billing_rule_versions | billing.statement_date_for_posting | F-12, F-16 | M1 | E-10 | PoC 已验证 |
| R-RULE-04 到期规则类型/非法规则 | P-04 | billing_rule_versions(CHECK) | billing.due_date_for_statement | F-13, F-17, TC-DB-03 | M1 | E-10 | PoC 已验证 |
| R-RULE-05 版本按入账日选择/旧账单不变 | P-04, P-05 | billing_rule_versions(排除约束), statements | billing.select_rule/resolve_cycle | F-14 | M1 | E-10 | PoC 已验证 |
| R-RULE-06 入账窗口多账期保守校验/顺延需日历 | P-05, P-12 | billing_rule_versions(holiday_rollover) | billing.cycles_for_transaction | F-15, F-17 | M1 | E-10 | PoC 已验证 |
| R-RULE-07 免息与计息 | P-05 | charges, installment_plans | statements | F-37 + 招行规则 pending | M1 | E-12 | 已规划（招行待核验 B-04） |
| R-RULE-08 额度语义 | P-04 | limit_snapshots | cards | F-25~F-28 | M1 | E-11 | 已规划 |
| R-RULE-09 退款/撤销/预授权 | P-05, P-13 | transactions(parent), reconciliation_items | statements/imports | F-34, F-51 | M1 | E-12 | 已规划 |
| R-ENG-01 输入契约 | P-10 | plans, scenarios | rules-protocol v1 | schema 校验 | M0 | E-13 | PoC 已验证（Python 侧） |
| R-ENG-02 数学模型 | — | — | allocation.build_model | F-18, F-23, F-69, 性质测试 | M0/M2 | E-10 | PoC 已验证 |
| R-ENG-03 分层目标 | P-11 | plan_runs(profile) | allocation.TIERS | F-18 | M2 | E-10 | PoC 已验证 |
| R-ENG-04 求解器状态与超时 | P-11 | plan_runs(solver_status) | allocation.solve | F-68 | M2 | E-10 | PoC 已验证（UNKNOWN 分支） |
| R-ENG-05 情景与业务状态 | P-11, P-12 | plan_runs(business_status), plan_run_checks | plan.plan | F-07, F-08, F-18 | M2 | E-10 | PoC 已验证 |
| R-ENG-06 输出契约 | P-12 | plan_runs.result | verifier/plan | F-18 | M2 | E-10 | PoC 已验证 |
| R-ENG-07 run_id 历史不覆盖 | P-11 | plan_runs, plan_allocations(PK run_id) | planner.service | TC-API-04 | M2 | E-12 | 已规划 |
| R-ENG-08 本地离线边界/双端一致 | P-11 | plan_runs(computed_locally) | Dart domain | E-13, F-68 | M0/M2 | E-13 | 已规划 |
| R-DATA-01 最小单位整数/币种 | — | currencies, *_minor | ADR-008 | 性质测试 roundtrip | M0 | E-10 | PoC 已验证 |
| R-DATA-02 时间语义 | — | *_at/*_tz/time_precision | ADR-008 | F-19, F-20 | M1 | E-12 | 已规划 |
| R-DATA-03 追加更正/版本 | — | statement_versions 触发器 | ADR-014 | TC-DB-01 | M0 | E-11 | 已规划 |
| R-DATA-04 幂等键 | — | idempotency_keys | 中间件 | TC-DB-07 | M0 | E-11 | 已规划 |
| R-DATA-05 所有权/RLS/绕过测试 | — | 全部表 + 策略 | ADR/迁移 0002 | TC-DB-04/05/06, F-65 | M0 | E-11 | 已规划 |
| R-DATA-06 迁移策略 | — | alembic | CI | E-16 | M0 | E-16 | 已规划 |
| R-API-01 契约约定（鉴权/幂等/分页/错误/异步） | — | — | api-contract §1 | TC-API-10/11 | M1 | E-12 | 已规划 |
| R-ARCH-01 离线能力矩阵 | 全部 | 本地表 | PRD §8 | TC-MOB-08 | M4 | E-08 | 已规划 |
| R-ARCH-02 同步/冲突/幂等/tombstone | P-21 | sync_changes, sync_conflicts | API-90~92 | F-60~F-62, TC-SYNC | M4 | E-17 | 已规划 |
| R-ARCH-03 隐私架构声明 | P-19 | consents | ADR-006 | 文档 + TC-SEC-S04 | M4 | E-14 | 已规划 |
| R-ARCH-04 AI 可关闭与边界 | P-19 | consents(ai_extract) | ai 适配器 | TC-SEC-S08 | M4 | E-14 | 已规划 |
| R-ARCH-05 队列/部署隔离 | AP-05, AP-07 | jobs | ADR-003, Compose | TC-DB-10, E-20 | M0 | E-20 | 已规划 |
| R-UI-01 五导航与双入口 | P-01~P-23 | — | go_router（UI 规格 §1） | TC-MOB-13 | M1~M4 | E-25 | 已规划 |
| R-UI-02 九种页面状态 | 全部 | — | UI 规格 §2/§6 | TC-MOB-* | M1~M4 | E-01~E-09 | 已规划 |
| R-UI-03 状态映射不一律绿色 | P-11, P-12 | plan_runs(business_status) | UI 规格 §5 | TC-MOB-04 | M2 | E-04 | 已规划 |
| R-UI-04 外链核验与返回核对 | P-06, P-14, P-16 | promotions(source_url 核验状态) | url_launcher + 核验表（UI 规格 §4.1） | TC-MOB-03/06/07 | M1~M3 | E-03/E-06/E-07 | 已规划 |
| R-UI-05 可访问性与数字金额呈现 | 全部, P-23 | *_minor, currencies | 设计 token + 金额组件（UI 规格 §3.4/§3.5） | TC-MOB-13, 性质测试 roundtrip | M1~M4 | E-25 | 已规划 |
| R-UI-07 确认层级徽标 | P-05, P-06, P-15, P-17 | *.confirmation_level | UI 组件（UI 规格 §4.3） | TC-MOB-03/06 | M1~M3 | E-25 | 已规划 |
| R-UI-08 金额隐藏/锁屏/遮罩/通知无金额 | 全部, P-18, P-19 | notifications.payload | settings/notifications（UI 规格 §3.6） | TC-SEC-M01, TC-MOB-10 | M4 | E-14 | 已规划 |
| R-SEC-01 MASVS 控制清单 | — | — | security §3 | TC-SEC-M* | M4 | E-14 | 已规划 |
| R-SEC-02 服务端控制 | — | — | security §4 | TC-SEC-S* | M0~M4 | E-14 | 已规划 |
| R-SEC-03 密钥管理与丢失后果 | P-20 | source_documents(dek_wrapped) | crypto | 演练 | M4 | E-18/E-23 | 已规划 |
| R-SEC-04 非可信输入 | P-13, AP-03 | — | parsers, fetch | F-47, TC-SEC-S05/S06/S08 | M1/M3 | E-14 | 已规划 |
| R-SEC-05 合规待核查项 | — | — | security §10 | 文档审查 | M5 | — | 已完成（清单） |
| R-TEST-01 覆盖矩阵与 fixtures | — | — | test-plan | — | M0~M5 | E-10~E-17 | 已规划（F-18 等已验证） |
| R-TEST-02 性质测试 | — | — | test-plan §3 | — | M0+ | E-10 | PoC 已验证（部分） |
| R-TEST-03 性能目标与方法 | — | — | test-plan §8 | — | M2/M4 | E-15 | 已规划（目标值） |
| R-DEL-01 分工与交叉审查 | — | — | milestones §3/§4 | — | 全程 | 审查记录 | 已规划 |
| R-DEL-02 完成定义 | — | — | milestones §5 | — | M5 | 全部 E | 已规划 |
| R-DEL-03 Android 自签构建与安装 | — | — | WP-50 | TC-MOB-14 | M5 | E-21 | 待外部凭证（B-06/B-07；签名由用户自签，ADR-015） |
| R-DEL-04 iOS 构建与自签安装 | — | — | WP-51 | TC-MOB-14 | M5 | E-22 | 待外部凭证（B-01；签名由用户自签，ADR-015） |
| R-DEL-05 自托管部署与恢复证据 | AP-07 | — | WP-52 | — | M0/M5 | E-20/E-23 | 已规划（公网部分待 B-05） |

## 4. 口径说明

- "PoC 已验证"仅指 `poc/engine_reference/` 在合成 fixture 上通过测试，不代表生产实现完成。
- "待外部凭证"条目在凭证到位前不计入完成，但其可独立验证部分（如 Android 调试构建、本机部署）仍须交付证据。
- R-UI-06 已合并入 R-UI-04，编号退役不复用。
- 本表是实施期的唯一验收清单；新增需求必须先在 PRD 登记 R-ID 再进入本表。
