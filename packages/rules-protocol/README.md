# packages/rules-protocol — 规则协议 v1

规则协议 v1（JSON Schema：BillingRule、Snapshot、CashEvent、Scenario、PlanRequest、CardOption、PlanOutcome）与 golden fixture 运行器
由任务 T-004 在本目录实现，见 `docs/20-architecture/architecture.md` §10 与 `docs/80-delivery/m0-execution-plan.md` §4。
金额字段一律为整数最小单位 + 币种，schema 不允许 float 金额。

状态：v1 已实现（T-004，2026-10-17），冻结前按 engine-spec §12 修订（T-004c，2026-10-18，引擎模型 1.1.0，见文末修订记录）；Python 运行器对 F-18 通过；Dart 运行器由 T-022 实现（待环境）。
引擎侧适配层：`services/api/cardflow/planner/engine/protocol.py`（只用标准库）；测试：`services/api/tests/protocol/`。

## 目录结构

```text
packages/rules-protocol/
├── README.md
├── ruff.toml                     # Python 代码沿用 services/api 的 ruff 规则
├── schema/v1/                    # JSON Schema draft 2020-12，$id 前缀 https://rules-protocol.cardflow.invalid/v1/
│   ├── common.schema.json        # $defs：MinorAmount（int64 整数最小单位）、Currency、Date、Timestamp、Id、
│   │                             #        EventId、DecimalString（利率/系数）、DayCount、Sha256Hex、Profile…
│   ├── BillingRule.schema.json   # 账期规则版本（含 DueRule：fixed_day / days_after_statement）
│   ├── CardOption.schema.json    # 候选卡
│   ├── CashAccount.schema.json   # 现金账户
│   ├── CashEvent.schema.json     # 现金事件
│   ├── Snapshot.schema.json      # 余额快照（含 includes_event_ids）
│   ├── Scenario.schema.json      # 情景（含 event_overrides）
│   ├── PlanRequest.schema.json   # 计划消费
│   ├── Pools.schema.json         # 共享额度池
│   ├── Options.schema.json       # profile、decision_scenario、time_limit_s、workers、seed、stale_after_days、global_reserve_floor_minor
│   ├── PlanInput.schema.json     # 一次求解的完整输入 = 以上全部 + horizon_end；input_hash 的对象
│   ├── PlanOutcome.schema.json   # 运行结果（engine-spec §6 + API-52）；$defs 另含 VerificationResult、CardCycles
│   └── Fixture.schema.json       # golden fixture = PlanInput + expected（cases + assertions）
├── fixtures/
│   ├── regression_2026-10-16_10000.json      # 人工格式（T-003 复制自 PoC，字节不得改动）
│   └── regression_2026-10-16_10000.v1.json   # 协议 v1 格式（由转换器生成，逐字节可复现）
└── runner_py/
    ├── run_fixtures.py             # Python 运行器（jsonschema 校验 → 适配 → 引擎 → 逐字段比对）
    └── convert_legacy_fixture.py   # 人工格式 → v1 的确定性转换器
```

`.invalid` 是保留顶级域名：`$id` 只是名字，校验时从本目录加载，从不联网。

## 版本规则

- 每个文档带 `protocol_version`，v1 固定为字符串 `"1"`；适配层与运行器拒绝其他值。`PlanOutcome.protocol_version` 记录产出它的协议版本（API-52、`plan_runs.protocol_version`）。
- `schema/v1/` 在 M0 验收（T-041）后冻结：凡是改变"哪些文档合法"或"字段含义"的修改（增删字段、改类型/范围/枚举、改默认值、改语义规则），一律发布新版本 `"2"`（新目录 `schema/v2/`、新 `$id` 前缀、重新派生 fixtures），v1 继续可运行；只改 `description`/`title` 等说明文字不升版本。冻结前的修改必须同时重新生成 fixtures 并让两端运行器通过。
- `model_version`（引擎模型版本，当前 `1.1.0`，见 `cardflow.planner.engine.MODEL_VERSION`；`1.0.0` 为首个生产版本，`1.1.0` 落实 engine-spec §12）与协议版本相互独立：引擎语义变化升 `model_version`；golden fixture 必须继续通过，否则只能显式重新基线并写明原因。

## 字段约定

- **金额**：一律 `integer` 最小单位（CNY 分、JPY 元、KWD 第 3 位小数），币种 = `request.currency`；v1 的计划是单币种（每个现金账户的 `currency` 必须等于请求币种）。**输入**金额（`MinorAmount` 系列）限于 |v| ≤ 10^13（见下节"支持的数值范围"）；**输出**金额（`ResultMinorAmount` 系列，可能是多笔之和，如余额）用完整 int64。输入对象的金额字段以 `_minor` 结尾；输出沿用 API-52：分配行用 `_minor`，检查/缺口/敏感性等嵌套结构保留引擎字段名（`balance`、`gap_to_zero`、`total`…），同样是整数最小单位。
- **整数是严格的**：`1.0`、`1e2` 是浮点记号，不是整数（标准 JSON Schema 会把 `1.0` 当整数；本运行器的校验器与适配层都拒绝，Dart `jsonDecode` 也会得到 `double`）。`true/false` 不是整数。例如金额 `1000000.0` 在标准 JSON Schema 下"合法"，在 v1 中一律非法：任何端（含 T-022 若使用通用校验库）都必须把 schema 的 `integer` 重新定义为"不带小数点和指数的整数记号"（Python 运行器：`StrictValidator`；Dart：`value is int`），否则会接受 v1 拒绝的文档（R3E-22）。
- **利率/系数**：十进制字符串，从不使用 JSON 数字，且必须是**规范写法**：不带多余的尾零，零写 `"0"`、一写 `"1"`（`"0.006"` 合法，`"0.00600"`、`"1.0"`、`"0.0"` 非法）——同一个值只有一种写法，因此相同的利率永远得到相同的 `input_hash`（R3E-11）。利率（`Rate`：`fee_rate`、`verified_benefit_rate`、`potential_benefit_rate`）为 0–1、至多 5 位小数，`^(0|1|0\.[0-9]{0,4}[1-9])$`；情景系数（`ScaleFactor`：`income_scale`、`expense_scale`）为 0–10、至多 10 位小数，`^(10|[0-9]|[0-9]\.[0-9]{0,9}[1-9])$`。从数据库读出的 `NUMERIC(20,10)`（如 `Decimal('0.0060000000')`、`Decimal('0E-10')`、`Decimal('1.0000000000')`）由 `inputs_to_protocol` 写成规范形式（`"0.006"`、`"0"`、`"1"`；`money.decimal_text`）；超出范围或位数的值报 `ProtocolError`，绝不取整。
- **唯一允许的非整数 JSON 数字**：输入 `options.time_limit_s`，输出 `time_limit_s`、`wall_time_s`、`tiers[].wall_time_s`（计时字段，非金额；`tests/protocol/test_schemas.py` 扫描所有 schema 守护此白名单）。
- **日期** `YYYY-MM-DD`，输入年份 1970–2999，月 01–12、日 01–31（`pattern`），且必须是真实日期（`date` format，如拒绝 `2026-02-30`）；**时间戳** RFC 3339，必须带时区偏移（`Z` 或 `±hh:mm`，偏移小时 00–23），小时 00–23、分秒 00–59（不接受闰秒 `60`），小数秒至多 6 位，`T`/`Z` 大写，年份同上，且必须是真实日期（`date-time` format）。`pattern` 与 format 两者都要检查：jsonschema 未安装 rfc3339-validator 时不检查 `date-time`，Python 运行器因此注册了标准库实现（`run_fixtures.FORMAT_CHECKER`）；适配层用同样的规则（R3E-20）。输出日期（`ResultDate`）不限年份：到期日等派生日期可比最晚的输入日期晚约两年。
- **文本长度**（`Text`，`maxLength` 1000）按 **Unicode 码点**计数，与 JSON Schema 和 Python `len` 一致：一个 emoji 计 1（虽然它是两个 UTF-16 码元）。Dart 端必须用 `runes.length`，不能用 `String.length`（R3E-21）。
- **数组大小**：`cards` ≤ 200、`cash_accounts` ≤ 100、`events` ≤ 10,000。
- **ID** `^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$`；事件 ID 不得以 `plan_repay_` 开头（引擎为计划还款保留）。
- **对象一律封闭**（`additionalProperties: false`）；以 ID 为键的映射（输出中的 `checks`、`min_balance_by_account` 等）用 `propertyNames` + 值 schema。输入里的集合一律是数组（顺序有意义：分配行、拒绝原因按 `cards` 顺序，情景按 `scenarios` 顺序）。
- **可省略成员的含义**：`name` 省略 = 对应 ID；`label`、`description`、`source` 省略 = 空串；规则 `status` 省略 = `user_declared`；`pool_id`、`per_txn_cap_minor`、卡级 `min_split_minor`、`verified_benefit_cap_minor`、`effective_from/to`、`verified_on`、`observed_at`、`at` 省略 = 无。其余成员全部必填（没有隐藏默认值）。
- **JSON Schema 表达不了、每个适配层都必须检查的规则**（Python 见 `inputs_from_protocol`）：`cards`/`cash_accounts`/`events`/`scenarios`/`pools` 内 ID 唯一；每个现金账户至多一个快照；所有 `cash_account_id`、`repay_from_cash_account_id` 指向已有现金账户；`includes_event_ids` 只能列本账户的已有事件，且事件日期不得晚于该快照的 `as_of`（快照不可能已包含之后的事件，R3E-14）；事件的 `at` 按其自身偏移取日期，必须等于 `on`（R3E-14）；同一 `credit_account_id` 的卡必须给出相同的 `raw_available_minor`（账户可用额只有一个值）和相同的 `pool_id`（R3E-04）；`event_overrides` 只能指向已有事件且每个事件至多一次；`posting_delay_min_days ≤ posting_delay_max_days`；现金账户币种 = 请求币种。
- **由引擎给出业务结果、协议层不拒绝的情况**：账户缺快照（`NEEDS_DATA/MISSING_SNAPSHOT`）、快照过期或晚于交易日（`STALE_SNAPSHOT`/`SNAPSHOT_AFTER_TXN_DATE`）、卡的池无条目（`MISSING_POOL_SNAPSHOT`）、`decision_scenario` 不在情景中（`UNKNOWN_DECISION_SCENARIO`）、规则需要工作日日历（`BILLING_RULE_INVALID`）。无求解器的验证路径（`verify_from_protocol`、fixture 的 `verify` case、Dart 本地验证器）先做同样的数据检查（`UNKNOWN_DECISION_SCENARIO` 除外：验证请求自带的情景不存在是 `ProtocolError`）：有问题时返回 `data_issues`、`allocation: []`、`verification: null`，绝不抛异常（R3E-13）。
- **engine-spec §2 中引擎 1.1.0 尚未支持的字段**（出现即拒绝，绝不静默忽略）：PlanRequest 的 `merchant`、`category`、`allow_installment`、`reserve_cash_override`、`reserve_limit_by_card`；CardOption 的 `daily_cap`、`temp_limit_expiry`、`future_releases`；CashAccount 的 `available_from`。API-51 求解请求的 `reserve_override_minor`（用户临时降低储备，engine-spec §4）在 v1 中同样不支持、没有对应字段：由 T-009 在 API 层拒绝（`VALIDATION_ERROR`），不得改写 `reserve_floor_minor` 冒充。
- **额度的三层**（engine-spec §12.3，bank-rules-spec §5"卡 ≤ 账户 ≤ 池，同时检查"）：卡层 = max(0, `raw_available_minor` − 本卡 `holds_uncounted_minor` − 本卡 `reservations_minor`)；**信用账户层**：同一 `credit_account_id` 的卡（主卡、附属卡）共享账户可用额，容量 = max(0, 账户可用额 − 该账户所有卡的预授权与预留之和)；**池层**：容量 = max(0, 池 `available_minor` − 池内所有卡的预授权与预留之和)。每层都按 0 截断：耗尽的层使其卡全部 `NO_CAPACITY`（`detail` 说明是卡、哪个信用账户或哪个池），层外的卡不受影响。v1 只表达一层池；多层池在 M2 随协议 v2 支持，此前不得用一层池近似多层。一笔预授权或预留只记在账户的**一张**卡上（不得在每张卡上重复，否则会被重复扣减）。
- **检查区间只取决于输入**（engine-spec §12.7）：现金时间线检查到 `horizon_end` 为止，**不再延长**；现金还款日晚于 `horizon_end` 的卡判为不可用，拒绝原因 `REPAY_AFTER_HORIZON`。求解接口（T-009）把 `horizon_end` 设为不早于交易日后 180 天。
- **快照与情景的先后**（engine-spec §12.2）：先按**原始事件**判定"已被快照反映"（日期早于 `as_of`，或等于 `as_of` 且列在 `includes_event_ids` 中）并剔除，再做情景变换（剔除预计事件、覆盖、收入延迟与缩放、生活支出缩放）；变换后日期早于 `as_of` 的事件按 `as_of` 当日计入，不丢弃。
- **同日顺序**（engine-spec §12.4）：情景要求按时间戳且当日**每个已有事件**都带 `at` 时按 `at` 排序（相同时刻保持 `events` 数组顺序），否则先支出后收入。计划还款（验证器的 `plan_repay_<卡>`）与模型的候选还款日不参与这一判断；在按时间戳排序的日子里，计划还款排在当日最前（与模型从当日最低点扣除还款的写法一致）。被情景改动了日期的事件丢弃原 `at`，在新日期上按保守顺序处理。
- **费用进入现金**（engine-spec §12.6）：手续费（费率部分向上取整 + 固定费）与本金同一期出账，在 `repay_on` 当天随还款从还款现金账户流出：现金时间线中的还款额 = 分配金额 + 该卡费用；已核实收益不作为现金流入。
- **可复现**（engine-spec §12.5）：最后一个目标层之后仍有并列最优时，取**按卡的输入顺序字典序最大**的分配（每张卡依次在剩余最优解中取尽可能多的金额），主求解与敏感性求解（最少补充现金：先分配、再按现金账户输入顺序；最大可负担金额）都如此；因此同一输入、同一 seed 在任意 `workers` 下得到同一结果（前提是每一步都在时限内证明最优，否则 notes/`detail` 写 `TIE_BREAK_INCOMPLETE`）。
- **时限**（engine-spec §12.9）：`options.time_limit_s` 是整次运行所有 CP-SAT 调用的预算：主求解（各目标层与平局处理）最多用一半，敏感性求解分享剩余时间；每次调用都在运行开始后 `time_limit_s` 内结束。来不及计算的敏感性项标为 `NOT_RUN`（`detail` 说明），某一项无法建模只把该项标为 `MODEL_INVALID`，整次运行的状态不变。推迟日期搜索在每个平移日期重新判定卡的可用性：规则在该日不生效（如 `effective_to` 已过）的卡当日不可用。
- **引擎的不可用判定与验证器违规**（v1 修订，见文末）：建模前的排除顺序为 `CARD_STATUS`、`CURRENCY_NOT_SUPPORTED`、`CHANNEL_NOT_SUPPORTED`、`REPAY_ACCOUNT_MISSING`、`REPAY_ACCOUNT_RESTRICTED`、`NO_CAPACITY`（卡、信用账户、池）、`MIN_SPLIT_ABOVE_AMOUNT`（卡的最小拆分额大于本次金额）、`REPAY_BEFORE_TXN_DATE`（现金还款日早于交易日）、`REPAY_AFTER_HORIZON`；全部卡被排除时业务状态 `INFEASIBLE`、求解器 `NOT_RUN`，若有卡因 `REPAY_BEFORE_TXN_DATE` 被排除，仍计算推迟日期敏感性（另两项为 `NOT_RUN`）。其余未用的卡：`INSUFFICIENT_LIMIT_ALONE`（`capacity` = 本次可用的上限：卡、单笔上限、信用账户、池中最小者，`detail` 指明是哪一层）、`CASH_BREACH_ALONE`、`DOMINATED`（单独可行，但求解器给出的方案在目标层上更优）、`NOT_COMPARED`（单独可行，但求解器没有给出可比较的方案：`UNKNOWN`/`MODEL_INVALID`）。验证器遇到早于快照日的计划还款，按快照当日计入（不跳过）并记违规 `PLANNED_REPAYMENT_BEFORE_SNAPSHOT: …`；共享账户层或池层超额记违规；验证器只接受整数金额（float/bool/Decimal/str → `TypeError`，绝不截断）。
- **只有可执行状态才有方案**（engine-spec §12.1）：`FEASIBLE_ROBUST` 与 `CONDITIONALLY_FEASIBLE` 之外，`allocation` 一律为空、`verification` 为 `null`（schema 用 if/then/else 强制）；被验证器拒绝的求解结果（`MODEL_INVALID`，notes 含 `VERIFIER_REJECTED_SOLVER_SOLUTION`）只出现在 `diagnostics.rejected_allocation`/`rejected_verification` 中，任何路径都不得展示或采纳。可执行状态的 `diagnostics` 为 `null`。
- **基线包含全局底线**（engine-spec §12.8）：每个情景的基线检查（`baseline[s]`）除各账户储备外，还检查所有现金账户合计不低于 `options.global_reserve_floor_minor`，检查点为每个快照日与任一账户有事件（最低点）的每一天，缺口列在 `baseline[s].global_breaches`；决策情景的基线不满足即 `BASELINE_SHORTFALL`。
- **建模异常兜底的范围**（engine-spec §12.10）：只有建模与求解调用中的 `ValueError`/`TypeError`/`OverflowError`（OR-Tools 无法表示某个值）成为 `MODEL_INVALID`，notes 写 `MODEL_BUILD_ERROR: <异常类名> while building the CP-SAT model (no plan is shown)`；CP-SAT 自身的模型校验失败写 `MODEL_VALIDATION_FAILED: CP-SAT rejected the model (no plan is shown)`；两者都不含输入值，也不断言原因。其他阶段的异常是缺陷，直接抛出（不再伪装成"超出支持范围"）。经协议进入的运行在适配层就会因超出支持范围而得到 `ProtocolError`。
- **错误消息不回显输入值**（R3E-12）：`ProtocolError` 只给 JSON Pointer（`path`）与违反的规则，不含任何 ID、日期、利率、数字或其片段；严格 JSON 读取的错误也只给语法规则与位置（行、列或字节偏移）。

## 支持的数值范围（T-004b）

协议 v1 只接受引擎的 CP-SAT 模型能精确表示的输入：在下列上限内，引擎建的每一个约束都低于 CP-SAT 的溢出界（变量域与每个线性约束的 Σ|系数|·max|变量| + |常数| 都不超过 int64 最大值的一半 ≈ 4.61×10^18；`model.validate()` 正是检查这一点）。超出上限在适配层报 `ProtocolError`（API：`VALIDATION_ERROR`），schema 同样拒绝。

| 量 | 上限 | 依据 |
|---|---|---|
| 输入金额 M（所有 `*_minor`、余额、事件、池、储备） | \|v\| ≤ 10^13 最小单位（CNY 1,000 亿元） | 等于引擎的变量上界 `BIG`（余量、补充现金、费用、收益变量的域都是 [0 或 −BIG, BIG]） |
| 利率小数位 F、利率值 R | F ≤ 5、0 ≤ R ≤ 1 | 费用约束 `f·den ≥ x·num + fixed·den·y`：BIG·10^F + M·R·10^F + M·10^F ≤ 3×10^18 需要 F ≤ 5（F = 6 时第一项就是 10^19） |
| 情景系数 S | 0 ≤ S ≤ 10 | 现金约束的常数项是余额 = 快照 + Σ(事件×系数)：≤ (1 + E·S)·M |
| 事件数 E、现金账户数 A | E ≤ 10,000、A ≤ 100 | 每账户现金约束 ≤ 2·BIG + n·(M + BIG) + (2 + E·S)·M ≈ 1.0×10^18（`n·BIG` 是 1.1.0 起随还款扣除的费用变量）；全局底线约束 ≤ (A + E·S)·M + A·BIG + n·(M + BIG) ≈ 1.0×10^18 |
| 卡数 n | n ≤ 200 | 缓冲目标 Σ x·buffer_days ≤ n·M·489（入账延迟 ≤ 366 天 + 下一期 ≤ 31 天 + 到期 ≤ 92 天）≈ 9.8×10^17 |
| 日期 | 1970-01-01 – 2999-12-31 | 引擎会在日期上加至多约两年（入账延迟、到期、推迟搜索、收入延迟），远离日历上下限 9999/0001 |

最紧的是费用约束（3×10^18，余量约 1.5 倍）。费用变量的取值上界是 `BIG`：在极端输入下（费率接近 1、固定费接近 10^13）某笔分配的费用超过 10^13 最小单位时，模型把该分配视为不可行（比验证器严格，绝不会接受验证器拒绝的方案）；这是数值范围的边界，不在现实输入中出现。`tests/protocol/test_limits.py` 用"所有值都取上限"的文档（200 张卡、100 个账户、10,000 笔事件、费率 0.99999、系数 10）实际建模并通过 `model.validate()`；再越过一步（利率第 6 位小数，或金额 ×10）即被 CP-SAT 判为溢出或拒绝建约束。若引擎的 `BIG` 或模型结构改变，必须重新推导这张表。

## 规范化 JSON 与 input_hash

`input_hash = lowercase_hex(sha256(canonical_json(PlanInput)))`，Python 实现为 `protocol_input_hash` / `canonical_json`（`cardflow/planner/engine/protocol.py`）。规范化规则（与 RFC 8785/JCS 一致，唯一差别：整数永远按精确十进制写出，不经过 double）：

1. 输入是**解析后的** PlanInput 文档：UTF-8、无 BOM、无重复键、无 NaN/Infinity（`parse_json` 严格解析）。文件的缩进、换行、成员顺序都不影响哈希。
2. 无任何空白；分隔符为 `,` 与 `:`。
3. 对象成员按键排序，比较键的 **UTF-16 代码单元**序列（RFC 8785 §3.2.3）；v1 所有键都是 ASCII，因此等同于按字节 / Python `sort_keys`。数组保持原顺序（顺序有意义）。
4. 字符串：`"` 与 `\` 写作 `\"`、`\\`；U+0008、U+0009、U+000A、U+000C、U+000D 写作 `\b \t \n \f \r`；其余 U+0000–U+001F 写作 `\u00xx`（小写十六进制）；其他字符（含 `/`、U+007F、U+2028、中文）原样 UTF-8 输出；孤立代理项是错误。
5. `true`、`false`、`null` 原样。
6. 数字：整数记号写成精确十进制（负号 `-`，无 `+`、无前导零，完整 int64 范围）；非整数（v1 只可能是 `options.time_limit_s`）按 ECMAScript `Number.prototype.toString`（RFC 8785 §3.2.2.3）：`10.0 → 10`、`0.5 → 0.5`、`1e-6 → 0.000001`、`1e-7 → 1e-7`、`1e21 → 1e+21`、`-0.0 → 0`。

对不含浮点记号（带小数点或指数的 JSON 数字）的 v1 文档，结果与 `json.dumps(doc, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")` 逐字节相同。

测试向量（`tests/protocol/test_adapter.py` 全部断言）：

| 值 | 规范化 JSON |
|---|---|
| `{"b":1,"a":[true,false,null]}` | `{"a":[true,false,null],"b":1}` |
| `{"金额":"卡A","z":"€"}` | `{"z":"€","金额":"卡A"}` |
| `{"😀":1,"ﬁ":2}`（U+1F600、U+FB01） | `{"😀":1,"ﬁ":2}`（UTF-16 序：D83D < FB01） |
| `9223372036854775807` / `-9223372036854775808` | 原样 |
| `10.0` / `0.5` / `-0.0` / `1e-7` / `1e21` / `2^68` | `10` / `0.5` / `0` / `1e-7` / `1e+21` / `295147905179352830000` |
| F-18：`fixtures/regression_2026-10-16_10000.v1.json` 的 `input` | sha256 `ea990327f08b42d476fa157d9bb8ddff6a1d8eb4e41ff60b1e498c5861a91ee8` |

**三种哈希，用途不同，不要混用**：

| 哈希 | 计算对象 | 用在哪里 |
|---|---|---|
| `protocol_input_hash(doc)`（语言中立） | PlanInput 文档（数据 + 情景 + 选项） | 所有经协议进入的运行：`PlanOutcome.input_hash`、`plan_runs.input_hash`、Dart 端、fixture 运行器 |
| `run_input_hash(...)`（引擎内部，1.1.0 起） | Python 引擎对象：数据 + 情景（按顺序）+ 选项（决策情景、画像、时限、`stale_after_days`、workers、seed） | 直接用引擎对象调用 `plan()` 时的默认 `input_hash`（R3E-15：换决策情景或画像即换哈希）；`solve()` 直调时同理（不含 `stale_after_days`）。依赖 Python 数据类表示，其他语言无法复现 |
| `ModelInputs.input_hash()`（引擎内部） | 只有数据（不含情景与选项） | 仅作数据指纹（如 `python -m cardflow.planner.engine.sample` 的报告头）；不是运行记录的哈希 |

两种引擎哈希中的 `Decimal` 一律按规范写法（`money.decimal_text`）序列化：`0.006` 与 `0.0060000000` 得到同一哈希（R3E-11）。`plan()` 在任何处理之前取调用方输入的哈希；经协议的运行把 `protocol_input_hash` 显式传入 `plan(input_hash=...)`，一次运行只有一个哈希。

## Fixture 格式与断言

Fixture = `input`（PlanInput）+ `expected`（cases）。每个 case 计算一个输出，再逐条检查断言：

| `kind` | 计算 | 输出 schema | 需要 CP-SAT |
|---|---|---|---|
| `cycles` | 每张卡在交易日的保守账期 | `PlanOutcome.schema.json#/$defs/CardCycles` | 否 |
| `verify` | 独立验证器检查给定的 `allocation`（`decision_scenario`） | `PlanOutcome.schema.json#/$defs/VerificationResult` | 否 |
| `plan` | 完整运行；`profile`、`decision_scenario` 替换 `input.options` 中的同名值 | `PlanOutcome.schema.json` | 是 |

断言：先按 RFC 6901 JSON Pointer 解析 `path`；有 `where` 时该值必须是数组且恰好一个元素（对象）的所列成员与之相等，再在该元素上解析 `then`（默认整个元素）；`equals` 做严格 JSON 相等（布尔不是数字，整数不是浮点）；`length` 比较数组/对象的元素数；`from` 记录期望值来自人工 fixture 的哪个键。期望值中不得出现浮点数。

人工 fixture 的 `expected` 键到 case 的转换规则见 `runner_py/convert_legacy_fixture.py`（`cycles` → cycles；`plan_<卡><元>…` → verify；`<情景>_scenario` → 以该情景为决策情景的 plan，首个基线缺口；`<画像>_optimum` → plan，已证最优且分配恰为所列卡与金额；`<前缀>_sensitivity` → 该情景的敏感性）；无规则的键或成员直接报错。

## 运行命令（在仓库根目录）

```bash
# 运行器：校验并运行全部 *.v1.json（或指定文件/目录）；0 = 全部一致，1 = 不一致，2 = 输入非法
uv run --project services/api python packages/rules-protocol/runner_py/run_fixtures.py
uv run --project services/api python packages/rules-protocol/runner_py/run_fixtures.py \
    packages/rules-protocol/fixtures/regression_2026-10-16_10000.v1.json

# 由人工 fixture 重新生成 v1 fixture；--check 只比较不写入（0 = 逐字节相同）
uv run --project services/api python packages/rules-protocol/runner_py/convert_legacy_fixture.py \
    packages/rules-protocol/fixtures/regression_2026-10-16_10000.json --check

# 协议测试与代码检查
(cd services/api && uv run pytest -q tests/protocol)
uv run --project services/api ruff check packages/rules-protocol
uv run --project services/api ruff format --check packages/rules-protocol
```

## Dart 端（T-022）如何复用

- **同一份 schema 与 fixture**：直接读取 `schema/v1/*.schema.json` 与 `fixtures/*.v1.json`，不复制、不改写。校验时整数按 `is int` 判定（与本运行器的严格整数一致）；JSON Schema 表达不了的规则（见"字段约定"）必须在 Dart 适配层同样实现，可用 `tests/protocol/test_rejections.py` 的用例清单对照。
- **运行哪些 case**：Dart 端没有 CP-SAT，运行 `cycles` 与 `verify` case（账期 + 独立验证器，与服务端同语义），`plan` case 报告为"未运行（需要 CP-SAT）"，不得算作通过或失败；本地有限搜索（T-023）的结果另行校验为可行。
- **相同的断言语义**：JSON Pointer（含 `~0`/`~1` 转义、数组下标不得有前导零）、`where`/`then`、严格相等、`length`。
- **相同的哈希**：按上节规则实现规范化 JSON；Dart `int` 用 `toString()`；`double` 若为整数值且绝对值 < 1e21 写成整数，否则用 `toString()`（Dart 的最短表示与 ECMAScript 只差末尾 `.0`）；键用 `compareTo` 排序（即 UTF-16 代码单元序）；字符串转义按上节逐条实现（遇到孤立代理项报错）。用上表的测试向量和 F-18 哈希 `ea990327…1ee8` 验证。
- **输出**：Dart 产出的 `VerificationResult`/`CardCycles` 必须通过同一 `PlanOutcome.schema.json` 的对应 `$defs`。
- **T-004c（模型 1.1.0）须同步的语义**：见文末修订记录"Dart 端（T-022）同步清单"。

## Fixtures（T-003）

- `fixtures/regression_2026-10-16_10000.json`：§10 回归样本（F-18）golden fixture，由 T-003 从 `poc/engine_reference/fixtures/` 原样复制（字节一致，sha256 `d7e64809b11642a615102596adefcf3d21f538e25dd7c9db99b546e3fe555d6e`，核对记录 `evidence/m0/T-003/fixture.sha256`）；PoC 原件保留作预言机，期望值不得修改。
- 当前使用方：`services/api/tests/engine/`（按测试文件位置定位，不依赖工作目录）与 `python -m cardflow.planner.engine.sample`。金额为十进制字符串，加载时按币种转为整数最小单位；schema 校验与运行器由 T-004 加入。

## Fixtures（T-004）

- `fixtures/regression_2026-10-16_10000.v1.json`：上一文件的协议 v1 形式，由 `runner_py/convert_legacy_fixture.py` 生成（金额转为整数最小单位、利率保持十进制字符串、加载器默认值显式写出、`expected` 逐键转为 case；`source.sha256` 记录来源文件哈希）。不得手工编辑：修改来源后重新生成，`tests/protocol/test_fixture_v1.py` 检查逐字节一致、来源哈希不变，并与"T-003 加载器 → `inputs_to_protocol`"这条独立路径的结果比对。

## v1 修订记录（冻结前；Dart 端 T-022 须同步）

**2026-10-17 · T-004b（引擎/协议健壮性）**，`protocol_version` 仍为 `"1"`（v1 尚未冻结）：

| 文件 | 变化 |
|---|---|
| `common.schema.json` | `MinorAmount`/`NonNegativeMinorAmount`/`PositiveMinorAmount` 上下限由 int64 收紧为 ±10^13；新增 `ResultMinorAmount`/`NonNegativeResultMinorAmount`/`PositiveResultMinorAmount`（int64，输出用）；`DecimalString` 拆为 `Rate`（0–1，≤ 5 位小数）与 `ScaleFactor`（0–10，≤ 10 位小数）；`Date`/`Timestamp` 年份限 1970–2999；新增 `ResultDate`（输出用，不限年份） |
| `CardOption.schema.json` | `fee_rate`、`verified_benefit_rate`、`potential_benefit_rate` 引用 `Rate` |
| `Scenario.schema.json` | `income_scale`、`expense_scale` 引用 `ScaleFactor` |
| `PlanInput.schema.json` | `cards` `maxItems` 200、`cash_accounts` `maxItems` 100、`events` `maxItems` 10000 |
| `PlanOutcome.schema.json` | 所有金额改引 `Result*MinorAmount`，所有日期改引 `ResultDate`；`Rejection.reason` 枚举新增 `REPAY_BEFORE_TXN_DATE` |
| 语义（适配层/引擎） | 见"字段约定"中的不可用判定、验证器违规与 `MODEL_BUILD_ERROR`；`fixtures/regression_2026-10-16_10000.v1.json` 内容不变（逐字节相同） |

**2026-10-18 · T-004c（引擎正确性修正，engine-spec §12，审查 R3E-01…R3E-22）**，`protocol_version` 仍为 `"1"`（v1 尚未冻结），引擎 `model_version` 升为 `1.1.0`。F-18 的输入文档、`protocol_input_hash`（`ea990327…1ee8`）与全部 23 条断言不变；`fixtures/regression_2026-10-16_10000.v1.json` 逐字节不变。

| 文件 | 变化 |
|---|---|
| `common.schema.json` | `Rate`、`ScaleFactor` 只接受规范写法（无多余尾零；`"0.00600"`、`"1.0"`、`"1.00000"`、`"10.0000000000"` 由合法变为非法）；`Date`/`ResultDate` 的 pattern 限定月 01–12、日 01–31；`Timestamp` 的 pattern 限定小时 00–23、分秒 00–59（不接受闰秒）、偏移小时 00–23、大写 `T`/`Z`；`Text`、`MinorAmount` 的说明写明码点计数与"整值浮点不是整数" |
| `PlanOutcome.schema.json` | 新增必填成员 `diagnostics`（`null` 或 `Diagnostics`：`code`=`VERIFIER_REJECTED_SOLVER_SOLUTION`、`rejected_allocation`、`rejected_verification`）；顶层 `allOf` 的 if/then/else：可执行状态必须有非空 `allocation`、非 null `verification`、`diagnostics` 为 null，其他状态 `allocation` 必须为空、`verification` 为 null；`BaselineCheck` 新增必填 `global_breaches`；`Rejection.reason` 新增 `MIN_SPLIT_ABOVE_AMOUNT`、`REPAY_AFTER_HORIZON`、`NOT_COMPARED`；敏感性项的 `status` 改为 `SensitivityStatus`（`SolveStatus` + `NOT_RUN`）；`FirstFeasibleDateShift` 增加第二形态 `{status: MODEL_INVALID|NOT_RUN, detail}`；`VerificationResult` 新增必填 `data_issues`，`verification` 可为 null（有数据问题时 `allocation` 为空）；`solver_status`、`allocation`、`verification` 等说明更新 |
| 其他 schema | 只改说明（不改判定）：`CardOption`（三层额度、一张卡记一笔预授权/预留、同账户同一可用额与池、费用随还款扣现金）、`Pools`（扣除成员卡预授权与预留、只有一层池）、`Snapshot`（反映判定先于情景、`includes_event_ids` 只能列 `as_of` 当天及以前）、`CashEvent`（`at` 的日期等于 `on`、改期丢弃 `at`、计划还款排在最前）、`Scenario`（变换顺序）、`PlanInput`（`horizon_end` 不延长、新的交叉规则）、`Options`（`time_limit_s` 是整次运行的预算、结果与 `workers` 无关）、`BillingRule`（`effective_to` 与推迟日期搜索） |
| 适配层（`protocol.py`） | 新的交叉规则：`includes_event_ids` 的事件日期 ≤ `as_of`；`at` 的日期（按其自身偏移）= `on`；同一 `credit_account_id` 的卡 `raw_available_minor` 相同、`pool_id` 相同。`inputs_to_protocol` 把 Decimal 写成规范文本。`ProtocolError` 消息只含路径与规则，不回显值；严格 JSON 读取的错误只给位置。`verify_from_protocol` 先做数据检查，返回 `data_issues` 而不是抛异常。`outcome_to_protocol` 输出 `diagnostics`、`baseline[].global_breaches` |
| 运行器（`runner_py/run_fixtures.py`） | 注册标准库实现的 `date-time` format 检查（`FORMAT_CHECKER`），schema 与适配层对时间戳的判定一致 |
| 转换器（`runner_py/convert_legacy_fixture.py`） | 利率/系数按规范写法校验 |
| 引擎语义（模型 1.1.0） | 见"字段约定"中的额度三层、检查区间、快照与情景的先后、同日顺序、费用进入现金、可复现、时限、不可用判定、只有可执行状态才有方案、基线包含全局底线、建模异常兜底的范围、错误消息不回显 |

**Dart 端（T-022）同步清单**（本地验证器、适配层与哈希必须与服务端同义；用 `tests/protocol/test_review_wave3_protocol.py`、`tests/engine/test_review_wave3_fixes.py` 的用例对照）：

1. 规范写法：利率/系数只接受规范文本，并在构造文档时由数值生成规范文本（去尾零，零为 `"0"`）；否则同一数值会得到不同的 `input_hash`。
2. 时间戳：按收紧后的 pattern 校验，并做真实日期检查；`at` 的日期（按其自身偏移）必须等于 `on`。
3. 快照：`includes_event_ids` 只能列本账户、日期不晚于 `as_of` 的事件；"已被快照反映"按**原始事件**判定（日期早于 `as_of`，或等于 `as_of` 且被列出），在情景变换之前剔除；情景把事件移到 `as_of` 之前时按 `as_of` 当日计入。
4. 情景变换：先剔除预计事件（`include_expected=false`），再覆盖 `on`/`amount_minor`，再对预计流入延迟与缩放（HALF_UP），再对 `living` 支出缩放；日期因此改变的事件丢弃 `at`。
5. 同日顺序：按时间戳排序的条件只看当日已有事件（计划还款与候选还款日不算）；按时间戳排序时计划还款排在当日最前，相同时刻保持 `events` 数组顺序；否则先支出（含计划还款）后收入。
6. 计划还款额 = 分配金额 + 该卡费用（费率部分向上取整 + 固定费，金额 > 0 时）；还款日早于快照日时按快照日计入并记违规。
7. 检查区间：时间线到 `horizon_end` 为止，不延长；还款日晚于 `horizon_end` 的卡违规 `ineligible (REPAY_AFTER_HORIZON)`。
8. 额度三层：卡层、信用账户层（同 `credit_account_id` 的卡，账户可用额减所有卡的预授权与预留，截零）、池层（池可用额减成员卡的预授权与预留，截零）；结构检查对两个共享层分别校验合计；排除原因的顺序与 `NO_CAPACITY`、`MIN_SPLIT_ABOVE_AMOUNT` 的判定同服务端。
9. 全局底线：检查点为每个快照日与任一账户有最低点的每一天，各账户取当日最低点或此前最后一天的期末余额（首个事件日之前取快照余额）；基线与验证器同一规则。
10. 验证前先做数据检查：缺快照、快照过期或晚于交易日、规则不可用（含需要日历）、池无条目 → 返回 `data_issues`，不验证、不抛异常。
11. 结果文档：非可执行状态的 `allocation` 为空、`verification` 为 null，`diagnostics` 中的被拒分配不得展示或采纳；按新的 `Rejection.reason`、`SensitivityStatus`、`FirstFeasibleDateShift` 两种形态解析。
12. 文本长度按码点（`runes.length`）；整值浮点（`1000000.0`）不是整数。

## Dart 端实现与 parity（I-0c，2026-10-18）

本节补充上文"Dart 端（T-022）如何复用"：Dart 端已实现，位于 `apps/mobile/packages/cardflow_domain`（纯 Dart 包，
不依赖 Flutter、drift；App 以 path 依赖引入）。上文状态行里"Dart 运行器由 T-022 实现（待环境）"已由本节取代。

**模块对应**（语义与引擎 1.1.0 一一对应，以 engine-spec §12/§12.1 为准）：

| Python（`cardflow/planner/engine/`） | Dart（`lib/src/`） |
|---|---|
| `money.py`（`MINOR_DIGITS`、`to_minor`/`from_minor`、`apply_rate`、`decimal_text`） | `money.dart`、`rational.dart`（BigInt 分数与四种取整；`UP` 与 money.py 一样是 `ROUND_CEILING`） |
| `billing.py` | `billing.dart`（规则错误消息与 `str(e)` 逐字相同） |
| `cash.py` | `cash.dart`（假设说明与 cash.py 的 f-string 逐字相同，测试读取 Python 源码比对） |
| `allocation.py` 中与验证相关的部分（`CardOption`、三层容量、`classify`、`_low_series`、目标层定义） | `allocation.dart` |
| `verifier.py` | `verifier.dart`（加权缓冲按 `Decimal` 的写法，包括 `-0.0`） |
| `plan.py` 的 `data_issues`、`baseline_check` | `checks.dart` |
| `protocol.py`（严格 JSON、规范化 JSON、`protocol_input_hash`、`inputs_from_protocol`/`inputs_to_protocol`、`verify_from_protocol`、`card_cycles_to_protocol`） | `protocol/*.dart` |
| `runner_py/run_fixtures.py` | `fixtures/*.dart`、`bin/run_fixtures.dart` |
| —（服务端用 CP-SAT） | `search.dart`：本地有限搜索（K ≤ 3，验证器为可行性预言机，`proven: false`） |

**运行器**（在 `apps/mobile/packages/cardflow_domain` 下）：

```bash
dart pub get --enforce-lockfile
dart run cardflow_domain:run_fixtures                       # 默认：仓库 packages/rules-protocol/fixtures/*.v1.json
dart run cardflow_domain:run_fixtures --dump DIR FIXTURE_OR_DIRECTORY ...
```

每个 fixture：严格 JSON（拒绝重复键、NaN、BOM、溢出的数字）→ 严格的 Fixture 外壳（封闭对象、必填成员、
CaseName/JsonPointer/Where 的 pattern、equals 与 length 二选一）→ 除 `input.options.time_limit_s` 外不得有浮点数 →
协议适配层（PlanInput 的全部规则，含"字段约定"中 JSON Schema 表达不了的交叉规则）→ cycles 与 verify case
逐条断言（JSON Pointer、where/then、严格相等、length，与 Python 同语义）；plan case 输出
`NOT RUN (needs CP-SAT; not counted as pass or fail)`。退出码与 Python 运行器相同：0 全部一致，1 有断言不成立，
2 输入非法（2 优先）。Dart 端不带通用 JSON Schema 校验库（不在 architecture §11 版本表内），schema 层的校验由
下述 parity job 用 Python 完成。

**`--dump DIR`（两端相同）**：每个 cycles/verify case 的输出写成规范化 JSON 加一个换行，路径
`DIR/<fixture 文件名去掉 .v1.json>/<两位序号>-<case 名>.<kind>.json`（序号 = case 在 `expected` 中的位置）。
Python：`uv run --project services/api python packages/rules-protocol/runner_py/run_fixtures.py --dump DIR`
（只是加了这个选项，原有行为与测试不变）。plan case 不导出：它的输出含 run_id、created_at 与求解耗时，
Dart 端也没有求解器。

**parity job**（`.github/workflows/mobile.yml` 的 `protocol-parity`）：`uv sync --locked`（services/api）→
Python 与 Dart 运行器分别 `--dump` 全部 golden fixture → `diff -r` 必须为空 → 用
`tool/gen_parity_fixtures.dart` 生成 300 份带固定种子的随机 fixture（移植自 `tests/engine/diff_reference.py` 的
`gen_doc`：共享信用账户、池内预授权与预留、快照包含关系、带偏移的时间戳与改期、晚于 horizon 的还款、
近乎相同的卡；每份 1 个 cycles + 3 个随机分配的 verify，断言只检查输出形状）→ 两端 `--dump` → `diff -r` 必须为空
→ Python jsonschema（运行器的 `StrictValidator` 与 `FORMAT_CHECKER`）校验每个 Dart 输出符合
`PlanOutcome.schema.json#/$defs/CardCycles` 或 `#/$defs/VerificationResult`。任一步失败即红。
本机另以 6 个种子 × 1000 份随机文档（24,000 个输出）核对，逐字节一致。

**哈希**：Dart 端按上文规则实现规范化 JSON；整数（含超出 64 位的整数记号，读成 `BigInt`）写成精确十进制；
非整数记号读成 binary64 的精确整数表示（就近舍入、恰在一半取偶，与 Python `float()` 相同）并按 ECMAScript
`Number::toString` 写出（最短往返，位数最少者中取最接近、再取偶），全程不用 `double`。F-18 的
`protocol_input_hash` 为 `ea990327…1ee8`；README 的测试向量与 Python 引擎生成的 161 个浮点向量全部一致
（`test/canonical_json_test.dart`）。

**未覆盖项**（Dart 端有意不做或留给后续任务）：

- plan case 与 `plan()` 的其余部分：CP-SAT 分层求解、敏感性、`DOMINATED`/`NOT_COMPARED` 等需要求解器的拒绝原因、
  运行记录、`outcome_to_protocol`。本地的替代是有限搜索（`boundedSearch`），它不声称最优，找不到时只说
  "本地未找到（非证明无解）"。
- money.py 中与本任务无关的分期与 IRR 函数（`split_installments`、`installment_cash_flows`、`irr_monthly`、
  `annualize`）：随分期功能（I-1 起）再移植。
- 通用 JSON Schema 校验：Dart 端只有适配层与 Fixture 外壳的严格检查，schema 层由 parity job 的 Python 完成。
- Python 运行器用 jsonschema 的 `pattern`（`re.search`，`$` 也匹配末尾换行之前）检查 Fixture 外壳中的
  CaseName、JsonPointer 等；Dart 的外壳读取器按整串匹配。只在名称以换行结尾这种不现实的输入上两端结论不同
  （Dart 判非法），不影响任何引擎输出。

