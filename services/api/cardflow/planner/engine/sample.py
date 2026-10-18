"""Print the evidence report for the §10 regression sample (markdown on stdout).

Production counterpart of ``poc/engine_reference/run_sample.py`` (T-003): same computations,
same report format. Run from a source checkout::

    uv run python -m cardflow.planner.engine.sample

The golden fixture is resolved relative to this file
(``<repo>/packages/rules-protocol/fixtures/regression_2026-10-16_10000.json``), so the
current working directory does not matter. Like the PoC script, the report is specific to
that fixture (card ids, the ``cash-main`` account and the compared allocations are fixed).
Developer entry point only: no engine module imports it.
"""

import json
import sys
from datetime import datetime
from pathlib import Path

from cardflow.planner.engine import MODEL_VERSION
from cardflow.planner.engine.allocation import derive_card_info
from cardflow.planner.engine.fixture import load_fixture
from cardflow.planner.engine.money import fmt
from cardflow.planner.engine.plan import _json, plan
from cardflow.planner.engine.verifier import verify

# This file is <repo>/services/api/cardflow/planner/engine/sample.py.
FIXTURE = (
    Path(__file__).resolve().parents[5]
    / "packages"
    / "rules-protocol"
    / "fixtures"
    / "regression_2026-10-16_10000.json"
)


def _emit(line: str) -> None:
    """Write one report line (the PoC script used ``print``)."""
    sys.stdout.write(f"{line}\n")


def main() -> int:
    """Print the report; returns the process exit code."""
    inputs, scenarios, raw = load_fixture(FIXTURE)
    # Report date only (never used in a computation): local date, as date.today() in the PoC.
    today = datetime.now().astimezone().date().isoformat()

    _emit(f"# 回归样本证据：{raw['fixture_id']}")  # noqa: RUF001
    _emit(
        f"模型版本 {MODEL_VERSION}；输入哈希 `{inputs.input_hash()[:16]}…`；生成日期 {today}\n"  # noqa: RUF001
    )
    _emit("## 1. 账期归属（交易日 2026-10-16，当天入账）\n")  # noqa: RUF001
    _emit("| 卡 | 账单日规则 | 到期规则 | 本次出账 | 到期还款 | 缓冲天数 |")
    _emit("|---|---|---|---|---|---|")
    for c in inputs.cards:
        i = derive_card_info(c, inputs.request)
        d = c.billing_rule.due
        due_desc = (
            f"{'次月' if d.month_offset else '当月'}{d.day}日"
            if d.kind == "fixed_day"
            else f"账单后{d.days}天"
        )
        _emit(
            f"| {c.id} | 每月{c.billing_rule.statement_day}日 | {due_desc} | "
            f"{i.cycle.statement_date} | {i.cycle.due_date} | {i.buffer_days} |"
        )

    _emit("\n## 2. 指定方案的独立验证（不经求解器）\n")  # noqa: RUF001
    for label, alloc in [
        ("A 8,000 + C 2,000", {"A": 800000, "C": 200000}),
        ("B 10,000 单卡", {"B": 1000000}),
    ]:
        v = verify(inputs, alloc, scenarios, "baseline")
        _emit(f"### {label}（加权付款缓冲 {v.weighted_buffer_days} 天）\n")  # noqa: RUF001
        _emit("| 情景 | 通过 | 最低现金 | 最低点日期 | 缺口点（日期/余额/距零/距储备） |")  # noqa: RUF001
        _emit("|---|---|---|---|---|")
        for sid, chk in v.checks.items():
            br = (
                "；".join(  # noqa: RUF001
                    f"{b['on']} / {fmt(b['balance'])} / {fmt(b['gap_to_zero'])} / "
                    f"{fmt(b['gap_to_reserve'])}"
                    for b in chk.breaches
                )
                or "—"
            )
            _emit(
                f"| {sid} | {'是' if chk.ok else '否'} | "
                f"{fmt(chk.min_balance_by_account['cash-main'])} | "
                f"{chk.min_on_by_account['cash-main']} | {br} |"
            )
        _emit("")

    _emit("## 3. 求解与业务状态\n")
    for profile in ("cash_safety", "verified_benefit", "fewer_cards"):
        out = plan(inputs, scenarios, "baseline", profile, time_limit_s=10)
        alloc_text = "，".join(f"{k} {fmt(v)}" for k, v in out.allocation.items())  # noqa: RUF001
        tiers = (
            "；".join(f"{t.name}={t.value}({t.status})" for t in out.solve.tiers)  # noqa: RUF001
            if out.solve
            else ""
        )
        _emit(
            f"- 目标画像 **{profile}**：求解器 {out.solve.status if out.solve else '—'}，"  # noqa: RUF001
            f"业务状态 **{out.business_status}**，分配 {alloc_text}；"  # noqa: RUF001
            f"未通过情景 {out.failing_scenarios}；层级 {tiers}；"  # noqa: RUF001
            f"耗时 {out.solve.wall_time_s:.3f}s"
        )
    out = plan(inputs, scenarios, "baseline", "cash_safety", time_limit_s=10)
    _emit("\n### 未选卡片原因（cash_safety）\n")  # noqa: RUF001
    for r in out.rejections:
        first = (
            f"首个缺口 {r['first_breach']['on']} 余额 {fmt(r['first_breach']['balance'])}"
            if r.get("first_breach")
            else ""
        )
        _emit(f"- {r['card']}: {r['reason']} " + first)
    _emit("\n### 压力情景敏感性（收入 11-26 → 11-29）\n")  # noqa: RUF001
    s = out.sensitivity["stress_income_delay"]
    _emit(
        f"- 最少补充已确认现金：{fmt(s['min_extra_confirmed_cash']['total'])}"  # noqa: RUF001
        f"（{s['min_extra_confirmed_cash']['status']}）"  # noqa: RUF001
    )
    _emit(
        f"- 该情景下最大可负担金额：{fmt(s['max_affordable_amount']['amount'])}"  # noqa: RUF001
        f"（分配 {s['max_affordable_amount']['allocation']}）"  # noqa: RUF001
    )
    _emit(f"- 最早可行的推迟消费日期：{s['first_feasible_date_shift']}")  # noqa: RUF001
    _emit(f"- 已确认口径：{out.sensitivity['confirmed']}")  # noqa: RUF001
    _emit("\n### 已确认口径（不计预计收入）\n")  # noqa: RUF001
    c = plan(inputs, scenarios, "confirmed", "cash_safety", time_limit_s=5)
    b = c.baseline["confirmed"]["accounts"]["cash-main"]
    _emit(
        f"- 业务状态 **{c.business_status}**：新增消费前基线已在 {b['breaches'][0]['on']} "  # noqa: RUF001
        f"跌至 {fmt(b['breaches'][0]['balance'])}"
        f"（距零 {fmt(b['breaches'][0]['gap_to_zero'])}，"  # noqa: RUF001
        f"距储备 {fmt(b['breaches'][0]['gap_to_reserve'])}）"  # noqa: RUF001
    )
    _emit("\n### 压力情景作为决策情景\n")
    sd = plan(inputs, scenarios, "stress_income_delay", "cash_safety", time_limit_s=10)
    sensitivity = json.dumps(
        sd.sensitivity["stress_income_delay"], default=_json, ensure_ascii=False
    )
    _emit(f"- 业务状态 **{sd.business_status}**；敏感性：{sensitivity}")  # noqa: RUF001
    _emit("\n### 运行记录\n")
    _emit(
        f"- run_id `{out.solve.run_id}`；求解器 OR-Tools {out.solve.solver_version}；"  # noqa: RUF001
        f"模型 {out.solve.model_version}；时限 {out.solve.time_limit_s}s；"  # noqa: RUF001
        f"检查点 {out.solve.checkpoints}；创建 {out.solve.created_at}"  # noqa: RUF001
    )
    _emit(f"- 假设：{out.assumptions}")  # noqa: RUF001
    _emit(
        "\n> 这是合成输入下的计算结果，不是真实可负担结论；"  # noqa: RUF001
        "基准口径依赖预计收入，已确认口径下基线本身已有缺口，"  # noqa: RUF001
        "因此不得标注为“稳妥”。"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
