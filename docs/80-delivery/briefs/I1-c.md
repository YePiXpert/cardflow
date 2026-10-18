# 简报 I-1c · 交易、账单版本、分期、还款登记与核对（UF-3）+ I-1 阶段交付 IPA

派发：I-1b 验收后。对应 `ios-first-plan.md` §3 的 I-1 第二段（手工交易、账单版本、分期；还款登记与状态）。本任务结束时**触发一次 iOS 构建**出第三个未签名 IPA。若需重新派发，在开头加一句"先核对磁盘与 git 现状，不要重复创建"。

## 环境与规则
与 `briefs/I1-a.md` 相同。范围：`apps/mobile/`、`evidence/i1/I1-c/`、根 README。**不改**领域包（分期计划与成本计算若需要进领域包——见 §1——先停下汇报，由主会话决定放领域包还是 App 层）、协议包、services/api、docs。iOS 构建本任务最多触发 2 次。

必读：PRD §4.2（R-STMT-01~11）、§6.2、§6.3、UF-3；ui-spec P-05、P-06、P-03（本期区、负债四分法、全部账单）、P-01（近期到期、待办）、UF-3、§4.5；data-model §3/§4（transactions、statements、statement_versions、installment_plans、installment_schedule、repayments、repayment_allocations、reconciliation_items）；bank-rules-spec §3/§5；engine-spec 中还款、费用取整、额度释放的语义；领域包 `billing.dart`（`resolveCycle`、`IssuedStatement`、`cyclesForTransaction`）、`money.dart`（`applyRate`、`RoundingMode`）；I-1a/I-1b 汇报的接口说明。

## 1. 本地库 v4
- `currentSchemaVersion` → 4；3→4 只 expand；新建 vs 升级一致。
- 表：
  - `transactions`(id, workspace_id, currency_account_id, card_id, txn_type `purchase`/`refund`/`repayment`/`transfer`/`fee`/`interest`/`installment_principal`/`installment_fee`/`adjustment`, amount_minor 负债增加为正, currency, txn_at, txn_tz, time_precision, posted_on, merchant, category, status `pending`/`posted`/`reversed`, parent_transaction_id, fingerprint, source_kind `manual`/`import`, confirmation_level, recorded_at, updated_at, deleted_at)。
  - `statements`(id, workspace_id, currency_account_id, statement_date, due_date, status PRD §6.2, current_version_id)；`statement_versions`(id, workspace_id, statement_id, version_no, source_kind `manual`/`import`/`correction`, previous_balance_minor, new_balance_minor, min_due_minor, payments_minor, credits_minor, fees_minor, interest_minor, installment_due_minor, credit_balance_minor, due_date, recorded_by, reason, recorded_at)。**追加只读**：SQLite 触发器禁止 UPDATE 金额列（`RAISE(ABORT)`），测试直接 UPDATE 必须失败；人工修正 = 新版本且理由必填。
  - `installment_plans`(id, workspace_id, transaction_id, principal_minor, periods, per_period_rate 十进制文本, fee_mode `per_period`/`upfront`, remainder_policy `last`/`first`, rounding `HALF_UP`, status, early_settled_at)；`installment_schedule`(plan_id, period_no, principal_minor, fee_minor, statement_date, due_date, status)。
  - `repayments`(id, workspace_id, currency_account_id, cash_account_id, amount_minor, currency, status PRD §6.3, method, payment_initiated_at, expected_debit_on, cash_debited_at, credit_posted_at, bank_confirmed_at, evidence_note, created_at, updated_at)；`repayment_allocations`(repayment_id, statement_id, amount_minor)：Σ ≤ 还款额由仓库层保证，UI 要求 =（F-33）。
  - `reconciliation_items`(id, workspace_id, kind `amount_mismatch`/`duplicate_repayment`/`refund_pending`/`unmatched_repayment`, refs JSON, status `open`/`resolved`/`dismissed`, resolution, resolved_at)。
- 分期计算（F-36/F-37）：本金按期拆分守恒，尾差按策略；每期费用 = `applyRate(本金, 费率, HALF_UP)`；成本两种并列：名义 = 月费率×12；实际年化 = 现金流 IRR，用有理数二分到 1e-6，**不得用 double**。先检查领域包是否已有分期函数：没有则停下汇报（建议放领域包并补 Python 对照测试；主会话裁决后再继续）。
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

## 验收（evidence/i1/I1-c/）
analyze.txt、format.txt、test.txt、schema-diff.txt、append-only.txt（触发器测试输出）、build-web.txt、ci-dart-run.txt、ci-ios-run.txt、ipa-inspect.txt、git-log.txt。

## 回复格式
1. 完成项与路径；2. 验收结果；3. artifact 地址与用户真机走通清单；4. 偏离/疑问；5. 给 I-2 的接口说明：如何从本地数据组装 `ModelInputs`/协议文档（卡、额度三层、现金、情景、已出账单）、预留（plan_reservations）将挂到哪里、测试工厂。
