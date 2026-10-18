# apps/mobile — 卡序 iOS App（Flutter）

本目录是卡序的 Flutter 工程（I-0a 骨架；I-0b 加密本地库；I-0c 领域包；I-1a 本地库 v2、真实/演示工作空间、
建卡/信用账户/账期规则/额度快照；I-1b 本地库 v3、现金账户与快照、收支计划与周期事项、情景、资金日历）。构建、触发 iOS 构建、下载与签名安装见根 README 的"移动端"一节；计划见
`docs/80-delivery/ios-first-plan.md`。

## 目录

| 路径 | 内容 |
|---|---|
| `lib/main.dart` | 入口：建立 Provider 容器、安装错误钩子、启动 App |
| `lib/app/` | App 外壳：`app.dart`（MaterialApp、语言、演示横幅）、`router.dart`/`routes.dart`（go_router：启动分流、五个主导航、卡包栈）、`startup/`（启动分流 `app_gate.dart`、启动页与"重置本地数据"确认页）、`diagnostics/`（内存环形诊断日志）、`shell/`（底部 Tab）、`theme/`（`tokens.dart` 设计 token 唯一来源，`app_theme.dart` 浅色/深色主题）、`money/`（金额格式与 `minorDigits` 表、全局金额隐藏开关）、`widgets/`（`MoneyText`、首次空白态、状态视图、空间标识、演示横幅、确认框、轻提示） |
| `lib/features/<模块>/` | 功能模块：`overview` 总览（P-01，含现金压力卡）、`cards` 卡包（P-02 卡包与新建卡片、P-03 详情、P-04 设置）、`planner` 规划（P-10 与规划 Tab 的分段条）、`cash` 现金与收支（P-08：账户、快照、收支计划、周期事项、调拨）、`calendar` 资金日历（P-07）、`scenarios` 情景与对比（P-09）、`promotions` 发现、`settings` 我的、`onboarding` 欢迎页（P-22）与空间切换、`diagnostics` 诊断页 |
| `lib/data/db/` | 加密本地库（drift + SQLite3MultipleCiphers，见下文"加密本地库"）：表定义、迁移、打开、重置 |
| `lib/data/repositories/` | 仓库（按当前工作空间过滤）、读模型 `CardWalletReader`/`CashPlanReader`/`CashForecastReader`、数据层 provider（当前工作空间、时钟、各仓库），见下文"工作空间与演示模式""仓库与 provider""现金与资金日历" |
| `lib/data/mapping/` | 数据层 → 领域对象映射：`domain_mapping.dart`（规则版本 → `BillingRule`、预测账期与 3 期预览、快照与授信池 → `CardOption`/`ModelInputs` → `capacityLayers`）；`cash_mapping.dart`（现金账户/快照/事件/情景 → `CashAccount`/`Snapshot`/`CashEvent`/`Scenario`，交叉校验、输入哈希、情景计算结果 JSON） |
| `lib/data/time/` | 业务时区（只支持固定偏移时区）、入账日推导（截止时点）、时钟（演示空间固定"今天"） |
| `lib/data/validation/` | G2/G5 与末四位校验（仓库与界面共用一套文案） |
| `lib/data/demo/` | 演示空间的合成数据 |
| `lib/data/ids.dart` | UUID v4（`Random.secure()`，不引入 uuid 包） |
| `packages/cardflow_domain/` | 纯 Dart 领域包（I-0c）：金额、日期、账期、现金时间线、独立验证器、有限搜索、规则协议 v1 与 fixture 运行器；App 以 path 依赖引入，见下文"领域层" |
| `test/` | 单元与 widget 测试；`test/ios/ios_config_test.dart` 在 Linux 上检查 iOS 工程配置；`test/data/db/`、`test/data/repositories/` 在真实 sqlite3mc 上测试加密本地库与仓库；`test/support/sensitive_text.dart` 查日志与报告里的敏感内容 |
| `ios/` | iOS 工程：`Flutter/CardFlow.xcconfig`（Bundle ID 与签名参数的唯一来源）、`Runner/PrivacyInfo.xcprivacy`（隐私清单） |
| `web/` | 只用于 CI 的 Web 编译烟雾测试，不发布 |

## 约定

- 依赖版本写死到补丁号，取自 `docs/20-architecture/architecture.md` §11；表外依赖先评审再加。
- 代码生成：Riverpod（`@riverpod`）与 drift 表 DSL（drift_dev 2.35.1，§11 已登记）。改了带注解的文件或
  `lib/data/db/tables.dart` 后：`dart run build_runner build`，再 `dart format .`；生成的 `*.g.dart` 随源码提交
  （CI 不跑生成）。provider 的返回类型不要直接用 drift 生成的行类型（同一轮生成里 riverpod_generator 看不到它们），
  用手写的值对象包一层（例：`Workspace`、`WalletView`、`AccountSettingsData`）。
- 颜色、字号、间距、圆角只从 `lib/app/theme/tokens.dart` 取；金额一律用 `MoneyText`（整数最小单位 + 币种）。
- 诊断日志只记事件标识与脱敏摘要：不得写入金额、卡号、别名与账单正文；数字会被替换为 `#`。日志在
  `lib/app/diagnostics/`（数据层也写日志，不得向上依赖 `lib/features/`，BL-06）。Release 构建里未捕获错误
  只进环形日志，不再打印到系统日志（`error_hooks.dart`，审查 R-08）。
- 文本输入：凡可能被误填卡号的输入框都 `autofillHints: null`（关闭系统自动填充，包括卡号填充）。
- iOS：最低 15.0；插件走 Swift Package Manager（Flutter 3.47 默认），目前没有 Podfile。若将来引入只支持 CocoaPods 的插件，Podfile 必须写 `platform :ios, '15.0'`（测试会检查）。
- 不提交任何签名材料（证书、描述文件、团队 ID、entitlements）。在 Mac 上自行签名时，把团队 ID 写进不入库的 `ios/Flutter/CardFlow.local.xcconfig`。
- 重新运行 `flutter create` 时必须带 `--org li.yep`，否则会生成错误的包名。

## 加密本地库（I-0b，ADR-001 PoC-1；I-1a 起 schema v2，I-1b 起 v3）

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
`DatabaseKeyManager` 在进程内缓存取到的密钥；"重置本地数据"用 `deleteKey()`（删除钥匙串条目并忘掉缓存），
否则重新建库会沿用缓存的旧密钥、下次启动成了 `key_missing`（审查 R-15，测试见 `database_providers_test.dart`）。

**失败即止**：数据库在 drift 的后台 isolate 中打开，任何读写之前（drift 的 `setup`）依次检查：
`PRAGMA cipher` 非空 → 固定算法 → 设置密钥（结果须为 `ok`）→ 读 `sqlite_master` 验证密钥 →
`sqlite3mc_version()` 非空；迁移提交后打开外键检查并**读回**（不是 1 即失败）；最后确认文件头不是明文
SQLite 头。任一步失败都关闭连接、抛 `DatabaseOpenException`（只含错误码），绝不退回明文库。数据库文件已有
数据而钥匙串没有密钥时报 `key_missing`，不会新建密钥覆盖旧库。`AppDatabase` 的构造函数是私有的，只能经
`openAppDatabase` 取得（测试用 `@visibleForTesting` 的 `AppDatabase.forTesting`），仓库代码无法拿未加密的执行器
绕过检查（审查 §4 第 9 条）。

> 规划文档写的是"`PRAGMA cipher_version` 为空即拒绝"。`cipher_version` 是 SQLCipher 的 PRAGMA，
> sqlite3mc 2.6.1 对它总是返回空（`test/data/db/encryption_test.dart` 有一条测试记录这一点），照字面执行会让
> 数据库永远打不开；因此改用上面 sqlite3mc 自己的检查（drift 文档推荐 `PRAGMA cipher`），诊断报告里仍如实
> 列出 `PRAGMA cipher_version` 的原始结果。

| 错误码 | 含义 | 启动页提供 |
|---|---|---|
| `cipher_unavailable` | 加载的不是加密构建（钩子没有选中 sqlite3mc） | 说明、诊断信息 |
| `wrong_key` | 密钥打不开该库（SQLITE_NOTADB）：密钥错误或文件损坏 | 「重置本地数据」 |
| `key_missing` | 库已有数据但钥匙串没有密钥（例如从设备备份恢复到新手机） | 「重置本地数据」 |
| `key_invalid` / `key_store_failed` / `key_apply_failed` | 钥匙串内容格式不对 / 钥匙串读写失败（例如设备锁定）/ 设置密钥失败 | 后两者「重试」 |
| `plaintext_database` | 打开后发现文件是明文 SQLite | 说明 |
| `schema_too_new` / `migration_failed` | 库来自更新版本的 App（拒绝降级）/ 迁移失败（整体回滚） | 后者「重试」 |
| `foreign_keys_unavailable` | 打开后 `PRAGMA foreign_keys` 读回不是 1（I-1a 新增，审查 §4 第 6 条） | 说明 |
| `reset_failed` | "重置本地数据"时删不掉数据库文件（钥匙串条目删不掉报 `key_store_failed`） | 「重试」 |
| `location_unavailable` / `open_failed` / `unsupported_platform` | 取不到目录 / 其他 SQLite 错误 / Web | 前两者「重试」 |

**启动页与恢复**（`lib/app/startup/`）：数据库打开中 → 启动页"正在打开本机加密数据…"；打不开 → 启动页显示
错误码与说明。可重试的错误在原页面「重试」（`DatabaseRecovery.retry()`，不要求重启 App，审查 §4 第 7 条）；
`key_missing`/`wrong_key` 提供「重置本地数据」→ 确认页（写明影响，输入"删除"才可执行，ui-spec §4.5）→ 关闭连接、
删除数据库文件与钥匙串密钥、忘掉密钥缓存 → 按首次使用重新打开 → 自动进 P-22。诊断日志只记 `db/retry`、
`db/reset`、`db/reset_failed`（错误码）。诊断页任何时候都可到达。

**文件位置**：`Library/Application Support/cardflow.sqlite`（"文件"App 里看不到）；sqlite3 临时文件与
"数据库基准"临时库在 `Library/Caches`。

**代码**（`lib/data/db/`）：

| 文件 | 内容 |
|---|---|
| `database_providers.dart` | `databaseProvider`（`Future<AppDatabase>`，供仓库使用）、`openedDatabaseProvider`（含加密库信息与是否新建）、钥匙串与目录 provider（测试替换点）、`databaseKeyExistsProvider`、`databaseRecoveryProvider`（重试与重置） |
| `app_database.dart` | `AppDatabase`（drift `@DriftDatabase`，私有构造）、`openAppDatabase`（取密钥 → 加密连接 → 迁移 → 外键读回 → 文件头检查）、`ensureForeignKeys`、`readMeta()`、`readCipherInfo()`；生成文件 `app_database.g.dart` |
| `tables.dart` | v2、v3 业务表的 drift 表 DSL（列、主键、唯一键、CHECK、复合外键，全部 STRICT） |
| `schema.dart` | `LocalSchema.currentSchemaVersion`（3）、meta 表、冻结的 `SchemaV2`、`SchemaV3`（各自的建表、索引、触发器）、`schemaMigrations`（1→2、2→3）、`createSchema` / `migrateSchema`（同一事务写 `user_version`） |
| `database_failures.dart` | 异常 → 错误码（`databaseOpenExceptionFrom`）、`closeQuietly` |
| `database_reset.dart` | "重置本地数据"：删数据库文件与钥匙串密钥、忘掉缓存 |
| `encryption.dart` | sqlite3mc 检查与设置密钥（drift 的 `setup`） |
| `database_key.dart` | `DatabaseKey`、`DatabaseKeyStore`（钥匙串实现，含 `delete`）、`DatabaseKeyManager`（只生成一次；`forget`/`deleteKey`） |
| `database_benchmark.dart` | "数据库基准"：临时加密库写 10 万行 → 关闭 → 重开 COUNT |
| `database_platform*.dart` | 平台实现：iOS 用 dart:io + drift_flutter；Web 一律 `unsupported_platform` |

**v2 的表**（I-1a，`tables.dart`；约定见 data-model §10.14）：主键 TEXT UUID v4；日期 TEXT `YYYY-MM-DD`；时刻
TEXT RFC 3339 带偏移；金额 INTEGER 最小单位（|v| ≤ 10^13）；币种 CHECK 只允许领域包 `minorDigits` 的 13 种
（审查 §4 第 8 条）；所有业务表带 `workspace_id`，表间用 `(workspace_id, …)` 复合外键，数据库层面不能跨工作空间
关联；自由文本列带 G2 兜底 CHECK（不得含 13 位连续数字）与长度 CHECK；全部 STRICT；同步列暂不建。

| 表 | 要点 |
|---|---|
| `meta` | v1：schema 版本与建库时间 |
| `workspaces` / `app_settings` | 真实/演示工作空间（同一种最多一个未删除的）；当前工作空间 id |
| `banks` | 银行名称与默认业务时区，不带规则；内置常用银行第一次被选用时才写入（`is_builtin`） |
| `credit_pools` | 授信池：`shared_limit_minor` + `currency`（本地新增，见"偏离"）；`parent_pool_id` 保留，只建单层池 |
| `credit_accounts` | 信用账户（账单主体）：银行、产品名、持卡人称呼、业务时区、状态、授信池 |
| `currency_accounts` | 币种子账户，`UNIQUE(credit_account_id, currency)`；建账户时默认建 CNY 主子账户（每账户恰一个主子账户） |
| `cards` | 卡片：末四位 CHECK 恰 4 位数字；主/附（附卡的主卡、换卡的新卡须同一信用账户，复合外键）；状态机触发器兜底 |
| `billing_rule_versions` | 账期规则版本：区间 `[effective_from, effective_to)` 不重叠（触发器兜底）；只能封口；主体须在同一工作空间 |
| `limit_snapshots` | 额度快照：按 DDL，另加 `holds_minor`（见"偏离"）；只追加不修改；临额须到期日、专项须用途 |

**v3 的表**（I-1b，`tables.dart` 与冻结的 `SchemaV3`；13 个索引、9 个触发器；2→3 只加表、索引与触发器，不动 v2 的表与数据，
`schema_test.dart` 比较新建、从 v1 升级、从 v2 升级三条路径的结构完全一致，并核对 v2 的行原样保留）：

| 表 | 要点 |
|---|---|
| `cash_accounts` | 现金账户：名称（G2/G5，同一空间未删除的不重名，部分唯一索引）、币种（13 种，不可改）、种类 `bank`/`wallet`/`wealth`/`restricted`（受限不能直接标可用于还款，CHECK）、`usable_for_repayment`、`available_from`、`reserve_floor_minor ≥ 0`、`status` `active`/`closed` |
| `cash_balance_snapshots` | 余额快照：`balance_minor`（可负）、`balance_as_of`（日期）、`observed_at`（实际时点）、来源、确认层级、`recorded_at`；只追加（触发器） |
| `snapshot_included_events` | 快照已包含的事件；另带 `workspace_id`、`cash_account_id`，用携带账户列的复合外键保证只能是本账户的事件；事件日期不晚于快照日（仓库校验，触发器兜底）；之后不改 |
| `cash_events` | 唯一的现金事实表：`event_on`、`event_at`（按自身偏移的日期必须等于 `event_on`，CHECK）、`amount_minor`（非零、按类别定符号）、`cls`、`category`、`label`、`posting_status`（已发生的必为确定）、`recurring_item_id`+`occurrence_key`、`transfer_group_id`、`linked_repayment_id`、`linked_plan_run_id`；软删除不可撤销，已发生不能退回，调拨两端的日期金额不可改（触发器） |
| `recurring_items` / `recurring_overrides` | 周期事项（频率、锚定日、日规则、起止日、启用）与单期例外（`skip`/`override` 的金额、日期、时刻） |
| `scenarios` / `scenario_runs` | 情景（内置两条参数固定只读，CHECK + 触发器；每个空间每种内置至多一条）与计算版本（版本号唯一递增、只追加、`inputs_hash` 64 位小写十六进制、`result` JSON 对象） |

**加表与迁移**（v3 即照此办理，I-1c 起同样；`schema.dart` 文件头有同样的步骤）：
1. 在 `tables.dart` 加表或加列（drift 表 DSL），`app_database.dart` 的 `@DriftDatabase(tables: …)` 登记新表；
   新的业务表必须带 `workspace_id`，并加进 `workspace_repository.dart` 的 `workspaceDataTables`（删除顺序：子表在前）；
2. 运行 `dart run build_runner build` 与 `dart format .`；
3. `LocalSchema.currentSchemaVersion` 加 1（I-1c 为 v4）；
4. 在 `schema.dart` 新建 `SchemaV<n>`：冻结这一版**新增**的建表语句（`CREATE TABLE IF NOT EXISTS`，内容与 drift
   生成的一字不差——可设 `CARDFLOW_SCHEMA_DUMP_DIR` 跑 `test/data/db/schema_test.dart` 看新库结构）、索引与触发器
   （都带 `IF NOT EXISTS`）；只做 expand，不改写金额原值；
5. `schemaMigrations` 登记 `n-1: _migrateV<n-1>ToV<n>`；`latestIndexes`/`latestTriggers` 加上新版的；
6. `schema_test.dart` 增加"从 v<n-1> 升级"与新建的一致性比较（已有的从 v1、v2 升级的比较保留；升级前写入旧版数据并核对原样保留）；
   约束测试加新约束（v3 的在 `cash_constraints_test.dart`）；`workspace_isolation_test.dart` 的 `runAllQueries` 加新仓库的全部
   查询（没有 `id` 列的表在 `_rowKeys` 里登记行键）；演示数据要写到每一张新表（隔离测试要求两个空间的每张表都有行）。
迁移在一个事务里执行（失败整体回滚，`migration_failed`）；`user_version` 在同一事务里写入，迁移语句可重跑
（测试"重跑 1→2 不报错"）。若 v3 要给 v2 的表**加列**，`ALTER TABLE` 后 SQLite 保存的建表文本与 drift 新建的不同，
一致性比较需改为比较 `PRAGMA table_xinfo` 等结构信息，并在测试里注明。

**诊断页**（我的 › 诊断信息 › 加密本地库）：加密库状态（成功显示 `SQLite3 Multiple Ciphers <版本>` 与算法，
失败显示错误码）、数据库密钥（只显示"已生成/未生成"）、「运行数据库基准（10 万行）」（写入、重新打开、
COUNT 的毫秒数，进入复制的报告；ADR-001 PoC-1 的退出条件"10 万行冷启动 <1 s"以真机结果为准）。
诊断日志记 `db/opened`（created/existing）、`db/open_failed`（错误码）、`db/benchmark_*`、`db/retry`、`db/reset`。

**测试**：`test/data/db/` 与 `test/data/repositories/` 用的是钩子提供的真实 sqlite3mc（本机与 CI 的 `flutter test`
都会运行钩子，需要能访问 GitHub release）；钩子没有选中 sqlite3mc 时第一条测试以明确的信息失败，不会跳过。
组件测试默认用 `test/test_helpers.dart` 的 `pumpCardFlowApp`：加密库状态用 `fakeDatabaseOverrides()`，本地库用内存库
（`AppDatabase.forTesting(NativeDatabase.memory())`，不加密）并按 `TestWorkspace.none/real/demo` 预置工作空间；
测试里要查数据用 `readWallet(tester)`（直接查库，不在 `tester.runAsync` 里建 provider，否则之后伪时钟里的查询会等不到结果）。
需要真实加密库的组件测试要在 `tester.runAsync` 里先把 provider 算好（例子见 `diagnostics_page_test.dart`）。
`test/flutter_test_config.dart` 让 `tap()` 落点被遮挡时直接失败。

## 工作空间与演示模式（I-1a，R-SYS-13、ui-spec §4.2）

- **两个工作空间**：真实（`real`）与演示（`demo`）各最多一个未删除的（部分唯一索引）。"当前工作空间"存在
  `app_settings`（键 `current_workspace_id`）。所有业务仓库都由 `WorkspaceScope`（数据库 + 当前工作空间 id + 时钟）
  构造，查询一律带 `workspace_id`；跨空间的 id 一律"已不存在"。隔离测试 `workspace_isolation_test.dart`：一个空间写满
  全部业务表，以另一个空间为当前空间运行每个仓库的全部查询（含用对方的 id 去查，82 条），结果全部为空；反向亦然。
- **启动分流**（`lib/app/startup/app_gate.dart`，BL-04）：数据库打开中/打不开 → 启动页；没有工作空间 → P-22
  （`/welcome`，任何路由都先到这里）；就绪后进入五个主导航。诊断页不受分流约束。
- **P-22**：「手工建卡」进入（必要时新建）真实空间并打开新建卡片；「体验演示」进入（首次生成）演示空间并转到总览；
  「从账单文件开始」「从备份恢复」「连接服务器」显示但禁用并注明阶段（I-3 / I-4 / 后续）。真实↔演示切换须确认；
  「退出演示」回到真实空间（没有则回到 P-22）；「清除演示数据」确认框写明影响数量，删除演示空间全部行。
- **演示数据**（`lib/data/demo/demo_workspace.dart`，经仓库写入、一个事务）：卡 A/B/C 的账期与可用额与回归样本一致
  （engine-spec §9），另加与 B 同行的卡 D：A 主卡 + 附属卡同一信用账户（F-21）；B 与 D 是同一银行的两个独立授信
  （F-22）且共享"乙行共享额度"池（F-23）；D 可用 −200（F-26）；B 有临时额度 5,000、2026-11-15 到期（F-27）；
  C 的规则带截止时点 22:00。现金部分（I-1b，`seedDemoCash`）：工资卡（储备 2,000）与受限的定期存款（不计入可用现金）、
  工资卡 10-16 的快照（当天早餐已包含、水电费未包含）、与回归样本同一组数值的收支、房租周期事项（每月 27 日，12-27 单期覆盖为
  1,200）、11-01 工资卡 → 定期存款 2,500 的调拨、"收入推迟 3 天"压力情景，并计算"基准预期"与它各一个版本；固定"今天"下
  基准口径 30 天内有一个可见缺口（11-01 定存转出后余额 300，低于储备）。
- **时钟**：`clockProvider` —— 演示空间固定"今天" = 2026-10-16（北京时间 12:00，`demoClock`），陈旧判定不触发；真实空间
  用系统时间。页面与仓库都不直接调用 `DateTime.now()`。
- **演示横幅**：`DemoBannerFrame`（`MaterialApp.builder`）在演示空间时每页顶部常驻紫色横幅（烧瓶 + "演示数据 ·
  与真实数据隔离" +「退出演示」），没有关闭按钮。

## 仓库与 provider（`lib/data/repositories/`，I-1b 起沿用）

| 仓库 | 主要方法 |
|---|---|
| `WorkspaceRepository`（全局） | `current()`、`live(kind)`、`ensure(kind)`、`setCurrent(id)`、`countRows(id)`、`deleteWorkspace(id)` |
| `BankRepository` | `listStored()`、`byId`、`choices()`（内置 + 用户添加）、`ensureByName(name)` |
| `CreditAccountRepository` | `list()`、`byId`/`require`、`create(NewCreditAccount)`（同时建 CNY 主子账户）、`updateDetails`、`currencyAccounts([accountId])`、`addCurrencyAccount`、`removeCurrencyAccount`、`poolMembers`、`joinPool`、`leavePool` |
| `CardRepository` | `list({creditAccountId})`、`byId`/`require`、`sameBankSameLast4`、`create(NewCardDraft)`（幂等）、`replace`（换卡/补卡）、`freeze`/`unfreeze`/`close`、`rename` |
| `CreditPoolRepository` | `list()`、`forBank`、`byId`、`create`、`updateLimit` |
| `BillingRuleRepository` | `versions(subject)`、`all()`、`effectiveOn(subject, date)`、`saveVersion(subject, draft, effect)`；`billingRuleDraftProblem(draft)` |
| `LimitSnapshotRepository` | `all()`、`history(currencyAccountId)`（最新在前，按绝对时刻）、`latestByCurrencyAccount()`、`record(LimitSnapshotDraft)` |
| `CardWalletReader` | `load()` → `WalletView`（授信池 › 账户 › 币种子账户 › 卡片，含预测账期与三层容量） |
| `CashAccountRepository`（I-1b） | `list()`、`byId`/`require`、`create(NewCashAccount)`（幂等）、`update`（名称、种类、可用于还款、可用日期、储备）、`setStatus`（停用/恢复） |
| `CashSnapshotRepository` | `all()`、`history(accountId)`（最新在前）、`latestByAccount()`、`includedEventIds()`、`includedIn(snapshotId)`、`sameDayEvents(accountId, date)`、`record(CashSnapshotDraft)`（当天事件须逐条回答是否已包含） |
| `CashEventRepository` | `list({cashAccountId, from, to})`、`byId`/`require`、`create(CashEventDraft)`（幂等）、`update`、`markPosted`、`delete`；调拨 `createTransfer(TransferDraft)`、`transfers()`；给 I-1c 的 `planRepaymentDebit`、`confirmRepaymentDebit`、`cancelRepaymentDebit`、`byRepayment` |
| `RecurringItemRepository` | `list()`、`byId`/`require`、`create`/`update(RecurringItemDraft)`、`setActive`、`overridesOf`、`occurrences`、`skip`/`overrideOccurrence`/`restore`、`expandUntil(date)`；纯函数 `recurringOccurrences(schedule, from, to)` |
| `ScenarioRepository` | `rows()`、`list()`（内置两条在前，未保存时是虚拟的）、`byKey`/`require`、`ensureBuiltin(kind)`、`create`/`update(ScenarioDraft)`、`delete`（连同版本）、`runs`/`allRuns`/`runById`、`addRun` |
| `CashPlanReader` | `load()` → `CashPlanView`（P-08）；`loadAccount(id)` → `CashAccountDetailView`；`loadRecurring(id)` → `RecurringDetailView` |
| `CashForecastReader` | `loadInputs()` → `CashDomainInputs`（映射、交叉校验、`dataIssues`）；`forecast(CashForecastQuery)` → `CashForecast`（P-07/P-01）；`recompute(scenarioKey)` → 新的计算版本；`isRunStale`；顶层函数 `forecastFrom`、`inputsHash`、`runResultOf`、`compareRuns`；`ScenarioBoard.load` |

写方法校验失败抛 `ValidationException(field, message)`（文案可直接显示、不含用户数据）；其余为 `NotFoundException`、
`IllegalCardTransitionException`、`ConflictException`、`StorageRejectedException`（`repository_errors.dart`）。

provider（`providers.dart`，都不自动重试）：`workspaceRepositoryProvider`、`currentWorkspaceProvider`（`Workspace?`；
`enterReal`/`enterDemo`/`exitDemo`/`clearDemo`，日志只记 `workspace/*` 事件与 real/demo）、`clockProvider`、
`workspaceScopeProvider`、各仓库 provider（I-1b 加 `cashAccountRepositoryProvider`、`cashSnapshotRepositoryProvider`、
`cashEventRepositoryProvider`、`recurringItemRepositoryProvider`、`scenarioRepositoryProvider`）、`localDataRevisionProvider`
（drift 表更新计数：读 provider watch 它，写入后自动重算）、`walletProvider`、`demoWorkspaceRowsProvider`；I-1b 的读 provider：
`cashPlanProvider`、`cashAccountDetailProvider(id)`、`recurringDetailProvider(id)`、`cashForecastProvider(CashForecastQuery)`、
`scenarioBoardProvider`。功能页自己的 provider 放在 `lib/features/<模块>/`（例：
`card_providers.dart`）。

**页面骨架与路由约定**：页面是 `ConsumerWidget`，按 `switch (asyncValue)` 给出四态——首次空白（`FirstRunEmptyState`，
未开放的操作用 `EmptyStateAction.stage` 注明阶段）、加载（`LoadingSkeleton`，静态）、错误（`ErrorBlock`，错误码 +「重试」=
`ref.invalidate`）、成功；对象不存在显示"已不存在"。区块标题 `SectionTitle`，提示 `NoticeCard`，徽标 `StatusBadge`，
"标签：值" `LabeledValue`（金额值用 `MoneyText`）；轻提示 `showFeedback`（替换正在显示的提示）；二次确认 `confirmAction`。
路由常量在 `routes.dart`（卡包栈：`/cards` → `/cards/accounts/:accountId`（P-03）→ `…/settings?section=rule|limits|currencies|pool`（P-04）；
新建卡片 `/cards/new` 全屏；规划 Tab 的 P-10 `/planner` 与分段 P-07 `/planner/calendar?basis=&scenario=`、P-08 `/planner/cash`、
P-09 `/planner/scenarios` 是并列的顶层路由（分段之间切换没有返回）；P-08 的表单（`new-account`、`new-event?type=`、`new-transfer`、
`new-recurring`、`events/:id`、`accounts/:id/snapshot`、`recurring/:id/edit`）与 P-09 的编辑器（`new`、`edit/:id`）全屏，
账户详情 `accounts/:id`、周期详情 `recurring/:id`、对比 `compare?a=&b=` 在 Tab 栈内）；新页面必须加进 `test/app/accessibility_test.dart` 的页面清单（触控尺寸、标签、对比度、2/3 倍字号）。

## 现金与资金日历（I-1b，R-CASH-01~10、UF-1 步骤 4–5、UF-5）

**现金的业务时区**：现金账户没有自己的时区列，日期与"今天"一律按默认业务时区（Asia/Shanghai，`cashTimeZone`）解释；
时刻存成该时区偏移的 RFC 3339（按自身偏移取的日期就是业务日期），与手机时区无关。

**可用现金口径**（`CashAvailability`）：受限资金，或 `usable_for_repayment = 0` 且没有 `available_from` 的账户不计入可用现金
（资金日历、总览、情景计算都不算它，界面写明原因）；有 `available_from` 的计入，领域 `CashAccount.usableForRepayment` 按"今天
是否已到可用日期"取值，并在假设里写明"{日期} 起才可用于还款"；已停用的账户不进入任何计算。受限资金不能直接标为可用于还款
（只能设可用日期）；理财、受限默认不可当日还款。

**余额快照**：余额 + 余额日期（不晚于今天）+ 实际时点（必填：缺实际时点不可存；不晚于现在、不早于余额日期）+ 来源 + 确认层级。
余额日期当天已有收支时逐条询问"余额是否已包含 {事件}"，全部回答才能保存（仓库同样检查）；回答"已包含"的写进
`snapshot_included_events`，只能是本账户、快照日当天及以前的事件。最新快照 = 余额日期最晚、再按实际时点、记录时点。

**收支计划**：类型（收入、固定生活支出、其他债务、一次性支出）决定类别与正负，金额填正数；层级必选（确定/预计），没有概率字段；
"已确认"口径只算确定的。标记已发生 = 层级变为确定、发生状态变为已发生（日期不晚于今天，时刻不晚于现在，可更正实际金额）；
已发生的不能退回。删除是软删除（tombstone，不可撤销）。

**周期事项展开规则**（`recurringOccurrences`、`RecurringItemRepository.expandUntil`）：
- 各期 = `anchor_on + k·周期`（k ≥ 0）落在 `[start_on, end_on]` 内；每月/每年按 `anchor_day`（锚定日的日号，小月截到月末，2 月 29 日
  在平年是 28 日）或 `month_end`（每月最后一天）；每周/每两周每 7/14 天；不支持工作日规则（没有已核验的节假日日历）；
- 按需展开：读模型每次计算前把启用的周期事项展开到"今天 + 180 天"（`cashHorizonDays`），起点是"该账户最新快照日（没有快照时为今天）"
  与 `start_on` 中较晚者——早于最新快照日的期已反映在余额里；每期一条事件（`occurrence_key` = 原定日期，部分唯一索引保证每期至多
  一条未删除的）；没有要补的期时不写库（读 provider 不会因此反复重算）；
- 单期例外（`recurring_overrides`）只影响那一期：跳过 = 记下例外并作废该期尚未发生的事件，之后不再展开；覆盖 = 改该期的金额
  和/或日期、时刻（期键不变）；恢复 = 去掉例外、回到周期规则。已发生的期不能再跳过或覆盖；
- 修改周期事项：只改金额/名称/层级时，今天之后尚未发生、没有覆盖金额的各期就地更新；改了周期规则（频率、第一期、日规则、
  结束日）时，今天之后尚未发生的各期连同它们的例外作废并按新规则重新展开；停用 = 今天之后尚未发生的各期作废，启用后重新展开。

**调拨**：两条事件共享 `transfer_group_id`（转出为负、到账为正，金额相反），两端账户不同、币种相同，到账日不早于转出日（同一天
都有时刻时到账时刻不早于转出时刻）；两端的日期与金额不可改（删除后重建），确认与删除两端一起。

**情景与计算版本约定**：
- 内置"已确认"（不含任何预计收入）与"基准预期"（预计收支按期发生）只读、参数固定；第一次「重算」之前没有数据库行（列表里是
  虚拟的，键为 `builtin:<kind>`），第一次计算时写入；用户压力情景只允许变差：收入延迟 0–180 天、收入比例 0–100%、生活支出比例
  100%–1000%（至多 10 位小数，存规范十进制文本），同日顺序（按时刻须所有收支都有时刻），事件覆盖（指向现存事件、每事件一次、
  与原事件同号或为 0），额度变化（信用账户 + 日期 + 非零变化额，I-2 使用，本期只保存与校验）；名称唯一且不与内置同名；
- 「重算」= 新的计算版本：版本号 = 已有最大 + 1，旧版本保留（只追加）；区间是"今天 至 今天 + 180 天"，全部计入可用现金的账户；
  `result` 是规范化 JSON（逐账户最低点与日期、全部缺口点、期末余额，假设，领域包的数据问题，未计入的账户，未生效的覆盖）；
- `inputs_hash` = 领域包规范化 JSON 的 sha256，内容是该版本区间内影响结果的数据（计入的账户与储备、可用日期、最新快照与包含
  关系、区间内的事件、情景参数）。判断"过期"时用版本自己的区间与当前数据、当前参数重算哈希，不同即过期（只过了一天不算过期）；
- 指向已删除事件的覆盖"未生效"：不交给领域包，界面与结果里列出。

**资金日历**（`CashForecastReader.forecast`、`forecastFrom`）：窗口 = 今天起 7/30/90/180 天；口径 = 已确认/基准预期/压力情景；
逐账户调用领域包 `evaluateAccounts`（账户之间从不互抵），摘要按币种给出"最差的那个账户"的最低点、日期、缺口数与距零/距储备；
日行来自领域时间线（当日流出、流入、当日最低，金额是情景变换后的），缺口 ▲ 与领域包的缺口点一致；尾部责任 = 窗口外、层级为
计划（planned）的事件（分期在 I-1c 接入同一列表）；假设 = 领域包的说明（先支出后收入、快照当天未包含事件、情景改期）加数据层的
说明（可用日期、陈旧）。快照超过 7 天（领域包 `dataIssues(staleAfterDays: 7)`，演示空间不判）→"假设分析"，照常从快照余额起算，
不补零；计入但缺快照的账户不进入计算，显示"数据不全：{账户}缺快照，未计入"。没有缺口用中性色，不用绿色，不出现"安全/稳妥"。

**审查带入项（§5）**：只用现金时间线的资金日历不经规则协议适配层，所以 `checkCashTimelineInputs` 在交给领域包之前复刻
`inputsFromProtocol` 里与现金有关的交叉规则：ID 唯一且符合协议格式（事件 ID 不以 `plan_repay_` 开头）、金额绝对值 ≤ 10^13、
事件与快照指向已有账户、事件 `at` 按自身偏移的日期等于 `on`、`includes` 只列快照日当天及以前的本账户事件、币种一致（账户币种
13 种之一、调拨两端同币种且成对）、情景覆盖指向已有事件且至多一次；违反时抛 `CashInputsException(rule)`（只有规则标识，不回显
取值）。数据库约束与触发器是第一道兜底，测试另在去掉触发器的库上确认读模型仍能拦下。I-2 交给 `verify`/`boundedSearch` 的数据
仍须先经 `inputsToProtocol`。

**给 I-1c 的接口**：
- 还款 → 现金：`CashEventRepository.planRepaymentDebit(repaymentId, cashAccountId, on, amountMinor, at?, label?)` 生成（或改期改额）
  一条层级 `planned`、类别 `repayment`、尚未发生、`linked_repayment_id = repaymentId` 的事件（每笔还款至多一条未删除的）；
  `confirmRepaymentDebit(repaymentId, debitedAt, amountMinor?)` 在确认扣款时把它变为确定、已发生，日期与时刻改为实际扣款时点
  （F-31：现金时间线按扣款日生效）；`cancelRepaymentDebit` 作废尚未发生的；`byRepayment` 查询。`linked_repayment_id` 暂无外键
  （`repayments` 表在 I-1c 建，届时用触发器或重建表加约束）；
- 尾部责任：`CashForecast.tail` 是 `TailObligation`（日期、金额、币种、账户名、标签、`source`、`refId`）的列表，I-1c 把分期计划的
  未来各期（`source: 'installment'`）加进同一列表即可在 P-07 显示；
- 测试工厂（`test/data/repositories/repository_test_support.dart`）：`createTestCashAccount`、`addTestCashEvent`、
  `recordTestCashSnapshot`（当天事件默认答"未包含"）、`StaleAwareClock`（时刻固定、判断陈旧）；组件测试 `readCashPlan(tester)`、
  `withCurrentScope(tester, action)`、`pumpCardFlowApp(realClock: …)`。

## I-1a 的偏离与约定（主会话裁决前的保守做法）

- `credit_pools` 增加 `shared_limit_minor`、`currency`（data-model §10.14 已登记）；池可用原值 = 池上限 − Σ 成员该币种
  子账户最新快照 `used_minor`，可为负；有成员缺快照时池可用未知，不以 0 代替。只建单层池（协议 v1 只有一层，
  engine-spec §12.3 不许用一层近似多层）。
- `limit_snapshots` 增加 `holds_minor`（快照时点已知的预授权合计）：F-25 需要预授权金额，DDL 把预授权放在单独的
  `preauth_holds` 表（本期不建）。`includes_holds = 1` 时只展示不扣减；为 0 时在账户层扣减一次（只记在账户第一张卡的
  `CardOption` 上）。
- 临时额度"到期日"按保守口径：到期日**当天起**不再计入（可用额回落 `temp_minor`，可为负 → 容量 0）。
- `billing_rule_versions.effective_from` 可空（空 = 全部历史，与领域包 `BillingRule.effectiveFrom`、协议 v1 一致；服务端 DDL
  为 NOT NULL）；第一个版本总是"全部历史"。"更正当前规则"让新版本接替当前版本的区间，被取代的版本区间变为空
  （`effective_to ≤ effective_from`，`effective_from` 为空时 `effective_to = '0001-01-01'`），任何日期都不选中它。
  `review_status` 本地只写 `user_declared`/`expired`，CHECK 不允许 `verified`/`published`（R2-13）。
- 截止时点（`cutoff_time`，F-19）：Python `billing.py` 没有 cutoff 语义（只接收入账日；服务端表只有 `cutoff_time`/`cutoff_tz`
  两列、没有计算），所以按简报在数据层实现：入账时点按账户业务时区换算，**晚于**（严格大于）`HH:MM` 则入账日加一天，
  恰好等于算当天（`lib/data/time/business_tz.dart` 的 `postingDateOf`，`domain_mapping.dart` 的 `postingDateFor`）。
- 业务时区只支持 8 个固定偏移时区（Asia/Shanghai、Asia/Hong_Kong、Asia/Macau、Asia/Taipei、Asia/Singapore、Asia/Tokyo、
  Asia/Seoul、UTC）；有夏令时的时区在选择器里列出但不可选（"后续支持"）。业务日期只取决于绝对时刻与账户时区（F-20）。
- G2 比字面更严：除 13 位及以上连续数字（含全角）外，数字之间只隔单个空格/短横、合计 13–19 位且通过 Luhn 的也拒绝
  （与服务端 `looks_like_pan` 同一判据）。
- 持卡人存在 `credit_accounts.holder_alias`（称呼，如"本人"）；账户在界面上的名字取主卡别名 → 任一卡别名 → 产品名 → 银行名。
- 有快照或规则的币种子账户不可删除（`UNIQUE(credit_account_id, currency)` 按简报用硬删除，不丢数据）。
- 冻结的卡不能直接换卡（PRD §6.1 只有 `active → replaced`），先解冻。
- "重置本地数据"的确认页按 ui-spec §4.5 输入"删除"；"抹除另需设备认证"（local_auth）本期未做（应用锁在 I-4）。

## I-1b 的偏离与约定（主会话裁决前的保守做法）

- 简报只列了 `snapshot_included_events(snapshot_id, cash_event_id)` 与 `recurring_overrides(recurring_item_id, occurrence_key, …)`：
  本地另加 `workspace_id`（全部业务表都带，隔离测试与清除演示数据按它删除），包含关系另加 `cash_account_id` 并用携带账户列的
  复合外键保证"只能包含本账户的事件"（data-model §10.5）；单期例外另加 `created_at`/`updated_at`。
- 现金账户没有业务时区列：现金的日期与"今天"按默认业务时区 Asia/Shanghai 解释（`cashTimeZone`）。
- 现金账户名称在同一空间未删除的账户里唯一（部分唯一索引）：快照提问、调拨与选择都按名称显示。
- 现金事件按类别约束正负（收入/调入为正，账单、生活、还款、调出、费用为负，其他不限，R2-16）；已发生的必为确定；软删除不可撤销。
- 支出比例上限 1000%（规则协议 v1 的 ScaleFactor 上限 10），收入比例 0–100%，都至多 10 位小数；用户压力情景总是含预计收入
  （`include_expected = 1`），只有内置"已确认"排除。
- 内置情景在第一次「重算」前不写库（与 I-1a 内置银行"第一次被选用时才写入"同一做法），隔离测试只数已保存的行。
- "按时刻排序须所有事件有时刻"按字面执行：保存时检查今天往前 31 天到今天 + 180 天、未停用账户的全部未删除事件都有时刻，
  否则拒绝并写明还有几笔没有时刻。
- 周期事项不支持工作日规则（没有已核验的日历），也不能做成调拨；单期覆盖须与周期同号（金额填正数）。
- 尾部责任本期只接"窗口外、层级为计划的事件"；用户登记的收支只能是确定/预计，所以真实数据里这部分要等 I-1c 的还款与分期。
- 资金日历只做表格视图（简报允许）；"储备虚线"在表格里是一段虚线图例 + 储备金额，低于储备的日行标"低于储备"，缺口点标 ▲。
- 资金日历的"账户"筛选只是只看某一个账户；无论筛选与否都逐账户计算，摘要按币种给出最差账户的最低点，不把账户相加。
- P-01 现金压力卡的口径默认"基准预期"（engine-spec F-18 的决策情景），可切到"已确认"；P-07 同样默认基准预期。
- "设为决策情景"留到 I-2（按钮位置写明）。

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


### 数据层 → 领域对象映射（I-1a，`lib/data/mapping/domain_mapping.dart`）

领域包不读写数据库；数据层把表行映射成领域对象，计算一律交给领域包：

| 本地数据 | 领域对象 / 函数 | 说明 |
|---|---|---|
| `billing_rule_versions` 行 | `billingRuleFromRow` → `BillingRule` | `ruleId` = 版本行 id；`effective_from` 空 = 不限；`due_*` → `DueRule.fixedDay`/`daysAfterStatement`；`expired` 映射为 `user_declared`（元数据） |
| 某主体的全部版本 + 交易日 | `forecastCycles` → `selectRule` + `cyclesForTransaction` | 预测账期（未出账）：入账延迟取该日生效版本的 `posting_delay_*`；多于一个 = 可能账期（保守取最早到期）；`BillingRuleError` → "规则非法，无法计算账期" |
| 规则 + 起始日 | `previewCycles` → `cycleForPosting` | P-04 的 3 期预览：第一期为起始日当天入账的账期，之后从上一账单日次日起（与领域包 F-12/F-16 测试一致） |
| 入账时点 `Timestamp` + 账户 + 版本 | `postingDateFor` | 按账户业务时区换算日期，晚于版本的 `cutoff_time` 则加一天（F-19）；领域包只接收入账日 |
| 币种子账户最新快照 | `availableOn`、`uncountedHoldsOf` | 可用额原值（临额到期日当天起回落，F-27）；未计入的预授权（`includes_holds` 为真时 0，F-25） |
| 账户、卡片、快照、授信池 | `CapacityModel.build` → `CardOption`/`ModelInputs` → `capacityLayers`/`cardLimit` | 每张未停用的卡一个 `CardOption`（同账户同一可用额，预授权只记在第一张，F-21）；池可用原值 = 池上限 − Σ 成员 `used_minor`（F-23）；容量逐层截零（F-26）。账期规则用占位规则（容量计算不读规则），`repayFrom` 为空串（现金账户在 I-1b） |

I-2 构造规划输入时，`CardOption` 换成真实规则（`billingRuleFromRow`）与还款现金账户，数据先经 `inputsToProtocol`
（它会再跑一遍 `inputsFromProtocol` 的全部交叉校验）再交给 `verify`/`boundedSearch`（审查 §4 第 2 条）。


### 数据层 → 领域对象映射：现金（I-1b，`lib/data/mapping/cash_mapping.dart`）

| 本地数据 | 领域对象 / 函数 | 说明 |
|---|---|---|
| `cash_accounts` 行 | `cashAccountFromRow` → `CashAccount` | `reserveFloor` = 储备；`usableForRepayment` 按 `CashAvailability` 在今天的取值；只把"计入可用现金"且未停用的账户交给计算 |
| 最新快照 + 包含关系 | `snapshotFromRow` → `Snapshot` | `asOf` = 余额日期，`observedAt` = 实际时点，`includesEventIds` = 包含的未删除事件（已删除的去掉，它本来就不影响时间线） |
| `cash_events` 行（未删除） | `cashEventFromRow` → `CashEvent` | 按日期、再按登记顺序（同日顺序与领域包的输入顺序一致）；标签空为 `''`；`at` 原样带过去 |
| 情景（行或内置） | `ScenarioParams` → `scenarioFromParams` → `Scenario` | 系数用 `Rational.parseDecimal`；只带指向现存事件的覆盖 |
| 全部计入的账户、快照、事件 + 今天 | `ModelInputs`（无卡、`txnDate` = 今天）→ `dataIssues(…, 7)` | `MISSING_SNAPSHOT`、`STALE_SNAPSHOT`（演示空间去掉）、`SNAPSHOT_AFTER_TXN_DATE` |
| 同上 + 情景 + 窗口末日 | `evaluateAccounts` → `CashReport` | 逐账户，从不互抵；`forecastFrom` 把时间线整理成日行、缺口、摘要 |
| 账户、快照、事件、调拨组、覆盖 | `checkCashTimelineInputs` | 审查 §5 的交叉规则（见"现金与资金日历"） |
| 计算区间的输入 | `cashInputsHash` | 领域包 `protocolInputHash`（规范化 JSON 的 sha256）；情景版本"过期"的依据 |

`test/data/repositories/cash_parity_test.dart` 用与领域包测试相同的数值写入真实库，经上表映射后调用领域包，与直接构造领域对象
调用领域包的结果逐字段比较（含时间线每个点、假设、跳过的事件、缺口的事件列表）：F-01、F-02、F-03、F-04（四种）、F-05、F-07。
