# 30 · 银行规则规格：账期、费用、额度、分期、退款

目的：把"银行怎么算"变成可版本化、可核验、可测试的规则对象，供账单预测、现金流和智能用卡引擎共用。本文定义**语义与字段**；具体银行数值只在 `sources.md` 已核验范围内给出，其余标注"待核验"。可执行语义见 `poc/engine_reference/cardflow_ref/billing.py`、`money.py`。

## 1. 时间点七分法（R-RULE-01）

| 时间点 | 字段 | 含义 | 谁决定 |
|---|---|---|---|
| 交易日 | `txn_time` | 消费发生 | 商户/卡组织 |
| 银行记账日 | `posted_on` | 入账到信用账户 | 银行（延迟 0–3+ 天，境外更长） |
| 账单日 | `statement_date` | 账单生成 | 账户规则 |
| 到期还款日 | `due_date` | 最后还款日 | 账户规则或已出账单 |
| 建议发起还款日 | `planned_repay_on` | `due_date − payment_lead_days` | 用户设置（测试样本 0） |
| 现金实际扣款日 | `cash_debited_at` | 现金账户减少 | 支付渠道 |
| 银行确认还款日 | `credit_posted_at` | 负债核销/额度释放起点 | 银行 |

规则："距离还款日的天数"（`due_date − txn_date`）与"确认可享免息的天数"分开；后者只在交易类型享受免息、且账单全额按时还清时成立（S15："当期分期应还本金可享受免息还款期待遇"仅在全额还清当期时）。

## 2. 规则对象模型（R-RULE-02）

每条规则记录：`subject_scope`（银行/卡产品/信用账户/币种子账户）、`source`（S-nn 或用户声明）、`published_on`（如有）、`effective_from`/`effective_to`、`verified_on`、`version`、`review_status`（draft/verified/user_declared/expired）、`exceptions`（文本）。同一主体同一时点只能有一个生效版本；已出正式账单优先于任何预测（`resolve_cycle`）。

| 规则类型 | 关键字段 | 默认 | 说明 |
|---|---|---|---|
| BillingCycleRule | `statement_day`(1–31，月末截断)、`statement_day_inclusive`、`due.kind`(fixed_day/days_after_statement)、`due.day`、`due.month_offset`(0 当月/1 次月)、`due.days`、`due.day_kind`(calendar/business)、`holiday_rollover`(none/next_business_day)、`cutoff_time`+`tz` | inclusive=true；rollover=none | 账单日当天入账是否计入本期为银行差异项，必须核验 |
| PostingDelayRule | `delay_min_days`、`delay_max_days`、按渠道/境内外区分 | 0/0 | 入账窗口不确定→多个可能账期，保守取最早到期 |
| GraceRule | `interest_free_txn_types[]`、`requires_full_payment`、`max_days`、`min_days` | 未知→不免息 | "未知不得默认零成本" |
| InterestRule | `daily_rate`(Decimal)、`basis`(full_balance/unpaid_part)、`accrual_start`(txn/posted)、`compounding`(monthly/none) | 待核验 | 招行 S03 正文未取得，状态=待核验 |
| MinPaymentRule | `ratio`、`floor_amount`、`includes_installment_full`(S15：分期应还全额计入最低) | 待核验 | |
| LateFeeRule | `ratio_of_unpaid_min`、`floor`、`cap` | 待核验 | 违约金 |
| FeeRule | 年费 `annual_fee`、取现费、外币兑换费 `fx_fee_ratio`、分期费率 | 按产品 | |
| InstallmentRule | `principal_occupies_limit`(true)、`release_per_period`(true)、`per_period_rounding`(HALF_UP)、`remainder_to`(last/first)、`interest_basis`(total_principal×per_period_rate)、`early_settlement`(remaining_principal + posted_periods_interest)、`refund_adjust_after_merchant_refund`(true)、`statement_shows_total_price`(true) | 建行 S15 实例 | 其他银行可不同 |
| RefundRule | `offsets_current_due`(yes/no/unknown)、`limit_release`(on_post/on_confirm/unknown)、`reward_clawback`(yes/no/unknown) | unknown | 默认待核对 |
| PreauthRule | `hold_days`、`counted_in_available`(bank_shows_net) | 待核验 | 不重复扣减 |
| LimitRule | `temp_limit_expiry_policy`、`special_limit_purpose`、`release_lag_days_after_posting`、`pool_id` | release 未知→不释放 | |
| RepaymentOrderRule | 冲抵顺序（费用/利息/本金；分期/循环） | 待核验 | 影响部分还款分配 |
| HolidayCalendar | 年份、节假日/调休 | 无 | 仅已核验规则使用 |

## 3. 账期计算语义（R-RULE-03~06）

1. **账单归属**：入账日 `p`；本月账单日 `S = clamp(year, month, statement_day)`；`p < S` 或（`p == S` 且 inclusive）→ 本月；否则下月。
2. **到期**：fixed_day → `clamp(month(S)+offset, day)`，若不晚于 S → 规则非法（MODEL_INVALID）；days_after_statement → 自然日或工作日（需日历）。
3. **月末截断**：31 → 30/28/29；闰年 2 月 29。
4. **跨年**：月份加法进位；测试 F-13。
5. **规则版本**：按入账日选择生效版本；已出账单优先。规则变更不改写已出账单（F-14）。
6. **入账不确定**：`cycles_for_transaction` 产出去重后的可能账期集合；UI 显示"可能的账期/还款日范围"；保守情景按最早到期校验（F-15）。
7. **顺延**：只有 `holiday_rollover=next_business_day` 且有已核验日历时执行；否则不顺延。

示例（回归样本）：A 账单 10 日、当月 28 日到期；交易 2026-10-16 当天入账 → 16 > 10 → 账单 2026-11-10，到期 2026-11-28。B 账单 20 日、次月 8 日：16 ≤ 20 → 账单 2026-10-20，到期 2026-11-08。C 账单 5 日、当月 25 日：账单 2026-11-05，到期 2026-11-25。

## 4. 免息与计息（R-RULE-07）

- 免息资格按**账户 + 交易类型**判断：消费类可免息；取现、转账、循环余额、最低还款后的剩余、分期手续费通常不免息（具体按规则版本）。未核验→"成本未知"，引擎不得按零成本计算，UI 显示"未核验，可能计息"。
- 正规分期成本：按实际本金、费用与各期现金流计算 IRR；展示"名义（月费率×12）"与"实际年化（复利）"两项；S15 的 18.25% 上限本身就是"月 IRR×12 的单利口径"，不得当作复利年化。`money.irr_monthly` 提供 Decimal 二分法实现。
- 循环信用计息（全额/未清偿部分、起息日）按 InterestRule 版本；招行规则待取得正文后实现（阻塞项 B-04）。

## 5. 额度语义（R-RULE-08）

| 字段 | 含义 | 规则 |
|---|---|---|
| `fixed_limit` | 固定额度 | 变更入历史 |
| `temp_limit` + `temp_expires_on` | 临时额度 | 到期后容量回落；超出固定额度的占用在到期时是否计入本期应还：待核验 |
| `special_limit` + `purpose` | 专项/分期额度 | 不可循环、不用于普通消费 |
| `used` | 已用 | 来自快照 |
| `available_raw` | 银行显示可用 | 可为负（超限）；原值保留 |
| `holds_uncounted` | 快照未包含的预授权 | 若银行已扣减则为 0 |
| `reservations` | 计划预留 | 采纳计划时增加，真实交易入账时转换 |
| `capacity_for_new_spend` | `max(0, available_raw − holds_uncounted − reservations)` | 允许截零的派生值。引擎 1.1.0 起按卡、信用账户、额度池三层逐层计算并逐层截零：每层都要扣除该层成员卡的未计预授权与预留；同一信用账户只有一个可用额，预授权与预留只记一次（engine-spec §12） |
| 共享池 | `pool.available` | 多层：卡 ≤ 账户 ≤ 池；同时检查，不按银行名分组 |
| 释放轨迹 | 还款 `credit_posted_at` + `release_lag` | 未知→保守不释放；远期消费按消费当天轨迹校验 |

快照记录：`source`（bank_app/statement/user/import）、`balance_as_of`（实际余额时点）、`observed_at`、`recorded_at`、`confirmation_level`、`includes_holds`。

## 6. 退款、撤销、预授权（R-RULE-09）

- 撤销（同日冲正）与退货退款（后续贷记）区分；预授权→入账为同一笔经济事实的状态变化，不是两笔交易。
- 退款是否冲抵本期应还：`offsets_current_due` 三态；未知→"待核对"，账单应还不变、统计不计收入、额度释放待确认。
- 活动奖励追回：按活动规则（S07：退货/冲正/撤销不返现；已返可从下月扣回）。

## 7. 已核验规则实例与待核验项

| 主体 | 规则 | 值 | 来源 | 状态 |
|---|---|---|---|---|
| 建行（名下所有卡） | 共享额度 | 共享 | S02（2022-12-27） | verified（页面较旧，账户级仍需核验） |
| 建行 | 分期占额/释放 | 账单/现金分期余额持续占用、逐期释放 | S02 | verified |
| 建行 | 临时额度有效期 | 一般 1 个月 | S02 | verified（"一般"） |
| 建行商户分期 | 每期本金、尾差 | 四舍五入，差额末期调整 | S15（2024-09 版） | verified |
| 建行商户分期 | 利息口径 | 分期收取；近似年化单利 ≤18.25% | S15 | verified |
| 建行商户分期 | 账单列示 | 先列示商品总价；逐期入账并全额计入最低还款 | S15 | verified |
| 建行商户分期 | 提前结清 | 剩余本金 + 已入账期数利息 | S15 | verified |
| 建行商户分期 | 退货 | 商户退款后调整金额/期数/利息 | S15 | verified |
| 浦发银联活动 | 统计口径/奖池/取整/追回 | 见 promotions-benefits-spec §2 | S07 | verified |
| 招行 | 账单日期、免息、计息、最低还款、冲抵顺序、退款入账时间 | — | S01/S03/S16 **未取得正文** | pending（阻塞项 B-04） |
| 任意银行 | 账单日当天入账归属、节假日顺延 | — | — | 按账户核验，默认 inclusive=true、不顺延 |

## 8. 规则维护流程（后台）

`draft → in_review → verified → published → expired`；每次发布附来源截图/PDF 指纹与核验人；差异视图对比版本；用户端可"采用官方模板"或"用户声明"，两者在账单页标明来源。官方旧网页可作历史资料，不因今天仍可打开就视为现行。

## 9. 测试要求

F-12 账单边界（inclusive 开关）、F-13 跨年、F-14 规则变更旧账单不变、F-15 入账窗口多账期、F-16 月末/闰年、F-17 工作日与顺延需日历、F-36/F-37 分期拆分与成本、F-25~F-28 额度语义、F-34 退款三态。PoC 已覆盖 F-12~F-17 的核心路径（`tests/test_billing.py`）。
