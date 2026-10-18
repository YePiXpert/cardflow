# 审查报告 · M0 波次 2 · T-005（迁移 0001 与 SQLAlchemy 模型）+ T-007（约束触发器）

- 审查日期：2026-10-17（新上下文审查代理，非实现者）
- 审查对象：`services/api/alembic/versions/0001_initial.py`、`alembic/env.py`、`cardflow/db/{base,migrations,models,tx}.py`、各模块 `models.py`、`cardflow/cli.py`（migrate）、`tests/conftest.py`、`tests/db/*`
- 规格依据：data-model（全文）、ADR-003/007/008/011/014、architecture §4–§6、bank-rules-spec、engine-spec §2/§6、api-contract、PRD §6（及 R-CARD-02、R-STMT-04/07/09、R-DATA-02/03）、security-privacy、test-plan §4、m0-execution-plan / phase-1-tasks
- 方法：以代码、数据库实际行为和规格为准独立复核；`evidence/m0/T-005`、`T-007` 只作对照。实验只在开发库 cardflow-dev（127.0.0.1:18432，PostgreSQL 18.6）的临时库 `cardflow_review_*` 中进行，结束时全部删除；变异实验在 `/tmp/cardflow-review/api`（不含 .venv 的副本）中进行。仓库文件除本报告外均未修改。
- 主会话已定的三项修订（plan_allocations 按卡唯一；statement_versions 整行不可改；交易/还款/费用币种 = 子账户币种）不重复报告；与它们相关的更深问题见 R2-03、R2-04、R2-06。

---

## 1. 总评

**结论：可以在 0001 的基础上开展 T-006（RLS）与 T-008（jobs）。没有 blocker。** 两个附加条件：

1. **R2-01（触发器函数的 search_path 遮蔽）必须在 RLS 落地前或同时处理**：要么在 0002 里固定函数的 search_path 并对表名做全限定，要么至少在 T-006 中 `REVOKE TEMPORARY ON DATABASE … FROM PUBLIC`，并把"非超级用户用临时表伪造查找结果"加入 TC-DB-05 绕过测试。否则 RLS 完成后仍能制造跨工作空间引用。
2. T-006 设计授权时要考虑 R2-02（延迟检查需要 repayments 的 UPDATE 权限）和 R2-10（不得向 app 角色授予 statement_versions 的 DELETE/TRUNCATE）。

其余 major（R2-02…R2-09）应进入 0002 结构修订；其中 R2-07（同步游标）不影响 T-006/T-008，但必须在同步任务开工前定案。

总体质量较高：所有约束和索引都显式命名，并与 SQLAlchemy 命名约定一致；租户数据表 `workspace_id NOT NULL` + `UNIQUE (workspace_id, id)` + 复合外键覆盖完整；对规格做了几处合理偏离（排除约束按作用域划分、`statements.current_version_id` 用延迟复合外键、模板行的 workspace_id 不可变、purge 开关只在事务内有效）。迁移可往返、可重复，downgrade 是事务性的，离线 `--sql` 渲染正常。漂移测试的第二层（`pg_get_constraintdef`/`pg_get_indexdef` 逐对象比对）能发现模型侧变异。TC-DB 测试都同时断言 SQLSTATE 和约束名，没有发现"抛出任何异常都算通过"的空洞测试。主要风险集中在三处：触发器函数的执行环境（search_path、隔离级别、权限）、"同一工作空间内跨账户错挂"缺约束，以及 tombstone 与自然键唯一约束、同步游标之间的冲突。

| 严重度 | 数量 | 编号 |
|---|---|---|
| blocker | 0 | — |
| major | 9 | R2-01 … R2-09 |
| minor | 18 | R2-10 … R2-27 |
| nit | 9 | R2-28 … R2-36 |

复跑测试：`cd services/api && CARDFLOW_TEST_DATABASE_URL="$(../../tools/dev-db.sh url)" uv run pytest -q tests/db -p no:cacheprovider` → **77 passed, 1 warning in 4.56s**。

---

## 2. 发现清单

位置中的行号指 `services/api/alembic/versions/0001_initial.py`，另有说明的除外。"证据"一栏的标签（B13′、C1 等）对应 §4 中的实验与完整输出。

| ID | 严重度 | 类别 | 位置 | 问题描述 | 证据（摘录） | 建议修法 |
|---|---|---|---|---|---|---|
| R2-01 | major | B / I | `check_template_scope` 1753–1779、`check_rule_subject_scope` 1810–1843、`check_repayment_allocations` 1652–1695 | 三个函数都是 SECURITY INVOKER，没有固定 search_path，表名也不带模式。search_path 未显式列出 pg_temp 时，PostgreSQL 会**最先**搜索会话临时模式。任何拥有默认 TEMP 权限的角色都能建同名临时表来伪造查找结果，从而绕过模板作用域、规则主体作用域和"分配和 ≤ 还款额"三项检查。临时表不受 RLS 约束，所以 RLS 上线后同样可以绕过。 | 非超级用户 `cardflow_review_app`（只有 SELECT/INSERT/UPDATE 和默认 TEMP）：`CREATE TEMP TABLE banks(id uuid, workspace_id uuid)` + 伪造行 → 插入 A 空间的信用账户、引用 B 空间私有银行 → `OK`，"A credit accounts now pointing at B's private bank: 2"（B13′/B13″）。同样手法：规则主体指向 B 的信用账户 → OK（B14）；临时表遮蔽 `repayment_allocations` 后，999999 的分配在 100000 的还款上 COMMIT OK（C4）。修复验证：执行 `ALTER FUNCTION … SET search_path = pg_catalog, public, pg_temp` 后，同一攻击返回 `23503 credit_accounts_bank_scope`（FIX）。 | 0002：所有触发器和检查函数加 `SET search_path = pg_catalog, public, pg_temp`（pg_temp 必须显式放在最后），函数体内用 `public.` 全限定，`format` 改为 `'%I.%I'`。T-006：`REVOKE TEMPORARY ON DATABASE … FROM PUBLIC`，app/admin 角色都不授予 TEMP，作为纵深防御。加回归测试：非超级用户 + 临时表遮蔽，必须被拒绝。 |
| R2-02 | major | C | 1646–1695（`FOR NO KEY UPDATE` 在 1663） | "分配和 ≤ 还款额"只在 READ COMMITTED 下成立。在 REPEATABLE READ 下，第二个事务 COMMIT 时能拿到锁（对方只加了锁、没有改行，不会触发序列化失败），但 SUM 用的是事务开始时的快照，看不到对方已提交的分配，于是两边都提交成功。另外 `FOR NO KEY UPDATE` 需要 repayments 的 UPDATE 权限。 | C1：还款 100000，两个会话分别插入 70000 和 60000：RC 下 s2 报 `23514`；**RR 下两边都 `COMMIT OK`，live total = 130000**；SERIALIZABLE 下 s2 报 `40001`。P1：只有分配表 INSERT 权限和 SELECT 权限的角色，COMMIT 时报 `42501 permission denied for table repayments`。修复验证（RRFIX）：把行锁换成对还款行的真实写入后，RC→23514，RR→40001，SER→40001，总额均为 70000。 | 用"写冲突"代替"只加锁"：维护 `repayments.allocated_minor`（触发器增量更新，同时让检查变成 O(1)），或写一张专用锁行表；也可以在函数里拒绝 `transaction_isolation = 'repeatable read'`。补 RR 并发测试。T-006 授权时，凡是写分配的角色都要有该函数所需的权限。 |
| R2-03 | major | C / A | `statement_lines` 715–740；决定 2 | 决定 2 的更深问题。(a) 银行原件的明细行可以随意 UPDATE、DELETE，也可以往既有版本追加，没有触发器，也不需要 purge 开关，R-STMT-07 "银行原值不可覆盖"在明细层失效。(b) "整行不可改"与"撤销错误导入 = tombstone + 审计"（API-25、PRD §6.4、R-STMT-09）冲突，也与同步的 tombstone 语义冲突：导入回滚后无法再给版本写 `deleted_at`，statement_versions 上的 row_version/updated_at/deleted_at 将变成死列。 | L1 `UPDATE statement_lines SET amount_minor=1` → OK；L2 `DELETE FROM statement_lines …`（未开 app.purge）→ OK；L3 向既有版本追加明细 → OK；SV1 `UPDATE statement_versions SET statement_id=<另一账单>, version_no=2` → OK（决定 2 将封堵）。 | 0002 把同一不可变规则扩展到 statement_lines。如需"明细↔交易"匹配，把 transaction_id 移到独立的匹配表。为作废设计追加式表达，例如 `statement_version_retractions(version_id, import_batch_id, reason, recorded_by, recorded_at)`，或"只允许 deleted_at 由 NULL 变为非 NULL 一次 + 审计"；同时让 `statements.current_version_id` 回退到上一版本；同步层用该表表达删除。相应修改 `test_tc_db_01_non_amount_columns_stay_updatable`。 |
| R2-04 | major | C | `currency_accounts.currency` 324–337；`preauth_holds` 616；`cash_transfers` 1409；`plan_allocations`/`plans`；`plan_reservations` | 决定 3 的更深问题。(a) 只在子表上用触发器检查"币种 = 子账户币种"不够：父侧的 `currency_accounts.currency`（以及 `credit_account_id`）随时可改，已有的 CNY 交易、还款、账单会被整体"改币种"。(b) 同类不一致还存在于：preauth_holds.currency；cash_transfers.currency 与 from/to 现金账户；plan_allocations 所指子账户的币种与 plans.currency；plan_reservations。 | C5：子账户已有 CNY 还款和 CNY 交易时，`UPDATE currency_accounts SET currency='USD'` → OK。I5：在 CNY 子账户上插入 `currency='USD'` 的 preauth_holds → OK。 | 优先用声明式复合外键：currency_accounts 加 `UNIQUE (workspace_id, id, currency)`，子表外键改为 `(workspace_id, currency_account_id, currency) → currency_accounts(workspace_id, id, currency)`。这样父侧改币种会被 NO ACTION 自动拒绝，不需要另写触发器。preauth_holds 同样处理；cash_transfers 对 from/to 账户同理（若允许跨币种转账，需显式的 FX 字段）。或者把 currency_accounts 的 currency/credit_account_id 设为不可变。 |
| R2-05 | major | A / C | transactions/preauth_holds/plan_allocations `.card_id`；rule_bindings `.currency_account_id`；statement_attributions；charges `.statement_id/.transaction_id`；statement_lines/preauth_holds `.transaction_id`；snapshot_included_events；cash_transfers `.out/in_event_id`；cash_events `.linked_repayment_id` | 复合外键只保证"同一工作空间"，不保证"同一账户"。以下错挂全部被接受：账户 B 的卡记到账户 A 的子账户上；规则绑定的子账户不属于所绑定的信用账户；交易归属到另一子账户（且另一币种）的账单；费用挂在 A 子账户，却指向 B 子账户的账单；快照的"已包含事件"来自别的现金账户；转账的出/入事件不属于 from/to 账户。这些关系是引擎和账单计算的前提，而数据经同步由不可信客户端推入。 | I1：A 的 CNY 子账户上的交易 + B 的卡 → OK。I2：rule_binding(信用账户 A + B 的子账户) → OK。I3：A 的 CNY 交易归属到 B 的 USD 账单 → OK。I4：charge(A 子账户) 指向 B 的账单 → OK。其余同一模式，由代码阅读确认。 | 用带额外键的复合外键表达"同账户"：`cards UNIQUE (workspace_id, credit_account_id, id)`、`currency_accounts UNIQUE (workspace_id, credit_account_id, id)`、`statements UNIQUE (workspace_id, currency_account_id, id)`、`cash_events UNIQUE (workspace_id, cash_account_id, id)`，子表携带对应列（如 transactions 冗余 credit_account_id）；或者与决定 3 的触发器族合并实现，并同时守护父侧列不可改。 |
| R2-06 | major | E / A | `pk_repayment_allocations` 956、`pk_snapshot_included_events` 1397、`pk_plan_allocations` 1256、`uq_statements_currency_account_id_statement_date` 662、`uq_currency_accounts_credit_account_id_currency` 332、`uq_credit_pool_members_…` 314、`uq_source_documents_workspace_id_sha256` 990、`uq_statement_attributions_…`、`uq_transaction_links_…`、`uq_installment_schedule_…` | 这些自然键约束把 tombstone 行（deleted_at 非空）也算在内，而同步模型是"删除 = tombstone，保留 ≥90 天；离线新建用新 UUID"。结果是：删掉的账单日、子账户币种、池成员关系、还款分配、附件指纹都无法重建。例如 API-20 重新上传同一 PDF，会命中已删除、文件已清除的记录。这与另外两条已按 `WHERE deleted_at IS NULL` 做成部分唯一的约束（`uq_currency_accounts_one_primary`、`uq_installment_plans_transaction_id`）也不一致。决定 1 的"id 主键 + 唯一约束"思路同样适用于 repayment_allocations 和 snapshot_included_events。 | E1a：新建与已删账单同日期的账单 → `23505 uq_statements_currency_account_id_statement_date`。E1b：重新添加 CNY 子账户 → `23505 uq_currency_accounts_credit_account_id_currency`。E1c：重新入池 → `23505`。C2：tombstone 后重新分配同一 (还款, 账单) → `23505 pk_repayment_allocations`。 | 0002 逐表定案"复活旧行"还是"允许新行"。建议：PK 一律改为 id；附件指纹、账单日、子账户币种、池成员、分配、快照包含事件改为 `UNIQUE … WHERE deleted_at IS NULL` 的部分唯一索引；`(statement_id, version_no)` 保持全量唯一，版本号永不复用。在同步设计中写明规则并补测试。 |
| R2-07 | major | E | `sync_changes` 1470–1485；`cardflow/sync/models.py:1-7` | seq 在 INSERT 时取号，而不是在 COMMIT 时。按 `seq > cursor` 拉取，会永久漏掉"先取号、后提交"的变更。模型注释建议"只读到最老在途 xid 之下"，但表里没有记录 xid，这条建议无法实施；系统列 xmin 是 32 位、会冻结和回绕，不宜当游标。 | E2：T1 取到 seq 1 未提交，T2 取到 seq 2 并提交；第一次拉取看到 `[2]`，游标 = 2；T1 提交后第二次拉取（seq > 2）看到 `[]`，seq 1 永远不会下发。 | 现在就定案：表还是空的，在 0002 加列几乎没有成本。方案 A：加 `txid xid8 NOT NULL DEFAULT pg_current_xact_id()`，拉取时按 seq 顺序读，遇到第一条 `txid >= pg_snapshot_xmin(pg_current_snapshot())` 就停止（只做过滤不够，会跳过序号更小的在途行）。方案 B：每个工作空间串行化写入（在计数行上 `UPDATE … RETURNING`，PK 改为 (workspace_id, seq)），使提交顺序等于序号顺序。不阻塞 T-006/T-008。 |
| R2-08 | major | D | `repayments` 913–947 | ADR-008 / R-DATA-02 要求事件时间 = TIMESTAMPTZ + *_tz + time_precision + observed_at + recorded_at。repayments 的 4 个事件时间都没有时区和精度列，整张表也没有 recorded_at/created_at。架构 §6 的"疑似重复还款"规则明确使用"cash_debited_at/recorded_at 相差 ≤1 天"；R-STMT-04/F-31 要求"扣款日"和"入账日"分别生效。用户往往只知道日期，没有精度标记时，无法判断该在哪个时区截取日期。data-model §4 本身就缺这些列（规格内部不一致）。次要缺口：cash_events.event_at 无 tz、无 recorded_at；transactions 无 observed_at；limit_snapshots.balance_as_of 无精度。 | 目录扫描：`repayments ts=[payment_initiated_at,cash_debited_at,credit_posted_at,bank_confirmed_at] tz/precision=[]`；repayments 没有 recorded_at/created_at 列。 | 0002 增加 tz 列（每个时间一列或统一一列）、time_precision（至少覆盖 cash_debited_at 和 credit_posted_at）、`recorded_at TIMESTAMPTZ NOT NULL DEFAULT now()`；同步修订 data-model §3/§4，写明 ADR-008 适用于哪些表；cash_events、transactions 的缺口一并定案。 |
| R2-09 | major | I | extraction_candidates `.raw_value/.normalized_value/.confirmed_value`、statement_lines `.description`、transactions `.merchant`、cash_events/recurring_items `.label`、cards `.alias`、credit_accounts `.holder_alias`、reconciliation_items 文本列 | R-CARD-02 要求"任何文本字段输入 ≥13 位连续数字时拒绝保存"。数据库只约束了 `cards.last4` 和 `statement_lines.card_last4`，其余自由文本都能存完整卡号。extraction_candidates.raw_value 按设计保存解析原文，账单头部的卡号字段会以明文原样落库并进入备份，相当于绕过了附件的信封加密（security-privacy §1 把附件定为"高敏，可能含完整卡号"）。 | I9：`INSERT statement_lines(description='POS 6222021234567890 SHANGHAI')` → OK。 | 0002 增加一个 IMMUTABLE 函数 `looks_like_pan(text)`（13–19 位数字，允许空格或连字符分隔，且通过 Luhn 校验），并在上述列加 `CHECK (NOT looks_like_pan(col))`；bank_reference 等合法长数字列除外。T-030 解析器落库前做掩码（只保留末四位）。补测试。 |
| R2-10 | minor | C / I | `forbid_statement_version_delete` 1620–1634 | app.purge 是自定义 GUC（USERSET），任何有 DELETE 权限的角色都能自行打开。会话级 `SET app.purge='on'` 会在池化连接的后续事务中一直有效。 | P2：非超级用户执行 `set_config('app.purge','on',true)` 后 DELETE 银行版本，rowcount=1。SV6：会话级 SET 之后，下一个事务的 DELETE rowcount=1。 | T-006：不向 cardflow_app 授予 statement_versions/statement_lines 的 DELETE/TRUNCATE，清除走专用角色。触发器改为校验角色成员资格（`pg_has_role(current_user,'cardflow_purge','MEMBER')`），或要求开关值等于 `pg_current_xact_id()::text`，让会话级残留失效。 |
| R2-11 | minor | B | `billing_rule_versions.subject_id`（多态、无 FK）；所有租户表的 workspace_id 可改（只有 3 张模板表有不可变触发器） | 规则主体可以被移走或删除：把没有子行的信用账户改到 B 空间后，A 的规则主体就落在 B；硬删主体后规则悬空。RLS 的 WITH CHECK 能挡住 app 角色，但迁移、后台、超级用户路径没有防护。 | B11：`UPDATE credit_accounts SET workspace_id=B` → OK，"rule still in A: True \| its subject now in B: True"。B12：删除主体 → "dangling rule subjects: 1"。 | 所有租户表禁止修改 workspace_id（通用触发器，或 T-006 中列级 UPDATE 授权不含 workspace_id）。主体改为三个可空外键列（product_id / credit_account_id / currency_account_id，复合外键 + CHECK 恰有一列非空），排除约束对三列做 COALESCE，可以去掉 `check_rule_subject_scope`。 |
| R2-12 | minor | B | `ex_billing_rule_versions_scope_subject_period` 429–433；workspaces.id | 作用域键是 `COALESCE(workspace_id, nil uuid)`。若某个工作空间的 id 恰好是 nil UUID（客户端离线生成 id 时可被刻意选中），它的 user_declared 规则会与官方模板落在同一作用域，可以阻止后台发布同产品、同时段的模板（跨租户干扰）。 | N1：`INSERT INTO workspaces (id,…) VALUES ('00000000-0000-0000-0000-000000000000',…)` → OK。 | workspaces 加 `CHECK (id <> '00000000-…')`，或拆成两条部分排除约束（`WHERE workspace_id IS NULL` / `IS NOT NULL`）。 |
| R2-13 | minor | A / B | `ck_billing_rule_versions_review_status` 410–412 | 工作空间私有规则可以自标 verified/published，从而伪造"官方核验"标签（bank-rules §8 要求标明来源）。 | R1（verified）、R2（published）→ OK。 | `CHECK (workspace_id IS NULL OR review_status IN ('draft','user_declared','expired'))`。 |
| R2-14 | minor | A | `rule_bindings` 438–458 | 同一账户可以有多条时间重叠的有效绑定，规则解析结果不确定。 | I6：两条重叠绑定 → OK。 | `EXCLUDE USING gist (workspace_id WITH =, credit_account_id WITH =, COALESCE(currency_account_id, nil) WITH =, daterange(effective_from, effective_to,'[)') WITH &&) WHERE (deleted_at IS NULL)`。 |
| R2-15 | minor | C | repayments ↔ repayment_allocations | 还款被 tombstone，或状态变为 reversed/failed 后，其分配仍然有效，继续冲抵账单。 | C3：`UPDATE repayments SET status='reversed', deleted_at=now()` → COMMIT OK，live allocations = 50000。 | 定规则并写进检查函数：deleted/reversed/failed 的还款，有效分配和必须为 0（或由触发器联动 tombstone 分配）；repayments 上的约束触发器列清单加入 status 和 deleted_at。 |
| R2-16 | minor | C | transactions/charges/cash_events/recurring_items `.amount_minor` | 符号约定只写在 SQL 注释里。没有 `amount_minor <> 0`，也没有 txn_type 与符号的对应：refund 可以为正，purchase 可以为 0；charges 的金额完全不受约束。 | I7：refund +5000、purchase 0 → OK。 | 至少加 `CHECK (amount_minor <> 0)`；按类型约束符号（purchase/cash_advance/fee/interest/installment_principal > 0；refund/reversal/repayment < 0；adjustment/transfer/preauth 不限）；用 `COMMENT ON COLUMN` 写明约定。 |
| R2-17 | minor | C | 21 个 TEXT 状态/种类列 | 以下列没有 CHECK：installment_plans.status、installment_schedule.status、preauth_holds.status、parse_jobs.status、reconciliation_items.status、sync_conflicts.status、deletion_tasks.status、charges.kind、statement_lines.kind、transaction_links.kind、import_batches.kind、plan_invalidations.cause、devices.platform、jobs.kind、dedupe_keys.entity_kind、audit_log.actor_kind，以及 5 个 source_kind（transactions、charges、preauth_holds、cash_balance_snapshots、reconciliation_items）。 | 目录查询（§4 CAT）。 | 对有状态机或枚举语义的列补 CHECK（worker 和对账流程会按这些值分支）；确实开放的列（如 consents.purpose）在注释中说明。 |
| R2-18 | minor | A / C | `credit_pools.parent_pool_id`、`cards.replaced_by_card_id`、`credit_pool_members` | 只禁止了自引用：池的父子环、换卡环都可以写入；账户也可以加入其他银行的池。引擎遍历多层池时可能死循环。 | Y1、Y2、Y3 → OK。 | 用触发器做环检测（递归 CTE），或池层级改用物化路径；规格如有要求，再校验成员与池的银行一致。 |
| R2-19 | minor | C | plan_runs/plan_allocations/plan_run_checks、limit_snapshots、cash_balance_snapshots | ADR-014、R-DATA-03 要求"财务事实追加、触发器禁止覆盖"，§3 也写明 plan_runs "历史不覆盖"。目前只有 statement_versions 受保护，运行记录和快照（纯观测）都能被 UPDATE 改写。 | 代码阅读：这些表没有相关触发器。 | 复用决定 2 的不可变触发器：运行记录整行只读，快照的金额和时间列只读；tombstone 采用与 R2-03 相同的追加式方案。 |
| R2-20 | minor | B / I | `source_document_id`（6 张表）、`repayments.evidence_document_id` | 软引用不受任何约束，可以指向别的工作空间的附件 id。RLS 会挡住读取，但溯源完整性（R-IMP-04）丢失。迁移说明中"附件会按保留期清除"指的是文件，元数据行（带 deleted_at）可以保留。 | §4 FK 查询：这些列没有外键。 | 改为复合外键 → `source_documents(workspace_id, id)`；清除附件时擦除 blob 和 dek_wrapped（改为可空），保留元数据行。 |
| R2-21 | minor | E | 40 张可同步表 | row_version"由服务端递增"、updated_at 的刷新、sync_changes 的写入全部依赖应用代码。任何遗漏（后台、worker、数据修复）都会导致客户端静默覆盖或漏拉。 | 代码阅读：没有维护这些列的触发器。 | 加通用 BEFORE UPDATE 触发器，递增 row_version 并刷新 updated_at；同步任务考虑由触发器写 sync_changes，与 R2-07 一起定案。 |
| R2-22 | minor | A | 0001 docstring 第 7–10 行；m0-execution-plan T-005 简报 vs phase-1-tasks T-005 | 执行计划的简报写"按 §3/§4 建表（10 组实体）"，但实现只含组 1–7 和组 10 的一部分，缺 promotions、promotion_*、reward_ledger、benefit_*、points_*、annual_fee_*、notification_rules、notifications 共 17 张表。实现与 phase-1-tasks 的 T-005 清单一致，docstring 也已声明，问题在于两份计划文件互相矛盾。另外：bank-rules-spec §2 的规则主体包含"银行"，而 subject_kind 只有 product/credit_account/currency_account；card_products 缺 benefits_template_id。 | 对照阅读。 | 主会话在执行计划里写明剩余表组由哪个任务、哪个迁移建（沿用本次的复合外键和同步列约定）；规则主体是否支持 bank 由规格裁定。 |
| R2-23 | minor | F | 1977–1978；docstring 第 9–10 行；`cardflow/db/migrations.py:12` | downgrade 无条件 DROP EXTENSION：扩展若在 0001 之前就存在（DBA 预装或其他对象使用），回滚会删掉不属于本迁移的扩展；没有依赖时是静默删除。docstring 仍写"RLS 为 0002"，执行计划已改为 0003。 | MIG：预装 pg_trgm → upgrade → downgrade base 后，扩展只剩 `['plpgsql']`。有外部依赖时报 `2BP01`，回滚整体失败，版本仍为 0001——这一点是期望行为。 | upgrade 时记录扩展是否由本迁移创建，downgrade 只删自己创建的；或者 downgrade 不删扩展。同时修正文档中的修订号。 |
| R2-24 | minor | G / H | `tests/db/test_model_drift.py:51-66`（触发器豁免）、`tests/db/test_constraints.py` | 漂移测试对模型可表达的对象有效，但触发器和函数只核对名称和数量。以下变异在完整的 tests/db（77 项）下全部通过：M5 把 card_products 的不可变触发器改成 `UPDATE OF name`；M6 把 credit_pools 的作用域触发器改成只在 INSERT 时触发；M8 删掉 currency_account 主体分支的 workspace 条件。另外缺少这些反例测试：RR 并发、临时表遮蔽、tombstone 后重建、作用域触发器的 UPDATE 路径、card_products/billing_rule_versions 不可变、会话级 purge 残留。 | MUT：M5/M6/M8 → `77 passed`。对照：M1/M2/M3（模型侧变异）使漂移测试失败；M4/M7 使行为测试失败。 | 增加触发器/函数的"金样"清单测试：把 `pg_get_triggerdef` 和 `md5(prosrc)` 与登记值比对，改动必须显式更新清单。补齐上述反例测试。 |
| R2-25 | minor | J | 见右栏 | data-model §5 列出的访问路径都有索引，但以下外键引用列没有可用的前导索引（部分索引不能用于外键检查）：transactions.card_id、transactions.parent_transaction_id（自引用，工作空间清除时逐行全表扫描，近似 O(n²)）、cash_events.cash_account_id（只有部分索引）/linked_repayment_id/recurring_item_id/linked_plan_run_id、installment_plans.transaction_id（只有部分唯一索引）、charges.statement_id/transaction_id、preauth_holds.card_id/transaction_id、repayments.cash_account_id、plan_allocations 的 3 个外键列、plan_reservations 的 3 个外键列、plan_runs.decision_scenario_id、plan_run_checks.scenario_id、plan_invalidations.run_id、cash_transfers 的 4 个外键列、cards.replaced_by_card_id、credit_pools.parent_pool_id/bank_id、credit_accounts.product_id、rule_bindings.currency_account_id、import_batches.target_currency_account_id、parse_jobs.import_batch_id。 | CAT J1：40 行（其中 8 行是指向 currencies 的 `fk_*_currency`，可忽略）。 | 至少给自引用列和高基数子表补普通索引；工作空间清除任务（deletion_tasks）实现之前补齐。 |
| R2-26 | minor | A / I | `idempotency_keys` 194–208 | (a) API-01 设备注册标注为幂等，但注册前还没有工作空间，而该表要求 workspace_id NOT NULL 且有外键，存不了这类键。(b) 没有保留期，也没有用于清理的 created_at 索引。(c) response_body 保存首次响应的业务内容（含金额），属于正文。 | 阅读。 | T-010/T-011 定案：为公开端点另设按 device/配对码作用域的幂等表。加 created_at 索引和清理任务。T-006 对 admin 角色隐藏 response_body。 |
| R2-27 | minor | I | `jobs` 1544–1572（给 T-008/T-006） | payload/result/last_error 可能带业务内容，但 jobs 表没有工作空间强制；租约回收查询（T-008 草稿 `cardflow/jobs/queue.py:482` 的 `WHERE status='running' AND locked_until < now() ORDER BY locked_until`）没有对应索引；周期任务入队缺去重键（多 worker 下 apscheduler 会重复入队）；`GET /v1/jobs/{id}` 需要按 workspace 过滤，而 workspace_id 可为空。 | 阅读，并核对 T-008 进行中的 queue.py。 | T-008：增加 `(locked_until) WHERE status='running'` 部分索引，以及 `dedupe_key` + 部分唯一索引；payload 只放 id。T-006：对 app 角色按 workspace_id 启用 RLS，worker 用独立角色；admin 的列级授权不含 payload/result/last_error。 |
| R2-28 | nit | D | 所有 `*_tz`、`business_tz*`、`cutoff_tz` | 时区名不校验。 | I8：`txn_tz='Mars/Olympus'` → OK。 | 在应用层校验并加测试；或用触发器对照 `pg_timezone_names` 检查（不要用 CHECK 调 now()）。 |
| R2-29 | nit | I | `uq_users_email` 90；`devices.public_key` 136 | email 唯一约束不排除已删除用户（账号删除流程须清空 email），且允许空串 ''；public_key 没有长度或格式约束。 | 阅读。 | `CHECK (email <> '')`；在账号删除流程中清空 email；public_key 加长度下限，或存 SPKI 后由应用层解析校验。 |
| R2-30 | nit | H | `tests/db/test_migrations.py:144-153`；`tests/db/test_model_drift.py:211-215` | 写死了 `== ("0001",)`、`len(metadata.tables) == 58`、`trigger_count == 15`、`version == [("0001",)]`，0002/0003 一落地这些 T-005 测试就必须跟着改。 | 阅读。 | 从 `head_revisions()` 和触发器清单推导期望值。 |
| R2-31 | nit | H | `test_currencies_seed_matches_engine_minor_units` | 期望值是硬编码字典，没有直接与引擎的 `money.MINOR_DIGITS`/`ROUNDING` 比对；当前三者内容一致。 | 已核对 `cardflow/planner/engine/money.py:9-29`，一致。 | 直接导入引擎常量比对，同时比对 `ck_installment_plans_rounding`。 |
| R2-32 | nit | C | 545、897、1365 行的注释 | 符号约定只写在 SQL 注释里（`-- liability increase positive`），没有 `COMMENT ON COLUMN`；statement_lines.amount_minor 的符号未定义。 | 阅读。 | 加 `COMMENT ON COLUMN`。 |
| R2-33 | nit | C | `statements_allocation_check` 1727–1740 | `SELECT DISTINCT repayment_id` 没有 ORDER BY，加锁顺序不确定，容易死锁（死锁会被检测并回滚，所以只是 nit）。 | 阅读。 | 加 `ORDER BY a.repayment_id`。 |
| R2-34 | nit | H | `test_tc_db_04_templates_must_be_product_rules` | 在共享会话库里执行 `ALTER TABLE … DISABLE TRIGGER`，持有 ACCESS EXCLUSIVE 锁直到回滚；串行运行没问题，将来并行跑测试会互相阻塞。 | 阅读。 | 改用 scratch 库，或直接用 `pg_get_constraintdef` 断言 CHECK 的定义。 |
| R2-35 | nit | E / I | `source_documents` 973–996（有同步列） | storage_key 和 dek_wrapped 不应进入同步载荷。 | 阅读。 | 同步层为每张表设列白名单。 |
| R2-36 | nit | J | `ix_transactions_merchant_trgm`、`ix_cash_events_label_trgm` | trgm GIN 索引不按工作空间划分，RLS 在索引扫描之后才过滤。个人规模下没有问题。 | 阅读。 | 规模增长后再考虑 btree_gin 复合索引。 |

### 2.1 major 补充说明

- **R2-01** 的根因是 PostgreSQL 的规则："search_path 中未显式列出 pg_temp 时，临时模式最先被搜索（甚至在 pg_catalog 之前）"。外键检查（RI 触发器）内部使用全限定名，不受影响，所以伪造只骗过了作用域触发器，真实外键照常通过，最终落库的就是一条跨工作空间引用。按 data-model §6，RLS 的工作空间绑定本身是用户可设的 GUC，只能防应用逻辑错误、防不了 SQL 注入；数据库触发器和复合外键是对 SQL 注入的最后防线，所以这一项定为 major。
- **R2-02** 迁移里的注释已经写明"concurrent READ COMMITTED transactions validate one after the other"，但没有任何机制保证调用方使用 RC。同步推送、导入确认等批处理很可能为了得到一致快照而选用 REPEATABLE READ。修复已在临时库实测验证（§4 RRFIX）。若改用"触碰还款行"的方式，建议写一个专用列，避免与同步的 row_version 语义纠缠。
- **R2-03/R2-04/R2-06** 都是三项既定修订的延伸：决定 2 要覆盖明细行并给出撤销路径；决定 3 要守住父侧的改动，并覆盖其余带 currency 的表；决定 1 的主键模式应推广到另外两张复合主键表，同时一并解决 tombstone 与唯一约束的关系。
- **R2-05** 与租户隔离无关，是工作空间内的账务一致性问题。这些行在设计上来自离线客户端的推送（ADR-007），数据库是最后一道校验。
- **R2-07** 若照模型注释的思路，只按"seq 小于最老在途事务"过滤而不加 txid 列，同样会丢变更。§4 E2 给出了最小复现。
- **R2-08/R2-09** 是规格层面的缺口（data-model §4 自身就缺这些列和约束），实现与 data-model 一致，但与 ADR-008、R-DATA-02、R-CARD-02 冲突，需要主会话先修订规格再落到 0002。

### 2.2 data-model §3/§4 逐表对照（摘要）

- **缺失**
  - 组 8、组 9 以及 notification_rules、notifications，共 17 张表（R2-22）。
  - `card_products.benefits_template_id`（字典中带 `?` 的可选字段，依赖组 9）。
  - 规格本身缺列，实现照抄（R2-08）：repayments 的 tz/precision/recorded_at，transactions.observed_at。
- **多余（多数合理）**
  - `worker_heartbeats`（/readyz 需要）。
  - `workspaces.dek_wrapped`（对应 security §5 的工作空间 DEK）。
  - `billing_rule_versions.cutoff_tz`（bank-rules §2 写明 `cutoff_time+tz`）。
  - jobs 新增 heartbeat_at、timeout_s、result、workspace_id、updated_at、finished_at。
  - plan_runs.job_id、plan_runs.reserve_override_minor（API-51）。
  - plan_allocations.cycle_assumptions、alternative_cycles（engine-spec §6）。
  - 各表的 created_at/recorded_at；40 张表的同步列；3 张复合主键表的 id 列。
  - 多出的 CHECK（字典里没有枚举的列也加了枚举约束，例如 confirmation_level）。
  - 多出的外键：cash_events → recurring_items/repayments/plan_runs，plan_runs.decision_scenario_id → scenarios，各 currency → currencies。
- **偏离**
  - 排除约束加入作用域：理由成立，测试覆盖了模板与用户声明共存、两个工作空间共存；遗留 R2-12/R2-13。
  - `statements.current_version_id` 增加延迟复合外键：比规格更严，正确。
  - `snapshot_included_events` 改为复合外键 + 指向 cash_events 的外键：比规格更严，正确。
  - `idempotency_keys` 采用 DDL 中的 response_status/response_body，而非字典中的 response_json：与 §4 一致。
  - `installment_plans.rounding` 允许 4 种取整模式：与引擎 ROUNDING 一致。
  - repayments.currency 增加 FK → currencies：合理。
  - 偏离中没有发现破坏规格意图的情况；有害的只是上面单列出的那些缺口。

---

## 3. 已核验无问题的要点

- **租户隔离基础**
  - 49 张租户数据表的 workspace_id 都是 NOT NULL，并带 `UNIQUE (workspace_id, id)`；只有 banks、card_products、billing_rule_versions 三张模板表可空（设计如此）；audit_log、jobs 可空且无外键（理由成立）；无 workspace_id 的只有 users、workspaces、currencies、worker_heartbeats（§4 CAT）。
  - 指向租户表、却不含 workspace_id 的外键恰好是 5 条模板引用，全部由作用域触发器守护（§4 FKS）；其余工作空间内引用都是复合外键。
- **作用域触发器的直接攻击路径全部被拒绝**（B1–B10）：INSERT、UPDATE bank_id/product_id、`INSERT … ON CONFLICT DO UPDATE`、模板产品引用私有银行、规则绑定指向他人规则、规则主体指向他人账户或私有产品、模板/私有银行改 workspace_id。错误码都是 23503 或 23000，约束名正确。
- **金额与数值类型**：38 个 `*_minor` 列全部是 BIGINT；没有 float/real/double/money 列；利率和系数是 NUMERIC(20,10)，其余 numeric 都有显式精度；所有时间戳都是 timestamptz；没有命名不规范的金额列（§4 CAT）；货币种子数据和取整枚举都与引擎一致。
- **statement_versions**
  - 金额列和 due_date 的 UPDATE 被拒绝，SET 原值也被拒绝。
  - 没有 purge 开关时 DELETE 被拒绝；直接 TRUNCATE、经 `TRUNCATE statements CASCADE` 或 `TRUNCATE workspaces CASCADE` 级联都被拒绝（SV4/SV5，BEFORE TRUNCATE 对级联表同样触发）。
  - purge 开关不放行金额 UPDATE；`set_config(…, true)` 只在本事务内有效（测试覆盖）。
- **还款分配延迟检查**
  - RC 与 SERIALIZABLE 下的并发都正确（C1）。
  - 降低还款额、跨币种子账户、移动已分配的账单、事务内临时超额后修正，都按预期工作。
  - 把已 tombstone 的分配复活并导致超额，会在 COMMIT 时被拒绝（C6）。
  - 删除和 tombstone 分配不需要检查；所需逻辑都在函数里。
- **排除约束**：同作用域重叠被拒绝，模板与用户声明不冲突，相邻区间 `[)` 不冲突，草稿和 tombstone 行不参与（测试与阅读一致）。
- **迁移**
  - 0001 没有任何数据 UPDATE，唯一的数据写入是 currencies 种子 INSERT（grep 核对）。
  - upgrade → downgrade → upgrade → downgrade 可重复（测试）；downgrade 失败时整体回滚（MIG）。
  - 离线 `alembic upgrade head --sql` 输出 1833 行、59 个 CREATE TABLE（含 alembic_version），`%`、`{}` 转义正确；CHECK 与 RAISE 中的 `%` 没有被双写（CAT F）。
  - 扩展用 IF NOT EXISTS 创建；btree_gist 和 pg_trgm 都是 trusted extension。
  - 对象命名与约定一致，长度 ≤63（测试）。
- **漂移测试**：模型侧的 CHECK、部分索引谓词、ON DELETE 变异（M1–M3）都被发现；函数体和加锁的变异（M4、M7）被行为测试发现。
- **测试**：TC-DB-01/02/03/04/07/08/09 都断言 SQLSTATE 和约束名；并发测试确认会话 2 确实在锁上等待；没有发现空洞测试。
- **身份凭据**：`users.password_hash` 只接受 `$argon2id$` 格式；`refresh_token_hash` 是 64 位小写十六进制，且 UNIQUE；`UNIQUE (rotated_from_id)` 能检测轮换令牌被重放；不存在完整卡号列，last4 只允许 4 位数字。
- **其他约束**：PRD §6 中卡片、账单、还款、导入批次、计划的状态取值与 CHECK 完全一致。uuidv7 是默认主键。`uq_currency_accounts_one_primary` 和 `uq_installment_plans_transaction_id` 这两条部分唯一索引的语义正确。
- **workspace_tx**：用 `set_config(…, true)` 设置的事务级 GUC 在 COMMIT 时运行的延迟触发器中依然可见，RLS 可以正常作用于这些触发器。

---

## 4. 实验命令与结果摘录

环境：开发库 PostgreSQL 18.6；Python 用 `services/api/.venv/bin/python`（`PYTHONDONTWRITEBYTECODE=1`）；脚本放在 `/tmp/cardflow-review/scripts/`（临时目录，下面摘录了关键 SQL）。

**T0 · 复跑测试**
`CARDFLOW_TEST_DATABASE_URL="$(…/dev-db.sh url)" uv run pytest -q tests/db -p no:cacheprovider` → `77 passed, 1 warning in 4.56s`。

**SETUP**：`create_db('cardflow_review_main')` 后，用仓库原代码执行 `cardflow.db.migrations.upgrade(url, 'head')` → `migrated cardflow_review_main`。

**B（作用域，exp_scope.py；以下操作都在回滚事务中）**
```
[B1 insert credit_account(A) -> B private bank] ERROR sqlstate=23503 constraint=credit_accounts_bank_scope
[B2 update A credit_account.bank_id -> B private bank] ERROR sqlstate=23503 constraint=credit_accounts_bank_scope
[B3 update A credit_account.product_id -> B private product] ERROR sqlstate=23503 constraint=credit_accounts_product_scope
[B4 upsert ON CONFLICT DO UPDATE bank_id -> B private bank] ERROR sqlstate=23503 constraint=credit_accounts_bank_scope
[B5 template card_product -> B private bank] ERROR 23503 card_products_bank_scope
[B6 A private card_product -> B private bank] ERROR 23503 card_products_bank_scope
[B7 A rule_binding -> B private rule] ERROR 23503 rule_bindings_rule_version_scope
[B8 A rule with subject = B credit account] ERROR 23503 billing_rule_versions_subject_scope
[B9 A rule with subject = B private product] ERROR 23503 billing_rule_versions_subject_scope
[B11 UPDATE credit_accounts SET workspace_id=B (subject of A's rule)] OK  -> rule still in A: True | its subject now in B: True
[B12 DELETE credit_account that is a rule subject] OK -> dangling rule subjects: 1
[B13 (superuser) temp 'banks' shadow, credit_account(A) -> B private bank] OK
[B14 temp 'credit_accounts' shadow, A rule with subject = B credit account] OK
```

**B′（非超级用户，exp_scope_role.py）**
`CREATE ROLE cardflow_review_app NOLOGIN NOSUPERUSER NOBYPASSRLS; GRANT SELECT, INSERT, UPDATE ON ALL TABLES …`，然后执行 `SET LOCAL ROLE`：
```
TEMP privilege for PUBLIC on this database: True
[B10 UPDATE banks SET workspace_id=A WHERE id=<B private bank>] ERROR sqlstate=23000 constraint=banks_workspace_immutable
current_user: ('cardflow_review_app', False)
[B1' (no shadow) credit_account(A) -> B private bank] ERROR 23503 credit_accounts_bank_scope
-- CREATE TEMP TABLE banks (id uuid, workspace_id uuid); INSERT INTO pg_temp.banks VALUES (<B bank>, NULL);
[B13' (temp shadow, non-superuser) credit_account(A) -> B private bank] OK
[B13'' (temp shadow, non-superuser) UPDATE A account bank_id -> B private bank] OK
   A credit accounts now pointing at B's private bank: 2
role dropped
```

**FIX（search_path 修复验证，回滚事务）**
`ALTER FUNCTION check_template_scope() SET search_path = pg_catalog, public, pg_temp`（另外两个函数同样处理），然后重复 B13：
`… ERROR sqlstate=23503 constraint=credit_accounts_bank_scope`；回滚后 proconfig 恢复为 None。

**SV（statement_versions，exp_stmt_versions.py）**
```
[SV1 move version of S1 to S2 (UPDATE statement_id, version_no)] OK
[SV2 rewrite provenance (source_kind, recorded_by, recorded_at)] OK
[SV3 amount UPDATE] ERROR sqlstate=23000 constraint=statement_versions_append_only
[SV4 TRUNCATE statements CASCADE] ERROR sqlstate=23000 constraint=statement_versions_no_truncate
[SV5 TRUNCATE workspaces CASCADE] ERROR sqlstate=23000 constraint=statement_versions_no_truncate
-- SET app.purge = 'on' (session level); COMMIT; new transaction:
   tx#2 current_setting: on
[SV6 DELETE in a LATER transaction] OK rowcount=1
```

**C（还款分配，exp_allocations.py；夹具先提交，每个场景使用新的工作空间）**
```
== C1 two sessions, 70000 + 60000 on a 100000 repayment, both INSERT before either COMMIT
[READ COMMITTED] session1: COMMIT OK | session2: ERROR sqlstate=23514 constraint=repayment_allocations_within_amount | total 70000
[REPEATABLE READ] session1: COMMIT OK | session2: COMMIT OK | live allocations total = 130000 vs repayment amount 100000
[SERIALIZABLE] session1: COMMIT OK | session2: ERROR sqlstate=40001 (read/write dependencies) | total 70000
[C2 INSERT new allocation row for the same pair after tombstone] ERROR sqlstate=23505 constraint=pk_repayment_allocations
[C3a repayment status=reversed, deleted_at=now() with live allocations] OK; commit OK; live allocations of tombstoned repayment: 50000
[C4] CREATE TEMP TABLE repayment_allocations(...) ; INSERT INTO public.repayment_allocations ... 999999 -> COMMIT OK; real live allocations: 999999 vs amount 100000
[C5 UPDATE currency_accounts SET currency='USD' (has CNY repayment + CNY transaction)] OK
[C6] revive over amount at commit: ERROR sqlstate=23514 constraint=repayment_allocations_within_amount
```

**RRFIX（临时库 cardflow_review_rr，执行后已删除）**
把函数中的 `SELECT … FOR NO KEY UPDATE` 换成
`UPDATE public.repayments AS r SET row_version = r.row_version WHERE r.id = $1 RETURNING r.amount_minor, r.currency_account_id`
（同时加上 `SET search_path = pg_catalog, public, pg_temp`）：
```
[patched, READ COMMITTED] s1: COMMIT OK | s2: ERROR sqlstate=23514 … | total=70000
[patched, REPEATABLE READ] s1: COMMIT OK | s2: ERROR sqlstate=40001 could not serialize access due to concurrent update | total=70000
[patched, SERIALIZABLE] s1: COMMIT OK | s2: ERROR sqlstate=40001 … | total=70000
```

**P（权限，exp_privs.py，临时角色用后删除）**
```
[P1] role with INSERT on allocations but no UPDATE on repayments: commit ERROR sqlstate=42501 msg='permission denied for table repayments'
[P2] non-superuser role sets app.purge itself and deletes a bank version: rowcount=1
```

**E / I（同步与工作空间内一致性，exp_sync_consistency.py）**
```
[E1a new statement, same (currency_account, statement_date) as a tombstoned one] ERROR 23505 uq_statements_currency_account_id_statement_date
[E1b re-add CNY sub-account after tombstoning the old one] ERROR 23505 uq_currency_accounts_credit_account_id_currency
[E1c re-join pool after tombstoned membership] ERROR 23505 uq_credit_pool_members_pool_id_credit_account_id
== E2 sync_changes.seq is assigned at INSERT, not at COMMIT
   T1 got seq 1 (open), T2 got seq 2 (committed); pull #1 sees [2] -> client cursor = 2
   after T1 commits, pull #2 (seq > 2) sees [] -> change seq 1 is never delivered
[I1 transaction on CNY sub-account of account A charged to a card of account B] OK
[I2 rule_binding: credit account A + currency sub-account of account B] OK
[I3 statement_attribution: CNY transaction of A -> USD statement of B] OK
[I4 charge on sub-account A pointing at statement of sub-account B] OK
[I5 preauth hold USD on a CNY sub-account] OK
[I6 two overlapping live rule_bindings for the same credit account] OK
[I7 zero-amount transaction / refund with positive amount] OK
[I8 txn_tz that is not a time zone] OK
[I9 statement_lines.description with a full 16-digit card number] OK
```

**L / R / N（exp_lines_rules.py）与 Y（环）**
```
[L1 UPDATE statement_lines.amount_minor of a bank version] OK
[L2 DELETE statement_lines row of a bank version (no app.purge)] OK
[L3 INSERT an extra line into an existing bank version] OK
[R1 workspace rule labelled review_status='verified'] OK
[R2 workspace rule labelled review_status='published' (enters the exclusion set)] OK
[N1 INSERT workspace id = 00000000-0000-0000-0000-000000000000] OK
[Y1 make p1 a child of p2 (2-cycle in credit_pools)] OK
[Y2 card replacement cycle (c1->c2->c1)] OK
[Y3 account of bank X joins a pool of bank Y] OK
```

**CAT（目录查询，exp_catalog.py；摘录）**
- J1：外键引用列没有非部分前导索引的有 40 行，见 R2-25；其中 8 行是 `fk_*_currency`，可忽略。
- 函数：9 个自有函数全部 `prosecdef = False`、`proconfig = None`，即没有固定 search_path。
- `ck_users_password_argon2id` 的存储定义为 `CHECK (((password_hash IS NULL) OR (password_hash ~~ '$argon2id$%'::text)))`，`%` 没有被双写。
- 同步列：40 张表四列齐全；只有部分同步列的是 users、workspaces、import_*、jobs、sync_changes、sync_conflicts、workspace_members；完全没有的是 audit_log、auth_sessions、currencies、dedupe_keys、deletion_tasks、devices、extraction_candidates、idempotency_keys、worker_heartbeats。
- workspace_id 可空的表：audit_log、banks、billing_rule_versions、card_products、jobs。没有 workspace_id 的表：currencies、users、worker_heartbeats、workspaces。
- 事件时间戳缺 tz/精度的表：repayments（4 列）、cash_events.event_at、limit_snapshots.balance_as_of 等；只有 transactions 和 preauth_holds 带 tz 与 time_precision。
- 无 CHECK 的状态/种类列共 21 个，见 R2-17。
- 不排除 tombstone 的唯一约束：11 条唯一约束，加 3 个复合自然主键（plan_allocations、repayment_allocations、snapshot_included_events）。

**FKS（外键与软引用）**
指向租户表、却不含 workspace_id 的外键只有 `fk_card_products_bank_id`、`fk_credit_accounts_bank_id`、`fk_credit_accounts_product_id`、`fk_credit_pools_bank_id`、`fk_rule_bindings_billing_rule_version_id`。没有外键的 uuid `*_id` 列：各表的 origin_device_id、6 个 source_document_id、evidence_document_id、subject_id、row_id、job_id、entity_id、resulting/duplicate_of_id、caused_by_id、audit_log 和 deletion_tasks 和 jobs 的 workspace_id——与迁移说明列出的"软引用"一致。

**MIG（临时库 cardflow_review_ext，执行后已删除）**
```
before upgrade: ['pg_trgm', 'plpgsql']
after downgrade base: ['plpgsql'] (pg_trgm existed before 0001 and was dropped by its downgrade)
downgrade with foreign dependency: failed loudly: 2BP01 cannot drop extension pg_trgm because other objects depend on it
after failed downgrade: alembic_version [('0001',)] tables 60 (transactional: nothing half-dropped)
```
离线模式：`python -m alembic -x url=… upgrade head --sql` 退出码 0，输出 1833 行，59 个 CREATE TABLE。

**MUT（变异，/tmp 副本中执行；测试库前缀改为 `cardflow_review_t_`，副本已删除）**
```
M1 model: repayments ck amount_minor > 0 -> >= 0            => FAILED test_catalog_definitions_match_models
M2 model: drop postgresql_where of ix_cash_events_…          => FAILED test_catalog_definitions_match_models
M3 model: drop ondelete=CASCADE on snapshot_included_events  => FAILED test_autogenerate_reports_no_difference + test_catalog_…
M4 migration: SUM without "AND a.deleted_at IS NULL"         => FAILED test_tc_db_09_tombstoned_allocations_do_not_count
M5 migration: card_products_workspace_immutable UPDATE OF name  => 77 passed (not detected)
M6 migration: credit_pools_bank_scope BEFORE INSERT only        => 77 passed (not detected)
M7 migration: drop FOR NO KEY UPDATE                             => FAILED test_tc_db_09_concurrent_allocations_are_serialised
M8 migration: currency_account subject branch without workspace check => 77 passed (not detected)
```

**CLEANUP**
删除 cardflow_review_main 后，开发集群只剩 `['cardflow', 'postgres', 'template0', 'template1']`，没有残留的 `cardflow_review*` 角色；`/tmp/cardflow-review/api*` 副本已删除。

---

## 5. 给 T-006（RLS/角色）与 T-008（jobs）的建议

1. **先堵 R2-01**：`REVOKE TEMPORARY ON DATABASE cardflow FROM PUBLIC`，不向 cardflow_app/cardflow_admin 授予 TEMP；并在 0002 中固定函数的 search_path。TC-DB-05 增加"非超级用户 + 临时表遮蔽"反例。
2. **角色属性**：app 角色不是表的属主，没有 BYPASSRLS，不是超级用户，不能 `ALTER TABLE … DISABLE TRIGGER`，也不能设置 `session_replication_role`。迁移角色和 app 角色分开。
3. **模板表**（banks、card_products、billing_rule_versions）：SELECT 策略为 `workspace_id IS NULL OR workspace_id = 当前空间`；INSERT/UPDATE/DELETE 的 WITH CHECK 只允许 `workspace_id = 当前空间`。模板写入走 admin 角色单独的策略。作用域触发器的查找条件与此一致，在 RLS 下仍然正确。
4. **追加式表**：statement_versions、statement_lines（以及决定 2 扩展后的表）只授 SELECT、INSERT；清除走专用角色（R2-10）。
5. **列级 UPDATE 授权**：不含 id、workspace_id，以及应当不可变的外键列和币种列（currency_account_id、currency 等），配合 R2-04、R2-05、R2-11。
6. **延迟检查的权限**：凡是写 repayment_allocations 的角色，在当前实现下都需要 repayments 的 UPDATE 权限（R2-02/P1）；若改用 SECURITY DEFINER，需固定 search_path，并评估属主在 FORCE RLS 下的行为。
7. **admin 角色的列级 SELECT 不应包含的正文列**：transactions（金额/商户）、statement_versions.*_minor、statement_lines.description/amount_minor、extraction_candidates.*_value、idempotency_keys.response_body、sync_changes.payload、sync_conflicts.*_payload、plan_runs.result、jobs.payload/result/last_error、source_documents.storage_key/dek_wrapped、workspaces.dek_wrapped、users.password_hash、auth_sessions.refresh_token_hash。
8. **其他表**：users 是全局表，建议通过成员关系视图或 SECURITY DEFINER 函数访问；audit_log 对 app 只开放 INSERT；sync_changes 只开放 INSERT + SELECT；jobs 对 app 按 workspace_id 启用 RLS，worker 使用独立角色（R2-27）。
9. **威胁模型说明**：`app.workspace_id` 是任何会话都能自行 SET 的 GUC，RLS 只防应用逻辑错误，防不了 SQL 注入；这一点应写进 T-006 文档。注入场景下依赖复合外键和触发器兜底，所以 R2-01 必须修复。
10. **FORCE RLS 与数据迁移**：表启用 FORCE RLS 后，属主执行的数据修复也会被过滤；后续迁移如需改数据，要用具备 BYPASSRLS 的迁移角色，或按工作空间逐个设置 GUC。
11. **T-008**：增加租约回收索引 `(locked_until) WHERE status='running'`（对应 queue.py 中的回收查询）；考虑让领取的排序 `ORDER BY run_after, created_at` 与部分索引的列一致；增加周期任务去重键；payload 只放 id。
