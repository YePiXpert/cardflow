# 简报 I-1c · 交易、账单版本、分期、还款登记与核对（UF-3）+ I-1 阶段交付 IPA

派发：I-1b 验收后。对应 `ios-first-plan.md` §3 的 I-1 第二段（手工交易、账单版本、分期；还款登记与状态）。本任务结束时**触发一次 iOS 构建**出第三个未签名 IPA。若需重新派发，在开头加一句"先核对磁盘与 git 现状，不要重复创建"。

## 环境与规则
与 `briefs/I1-a.md` 相同，另加 §6 第 9、10 条。范围：`apps/mobile/`（含领域包的**一个新模块**，见 §6 第 1 条）、`.github/workflows/mobile.yml`（只做 §6 第 7、8 条）、`evidence/i1/I1-c/`、根 README。**不改**领域包其他文件、协议包、services/api、docs。iOS 构建本任务最多触发 2 次。

必读：PRD §4.2（R-STMT-01~11）、§6.2、§6.3、UF-3；ui-spec P-05、P-06、P-03（本期区、负债四分法、全部账单）、P-01（近期到期、待办）、UF-3、§4.5；data-model §3/§4（transactions、statements、statement_versions、installment_plans、installment_schedule、repayments、repayment_allocations、reconciliation_items）；bank-rules-spec §3/§5；engine-spec 中还款、费用取整、额度释放的语义；领域包 `billing.dart`（`resolveCycle`、`IssuedStatement`、`cyclesForTransaction`）、`money.dart`（`applyRate`、`RoundingMode`、`Rational`）；Python `services/api/cardflow/planner/engine/money.py` 的 `split_installments`、`installment_cash_flows`、`irr_monthly`、`annualize`（分期语义的唯一依据，只读不改）；`apps/mobile/README.md` 的"加密本地库"（加表与迁移步骤）、"仓库与 provider"、"现金与资金日历"（末尾"给 I-1c 的接口"）、"I-1a 的偏离与约定"、"I-1b 的偏离与约定"、"数据层 → 领域对象映射"两节；`docs/80-delivery/backlog.md` 的 BL-14、BL-16、BL-18、BL-21。

## 1. 本地库 v4
- `currentSchemaVersion` → 4；3→4 只 expand；新建 vs 升级一致。
- 表：
  - `transactions`(id, workspace_id, currency_account_id, card_id, txn_type `purchase`/`refund`/`repayment`/`transfer`/`fee`/`interest`/`installment_principal`/`installment_fee`/`adjustment`, amount_minor 负债增加为正, currency, txn_at, txn_tz, time_precision, posted_on, merchant, category, status `pending`/`posted`/`reversed`, parent_transaction_id, fingerprint, source_kind `manual`/`import`, confirmation_level, recorded_at, updated_at, deleted_at)。
  - `statements`(id, workspace_id, currency_account_id, statement_date, due_date, status PRD §6.2, current_version_id)；`statement_versions`(id, workspace_id, statement_id, version_no, source_kind `manual`/`import`/`correction`, previous_balance_minor, new_balance_minor, min_due_minor, payments_minor, credits_minor, fees_minor, interest_minor, installment_due_minor, credit_balance_minor, due_date, recorded_by, reason, recorded_at)。**追加只读**：SQLite 触发器禁止 UPDATE 金额列（`RAISE(ABORT)`），测试直接 UPDATE 必须失败；人工修正 = 新版本且理由必填。
  - `installment_plans`(id, workspace_id, transaction_id, principal_minor, periods, per_period_rate 十进制文本, fee_mode `per_period`/`upfront`, remainder_policy `last`/`first`, rounding `HALF_UP`, status, early_settled_at)；`installment_schedule`(plan_id, period_no, principal_minor, fee_minor, statement_date, due_date, status)。
  - `repayments`(id, workspace_id, currency_account_id, cash_account_id, amount_minor, currency, status PRD §6.3, method, payment_initiated_at, expected_debit_on, cash_debited_at, credit_posted_at, bank_confirmed_at, evidence_note, created_at, updated_at)；`repayment_allocations`(repayment_id, statement_id, amount_minor)：Σ ≤ 还款额由仓库层保证，UI 要求 =（F-33）。
  - `reconciliation_items`(id, workspace_id, kind `amount_mismatch`/`duplicate_repayment`/`refund_pending`/`unmatched_repayment`, refs JSON, status `open`/`resolved`/`dismissed`, resolution, resolved_at)。
- 分期计算（F-36/F-37）：本金按期拆分守恒，尾差按策略；每期费用 = `applyRate(本金, 费率, HALF_UP)`；成本两种并列：名义 = 月费率×12；实际年化 = 现金流 IRR，用有理数二分，**不得用 double**。领域包目前没有分期函数（主会话已核实），按 §6 第 1 条在领域包新增模块，不必停下汇报。
- 账期归属：交易入账日 → 领域包 `resolveCycle`（已出账单优先，否则预测账期）；入账日为空且有入账延迟区间 → `cyclesForTransaction` 多账期，UI 显示"可能账期"（F-15）。
- 负债四分法（R-STMT-02、F-30）：总负债 = 已出账未还 + 未出账 + 未来分期本金（不含未计提费用）；本期应还；未出账；未来分期本金。四项分列不重复相加，测试一笔 12 期分期的归属。
- 还款（UF-3）：状态机 §6.3 全部转移在仓库层实现，非法转移拒绝；双侧时间（F-31）：现金时间线按 `expected_debit_on`/`cash_debited_at` 的日期生成/确认 planned 现金事件（I-1b 接口 `linked_repayment_id`），负债按 `credit_posted_at` 的日期核销；额度释放（F-28）：容量计算把还款视为"银行入账后 + 释放时滞（账户规则，未知 → 保守不释放）"才释放，未入账前不释放；结清/部分结清只由 `bank_confirmed` 触发；「我已还款」→ `user_marked_paid` 不结清；到期后无证据 → `needs_review`（提醒降级在 I-4，这里只改状态与文案）。
- 疑似重复（F-32）：同日、同账户、同金额的两笔还款（一笔 `method=auto_debit`、一笔手工）→ 生成 `duplicate_repayment` 差异项，负债只核销一次，直到用户处理。
- 退款（F-34）：`refund` 交易在规则未知时生成 `refund_pending` 差异项，账单应还不变，不计入收入统计。
- 贷方余额（F-38）：`credit_balance_minor` 可为正，账单显示"贷方余额"，本期应还 0。
- F-24 复测：换卡后旧卡交易仍归属同一币种子账户，还款分配不变。
- F-06：分期计划在 180 天窗口外的到期期次进入 I-1b 日历的尾部责任区。

## 2. 页面
- **P-05 账单中心**：列表（筛选 账户/状态/币种/月；行含应还、到期、状态、确认层级、版本数、差异数）；详情（版本切换；要素 R-STMT-01 全项带来源与版本，来源未含的项显示"来源未含此项"而不是 0；负债四分法；交易列表含退款待核对；分期区每期本金/费用、尾差、名义与实际年化并列；还款分配；差异清单）。动作：「登记还款」「人工修正」（新版本、理由必填、原值可查）「录入正式账单」（手工录入要素作为 v1）「记一笔」（账户、类型、金额、交易时间与精度、入账日可空、商户、分类；G1~G3）。
- **P-06 还款登记与核对**：表单（账单、金额、现金账户、方式、发起时间、预计扣款日、证据备注）；时间线（已登记 › 处理中 › 现金已扣 › 银行已入账 › 银行确认；失败；用户已标记）；多期分配实时合计（≠ 还款额禁止保存）；核对区（疑似重复、金额不符、未匹配）。校验：超应还提示溢缴或分到他期；受限账户警告；扣款/入账时间 ≥ 发起时间。文案："已登记（待银行确认）"；禁止"还款成功"。
- **P-03**：补齐本期区（账期、应还、最低还款、还款状态）、负债四分法、最近 3 期与「全部账单」、「去还款」「登记还款」。
- **P-01**：「近期到期」列表（P-05 入口）、待办（待核对的还款、差异项）、快捷新增（登记还款、记一笔）。
- 演示空间：加交易、一期已出账单（两个版本体现修正留痕）、一笔 12 期分期、一笔已登记未确认的还款、一个疑似重复差异项。
- 可访问性 3.0x 检查加入新页面。

## 3. 测试
- 迁移一致；金额列 UPDATE 触发器；版本追加。
- F-06、F-21（两卡导入同一账单 → 一份：手工录入时同账户两卡只产生一个 statement）、F-24 复测、F-28、F-30、F-31、F-32、F-33、F-34、F-36、F-37、F-38；还款状态机全转移；"可能账期"；负债四分法；差异项生命周期。
- 组件：P-05/P-06 四态；分配合计校验；禁止文案（"还款成功"、绿色勾）不出现。
- 工作空间隔离扩展到新表；analyze/format/build web。

## 4. 阶段交付
- 更新 `apps/mobile/README.md`（v4 表、还款状态机、分期算法与取整、差异项）与根 README 状态"I-1 已交付（待真机）"。
- 推送后等 dart 与 protocol-parity job 绿 → `gh workflow run mobile.yml --ref main` 触发 ios-unsigned → `gh run download` → 检查 IPA（Bundle ID、MinimumOSVersion、Frameworks 数量）→ 记录 artifact URL、大小、sha256。
- 真机走通清单（写进汇报，供用户按步执行）：UF-1（建卡 → 账期 → 额度 → 现金账户 → 总览预测账期）、UF-3（登记还款 → 确认扣款 → 入账 → 确认 → 结清）、UF-5（日历 → 缺口 → 情景 → 重算 → 对比），以及诊断页复制。

## 6. 带入项与主会话裁决（派发前补齐，2026-10-19）

1. **分期拆分与成本进领域包**（主会话裁决，替代 §1 的"停下汇报"）：在 `apps/mobile/packages/cardflow_domain/lib/src/installment.dart` 新增模块并从包入口导出，语义**逐条对齐** Python `money.py`：`splitInstallments(principalMinor, periods, remainderTo)` = 每期 `HALF_UP(本金/期数)`、尾差加到末期（`last`）或首期（`first`），`periods ≤ 0` 抛错，Σ 守恒；`installmentCashFlows(...)` = 每期 `(期号, 本金, 费用)`，费用 = `applyRate(本金总额, 每期费率, rounding)`（建行口径：按分期本金总额计，每期相同）；`irrMonthly(flows, tol)` = 对 `[(月序, 金额)]` 用 `Rational` 在 `[0, 1]` 上二分（`npv(0) < 0` 抛"无正 IRR"；至多 200 次，`hi − lo < tol` 停，返回 `(lo + hi)/2`），`tol` 默认 10^-12。**注意** Python `irr_monthly` 的 docstring 写"月 0 放款为正、还款为负"，但代码要求 `npv(0) ≥ 0`，即实际约定是**月 0 放款为负、1..n 各期还款为正**（主会话实测：按 docstring 的符号传入会抛 `no positive IRR`）；Dart 以代码行为为准，注释写明这一点，调用方与对照样本都用这个符号。`annualize(monthlyRate)` 返回名义 `×12` 与复利 `(1+r)^12 − 1` 两个 `Rational`。显示时用现有 `decimalText(Rational)` 转十进制文本，百分数保留 4 位小数即可。**只用 `int`/`BigInt`/`Rational`**，`no_double_test` 必须继续通过；包内 `dart format`/`analyze --fatal-infos`/`test` 照旧（CI dart job 会跑领域包测试）。测试：移植 Python `tests/engine/test_properties.py::test_installment_split_conserves_principal`（随机本金/期数守恒与尾差位置）；F-36（12 期拆分、尾差末期）；F-37（月费率 1.5%：名义 18%、复利年化与 IRR 并列，且 IRR 不等于名义值）；**Python 对照**：在本机用 `uv run --project services/api python -c ...` 调用上述 4 个 Python 函数算至少 6 组样本（含 F-36/F-37、`remainder_to="first"`、3 组随机），把输出写进 Dart 测试的期望值（月 IRR 相差 < 10^-9、拆分与费用逐期相等、名义与复利相等到 10 位小数），命令与原文 tee 到 `evidence/i1/I1-c/installment-parity.txt`。不改 CI 的 parity job，不改 Python。`apps/mobile/README.md` 的"领域层"一节补这个模块。
2. **`linked_repayment_id` 的约束**（I-1b 遗留）：v4 建 `repayments` 后用触发器补：`cash_events` 在 INSERT 与 UPDATE OF `linked_repayment_id` 时，非空值必须指向同一 `workspace_id` 的 `repayments` 行；`repayments` 行删除前若仍有未删除的现金事件指向它则 `RAISE(ABORT)`。新建库的冻结 `SchemaV4` 与 3→4 迁移都用同一组触发器（不重建 `cash_events` 表），"新建 vs 升级结构一致"测试照旧。
3. **I-1b 的接口说明**（原文，来自其汇报与 `apps/mobile/README.md`"给 I-1c 的接口"）：
   - 还款 → 现金：`CashEventRepository.planRepaymentDebit(repaymentId, cashAccountId, on, amountMinor, at?, label?)` 生成（或改期改额）一条层级 `planned`、类别 `repayment`、尚未发生、`linked_repayment_id = repaymentId` 的事件（每笔还款至多一条未删除的）；`confirmRepaymentDebit(repaymentId, debitedAt, amountMinor?)` 在确认扣款时把它变为确定、已发生，日期与时刻改为实际扣款时点（F-31：现金时间线按扣款日生效）；`cancelRepaymentDebit` 作废尚未发生的；`byRepayment` 查询。带 `linked_repayment_id`/`linked_plan_run_id` 的事件 P-08 不可改，仓库拒绝并说明。
   - 尾部责任：`CashForecast.tail` 是 `TailObligation`（日期、金额、币种、账户名、标签、`source`、`refId`）的列表，I-1c 把分期计划的未来各期（`source: 'installment'`）加进同一列表即可在 P-07 显示（F-06）。
   - 测试工厂（`test/data/repositories/repository_test_support.dart`）：`createTestCashAccount`、`addTestCashEvent`、`recordTestCashSnapshot`（当天事件默认答"未包含"）、`StaleAwareClock`（时刻固定、判断陈旧）；组件测试 `readCashPlan(tester)`、`withCurrentScope(tester, action)`、`pumpCardFlowApp(realClock: …)`。
   - 现金的日期与"今天"按 Asia/Shanghai（`cashTimeZone`）；信用账户按各自 `business_tz`。还款的 `expected_debit_on`/`cash_debited_at` 走现金时区，`credit_posted_at` 的入账日走信用账户业务时区（`postingDateOf`）。
4. **新表登记**：每张新表都要进 `lib/data/repositories/workspace_repository.dart` 的 `workspaceDataTables`（隔离测试会对照 `sqlite_master` 断言全覆盖，清除演示数据按它删除）；没有 `id` 列的表（`installment_schedule`、`repayment_allocations`）要在 `test/data/repositories/workspace_isolation_test.dart` 的 `_rowKeys` 登记行键表达式；演示数据必须给**每张新表**至少写一行，否则双向隔离测试对该表是空测。
5. **BL-21**：P-04 新建规则不再预填"10 日 / 当月 28 日"，账单日与到期日必须用户填写，示例只作 placeholder；保存时的校验不变。
6. **BL-18**：`test/ios/ios_config_test.dart` 遍历 `ios/` 时排除 `*.local.xcconfig`（本地签名配置），加一个带该文件的临时目录用例。
7. **BL-14（CI 供应链）**：`mobile.yml` 的 4 个第三方 action（`actions/checkout`、`subosito/flutter-action`、`astral-sh/setup-uv`、`actions/upload-artifact`）固定到 40 位提交 SHA，行尾注释版本号；SHA 用 `gh api repos/<owner>/<repo>/git/ref/tags/<tag>` 取，带注释的 tag 再解引用到 commit，查询原文 tee 到 `evidence/i1/I1-c/ci-pins.txt`。protocol-parity job 的 golden 与 schema 校验步骤改为断言产出文件数等于期望数（期望数在 workflow 里写死并注明来源）。改完的 workflow 必须在推送后 dart、protocol-parity 绿，再触发 ios-unsigned。
8. **BL-16（Required Reason API）**：ios-unsigned job 在构建后加一步，用 `nm -u`/`strings` 扫 `Runner.app` 主二进制与 `Frameworks/` 下每个 framework 的二进制，查四类 API 的符号（UserDefaults：`NSUserDefaults`；FileTimestamp：`stat`/`fstat`/`lstat`/`getattrlist`/`fgetattrlist`/`getattrlistbulk`/`NSFileCreationDate`/`NSFileModificationDate`/`NSURLContentModificationDateKey`/`NSURLCreationDateKey`；SystemBootTime：`systemUptime`/`mach_absolute_time`/`sysctl` 与 `kern.boottime`；DiskSpace：`statfs`/`statvfs`/`fstatfs`/`fstatvfs`/`NSFileSystemFreeSize`/`NSFileSystemSize`/`volumeAvailableCapacityKey`/`volumeAvailableCapacityForImportantUsageKey`/`volumeAvailableCapacityForOpportunisticUsageKey`/`volumeTotalCapacityKey`），逐个二进制列出命中并上传为 artifact `required-reason-scan`，同时查每个 framework 是否自带 `PrivacyInfo.xcprivacy`。结论写进 `evidence/i1/I1-c/required-reason-scan.txt`：主二进制或**没有自带清单**的 framework 命中的类别保留在 `ios/Runner/PrivacyInfo.xcprivacy`，其余类别删除（理由码不变）。若 PrivacyInfo 有改动，再触发第二次构建，交付的是第二个 IPA；没有改动则第一个即交付。
9. **证据规则**（审查 R-10/R-11）：证据必须是工具原文（tee），不得省略成 `<关键行>`/`...`；过滤宿主发行版、内核、代理状态行（`grep -Ev`）并在文件头注明过滤了什么。
10. **一次一个代理**：本任务不得派子代理（I-1b 曾派只读审查子代理，违反约定）；不自行做审查，审查由主会话在阶段末安排。建议提交顺序：v4 表与迁移 → 领域包分期模块与对照 → 交易/账单/分期仓库 → 还款与现金联动、差异项 → 页面 → 演示数据 → BL-18/BL-21 → CI（第 7、8 条）→ 触发 iOS 构建。每一步都单独提交推送，CI 绿再做下一步；被用量上限打断时主会话会续跑。

## 验收（evidence/i1/I1-c/）
analyze.txt、format.txt、test.txt、schema-diff.txt、append-only.txt（触发器测试输出）、installment-parity.txt、ci-pins.txt、required-reason-scan.txt、build-web.txt、ci-dart-run.txt、ci-ios-run.txt、ipa-inspect.txt、git-log.txt。

## 回复格式
1. 完成项与路径；2. 验收结果（含 Required Reason 扫描结论与 PrivacyInfo 是否改动、CI 固定清单）；3. artifact 地址与用户真机走通清单；4. 偏离/疑问；5. 给 I-2 的接口说明：如何从本地数据组装 `ModelInputs`/协议文档（卡、额度三层、现金、情景、已出账单）、预留（plan_reservations）将挂到哪里、测试工厂。
