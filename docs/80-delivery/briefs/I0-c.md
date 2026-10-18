# 简报 I-0c · Dart 领域层移植 + Dart fixture 运行器 + 有限搜索

派发：2026-10-18。对应 `ios-first-plan.md` 的 I0-6、I0-7。本任务不出 IPA。若需重新派发，在开头加一句"先核对磁盘与 git 现状，不要重复创建"。

## 环境与规则（与 I-0a/b 相同的部分从简）
- 仓库 /projects/cardflow = `YePiXpert/cardflow`（公开，main）；`gh` 已登录；git 身份已配置；提交、代码、文档、CI 中不得出现 Claude/AI 署名或 trailer。
- Flutter 3.47.7 在 /opt/flutter-sdk（`export PATH=/opt/flutter-sdk/bin:$PATH`，含 `dart`）。本机还有 services/api 的 Python venv（`uv run --project /projects/cardflow/services/api ...`），可运行 Python 引擎 1.1.0 与 `packages/rules-protocol/runner_py/run_fixtures.py` 作对照。
- 宿主是生产 VPS：不运行 docker；不改 /opt 下除 flutter-sdk 外的目录；不装系统包。
- 范围：`apps/mobile/packages/cardflow_domain/`（新建纯 Dart 包）、`apps/mobile/`（接入与少量改动）、`packages/rules-protocol/runner_py/`（只允许加"导出每个 case 的参考输出"的选项，不改语义）、`packages/rules-protocol/README.md`（追加 Dart 端说明）、`.github/workflows/mobile.yml`（加 parity job）、`evidence/i0/I0-c/`。**不改** `packages/rules-protocol/schema/`、`fixtures/`、`services/api/cardflow/`、docs/。
- Dart 依赖只能来自 architecture §11 版本表。已登记可用：`crypto` 3.x（sha256）、`drift_dev` 2.35.1（本任务不需要）。表外依赖先停下汇报；JSON Schema 校验库不在表内，见下文处理方式。
- 直接在 main 小步提交推送，不开 PR。证据存 evidence/i0/I0-c/（tee）。不把 mock 当完成；规格矛盾选最保守做法并写进"偏离/疑问"。
- 必读：docs/30-rules-engine/engine-spec.md（全文，尤其 §8、§12、§12.1）、docs/30-rules-engine/bank-rules-spec.md §3/§5、docs/20-architecture/adr/ADR-004、ADR-008、architecture §3/§10；packages/rules-protocol/README.md（规范化 JSON 与哈希规则、字段约定、断言语义、v1 修订记录、Dart 端同步清单）；packages/rules-protocol/schema/v1/*.json；services/api/cardflow/planner/engine/（money、billing、cash、verifier、protocol、plan 中与验证相关的部分）与 tests/engine/、tests/protocol/（尤其 test_rejections、test_review_wave3_fixes、test_differential 与 diff_reference.py）；apps/mobile/README.md 与 I-0b 的接口说明（领域层不依赖数据库；`lib/app/money/money_format.dart` 的 `minorDigits` 要移入领域层）。

## 1. 纯 Dart 领域包 `apps/mobile/packages/cardflow_domain`
- 不依赖 Flutter、drift；`dart test` 可独立运行；主 App 以 path 依赖引入。
- **禁止 double 的可执行检查**：一个测试扫描包内 lib/ 的 Dart 源码，出现 `double` 类型、`.toDouble()`、`num` 字面量小数即失败（允许在注释中出现）。金额用 `int` 最小单位；利率与系数用十进制字符串/分数（自写最小 `Rational` 或用 `BigInt` 分数），不用浮点。
- 模块与 Python 引擎 1.1.0 一一对应（语义以 engine-spec §12/§12.1 为准）：
  - `money`：minorDigits 表（与 money.py 一致）、toMinor/fromMinor（超精度拒绝，不取整）、显式取整模式（HALF_UP/DOWN/HALF_EVEN/UP）、`decimalText` 规范形式（去尾零，与 Python `money.decimal_text` 一致）。
  - `time`：日期（本地业务日期，无时区混淆）、带偏移的时间戳解析（自写，不引入 tz 数据库；时间戳的日期按其自身偏移计算，必须等于事件 `on`）、精度枚举。
  - `billing`：规则版本选择（按入账日、效期区间）、固定日/账单后 N 日、当月/次月偏移、月末截断、闰年、账单日当天归属开关、入账窗口多账期（取最早到期保守）、工作日与顺延（需日历，无日历则不顺延）、`BillingRuleError`。
  - `cash`：逐账户时间线；快照包含关系（includes 只允许快照日当天及以前）；同日顺序（全部带时间戳才按时间戳，否则保守"先支出后收入"）；情景（include_expected、income_delay_days、income_scale、expense_scale、event_overrides、same_day_order；**快照反映判定先于情景变换**；被改日期的事件丢弃时间戳；移到快照日前的事件按快照日计入并记假设）；缺口点全部列出，含 gap_to_zero / gap_to_reserve / min_on；全局底线（检查点含快照日）。
  - `verifier`：与 Python `verify` 同义：数据检查（NEEDS_DATA 的 data_issues）、三层容量（卡、信用账户、额度池；扣除成员卡的预授权与预留后截零）、还款额 = 分配 + 费用、费用向上取整/收益向下取整、计划还款早于快照日记违规并按快照日计入、还款日晚于 horizon_end 为违规、未知卡号为违规、非整数金额直接报错、按时间戳排序的日子里计划还款排最前、`structural_ok` 与 `ok`、每情景检查结果、加权缓冲天数。
  - `search`：有限搜索（K≤3）：候选切点枚举（各卡容量、最小拆分、金额整除等切点，按 engine-spec §8 与 ADR-004），以验证器为可行性预言机，找到则给出方案并标注 `proven: false`（"本地找到可行方案，非最优证明"），找不到输出"本地未找到（非证明无解）"；时间预算 ≤2 s（可配置）；并列时按卡输入顺序取字典序最大分配（与 Python 平局规则一致）。
  - `protocol`：严格读取 v1 文档（`parseJson` 拒绝重复键、NaN、BOM；布尔不算整数；浮点金额直接拒绝；`additionalProperties` 封闭对象；README"字段约定"里 JSON Schema 表达不了的规则全部实现，可对照 tests/protocol/test_rejections.py 的用例清单）；`ProtocolError` 带 JSON Pointer 路径，不回显原值；`canonicalJson`（键按 UTF-16 代码单元排序、非整数按 ECMAScript 规则、UTF-8 不转义，控制字符转义与 Python `json.dumps(ensure_ascii=False)` 一致）与 `protocolInputHash`（crypto 的 sha256）。F-18 的哈希必须等于 `ea990327f08b42d476fa157d9bb8ddff6a1d8eb4e41ff60b1e498c5861a91ee8`；README 的测试向量全部通过。
  - 输出：`VerificationResult` 与 `CardCycles` 的 JSON 形状必须符合 `PlanOutcome.schema.json` 中对应的 `$defs`（由 parity job 用 Python 校验）。
- 本任务不做 JSON Schema 通用校验库（表外）；Dart 端只实现适配层的严格检查。Schema 层校验由 Python 运行器在 CI 的 parity job 完成。

## 2. Dart fixture 运行器
- `dart run cardflow_domain:run_fixtures [fixture...]`（或等价入口）：读 `packages/rules-protocol/fixtures/*.v1.json`，运行 `cycles` 与 `verify` 两类 case，`plan` 类 case 报告"未运行（需 CP-SAT）"；断言语义按 README（JSON Pointer、where/then、严格相等、length）；全部一致退出 0，否则 1，输入非法 2。
- `--dump <dir>`：把每个 case 的 Dart 输出写成规范化 JSON。
- Python 运行器加 `--dump <dir>` 选项，写出同样命名的参考输出（只加选项，不改既有行为；现有 Python 测试必须继续通过：`uv run --project services/api pytest -q tests/protocol`）。
- **parity**：对 F-18 的全部 cycles/verify case，Dart 输出与 Python 输出逐字节一致（规范化 JSON 后 diff 为空）。

## 3. 测试（`dart test`）
- 移植 tests/engine 中的 test_billing（8）、test_cash（9）、test_properties 中与验证器/现金相关的性质（自写带固定种子的生成器，每条 ≥100 例）、test_regression_sample 的 cycles/verify 部分、test_review_wave3_fixes 与 test_robustness 中与验证器/现金/协议相关的用例、tests/protocol/test_rejections 与 test_review_wave3_protocol 中适配层相关的用例。期望值与 Python 测试相同。
- 有限搜索：F-18 样本返回 A 800000 + C 200000 可行（proven=false）；K=1 返回"本地未找到（非证明）"；时间预算生效。
- 禁止 double 的扫描测试；canonical JSON 与哈希的测试向量；运行器退出码测试。
- 主 App：`MoneyText` 改为引用领域包的 minorDigits；`flutter analyze --fatal-infos`、`flutter test`、`flutter build web` 继续通过。

## 4. CI
- dart job 增加：`dart test` 于领域包；`dart format`/`dart analyze --fatal-infos` 于领域包。
- 新 job `protocol-parity`（ubuntu-latest）：安装 uv 与 Flutter → `uv sync --locked`（services/api）→ Python 运行器 `--dump` → Dart 运行器 `--dump` → diff 两目录为空 → Python 用 jsonschema 校验 Dart 输出符合 `PlanOutcome` 的对应 `$defs`。任一步失败即红。
- 不触发 iOS 构建。

## 5. 文档
- `packages/rules-protocol/README.md` 追加"Dart 端实现与 parity"一节（运行器用法、--dump、parity job、未覆盖项）。
- `apps/mobile/README.md` 追加领域包说明（分层、禁止 double、如何加测试）。

## 验收（evidence/i0/I0-c/）
dart-test.txt、no-double-scan.txt、hash-vectors.txt（含 F-18 哈希）、runner-dart.txt、runner-python.txt、parity-diff.txt（空 diff 的证明与 case 数量）、bounded-search.txt（F-18 K≤3 与 K=1 的输出与耗时）、flutter-checks.txt（analyze/test/build web）、ci-runs.txt（dart 与 protocol-parity job 的运行号与结论）、git-log.txt。

## 回复格式
1. 完成项与路径；2. 验收结果（引用证据）；3. 与 Python 引擎的已知差异清单（应为空；不为空则逐条解释）；4. 偏离/疑问（规格需主会话裁决的点、表外依赖诉求）；5. 给 I-1 的接口说明：领域包 API（Money、Date、BillingRule、CashTimeline、verify、boundedSearch）、如何从本地数据库映射到协议输入、测试辅助。
