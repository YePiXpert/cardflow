# apps/mobile — 卡序 iOS App（Flutter）

本目录是卡序的 Flutter 工程（I-0a 骨架；I-0b 加密本地库）。构建、触发 iOS 构建、下载与签名安装见根 README 的"移动端"一节；计划见 `docs/80-delivery/ios-first-plan.md`。

## 目录

| 路径 | 内容 |
|---|---|
| `lib/main.dart` | 入口：建立 Provider 容器、安装错误钩子、启动 App |
| `lib/app/` | App 外壳：`app.dart`（MaterialApp、语言）、`router.dart`/`routes.dart`（go_router，五个主导航）、`shell/`（底部 Tab）、`theme/`（`tokens.dart` 设计 token 唯一来源，`app_theme.dart` 浅色/深色主题）、`money/`（金额格式与 `minorDigits` 表、全局金额隐藏开关）、`widgets/`（`MoneyText`、首次空白态等） |
| `lib/features/<模块>/` | 功能模块：`overview` 总览、`cards` 卡包、`planner` 规划、`promotions` 发现、`settings` 我的、`onboarding` 欢迎页、`diagnostics` 诊断页与内存日志 |
| `packages/cardflow_domain/` | 纯 Dart 领域包（I-0c）：金额、日期、账期、现金时间线、独立验证器、有限搜索、规则协议 v1 与 fixture 运行器；App 以 path 依赖引入，见下文"领域层" |
| `lib/data/db/` | 加密本地库（drift + SQLite3MultipleCiphers，见下文"加密本地库"） |
| `test/` | 单元与 widget 测试；`test/ios/ios_config_test.dart` 在 Linux 上检查 iOS 工程配置；`test/data/db/` 在真实 sqlite3mc 上测试加密本地库 |
| `ios/` | iOS 工程：`Flutter/CardFlow.xcconfig`（Bundle ID 与签名参数的唯一来源）、`Runner/PrivacyInfo.xcprivacy`（隐私清单） |
| `web/` | 只用于 CI 的 Web 编译烟雾测试，不发布 |

## 约定

- 依赖版本写死到补丁号，取自 `docs/20-architecture/architecture.md` §11；表外依赖先评审再加。
- Riverpod 用代码生成（`@riverpod`）。改了带注解的文件后：`dart run build_runner build`，再 `dart format .`；生成的 `*.g.dart` 随源码提交（CI 不跑生成）。
- 颜色、字号、间距、圆角只从 `lib/app/theme/tokens.dart` 取；金额一律用 `MoneyText`（整数最小单位 + 币种）。
- 诊断日志只记事件标识与脱敏摘要：不得写入金额、卡号、账单正文；数字会被替换为 `#`。
- iOS：最低 15.0；插件走 Swift Package Manager（Flutter 3.47 默认），目前没有 Podfile。若将来引入只支持 CocoaPods 的插件，Podfile 必须写 `platform :ios, '15.0'`（测试会检查）。
- 不提交任何签名材料（证书、描述文件、团队 ID、entitlements）。在 Mac 上自行签名时，把团队 ID 写进不入库的 `ios/Flutter/CardFlow.local.xcconfig`。
- 重新运行 `flutter create` 时必须带 `--org li.yep`，否则会生成错误的包名。

## 加密本地库（I-0b，ADR-001 PoC-1）

**方案**：drift 2.35.2 + sqlite3 3.7.1。`pubspec.yaml` 末尾的 `hooks.user_defines.sqlite3.source: sqlite3mc`
让 sqlite3 包的构建钩子把 [SQLite3MultipleCiphers](https://github.com/utelle/SQLite3MultipleCiphers)（sqlite3mc）
而不是普通 SQLite 打进 App（写法出处：drift 文档 Encryption 页、sqlite3 包的 `doc/hook.md`；摘录见
`evidence/i0/I0-b/hook-source.txt`）。钩子不在本机编译，而是从 sqlite3.dart 的 GitHub release 下载
预编译库并用包内记录的 sha256 校验；iOS 上它成为 `Runner.app/Frameworks/sqlite3mc.framework`。
不需要 Podfile，也不需要任何 entitlement。

**密钥**：首次启动用 `Random.secure()` 生成 32 字节，存 iOS 钥匙串（flutter_secure_storage 11.2.0；
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`，不同步 iCloud 钥匙串，不设 access group）。
以原始密钥（`PRAGMA key = "x'…'"`）交给 sqlite3mc，跳过口令派生；算法固定为 `chacha20`
（ChaCha20-Poly1305）。密钥不进日志、诊断报告和异常消息（`DatabaseKey.toString()` 也不输出内容）。

**失败即止**：数据库在 drift 的后台 isolate 中打开，任何读写之前（drift 的 `setup`）依次检查：
`PRAGMA cipher` 非空 → 固定算法 → 设置密钥（结果须为 `ok`）→ 读 `sqlite_master` 验证密钥 →
`sqlite3mc_version()` 非空；打开后再确认文件头不是明文 SQLite 头。任一步失败都关闭连接、抛
`DatabaseOpenException`（只含错误码），绝不退回明文库。数据库文件已有数据而钥匙串没有密钥时报
`key_missing`，不会新建密钥覆盖旧库。

> 规划文档写的是"`PRAGMA cipher_version` 为空即拒绝"。`cipher_version` 是 SQLCipher 的 PRAGMA，
> sqlite3mc 2.6.1 对它总是返回空（`test/data/db/encryption_test.dart` 有一条测试记录这一点），照字面执行会让
> 数据库永远打不开；因此改用上面 sqlite3mc 自己的检查（drift 文档推荐 `PRAGMA cipher`），诊断报告里仍如实
> 列出 `PRAGMA cipher_version` 的原始结果。

| 错误码 | 含义 |
|---|---|
| `cipher_unavailable` | 加载的不是加密构建（钩子没有选中 sqlite3mc） |
| `wrong_key` | 密钥打不开该库（SQLITE_NOTADB）：密钥错误或文件损坏 |
| `key_missing` | 库已有数据但钥匙串没有密钥（例如从设备备份恢复到新手机） |
| `key_invalid` / `key_store_failed` / `key_apply_failed` | 钥匙串内容格式不对 / 钥匙串读写失败 / 设置密钥失败 |
| `plaintext_database` | 打开后发现文件是明文 SQLite |
| `schema_too_new` / `migration_failed` | 库来自更新版本的 App（拒绝降级）/ 迁移失败（整体回滚） |
| `location_unavailable` / `open_failed` / `unsupported_platform` | 取不到目录 / 其他 SQLite 错误 / Web |

**文件位置**：`Library/Application Support/cardflow.sqlite`（"文件"App 里看不到）；sqlite3 临时文件与
"数据库基准"临时库在 `Library/Caches`。

**代码**（`lib/data/db/`）：

| 文件 | 内容 |
|---|---|
| `database_providers.dart` | `databaseProvider`（`Future<AppDatabase>`，供仓库使用）、`openedDatabaseProvider`（含加密库信息与是否新建）、钥匙串与目录 provider（测试替换点）、`databaseKeyExistsProvider` |
| `app_database.dart` | `AppDatabase`（drift `GeneratedDatabase`，目前无代码生成）、`readMeta()`、`readCipherInfo()` |
| `schema.dart` | `LocalSchema.currentSchemaVersion`、v1 的 `meta` 表、`schemaMigrations` 迁移登记表、`createSchema` / `migrateSchema` |
| `database_opener.dart` | `openAppDatabase`：取密钥 → 加密连接 → 迁移 → 文件头检查；错误码映射 |
| `encryption.dart` | sqlite3mc 检查与设置密钥（drift 的 `setup`） |
| `database_key.dart` | `DatabaseKey`、`DatabaseKeyStore`（钥匙串实现）、`DatabaseKeyManager`（只生成一次） |
| `database_benchmark.dart` | "数据库基准"：临时加密库写 10 万行 → 关闭 → 重开 COUNT |
| `database_platform*.dart` | 平台实现：iOS 用 dart:io + drift_flutter；Web 一律 `unsupported_platform` |

**加表与迁移**（I-1 起）：把 `LocalSchema.currentSchemaVersion` 加 1；在 `schemaMigrations` 登记"旧版本 → 旧版本+1"
的一步（只做 expand：加表、加列、建索引）；`createSchema` 建出最新完整结构；测试新建与升级两条路径结构一致。
迁移在一个事务里执行，失败整体回滚。业务表若改用 drift 的表 DSL，需要代码生成器 drift_dev——它不在
architecture §11 版本表内，引入前须评审登记。

**诊断页**（我的 › 诊断信息 › 加密本地库）：加密库状态（成功显示 `SQLite3 Multiple Ciphers <版本>` 与算法，
失败显示错误码）、数据库密钥（只显示"已生成/未生成"）、「运行数据库基准（10 万行）」（写入、重新打开、
COUNT 的毫秒数，进入复制的报告；ADR-001 PoC-1 的退出条件"10 万行冷启动 <1 s"以真机结果为准）。
诊断日志记 `db/opened`（created/existing）、`db/open_failed`（错误码）、`db/benchmark_*`。

**测试**：`test/data/db/` 用的是钩子提供的真实 sqlite3mc（本机与 CI 的 `flutter test` 都会运行钩子，
需要能访问 GitHub release）；钩子没有选中 sqlite3mc 时第一条测试以明确的信息失败，不会跳过。
组件测试默认用 `test/test_helpers.dart` 的 `fakeDatabaseOverrides()` 替换加密库状态；需要真实加密库的
组件测试要在 `tester.runAsync` 里先把 provider 算好（例子见 `diagnostics_page_test.dart`）。

## 领域层（I-0c）：`packages/cardflow_domain`

**分层**：领域层是独立的纯 Dart 包（不依赖 Flutter、drift、数据库），App 在 `pubspec.yaml` 里以 path
依赖引入。依赖只向下：页面/Provider → 用例 → 领域包；数据层（drift 加密库）负责把表行映射成领域对象
或协议 v1 文档，领域包本身不读写数据库。语义与服务端 Python 引擎 1.1.0
（`services/api/cardflow/planner/engine/`）一一对应，以 `docs/30-rules-engine/engine-spec.md` §12/§12.1 为准。
金额展示组件 `MoneyText` 的最小单位位数表就是领域包的 `minorDigits`（`lib/app/money/money_format.dart`
只转导出，不再自带一份）。

| 库 | 内容 |
|---|---|
| `package:cardflow_domain/cardflow_domain.dart` | `Money`/`minorDigits`/`toMinor`/`fromMinor`/`applyRate`/`decimalText`/`Rational`/`RoundingMode`；`LocalDate`/`Timestamp`/`TimePrecision`；`BillingRule`/`cyclesForTransaction`/`selectRule`/`resolveCycle`；`CashEvent`/`Snapshot`/`Scenario`/`buildTimeline`/`evaluate`；`CardOption`/`PlanRequest`/`ModelInputs`/`capacityLayers`/`classify`；`verify`；`dataIssues`/`baselineCheck`；`boundedSearch`；协议 v1：`parseJson`、`canonicalJson`、`protocolInputHash`、`inputsFromProtocol`、`inputsToProtocol`、`verifyFromProtocol`、`cardCyclesToProtocol` |
| `package:cardflow_domain/fixture_runner.dart` | golden fixture 运行器（依赖 dart:io，App 不引用） |
| `package:cardflow_domain/testing.dart` | 测试辅助：按 Python 测试写法构造协议文档（`protocolCard`、`protocolDocument`…）、带种子的随机文档（`randomPlanInput`） |

**禁止 double**：领域包的 `lib/`、`bin/`、`tool/` 里不得出现 `double`、`num`、`toDouble()` 一类调用、小数或
指数字面量，以及浮点除法 `/`（整数除法用 `~/`）。金额是 `int` 最小单位；利率、情景系数是 `Rational`
（BigInt 分数），取整只通过 `RoundingMode` 显式进行；JSON 里唯一的非整数（`options.time_limit_s`）用 binary64
的精确整数表示（`JsonFloat`）。可执行检查是 `test/no_double_test.dart`：它去掉注释与字符串内容后扫描代码，
先用正反例自检扫描器本身；注释里写这些字样是允许的。

**命令**（在 `apps/mobile/packages/cardflow_domain` 下）：

```bash
dart pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test                                                     # 全部领域测试（含禁止 double 的扫描）
dart run cardflow_domain:run_fixtures [--dump DIR] [FIXTURE ...]  # golden fixture 的 cycles/verify case
dart run cardflow_domain:bounded_search [--max-cards K] [--budget-ms N] [--json] FILE_OR_DIR
dart run tool/gen_parity_fixtures.dart DIR [--count N] [--seed S]  # 跨语言一致性用的随机 fixture
```

App 自己的 `flutter analyze` 排除了 `packages/**`（领域包有自己的分析配置，用上面的 `dart analyze` 检查）。

**如何加测试**：

- 测试放在 `packages/cardflow_domain/test/`，用 `dart test` 运行，不依赖 Flutter。期望值取自 Python 引擎的
  测试或实际输出（测试注释写明出处）；与 Python 逐字一致的文本（违规消息、假设说明、规则错误）要逐字断言。
- 协议文档用 `package:cardflow_domain/testing.dart` 的构造函数（与 Python 测试的 `card()`/`document()` 同一默认值），
  F-18 与 Python 源码用 `test/support/repo.dart` 读取（从当前目录向上找仓库根）。
- 性质测试用 `TestRandom`（固定种子）与 `randomPlanInput`，每条性质至少 100 例。
- 新的 golden fixture 放 `packages/rules-protocol/fixtures/*.v1.json`：两端运行器都会自动运行，CI 的
  protocol-parity job 逐字节比较两端输出（见 `packages/rules-protocol/README.md`"Dart 端实现与 parity"）。

