# I-0 阶段末审查报告（简报 R-I0）

- 日期：2026-10-18；审查时仓库 HEAD `8b331b3`。被审查的代码自 `fdd7433`（CI 运行 39114057360 全绿）起没有变化，之后的提交只改文档（`git diff --stat fdd7433..HEAD -- apps .github packages services` 只有 `packages/rules-protocol/README.md` 的两行文字，见 `review-i0/ci-workflow-check.txt`）。
- 只读审查：仓库内已有文件一律未改；新建的只有本报告与 `evidence/i0/review-i0/`（复现输出与脚本副本）。临时文件都在 `/tmp/rv/`。
- 结论：**blocker 0 条，major 0 条，minor 15 条，疑问 5 条。**双端语义差分（18,000 个盲区输出、20,000 份变异文档、5,489 个 JSON 用例、42 个边界文档、5,000 份搜索对照）只发现一处接受/拒绝分歧（JSON 嵌套 513 层以上，Dart 更严格）。需要优先处理的两条 minor：R-15（I-1a 的"重置本地数据"会触发数据不可读，见 Q-5）与 R-01（有限搜索漏报可行方案，见 Q-1）。

## 1. 范围与方法

### 1.1 范围

`apps/mobile/`（App 与 `packages/cardflow_domain/`）、`.github/workflows/mobile.yml`、`packages/rules-protocol/runner_py/run_fixtures.py` 的 `--dump` 改动（提交 16cb2da 的 diff）、`evidence/i0/I0-a|I0-b|I0-c/`。`services/api/` 只作语义基准阅读与运行，不审查。

### 1.2 读过的对照依据

engine-spec §1–§12.1（重点 §8、§12、§12.1）；bank-rules-spec §1–§3、§5；ADR-001、ADR-004、ADR-008、ADR-015；security-privacy §1–§5；packages/rules-protocol/README.md 全文（字段约定、断言语义、v1 修订记录、Dart 同步清单、"Dart 端实现与 parity"）；briefs I0-a/I0-b/I0-c、apps/mobile/README.md、根 README"移动端"、backlog、handoff；为写 §4 另读了 briefs I1-a/I1-b/I1-c。

Python 引擎逐模块对照阅读：`money.py`、`billing.py`、`cash.py`、`verifier.py`、`allocation.py`（`CardOption`、`capacity_layers`、`card_limit`、`classify`、`_low_series`、`build_model`、`solve` 的平局处理）、`plan.py`（`data_issues`、`baseline_check`、`plan` 的早停顺序）、`protocol.py` 全文；测试：`tests/protocol/test_rejections.py`、`test_review_wave3_protocol.py`、`test_adapter.py`、`test_limits.py`，`tests/engine/` 各文件的用例清单，`diff_reference.py` 的 `gen_doc`。

Dart 侧逐文件阅读：领域包 `lib/src/` 全部 23 个文件、`bin/` 两个入口、`tool/gen_parity_fixtures.dart`、`test/` 全部；App 的 `lib/` 全部（重点 `lib/data/db/`、`lib/features/diagnostics/`、`lib/app/money/`、`router.dart`）、`test/data/db/`、`test/features/diagnostics/`、`test/ios/ios_config_test.dart`；`ios/` 的 Info.plist、PrivacyInfo.xcprivacy、xcconfig、pbxproj；drift_flutter 0.3.1 的 `native.dart`（确认 setup 的调用时机、没有打开 WAL）。

### 1.3 运行了什么（命令原文；输出见 §5）

基线（`export PATH=/opt/flutter-sdk/bin:$PATH`）：

```bash
cd apps/mobile/packages/cardflow_domain && dart format --output=none --set-exit-if-changed . && dart analyze --fatal-infos && dart test   # 265 项全过
cd apps/mobile && dart format --output=none --set-exit-if-changed . && flutter analyze --fatal-infos && flutter test           # 154 项全过，无 skip，真实 sqlite3mc
cd services/api && uv run --project /projects/cardflow/services/api pytest -q tests/protocol tests/engine                    # 434 项全过
```

差分与探针（脚本副本都在 `evidence/i0/review-i0/scripts/`；`/tmp/rv/dart` 是一个以 path 依赖引用领域包的临时包，用来跑 `json_diff.dart`、`adapter_diff.dart`）：

| 目的 | 做法 | 证据 |
|---|---|---|
| 生成器覆盖不到的分支（重点 1） | `gen_blind.py`：闰年/世纪年与月末、10^13 级金额、任意 5 位小数费率、10 位小数情景系数、混合偏移（Z、−00:00、+14:00、+05:45、±23:59）与 1–6 位小数秒、`effective_from/to`、`next_business_day`/工作日规则、快照晚于交易日、horizon 早于交易日或快照日、入账窗口至 40 天、共享信用账户与池、大额全局底线、非 ASCII 名称；6 个种子 × 600 份 × 5 个 case，两端运行器 `--dump` 后 `diff -r` | parity-blind-spots.txt |
| 适配层拒绝清单（重点 2） | `gen_mutants.py`：20,000 份变异文档（改类型、删成员、加未知成员、浮点记号、复制 ID 造重复/错引用、增删数组项），两端逐份比较裁决、JSON Pointer、消息与 input_hash；`gen_limits_cases.py`：`test_limits.py` 的 42 个边界文档 | adapter-differential.txt、limits-differential.txt |
| 严格 JSON 与规范化 JSON（重点 2） | `gen_json_cases.py`：5,489 个用例（随机小数/指数记号、binary64 相邻值中点 ±10^-60、次正规与最大值边界、4300/4301 位整数、转义与孤立/成对代理项、非法 UTF-8、BOM、控制字符、深度 1–3000、重复键、300 组 Unicode 键排序），比较 `parse_json`+`canonical_json` 与 `parseJson`+`canonicalJson` 的字节 | json-differential.txt、python-side-observations.txt |
| 有限搜索（重点 3） | 与 Python `plan_from_protocol` 逐份对照：`gen_parity_fixtures.dart` 种子 11–15 各 1,000 份（小金额，Dart 逐一枚举），种子 11、12 金额 ×100003（只走切点）；构造全局底线反例；协议上限文档（200 卡/100 账户/10,000 事件/5 情景）上测预算 | bounded-search.txt、cli-errors.txt |
| 加密库与密钥（重点 4、5） | 在 apps/mobile 下用 `flutter test` 跑仓库外的四个探针：原始密钥是否绕过 KDF；`containsKeyMaterial` 能否发现进入日志的密钥；sqlite3mc 编译选项；wrong_key 后"删库删密钥再打开"重启后能否读回 | db-probes.txt |
| CI 与卫生（重点 6、8） | grep 工作流、`gh run list`；扫描邮箱/令牌/IP/Luhn 卡号/宿主信息 | ci-workflow-check.txt、hygiene-scan.txt |

## 2. 发现清单（按级别排序）

### blocker

无。

### major

无。

### minor

**R-01 · minor · 有限搜索的候选切点不考虑全局底线，存在可行的两卡方案时报"本地未找到"**
- 位置：`apps/mobile/packages/cardflow_domain/lib/src/search.dart:462-511`（`_assign` 的切点：上下限、本卡单独的现金余量、其余卡余量的补足额、等分、共享额度层剩余）、`:622-753`（`_MarginModel` 只按单个现金账户建余量；`cashCut` 只看本卡的还款账户）。全局底线只在验证器里出现（`verifier.dart:216-248`）。
- 现象：反例 `review-i0/scripts/global_floor_band.json`（合成数据）：两个现金账户各 100,000.00 元，全局底线 196,000.00 元；B 卡 11-05 从账户 2 还款、11-10 账户 2 到账工资 6,065.00 元、A 卡 11-25 从账户 1 还款且费率 1%，交易 10,000.00 元。B 段的全局底线要求 x_A ≥ 600000，A 段要求 ceil(0.01·x_A) ≤ 6500 即 x_A ≤ 650000。Python CP-SAT：FEASIBLE_ROBUST，A 600000 + B 400000，proven_optimal True；验证器确认 [600000, 650000] 内可行、两端外一单位即不可行。Dart：只评估 5 个候选（x_A ∈ {1, 999999, 500000} 与两张单卡），全部被全局底线拒绝，输出"本地未找到（非证明无解）"，`exhausted true`；预算放宽到 60 s 结果相同。
- 复现：`uv run --project services/api python evidence/i0/review-i0/scripts/make_cx.py /tmp/rv/cx/global_floor_band.json`，再 `(cd apps/mobile/packages/cardflow_domain && dart run cardflow_domain:bounded_search /tmp/rv/cx/global_floor_band.json)`。
- 范围说明：在小金额（逐一枚举）的 5,000 份随机文档上 Dart 与 CP-SAT 结论与分配完全一致；金额放大 ×100003 后的 2,000 份里没有出现"CP-SAT 可行而 Dart 未找到"，只有 0.5%–0.9% 给出非最优分配（BL-10 已登记）。漏报需要切点完全没有覆盖到的约束，全局底线是已确认的一类。
- 建议：把"全局底线"当作一个虚拟账户（余量 = 各账户当日最低点合计 − 底线）加入 `_MarginModel`，生成与单账户相同的 `cashCut`/补足额切点；两卡组合再加一个以验证器为预言机、沿 x 二分可行边界的补充切点。把本反例做成领域包测试。与 BL-10 合并跟踪（严重度见 Q-1）。

**R-02 · minor · 时间预算是软上限：最后一次验证器调用与最终全情景验证不受预算约束**
- 位置：`search.dart:228`（从入口起计时，数据检查、各情景基线、余量模型都计入预算）、`:417`（每 1024 个组合查一次）、`:522`（每次调用验证器前查一次）、`:542-544`（单次验证不可中断）、`:319`（找到后对全部情景再验证一次，在预算之外）。
- 现象：协议上限文档（AOT 编译的同一 CLI，本机服务器 CPU）：`--budget-ms 2000` → elapsed 2065 ms；`--budget-ms 100` → 174 ms；`--budget-ms 0` → 83 ms（全部是建模前开销）。超出量约等于一次验证器调用加一次全情景验证；手机上会更多。engine-spec §8、ADR-004 写的是"预算 ≤ 2 s"。
- 复现：`uv run --project services/api python evidence/i0/review-i0/scripts/make_big.py /tmp/rv/cx/big_limits.json 0`；在临时包 `/tmp/rv/dart` 中把 `bin/bounded_search.dart` 复制为 `bin/bs.dart` 后 `dart compile exe bin/bs.dart -o /tmp/rv/bs`；`/tmp/rv/bs --budget-ms 2000 /tmp/rv/cx/big_limits.json`。
- 建议：枚举截止时间 = 预算 − 预估的最终验证耗时（用已测得的单次验证耗时 × 情景数），或在 README/engine-spec §8 写明"≤ 预算 + 一次全情景验证"；结果里给出超出量，UI 据此提示。

**R-03 · minor · 测试辅助 `containsKeyMaterial` 发现不了进入诊断日志的密钥（覆盖不真实）**
- 位置：`apps/mobile/test/data/db/db_test_support.dart:95-99`；只用它判断的地方：`test/features/diagnostics/diagnostics_page_test.dart:227`；`test/data/db/database_providers_test.dart:268-279` 另断言了不含 `x'`。
- 现象：诊断日志把 detail 中所有数字换成 `#`（`lib/features/diagnostics/diagnostic_log.dart:203-211`）。假设某处把密钥写进日志，报告行是 `x'####################aabbccddeeff##################a#bacbdcedfe#f'`——十六进制里的字母全部保留，而辅助函数的三个条件（完整 hex、大写 hex、前 16 位）一个也不命中；`Uint8List` 的十进制字节列表形式同样不命中。只有 `database_providers_test` 额外的 `x'` 断言能拦住 `rawKeyLiteral()` 这一种写法，`encode()` 的裸 hex 拦不住。已核对：现有代码没有任何把密钥写进日志、报告或异常的路径（§3.5），所以这是测试缺口而非泄露。I-1a 简报要求"现有 containsKeyMaterial 类检查继续通过"并扩展到金额与卡号。
- 复现：`(cd apps/mobile && flutter test /tmp/rv/ftest/key_leak_probe_test.dart)`（副本 `scripts/key_leak_probe_test.dart`），输出 `containsKeyMaterial(line) = false`。
- 建议：对密钥 hex 的每个 ≥8 字符窗口检查原样、大写、数字掩码（0–9→`#`）三种形态，另查 base64 与十进制字节列表；diagnostics_page_test 同样断言不含 `x'`。

**R-04 · minor · 严格 JSON 的嵌套深度与 Python 不同，注释与 BL-11 的数值不准确**
- 位置：`apps/mobile/packages/cardflow_domain/lib/src/protocol/json.dart:41-42`（注释"Python 的 json 在约 1000 层时因递归上限报错"，`maxJsonDepth = 512`）；`docs/80-delivery/backlog.md` BL-11（"Python 约 1000"）。
- 现象：实测 Python 3.13 的 `parse_json` 接受到约 1 万层（数组 9,998 层仍接受，9,999 层起报 nested too deeply；对象的阈值略低，5,000 层仍接受）；Python 的 `canonical_json` 从约 995 层起抛未处理的 `RecursionError`。Dart 从 513 层起拒绝。5,489 个 JSON 用例中这是唯一的接受/拒绝分歧（14 例，深度 513–995；另 6 例深度 ≥1000 时两端都拒绝）。PlanInput 是封闭对象，只有 fixture 的 `equals` 期望值这类任意 JSON 能触及，且 Dart 是更严格的一方。
- 复现：见 `review-i0/json-differential.txt` 末尾的深度探测。
- 建议：改正注释与 BL-11 的数字；512 可以保留。

**R-05 · minor · CI 的产出计数断言不完整，存在"少了也绿"的情形**
- 位置：`.github/workflows/mobile.yml:156-157`（golden 只断言 Python 输出数 > 0，F-18 当前为 3）；`:198-211`（schema 校验只要求至少 1 个文件，不断言等于 3 + 1200）。
- 现象：如果 F-18 的 verify case 被删，或 Dart 的 dump 目录层级变化导致 `*/dart/*/*.json` 漏掉某一组，两端 `diff -r` 只比较各自产出的文件，相关步骤仍可能绿。随机 fixture 的 `test "$n" -eq 1200` 是到位的。
- 建议：golden 按 fixture 中 cycles/verify case 的数量断言相等；schema 步骤断言 `checked == {'cycles': 301, 'verify': 902}`（或由 Python dump 的文件数推出）。

**R-06 · minor · 第三方 action 只固定到大版本/标签**
- 位置：`mobile.yml:75、125、131、232`（`subosito/flutter-action@v2`、`astral-sh/setup-uv@v10.3.0`；`actions/*@v7` 同理）。
- 现象：`ios-unsigned` job 产出的 IPA 由用户直接重签安装；被篡改或被劫持的第三方 action 可以改写构建产物，`permissions: contents: read` 挡不住这一点。
- 建议：固定到 40 位提交 SHA（行尾注释写版本号），由 Dependabot 提升。

**R-07 · minor · `bounded_search` 命令行对错误输入以未处理异常退出（255），与文档的 0/2 不符**
- 位置：`apps/mobile/packages/cardflow_domain/bin/bounded_search.dart:28-47`（`int.parse(args[++i])`）、`:72-95`（`BoundedSearchOptions(maxCards: …)` 与 `readAsBytesSync` 在 `on ProtocolError` 之外）。
- 现象：文件不存在、`--max-cards 4`、`--budget-ms` 缺值都打印栈并退出 255；同类输入下 `run_fixtures` 按约定退出 2。
- 复现：`review-i0/cli-errors.txt`。
- 建议：捕获 `FileSystemException`、`ArgumentError`、`FormatException`、`RangeError`，打印用法并 `exitCode = 2`。

**R-08 · minor · Release 构建仍把未捕获错误的正文打印到系统日志**
- 位置：`apps/mobile/lib/features/diagnostics/error_hooks.dart:26-37`。
- 现象：钩子记完脱敏日志后仍调用原来的 `FlutterError.onError`（Release 下 `dumpErrorToConsole` 用 `debugPrintStack` 打印 `exception.toString()`），`PlatformDispatcher.onError` 返回 `false`（引擎再打印一次）。I-0 没有含用户数据的异常，但 security-privacy §3 CODE 要求"调试日志在 Release 关闭"，I-1 起表单校验、导入解析的异常可能带用户输入。
- 建议：`kReleaseMode` 下不转发给原处理器、`onError` 返回 `true`；debug 保持现状；加测试。

**R-09 · minor · 根 README 对 CI 触发条件的描述已过时**
- 位置：`README.md:47`。
- 现象：写的是"dart job：apps/mobile/ 或该工作流有变动时运行"；实际 paths 还包括 `packages/rules-protocol/**`、`services/api/cardflow/planner/engine/**`、`pyproject.toml`、`uv.lock`，且有 `protocol-parity` job。
- 建议：照 `mobile.yml` 头部注释改写。

**R-10 · minor · I0-c 证据里有几条命令不是原文，无法逐字复现**
- 位置：`evidence/i0/I0-c/ci-runs.txt:27、33、73`（`gh run view … --log | grep <关键行>`）；`hash-vectors.txt:45`（`python -c "...protocol_input_hash(...)"`）；`parity-diff.txt:26-33`（"本机加测 6 个种子 × 1000 份"与覆盖面 JSON 没有命令与脚本）。
- 影响：结论本身被本次复现支持（§3.1、§3.3），但证据可复现性不足。
- 建议：以后证据写出完整命令，或把脚本放进证据目录（本次 `review-i0/scripts/` 的做法）。

**R-11 · minor · 公开证据里留有宿主信息**
- 位置：`evidence/i0/I0-a/flutter-doctor.txt:6、41-48`（发行版与内核版本、`HTTP_PROXY is set`）；I0-a/I0-b 的多数证据含 flutter 的"以 root 运行"提示。
- 现象：不是服务/端口清单，也没有代理地址或凭据，风险低；但生产 VPS 的内核版本与运行身份进了公开仓库。
- 建议：以后的证据过滤这两类行（本次证据用 `grep -Ev` 滤掉并在文件头写明）；既有证据是否改写由主会话决定。

**R-12 · minor · `Money` 的加减不做 64 位溢出检查**
- 位置：`apps/mobile/packages/cardflow_domain/lib/src/money.dart:137-146`。
- 现象：`toMinor`、`roundToInt` 等路径都用 `checkedInt` 拒绝溢出，`Money +/-` 却会静默回绕（现实金额不可达，9.2×10^16 元量级）。与"绝不静默截断"的约定不一致。
- 建议：用 `checkedInt(BigInt…)` 或断言统一行为。

**R-13 · minor · `ios_config_test` 注释说"只看纳入版本控制的文件"，实现是遍历目录**
- 位置：`apps/mobile/test/ios/ios_config_test.dart:12-28`。
- 现象：在自签用的 Mac 上存在被忽略的 `ios/Flutter/CardFlow.local.xcconfig`（含团队 ID）时测试会误报失败。CI 上无影响，方向保守。
- 建议：显式跳过 `CardFlow.local.xcconfig`，或改用 `git ls-files`。

**R-14 · minor · Dart 测试没有移植的 Python 协议用例**
- 位置：`apps/mobile/packages/cardflow_domain/test/protocol_adapter_test.dart`、`test/fixture_runner_test.dart`。
- 现象：`tests/protocol/test_limits.py` 的 BOUNDARY（23 个上下限）、PROBE、数组上限 200/100/10000（及 +1）在 Dart 测试里一条都没有；`test_review_wave3_protocol.py` 的 R3E-13 运行器用例（需要日历的规则上跑 verify case 不崩溃）没有对应的运行器测试。行为本身已逐例验证一致：42 个边界文档两端裁决、指针、消息、input_hash 全同（limits-differential.txt）；R3E-13 路径在本次盲区 parity 中被 7,160 个带数据问题的 verify case 覆盖。
- 建议：把这 42 个向量与一个 R3E-13 运行器用例补进领域包测试，防止以后回归。

**R-15 · minor · `DatabaseKeyManager` 把第一次取到的密钥永久缓存，没有失效接口；I-1a 的"重置本地数据"会因此建出一个打不开的库**
- 位置：`apps/mobile/lib/data/db/database_key.dart:123-142`（成功后的 `_pending` 永不清除，后续调用忽略 `databaseHasData`）；`apps/mobile/lib/data/db/database_providers.dart:29-31`（`databaseKeyManagerProvider` 为 keepAlive）。
- 现象：I-0 中没有触发路径。但 I-1a 简报要求在 `wrong_key` 时提供"删除数据库文件与钥匙串密钥后重新初始化"。若实现只失效 `openedDatabaseProvider`，`obtain()` 会返回缓存的旧密钥：新库用旧密钥加密，钥匙串里却没有密钥；下次启动 `databaseHasData = true` 且读不到密钥 → `key_missing`，重置后录入的数据全部无法读取。（`key_missing` 之后的重置不受影响：失败的 Future 会被清掉。）探针已复现：`step2=wrong_key; after reset: created=true, keychain empty; after restart: key_missing`。
- 复现：`(cd apps/mobile && flutter test /tmp/rv/ftest/reset_trap_probe_test.dart)`（副本 `scripts/reset_trap_probe_test.dart`，输出在 `db-probes.txt` 第 4 节）。
- 建议：给 `DatabaseKeyManager` 加 `forget()`（或重置流程同时 `invalidate(databaseKeyManagerProvider)`），并写"wrong_key → 重置 → 写入 → 模拟重启 → 能读回"的测试。见 §4 第 1 条；严重度见 Q-5。

### 疑问（未定级）

- **Q-1**：handoff 写明"只做 iOS 端，纯本地模式；后端已冻结"，有限搜索因此是用户唯一的规划器。按 engine-spec §8 的字面，R-01 的漏报是允许的行为（"本地未找到（非证明无解）"），但在纯本地模式下它直接表现为"有方案却说找不到"。是否把 R-01 升为 major，在 I-2 之前修？
- **Q-2**：`ios/Runner/PrivacyInfo.xcprivacy` 声明了 DiskSpace（E174.1）与 UserDefaults（CA92.1），App 自身代码没有用到；是否由 Flutter 引擎、插件或 `sqlite3mc.framework`（不自带隐私清单）调用，在 Linux 上无法核实。security-privacy SEC-M-25 要求"与实际一致"，而 I0-a 简报指定了这四项。保留，还是在下次 iOS 构建时扫描二进制符号后再定？
- **Q-3**：security-privacy §3 CODE 要求"Release 混淆（Dart obfuscate）"，CI 的 iOS 构建没有 `--obfuscate --split-debug-info`。混淆会让诊断日志里的代码位置不可读（需要保存符号文件再还原）。v1 是否启用？
- **Q-4**：Python 端（已冻结）有两处未处理异常：`canonical_json` 对孤立代理项作键抛 `UnicodeEncodeError`，对约 995 层以上的嵌套抛 `RecursionError`（而 `parse_json` 接受到约 9,998 层）。两端都拒绝，parity 不受影响（python-side-observations.txt）。是否像 BL-09 一样登记到后端解冻时修？
- **Q-5**：R-15 目前没有触发路径，所以定为 minor；但 I-1a 简报照字面实现"重置本地数据"时就会触发，后果是重置后录入的数据在下次启动时全部 `key_missing`（探针已复现）。是否按 major 处理，在派发 I-1a 前修 `DatabaseKeyManager` 或把要求写进 I-1a 简报？

## 3. 已核对无问题的项（便于以后不重复审）

### 3.1 金额与日期语义（重点 1）

逐函数对照，结论"同义"，并由差分验证：
1. `money`：`minorDigits` 与 money.py 逐项一致（测试读 Python 源码比对）；`toMinor` 超精度拒绝不取整（比 Python `Decimal(str)` 更严：不接受空白、下划线、非 ASCII 数字，作为 App 输入是更安全的方向）；`fromMinorText` 与 `str(from_minor)` 相同；`applyRate` 与四种取整一致，`UP` 即 `ROUND_CEILING`，`DOWN` 朝零；`decimalText` 与 `decimal_text` 相同（Python `normalize()` 的 28 位精度只在 >28 位有效数字时才有差别，协议值最多 12 位，不可达）。
2. 取整方向：费用 = 费率部分向上 + 固定费（金额 > 0），已核实/潜在收益向下并封顶，`verify` 与搜索目标同一算法。Python 的 Decimal 运算在协议上限内不会触发 28 位上下文舍入：`_scale` ≤ 25 位、`apply_rate` ≤ 19 位；加权缓冲 `(Σx·d / M).quantize(0.1)` 的双重舍入，分界点距离 ≥ 1/(20M)，远大于 28 位精度的步长，不可能翻转（含 `-0.0` 的写法，Dart 已复刻）。
3. `time`：Hinnant 日期算法、闰年（含 2100 非闰、2000/2400 闰）、`clampDay` 月末截断、`addMonths` 负数进位、时间戳按自身偏移取日期、同日排序按绝对时刻、`isoformat` 与 Python 相同（`Z`→`+00:00`、`-00:00`→`+00:00`）。
4. `billing`：账单日当天归属开关、固定日与账单后 N 日、`month_offset` 0–2、到期不晚于账单日报规则错误、入账窗口多账期去重后按到期日稳定排序取最早、版本生效区间（窗口内任一入账日不生效即整卡报错）、需要日历时报错且消息与 Python `str(e)` 逐字相同。
5. `cash`：快照反映判定按原始事件且先于情景变换；被移到快照日前的事件按快照日计入并记假设；改期事件丢弃时间戳；同日顺序（全部已有事件带时间戳才按时间戳，计划还款排最前，空日也走时间戳分支，与 Python `all([])` 相同）；零额事件不进 low 点 ID；缺口点规则（快照点或有流出的 low 点）；`min_on` 取最早；各账户不互抵。
6. `verifier`/`checks`/`allocation`：三层容量逐层截零（账户层只对 ≥2 张卡的信用账户、池层扣成员卡预授权与预留）；排除顺序与 Python 相同；早于快照日的计划还款按快照日计入并记违规；晚于 horizon 为 `REPAY_AFTER_HORIZON`；未知卡为违规且不参与后续计算；全局底线检查点含各快照日；`data_issues` 顺序与字段相同。
7. 64 位整数：在协议上限内，余额、合计与全局合计的最大量级约 1.0×10^18，低于 int64 上限 9.2×10^18；验证器的加权缓冲用 BigInt；`roundToInt` 越界抛错。
8. 差分结果：盲区生成器 6 个种子 × 3,000 个输出 = 18,000 个 cycles/verify 输出两端逐字节相同（含 945 个落在 2 月 29 日的账期、全部 5 种假设文本、经协议可达的 4 种规则错误、verify 路径上的 5 种数据问题、经协议可达的全部违规类型、1,635 个负加权缓冲、4,460 个全局底线缺口）。随机生成器（CI 同款）的盲区记录见本节末。

生成器盲区（`tool/gen_parity_fixtures.dart` 与 Python `gen_doc` 相同，都覆盖不到）：交易日只在 2026-01-01 起 400 天内（无 2 月 29 日）；金额 ≤ 60；每份文档只有一个时区偏移、秒为 00、无小数秒；`holiday_rollover` 恒为 none；无 `effective_from`；快照不会晚于交易日；horizon 总晚于交易日；`stale_after_days` 恒为 7；情景系数只有 8 个固定值；入账窗口 ≤ 6 天；最多 4 张卡、3 个账户、16 笔事件。以上全部由第 8 条的盲区生成器覆盖。

### 3.2 协议适配层（重点 2）

1. `test_rejections.py`：BOTH 35 条、ADAPTER_ONLY 14 条在 `protocol_adapter_test.dart` 中逐条存在，期望指针相同；`test_review_wave3_protocol.py` 中适配层相关的 R3E-04、R3E-11（5 + 8 条）、R3E-12（16 + 3 条）、R3E-13（4 条）、R3E-14（2 组）、R3E-20（12 条）、R3E-21 都有对应。没有 Dart 对应但不适用的：R3E-02（PlanOutcome 与 schema）、R3E-11 的引擎内部哈希、R3E-18（schema 文案）、R3E-20 的 format checker、R3E-22（README 文案）。未移植的见 R-14。
2. 20,000 份变异文档：两端裁决、JSON Pointer、消息、input_hash 逐份相同（16,463 份拒绝、3,537 份接受，触发 153 种拒绝消息，覆盖全部交叉规则：ID 唯一、单币种、还款账户与事件账户引用、同信用账户同可用额与池、includes 只列本账户事件、覆盖只指向已有事件且不重复、入账延迟顺序、保留事件前缀、`at` 的日期等于 `on`）。成员读取顺序与 Python 一致，所以同一份非法文档报告同一指针。
3. `test_limits.py` 的 42 个边界文档两端完全一致（R-14）。
4. 严格 JSON：重复键、NaN/±Infinity、溢出字面量（1e400、1e99999999）、BOM（字节与文本两种）、非 UTF-8（过长编码、编码的代理项、>U+10FFFF、截断序列）、控制字符、非法转义、尾随数据、4300/4301 位整数都与 Python 同判；整值浮点 `1.0` 读成浮点并在整数字段被拒。
5. 规范化 JSON：5,014 个两端都接受的用例规范化字节全部相同，包括约 2,000 个 binary64 舍入中点 ±10^-60 的扰动记号（就近、恰半取偶）、次正规数、最大有限值、`-0.0`、ECMAScript 指数格式、UTF-16 键序（BMP 私用区与增补平面字符混排）、`ensure_ascii=False` 的转义集合（含 U+007F、U+2028 原样）。孤立代理项在字符串与键中都被拒（Dart 报 ProtocolError，Python 见 Q-4）。F-18 哈希 `ea990327…1ee8`。
6. `inputsToProtocol` 与 Python `inputs_to_protocol` 写法一致（规范利率文本、includes 按码点排序、时间戳 `isoformat`），并会再跑一遍 `inputsFromProtocol`。

### 3.3 有限搜索（重点 3）

1. `proven` 是常量 getter（`search.dart:139`），`toJson` 与 CLI 两条输出路径都只读它；没有其他字段或文案声称最优或无解；`needsData`/`baselineShortfall`/`notFound` 的文案都不说"无解"。
2. 早停顺序与 Python `plan()` 相同：数据问题（含 `UNKNOWN_DECISION_SCENARIO`）→ 各情景基线、决策情景不满足即停（failing 列表同 Python）→ 建模前排除 → 搜索；没有可用卡时报 notFound（Python 为 INFEASIBLE，Dart 措辞更保守）。
3. 平局规则：在 5,000 份小金额文档上（种子 11–15，含请求 K>3 的文档）与 CP-SAT 的业务状态、分配、failing 场景全部一致；目标层定义与 CP-SAT 模型相同（费用变量在最优解处取最小值、收益封顶、缓冲与用卡数）。
4. 预算在枚举阶段生效（每次调用验证器前、每 1024 个组合检查一次），超出量见 R-02；零预算一个候选也不评估。
5. 余量模型 `_BlockRangeMin` 的断点、稀疏表与区间查询正确（查询端点都是断点；`_dateCount == 0` 在可达输入中不会出现：每张可用卡的还款日都是其账户的检查点）。

### 3.4 加密库失败即止（重点 4）

1. 打开顺序（`encryption.dart:104-138`）：`PRAGMA cipher` 非空 → 固定 `chacha20` 且读回相等 → `PRAGMA key` 结果必须为 `ok` → 读 `sqlite_master`（SQLITE_NOTADB → `wrong_key`）→ `sqlite3mc_version()` 非空；全部在 drift 的 `setup` 中、任何读写之前执行（drift_flutter 0.3.1 `native.dart:133` 把 `setup` 交给 `NativeDatabase`）。任一步失败：`openAppDatabase` 关闭连接并只抛错误码（`database_opener.dart:87-90`），provider 不重试、不缓存可用库。
2. 原始密钥：探针证实 `PRAGMA key = "x'<64 hex>'"` 不经 KDF（把 `kdf_iter` 改为 1 仍能打开；同样的十六进制当口令打不开），README 的"跳过口令派生"属实。
3. 没有退回明文的路径：不是加密构建时 `PRAGMA key` 根本不会执行；已有明文库 → `wrong_key` 且文件不动（有测试）；打开后再查文件头；密钥字面量永不为空（sqlite3mc 的空密钥即不加密）；钩子提供的库编译为 `TEMP_STORE=2`（临时表与排序默认在内存，探针在同一 release 的 Linux 构建上读 `PRAGMA compile_options` 确认），drift_flutter 不开启 WAL。
4. 密钥缺失：文件有数据而钥匙串无密钥 → `key_missing`，不会新建密钥覆盖；钥匙串读写异常 → `key_store_failed`，失败的 Future 会被清除以便重试；新密钥写入后读回不一致即失败，不建库。
5. Web 条件导入：`export 'database_platform_stub.dart' if (dart.library.io) 'database_platform_io.dart'`，iOS 有 `dart:io`，不可能选中桩实现；桩实现一律 `unsupported_platform`。
6. 错误码是固定字符串的枚举，与 README 表一致；`DatabaseOpenException.toString()` 只含错误码与 SQLite 结果码。
7. 基准用只在内存中的随机密钥、不碰钥匙串与正式库，文件名与正式库不同，结束即删。

### 3.5 密钥与日志（重点 5）

1. `PRAGMA key` 语句的异常被吞掉换成 `key_apply_failed`（`SqliteException.toString()` 会带语句全文）；`DriftRemoteException` 逐层解包后只留错误码；`DatabaseKey.toString()` 输出 `<redacted>`；钥匙串异常正文不外传（有测试）。
2. 诊断日志：category/event 只能是常量形态；detail 取首行、数字换 `#`、截断 120；错误只记类型与 FlutterError/AssertionError 的脱敏摘要和代码位置；路由只记模板（`fullPath`）。
3. 诊断报告与页面：版本、构建、Bundle ID、系统版本、Dart 版本、语言区域、文字缩放、外观、加密库状态、密钥"已生成/未生成"、基准毫秒数、日志；失败只显示错误码或异常类型。没有设备名、路径或其他个人数据。
4. 测试输出：仓库里只有公开的测试密钥常量；R-03 是检测能力的缺口，不是泄露。

### 3.6 CI（重点 6）

1. `defaults.run.shell: bash` 使每一步以 `bash --noprofile --norc -eo pipefail` 运行；多行脚本另有 `set -euo pipefail`。
2. 没有 `continue-on-error`；`|| true` 只出现在 iOS job 的 `flutter doctor -v > build-logs/…`（诊断输出）。
3. `flutter pub get --enforce-lockfile`、`dart pub get --enforce-lockfile`、`uv sync --locked` 都在；之后的 `uv run` 不带 `--locked`，但锁文件已先被验证。
4. `dart test` 在 `${{ env.DOMAIN_DIR }}` 下运行；领域包的 format/analyze 也在该目录。
5. golden 与随机两步都在 `diff -r` 前断言 Python 有产出（随机为 =1200）；Dart 少文件会以 `Only in` 失败，目录不存在会以 diff 出错失败；schema 步骤在没有文件时失败（计数不足见 R-05）。
6. `paths` 覆盖领域测试读取的 Python 源码（`services/api/cardflow/planner/engine/**`）与 fixture、schema；`services/api/cardflow/__init__.py` 等包初始化文件不在列表内（无实际影响）；推送 `ios-v*` 标签与手动触发不受 paths 影响。并发组含 `event_name`，push 不会取消手动的 iOS 构建。
7. 最近运行：39114057360（fdd7433）与 39114777414（d74deeb）均为 success；之后代码未变。

### 3.7 iOS 配置（重点 7）

Bundle ID 只在 `CardFlow.xcconfig` 定义（pbxproj 不含 `li.yep`）；团队 ID、签名身份为空，无 entitlement、描述文件、证书；6 个 target 配置都以 Debug/Release.xcconfig 为基础且不覆盖签名；`IPHONEOS_DEPLOYMENT_TARGET` 全部 15.0，无 Podfile；Info.plist 显示名"卡序"、语言 zh_CN/en、无用途说明、无后台模式、无 App Group；PrivacyInfo 不跟踪、不收集、已加入资源阶段。`ios_config_test.dart` 覆盖以上全部（注释问题见 R-13）。I0-b 的 IPA 检查显示 `sqlite3mc.framework` 的 MinimumOSVersion 也是 15.0。

### 3.8 公开仓库卫生（重点 8）

扫描范围内（173 个跟踪文件）：邮箱只有 `users.noreply.github.com`（20 处，提交身份）；没有令牌、私钥特征；IP 只有 flutter doctor 里的 127.0.0.1；13–19 位数字串中没有通过 Luhn 校验的卡号形态（测试里的 622202… 是故意构造的非法号）；没有服务或端口清单。宿主信息见 R-11。

### 3.9 证据（重点 9）

1. 文件齐全：I0-a 8/8、I0-b 8/8、I0-c 10/10，与各简报的验收清单逐项对应。
2. 是工具原文：带命令行、时间戳、提交号与退出码，CI 日志为 `gh run view` 原样输出。
3. 可复现性：本次复现了 265/154/434 项测试、F-18 哈希、F-18 的 cycles 与两个 verify 输出（两端 sha256 与 I0-c/parity-diff.txt 记录的完全相同）、有限搜索 F-18 结论（A 800000 + C 200000，proven false；K=1 未找到）与 I0-c 的 CP-SAT 对照（种子 11–13 结论相同）。命令不全的几处见 R-10。
4. `run_fixtures.py` 的 `--dump` 只新增了选项与写文件函数，既有行为不变（diff 只有参数解析、`enumerate` 与一处写文件调用）；Python 434 项测试通过。

## 4. 对 I-1 的建议

1. **重置本地数据（BL-07）必须同时让密钥管理器忘掉缓存**：给 `DatabaseKeyManager` 加 `forget()` 或在重置流程中 `invalidate(databaseKeyManagerProvider)`，并写"wrong_key → 重置 → 写入 → 模拟重启 → 读回"的测试（R-15）。
2. **数据层到领域层走适配层的校验**：交给 `verify`/`boundedSearch` 的数据先经 `inputsToProtocol`（它会再跑一遍 `inputsFromProtocol`）。只用现金时间线的页面（I-1b 的资金日历）在仓库层复刻交叉规则：`at` 的日期按自身偏移等于 `on`、`includes` 只列快照日当天及以前本账户事件、同一信用账户的卡同一可用额与池、金额 |v| ≤ 10^13、ID 唯一、币种一致。领域对象的构造函数不做这些检查（与 Python 数据类相同）；若希望在领域包里提供公开的校验函数，需要主会话先裁决（I-1 简报不允许改领域包）。
3. **强化 `containsKeyMaterial`**（R-03），I-1a 要求的"日志与报告不含金额、末四位以外的卡片数字、别名"用同样的掩码形态匹配（日志会把数字换成 `#`，按原样查数字永远查不到）。
4. **Release 下错误正文不进系统日志**（R-08），在表单与导入出现之前做。
5. **迁移步骤幂等**：drift 在 `onUpgrade` 返回之后才写 `user_version`；崩溃发生在两者之间时下次会重跑 expand 步骤，`CREATE TABLE` 会失败成 `migration_failed`。用 `IF NOT EXISTS`，或在同一事务内设置 `user_version`。
6. **校验 `PRAGMA foreign_keys` 已生效**：`beforeOpen` 只执行不读回（`app_database.dart:44`）；I-1 的业务表依赖外键与触发器，读回不是 1 时应失败即止。
7. **钥匙串暂时不可用（`key_store_failed`）提供"重试"**：目前数据库 provider 不重试、要求重启 App；设备锁定等暂时性失败应能在原页面重试。
8. **币种约束前移**：领域包与 `MoneyText` 只认 13 种币种，未知币种在渲染时抛错；库表的币种列加 CHECK 或枚举。
9. **`AppDatabase` 只允许 `openAppDatabase` 构造**：现在构造函数是公开的，仓库代码可以直接用一个未加密的执行器 new 出来而绕过全部检查；改成私有构造 + 工厂或加 `@visibleForTesting` 约束。
10. **有限搜索在 I-2 之前补两件事**：R-01 的反例做成测试并加全局底线切点；预算为最终验证预留时间（R-02）。另在下次 iOS 构建时于 macOS runner 上扫描二进制对 Required Reason API 的调用，据此定 PrivacyInfo（Q-2）。

## 5. 复现输出索引（`evidence/i0/review-i0/`）

| 文件 | 内容 |
|---|---|
| `domain-baseline.txt` | 领域包 format/analyze/test（265 项） |
| `app-baseline.txt` | App format/analyze/test（154 项，无 skip） |
| `python-baseline.txt` | `pytest -q tests/protocol tests/engine`（434 项） |
| `golden-parity.txt` | F-18 golden fixture 双端 `--dump` 与 diff（与 CI 同命令），输出 sha256（§3.9） |
| `parity-blind-spots.txt` | 盲区 fixture 双端 parity：6 个种子、18,000 个输出逐字节相同，附覆盖面统计（§3.1） |
| `adapter-differential.txt` | 20,000 份变异文档的适配层对照与触发到的全部拒绝消息（§3.2） |
| `limits-differential.txt` | `test_limits.py` 的 42 个边界文档两端对照（R-14） |
| `json-differential.txt` | 5,489 个严格 JSON/规范化 JSON 用例对照与 Python 深度阈值（R-04、§3.2） |
| `python-side-observations.txt` | Python 端两处未处理异常（Q-4） |
| `bounded-search.txt` | 全局底线反例（R-01）、与 CP-SAT 的 7,000 份对照（§3.3）、协议上限文档的预算测量（R-02）、F-18 的 K≤3 与 K=1 复现（§3.9） |
| `cli-errors.txt` | `bounded_search` 命令行错误处理（R-07） |
| `db-probes.txt` | 原始密钥不经 KDF 的探针（§3.4）、`containsKeyMaterial` 检测缺口（R-03）、sqlite3mc 编译选项（`TEMP_STORE=2`）、重置后数据不可读的复现（R-15） |
| `ci-workflow-check.txt` | 工作流静态检查、最近 6 次运行、fdd7433 之后的代码变化（§3.6、R-05、R-06） |
| `hygiene-scan.txt` | 邮箱/令牌/IP/卡号形态/宿主信息扫描（§3.8、R-11） |
| `scripts/` | 本次使用的全部脚本与反例文档（`global_floor_band.json`）；`*_test.dart` 是在 apps/mobile 下用 `flutter test <路径>` 运行的探针 |
