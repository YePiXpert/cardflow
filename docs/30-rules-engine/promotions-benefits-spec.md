# 33 · 活动、权益、积分与年费规格

版本 0.1 · 2026-10-16。对应 R-PROMO-01~07、R-BEN-01~06。活动规则样本来自 S07（仅作模型覆盖样本，不构成推荐）。

## 1. 活动声明式规则模型（promotion rule schema v1）

```json
{
  "schema": "promotion-rule/v1",
  "subject": { "banks": ["SPDB"], "products": ["*"], "card_bins": ["62"], "scope": "card", "one_per_person": true },
  "enrollment": { "required": true, "channel": "官方 App 路径", "window": { "from": "2026-08-10T00:00+08:00", "to": "2026-12-31T23:00+08:00" }, "counts_only_after_enrollment": true },
  "counting": { "window": { "from": "...", "to": "..." }, "tz": "Asia/Shanghai", "time_basis": "network_received", "posting_required": true },
  "eligibility": { "regions": ["overseas", "HK", "MO", "TW"], "channels": ["pos_swipe", "contactless", "chip"], "mcc_include": [], "mcc_exclude": [], "exclude_types": ["cash_advance", "preauth", "refund", "reversal", "fee", "tax_refund"], "exclude_wallets": ["alipay", "wechat"] },
  "thresholds": [ { "kind": "per_txn_min", "amount_minor": 0 } ],
  "reward": { "kind": "cashback", "basis": "per_txn", "rate": "0.03", "rounding": "DOWN_2", "cap": { "per_card_per_month_minor": 30000 }, "excess_only": false },
  "pool": { "monthly_minor": 30000000, "total_minor": 150000000, "ordering": "first_posted", "carry_over": false },
  "stacking": { "allowed": true, "exclusive_with": [] },
  "payout": { "form": "cashback_to_card", "within_days_after_posting": 30 },
  "clawback": { "on_refund": "no_reward", "after_payout": "deduct_next_month" },
  "version": { "source_url": "...", "verified_on": "2026-10-16", "effective_from": "2026-08-10", "effective_to": "2026-12-31" }
}
```

规则 JSON 经 JSON Schema 校验入库；运行时由固定解释器求值，**不执行任何来自内容的代码**。`rate` 为字符串小数；取整模式枚举（DOWN_2 = 截断两位，S07）。每个字段缺失时用 `null` 而非默认值，并在资格判断中产出 `unknown_reasons`。

## 2. S07 样本的字段覆盖（F-40）

| 条款 | 模型表达 |
|---|---|
| 北京时间 2026-08-10 00:00 至 2026-12-31 23:00 | counting.window + tz |
| 须先报名；报名前消费不计 | enrollment.required/counts_only_after_enrollment |
| 以进入银联后台时间为准 | counting.time_basis=network_received |
| 境外含港澳台；线下刷卡/挥卡/插卡；不含支付宝微信 | eligibility.regions/channels/exclude_wallets |
| 不含取现、溢缴款取现、费用、退税、预授权 | eligibility.exclude_types |
| 3% 每笔，每卡每月 300 封顶 | reward.rate/basis/cap |
| 月奖池 30 万、总 150 万、先到先得、不结转 | pool |
| 累计满 1 万超额部分 10%（活动二） | thresholds[{kind:"cumulative_monthly_min", amount}] + reward.excess_only=true |
| 取小数点后两位不四舍五入 | reward.rounding=DOWN_2 |
| 30 日内返现；活动二次月月底 | payout.within_days / payout.by_end_of_next_month |
| 退货/冲正/撤销不返现；已返下月扣回 | clawback |
| 可与其他活动叠加（另有规定除外） | stacking |
| 一人一卡一手机号 | subject.one_per_person |

## 3. 资格三态与未知处理（R-PROMO-04）

| 判断项 | 已知来源 | 未知时 |
|---|---|---|
| MCC | 交易导入含 MCC | `unknown_reasons: ["mcc_unknown"]`，不从商户名推断 |
| 名额/奖池余量 | 无官方接口 | `pool_unknown`，估计奖励标注"奖池可能已耗尽" |
| 用户定向资格 | 用户确认 | `targeting_unknown` |
| 报名状态 | 用户确认（user_confirmed） | 未确认→不进入确定收益 |

## 4. 三层状态与现金流（R-PROMO-06）

`system_estimated`（进度/奖励估计）→ `user_confirmed`（报名、领取）→ `bank_confirmed`（到账核对匹配交易）。现金流中奖励以 `expected` 事件出现（可在情景中排除），到账后转 `confirmed`。退款追回生成负向 `reward_ledger` 行与 `expected` 负事件。

## 5. 周期与取整测试（F-41~F-43）

- 月/季/年/活动期周期键 `period_key` 由 `counting.tz` 计算；跨月交易按入账时间归属。
- 取整：3% × 123.45 = 3.7035 → DOWN_2 = 3.70；HALF_UP 才是 3.70（此例相同），用 3% × 123.49 = 3.7047 → DOWN_2 3.70 / HALF_UP 3.70；用 10% × 0.99 → 0.09 vs 0.10 区分。
- 封顶：每卡每月 300；共享上限（同一持卡人多卡）按 subject.scope。
- 奖池不结转：11 月池未用完不进 12 月。

## 6. 权益（R-BEN-01~03）

`benefit_definitions{type, unit(times/amount), cycle(annual/calendar_year/card_year/rolling_days), shared_scope(card/account/holder), booking_required, provider, terms_url, source}`；`benefit_grants{cycle_start,cycle_end,quota,remaining}`；`benefit_usages{status}`。取消后 `cancel_pending_restore`，恢复需用户/银行确认；保险类不计价值。

## 7. 积分（R-BEN-04）

批次按 `earned_at` FIFO 扣减；`expires_at` 到期生成 `expire` 事件；退款追回 `reverse` 指向原批次；估值字段 `valuation_minor_per_point` 为 null 时价值显示"未估值"。

## 8. 年费（R-BEN-05）

`annual_fee_rules{amount, charge_rule(日期/持卡年), waiver{kind: txn_count|spend_amount|points_redeem, threshold, window}}`；周期进度由交易投影计算（system_estimated），"已达标待确认"直到账单显示减免（bank_confirmed）。

## 9. 卡片保留分析（R-BEN-06）

四列：已实现权益价值（bank/user confirmed 使用 × 用户估值）、主观估值（用户输入）、年费（规则）、其他成本（利息/费用实际）。不合成分数，不给"建议销卡"结论，只列数字与来源。

## 10. 来源与抓取策略（R-PROMO-02）

`promotion_sources{domain, allowed_paths, license_note, robots_checked_on, fetch_interval_hours(≥24), last_fetch, status}`；抓取只做"变更检测 + 保存快照"，解析为规则草稿需人工复核发布；无法访问时保存链接请用户补充；失效下架保留历史版本。SSRF 防护：仅白名单域名、禁止内网地址与重定向到内网。
