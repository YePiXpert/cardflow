"""Print the evidence report for the §10 regression sample (markdown on stdout)."""
import json
import os
import sys
from dataclasses import asdict
from datetime import date

from cardflow_ref import MODEL_VERSION
from cardflow_ref.allocation import derive_card_info
from cardflow_ref.fixture import load_fixture
from cardflow_ref.money import fmt
from cardflow_ref.plan import _json, plan
from cardflow_ref.verifier import verify

FIX = os.path.join(os.path.dirname(__file__), "fixtures", "regression_2026-10-16_10000.json")
inputs, scenarios, raw = load_fixture(FIX)
P = lambda s: print(s)

P(f"# 回归样本证据：{raw['fixture_id']}")
P(f"模型版本 {MODEL_VERSION}；输入哈希 `{inputs.input_hash()[:16]}…`；生成日期 {date.today().isoformat()}\n")
P("## 1. 账期归属（交易日 2026-10-16，当天入账）\n")
P("| 卡 | 账单日规则 | 到期规则 | 本次出账 | 到期还款 | 缓冲天数 |")
P("|---|---|---|---|---|---|")
for c in inputs.cards:
    i = derive_card_info(c, inputs.request)
    d = c.billing_rule.due
    due_desc = f"{'次月' if d.month_offset else '当月'}{d.day}日" if d.kind == "fixed_day" else f"账单后{d.days}天"
    P(f"| {c.id} | 每月{c.billing_rule.statement_day}日 | {due_desc} | {i.cycle.statement_date} | {i.cycle.due_date} | {i.buffer_days} |")

P("\n## 2. 指定方案的独立验证（不经求解器）\n")
for label, alloc in [("A 8,000 + C 2,000", {"A": 800000, "C": 200000}), ("B 10,000 单卡", {"B": 1000000})]:
    v = verify(inputs, alloc, scenarios, "baseline")
    P(f"### {label}（加权付款缓冲 {v.weighted_buffer_days} 天）\n")
    P("| 情景 | 通过 | 最低现金 | 最低点日期 | 缺口点（日期/余额/距零/距储备） |")
    P("|---|---|---|---|---|")
    for sid, chk in v.checks.items():
        br = "；".join(f"{b['on']} / {fmt(b['balance'])} / {fmt(b['gap_to_zero'])} / {fmt(b['gap_to_reserve'])}" for b in chk.breaches) or "—"
        P(f"| {sid} | {'是' if chk.ok else '否'} | {fmt(chk.min_balance_by_account['cash-main'])} | {chk.min_on_by_account['cash-main']} | {br} |")
    P("")

P("## 3. 求解与业务状态\n")
for profile in ("cash_safety", "verified_benefit", "fewer_cards"):
    out = plan(inputs, scenarios, "baseline", profile, time_limit_s=10)
    alloc = "，".join(f"{k} {fmt(v)}" for k, v in out.allocation.items())
    tiers = "；".join(f"{t.name}={t.value}({t.status})" for t in out.solve.tiers) if out.solve else ""
    P(f"- 目标画像 **{profile}**：求解器 {out.solve.status if out.solve else '—'}，业务状态 **{out.business_status}**，分配 {alloc}；未通过情景 {out.failing_scenarios}；层级 {tiers}；耗时 {out.solve.wall_time_s:.3f}s")
out = plan(inputs, scenarios, "baseline", "cash_safety", time_limit_s=10)
P("\n### 未选卡片原因（cash_safety）\n")
for r in out.rejections:
    P(f"- {r['card']}: {r['reason']} " + (f"首个缺口 {r['first_breach']['on']} 余额 {fmt(r['first_breach']['balance'])}" if r.get('first_breach') else ""))
P("\n### 压力情景敏感性（收入 11-26 → 11-29）\n")
s = out.sensitivity["stress_income_delay"]
P(f"- 最少补充已确认现金：{fmt(s['min_extra_confirmed_cash']['total'])}（{s['min_extra_confirmed_cash']['status']}）")
P(f"- 该情景下最大可负担金额：{fmt(s['max_affordable_amount']['amount'])}（分配 {s['max_affordable_amount']['allocation']}）")
P(f"- 最早可行的推迟消费日期：{s['first_feasible_date_shift']}")
P(f"- 已确认口径：{out.sensitivity['confirmed']}")
P("\n### 已确认口径（不计预计收入）\n")
c = plan(inputs, scenarios, "confirmed", "cash_safety", time_limit_s=5)
b = c.baseline["confirmed"]["accounts"]["cash-main"]
P(f"- 业务状态 **{c.business_status}**：新增消费前基线已在 {b['breaches'][0]['on']} 跌至 {fmt(b['breaches'][0]['balance'])}（距零 {fmt(b['breaches'][0]['gap_to_zero'])}，距储备 {fmt(b['breaches'][0]['gap_to_reserve'])}）")
P("\n### 压力情景作为决策情景\n")
sd = plan(inputs, scenarios, "stress_income_delay", "cash_safety", time_limit_s=10)
P(f"- 业务状态 **{sd.business_status}**；敏感性：{json.dumps(sd.sensitivity['stress_income_delay'], default=_json, ensure_ascii=False)}")
P("\n### 运行记录\n")
P(f"- run_id `{out.solve.run_id}`；求解器 OR-Tools {out.solve.solver_version}；模型 {out.solve.model_version}；时限 {out.solve.time_limit_s}s；检查点 {out.solve.checkpoints}；创建 {out.solve.created_at}")
P(f"- 假设：{out.assumptions}")
P("\n> 这是合成输入下的计算结果，不是真实可负担结论；基准口径依赖预计收入，已确认口径下基线本身已有缺口，因此不得标注为“稳妥”。")
