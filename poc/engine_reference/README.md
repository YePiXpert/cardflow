# CardFlow 参考引擎（PoC，规划轮 2026-10-16）

目的：把任务书 §4/§5 的账期规则、逐时点现金流、CP-SAT 分配模型、独立验证器和分层业务状态落成**可执行语义**，并用 §10 回归样本产出证据。它是生产引擎的 golden-fixture 预言机，**不是生产代码**：没有持久化、没有 API、没有导入/对账、没有活动权益。

## 运行

```bash
uv venv .venv --python 3.13 && uv pip install --python .venv/bin/python -r requirements.lock.txt
PYTHONPATH=. .venv/bin/python -m pytest -q tests
PYTHONPATH=. .venv/bin/python run_sample.py > EVIDENCE.md
```

## 模块

| 文件 | 内容 |
|---|---|
| `cardflow_ref/money.py` | 整数最小单位、显式取整、分期拆分（尾差末期）、Decimal IRR |
| `cardflow_ref/billing.py` | 固定日/账单后 N 天、月末截断、闰年、跨年、账单日当天归属开关、工作日与顺延（需日历）、规则版本与已出账单优先 |
| `cardflow_ref/cash.py` | 逐账户现金时间线：快照包含关系、同日保守顺序、情景（已确认/基准/压力）、全部缺口点与双口径缺口 |
| `cardflow_ref/allocation.py` | CP-SAT：x_i 整数分、y_i、共享池、K、最小拆分、逐检查点现金底线、分层目标（三种画像）、状态直传、敏感性求解 |
| `cardflow_ref/verifier.py` | 不依赖求解器的独立验证器 |
| `cardflow_ref/plan.py` | 数据检查 → 基线 → 求解 → 多情景验证 → 业务状态/拒绝原因/敏感性 |
| `fixtures/regression_2026-10-16_10000.json` | §10 golden fixture 与验收期望 |

## 已证明 / 未证明

- 已证明：样本的账期、A8000+C2000 的最低现金 3,000 与 42.4 天缓冲、B 单卡 11-08 −3,500 与 11-16 −7,000、收入延迟下 11-28 −2,000（距零 2,000 / 距储备 4,000）、已确认口径基线缺口、条件可行/不可行/数据不足/超时的状态区分。
- 未证明：真实银行规则（招行章程正文未取得）、性能规模（10–30 卡 × 180 天 × 万笔交易）、离线端一致性。
