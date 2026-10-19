# I-1 阶段末审查报告（简报 R-I1）

- 日期：2026-10-19；审查开始时仓库 HEAD `13d72c0`（= origin/main）；审查期间主会话推送了 `43cd136` 与 `36d7819`（只有 docs：0.0.2 设计稿与简报 U-1、消费贷需求与简报 L-1；`git diff --stat 13d72c0 36d7819 -- apps .github packages services` 为空），被审查的代码不变，证据文件头的 HEAD 有 `13d72c0` 与 `43cd136` 两种。公测版 0.0.1 = 标签 `ios-v0.0.1` → `83be815`；`git diff --stat 83be815 13d72c0 -- apps .github packages services` 为空（发版之后只改了文档与证据，见 `review-i1/migration-check.txt`），所以本报告的结论就是对用户手里 0.0.1（构建 55）的结论。
- 只读审查：仓库内已有文件一律未改；新建的只有本报告与 `evidence/i1/review-i1/`（复现输出原文与探针、脚本副本）。临时文件都在 `/tmp/rv1/`。结束时的 `git status --short` 原文见文末。
- 结论：**blocker 2 条，major 3 条，minor 11 条，疑问 5 条。**两条 blocker 都是负债与应还的金额算错，都出在"账单之间、还款与账单日期之间"的关系上：R-01 已出账的消费再「转分期」→ 总负债把本金算两次；R-02 还款分配不看账单日的先后、旧账单不被新一期吸收 → 迟付时本期应还多算、补登早于账单日的还款时把仍欠的钱算成"已结清"、旧账单永远"已逾期"。三条 major：R-03 冲正后账单仍"已结清"、欠款从近期到期与逾期里消失（BL-29 比登记的更严重）；R-04 分期成本的有理数 IRR 在界面线程每次 build 重算，36 期约 0.4 s、60 期约 2.3 s（AOT 实测）；R-16 录错的交易与分期在界面上无法删除或作废（仓库方法已有、没有入口），R-01 发生后用户也无法撤销。迁移、隔离（唯一例外是 R-15 的界面路径）、追加只读的仓库路径、日期函数、分期算法与 Python 的一致性、CI 断言都核对无误（§3）。

## 1. 范围与方法

### 1.1 范围

`apps/mobile/`（App；领域包只看 `lib/src/installment.dart` 与测试，其余在 I-0 审查过、本次只在被 I-1 新用法触及时复核）、`.github/workflows/mobile.yml`、`evidence/i1/I1-a|I1-b|I1-c|release-0.0.1|device-0.0.1`。`services/api/` 只作语义基准（`money.py`、`cash.py`、`billing.py`）。I1-a、I1-b（现金数据层此前没有审查过）、I1-c/I1-c2 全部覆盖。

### 1.2 读过的对照依据

PRD §4.1–§4.3、§5（UF-1/UF-3/UF-5）、§6.1–§6.3、§10；ui-spec §1–§4、P-07（逐条）、§3.6 金额隐藏；data-model §3/§4/§10.14（经 README 的登记）；test-plan F-01~F-38 清单；security-privacy §3、§5、§6；ADR-001/008/015；briefs I1-a、I1-b、I1-c、I1-c2、review-i1；`apps/mobile/README.md` 全文（含三节"偏离与约定"）；backlog BL-01~BL-31；handoff；上次审查报告 `evidence/i0/review-i0.md`。

代码逐文件阅读：`lib/data/db/`（`schema.dart` 全部冻结语句：建表 25、索引 37、触发器 39、`app_database.dart`、`database_reset.dart`、`database_platform_io.dart`、`database_key.dart` 与 4d720c9 的差异）、`lib/data/repositories/` 全部仓库与读模型（重点 `ledger_reader`、`repayment_repository`、`statement_repository`、`installment_repository`、`transaction_repository`、`cash_event_repository`、`cash_forecast_reader`、`recurring_item_repository`、`workspace_repository`、`providers`）、`lib/data/mapping/`（三个映射文件）、`lib/data/time/`、`lib/data/validation/`、`lib/data/demo/`；界面里与金额、文案、表单、分配、隐私相关的部分（`statement_pages/forms`、`repayment_form_page`、`scenario_pages`、`cash_account_pages`、`about_page`、`public_beta`、`new_card_page`、`first_run_empty_state`、`tokens`、`app_theme`、`error_hooks`、`diagnostic_log`）；测试辅助 `db_test_support`、`repository_test_support`、`test_helpers`、`forbidden_ui`、`sensitive_text`、`schema_test`、`workspace_isolation_test`、`accessibility_test`。Python 对照：`money.py` 的 4 个分期函数、`cash.py` 的情景变换与快照包含。

### 1.3 运行了什么（命令原文；输出见 §5）

基线（`export PATH=/opt/flutter-sdk/bin:$PATH`）：

```bash
cd apps/mobile && dart format --output=none --set-exit-if-changed . && flutter analyze --fatal-infos && flutter test --reporter expanded      # 489 项全过
cd apps/mobile/packages/cardflow_domain && dart format --output=none --set-exit-if-changed . && dart analyze --fatal-infos && dart test --reporter expanded   # 279 项全过
```

探针都放在 `evidence/i1/review-i1/scripts/`，在 `apps/mobile` 下用 `flutter test ../../evidence/i1/review-i1/scripts/<文件>` 运行（真实 sqlite3mc 加密库或与组件测试相同的内存库），全部证据由 `scripts/gen_evidence.sh` 一次生成：

| 目的 | 做法 | 证据 |
|---|---|---|
| 迁移与外键（重点 1） | 复现 I1-c 的新建/升级结构比较并核对哈希；查 SchemaV2/V3 冻结段在各提交的 sha256、各次 iOS 构建之间 `lib/data/db` 的差异；v1 库经 `openAppDatabase` 升到 v4 后读 `foreign_keys`/`foreign_key_check`/`integrity_check`，并做跨空间、悬空引用的写入 | migration-check.txt |
| 隔离（重点 2） | 扫描 `lib/data` 下每个查询/更新语句是否带工作空间过滤；读 provider 依赖链；外键探针（同上） | hygiene-scan.txt（末段）、migration-check.txt |
| 金额与日期（重点 3） | 合成数据构造边界场景：已出账消费转分期、迟付旧账单、早于账单日的还款、冲正、修正后状态；周期事项展开 20,000 组随机规则与按天暴力判定比较；业务日期/截止时点/时刻写法 200,000 个时刻与 `DateTime` 独立计算比较；分期 278 例（含 10^13 本金、0 与 0.0000000001 费率、60 期）与 Python `money.py` 逐项比较 | ledger-probe.txt、reversal-probe.txt、misc-probe.txt、date-props.txt、installment-parity.txt |
| 追加只读（重点 4） | 原始 SQL 尝试 UPDATE、DELETE、同一事务删后同 id 重插、INSERT OR REPLACE | append-only-probe.txt、ledger-probe.txt P2 |
| 界面与隐私（重点 5） | grep 禁用文案与绿色 token、金额显示是否经 MoneyText、自由文本的 G2 校验覆盖、诊断日志写入点 | 本报告 §3.5 |
| 隔离（界面路径） | 演示空间打开全屏表单 → 横幅退出演示 → 保存 | demo-exit-probe.txt |
| 首次体验与性能（重点 6） | 2.0x/3.0x 字号下演示空间 46 个页面逐屏滚到底（现有测试只看首屏）；20 张卡、14,610 笔交易、476 期账单、450 笔还款、10 个分期、518 条现金事件下各读模型耗时；IRR 耗时（AOT 编译） | textscale-scroll.txt、perf-probe.txt、installment-parity.txt |
| CI（重点 7） | `gh api` 复核 4 个 action 的 SHA 与标签、查 flutter-action 内部引用；grep 失败掩盖与产出数断言；下载发版构建 #55 的 Required Reason 扫描结果 | ci-check.txt |
| 卫生（重点 8） | 扫描邮箱/令牌/私钥/IP/端口/宿主信息/Luhn 卡号形态（不回显数字）、提交身份与署名 | hygiene-scan.txt |
| 证据（重点 9） | 逐项对照各简报验收清单，复现 schema-diff 哈希与分期对照 | migration-check.txt、installment-parity.txt |

## 2. 发现清单（按级别排序）

### blocker

**R-01 · blocker · 已出账的消费再「转分期」：总负债把这笔本金算两次（F-30"不重计"被破坏）**
- 位置：`apps/mobile/lib/data/repositories/installment_repository.dart:141-171`（只查"是消费、未删除、没转过"，不查这笔消费是否已在某期录入账单里）、`:204-223`（各期按账单日是否 ≤ 最近已出账单标"已出账"）；`apps/mobile/lib/data/mapping/ledger_mapping.dart:338-364`（`coveredByPlans` 只把原消费从"未出账"里拿掉；已出账的原消费本来就在账单新余额里，再加上"未来分期本金"）；`apps/mobile/lib/features/statements/statement_pages.dart:700`（`canConvert = 消费 && 未转过`：账单详情"本期交易"里已出账的消费也给「转分期」）。
- 现象（合成数据，ledger-probe.txt P1/P1b）：10-05 消费 12,000，10-10 账单新余额 12,000（含这笔）；转 12 期、每期 0.6%：默认首期 → 已出账未还 12,000 + 未来分期本金 12,000 = **总负债 24,000**；首期指定为 10-10 → 12,000 + 11,000 = 23,000。实际负债 12,000（加一期费用）。P-01/P-03/P-05 的负债四分法都显示加倍后的数字。README 的 F-30 例子用的是"银行已按分期出账"的账单数值，没有覆盖"先出账、后分期（账单分期/已出账消费分期）"这条常见路径。
- 复现：`cd apps/mobile && flutter test ../../evidence/i1/review-i1/scripts/ledger_probe_test.dart --plain-name P1`。
- 建议（0.0.2）：最小修法是只允许把**未出账**的消费转分期（`isBilled` 为真时仓库拒绝并说明"已出账的消费请按银行调整后的账单录入修正版本"，界面不显示按钮）；若要支持账单分期，则转分期时要求同时录入该期账单的修正版本（新余额扣除分期本金），或在读模型里把已出账消费的分期本金从该期剩余应还中扣出，二选一由主会话定。加 F-30 的"已出账消费转分期"测试。

**R-02 · blocker · 还款分配与账单日的先后无关、旧账单不被新一期吸收：本期应还与总负债算错，旧账单永远"已逾期"**
- 位置：`apps/mobile/lib/data/mapping/ledger_mapping.dart:68-108`（`paidOnStatement` 只看分配到这一期的已入账还款，不看还款日期与账单日、也不看更新的账单）、`:310-316`（本期应还 = 最近一期的剩余应还）；`apps/mobile/lib/data/repositories/repayment_repository.dart:186-198`（分配只要求同一子账户、未结清，不查还款日期）；`apps/mobile/lib/data/repositories/ledger_reader.dart:291-307`（近期到期列出全部"已逾期"）、`:399-417`（过了到期日、剩余应还 > 0 即标逾期，不管是否已有更新的一期）；`apps/mobile/lib/features/repayments/repayment_form_page.dart:256-258`（候选为全部未结清的账单）、`:332`（超过剩余应还只提示、可保存）；`statement_pages.dart:450-458`（任何未结清账单都有「登记还款」并预填到该期）。
- 现象（ledger-probe.txt，合成数据）：
  1. **P3 迟付分配到旧账单 → 多算**：9-10 账单 1,000 未还（逾期）；10-10 账单新余额 1,500（含上期 1,000）；在 9 月账单页「登记还款」1,000（10-12 扣款、银行确认）→ 9 月"已结清"，10 月**本期应还仍 1,500、总负债 1,500**（应为 500）。照 App 再还 1,500 就多还 1,000。
  2. **P4 补登早于账单日的还款 → 少算并误判已结清**：10-10 账单新余额 800（银行已扣除 09-25 还的 1,500）；补登 09-25 那笔 1,500（App 里只有 10 月这一期可分配——BL-27：登记还款须先有账单；界面只提示"超过剩余应还"）→ 10 月**"已结清"、剩余应还 0、总负债 0、近期到期为空**，实际仍欠 800，到期不会再提醒。
  3. **P3b 旧账单无法结束**：同 1 的数据，改为按 10 月全额 1,500 还清（分配到 10 月）→ 10 月"已结清"、总负债 0，但 9 月**永远"已逾期 1,000"并留在近期到期**；要清掉只能虚构一笔还款。
- 复现：`cd apps/mobile && flutter test ../../evidence/i1/review-i1/scripts/ledger_probe_test.dart --plain-name P3`（P3、P3b）与 `--plain-name P4`。
- 建议（0.0.2）：① 一个币种子账户有更新的一期账单后，较早未结清的账单视为"已并入下一期"：不再进近期到期、不再标逾期、不再接受新的分配（读模型层即可，状态机是否加转移见 Q-4）；② 分配校验：还款的扣款/入账日早于所分配账单的账单日时拒绝或不计入该期（该期新余额已反映它）；入账日晚于更新一期账单日、却分配到旧账单的，计入最新一期；③ 登记表单默认分配到最近一期，超过剩余应还时要求确认。三点都配测试（上面三个探针可直接改成测试）。

### major

**R-03 · major · 冲正后账单仍"已结清"：剩余应还 > 0 却不进近期到期、过了到期日也不标逾期（BL-29 比登记的更严重）**
- 位置：`apps/mobile/lib/data/repositories/repayment_repository.dart:469-472`（`reverse` 只改还款状态）；`ledger_models.dart:105`（已结清没有后续状态）；`ledger_reader.dart:296`（近期到期跳过已结清）、`:408-411`（逾期只在 `canBecome(overdue)` 时）；`statement_repository.dart:298-303`（结清时把各期分期标"已结清"、计划可能变"已还完"，冲正后也不回退）。
- 现象（reversal-probe.txt）：10-10 账单 1,000 → 还款银行确认 → 已结清；冲正后：状态"已结清"、剩余应还 1,000、总负债 1,000、**近期到期 0 条**；把"今天"设为 11-05（已过 10-28 到期日）仍是"已结清"、近期到期 0 条。BL-29 写的是"状态与金额看起来矛盾"，实际后果是被冲正的欠款从提醒与逾期里消失，用户会错过还款。
- 复现：`cd apps/mobile && flutter test ../../evidence/i1/review-i1/scripts/reversal_probe_test.dart`。
- 建议（0.0.2）：冲正时对它分配到的账单重新判断：剩余应还 > 0 的回到"部分结清/已出账"（过了到期日则"已逾期"），同时回退因结清而标记的分期各期与计划；需要在 PRD §6.2 与触发器里加 `settled → partially_settled/issued/overdue`（仅由冲正触发，见 Q-5）。若 0.0.2 不改状态机，至少让读模型把"已结清但剩余应还 > 0"的账单照常列入近期到期与逾期提醒。

**R-04 · major · 分期成本（有理数 IRR）在界面线程每次 build 重算：36 期约 0.4 s、60 期约 2.3 s**
- 位置：`apps/mobile/lib/features/statements/statement_pages.dart:764`（`InstallmentPlanCard.build` 里 `data.costOf(plan)`；账单详情列出该账户全部分期）；`statement_forms.dart:982-987`（转分期表单在 build 里算预览成本，`:1002`、`:1010` 每次按键 `setState`）；`ledger_reader.dart:266-276`；领域包 `installment.dart:92-135`（每步二分都用精确 `Rational` 算 (1+r)^t，分母随期数指数增长）、`rational.dart:47`（每次运算都做 BigInt gcd）。
- 现象（installment-parity.txt 末段，`dart compile exe` 的 AOT 程序，服务器级 x86-64 CPU，两次）：一次 IRR + 年化 12 期 34–38 ms、24 期 112–118 ms、**36 期 409–420 ms、60 期 2,308–2,331 ms**；perf-probe.txt（JIT）10 个分期（含两个 36 期）一次算完 1,307–1,335 ms。界面上表现为：打开有 36/60 期分期的账单详情、滚到分期卡片、任何写库后读 provider 重算重建时卡顿；转分期表单的期数为 60 时，之后每改一次费率或尾差都要重算一次（按本机 AOT 数字约 2.3 秒，手机上量级相同）。期数上限 60 是仓库与界面明确允许的（`installment_repository.dart:118`、`statement_forms.dart:873`）。
- 复现：`cp -r evidence/i1/review-i1/scripts/dart /tmp/x && cd /tmp/x && dart pub get && dart compile exe bin/irr_timing.dart -o irr && ./irr`；界面层见 `flutter test ../../evidence/i1/review-i1/scripts/perf_probe_test.dart`。
- 建议（0.0.2）：条款建好后不可改，成本只需在建计划时算一次并缓存（读模型按计划 id 记忆化，或存进库）；表单预览去抖并放到 `compute`（后台 isolate）；领域包的 IRR 可改用定点 BigInt（如 2^-96 定标）计算 NPV，结果与 Python 的差仍远小于 10^-9（本次 278 例对照可作回归）。

**R-16 · major · 录错的交易与分期在界面上无法删除、作废或补入账日**
- 位置：仓库已有 `TransactionRepository.markPosted`（`apps/mobile/lib/data/repositories/transaction_repository.dart:227`）、`delete`（`:255`）与 `InstallmentRepository.cancel`（`installment_repository.dart:233`），`lib/features` 里没有任何调用；路由只有 `transactions/new` 与 `transactions/:id/installment`（`apps/mobile/lib/app/routes.dart:148-158`）；P-05 的交易行只有「转分期」（`statement_pages.dart:700-737`），分期卡片没有任何操作（`statement_pages.dart:747-870`）。
- 现象（ui-entry-check.txt）：「记一笔」录错金额/类型/日期或重复录入后无法删除，只能等它所在账期的账单录入后被账单数字覆盖；入账日未知的交易无法补入账日（Q-3 的偏大口径会一直持续到最晚的可能账期也出账）；转分期录错期数或费率、或发生 R-01 之后，计划的"未来分期本金"、费用与资金日历尾部责任会持续整个分期期限（12–60 个月），用户没有任何修正办法（「重置本地数据」正常使用时也不可达，BL-26）。
- 复现：`cd apps/mobile && grep -rn 'transactionRepositoryProvider\|installmentRepositoryProvider\|\.cancel(' lib/features`——只有「记一笔」（`statement_forms.dart:659`）与「转分期」（`:899`）两处创建调用，没有删除、补入账日或作废；在演示空间打开账单详情，交易行只有「转分期」、分期卡片没有按钮（原文见 ui-entry-check.txt，或 `bash evidence/i1/review-i1/scripts/gen_evidence.sh ui`）。
- 建议（0.0.2）：交易行加「删除」（已转分期的先提示作废分期）与「补入账日」，分期卡片加「作废（录错了）」，都调用已有的仓库方法（已有校验与测试）；删除/作废时按 R-07 关闭相关差异项。U-1 的"记本期账单""还清本期"快捷操作会让录入更频繁，更需要撤销入口。

### minor

**R-15 · minor · 在演示空间打开的全屏表单，点横幅「退出演示」后仍留在屏幕上，保存会写进真实空间**
- 位置：`apps/mobile/lib/app/widgets/demo_banner.dart:52-65`（退出演示只切换当前空间，不离开当前页面；进入演示 `workspace_actions.dart:30-31` 则会转到总览）；表单在保存时才取仓库（例：`lib/features/cash/cash_account_pages.dart:149` `ref.read(cashAccountRepositoryProvider.future)`）。
- 现象（demo-exit-probe.txt）：真实与演示两个空间都在、当前为演示；打开"新建现金账户"填名称 → 横幅「退出演示」并确认 → 表单仍在（横幅消失）→「保存」→ 账户写进了**真实空间**（演示空间仍只有"工资卡""定期存款"）。引用演示对象的表单（选了演示账户的收支、还款等）会因外键或"已不存在"失败，所以只有新建独立对象（现金账户、卡片、情景等）的表单会这样；卡片与现金账户在真实空间只能停用、不能删除。这是本次找到的唯一一条演示→真实的写入路径。
- 复现：`cd apps/mobile && flutter test ../../evidence/i1/review-i1/scripts/demo_exit_form_probe_test.dart`。
- 建议：切换空间后统一回到总览（与进入演示一致），或让表单在打开时记下工作空间 id、保存时不一致就拒绝并提示。

**R-05 · minor · 账单版本"追加只读"只拦 UPDATE：DELETE、删后同 id 重插、INSERT OR REPLACE 都能改写或抹掉版本（仓库没有这条路径）**
- 位置：`apps/mobile/lib/data/db/schema.dart:1188-1191`（只有 BEFORE UPDATE）；`:1193-1200`（版本号检查在删掉当前版本后放行同号重插）；`:1173-1186`（当前版本"只能前移"在旧版本行被删时子查询为 NULL，不触发）。
- 现象（append-only-probe.txt、ledger-probe.txt P2）：直接 DELETE 旧版本 v1 成功（"原值可查"丢失）；同一事务删掉当前 v2 再以同一 id、同一版本号插入新余额 1 → 成功，`current_version_id` 不变，读模型本期应还变 1；`INSERT OR REPLACE` 以 v1 的 id 写入 v3 → 成功、v1 消失。已核对：App 的仓库代码没有任何删除账单版本或用 REPLACE 写入的路径（§3.4），所以对用户目前不可达；R-STMT-07 的验收只要求拒绝 UPDATE。
- 复现：`cd apps/mobile && flutter test ../../evidence/i1/review-i1/scripts/append_only_probe_test.dart`。
- 建议：下一个 schema 版本（v5：L-1 的消费贷或 I-2 的预留，以先到者为准）加 `BEFORE DELETE ON statement_versions`：只在所属工作空间正在清除时放行（例如清除前在同一事务里写一个标记行，触发器查它），并加删除/替换的约束测试。

**R-06 · minor · 人工修正后不重新判断结清与逾期**
- 位置：`apps/mobile/lib/data/repositories/statement_repository.dart:257-270`（只把"已出账"改"已修正"）。
- 现象（misc-probe.txt M1）：账单 1,000、银行确认还 800 → 部分结清；银行调整后修正为 800 → 仍"部分结清"、剩余应还 0，并以 0 元留在近期到期；同理，已逾期的账单把到期日改晚也不会回退。
- 复现：`cd apps/mobile && flutter test ../../evidence/i1/review-i1/scripts/misc_probe_test.dart --plain-name M1`。
- 建议：修正后调用与 `_settleStatements` 相同的判断（只用银行确认的分配）；近期到期跳过剩余应还为 0 的账单。

**R-07 · minor · 作废还款（或删除交易）后，指向它的差异项仍"待处理"**
- 位置：`apps/mobile/lib/data/repositories/repayment_repository.dart:478-504`（直接「作废登记」不处理所在的疑似重复差异项，只有 `resolveDuplicate` 会处理）；`transaction_repository.dart:255-286`（删除交易不处理差异项；0.0.1 界面没有删除交易的入口，见 R-16）。
- 现象（misc-probe.txt）：M4 同日同额的自动扣款与手工还款生成疑似重复后，在还款详情直接「作废登记」手工那笔 → 只剩一笔还款，"疑似重复还款"仍待处理（计入 P-01 待办）；M2 删除一笔退款后，它的"退款待核对"仍待处理、指向的交易已不存在。
- 复现：`cd apps/mobile && flutter test ../../evidence/i1/review-i1/scripts/misc_probe_test.dart --plain-name M4`（M2 同理）。
- 建议：作废/删除时把引用它的未处理差异项标为已处理或已忽略（`resolved_by = system`）。

**R-08 · minor · 删除非主币种子账户只查快照与规则；已有交易/账单/还款时由外键拒绝，异常未包装，界面没有任何提示**
- 位置：`apps/mobile/lib/data/repositories/credit_account_repository.dart:235-273`；`apps/mobile/lib/features/cards/currency_pool_sections.dart:20-31`（只接 `RepositoryException`）。
- 现象（misc-probe.txt M3）：USD 子账户有一笔交易时删除 → `DriftRemoteException`（SQLite 787），不是 `RepositoryException`；界面上点了没有反应（错误只进诊断日志）。数据不丢（外键挡住）。
- 建议：删除前一并检查交易、账单、还款、分期，给出说明；该方法也走 `rethrowAsRepositoryException`。

**R-09 · minor · 金额隐藏：0.0.1 没有开关入口；有 4 处金额绕过 MoneyText**
- 位置：`apps/mobile/lib/app/money/amount_visibility.dart:8-17`（只有 provider，界面无入口）；纯文本金额：`lib/features/scenarios/scenario_pages.dart:613`、`:674`、`:709`，`lib/features/cash/cash_account_pages.dart:932`。
- 影响：当前用户无法打开隐藏，所以不泄露；I-4 接入开关后这 4 处不会隐藏（ui-spec §3.6"金额一律显示固定 4 个点"）。
- 建议：这几处改用 `MoneyText`（或在文本里按隐藏状态替换为"••••"），并把"开启隐藏后整页无数字金额"加进可访问性页面清单的检查。

**R-10 · minor · 公测说明提到「重置本地数据」，正常使用时找不到这个入口**
- 位置：`apps/mobile/lib/features/settings/public_beta.dart:24-26`；入口只在数据库打不开时的启动页（`lib/app/startup/`）。
- 影响：BL-26 只登记了"没有清空真实数据的入口"，没登记说明文案与之不符；公测用户读到说明会去"我的"里找。
- 建议：说明改为"删除 App 会永久删除全部数据（数据库打不开时启动页另有「重置本地数据」）"，或随 BL-26 加入口后保持现文案。

**R-11 · minor · CI 的三处小缺口**
- 位置：`.github/workflows/mobile.yml:313-316`（`Verify IPA` 读出版本与构建号只打印、不断言，与 pubspec 的版本名、`run_number`、`ios-v*` 标签都不比对）；`:378-458`（Required Reason 扫描对"须由 App 清单承担、App 清单却未登记"的类别也只报告不失败）；flutter-action 1a449444 的 `action.yaml:123`、`:130` 内部用 `actions/cache@v5`（标签，未固定 SHA；`cache: true` 时生效）。
- 影响：前两处都不会让失败显示为绿（版本由 pubspec 经 `$(FLUTTER_BUILD_NAME)` 写入，0.0.1 发版构建的扫描结论与清单一致，见 ci-check.txt），但下次改版本或加插件时少一道自动检查；第三处是供应链的残余（GitHub 自家 action）。
- 建议：断言 `version` 等于 pubspec 版本名、标签构建时等于标签去掉 `ios-v`、`build` 等于 `run_number`；扫描在"需要但未登记"时 `exit 1`；flutter-action 设 `cache: false` 或另用固定 SHA 的 `actions/cache`。

**R-12 · minor · 可访问性测试的 2.0x/3.0x 只检查每页首屏**
- 位置：`apps/mobile/test/app/accessibility_test.dart:184-199`（`goTo` 后只看 `takeException` 与缩放未被钳制，不滚动；ListView 只构建可见子项）。
- 现象：本次用 `forEachScreen` 逐屏滚到底复查演示空间 46 个页面，2.0x 与 3.0x 都是 0 条错误（textscale-scroll.txt），所以没有掩盖缺陷，只是覆盖不足。
- 建议：把探针里的逐屏检查并入该测试。

**R-13 · minor · 已提交证据的过滤说明原文写出了宿主上工具的运行身份**
- 位置：`evidence/i1/` 下 24 个文件的第 3 行（如 `evidence/i1/I1-a/test.txt:3`、`evidence/i1/release-0.0.1/app-test.txt:2`）；过滤本身生效（宿主提示的 4 行确实去掉了）。
- 影响：I-0 审查 R-11 要求不公开宿主运行身份；被过滤掉的提示行虽已删除，过滤说明（含 grep 模式原文）又把运行身份写了出来；风险低。
- 建议：以后的过滤说明写"工具打印的宿主运行环境提示（4 行）"，模式只写不含身份字样的子串（本次 `scripts/filt.sh` 的写法）；既有文件是否改写由主会话决定。

**R-14 · minor · 账单读模型在大数据量下偏慢（导入落地前要处理）**
- 位置：`apps/mobile/lib/data/repositories/transaction_repository.dart:79-83`（排序比较器里每次 `Timestamp.parse` 两个时刻）；`ledger_mapping.dart:218`（每笔交易都把全部规则版本重新映射一遍）；`ledger_reader.dart:443-445`（每笔还款一条查询）。
- 现象（perf-probe.txt，JIT/调试模式，真实加密库，14,610 笔交易、476 期账单、450 笔还款）：`LedgerReader.load` 762–1,714 ms（首次含逾期维护的写库），资金日历 30/180 天 9–42 ms、卡包 4–9 ms、情景列表 9–15 ms。手工录入的现实数据量远小于此，所以目前不影响公测；I-3 导入后每次写库都会触发重算。
- 建议：交易列表在 SQL 里按存好的 UTC 排序键排序（或缓存解析结果）；规则按子账户映射一次；还款事件一次查齐。

### 疑问（未定级）

- **Q-1**：资金日历与总览"现金压力"只含现金事件——信用卡的本期应还在登记还款之前、以及窗口内的分期各期都不进时间线（尾部责任只列窗口外的分期）。这与 ui-spec P-07 的写法一致（README 也这样实现），但公测用户第一次看资金日历时很可能把"无缺口"理解为"信用卡也还得起"。是否在 P-07/P-01 加一行"未计入：信用卡应还 X（登记还款后计入）"？
- **Q-2**：公测说明"不上传任何服务器""删除 App 会永久删除全部数据"：数据库在 `Application Support`，会进 iCloud/电脑的设备备份（加密、钥匙串条目 `ThisDeviceOnly`，换机不可读）；同一台 iPhone 从删除前的备份恢复会连同密钥一起回来；钥匙串条目在删除 App 后也仍在。App 本身确实不上传。是否把库排除出设备备份（`NSURLIsExcludedFromBackupKey`），或把文案改得更准确？
- **Q-3**：入账日未知的交易，若"可能账期"跨过最近一期账单日，按"未出账"计入（README"I-1c 的偏离与约定"已写明的保守口径）；而这笔若实际已在录入账单的新余额里，就会重复计入总负债，直到最晚的可能账期也出账（0.0.1 界面无法补入账日，见 R-16）。是否接受这种偏大的口径，还是在 P-05 对这类交易提示"请补入账日"？
- **Q-4**：R-02 的修法需要定义"旧账单被下一期合并"——PRD §6.2 没有这个状态或转移。0.0.2 只在读模型层处理（推荐，状态表不变），还是给状态机加转移？
- **Q-5**：R-03 若要让冲正回退账单状态，需要在 PRD §6.2 与 `statements_status_transition` 触发器里加 `settled → partially_settled/issued/overdue`（仅冲正触发）。BL-29 写的是"本次审查确认后决定"：本次结论是需要回退（或至少让读模型照常提醒），请主会话裁决。

## 3. 已核对无问题的项（便于以后不重复审）

### 3.1 数据丢失与迁移（重点 1）

1. 真机上可能存在的库只有两种：I-0b 的 IPA（4d720c9）建的 v1，以及 I1-c 两次构建（6547054、8149c29）与发版构建（83be815）建的 v4；I1-a、I1-b 没有出 IPA（migration-check.txt 的 `gh run list`）。6547054..83be815 之间 `lib/data/db` 无改动，v4 结构只有一种。
2. v1 的真实建库代码（4d720c9 的 `createSchema`：建 meta、写一行；drift 随后写 `user_version = 1`）与测试里的 `LegacyV1Database` 等价；4d720c9 → HEAD 的密钥存取只增加了 `delete`，条目名与编码不变，v1 用户升级不会 `key_missing`。
3. 冻结 SQL 与 drift 定义一致：复现新建与从 v1/v2/v3 升级四条路径的结构描述，sha256 都是 `b41dbeb0…e501`，与 I1-c `schema-diff.txt` 第 48 行相同；SchemaV2/V3 冻结段自引入后各提交的 sha256 不变。
4. 迁移在一个事务里，`meta` 与 `PRAGMA user_version` 在同一事务写入；失败整体回滚（四条回滚测试与"经 openAppDatabase 失败后仍是 v1、可重试"）；重跑 1/2/3→4 不报错；旧版 App 打开 v4 报 `schema_too_new` 且文件不变。升级后 v2/v3 种子行逐行不变（`schema_test`）。
5. 外键真的开启：`beforeOpen` 读回 1；v1 升级上来的库 `foreign_keys=1`、`foreign_key_check` 为空、`integrity_check=ok`；写入不存在的工作空间、真实空间的事件指向演示空间的账户、删除仍被引用的工作空间都被 787 拒绝（migration-check.txt）。drift_flutter 单连接、无读池，外键设置覆盖全部语句。
6. 「清除演示数据」只经 `clearDemo` → `deleteWorkspace(演示空间 id)`；删除顺序满足外键与触发器（现金事件先于还款、版本先于账单、自引用在一条语句内）；隔离测试确认真实空间不受影响。「重置本地数据」只在 `key_missing`/`wrong_key` 时出现，须输入"删除"，删除库文件与 -journal/-wal/-shm 与钥匙串密钥并忘掉缓存（I-0 审查 R-15 已修，有"重置 → 写入 → 重启 → 读回"测试）。
7. 仓库层的硬删除只有 4 处（无快照规则的非主子账户、演示空间清除、压力情景连同版本、周期事项单期例外），都带工作空间与 id 条件；其余"删除"都是 tombstone，读模型一律排除已删除行（遗留差异项见 R-07）。

### 3.2 工作空间隔离（重点 2）

1. `lib/data` 下每个查询/更新语句的 14 行内都有工作空间过滤（例外只有全局的 `WorkspaceRepository` 与库层 PRAGMA），扫描原文见 hygiene-scan.txt 末段；与隔离测试的 237 条查询互为印证。
2. 表间全部是携带 `workspace_id` 的复合外键，多态主体（规则）与 `linked_repayment_id` 用触发器限定同一空间；外键探针确认跨空间引用被拒。
3. 全部仓库与读 provider 都 watch `workspaceScopeProvider`（它 watch 当前工作空间与时钟），切换空间时整体重建；功能页自己的 provider 也经仓库 provider 取数。演示数据经演示空间的 scope 写入，一个事务。界面层唯一的例外见 R-15（退出演示后留在屏幕上的表单）。

### 3.3 金额与日期（重点 3）

1. 日期：周期事项展开 20,000 组随机规则（1999–2101，含 2000 闰年、2100 平年、1/29–1/31 锚定、月末规则、跨年、起止日）与按天暴力判定 0 不一致；`businessDateOf`/`postingDateOf`/`timestampTextIn` 在 200,000 个时刻（8 个业务时区、任意书写偏移 −14:00~+14:00、当地午夜 ±2 秒、随机截止时点）上与 `DateTime` 独立计算 0 不一致（date-props.txt）。截止时点"严格晚于才算次日"与 README 一致。
2. 分期：278 例（1–36 期与 60 期、本金 1 到 10^13、费率 0、10^-10 到 0.5、尾差首期/末期）与 Python `money.py` 逐项比较：拆分、每期费用、名义年化完全相同，月 IRR 差 ≤ 10^-27，复利年化到 10 位小数相同，界面百分数文本（4 位小数 HALF_UP）全部相同（installment-parity.txt）。"首期一次收取"是 README 登记的本地约定，未对照。
3. 还款状态机：仓库的 `next` 表、`repayments_status_transition` 触发器与 PRD §6.3 + README 两条偏离逐条一致；`repayment_test` 有"每个状态 × 每个动作"的穷举。账单状态机同样一致。
4. 双侧时间（F-31）：现金侧按现金时区的扣款日（计划事件确认时改为实际扣款时点），负债侧按信用账户时区与截止时点的入账日（`creditDateOf`），只计入账日 ≤ 今天的；与 `cash.py` 的"快照日之前的事件视为已反映"一致。额度释放（F-28）在没有释放时滞时恒为不释放（BL-28 已登记）。
5. 疑似重复（F-32）只在两笔都已核销时扣掉较小的一笔；分配（F-33）仓库 ≤、界面 =、触发器兜底；退款（F-34）在处理前不进未出账、不进现金；贷方余额（F-38）本期应还 0、已出账未还为负。
6. 现金（I1-b）：映射、可用现金口径、快照包含、陈旧判定与领域包一致（`cash_parity_test` 逐字段比较 F-01~F-05/F-07，基线全过）；交叉规则 `checkCashTimelineInputs` 覆盖简报 §5 全部条目；资金日历 30/180 天在 518 条事件下 9–42 ms。
7. 金额范围：库表 CHECK 把每个金额限制在 ±10^13，合计用 64 位整数不会溢出；负可用额度原值保留、容量截零（F-26）。

### 3.4 追加只读与触发器（重点 4）

1. `statement_versions` 的任何 UPDATE 都被 `RAISE(ABORT)`（探针与 `ledger_constraints_test`）。
2. 仓库路径不能绕过：没有任何代码删除账单版本或用 REPLACE/ON CONFLICT 写版本（`grep` 全部 `delete(`、`DELETE FROM`、`insertOnConflictUpdate`）；人工修正只插新版本并把当前版本前移；已结清的账单不能修正。数据库层的 DELETE/REPLACE 缺口见 R-05。
3. `linked_repayment_id` 的两个触发器、"仍有未删除的现金事件指向时不能删除或作废还款"的两个触发器，与仓库的作废流程（先作废计划扣款）一致；分配合计、分期条款、各期状态、差异项只处理一次的触发器与仓库规则不矛盾。

### 3.5 界面规则与隐私（重点 5）

1. `lib/` 里没有"还款成功""稳妥"一类文案（"安全"只出现在"隐私安全"设置分组与注释里）；没有任何页面使用 robust（绿色）token，主题 ColorScheme 全部显式取 token；`forbidden_ui` 的整页检查覆盖 9 种还款状态。
2. G2：全部自由文本列（银行名、池名、产品名、持卡人、别名、规则例外、专项用途、现金账户名、收支与周期标签、情景名、商户、分类、修正理由、证据备注）在仓库层都经 `validateFreeText`（含全角与分组 Luhn），库表另有 13 位数字 GLOB 兜底。
3. 诊断日志只有固定事件码；detail 掩码数字；未捕获错误只记类型与代码位置（Release 不再打印到系统日志）；`containsKeyMaterial` 已按 I-0 审查 R-03 加强（掩码形态、base64、字节列表）。
4. 「关于」的版本与构建号来自 package_info_plus；公测说明只在 `PublicBeta` 一处，版本号由测试与 pubspec 核对。

### 3.6 首次体验与性能（重点 6）

1. P-22 → 「手工建卡」进真实空间并打开新建卡片，保存后回卡包并给出「设置账期」；「体验演示」生成演示空间进总览；未开放的入口一律写明"后续版本提供"。每个首次空白页都有下一步动作；错误态有错误码与「重试」。已登记的死路：BL-27（先有账单才能登记还款）、BL-26（无清空入口）；本次新发现的见 R-16（录错的交易与分期无法撤销）。
2. 2.0x/3.0x 字号下演示空间 46 个页面逐屏滚到底 0 条布局错误（textscale-scroll.txt）。
3. 大数据量耗时见 R-04、R-14；卡包、资金日历、情景列表在上述数据量下都在 45 ms 内（JIT）。

### 3.7 CI 与发布（重点 7）

1. 4 个第三方 action 全部固定到 40 位 SHA，`gh api` 复核与注释的标签一致（ci-check.txt）。
2. 没有 `continue-on-error`；`|| true` 只在诊断输出（`flutter doctor`）、读图标名（随后断言）与扫描的 grep 收集里。
3. 产出数断言：golden 两端各断言 3 个、随机断言 Python 1,200 个后 `diff -r`（Dart 少文件会失败）、Schema 校验断言 cycles 301 / verify 902，少产出都会失败。
4. Required Reason 扫描覆盖主二进制、`Frameworks/` 下每个 framework 与 dylib；发版构建 #55（39268709025）的扫描结论与 `PrivacyInfo.xcprivacy` 一致（UserDefaults 无命中已删，其余三类保留）。`Verify IPA` 检查 Bundle ID、最低系统、无描述文件、隐私清单、两个必备 framework、AppIcon 与 Assets.car、sqlite3mc。
5. 标签推送不受 paths 过滤，`ios-unsigned` 依赖 dart job；发版运行三个 job 全绿。

### 3.8 公开仓库卫生（重点 8）

`apps/mobile`、`evidence/i1`、`.github` 的 327 个跟踪文件：邮箱只有 `users.noreply.github.com` 与图标文件名的误报；无令牌、私钥、口令赋值；IP 只有规范章节号"3.2.2.3"；端口只有测试计时 `00:22` 的误报；无宿主发行版、内核、代理状态；Luhn 命中是公开测试卡号 4111…（G2 测试）、浮点向量与 pubspec.lock 的哈希。93 个提交的作者与提交者都是 noreply 身份，提交说明与文件里没有署名字样（hygiene-scan.txt）。`docs/90-promo` 未合入 main，不在范围内。

### 3.9 证据（重点 9）

1. 文件齐全：I1-a 8/8、I1-b 8/8、I1-c 13/13 + `public-beta.txt`，与各简报验收清单逐项对应；release-0.0.1 与 device-0.0.1 另有发版与真机记录。
2. 是工具原文：带命令行、生成时间、源码提交与退出码；没有省略号或"<关键行>"式删节（检出的 `...` 都是工具自身输出）。
3. 可复现：本次复现了 App 489 / 领域包 279 项测试、schema-diff 的结构哈希、分期对照（范围更大），CI 运行与发版构建的扫描结果可从 GitHub 取回。宿主运行身份的残留见 R-13。

## 4. 对 0.0.2 与 I-2 的建议（10 条）

1. **0.0.2 先修 R-01、R-02，再做 U-1 的卡账首页**：U-1 的"待还"大字与"已逾期 N 天"直接取最近一期剩余应还与未结清账单的到期日，R-02 的三种情形会原样出现在首页每一行；"记本期账单"会让一个子账户积累更多期账单，"还清本期"按剩余应还预填。最小改动："只允许未出账消费转分期"＋"有更新一期账单后旧账单并入下一期（读模型层）"＋"分配不接受早于账单日的还款"，三个探针改成测试一起提交，修完重跑 F-30 与 P1/P3/P3b/P4。
2. **0.0.2 修 R-03**：冲正后按剩余应还重新判断账单状态（或至少照常进近期到期与逾期），先由主会话对 Q-5 裁决。
3. **0.0.2 修 R-04**：分期成本按计划缓存、表单预览去抖并移到后台 isolate；领域包 IRR 的提速放到 I2-0 与 BL-15 一起做，用本次 278 例作回归。
4. **0.0.2 修 R-16 并顺带 R-06、R-07**：交易「删除」「补入账日」、分期「作废」接上已有仓库方法；删除/作废/修正之后由系统关闭相关差异项、重新判断结清与逾期。
5. **公测说明、入口与空间切换**（R-10、R-15、Q-2）：0.0.2 发版前定文案；退出演示后统一回到总览（U-1 把空间切换移到"我的"时一并处理）；若决定把库排除出设备备份，同时更新 BL-07 的说明。
6. **v5 迁移时补齐兜底**（R-05）：无论 v5 先由 L-1（消费贷）还是 I-2（`plan_reservations`）引入，都顺带加 `statement_versions` 的删除/替换触发器与测试，并照 README 的加表步骤做（演示数据写一行、隔离测试覆盖、新建与各旧版本升级的结构比较）。
7. **I-2 组装规划输入时**：负债与应还取自修完 R-02 之后的读模型；信用卡应还要不要作为现金时间线的计划流出（Q-1）在 I-2 开始前定下来，否则规划、资金日历与 U-1 的现金曲线会对同一笔钱给出不同结论。
8. **CI**（R-11）：断言 IPA 版本号与标签一致、构建号与运行序号一致；Required Reason 扫描在"需要但未登记"时失败；固定 flutter-action 内部的缓存 action。
9. **导入（I-3）前**处理 R-14 的读模型热点，并把 perf-probe 的数据量（或更大）做成常驻的性能测试，给出上限。
10. **测试与证据**：可访问性 2x/3x 改为逐屏检查（R-12，U-1 的新页面同样适用）；证据的过滤说明不再写宿主运行身份（R-13）；本次的日期性质与分期对照探针可直接收进 `test/`。

## 5. 复现输出索引（`evidence/i1/review-i1/`）

全部由 `scripts/gen_evidence.sh` 生成（`bash scripts/gen_evidence.sh [baseline|probes|migration|parity|ci|hygiene|ui]`）；每个文件头写明生成时间、HEAD 与过滤规则（`scripts/filt.sh`：去掉工具打印的宿主运行环境提示 4 行与含发行版/内核/代理字样的行）。

| 文件 | 内容 |
|---|---|
| `app-baseline.txt` | App format / analyze / test（489 项全过，真实 sqlite3mc） |
| `domain-baseline.txt` | 领域包 format / analyze / test（279 项全过） |
| `ledger-probe.txt` | R-01（P1、P1b）、R-02（P3、P3b、P4）、R-05（P2：UPDATE 被拒、DELETE 旧版本成功；P2 的"删后重插"因同一测试里 v1 已先删而被版本号检查拦下，成功的变体见下一个文件） |
| `append-only-probe.txt` | R-05：同一事务删掉当前版本后同 id 重插成功、INSERT OR REPLACE 成功 |
| `reversal-probe.txt` | R-03：冲正前后与过期后的状态、剩余应还、近期到期 |
| `misc-probe.txt` | R-06（M1）、R-07（M2、M4）、R-08（M3） |
| `migration-check.txt` | 结构哈希复现、冻结段哈希、iOS 构建列表、库代码差异、v1 建库原文、外键探针（§3.1） |
| `date-props.txt` | 周期事项展开与业务日期/截止时点/时刻写法的性质对照（§3.3） |
| `installment-parity.txt` | 分期 278 例与 Python 对照、IRR 耗时（AOT，R-04） |
| `perf-probe.txt` | 大数据量下各读模型耗时（R-04、R-14、§3.6） |
| `textscale-scroll.txt` | 2.0x/3.0x 逐屏滚动检查（R-12、§3.6） |
| `demo-exit-probe.txt` | R-15：演示空间里的表单在退出演示后保存到真实空间 |
| `ui-entry-check.txt` | R-16：交易删除/补入账日、分期作废的仓库方法在界面里有没有入口 |
| `ci-check.txt` | action SHA 复核、flutter-action 内部引用、失败掩盖与断言、发版构建的 Required Reason 扫描（R-11、§3.7） |
| `hygiene-scan.txt` | 卫生扫描、提交身份与署名、数据层查询的工作空间过滤扫描（§3.2、§3.8） |
| `scripts/` | 全部探针（`*_test.dart`，在 `apps/mobile` 下 `flutter test ../../evidence/i1/review-i1/scripts/<文件>`）、Python 脚本（`py/`）、纯 Dart 程序（`dart/`，复制到临时目录后 `dart pub get` 再运行）、`gen_evidence.sh`、`filt.sh`、`hdr.sh` |

结束时 `git status --short` 原文（HEAD `36d7819`；只有本报告与证据目录两个新路径，仓库内已有文件未改动）：

```
?? evidence/i1/review-i1.md
?? evidence/i1/review-i1/
```
