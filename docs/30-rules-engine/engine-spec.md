# 31 · 智能用卡引擎规格：数学模型、求解、状态与解释

参考实现：`poc/engine_reference/`（OR-Tools 9.15.6755，40 项测试通过，证据 `EVIDENCE.md`）。生产引擎必须与该 PoC 在 golden fixtures 上逐字段一致。

## 1. 目标与非目标

目标：对一笔已确定净额的计划消费，在硬约束（额度、拆单、渠道、现金底线）下给出三类可比较方案与完整解释；状态可复现、可审计。
非目标：让大模型决定金额/日期；在硬约束不满足时给出"看似合理"的推荐；自动假设借款、提额、以卡养卡。

## 2. 输入契约（R-ENG-01）

| 对象 | 字段 |
|---|---|
| PlanRequest | `amount`(最小单位整数 M)、`currency`、`txn_date`、`allow_split`、`max_cards` K、`min_split`、`payment_lead_days`、`channel`、`merchant/category`、`allow_installment`、`reserve_cash_override?`、`reserve_limit_by_card?` |
| CardOption[] | `card_id`、`credit_account_id`、`raw_available`、`holds_uncounted`、`reservations`、`per_txn_cap`、`daily_cap`、`min_split`、`channel_ok`、`currency_ok`、`status_ok`、`pool_id`、`billing_rule_version`、`posting_delay_min/max`、`repay_from_cash_account`、`fee_rate/fee_fixed`、`verified_benefit_rate/cap`、`potential_benefit_rate`、`temp_limit_expiry`、`future_releases[]` |
| Pools | `pool_id → available`（多层时每层一条） |
| CashAccount[] | `id`、`currency`、`reserve_floor`、`usable_for_repayment`、`available_from?` |
| Snapshot[] | `account`、`balance`、`as_of`、`observed_at`、`includes_event_ids[]` |
| CashEvent[] | `id`、`account`、`on`/`at`、`amount`、`cls`(confirmed/expected/planned)、`category` |
| Scenario{} | `include_expected`、`income_delay_days`、`income_scale`、`expense_scale`、`event_overrides`、`same_day_order`；至少 `confirmed`、`baseline`，可多个 `stress_*` |
| Options | `profile`(cash_safety/verified_benefit/fewer_cards)、`decision_scenario`、`time_limit_s`、`workers`、`seed`、`stale_after_days`、`global_reserve_floor` |

## 3. 数学模型（R-ENG-02）

决策变量：`x_i ∈ ℤ`（卡 i 分配的最小单位金额），`y_i ∈ {0,1}`。

硬约束：
1. 守恒 `Σ x_i = M`
2. 容量 `0 ≤ x_i ≤ cap_i · y_i`，`cap_i = min(capacity_i, per_txn_cap_i, daily_cap_remaining_i)`
3. 卡数 `Σ y_i ≤ K`（未确认拆单 K=1）
4. 最小拆分 `x_i ≥ min_split_i · y_i`
5. 共享池 `Σ_{i∈g} x_i ≤ available_g`，多层逐层
6. 资格 `y_i = 0` 若渠道/币种/状态/专项额度用途/临额有效期/还款账户受限不满足（建模前剔除并记录原因）
7. 远期消费 `capacity_i(txn_date) = capacity_i(now) + Σ 已确认释放(≤ txn_date)`；未确认释放不计
8. **现金底线（每账户、每情景 s、每检查点 t）**：`C[a,s,t] = base_low[a,s,t] − Σ_{i: repay_from(i)=a, repay_on(i) ≤ t} x_i ≥ floor_a`，其中 `base_low` 为不含新计划的当日"先支出后收入"最低点（含快照包含关系与同日假设）；检查点 = 该情景所有事件日 ∪ 所有候选扣款日；可选整体底线 `Σ_a C[a,s,t] ≥ floor_global`
9. 基线：若某检查点无新计划项且 `base_low < floor` → 该情景 BASELINE_SHORTFALL（模型层以不可行约束表达，业务层先行拦截）

线性化：费用 `f_i·den ≥ x_i·num + fee_fixed·den·y_i`（向上取整）；已核实收益 `b_i·den ≤ x_i·num, b_i ≤ cap`（向下取整）；缓冲 `Σ x_i·days_i`。利率/汇率用精确分数（`Fraction(Decimal)`），不出现二进制浮点。

## 4. 分层目标（R-ENG-03）

逐层求解，上一层最优值作为下一层约束（严格字典序）：

| 画像 | 层 1 | 层 2 | 层 3 | 层 4 | 层 5 |
|---|---|---|---|---|---|
| cash_safety | max 最差现金余量 `m = min_{a,t}(C − floor)` | min 确定费用 | max 已核实净收益 | max 加权付款缓冲 | min 用卡数 |
| verified_benefit | max 已核实净收益 | max 最差余量 | max 缓冲 | min 用卡数 | — |
| fewer_cards | min 用卡数 | max 最差余量 | max 已核实净收益 | max 缓冲 | — |

任何收益都不能抵消逾期或现金不足（它们在硬约束层）。用户手动降低储备 → 以新 floor 重算并写入运行记录 `reserve_override`。

## 5. 情景与业务状态（R-ENG-05）

```
plan():
  issues = data_issues()                      # 缺快照、快照过期(>stale_after_days)、规则非法、池缺快照
  if issues: return NEEDS_DATA(issues)
  baseline[s] = evaluate(existing events, s) for s in scenarios
  if not baseline[decision].ok: return BASELINE_SHORTFALL(baseline)
  if no eligible card: return INFEASIBLE + rejections   # 全部卡在建模前被排除；求解器 NOT_RUN，notes 含 NO_ELIGIBLE_CARDS（M0 起）
  res = solve(decision, profile, time_limit)  # 分层 CP-SAT
  if res.status == INFEASIBLE: return INFEASIBLE + sensitivity(decision) + rejections
  if res.status == UNKNOWN and no solution: return UNKNOWN(time limit, not a proof)
  if res.status == MODEL_INVALID: return MODEL_INVALID(detail)
  ver = verify(res.allocation, all scenarios)  # 独立验证器
  if not ver.ok: return MODEL_INVALID("VERIFIER_REJECTED_SOLVER_SOLUTION")   # 缺陷，不吞掉
  failing = scenarios where ver fails or baseline fails
  status = FEASIBLE_ROBUST if failing == [] else CONDITIONALLY_FEASIBLE
  sensitivity for each failing stress scenario; rejections for unused cards
```

| 业务状态 | 含义 | UI 语义 |
|---|---|---|
| NEEDS_DATA | 缺快照/过期/规则缺失 | 列出缺什么；可按假设继续（标注） |
| BASELINE_SHORTFALL | 新增消费前已有缺口 | 先解决基线 |
| INFEASIBLE | 决策情景下证明无解 | 解释 + 敏感性 |
| UNKNOWN | 超时/资源限制，未证明 | "未能在时限内判定"，可延时重试 |
| MODEL_INVALID | 输入/模型非法或验证器拒绝 | 报缺陷，不展示方案 |
| CONDITIONALLY_FEASIBLE | 决策情景通过，但已确认口径或某压力情景不通过 | 黄色；列出未通过情景与缺口 |
| FEASIBLE_ROBUST | 所有情景（含已确认口径）通过 | 绿色"稳妥"仅此状态 |

## 6. 输出契约（R-ENG-06）

- `allocation[]`：`card_id, amount, statement_date, due_date, repay_on, repay_from, buffer_days, fee, verified_benefit, potential_benefit, cycle_assumptions[], alternative_cycles[]`
- `verification`：`weighted_buffer_days`、每情景 `ok/ok_zero/min_balance_by_account/min_on/breaches[]{on,balance,gap_to_zero,gap_to_reserve,events}`、`assumptions[]`
- `rejections[]`：`CARD_STATUS | CURRENCY_NOT_SUPPORTED | CHANNEL_NOT_SUPPORTED | REPAY_ACCOUNT_RESTRICTED | NO_CAPACITY | INSUFFICIENT_LIMIT_ALONE | CASH_BREACH_ALONE{first_breach, all_breaches} | DOMINATED{min_balance, buffer_days}`
- `sensitivity{scenario}`：`min_extra_confirmed_cash{total, by_account, allocation}`、`max_affordable_amount{amount, allocation}`、`first_feasible_date_shift{shift_days, txn_date}`
- `run record`：`run_id, created_at, input_hash, model_version, solver_version, profile, decision_scenario, time_limit_s, workers, seed, checkpoints, tiers[]{name, sense, status, value, bound, wall_time}, proven_optimal, notes[]`

## 7. 求解器状态与超时（R-ENG-04）

- 求解器状态直传：OPTIMAL / FEASIBLE / INFEASIBLE / UNKNOWN / MODEL_INVALID（S08）。
- 时限按层分配；某层 FEASIBLE（未证最优）→ 总状态 FEASIBLE 并记录 bound；某层 UNKNOWN 且已有解→保留上层解并标注；首层 UNKNOWN 无解→UNKNOWN，**不得写成"没有可用组合"**。
- `num_workers=8`、`random_seed` 固定以利复现；记录 `wall_time`。

## 8. 本地离线求解边界（R-ENG-08）

Flutter/Dart 端不具备 CP-SAT。本地提供：① 独立验证器（与服务端同语义，逐时点）；② 有限搜索（K ≤ 3、按最小拆分步长或候选切点枚举，预算 ≤ 2 s）。有限搜索找到的方案可验证为可行；找不到只输出"本地未找到（非证明无解）"。双端一致性通过共享规则协议（JSON schema）与 golden fixtures（本 PoC fixture 为首个）保证；服务端联网时以 CP-SAT 结果为准并可覆盖本地结果。

## 9. 回归样本结果（§10）

| 项目 | 结果 |
|---|---|
| 账期 | A 11-10/11-28；B 10-20/11-08；C 11-05/11-25 |
| 基准情景最优（三画像一致） | A 8,000 + C 2,000；最低现金 3,000（10-28、11-16、11-28）；缓冲 42.4 天；min_margin 1,000 |
| B 单卡 | 11-08 −3,500；11-16 −7,000（全窗口最低）；11-22 −2,000；三个缺口点 |
| 压力（收入 11-26→11-29） | A+C 在 11-28 −2,000；距零 2,000，距储备 4,000；作决策情景时 INFEASIBLE；最少补充 4,000；最大可负担 6,000；推迟至 10-21 可行（B 进入 11-20 账单，12-08 到期） |
| 已确认口径 | 基线在 11-08 已 −2,000 → BASELINE_SHORTFALL |
| 总体 | CONDITIONALLY_FEASIBLE（不得标"稳妥"） |

## 10. 性能目标（目标值，未测量）

规模：10–30 张卡、≥180 天预测、万笔级历史交易、3–5 个情景。目标：服务端求解 p95 ≤ 3 s（8 vCPU 容器，时限 10 s），本地验证 ≤ 300 ms（中端手机）。测试方法：合成数据生成器（`70-testing/test-plan.md` §8）；超时后真实降级状态（UNKNOWN + 本地有限搜索结果）必须可演示。

## 11. 可复现性

`input_hash = sha256(canonical JSON of inputs)`；`model_version` 随模型变更递增；每次运行独立 `run_id`，分配结果与验证结果绑定 run_id，不覆盖历史。

## 12. M0 审查裁决（2026-10-17，依据 `evidence/m0/review-wave3-engine.md`）

以下语义由主会话裁决，修正后 `model_version` 升为 1.1.0；F-18 的期望值不变。

1. **只有可执行状态才给出方案**：FEASIBLE_ROBUST 与 CONDITIONALLY_FEASIBLE 之外，`allocation` 一律为空；被验证器拒绝的分配只放在诊断字段里，任何路径都不得展示或采纳（R3E-02）。
2. **快照反映判定先于情景变换**：
   - 先按原始事件判定"已被快照反映"，再做情景变换（延迟、缩放、覆盖）。
   - 变换后日期早于快照日的事件，按快照日计入，不丢弃。
   - includes_event_ids 只能列快照日当天及以前的事件（R3E-03、R3E-14）。
3. **额度共享**：
   - 同一信用账户下的卡（主卡、附属卡）共享该账户的可用额度，构成一个容量层。
   - 额度池的容量要扣除成员卡的预留与未计入的预授权。
   - 协议 v1 只表达一层池；多层池在 M2（WP-20）随协议 v2 支持，在此之前不得用一层池近似多层（R3E-04）。
4. **同日顺序一致**：
   - 模型与验证器对同一天使用同一顺序规则。
   - 模型为候选还款日插入的零额标记，不参与"当日事件是否全部带时间戳"的判断。
   - 被情景改动了日期的事件丢弃原时间戳，在新日期上按保守顺序处理（R3E-05）。
5. **可复现**：并列最优时必须有确定的平局规则，同一输入、同一 seed 在任意 workers 下得到同一分配；敏感性求解同样适用（R3E-06）。
6. **费用进入现金**：
   - 手续费与本金出现在同一期账单上，在 repay_on 当天随还款一并从还款现金账户流出。
   - 现金时间线中的还款额 = 分配金额 + 该卡费用。
   - 已核实收益不作为现金流入，保持保守口径（R3E-07）。
7. **检查区间只取决于输入**：
   - 检查到 `horizon_end` 为止，不再按可用卡的还款日延长。
   - 还款日晚于 `horizon_end` 的卡判为不可用，拒绝原因为 `REPAY_AFTER_HORIZON`。
   - 求解接口把 `horizon_end` 设为不早于交易日后 180 天（R3E-08）。
8. **基线检查包含全局底线**（R3E-09）。
9. **敏感性求解**：
   - 时限受整次运行的 `time_limit_s` 约束（R3E-17）。
   - 单项敏感性失败只把该项标为不可用，不让整次运行变成 MODEL_INVALID。
   - 规则带 `effective_to` 时，平移后日期上规则不生效的卡视为当日不可用（R3E-01）。
10. **建模异常兜底的范围**：只包住建模与求解调用；其他阶段的异常是缺陷，要暴露给测试，不得伪装成"超出支持范围"（R3E-15）。

### 12.1 落地细节（T-004c，引擎 1.1.0；与前文冲突处以本节为准）

证据见 `evidence/m0/T-004/c2-*`。F-18 期望值不变。默认差分测试 1,200 例、模糊测试 12,000 例，均 0 失配。

- **§2 与 §5**：
  - 检查区间不延长；还款日晚于 `horizon_end` 的卡给出拒绝原因 `REPAY_AFTER_HORIZON`。
  - 无可用卡时返回 INFEASIBLE。若有卡因 `REPAY_BEFORE_TXN_DATE` 被排除，仍计算推迟日期敏感性，另两项敏感性为 NOT_RUN。
- **§3**：
  - 还款现金 = 分配金额 + 费用。
  - 容量分三层：卡、信用账户、额度池，每层扣除成员卡的预授权与预留后截零。
  - 全局底线的检查点包含每个快照日。
- **§4 与 §7**：
  - 末层之后加平局规则：按卡的输入顺序，在剩余最优解中依次取最大金额。结果与 workers 无关，敏感性同样处理。
  - `time_limit_s` 是整次运行的预算：主求解最多用一半，敏感性分享剩余时间。
- **§6**：
  - 非可执行状态下 `allocation` 为空、`verification` 为 null；被拒方案只放在 `diagnostics`（不得展示或采纳）。
  - 拒绝原因新增 `MIN_SPLIT_ABOVE_AMOUNT`、`REPAY_BEFORE_TXN_DATE`、`REPAY_AFTER_HORIZON`、`NOT_COMPARED`。
  - 敏感性逐项给出状态（含 NOT_RUN / MODEL_INVALID）。
  - 基线检查输出 `global_breaches`。
- **§10 性能**：在协议上限（200 卡、10,000 事件）下，Python 侧逐卡拒绝原因验证约需 6 s，与求解时限无关，列入 M2 WP-23 的优化项。
- **数据缺口**：数据模型还没有"额度池可用额"的来源（`credit_pools` 无可用额字段，也没有池级快照），在 M1 WP-10 补上。在此之前，求解接口遇到涉及额度池的计划，返回 NEEDS_DATA（`POOL_SNAPSHOT_MISSING`），不得估算。
