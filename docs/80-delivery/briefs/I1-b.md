# 简报 I-1b · 现金账户、快照、收支计划、三口径与情景、资金日历（UF-1 步骤 4–5、UF-5）

派发：I-1a 验收后。对应 `ios-first-plan.md` §3 的 I-1 第三段（现金账户、快照、收支计划、三口径、情景；资金日历与缺口）。本任务**不出 IPA**，不触发 iOS 构建。若需重新派发，在开头加一句"先核对磁盘与 git 现状，不要重复创建"。

## 环境与规则
与 `briefs/I1-a.md` 相同（仓库、Flutter 路径、VPS 限制、依赖只来自 architecture §11、不引入 uuid/timezone/freezed、小步提交推送、CI dart job 必须绿、代码生成产物随源码提交、无 Claude/AI 署名）。范围：`apps/mobile/`、`evidence/i1/I1-b/`、根 README 一行。**不改**领域包、协议包、services/api、docs；领域包缺口先停下汇报。证据 tee 到 evidence/i1/I1-b/。

必读：PRD §4.3（R-CASH-01~10）、UF-5；ui-spec P-07、P-08、P-09、P-01（现金压力卡）、UF-1 步骤 4–5、UF-5；data-model §3/§4（cash_accounts、cash_balance_snapshots、snapshot_included_events、cash_events）；engine-spec §12/§12.1 的现金与情景语义；领域包 `lib/src/cash.dart`（`CashEvent`、`Snapshot`、`CashAccount`、`Scenario`、`EventOverride`、`buildTimeline`、`evaluate`、`evaluateAccounts`）与 `checks.dart`（`dataIssues`、`baselineCheck`）；apps/mobile/README.md 的"加密本地库"（schema v2 与加表步骤）、"工作空间与演示模式"、"仓库与 provider"、"I-1a 的偏离与约定"、"数据层 → 领域对象映射"各节（即 I-1a 的接口说明）；`lib/data/repositories/`、`lib/data/mapping/domain_mapping.dart`、`test/data/repositories/repository_test_support.dart`、`test/test_helpers.dart`。

## 1. 本地库 v3
- `LocalSchema.currentSchemaVersion` → 3；2→3 只 expand；新建 vs 升级结构一致测试照旧。
- 表：
  - `cash_accounts`(id, workspace_id, name, currency, kind `bank`/`wallet`/`wealth`/`restricted`, usable_for_repayment, available_from, reserve_floor_minor ≥0, status, created_at, updated_at, deleted_at)。
  - `cash_balance_snapshots`(id, workspace_id, cash_account_id, balance_minor, balance_as_of 日期, observed_at 时刻, source_kind, confirmation_level, recorded_at)；`snapshot_included_events`(snapshot_id, cash_event_id)：只允许快照日当天及以前的事件（仓库层校验）。
  - `cash_events`(id, workspace_id, cash_account_id, event_on, event_at 可空, amount_minor 收入为正支出为负, cls `confirmed`/`expected`/`planned`, category, label, posting_status `planned`/`posted`, recurring_item_id, occurrence_key, transfer_group_id, linked_repayment_id, linked_plan_run_id, created_at, updated_at, deleted_at)。唯一现金事实表。
  - `recurring_items`(id, workspace_id, cash_account_id, label, amount_minor, cls, category, frequency `monthly`/`weekly`/`biweekly`/`yearly`, anchor_on, day_rule, start_on, end_on, active)；`recurring_overrides`(recurring_item_id, occurrence_key, action `skip`/`override`, amount_minor, event_on, event_at)：周期事项按需展开成 `cash_events`（展开到 horizon），单条可覆盖/跳过而不影响他期。
  - 调拨：两条 `cash_events` 共享 `transfer_group_id`（转出负、到账正，到账日 ≥ 转出日）；不设任何"概率"字段。
  - `scenarios`(id, workspace_id, name UNIQUE per workspace, kind `builtin_confirmed`/`builtin_baseline`/`user_stress`, include_expected, income_delay_days 0–180, income_scale 十进制文本 0–1, expense_scale ≥1, same_day_order, limit_changes JSON, event_overrides JSON, created_at, updated_at)；内置两条只读。
  - `scenario_runs`(id, workspace_id, scenario_id, version_no, computed_at, horizon_from, horizon_to, inputs_hash, result JSON：逐账户最低点、缺口点、假设、数据问题)；旧版本保留用于对比。
- 数据层 → 领域映射：账户/快照/事件 → `CashAccount`/`Snapshot`/`CashEvent`；情景 → `Scenario`；陈旧判定 `dataIssues(staleAfterDays: 7)`；受限账户或 `usable_for_repayment=false` 且无 `available_from` 的账户不进入可用现金；`evaluateAccounts` 始终逐账户，不互抵。

## 2. 页面
- **P-08 现金账户与收支计划**：账户列表（最新快照、"{n} 天前"陈旧徽标、可用性、储备）；详情（快照历史、已包含事件）；「记录新快照」时若同日已有事件，逐条询问"余额是否已包含 {事件}"并写入 included events；收支计划（确定/预计收入、固定生活支出、其他债务、一次性支出、周期事项；逐条覆盖/跳过）；调拨（两端账户不同、到账 ≥ 转出）。校验：G1/G3/G4/G5；储备 ≥0；收支必须选层级（确定/预计），没有概率字段；缺实际时点不可存。
- **P-07 资金日历**：控制条（7/30/90/180 天、账户、口径 已确认/基准/压力情景、情景选择）；摘要（全窗口最低点与日期、缺口数、距零/距储备）；日行（流出、流入、当日最低）；缺口 ▲ 标记；储备虚线；图表↔表格切换可先只做表格；缺口列表（全部缺口点 + 造成缺口的事件）；尾部责任区（本任务先接入"窗口外的 planned 事件"，分期在 I-1c 接入）；假设列表（先支出后收入、快照包含、陈旧→"假设分析"）。无缺口用中性色，不用绿色，不出现"安全/稳妥"。数据变化自动重算（provider 依赖）。
- **P-09 情景与假设对比**：列表（内置两条不可改；用户压力情景带参数、最近计算、状态）；编辑器（收入延迟 0–180、收入比例 0–100%、支出比例 ≥100%、额度变化占位（账户+日期，I-2 使用）、事件覆盖、同日顺序：按时间戳排序须所有事件有时刻）；「重算」生成新 `scenario_runs` 版本；「对比」两情景或两版本并排（最低现金、日期、缺口数、逐账户差异）；输入变化后标"过期"。
- **P-01**："现金压力"卡：最低点、首个缺口日、口径；陈旧 → "假设分析"徽标；缺快照账户 → "数据不全：{账户}缺快照，未计入"。
- 演示空间：加现金账户 2 个（一个受限）、快照、收支计划、一个周期事项、一笔调拨、一个压力情景，固定"今天"下有一个可见缺口。
- 可访问性 3.0x 检查加入新页面。

## 3. 测试
- 迁移：新建 vs 升级一致。
- 仓库 → 领域：F-01（已确认口径排除预计收入）、F-02（收入延迟 3 天情景最低现金按期望变化）、F-03（两账户隔离）、F-04（快照当天未包含事件计入；同日只有日期时先支出后收入并记假设）、F-05（全部缺口点、距零/距储备）、F-07（快照 >7 天 → 数据问题、"假设分析"，不补零）：用与领域包测试相同的数值构造数据库行，经仓库映射后调用领域包，结果必须与领域包直接计算完全一致（逐字段）。
- 周期事项展开与单条覆盖/跳过；调拨两端；受限账户排除；快照包含只接受快照日及以前；情景版本保留与对比；情景校验边界。
- 组件：P-07/P-08/P-09 四态与关键交互；无缺口不出现绿色（断言颜色 token）。
- 工作空间隔离测试扩展到新表。
- analyze/format/build web 照旧。

## 4. 文档
`apps/mobile/README.md`：v3 表清单、周期事项展开规则、情景版本约定、"数据层 → 领域对象映射"补现金部分。根 README 一行状态"I-1b（现金与资金日历）"。

## 5. 审查带入项（I-0 阶段末审查 `evidence/i0/review-i0.md` §4 第 2 条）
交给 `verify`/`boundedSearch` 的数据先经 `inputsToProtocol`（它会再跑一遍 `inputsFromProtocol` 的全部交叉校验）。只用现金时间线的资金日历在仓库层复刻这些交叉规则并测试：事件 `at` 的日期按自身偏移等于 `on`；`includes` 只列快照日当天及以前的本账户事件；金额绝对值 ≤ 10^13；ID 唯一；币种一致。领域对象构造函数不做这些检查（与 Python 数据类相同）。若认为应在领域包提供公开校验函数，停下汇报，不自行改领域包。

## 验收（evidence/i1/I1-b/）
analyze.txt、format.txt、test.txt、schema-diff.txt、parity-with-domain.txt（F-01~F-05/F-07 经仓库映射与领域包直算一致的测试输出）、build-web.txt、ci-dart-run.txt、git-log.txt。

## 回复格式
1. 完成项与路径；2. 验收结果；3. 偏离/疑问；4. 给 I-1c 的接口说明：现金仓库 API、如何由还款生成 planned 现金事件（`linked_repayment_id`）并在扣款确认时转 confirmed、尾部责任的数据接口、测试工厂。
