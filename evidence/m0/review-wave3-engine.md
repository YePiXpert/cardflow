# 审查报告 · M0 波次 3 · 生产引擎（T-003 / T-004 / T-004b / 主会话修正）与规则协议 v1 的财务语义

- 审查日期：2026-10-17（新上下文审查代理，非实现者）
- 审查对象：`services/api/cardflow/planner/engine/`（相对 `poc/engine_reference/cardflow_ref/` 的全部改动：allocation、verifier、plan、`__init__`；billing、cash、money、fixture 经 AST 比对只有注解与导入变化）、`cardflow/planner/engine/protocol.py`、`packages/rules-protocol/`（schema v1、README、runner_py、fixtures）、`tests/engine/`、`tests/protocol/`
- 规格依据：engine-spec（全文）、bank-rules-spec §3/§5、ADR-004、ADR-008、api-contract §3（API-52）、test-plan §2–§3、rules-protocol README、data-model（credit_pools、cards）
- 方法：以代码、实际运行结果和规格为准独立复核；`evidence/m0/T-003`、`T-004` 只作对照。所有实验在副本 `/tmp/cardflow-review-engine/`（tar 复制 services、packages、poc、docs、evidence，不含 .venv 与缓存）中进行，解释器为 `services/api/.venv/bin/python`（Python 3.13.5、OR-Tools 9.15.6755、jsonschema 4.26.0），`PYTHONPATH=/tmp/cardflow-review-engine/services/api`（已确认导入的是副本中的包）。没有连接任何数据库，没有运行 docker，没有安装依赖。仓库文件除本报告外均未修改。审查结束时复核：仓库中 `planner/engine`、`tests/engine`、`tests/protocol`、`packages/rules-protocol`、`poc/engine_reference` 与副本逐文件 sha256 一致，即审查期间被审代码未发生变化。
- 自写独立参考实现 `scripts/ref.py`（只用标准库，不导入 cardflow，按规格重写账期、情景、时间线、结构约束、取整与分层目标），用带种子的自写生成器做差分与性质实验（未用 hypothesis）。脚本和原始输出在 `/tmp/cardflow-review-engine/{scripts,out}/`（未入库，临时目录）；major 的最小复现在 §2 与 §4 中写全，可独立重做。

---

## 1. 总评

**结论：可以在此基础上实现 T-009（求解接口）。没有 blocker。** T-009 的 M0 验收（提交 F-18 → 202 → `business_status=CONDITIONALLY_FEASIBLE`、`A=800000, C=200000`）所依赖的部分已经稳定：F-18 经人工 fixture 和协议两条路径，在三种画像、三个决策情景下与 PoC 逐字段一致；求解器结果在 3,941 个随机最优解上全部通过独立复算；协议 v1 的数值范围推导经模型 proto 实测成立。

T-009 开工时必须同时落实以下四条（都在 T-009 的设计范围内）：

1. **R3E-02**：MODEL_INVALID（验证器拒绝）的结果文档目前在 `allocation` 里给出被拒方案。T-009 不得把它写成 `plan_allocations`，API-53 采纳前必须检查 `business_status ∈ {FEASIBLE_ROBUST, CONDITIONALLY_FEASIBLE}`。最好在 v1 冻结前直接修改 `outcome_to_protocol`。
2. **R3E-04**：数据库 → CardOption 的映射不能让同一信用账户的几张卡各自带一份账户可用额，池的可用额也要扣除成员卡的预留与未计预授权。在引擎/协议支持之前，由 T-009 按账户建池；无法表达的多层池要拒绝。
3. 走 `plan_from_protocol`（`input_hash` = `protocol_input_hash`，R3E-15）；构造 PlanInput 时规范化 NUMERIC(20,10) 利率（R3E-11）；`horizon_end` 取不早于 `txn_date + 180 天`，以规避 R3E-08；worker 超时按敏感性求解的实际上限估算（R3E-17）。
4. 用真实数据对外提供求解之前，必须修正引擎语义问题 R3E-01、03、05、06、07、08（其中 03、05、07、08 继承自 PoC，07 需要先改规格）。逐项核对过：这些修正都不改变 F-18 的任何期望值（F-18 没有快照前事件，没有 includes，不用 timestamp 顺序，费用为 0，horizon 晚于全部还款日，没有 effective_to，没有共享账户或池）。修正后需升 `model_version`，并保持 F-18 不变。

总体质量：T-004/T-004b 的每项修正都有能"回退即失败"的测试（30 个变异体中 21 个被现有测试杀死，存活的有 3 个等价、6 个是测试缺口，见 R3E-16）。协议适配层不依赖 schema 库，独立校验类型、范围和交叉引用；schema 全部封闭（`additionalProperties:false` 或 propertyNames 映射）；金额字段不允许非整数浮点；范围错误不回显金额；canonical JSON 实现了 JCS 的键序、转义与数字格式。主要风险不在迁移本身，而在 PoC 继承下来、F-18 覆盖不到的语义：

- 情景变换与快照"已反映"关系的先后次序（R3E-03）；
- 共享额度的层级与预留（R3E-04）；
- timestamp 同日顺序（R3E-05）；
- 费用不进入现金（R3E-07）；
- 检查区间随可用卡变化（R3E-08）。

另有两处 T-004b 新代码的问题：全阶段兜底把一个正常的规则版本字段变成了 MODEL_INVALID（R3E-01）；多线程求解在并列最优时结果不可复现（R3E-06）。

| 严重度 | 数量 | 编号 |
|---|---|---|
| blocker | 0 | — |
| major | 8 | R3E-01 … R3E-08 |
| minor | 9 | R3E-09 … R3E-17 |
| nit | 5 | R3E-18 … R3E-22 |

复跑测试：`cd /tmp/cardflow-review-engine/services/api && PYTHONPATH=$PWD .../.venv/bin/python -m pytest -q tests/engine tests/protocol -p no:cacheprovider` → **310 passed, 1 warning in 15.79s**；运行器 F-18 **23/23**、退出码 0；`convert_legacy_fixture.py --check` → 逐字节相同（12977 bytes）。

---

## 2. 发现清单

位置的行号指 `services/api/cardflow/planner/engine/<文件>`，另有说明的除外。"PoC 继承"表示 PoC 中已有相同语义，生产引擎忠实迁移了它，问题并非迁移引入。证据标签（P-EFF 等）对应 §4。

| ID | 严重度 | 类别 | 位置 | 问题 | 复现（输入 → 实际；期望） | 建议修法 |
|---|---|---|---|---|---|---|
| R3E-01 | major | C / E / B | `allocation.py:661–697` `first_feasible_date_shift`（经 `ineligible_reason`→`derive_card_info`→`billing.cycle_for_posting` 抛 ValueError）；`plan.py:252–268` 全阶段 `except BUILD_ERRORS`；README"经协议进入的运行…到不了这一步" | 规则版本带 `effective_to` 是协议允许的正常字段。只要该日期落在推迟搜索的 45 天窗口内，且本次运行需要敏感性（决策情景 INFEASIBLE，或 CONDITIONALLY_FEASIBLE 且有失败的压力情景，F-18 就属于后者），推迟搜索在平移后的入账日调用 `derive_card_info` 就会抛 `ValueError("rule … not effective on …")`，再被 `plan()` 的兜底变成整次运行 MODEL_INVALID。后果：已求出且通过验证的方案被丢弃（allocation=[]、verification=null），INFEASIBLE 的解释和敏感性也一并丢失；note 写的是"a value is outside the range the engine supports"，与事实不符。PoC 在这里直接崩溃，T-004b 的兜底把崩溃换成了误导性的业务状态。边界 fuzz 的 575 份合法文档中有 7 份因此得到 MODEL_INVALID。 | P-EFF：F-18 v1 input，令 `cards[2].billing_rule.effective_to="2026-10-18"` → `business_status=MODEL_INVALID`、`solver_status=OPTIMAL`、allocation=[]、notes=`["MODEL_BUILD_ERROR: ValueError during sensitivity (a value is outside the range the engine supports; no plan is shown)"]`；期望 CONDITIONALLY_FEASIBLE、A 800000 + C 200000（与去掉 effective_to 相同）。decision=stress_income_delay 时同样得到 MODEL_INVALID，期望 INFEASIBLE + 敏感性。 | 推迟搜索对每个平移日期逐卡捕获规则不生效：把该卡视为该日不可用，或在最早的 effective_to 处停止搜索并写 note。任一敏感性计算失败，只把该条降级为 `{"status":"MODEL_INVALID","detail":…}`，不影响主结果。`BUILD_ERRORS` 兜底只包住建模/求解调用，不包整个 `plan()`；note 不要断言原因是"超出范围"。补测试：F-18 + effective_to 在 45 天内 → 仍为 CONDITIONALLY_FEASIBLE。长期：CardOption 支持多版本规则，按入账日选择。 |
| R3E-02 | major | E / G | `plan.py:412–429`（验证器拒绝分支带上 `res.allocation` 与 `ver`）；`protocol.py:1131、1189`（`allocation` 取自验证器明细行）；`PlanOutcome.schema.json` 描述"MODEL_INVALID keeps the rejected allocation for diagnosis" | engine-spec §5 规定 MODEL_INVALID"报缺陷，不展示方案"。现在 VERIFIER_REJECTED_SOLVER_SOLUTION 的 PlanOutcome，在与可执行方案同名的 `allocation` 字段里给出完整分配行（卡、金额、还款日、还款账户），同时 `failing_scenarios=[]`。API-52 原样返回这份文档。只要客户端，或 T-009 的落库与 API-53 采纳逻辑，按"allocation 非空"处理，就会展示甚至采纳一个被独立验证器拒绝的方案。 | P-MI：按 `tests/protocol/test_adapter.py` 的方式注入验证器拒绝 → `business_status=MODEL_INVALID`、allocation=`[A 800000 (repay 2026-11-28), C 200000 (2026-11-25)]`、failing_scenarios=[]；期望 allocation=[]，被拒分配只出现在诊断字段中。 | v1 冻结前修改：非可执行状态一律 `allocation=[]`，被拒分配放进独立的诊断字段（如 `verification.rejected_allocation`）。schema 增加条件：business_status 不属于可执行集合时，allocation 的 maxItems 为 0。T-009：plan_allocations 只写可执行状态的分配；API-53 采纳前校验 business_status。 |
| R3E-03 | major | C / D | `cash.py:90–103` `apply_scenario`（先改日期/金额）与 `cash.py:106–127` `build_timeline`（后按快照日判断"已反映"）；PoC 继承 | 快照是否已反映某个事件，是针对原始事件的事实判断，现在却用情景变换后的日期来判断。(a) 快照前的事件（视为已反映），或快照当日且列在 `includes_event_ids` 中的事件，如果是预计收入，被 `income_delay_days` 或 override.on 移到快照之后，就会再计入一次；(b) 快照后的事件（未反映）被 override 移到快照之前，会被当作已反映而丢弃。结果是压力情景可能比基准更乐观，"决策情景通过"和 FEASIBLE_ROBUST 可能是假的。 | P-DBL：现金 50,000（as_of 10-16），已包含当日工资 sal（+200,000，expected）；房租 −40,000（11-01）；卡 A（账单日 20，次月 8 日到期，11-08 还款）；消费 100,000；情景 baseline + stress（income_delay_days=3），决策情景 stress → CONDITIONALLY_FEASIBLE、A=100,000。基线期末余额：baseline 10,000，**stress 210,000**。期望 stress 与 baseline 相同，均为 10,000，决策情景 INFEASIBLE。工资日期改为 10-14（快照前），结果相同；用 override 把已包含事件移到 10-20，结果相同；用 override 把 11-01 的 −40,000 账单移到 10-10，该账单从情景中消失（期末 50,000，期望 10,000）。 | 在应用情景变换之前，用原始 `(on, id)` 判定"已反映"并剔除；对未反映的事件，若变换后日期早于快照日，按快照日计入（与 T-004b 中验证器处理计划还款的规则一致）。升 `model_version`；F-18 不受影响。补性质测试：只延迟或缩减收入的情景，任一检查点的余额都不高于基准情景。 |
| R3E-04 | major | C / G | `allocation.py:83–85`（capacity 只扣卡自身的 holds/reservations）、`allocation.py:281–288`（池约束用原始可用额）、`protocol.py:565–596`（`credit_account_id` 被读入，但不参与任何约束）；`Pools.schema.json`（"one pool level per card"）；PoC 继承 + 协议 | bank-rules-spec §5 要求"卡 ≤ 账户 ≤ 池，同时检查"，且预留与未计预授权都会减少可用容量。现状有三处缺口。(a) `credit_account_id` 被接受，但对容量没有任何作用：同一信用账户的主卡、附属卡各自携带银行显示的账户可用额，引擎会把两份都用掉。(b) 池约束用池的原始可用额，不扣池内各卡的 `reservations_minor`（其他已采纳计划的预留）和 `holds_uncounted_minor`，同池的另一张卡可以把已预留的额度再用一次。(c) 只支持一层池，账户层与银行池层不能同时表达（data-model 的 `credit_pools.parent_pool_id` 是多层）。 | P-CAP S1：两张卡 credit_account_id 都是 acc-1，各显示可用 600,000，消费 1,000,000（允许拆分）→ **FEASIBLE_ROBUST**，main 600,000 + supp 400,000；期望合计不超过 600,000，即 INFEASIBLE。S2：池 p 可用 1,000,000；池内卡 A 的 reservations 为 800,000；池内卡 B 显示可用 1,000,000；消费 1,000,000 → **FEASIBLE_ROBUST**，B=1,000,000；期望池剩余 200,000，即 INFEASIBLE。S3：把 reservations 换成 holds_uncounted，结果同 S2。 | v1 冻结前定案：(1) 按 `credit_account_id` 自动形成账户层容量；或者要求同账户的卡必须共享 pool，并在适配层校验，否则报 ProtocolError。(2) 池的新增消费容量 = max(0, available − Σ 成员卡 holds − Σ 成员卡 reservations)，或在 Pools 上增加 reservations/holds 字段。(3) 支持 `pool_ids` 列表（多层逐层约束）。在引擎支持之前，T-009 按账户建池，并拒绝无法表达的多层情况。 |
| R3E-05 | major | D / C | (a) `allocation.py:295–300`（零额标记事件没有 `at`）+ `cash.py:138`（只有当日全部事件都有 `at` 才按时间排序）；(b) `cash.py:96–102`（延迟后的收入保留原 `at`）；PoC 继承 | `same_day_order="timestamp"` 有两处语义错误。(a) 模型在每张可用卡的还款日放一个零额标记，标记没有时间戳，于是这一天在模型里退回保守顺序；而验证器和基线里没有未选用卡的还款事件，仍按时间戳排序。模型因此比验证器严格：明明存在通过验证的方案，仍报 INFEASIBLE（"证明无解"不成立）；只多加一张卡，FEASIBLE_ROBUST 就变成 INFEASIBLE，拒绝原因还同时写着 A"DOMINATED（单卡可行）"。(b) 收入延迟后仍带原来的 `at`（比新日期早几天），在新日期里排在所有支出之前，等于假定它在当日最早到账；压力情景反而取了最乐观的位置。 | P-TS1：余额 10；11-08 收入 +20@09:00、账单 −25@18:00；情景按 timestamp 排序；卡 A 11-28 还款，卡 B 11-08 还款；消费 3。只有 A → FEASIBLE_ROBUST，A=3。A、B 都在 → **INFEASIBLE**（拒绝原因 A DOMINATED、B CASH_BREACH_ALONE），而对同一文档执行 `verify_from_protocol(A=3)` 得到 ok=true、最低余额 2。期望两种情况都是 FEASIBLE_ROBUST，A=3。P-TS2：余额 10；预计工资 +20，11-05@09:00；账单 −15，11-08@10:00；stress 延迟 3 天。timestamp 顺序下 stress 基线 ok，结果 FEASIBLE_ROBUST；conservative 顺序下为 BASELINE_SHORTFALL（最低 −5）。期望 timestamp 顺序下同样视为失败。 | (a) 模型检查点的低点必须与验证器同义：零额标记不参与"当日全部有 at"的判断；或者 timestamp 情景下计划还款统一按"当日最后"处理，验证器与 Dart 端用同一规则。(b) 被情景改动日期的事件丢弃 `at`，退回保守顺序；或把 `at` 平移相同天数，并写进 schema。补性质测试：timestamp 情景下增加一张卡，不得使原本可行的问题变为不可行（test-plan §3 单调性）。 |
| R3E-06 | major | F | `allocation.py:415–420`（num_workers=8，没有确定性的并列处理）、`allocation.py:477–542` 分层求解；`tests/engine/test_determinism.py` 只用 F-18（最优解唯一） | 最后一层求解之后仍有多个并列最优解时，CP-SAT 多线程返回哪一个取决于线程竞速，与固定 seed 无关。同一输入（同一 input_hash，seed=0，workers=8）重复运行会得到不同的分配，敏感性中的 allocation 也会变化。engine-spec §7/§11 与 ADR-004 以"固定 seed 以利复现"为前提；T-004 证据中"全部重复一致"只对 F-18 成立。 | P-DET：30 张近似相同的卡、2 个账户、60 个事件（`probe_determinism_big.py`，事件种子 5），消费 15,500：cash_safety 跑 20 次得到 **4 种分配**（各层目标值完全相同），fewer_cards 得到 3 种；workers=1 时只有 1 种。随机实例共重跑 1,120 次，其中 2 次敏感性分配不同：种子 105 第 10 例 `max_affordable_amount.allocation` 在 A 与 D 之间变化；种子 203 第 200 例 `min_extra_confirmed_cash.allocation` 有 3 种取值。期望：相同输入得到相同的分配和结果文档。 | 增加最后一层确定性的并列规则（例如最小化 Σ rank_i·x_i，rank 取卡在输入中的顺序），使最优解唯一；敏感性求解同样加并列规则，或用单个 worker；或者改用 CP-SAT 的确定性搜索参数，并写进 run record。determinism 测试加入并列解丰富的实例。 |
| R3E-07 | major | B | engine-spec §3.8（现金约束不含费用）；`verifier.py:52–67`（计划还款金额 = −amt）；`allocation.py:314–327`；费用只进入目标函数（`allocation.py:341–354`）；规格缺口，PoC 继承 | 费用（费率部分向上取整，加固定费）记在卡上，会随账单一起由现金还款，但模型和验证器中的还款额只等于分配金额。存在费用时，现金底线这一硬约束少算了费用：绿色"稳妥"的方案可能在还款日透支，缺口正好等于费用。这违背 engine-spec §4"任何收益都不能抵消逾期或现金不足"的分层原则。 | P-FEE：现金 10,000，用卡 A 消费 10,000（fee_rate 0.006、fee_fixed 1,000，费用 1,060）→ **FEASIBLE_ROBUST**，最低现金 0；期望还款 11,060，缺口 1,060，不应判为可行。 | 先由规格决定费用的现金口径：随该卡还款扣除，或在交易当日从现金扣除。然后把模型中的还款项改为 x_i + f_i（f_i 已是整数变量，约束仍为线性），验证器同步修改；升 `model_version`。F-18 费用为 0，不受影响。 |
| R3E-08 | major | D / E | `plan.py:306–317`（按"可用卡"的最晚还款日延长 horizon，之后基线、模型、验证都用延长后的区间）；`verifier.py:88`（无求解器的验证路径只按所验证分配的还款日延长）；PoC 继承 | `horizon_end` 早于某张可用卡的还款日时，基线、求解和各情景验证所纳入的事件，取决于"哪些卡可用"。一张与所选方案无关、甚至根本用不上的卡是否可用，会改变 BASELINE_SHORTFALL、FEASIBLE_ROBUST 与 CONDITIONALLY_FEASIBLE 的判定。服务端运行与无求解器的验证路径（T-022 Dart 本地验证器的依据）对同一分配会得出不同结论。 | P-HZN：horizon_end 11-30；卡 A（容量 1,000，11-08 还款），卡 B（容量 50，12-28 还款，用不上）；现金 500；12-15 有账单 −450；消费 100。卡为 [A,B] 时 → **INFEASIBLE**（notes："horizon extended … to 2026-12-28"）；只有 [A] 时 → FEASIBLE_ROBUST，A=100；对同一 [A,B] 文档执行 `verify_from_protocol(A=100)` 得到 ok=true。PoC↔生产随机对照中，有 4 例状态翻转仅仅因为池截零改变了某张卡的可用性。例如 #1345：两边分配都是 B=8，PoC 为 CONDITIONALLY_FEASIBLE（stress0 在延长区间内失败），生产为 FEASIBLE_ROBUST。 | 让检查区间只取决于输入本身：要求 `horizon_end` 不早于所有卡（含不可用卡）可能的最晚还款日，否则返回 NEEDS_DATA；或固定取 txn_date + 规格上限（如 180 天）；无求解器的验证路径用同一规则。修正之前，T-009 把 horizon_end 设为 ≥ txn_date + 180 天。 |
| R3E-09 | minor | E | `plan.py:80–101` `baseline_check`（只看各账户）；`allocation.py:328–339`；PoC 继承 | 基线检查不看 `global_reserve_floor`，而模型把"无计划项的全局检查点不满足"编码为不可行。于是决策情景的基线已经违反整体底线时，结果是 INFEASIBLE（还附带敏感性），而不是 §3.9/§5 规定的 BASELINE_SHORTFALL；`baseline[s].ok` 同时为 true。差分中共有 516 次基线违反全局底线未被报告，其中 180 次发生在决策情景，全部输出 INFEASIBLE。 | 差分 C3 注记，例：种子 11 第 91 例，全局底线 20，基线在 06-04 合计 16 → INFEASIBLE。 | `baseline_check` 计入全局底线，口径与验证器相同。 |
| R3E-10 | minor | C / E | `plan.py:133–187` `rejection_reasons`；PoC 继承，池部分涉及 T-004b | INSUFFICIENT_LIMIT_ALONE 只比较 capacity。当单卡受 per_txn_cap、池可用额或卡级 min_split（大于消费额）限制时，仍只用现金检查给出 CASH_BREACH_ALONE 或 DOMINATED；DOMINATED 的文字是"单卡可行，但在目标层上更差"。INFEASIBLE 与 UNKNOWN 的解释因此自相矛盾。差分审计中，共有 671 次 DOMINATED 所对应的卡单独使用在结构上不可行。池耗尽时给出的 NO_CAPACITY 也没有指明原因在池。 | P-CAP S4/S5/S6（池 500,000 / 单笔上限 500,000 / 卡级 min_split 900,000，消费 800,000）→ INFEASIBLE，同时 A 为 DOMINATED。P-UNK：time_limit 1e-9 → UNKNOWN，B 为 DOMINATED "scored lower on the objective tiers"，而任何目标层都没有运行。 | 按 engine-spec 的 cap_i = min(capacity, per_txn_cap, …) 和池可用额判断 INSUFFICIENT_LIMIT_ALONE；单卡检查用 `verify().ok`（含结构约束）；min_split 大于金额时单列原因；DOMINATED 只在求解器给出可行解时使用，UNKNOWN 下改为"未在时限内比较"；NO_CAPACITY 增加 detail（pool_id）。 |
| R3E-11 | minor | F / G | `protocol.py:802–806` `_decimal_text`；Rate 模式 | 利率字符串没有规范形式。ADR-008 的 NUMERIC(20,10) 读出来是 `Decimal('0.0060000000')`、`Decimal('0E-10')`、`Decimal('1.0000000000')`，这些全部被 `inputs_to_protocol` 拒绝（ProtocolError）。同一利率写成 "0.006" 和 "0.00600"，得到的 protocol_input_hash 不同。 | P-DEC：上述三个值 → ProtocolError "outside the v1 range"；同一利率 0.006 与 0.00600 → 哈希不同。 | `inputs_to_protocol` 先规范化（去掉多余尾零，零写成 "0"）。README 规定 Rate/ScaleFactor 的规范写法，两端都在哈希前规范化，或都拒绝非规范写法。T-009 从数据库构造 PlanInput 时必须规范化。 |
| R3E-12 | minor | G | `protocol.py:300–307`（`_matching`）、`369–375`（`_enum`）、`391–397`、`508–511`、`331–362`；引擎直调路径 `allocation.py:480–482`（validate 报错原文进入 notes） | 金额的范围错误不回显数值（已验证），但其他校验错误会把原值写进消息：ID（客户端误把完整卡号放进 card_id 时，消息为 `'6222 0212 3456 7890' is not a valid id`）；枚举字段收到数字或对象时整段回显（`cls: 123456789`、`profile: {"balance_minor": 98765432}`）；protocol_version、time_limit、currency、rate、日期也会回显。引擎直调路径上，CP-SAT `validate()` 的报错原文（含系数与常数）会进入 notes。 | P-ECHO（§4.7）。 | 消息只给路径、类型和长度（如 "not a valid id (length 19)"），不回显值；或对 VALIDATION_ERROR 统一做 PAN 掩码（与 R2-09 的 looks_like_pan 一致）。validate 失败时 note 只写 "CP-SAT model validation failed"。 |
| R3E-13 | minor | G | `protocol.py:1250–1257` `verify_from_protocol` | 有些文档协议上合法，`plan()` 会给出 NEEDS_DATA，但在无求解器的验证路径上直接抛异常：缺快照 → LookupError（"NEEDS_DATA: …"）；规则需要工作日日历 → ValueError。fixture 运行器的 verify case 只捕获 ProtocolError，遇到这种文档会以 traceback 退出；T-022 的 Dart 验证器也没有可对照的语义。 | P-VER：F-18 去掉快照 → LookupError；holiday_rollover=next_business_day → ValueError（plan_from_protocol 对两者都返回 NEEDS_DATA）。 | `verify_from_protocol` 先执行 data_issues，返回结构化的 NEEDS_DATA（或抛 ProtocolError），并把这条规则写进 README 的双端规则。 |
| R3E-14 | minor | G | `protocol.py:750–762`（只检查"属于本账户的已有事件"）；`_event`（`at` 与 `on` 不做一致性校验） | Snapshot schema 写明 `includes_event_ids` 列的是"dated as_of"的事件，但适配层不检查日期。如果列入一个快照日之后的事件，引擎照常再计一次，而文档声称余额已经包含它；这属于"静默误读"。另外，`at` 的日期可以与 `on` 任意不同。 | P-DBL case 5：as_of 10-16，includes 中列入 10-17 的工资 +200,000 → 被接受，结果 FEASIBLE_ROBUST，基线期末 210,000；期望 ProtocolError。 | 适配层拒绝 includes 中 on ≠ as_of 的事件；`at` 的本地日期与 `on` 不一致时拒绝，或要求给出时区规则。写进 README，Dart 端同步实现。 |
| R3E-15 | minor | F / E | `plan.py:228–268` | (a) 直接调用 `plan()` 时，默认 input_hash 取 `ModelInputs.input_hash()`，不含情景和选项：同一份数据换决策情景或画像，结果不同而哈希相同。README 已说明这一点，但 run record 的字段名相同，T-009 容易误用。(b) BUILD_ERRORS 兜底覆盖所有阶段，任何 ValueError/TypeError（包括 R3E-01 这类程序缺陷）都被报告为"超出支持范围"，与 README"经协议进入…到不了这一步"的说法矛盾。 | P-EFF；README "超出引擎能力的输入不会让引擎抛异常"一段。 | (a) 引擎默认哈希改为覆盖情景与选项，或强制 T-009 走 `plan_from_protocol`；(b) 见 R3E-01，兜底 note 只写"内部错误 + 阶段"，并修正 README 的不可达说法。 |
| R3E-16 | minor | H | `tests/engine/*`、`tests/protocol/*` | 存活的变异体（§4.8）：M05（`repay_on <= txn_date` 也判为早于交易日，没有相等边界的测试）、M14/M15（验证器的费用向下取整、收益向上取整，没有测试）、M17（模型不读 verified_benefit_cap，没有测试）、M20（快照过期边界）、M26（加权缓冲天数的取整方式）。determinism 测试只覆盖最优解唯一的 F-18。`test_robustness.py:160` 中 `result.get("detail", "MODEL_BUILD_ERROR").startswith(...)` 在没有 detail 时会空洞通过。 | 本审查的差分测试能杀死 M05、M14、M15、M17（§4.8）。 | 补边界测试（repay_on == txn_date 时可用；快照年龄 = stale_after_days 时不算过期）和取整方向测试（非整数费用向上、收益向下、收益上限进入模型）；把差分/性质测试（或对应的 hypothesis 版本）纳入 tests/engine；determinism 测试加入有并列解的实例；去掉 `get` 的默认值。 |
| R3E-17 | minor | E | `allocation.py:599、634、664–665` | 敏感性求解的时限是写死的（5 s、5 s、45×1 s），不受 `options.time_limit_s` 约束，而且每个失败的压力情景各算一次。run record 中的 `time_limit_s` 并不是运行总时长的上界。 | 代码阅读。 | 给敏感性分配总预算（如 time_limit_s 的固定比例）并记录在 run record 中。T-009 的 worker 超时按"主求解 + 每个敏感性情景 ≤ 55 s"估算，或把敏感性改为异步计算。 |
| R3E-18 | nit | G | `PlanOutcome.schema.json:55`；bank-rules-spec §5 | solver_status 的描述"NOT_RUN when no solver ran (NEEDS_DATA, BASELINE_SHORTFALL)"未包含"无可用卡"的 INFEASIBLE，以及建模前阶段产生的 MODEL_INVALID。bank-rules-spec §5 说 capacity_for_new_spend 是"唯一允许截零的派生值"，没有提到池截零。 | — | 更新这两处描述。 |
| R3E-19 | nit | C | `plan.py:345–369`；engine-spec §5 | 无可用卡时 INFEASIBLE 的 sensitivity 为空。min_extra_cash 和 max_affordable 在没有可用卡时本就无意义，这是合理的。但如果排除原因是 REPAY_BEFORE_TXN_DATE，推迟消费日期可能让卡重新可用，first_feasible_date_shift 仍有信息量。另外 §5 表格写"解释 + 敏感性"，伪代码写"+ rejections"，两处略不一致。 | — | 排除原因都与日期有关时，可以只计算 date-shift；同时统一 §5 表格与伪代码的写法。 |
| R3E-20 | nit | G | `common.schema.json` Timestamp | 现有 pattern 接受 "2026-10-16T99:99:99+99:99"；当前 jsonschema 安装没有启用 date-time 格式检查（FormatChecker 中没有 date-time，需要 rfc3339-validator），所以 schema 接受而适配层拒绝。 | P-TS3。 | 收紧 pattern（小时 00–23、分 00–59、秒 00–60），或在 README 写明适配层必须解析校验。 |
| R3E-21 | nit | G | `protocol.py:322–328`；README | Text 的 maxLength 在 Python 和 JSON Schema 中按码点计数，而 Dart 的 `String.length` 按 UTF-16 码元计数；同一份含 emoji 的文本，两端判定可能不同。 | — | README 写明按码点计数；T-022 用 `runes.length`。 |
| R3E-22 | nit | G | `common.schema.json` MinorAmount | 标准 JSON Schema 下，金额字段接受 `1000000.0` 这样的整值浮点（integer 按数学值判定）。本仓库的运行器和适配层都拒绝，README 已说明。 | `test_standard_json_schema_admits_an_integral_float…` | T-022 若使用通用校验库，必须同样重定义 integer 类型；在 README 的"Dart 端"一节显式要求。 |

---

## 3. 已核验无问题的要点

**A. golden 一致性**
- F-18 人工 fixture 路径（`load_fixture → plan`）与 PoC 对照：3 种画像 × 3 个决策情景（baseline / stress_income_delay / confirmed），PlanOutcome 的全部字段逐一一致，包括分配、求解层的状态/值/界、各情景检查与缺口点、分配行、拒绝原因、敏感性、假设和 notes（只屏蔽 run_id、created_at、墙钟时间）。`ModelInputs.input_hash` 两边相同（`50b7df30…c8ed24c`）。生产端新增的 run record 字段：model 1.0.0、workers 8、seed 0。
- 协议路径（`plan_from_protocol` 读 v1 fixture）与"PoC 结果经 `outcome_to_protocol` 转换后的文档"对照：9 组，差异 0。`protocol_input_hash` = `ea990327…1ee8`，与 README 一致。
- 随机 1,500 个实例上 PoC 与生产对照：1,220 个完全一致；其余 280 个差异全部来自有意的修改（REPAY_BEFORE_TXN_DATE 55 个、池截零 81 个、无可用卡由 MODEL_INVALID 改为 INFEASIBLE 144 个），没有意外差异。其中 PoC 为 FEASIBLE_ROBUST、生产为 INFEASIBLE 的例子，都是 PoC 把"早于交易日的还款"当作快照已反映而跳过（PoC 的缺陷），生产的结果是对的。

**B. 金额语义**
- 11,200 份结果文档中，计时字段以外没有任何浮点数；所有金额都是整数，`weighted_buffer_days` 是字符串。
- 3,941 个最优分配（含金额 ×10007 的非整值场景）的分配行与独立实现一致：费用向上取整加固定费、已核实收益向下取整并受上限约束、潜在收益向下取整；情景缩放 HALF_UP；分期尾差记在末期（money 模块未改，变异体 M19 被杀死）。
- 超出最小单位的精度一律拒绝而不是取整：`to_minor` 拒绝 123.455 CNY、1.5 JPY、1.2345 KWD；协议拒绝超过 5 位小数的利率和超过 10 位小数的系数；`inputs_to_protocol` 遇到超范围利率报错，不取整。
- 范围推导成立。在 6 个极限变体 × 3 种模型（主模型、补充现金、最大可负担）上实测 CP-SAT proto：线性约束的 Σ|系数|·max|变量| 最大为 3.000e18 = **0.651 × 2^62**（费用约束，费率 0.99999），常数项 ≤ 1.001e18，目标 ≤ 9.44e17，`validate()` 全部通过，与 README 表中约 1.5 倍余量的结论一致。575 份边界合法文档的 fuzz：没有未捕获异常，没有 CP-SAT 层面的 MODEL_INVALID；唯一的异常路径是 R3E-01。

**C. 新规则**
- REPAY_BEFORE_TXN_DATE 的边界正确：还款日等于交易日时可用（缓冲 0，含跨年：2026-12-31 交易、2027-01-05 到期、提前 5 天）；提前 6 天被拒绝；闰年 2028-02-29 正确；还款日等于快照日时当日扣减，余额不足报 CASH_BREACH_ALONE。
- 验证器对早于快照日的计划还款按快照当日计入，并记结构违规 PLANNED_REPAYMENT_BEFORE_SNAPSHOT（ok=false）。这已是可观测范围内最早的一天，属于保守但不过度的处理。它不会与 includes_event_ids 重复计算：`plan_repay_` 前缀被协议保留，includes 只能引用已有事件；只有在引擎直调、手工构造 Snapshot 时才可能让 includes 含 "plan_repay_X"。在 `plan()` 中这种情况不可达（快照日 ≤ 交易日 ≤ 还款日）。
- 池可用额 ≤ 0 时，池内的卡报 NO_CAPACITY，池外的卡不受影响。模型和验证器中的 `max(0, …)` 截零是冗余的（变异体 M09/M10 与原代码等价），但无害。
- 无可用卡时：在 1,456 个随机实例上全部得到 INFEASIBLE / solver NOT_RUN / note NO_ELIGIBLE_CARDS，且每张卡都有正确的排除原因；判定顺序（排在 BASELINE_SHORTFALL 之后）与 engine-spec §5 第 60 行一致。

**D. 求解器与验证器一致性**（§4.4，共 11,200 个随机实例）
- verify(solve(x)) 必然通过：3,941 个最优解中违例 0，从未出现 VERIFIER_REJECTED。
- 完备性：求解器报 INFEASIBLE 时穷举找不到可行分配（2,292 个），随机实例中失配 0；反例只在定向构造中出现（R3E-05）。
- 字典序最优：在保守顺序的决策情景上做了 2,227 次检查，各层目标值与穷举得到的最优向量完全一致。
- 随机分配下，验证器的 ok、structural_ok、各情景最低余额与缺口点，与逐约束手算一致：9,485 例，失配 0。
- FEASIBLE_ROBUST 当且仅当所有情景检查和所有基线都通过，failing_scenarios 与参考实现一致：失配 0。

**E. 状态语义**
- 判定顺序与 §5 伪代码一致：NEEDS_DATA → BASELINE_SHORTFALL → 无可用卡 INFEASIBLE → 求解 → INFEASIBLE / UNKNOWN / MODEL_INVALID → 验证 → MODEL_INVALID（VERIFIER_REJECTED_SOLVER_SOLUTION）→ FEASIBLE_ROBUST / CONDITIONALLY_FEASIBLE。
- UNKNOWN 不会被写成无解：notes 写明 "NOT a proof of infeasibility"，不附分配和敏感性。敏感性内部的 UNKNOWN 同样如实标注。
- 没有运行求解器的结果（NEEDS_DATA、BASELINE_SHORTFALL、无可用卡），solver_status 为 NOT_RUN，wall_time 为 null。

**F. 可复现性**
- canonical JSON：键按 UTF-16 码元排序（变异体 M23 被杀死），转义规则与 JCS 一致，ECMAScript 数字格式（含 1e-7、1e21、2^68）、拒绝孤立代理项、严格解析（重复键、NaN、BOM、超长整数、嵌套过深都被拒绝），均已核对。
- input_hash 取的是调用方的原始输入，在 horizon 延长之前计算（M02 被杀死）；协议运行传入 protocol_input_hash（M24 被杀死）；workers/seed 传给每一次 CP-SAT 调用（M03 被杀死）；run_id 贯穿整次运行（M27 被杀死）。
- F-18 和小规模随机实例可以复现（1,120 次重跑中 1,118 次一致）；不可复现的情况见 R3E-06。

**G. 协议 v1**
- 所有对象都是封闭的；JSON 数字只出现在 time_limit_s 和 wall_time_s；利率和系数只能是字符串。
- engine-spec §2 中引擎尚未支持的字段（daily_cap、temp_limit_expiry、future_releases、available_from、merchant/category/allow_installment/reserve_*）一律按未知成员拒绝。
- 金额范围错误只给出上下界，不回显数值。
- PlanOutcome 是 API-52 字段的超集：run_id、solver_status/business_status、带 `*_minor` 的分配行、repay_from_cash_account_id、weighted_buffer_days（字符串）、checks、failing_scenarios、rejections、sensitivity、assumptions、input_hash、model_version、solver_version、protocol_version、time_limit_s、wall_time_s、created_at。
- 11,200 份输出全部通过严格整数类型的 `PlanOutcome.schema.json` 校验。

**H. 测试质量**
- T-004/T-004b 声称的每项修正，回退后都有测试失败：M01–M04、M06–M08、M11–M13、M21–M24、M27–M30 均被杀死。
- 测试大多断言具体的值、指针和消息；本次只发现一处空洞断言（见 R3E-16）。

---

## 4. 实验命令、种子与结果摘录

公共前缀：`PY=/projects/cardflow/services/api/.venv/bin/python`；`R=/tmp/cardflow-review-engine`；以下命令都在 `$R` 下执行，`PYTHONPATH=$R/services/api`（PoC 对照时再加上 `:$R/poc/engine_reference`）。

### 4.0 副本与基线
```
tar --exclude=.venv --exclude=.hypothesis --exclude=.pytest_cache --exclude=__pycache__ --exclude=.ruff_cache \
    -cf - services packages poc docs evidence | (cd $R && tar -xf -)
cd $R/services/api && PYTHONPATH=$PWD $PY -m pytest -q tests/engine tests/protocol -p no:cacheprovider   → 310 passed
$PY packages/rules-protocol/runner_py/run_fixtures.py   → result: PASS (23/23 assertions hold) … exit 0
$PY packages/rules-protocol/runner_py/convert_legacy_fixture.py …/regression_2026-10-16_10000.json --check → identical (12977 bytes)
```
AST 比对（`scripts/astdiff.py`、`fielddiff.py`）：money/billing/cash/fixture 与 PoC 相比只有导入和注解变化（`Optional[X]` → `X | None`）；行为变化只出现在 allocation（ineligible_reason、build_model、solve、敏感性函数）、verifier（check_scenario、verify）和 plan（plan/_plan、rejection_reasons），以及新增的 protocol。

### 4.1 A · golden
- `scripts/golden_compare.py` → 人工路径 9 组、协议路径 9 组，`TOTAL DIFFS: 0`；PoC 与生产的 input_hash 都是 `50b7df309486409ba99b4a241d7d7996669b8a1f5aa1a3e9e1062aa39c8ed24c`。
- `scripts/poc_vs_prod_random.py 401 1500` → identical 1220；REPAY_BEFORE_TXN_DATE 55、池截零 81、无可用卡 144；`UNEXPECTED` 0。`poc_vs_prod_explain.py` 中的 #688、#1138、#1205、#1345 是 R3E-08 的实例。

### 4.2 B · 金额与范围
- `scripts/limits_proto_scan.py`：以 `tests/protocol/test_limits.py::_worst_case_document` 为基础构造 6 个变体（10k 支出 ×10 / 10k 收入 ×10 / 支出分散到 100 个账户 / 全部事件 override 为 −1e13 / 费率 0.00001 / 费率 0.33333 与 0.99999），每个变体建 3 种模型，扫描 `model.proto`：
  `max_linear=3.000e+18 (0.651 of 2^62) max_const=1.000e+18 objective=9.440e+17 validate=OK`（各变体最大值；0.00001 费率时为 0.434）。
  注意：OR-Tools 9.15 的 proto 包装对象不支持负下标，`v.domain[-1]` 会返回 `domain[0]`；扫描时必须用 `list(v.domain)[-1]`。
- `scripts/fuzz_exceptions.py 7 600`：600 份文档，其中生成器产生的非法文档 25 份已跳过；合法文档的结果为 BASELINE_SHORTFALL 146、CONDITIONALLY 20、ROBUST 107、INFEASIBLE 166、NEEDS_DATA 124、UNKNOWN 5、**MODEL_INVALID 7（全部是 "ValueError during sensitivity"，即 R3E-01）**；未捕获异常 0。
- P-FEE（`probe_fee_cash.py`）：`cash 10,000; spend 10,000 on A with fee 1060 … FEASIBLE_ROBUST, min cash {'cash': 0}`。
- P-DEC（`B_minor_unit_probe`）：`to_minor('123.455','CNY') -> ValueError`；`Decimal('0.0060000000') -> ProtocolError … outside the v1 range`；`0.006 vs 0.00600 -> same protocol_input_hash? False`。

### 4.3 C · 新规则与额度
- P-EFF（`probe_effective_to.py`、`probe_effective_to2.py`）：
  `decision=baseline: business_status=MODEL_INVALID solver_status=OPTIMAL allocation=[] … notes: ['MODEL_BUILD_ERROR: ValueError during sensitivity (…)']`；去掉 effective_to 作对照 → `CONDITIONALLY_FEASIBLE allocation=[('A', 800000), ('C', 200000)]`。
- P-DBL（`probe_double_count.py`，最小文档在脚本内：单账户、卡 A 账单日 20、次月 8 日到期）：
  case 1 `CONDITIONALLY_FEASIBLE … {'baseline': (10000, 10000), 'stress': (50000, 210000)}`；case 2（工资在快照前）同 case 1；case 4（override.on）同 case 1；case 5（includes 列入次日事件）`accepted; FEASIBLE_ROBUST … (50000, 210000)`；case 6（override 把账单移到快照前）`'early_bill': (50000, 50000)`。
- P-CAP（`probe_capacity.py`）：S1 `FEASIBLE_ROBUST allocation=[('main', 600000), ('supp', 400000)]`；S2/S3 `FEASIBLE_ROBUST allocation=[('B', 1000000)]`；S4/S5/S6 `INFEASIBLE rejections=[('A', 'DOMINATED', 'feasible alone but scored lower on the objective tiers')]`。
- P-RB（`probe_repay_boundary.py`）：`lead 5 -> repay 2026-12-31 == txn … FEASIBLE_ROBUST … buffer 0`；`lead 6 … INFEASIBLE rejections [('A', 'REPAY_BEFORE_TXN_DATE')]`；`balance 20 < 30 … INFEASIBLE [('A','CASH_BREACH_ALONE')]`；闰年 `due 2028-02-29`。

### 4.4 D · 差分与性质实验
生成器 `scripts/gen.py`（种子由 `random.Random(seed)` 决定）：交易日跨整年（含 12 月→1 月）；1–4 张卡（固定日/账单后 N 天两种规则、inclusive 开关、入账延迟、池、单笔上限、卡级最小拆分、费率/固定费/收益率/收益上限，偶尔不可用）；1–3 个现金账户（储备、受限账户）；0–20 个事件（confirmed/expected/planned，living/bill/income 等类别，部分带时间戳）；快照 includes 随机子集；2–4 个情景（confirmed、baseline、带延迟/缩放/override 的 stress，conservative 或 timestamp 顺序）；画像、决策情景和全局底线随机；约 3% 的实例故意缺快照或池条目、规则非法或快照过期。参考实现 `scripts/ref.py` 不导入 cardflow。驱动脚本 `scripts/diff_test.py SEED N` 执行检查 C1–C12：C1 输入/输出 schema 校验与浮点扫描；C2 NEEDS_DATA；C3 基线；C4 无可用卡；C5 可靠性；C6 完备性（穷举）；C7 字典序最优；C8 状态；C9 校验数字与分配行；C10 拒绝原因；C11 随机分配下的验证器；C12 重跑一致。

| 组 | 命令 | 实例 | 评估（无数据问题） | OPTIMAL / INFEASIBLE | C7 | C11 | C12 | 失配 |
|---|---|---|---|---|---|---|---|---|
| 基础 | `diff_test.py {11,12,13} 400` | 1,200 | 974 | 411 / 246 | 335 | 1,015 | 120 | 0 |
| 基础 | `diff_test.py {101..105} 1000` | 5,000 | 4,114 | 1,765 / 1,039 | 1,502 | 4,230 | 500 | C12 ×1 |
| 时间戳为主 | `TS_RATE=1.0 diff_test.py {201,202,203} 1000` | 3,000 | 2,493 | 1,056 / 600 | 390 | 2,512 | 300 | C12 ×1 |
| 金额 ×10007，不穷举 | `NO_BRUTE=1 MONEY_SCALE=10007 diff_test.py {301,302} 1000` | 2,000 | 1,640 | 709 / 407 | — | 1,728 | 200 | 0 |
| **合计** | | **11,200** | 9,221 | 3,941 / 2,292 | 2,227 | 9,485 | 1,120 | C12 ×2（R3E-06） |

注记（不是失配，而是与规格不符的行为）：基线违反全局底线但 baseline.ok 未反映，共 516 次，其中决策情景 180 次，全部输出 INFEASIBLE（R3E-09）；DOMINATED 对应的卡单独使用时结构不可行，共 671 次（R3E-10）。

定向探针（随机生成碰不到的条件）：
- P-TS1/P-TS2（`probe_timestamp.py`）：`cards [A] -> FEASIBLE_ROBUST … allocation=[('A', 3)]`；`cards [A, B] (B repays 11-08) -> INFEASIBLE`；`verify_from_protocol(A=3) … ok=True, min={'cash': 2}`；`order=timestamp: stress baseline ok=True min=10 -> FEASIBLE_ROBUST`；`order=conservative: … min=-5 -> BASELINE_SHORTFALL`。
- P-HZN（`probe_horizon.py`）：`plan, cards ['A','B']: INFEASIBLE … horizon extended from 2026-11-30 to 2026-12-28`；`plan, cards ['A']: FEASIBLE_ROBUST allocation=[('A', 100)]`；`verify_from_protocol(A=100) … ok=True`。

### 4.5 E · 状态
- P-MI（`probe_model_invalid.py`，注入验证器拒绝）：`business_status: MODEL_INVALID | solver_status: OPTIMAL`；`allocation lines: [('A', 800000, '2026-11-28'), ('C', 200000, '2026-11-25')]`；`failing_scenarios: []`。
- P-UNK（`probe_unknown.py`，F-18，余额 5,000,000，time_limit 1e-9 或 1e-6）：`business=UNKNOWN solver=UNKNOWN allocation=[]`，notes 为 `time limit reached before any solution; this is NOT a proof of infeasibility`，拒绝原因中 `('B', 'DOMINATED', 'feasible alone but scored lower on the objective tiers')`。

### 4.6 F · 哈希与确定性
- 小规模并列实例（`probe_determinism.py 30`，2/3/4 张相同的卡，workers 取 8 或 1）：均只有 1 种分配。
- `determinism_scan.py 21 300 10`：185 个实例各重跑 10 次，0 个出现变化；`… 22 150 10 sens`：80 个实例，0 个出现变化。
- P-DET（`probe_determinism_big.py 20 cash_safety|fewer_cards [workers]`）：`workers=8 cash_safety: 4 distinct allocation(s); 1 distinct tier vectors`；`fewer_cards: 3`；`workers=1: 1`。
- `probe_nondeterminism.py 40 out/F_nondeterministic_doc{,2}.json`：`workers=8: 2 distinct outcome(s) … /sensitivity/baseline/max_affordable_amount/allocation/A: 4 != None`；第二个实例 `3 distinct … min_extra_confirmed_cash/allocation`；`workers=1: 1`。

### 4.7 G · 协议
- schema 扫描：所有对象都设了 `additionalProperties:false`，或是 propertyNames 映射；`type: number` 只出现在 `Options.time_limit_s`、`PlanOutcome.time_limit_s`、`wall_time_s`、`tiers[].wall_time_s`。
- P-ECHO（`probe_protocol_echo.py`，节选）：`/events/0/cls: 123456789 is not one of [...]`；`/options/profile: {'balance_minor': 98765432} is not one of [...]`；`/cards/0/card_id: '6222 0212 3456 7890' is not a valid id`；金额字段只返回 `must be an integer in [1, 10000000000000]`（不回显数值）。
- P-VER（`probe_verify_path.py`）：`missing snapshot: UNCAUGHT LookupError`；`rule needs calendar: UNCAUGHT ValueError`（`plan_from_protocol` 对两者都返回 NEEDS_DATA）。
- P-TS3：`2026-10-16T23:59:60Z` 与 `T24:00:00Z` 的结果都是 `schema accepts | adapter rejects`；`T99:99:99+99:99` 的 schema errors 为 []；`date-time format checked by this jsonschema install: False`。

### 4.8 H · 变异测试
`scripts/mutants.py`（30 个单点变异）+ `scripts/run_mutants.sh NAME`：每个变异体在独立副本 `$R/mut/NAME` 中执行 `pytest tests/engine tests/protocol -x`，4 个并行，总耗时 65 s。

| 变异体 | 结果 |
|---|---|
| M01 验证器遇未知卡号崩溃、M02 哈希改为延长后计算、M03 敏感性不传 workers/seed、M04 去掉 REPAY_BEFORE_TXN_DATE、M06 验证器跳过早于快照日的还款、M07 不记违规、M08 不排除池耗尽的卡、M11 验证器截断浮点、M12 兜底失效、M13 无可用卡改回 MODEL_INVALID、M16 模型费用向下取整、M18 情景缩放改 HALF_EVEN、M19 分期尾差记首期、M21 金额上限改为 int64、M22 利率允许 6 位小数、M23 键按码点排序、M24 协议运行使用引擎哈希、M27 run_id 不传给 solve、M28 不做推迟搜索、M29 includes 允许他户事件、M30 验证器忽略池 | **被杀死（21）** |
| M09 模型不截零池、M10 验证器不截零池 | 存活，**等价变异**（池耗尽的卡在建模前已被排除） |
| M25 `solve()` 内判定不可用时不传 pools | 存活，近似等价（只少一条 solve note） |
| M05 `repay_on <= txn_date`、M14 验证器费用向下取整、M15 验证器收益向上取整、M17 模型忽略收益上限、M20 过期判定改为 `>=`、M26 缓冲天数取整改 HALF_EVEN | **存活，测试缺口**（R3E-16）。用本审查的差分测试（种子 11，400 例）可杀死 M05（C6/C7/C10）、M14（C9 ×66）、M15（C9 ×89）、M17（C7 ×5） |
