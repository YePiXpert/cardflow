# apps/mobile — 卡序 iOS App（Flutter）

本目录是卡序的 Flutter 工程（I-0a 骨架；I-0b 加密本地库；I-0c 领域包；I-1a 本地库 v2、真实/演示工作空间、
建卡/信用账户/账期规则/额度快照；I-1b 本地库 v3、现金账户与快照、收支计划与周期事项、情景、资金日历；I-1c 本地库 v4、
交易与账单版本、分期、还款登记与核对、差异项；公测版 0.0.1：关于页与公测说明；F-1：账单接续与有效状态、撤销入口、分期成本移出
界面线程、切换空间的保护）。构建、触发 iOS 构建、下载与签名安装见根 README 的"移动端"一节；计划见
`docs/80-delivery/ios-first-plan.md`。

## 目录

| 路径 | 内容 |
|---|---|
| `lib/main.dart` | 入口：建立 Provider 容器、安装错误钩子、启动 App |
| `lib/app/` | App 外壳：`app.dart`（MaterialApp、语言、演示横幅）、`router.dart`/`routes.dart`（go_router：启动分流、五个主导航、卡包栈）、`startup/`（启动分流 `app_gate.dart`、启动页与"重置本地数据"确认页）、`diagnostics/`（内存环形诊断日志）、`shell/`（底部 Tab）、`theme/`（`tokens.dart` 设计 token 唯一来源，`app_theme.dart` 浅色/深色主题）、`money/`（金额格式与 `minorDigits` 表、全局金额隐藏开关）、`widgets/`（`MoneyText`、首次空白态、状态视图、空间标识、演示横幅、确认框、轻提示） |
| `lib/features/<模块>/` | 功能模块：`overview` 总览（P-01，含现金压力卡、近期到期与待办）、`cards` 卡包（P-02 卡包与新建卡片、P-03 详情（含账单部分）、P-04 设置）、`statements` 账单中心（P-05：列表、详情、录入正式账单、人工修正、记一笔、转分期）、`repayments` 还款与核对（P-06：列表、详情与时间线、登记还款）、`planner` 规划（P-10 与规划 Tab 的分段条）、`cash` 现金与收支（P-08：账户、快照、收支计划、周期事项、调拨）、`calendar` 资金日历（P-07）、`scenarios` 情景与对比（P-09）、`promotions` 发现、`settings` 我的（含「关于」与公测说明）、`onboarding` 欢迎页（P-22）与空间切换、`diagnostics` 诊断页 |
| `lib/data/db/` | 加密本地库（drift + SQLite3MultipleCiphers，见下文"加密本地库"）：表定义、迁移、打开、重置 |
| `lib/data/repositories/` | 仓库（按当前工作空间过滤）、读模型 `CardWalletReader`/`CashPlanReader`/`CashForecastReader`/`LedgerReader`、数据层 provider（当前工作空间、时钟、各仓库），见下文"工作空间与演示模式""仓库与 provider""现金与资金日历""账单、分期与还款" |
| `lib/data/mapping/` | 数据层 → 领域对象映射：`domain_mapping.dart`（规则版本 → `BillingRule`、预测账期与 3 期预览、快照与授信池 → `CardOption`/`ModelInputs` → `capacityLayers`）；`cash_mapping.dart`（现金账户/快照/事件/情景 → `CashAccount`/`Snapshot`/`CashEvent`/`Scenario`，交叉校验、输入哈希、情景计算结果 JSON）；`ledger_mapping.dart`（交易账期归属、账单余额、负债四分法、分期各期与成本、还款入账日与额度释放） |
| `lib/data/time/` | 业务时区（只支持固定偏移时区）、入账日推导（截止时点）、时钟（演示空间固定"今天"） |
| `lib/data/validation/` | G2/G5 与末四位校验（仓库与界面共用一套文案） |
| `lib/data/demo/` | 演示空间的合成数据 |
| `lib/data/ids.dart` | UUID v4（`Random.secure()`，不引入 uuid 包） |
| `packages/cardflow_domain/` | 纯 Dart 领域包（I-0c）：金额、日期、账期、现金时间线、独立验证器、有限搜索、规则协议 v1 与 fixture 运行器；App 以 path 依赖引入，见下文"领域层" |
| `test/` | 单元与 widget 测试；`test/ios/ios_config_test.dart` 在 Linux 上检查 iOS 工程配置；`test/data/db/`、`test/data/repositories/` 在真实 sqlite3mc 上测试加密本地库与仓库；`test/support/sensitive_text.dart` 查日志与报告里的敏感内容；`test/support/forbidden_ui.dart` 整页检查"还款成功"与绿色；`test/app/public_beta_test.dart` 阶段代号防回归与公测说明 |
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

## 加密本地库（I-0b，ADR-001 PoC-1；I-1a 起 schema v2，I-1b 起 v3，I-1c 起 v4）

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
| `tables.dart` | v2、v3、v4 业务表的 drift 表 DSL（列、主键、唯一键、CHECK、复合外键，全部 STRICT） |
| `schema.dart` | `LocalSchema.currentSchemaVersion`（4）、meta 表、冻结的 `SchemaV2`、`SchemaV3`、`SchemaV4`（各自的建表、索引、触发器）、`schemaMigrations`（1→2、2→3、3→4）、`createSchema` / `migrateSchema`（同一事务写 `user_version`） |
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

**v4 的表**（I-1c，`tables.dart` 与冻结的 `SchemaV4`；8 张表、14 个索引、20 个触发器；3→4 只加表、索引与触发器，不动 v2/v3 的
表与数据。`schema_test.dart` 比较新建与从 v1、v2、v3 升级四条路径的结构完全一致，并核对升级前写入的 v2、v3 数据原样保留；
`ledger_constraints_test.dart` 直接写 SQL 验证每条约束与触发器，例如直接 UPDATE 账单版本的金额列必须失败）：

| 表 | 要点 |
|---|---|
| `transactions` | 交易挂在币种子账户（卡片只是介质，F-24）：类型 9 种，金额"负债增加为正"按类型定符号（CHECK）；交易时点 + 业务时区 + 精度；入账日可空；状态；退款/冲正的原交易（同一子账户，复合外键）；指纹；卡片须属于该子账户的信用账户（触发器）；归属、类型、来源不可改，删除（tombstone）后不再改 |
| `statements` | 账单挂在币种子账户：同一子账户同一账单日只一份（UNIQUE，F-21）；状态机 PRD §6.2（触发器，见偏离）；`current_version_id` 指向最新版本（延迟检查的复合外键，只能前移）；账单日与归属不可改 |
| `statement_versions` | 追加只读：任何 UPDATE 都 `RAISE(ABORT)`；版本号紧接最新；人工修正 = 新版本且理由必填（CHECK）；要素除新余额外可空（来源未含此项）；贷方余额 ≥ 0 且不与正的新余额并存（F-38）；最低还款不超过新余额；到期日晚于账单日 |
| `installment_plans` | 由一笔消费转成（每笔至多一个，同一子账户）；条款（本金、期数 1–60、每期费率规范十进制文本、收费方式、尾差位置、取整 `HALF_UP`）建好后不可改；状态只能从进行中变为已还完、已提前结清或已作废 |
| `installment_schedule` | 各期本金、费用、所在账单日与到期日（建计划时算好），之后只改状态（未出账 → 已出账 → 已结清，或作废）；期号不超过期数 |
| `repayments` | 状态机 PRD §6.3（触发器，见偏离）；双侧时间（发起、预计扣款日、现金扣款、银行入账、银行确认）与状态要求的时点（CHECK）；金额、方式、归属与币种不可改；现金账户须同币种同空间；作废 = tombstone |
| `repayment_allocations` | 还款 → 账单（同一子账户，复合外键）；Σ ≤ 还款额（触发器；界面要求 =，F-33）；只删了重写，不改 |
| `reconciliation_items` | 4 种差异项；`refs` 是规范化 JSON 对象，同类同引用唯一；只能从待处理处理一次（已处理/已忽略，记结果与处理者），不重开 |

另：父表补唯一索引 `currency_accounts (workspace_id, id, currency)`、`cash_accounts (workspace_id, id, currency)`，让交易与还款的币种
经复合外键与账户一致；v3 的 `cash_events.linked_repayment_id` 用触发器约束（INSERT 与 UPDATE OF：非空值必须指向同一空间的还款），
还款删除或作废前若仍有未删除的现金事件指向它则 `RAISE(ABORT)`——不重建 `cash_events`，新建库与升级上来的库用同一组触发器。

**加表与迁移**（v3、v4 即照此办理，之后同样；`schema.dart` 文件头有同样的步骤）：
1. 在 `tables.dart` 加表或加列（drift 表 DSL），`app_database.dart` 的 `@DriftDatabase(tables: …)` 登记新表；
   新的业务表必须带 `workspace_id`，并加进 `workspace_repository.dart` 的 `workspaceDataTables`（删除顺序：子表在前）；
2. 运行 `dart run build_runner build` 与 `dart format .`；
3. `LocalSchema.currentSchemaVersion` 加 1（I-1c 为 v4，下一次为 v5）；
4. 在 `schema.dart` 新建 `SchemaV<n>`：冻结这一版**新增**的建表语句（`CREATE TABLE IF NOT EXISTS`，内容与 drift
   生成的一字不差——可设 `CARDFLOW_SCHEMA_DUMP_DIR` 跑 `test/data/db/schema_test.dart` 看新库结构）、索引与触发器
   （都带 `IF NOT EXISTS`）；只做 expand，不改写金额原值；
5. `schemaMigrations` 登记 `n-1: _migrateV<n-1>ToV<n>`；`latestIndexes`/`latestTriggers` 加上新版的；
6. `schema_test.dart` 增加"从 v<n-1> 升级"与新建的一致性比较（已有的从 v1、v2 升级的比较保留；升级前写入旧版数据并核对原样保留）；
   约束测试加新约束（v3 的在 `cash_constraints_test.dart`，v4 的在 `ledger_constraints_test.dart`）；`workspace_isolation_test.dart` 的 `runAllQueries` 加新仓库的全部
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
  全部业务表，以另一个空间为当前空间运行每个仓库的全部查询（含用对方的 id 去查，I-1c 时 237 条），结果全部为空；反向亦然。
- **启动分流**（`lib/app/startup/app_gate.dart`，BL-04）：数据库打开中/打不开 → 启动页；没有工作空间 → P-22
  （`/welcome`，任何路由都先到这里）；就绪后进入五个主导航。诊断页不受分流约束。
- **P-22**：「手工建卡」进入（必要时新建）真实空间并打开新建卡片；「体验演示」进入（首次生成）演示空间并转到总览；
  「从账单文件开始」「从备份恢复」「连接服务器」显示但禁用并注明"后续版本提供"（连接服务器为"后续提供（自托管同步）"；
  公测版起界面不写内部阶段代号）；最底部是公测说明（见"公测版 0.0.1"）。真实↔演示切换须确认；
  「退出演示」回到真实空间（没有则回到 P-22）；「清除演示数据」确认框写明影响数量，删除演示空间全部行。
- **演示数据**（`lib/data/demo/demo_workspace.dart`，经仓库写入、一个事务）：卡 A/B/C 的账期与可用额与回归样本一致
  （engine-spec §9），另加与 B 同行的卡 D：A 主卡 + 附属卡同一信用账户（F-21）；B 与 D 是同一银行的两个独立授信
  （F-22）且共享"乙行共享额度"池（F-23）；D 可用 −200（F-26）；B 有临时额度 5,000、2026-11-15 到期（F-27）；
  C 的规则带截止时点 22:00。现金部分（I-1b，`seedDemoCash`）：工资卡（储备 2,000）与受限的定期存款（不计入可用现金）、
  工资卡 10-16 的快照（当天早餐已包含、水电费未包含）、与回归样本同一组数值的收支、房租周期事项（每月 27 日，12-27 单期覆盖为
  1,200）、11-01 工资卡 → 定期存款 2,500 的调拨、"收入推迟 3 天"压力情景，并计算"基准预期"与它各一个版本；固定"今天"下
  基准口径 30 天内有一个可见缺口（11-01 定存转出后余额 300，低于储备）。账单与还款部分（I-1c，`seedDemoLedger`）见"账单、分期与
  还款"一节；两笔还款的现金事件都在工资卡快照日之前，资金日历的数字不变。
- **时钟**：`clockProvider` —— 演示空间固定"今天" = 2026-10-16（北京时间 12:00，`demoClock`），陈旧判定不触发；真实空间
  用系统时间。页面与仓库都不直接调用 `DateTime.now()`。
- **演示横幅**：`DemoBannerFrame`（`MaterialApp.builder`）在演示空间时每页顶部常驻紫色横幅（烧瓶 + "演示数据 ·
  与真实数据隔离" +「退出演示」），没有关闭按钮。
- **切换空间不写进另一个空间**（审查 R-15）：当前工作空间从一个变成另一个（进入/退出演示、切换空间、清除演示数据后回到真实
  空间）时，`appRouterProvider` 统一回到首页（总览）——根导航器上的全屏表单与当前 Tab 的页面栈一并清掉；`HomeShell` 让切换之前
  留在其他 Tab 的页面栈作废（下次点进那个 Tab 从根页开始），切换之后新开的栈照常保留。全屏表单混入 `WorkspaceBoundForm`
  （`lib/app/widgets/workspace_bound_form.dart`）：打开时记下工作空间 id，保存时经 `boundRepository` 取仓库，当前空间不同就抛
  `WorkspaceChangedException`（"已切换空间：这张表单是在另一个空间里打开的，没有保存"），作为第二道防线；新加的全屏表单也要混入
  它。从没有工作空间（P-22）进入时由调用方决定去哪（「手工建卡」去新建卡片）。

## 仓库与 provider（`lib/data/repositories/`，I-1b 起沿用）

| 仓库 | 主要方法 |
|---|---|
| `WorkspaceRepository`（全局） | `current()`、`live(kind)`、`ensure(kind)`、`setCurrent(id)`、`countRows(id)`、`deleteWorkspace(id)` |
| `BankRepository` | `listStored()`、`byId`、`choices()`（内置 + 用户添加）、`ensureByName(name)` |
| `CreditAccountRepository` | `list()`、`byId`/`require`、`create(NewCreditAccount)`（同时建 CNY 主子账户）、`updateDetails`、`currencyAccounts([accountId])`、`addCurrencyAccount`、`removeCurrencyAccount`（已有快照、规则、交易、账单、还款或分期的拒绝并说明，异常一律包装，审查 R-08）、`poolMembers`、`joinPool`、`leavePool` |
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
| `TransactionRepository`（I-1c） | `list({currencyAccountId})`、`byId`/`require`、`create(TransactionDraft)`（幂等；退款 → 退款待核对、无登记的还款入账 → 未匹配）、`markPosted`（补入账日）、`delete`（引用它的未处理差异项由系统处理） |
| `StatementRepository` | `list({currencyAccountId})`、`byId`/`require`、`versions(statementId)`、`allVersions()`、`recordIssued(StatementEntryDraft)`（v1）、`correct(statementId, figures:, reason:, dueDate:)`（新版本）、`moveStatus` |
| `InstallmentRepository` | `plans({currencyAccountId})`、`byId`/`require`、`byTransaction`、`schedule(planId)`、`allPeriods()`、`create(InstallmentDraft)`（幂等）、`cancel` |
| `RepaymentRepository` | `list`、`byId`/`require`、`allocationsOf`、`allAllocations`、`create(RepaymentDraft)`（幂等）、`markInitiated`、`confirmDebit`、`markFailed`、`retry`、`markUserPaid`、`markCreditPosted`、`confirmByBank`、`markNeedsReview`、`reverse`、`delete`（作废登记）、`setEvidenceNote`、`resolveDuplicate`（`create` 只分配到本期账单；`delete` 之后引用它的未处理差异项由系统处理） |
| `ReconciliationRepository` | `list({status})`、`byId`/`require`、`find`、`open(kind, refs)`（同类同引用不重复）、`resolve(id, resolution)`、`dismiss`、`closeBySystem({transactionId, repaymentId})`（审查 R-07）、`openDuplicatePairs()`、`offsetRefunds()` |
| `LedgerReader` | `load()` → `LedgerData`（P-05/P-06/P-03/P-01：账单、版本与读数（本期剩余应还、有效状态、已并入下一期），交易与账期，分期与各期，还款、分配与现金事件，差异项，负债四分法，近期到期；`currentStatementOf`、`statusOf`、`repaymentStatusOf`、`looseTransactions`、`mayBeBilled`、`systemCloseReason`）。只读，不写库 |

写方法校验失败抛 `ValidationException(field, message)`（文案可直接显示、不含用户数据）；其余为 `NotFoundException`、
`IllegalCardTransitionException`、`IllegalRepaymentTransitionException`（I-1c）、`ConflictException`、`StorageRejectedException`
（`repository_errors.dart`）。

provider（`providers.dart`，都不自动重试）：`workspaceRepositoryProvider`、`currentWorkspaceProvider`（`Workspace?`；
`enterReal`/`enterDemo`/`exitDemo`/`clearDemo`，日志只记 `workspace/*` 事件与 real/demo）、`clockProvider`、
`workspaceScopeProvider`、各仓库 provider（I-1b 加 `cashAccountRepositoryProvider`、`cashSnapshotRepositoryProvider`、
`cashEventRepositoryProvider`、`recurringItemRepositoryProvider`、`scenarioRepositoryProvider`）、`localDataRevisionProvider`
（drift 表更新计数：读 provider watch 它，写入后自动重算）、`walletProvider`、`demoWorkspaceRowsProvider`；I-1b 的读 provider：
`cashPlanProvider`、`cashAccountDetailProvider(id)`、`recurringDetailProvider(id)`、`cashForecastProvider(CashForecastQuery)`、
`scenarioBoardProvider`；I-1c 加 `transactionRepositoryProvider`、`statementRepositoryProvider`、`installmentRepositoryProvider`、
`repaymentRepositoryProvider`、`reconciliationRepositoryProvider` 与读 provider `ledgerProvider`；F-1 加分期成本的
`installmentCostProvider(planId)` 与 `installmentCostRunnerProvider`（`lib/features/statements/installment_cost.dart`，后台 isolate）。
功能页自己的 provider 放在 `lib/features/<模块>/`（例：`card_providers.dart`）。

**页面骨架与路由约定**：页面是 `ConsumerWidget`，按 `switch (asyncValue)` 给出四态——首次空白（`FirstRunEmptyState`，
未开放的操作用 `EmptyStateAction.stage` 注明"后续版本提供"，不写内部阶段代号）、加载（`LoadingSkeleton`，静态）、错误（`ErrorBlock`，错误码 +「重试」=
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
计划（planned）的事件与进行中分期尚未结清的各期（I-1c 接入同一列表，`source: 'installment'`）；假设 = 领域包的说明（先支出后收入、快照当天未包含事件、情景改期）加数据层的
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
  （F-31：现金时间线按扣款日生效）；`cancelRepaymentDebit` 作废尚未发生的；`byRepayment` 查询。`linked_repayment_id` 在 I-1c 用触发器
  约束到同一空间的还款（见"v4 的表"）；
- 尾部责任：`CashForecast.tail` 是 `TailObligation`（日期、金额、币种、账户名、标签、`source`、`refId`）的列表，I-1c 把分期计划的
  未来各期（`source: 'installment'`）加进同一列表即可在 P-07 显示；
- 测试工厂（`test/data/repositories/repository_test_support.dart`）：`createTestCashAccount`、`addTestCashEvent`、
  `recordTestCashSnapshot`（当天事件默认答"未包含"）、`StaleAwareClock`（时刻固定、判断陈旧）；组件测试 `readCashPlan(tester)`、
  `withCurrentScope(tester, action)`、`pumpCardFlowApp(realClock: …)`。

## 账单、分期与还款（I-1c，R-STMT-01~11、UF-3；F-1 按 PRD §6.2 的 2026-10-19 裁决改为接续与有效状态）

**交易与账期归属**（`TransactionRepository`；`ledger_mapping.dart` 的 `transactionCycle`）：
- 交易挂在币种子账户上，卡片只是介质：换卡后旧卡的交易、账单与还款分配都不迁移、不变（F-24）。金额"负债增加为正"，
  类型决定符号（消费、费用、利息为正，退款与还款入账为负，转账/取现与调整按方向）；交易时点按账户业务时区写出并带精度
  （精确到时刻/只知道日期/只知道月份）；入账日可空；指纹 = 规范化要素的 sha256（导入去重时用）。「记一笔」不提供"分期本金"
  "分期手续费"两种类型——它们由分期计划的各期表示，不另记交易（避免重复计入）；"还款入账（银行记录）"只用于核对，负债按
  P-06 登记的还款核销。
- 账期归属：入账日已知 → 领域包 `resolveCycle`（已出账单优先，否则按规则预测）；入账日未知 → 交易日在入账延迟区间内的
  全部可能账期（领域包 `cyclesForTransaction`；已出账的账单日用已出账单的到期日），界面显示"可能账期：… 或 …（入账日未知，
  保守按最早到期 …）"（F-15）。交易"已出账" = 它的每个可能账单日都不晚于该子账户最近一期已出账单的账单日。

**账单与版本**（`StatementRepository`）：
- 「录入正式账单」= v1（来源"手工录入"）：账单日不晚于今天（账户业务时区）、到期日晚于账单日；同一币种子账户同一账单日只有
  一份，所以同一信用账户的两张卡只产生一份账单（F-21）。要素：上期余额、本期新余额（可负）、最低还款、本期还款、本期贷记、
  费用、利息、分期应还、贷方余额；来源没有给的项存空值，界面显示"来源未含此项"而不是 0。
- 「人工修正」= 新版本（来源"人工修正"、理由必填，可同时更正到期日），旧版本原样保留、可切换查看（R-STMT-07）；账单版本表的
  任何 UPDATE 都被触发器拒绝；**有效状态**为"已还清"的账单不能再修正（看有效状态、不看存储状态：冲正后剩余应还 > 0 的又可以
  修正）。
- 存储状态（PRD §6.2 的状态图，`statements.status`，触发器照它约束）只是**动作记录**：录入为"已出账"，修正后"已修正"，还款银行
  确认时按分配记"已结清/部分结清"（`paidOnStatement`）。界面、近期到期、逾期提醒、账单中心、P-01、P-03 一律用读模型推导的
  **有效状态**（下一段）；读模型只读，不在读取时写库（0.0.1 打开时写过的"已逾期"照常保留在库里，不再用于显示）。

**账单接续、本期剩余应还与有效状态**（PRD §6.2 的 2026-10-19 裁决段，审查 R-01/R-02/R-03/R-06；`ledger_mapping.dart` 的
`StatementBalance`、`creditedAfter`、`installmentAdjustmentsFor`、`effectiveStatusOf`，`LedgerData.balances`）：
- **接续**：同一币种子账户里账单日最近的一期是**本期**；更早的账单"已并入 {下一期账单日} 账单"（下一期的新增账单已含它没还的
  部分）——不计入总负债与本期应还、不进近期到期、不标逾期、不再接受还款分配，详情页写明。
- **本期剩余应还** = 本期当前版本的新增账单（新余额；有贷方余额时为 −贷方余额）− 入账日**晚于**本期账单日的银行已入账还款
  （`credit_posted`/`bank_confirmed`；入账日按信用账户业务时区与截止时点；不论分配到哪一期——已存的分配到旧账单的还款照常读出，
  金额按入账日期计算、不按分配；未处理的疑似重复只计一次）± 已出账消费转分期的调整。入账日不晚于账单日的还款已反映在新增账单里，
  不再扣减。可以为负：负数是贷方余额（多还的部分）。
- **已出账消费转分期**（审查 R-01）：消费的账期（入账日已知）就是某期账单 S、且 S 的当前版本录入**严格早于**分期计划建立时 →
  S 的剩余应还 − 分期本金 + 账单日等于 S 的那一期（本金 + 手续费）；之后录入的修正版本视为已反映分期，不再调整。"未来分期本金"
  只计账单日晚于本期账单日的各期。例（`ledger_test.dart` 的 F-30 补例）：10-05 的 12,000 已计入 10-10 账单（新增账单 12,000），
  账单录入后转 12 期（每期 0.6%）——首期默认在 11-10：10-10 剩余应还 0、"已转分期"，未来分期本金 12,000，总负债 12,000；首期
  指定为 10-10：剩余应还 12,000 − 12,000 + 1,072 = 1,072、"待还"，未来分期本金 11,000，总负债 12,072。
- **有效状态**（`EffectiveStatementStatus`）：剩余应还 > 0 → 没过到期日为"待还"（有账单日之后入账的还款时为"已还一部分"），
  过了到期日（到期日当天不算）为"已逾期"；≤ 0 → 转分期本身就结清了这期为"已转分期"；有入账还款时，只按银行确认的也结清为
  "已还清"、否则"已入账（待银行确认）"；没有还款也没有转分期为"无需还款"；< 0 另显示贷方余额。冲正、人工修正、删除交易、作废
  分期之后自动重新推导。"已还清"的确认层级显示"银行确认"。表驱动测试 `statement_standing_test.dart`，审查探针的改写
  `review_probes_test.dart`。
- 还款的有效状态：存储状态"用户已标记"、而分配到的账单过了到期日仍无证据时推导为"待核对"（`LedgerData.repaymentStatusOf`，
  UF-3 步骤 6，不写库）。

**负债四分法**（R-STMT-02、F-30，`liabilityOf` → `LiabilityBreakdown`）：总负债 = 已出账未还 + 未出账 + 未来分期本金（不含
未计提的分期手续费），四项分列、不重复相加：
- 已出账未还 = 本期账单的有符号剩余应还（"本期应还"是它不小于 0 的部分）；贷方余额时为负（负债为负，R-STMT-11）；更早的
  账单已并入本期，不另计；
- 未出账 = 本期账单之后的交易，不含已转分期的原消费、还款入账行与待核对的退款（待核对的退款单列，F-34）；入账日未知、可能账期
  跨过本期账单日的交易按未出账计（偏大），界面提示"可能已出账，请补入账日"（Q-3）；
- 未来分期本金 = 未作废计划里账单日晚于本期账单日的各期本金（没有账单时为全部各期）；这些期的手续费单列，不计入总负债；
- 只扣减银行已入账的还款（`credit_posted`/`bank_confirmed`），"我已还款"不扣减。
- 例（`ledger_test.dart` 的 F-30）：12,000 的消费转 12 期（每期费率 0.6%：每期本金 1,000、费用 72），第 1 期在已出账的 10-10 账单里
  （账单应还 1,572 = 当期分期 1,072 + 另一笔 500），10-12 的 300 未出账，其余 11 期本金 11,000 是"未来分期本金"（792 的费用单列），
  原消费不再计入未出账：总负债 = 1,572 + 300 + 11,000 = 12,872。

**分期算法与取整**（F-36、F-37；`InstallmentRepository`、领域包 `installment.dart`）：
- 本金拆分 = 领域包 `splitInstallments`：每期 `HALF_UP(本金 / 期数)`，尾差加到末期（默认，建行口径）或首期，Σ 各期 = 本金；
  每期收取的手续费 = `applyRate(本金总额, 每期费率, HALF_UP)`（`installmentCashFlows`，每期相同）。条款里的取整固定 `HALF_UP`；
  "首期一次收取"见"I-1c 的偏离与约定"。
- 条款：本金默认 = 消费金额（可小于它）、期数 1–60、每期费率 0 ≤ r < 1（至多 10 位小数，存规范十进制文本）、收费方式、尾差
  位置；建好后不可改（触发器）。
- 各期所在账单：第 1 期默认是"入账日（未知时交易日）与今天中较晚者"所在的账期，也可指定首期账单日（须是规则给出的账单日、
  不早于这笔消费本身的账期）；之后每期从上一期账单日的次日推出（`resolveCycle`，已出账单优先）。各期的存储状态是动作记录：
  已出账单覆盖的期直接是"已出账"，之后录入账单时账单日不晚于它的各期 → 已出账，账单（存储状态）结清时 → 已结清，全部结清的
  计划 → 已还完；负债按账单日计（见上），不看这些状态。已出账的消费也可以转分期（账单分期），见上面的"已出账消费转分期"。
- 成本两种并列（`InstallmentCost`）：名义年化 = 每期费率 × 12（界面注明"不是实际成本"）；实际年化 = 各期现金流（月 0 放款为负、
  第 k 月还"本金 + 费用"为正）的月 IRR（有理数二分，精度 10^-12）按复利 `(1 + r)^12 − 1`；显示为百分数，至多 4 位小数（HALF_UP）。
  F-37：每期 1.5%、12 期 → 名义 18%，实际年化 36.7571%（与 Python 对照一致）。
- 成本不在界面线程算（审查 R-04：有理数 IRR 60 期要 2 秒多）：`lib/features/statements/installment_cost.dart` 的
  `installmentCostProvider(planId)` 按计划 id 记忆化（条款与各期金额不可改，keepAlive），经 `installmentCostRunnerProvider` 在后台
  isolate 里算（`lib/app/background/off_main_isolate.dart`：原生平台 `Isolate.run`，Web 只作编译烟雾测试、就地计算），算好之前显示
  "计算中…"；每期费率与名义年化（费率 × 12）当场算。转分期表单的拆分与名义年化当场算，实际年化等改动停下 300 ms
  （`installmentCostDebounce`）之后在后台算、只认最后一次请求。`LedgerData.costOf` 只给测试与工具用；`installmentCostEvaluations`
  数当前 isolate 里的 IRR 调用（测试断言主 isolate 不算 IRR）。领域包 IRR 的提速在 I2-0。
- 作废只在各期都还没出账时可以（录错了；分期卡片「作废（录错了）」），原消费重新计入未出账；提前结清在后续版本。资金日历（P-07）
  的尾部责任列出进行中计划尚未结清、到期日在窗口外的各期（`source: 'installment'`，金额 = 本金 + 费用，F-06）。

**还款状态机**（PRD §6.3，`RepaymentRepository`；非法转移抛 `IllegalRepaymentTransitionException`，触发器
`repayments_status_transition` 兜底）：

| 从 → 到 | P-06 动作 | 条件与效果 |
|---|---|---|
| — → 已登记 `recorded` | 「登记」 | 发起时间不晚于现在；预计扣款日不早于发起日；分配 Σ ≤ 还款额（界面要求 =，F-33），只能分到本子账户的**本期**账单（更早的已并入下一期，分到它们被拒）；本期已还清也可以再分配（多还的形成贷方余额，界面在保存前要求确认）；表单默认分到本期并预填剩余应还；有现金账户与预计扣款日时，现金时间线生成一条计划扣款（`planRepaymentDebit`） |
| 已登记 → 处理中 `processing` | 「标记已发起」 | 记发起时间 |
| 已登记/处理中 → 现金已扣 `cash_debited` | 「确认扣款」 | 已登记的先经处理中；扣款时点不晚于现在、不早于发起；计划扣款按实际时点变为确定、已发生（`confirmRepaymentDebit`，F-31）；实际金额与登记不同 → 金额不符 |
| 处理中 → 失败 `failed` | 「标记失败」 | 计划扣款作废 |
| 失败 → 已登记 | 「重试登记」 | 可给新的预计扣款日，重新生成计划扣款 |
| 现金已扣 → 银行已入账 `credit_posted` | 「上传入账证据」 | 入账时点不早于扣款；负债从入账日（信用账户业务时区，截止时点按 `postingDateFor`）起核销；入账金额与登记不同 → 金额不符 |
| 银行已入账 → 银行确认 `bank_confirmed` | 「银行确认」 | 不早于入账；存储状态按银行确认的分配记所分配账单"已结清/部分结清"（动作记录；有效状态按入账日期推导） |
| 已登记 → 用户已标记 `user_marked_paid` | 「我已还款」 | 只是你的确认：不结清、不核销负债（R-STMT-03） |
| 用户已标记 → 待核对 `needs_review` | 推导 | 分配到的账单过了到期日仍无银行证据：读模型显示为待核对（`repaymentStatusOf`，不写库）；存储状态只由 `markNeedsReview` 写 |
| 用户已标记/待核对 → 银行确认 | 「银行确认（取得证据）」 | 须给实际扣款时点（现金侧按它确认扣款），入账时点取确认时点 |
| 银行确认 → 已冲正 `reversed` | 「冲正」 | 不再核销负债；账单的剩余应还与有效状态按入账日期重新推导（还欠着的重新进入近期到期与逾期；存储状态"已结清"不回退） |

另：「作废登记」（tombstone）只对已登记、失败、用户已标记、待核对且现金尚未扣的还款，计划扣款一并作废，引用它的未处理差异项由
系统标为已处理（审查 R-07，见下）。双侧时间（F-31）：
现金侧（`expected_debit_on`、`cash_debited_at`）按现金时区；负债侧按 `credit_posted_at` 在信用账户业务时区的日期。额度释放
（F-28，`releasedRepaymentsOn`）：只有银行已入账、入账日晚于额度快照日、且"入账日 + 释放时滞 ≤ 今天"的还款才释放；账户规则里
还没有释放时滞，一律按"未知"处理——不释放，以新的额度快照为准（P-03 有说明）。文案：状态与轻提示都带确认层级（"已登记（待
银行确认）"），没有"还款成功"，不用绿色（银行确认用 confirm.bank 色与印章图标）；`repayment_pages_test.dart` 在 9 种状态下逐页
滚动检查（`test/support/forbidden_ui.dart`，检查本身带自检）。

**差异项**（R-STMT-09，`ReconciliationRepository`）：

| 类型 | 何时生成（引用） | 处理结果 |
|---|---|---|
| 疑似重复还款 | 同一天（实际扣款日 → 预计扣款日 → 发起日，现金时区）、同一子账户、同金额的一笔自动扣款与一笔手工还款，两笔都不是失败或冲正（F-32；`repayment_ids`） | 确为两笔；同一笔 → 作废其中一笔登记（`resolveDuplicate`） |
| 金额不符 | 确认扣款或上传入账证据时金额与登记不同（`repayment_id`、`side`、登记与实际金额） | 已核对 |
| 退款待核对 | 每一笔退款：是否冲抵本期应还取决于账户规则，规则未知（`transaction_id`） | 已冲抵应还（之后计入未出账）；未冲抵本期应还 |
| 未匹配的还款 | 记一笔"还款入账（银行记录）"时，同一子账户 3 天内没有同金额、未作废的还款登记（`transaction_id`） | 已登记对应还款（或「去登记还款」） |

同类同引用只有一条（包括已处理的，不重开）；任何一条都可「忽略」；只能处理一次，记录结果、处理者与时间，P-06"已处理的差异"
列出。删除交易、作废还款登记之后，引用它的未处理差异项由系统标为已处理（审查 R-07，`ReconciliationRepository.closeBySystem`：
状态"已处理"、处理者"系统"、结果代码 `dismissed`；表里没有原因列，界面按引用对象的状态写明"系统处理（引用的交易已删除）"
"系统处理（引用的还款登记已作废）"，`LedgerData.systemCloseReason`）；按差异项"同一笔"作废的仍记为本机用户的处理。
疑似重复处理前负债只核销一次（两笔都已入账时只计较大的一笔，`creditedAfter`/`paidOnStatement`）；退款在处理前应还不变、
不计入未出账，也不进现金（不当收入，F-34）。

**页面与演示数据**：P-05 账单中心（`lib/features/statements/`：列表与筛选、详情、录入正式账单、人工修正、记一笔、转分期）与
P-06 还款与核对（`lib/features/repayments/`：列表、详情与时间线、登记还款）挂在总览栈与信用账户详情栈下（`/overview/…`、
`/cards/accounts/:accountId/…`；路由常量 `AppRoutes.statements`/`statement`/`newStatement`/`correctStatement`/`newTransaction`/
`newInstallment`/`repayments`/`repayment`/`newRepayment`，表单全屏）。P-03 的账单部分在 `account_ledger_section.dart`（本期、负债
四分法、最近 3 期与「全部账单」、「去还款：查看操作说明」「登记还款」、还款释放说明），P-01 的在 `ledger_overview.dart`（待办条、
快捷新增、近期到期 14 天、负债四分法）。徽标与筛选一律用有效状态（`effectiveStatusBadge`，已并入的写"已并入 MM-DD 账单"）。
读 provider：`ledgerProvider`（`LedgerReader.load`）、`installmentCostProvider`。

**撤销入口**（审查 R-16、Q-3；`ledger_actions.dart`，都调用已有的仓库方法）：交易行（账单详情的"本期交易"，以及账单中心列表下面
新加的"不在已录账单里的交易"——未出账的、所在账期还没录入正式账单的、没有账期规则的，`LedgerData.looseTransactions`）有
「删除」（已转分期的先提示作废分期，确认后先作废计划再删除交易）、「补入账日」（入账日未知时；不早于交易日、不晚于今天）与
「转分期」；入账日未知、可能账期跨过本期账单日的标"可能已出账，请补入账日"（`LedgerData.mayBeBilled`）；分期卡片在各期都还没
出账时有「作废（录错了）」。删除、作废之后引用它们的未处理差异项由系统处理（见"差异项"）。演示空间（`seedDemoLedger`）：卡 A
的交易（家电城 10,000 转 12 期、每期 0.6%；超市消费；超市退货 → 退款待核对；附属卡入账日未知的机票）、10-10 账单 v1 与 v2（修正
最低还款额）、10-15 自动扣款 1,000（现金已扣）与同日手工登记的 1,000（已登记）→ 疑似重复差异项。

## 公测版 0.0.1

- 版本：`pubspec.yaml` 的版本名 0.0.1（按用户要求；版本号不再写"beta n"）；构建号由 CI 的运行序号给出（`--build-number`），不在 pubspec 里改。
  ios-unsigned 的"Verify IPA"断言 `CFBundleShortVersionString` = pubspec 版本名（推 `ios-v*` 标签构建时还要 = 标签去掉 `ios-v`）、
  `CFBundleVersion` = 运行序号（F-1，审查 R-11）。App 图标是卡序自己的
  图标（`ios/Runner/Assets.xcassets/AppIcon.appiconset`，15 个尺寸，RGB 无透明通道）；ios-unsigned 的"Verify IPA"检查构建出的
  `Info.plist` 有 `CFBundleIcons`（主图标名 AppIcon）且 `Runner.app/Assets.car` 存在。
- 界面文字不出现内部阶段代号：未开放的功能写"后续版本提供"一类说法。防回归测试 `test/app/public_beta_test.dart`：扫描 `lib/`
  全部字符串字面量（注释除外，扫描器带正反例自检）是否匹配 `I-\d`，并逐页打开演示空间的全部页面、真实空间的首次空白页与 P-22，
  每页滚到底检查渲染出来的文字。
- 公测说明（`lib/features/settings/public_beta.dart` 的 `PublicBeta.note`，P-22 首次使用页最底部与「关于」共用同一段）："公测版
  0.0.1：数据只保存在这台 iPhone 的加密数据库里，不上传任何服务器。删除 App 或「重置本地数据」会永久删除全部数据；目前还没有备份
  与导出，后续版本提供。"说明里的版本号只来自 `PublicBeta.version` 一处；测试逐字核对原文，并读取 `pubspec.yaml` 断言
  `PublicBeta.version` 与版本名相同——改 pubspec 的版本名而忘了改它，CI 的 dart job 会失败。「关于」页的"版本"一行另从
  package_info_plus 读取（与诊断页同一来源）。
- 「关于」（我的 › 关于卡序，`/settings/about`，`about_page.dart`）：名称"卡序 CardFlow"、"公测版"标识、版本与构建号（与诊断页
  同一来源 `appDiagnosticsProvider`，即 package_info_plus）、公测说明、源码地址 `github.com/YePiXpert/cardflow`（可选中的纯文本 +
  「复制源码地址」；App 内不打开浏览器，不加依赖）、反馈方式"我的 › 诊断信息 › 复制诊断信息，附上问题描述发到 GitHub Issues"与
  「打开诊断信息」。
- 隐私清单（BL-16）：ios-unsigned 构建后扫描主二进制与 `Frameworks/` 下每个二进制（`nm -u` 与 `strings`）的四类 Required Reason
  API，并查每个 framework 是否自带隐私清单（artifact `required-reason-scan`）。按"主二进制或没有自带清单的 framework 命中的类别
  留在 App 清单"：`ios/Runner/PrivacyInfo.xcprivacy` 保留 FileTimestamp（C617.1：主二进制的 `NSFileCreationDate`、sqlite3mc 的
  `stat`/`fstat`/`lstat`）、SystemBootTime（35F9.1：sqlite3mc 的 `sysctlbyname`，见偏离）、DiskSpace（E174.1：sqlite3mc 的
  `statfs`/`fstatfs`），删除没有任何命中的 UserDefaults（CA92.1）。Flutter.framework 与两个插件资源包自带清单。F-1 起扫描对"须由 App
  清单承担、App 清单却未登记"的类别判失败（审查 R-11）。
- 打 `ios-v*` 标签与建 GitHub 预发布版由主会话在验收后进行。

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

## I-1c 的偏离与约定（主会话裁决前的保守做法）

- 状态机比 PRD 多两条：账单"已修正 → 已逾期"（PRD §6.2 只画了已出账、部分结清 → 已逾期；修正过的账单同样会过期未还）；还款
  "待核对 → 银行确认"（PRD §6.3 里待核对没有出口；取得证据后与"用户已标记 → 银行确认"同样处理）。账单的"预测账期"不存表：未出的
  账单由领域包按规则预测（P-03/P-01 的"预测账期（未出账）"），`statements` 只存已出账的。（F-1 起读模型不再写"已逾期"与到期的
  "待核对"，两者都由读模型推导，触发器里的转移保留不变，见"F-1 的偏离与约定"。）
- 分期手续费"首期一次收取"（`fee_mode = upfront`）：Python `money.py` 没有这种方式；本地约定手续费总额 =
  `applyRate(本金总额, 每期费率 × 期数, HALF_UP)`，全部在第 1 期收取，本金拆分不变。
- 分期各期的账单日在建计划时按当时的规则与已出账单算好，之后不改（规则改了也不重排；`installment_schedule` 只改状态）。
- 本地表比 data-model §3 多的列：`installment_plans.currency_account_id`、`repayment_allocations.workspace_id`/`currency_account_id`
  （携带账户列的复合外键保证交易、账单、还款属于同一币种子账户，data-model §10.5）；`repayments.expected_debit_on`（简报列）、
  `evidence_note`、`deleted_at`（作废登记的 tombstone）；各表的 `row_version` 与时间戳。没有建的列
  （导入与附件在后续版本）：`source_document_id`、`bank_reference`、`mcc`、`evidence_document_id`、`origin_device_id`。
  `installment_schedule` 的费用列叫 `fee_minor`（DDL 写 `interest_minor`；这里存的是分期手续费，不是利息）。
- `reconciliation_items.kind` 本地只有 4 种（金额不符、疑似重复还款、退款待核对、未匹配的还款）；DDL 的 `missing`、
  `duplicate_txn`、`sync_conflict` 属于导入与同步，后续版本再加（放宽 CHECK 只需 expand）。
- 疑似重复的"同一天"按现金时区依次取实际扣款日、预计扣款日、发起日；未匹配的还款按"同一子账户、同金额、日期相差 3 天内"匹配
  登记。退款一律先进"退款待核对"（规则未知），用户标记"已冲抵应还"后才计入未出账，"未冲抵本期应还"的继续不计。
- 额度释放时滞：账户规则（bank-rules-spec 的 LimitRule）本期没有建，`releasedRepaymentsOn` 的时滞一律为未知 → 不释放（最保守）。
- 冲正后的账单状态：改按 F-1 的有效状态推导（冲正后剩余应还 > 0 的账单照常是"待还"/"已逾期"、进近期到期，按 2026-10-19 裁决），
  见"F-1 的偏离与约定"；原约定里只有"存储状态不回退（PRD §6.2 没有回退的转移）"仍然成立。
- 交易"是否已出账"按"所有可能账单日都不晚于最近一期已出账单的账单日"判断；没有规则时按入账日（未知时交易日）比较。（入账日
  未知、可能账期跨过本期账单日的，F-1 起界面提示"可能已出账，请补入账日"，并有「补入账日」入口，见"F-1 的偏离与约定"。）
- "记一笔"不提供分期本金/手续费类型（由分期各期表示）；"还款入账（银行记录）"只用于核对，不进入负债计算。
- 资金日历尾部责任里分期一期的金额 = 本金 + 费用（现金要付的）；负债四分法的"未来分期本金"不含费用（费用单列）。
- 隐私清单的 SystemBootTime：扫描规则把 `sysctlbyname` 算作命中，sqlite3mc 导入了它，但二进制里只有 `hw.ncpu`、没有
  `kern.boottime`（实际不是读开机时间）；按扫描规则与"多报不影响安装"保守保留 35F9.1，删除与否请主会话裁决（删了要再构建一次）。
- 公测版：界面上未开放的功能统一写"后续版本提供"（原来写内部阶段代号）；需求编号（如"（F-33）""（R-CASH-01）"）与页面编号
  （"（P-06）"）仍出现在少数提示里，简报只要求去掉阶段代号，未改，见汇报的已知问题。

## F-1 的偏离与约定（I-1 阶段末审查的修复，公测版 0.0.2）

按简报 F-1 的主会话裁决与 PRD §6.2 的 2026-10-19 裁决段实现；表结构（v4）、触发器、领域包、协议包都没有改。规格没写到、按最保守
做法定下的：

- **转分期调整的先后只认"严格早于"**：账单当前版本的录入时刻与分期计划的建立时刻（都按绝对时刻比较）相同时不调整，按新增账单
  原值计——分不出先后时宁可负债偏大（把本金算两次），不偏小。App 里的时刻精确到微秒，实际不会相同；测试里同一时刻写入的
  （例如演示数据、I-1c 的 F-30 例子是先建计划后录账单）都不调整。
- **转分期调整只对入账日已知、账期就是那一期账单 S 的消费**；入账日未知、只是"可能"在 S 里的消费不调整（负债偏大），界面提示
  "可能已出账，请补入账日"，补了入账日之后按确定的账期算。S 已经不是本期（转分期之前已录入了更新一期的账单）时，裁决只调整 S，
  而 S 已并入下一期、不计入负债，所以负债里不扣这笔本金（偏大）；这时请按银行调整后的账单给本期录入修正版本。
- **"无需还款"**：裁决列出的 ≤ 0 的三种（已还清、已入账待银行确认、已转分期）都以有还款或转分期为前提；新增账单本身 ≤ 0、又没有
  还款与转分期的（例如账单日前已还清、溢缴）显示"无需还款"，< 0 时另显示贷方余额。
- **"已还清"只认银行确认**：账单日之后入账的还款合计足额、但只按银行确认的不足额时是"已入账（待银行确认）"。转分期本身就把这期
  结清时是"已转分期"（之后再有还款也一样，多出的显示为贷方余额）。到期日当天仍是"待还"，过了才是"已逾期"（与 0.0.1 相同）。
- **已并入下一期的旧账单**：剩余应还显示为 0、不计入任何合计，详情页说明"已并入 MM-DD 账单"；只禁止新的还款分配，人工修正仍
  可以（只影响这期的记录，不影响负债）。账单日前就已还清的旧账单同样显示"已并入"。
- **人工修正看有效状态**：有效状态"已还清"的账单不能再修正（裁决举的例子）。若新增账单录小了、又按录的金额还清，这期会显示
  "已还清"且不能修正——请在下一期账单里体现差额；冲正后又可以修正。这一点可能需要再裁决（见 F-1 汇报的疑问）。
- **读模型只读**：删去了打开账单时写"已逾期"与把到期的"用户已标记"写成"待核对"的维护（`markOverdueMarkedPaid` 已删），两者都由
  读模型推导；0.0.1 已写进库的账单"已逾期"作为动作记录保留、不用于显示，已写成"待核对"的还款照常显示为待核对（两种动作一样）。
  冲正后存储状态"已结清"不回退，因结清而记为
  "已结清"的分期各期与"已还完"的计划也不回退（触发器不改）——负债与剩余应还按金额与日期计算，不受影响，只是分期卡片上计划的
  状态文字可能仍是"已还完"。
- **没有任何账单的子账户**：银行入账的还款不冲减任何金额（没有本期可扣；负债偏大），界面上登记还款本来也要先有账单（BL-27）。
- **还款分配**：仓库只允许分到本期账单（更早的被拒并说明）；本期已还清也允许再分配，"多还要先确认"由表单在保存前弹确认框做，
  仓库不再拦。登记时还不知道入账日，"早于本期账单日的还款不会再扣减"的提示按预计扣款日判断（只是提示）。
- **系统处理的差异项**：状态"已处理"、处理者"系统"、结果代码 `dismissed`（结果代码的 CHECK 只有 7 种、表里没有原因列；不能为它
  加列）；界面按引用对象现在的状态写明原因。删除与作废都不可撤销，所以原因不会变。修正账单、作废分期、补入账日不涉及任何差异项的
  引用（4 类差异项只引用还款或交易），所以没有要系统处理的。
- **撤销入口的位置**：0.0.1 的界面里看不到未出账的交易（只在已录入账单的"本期交易"里列），无法删除；账单中心在账单列表下面加了
  "不在已录账单里的交易"一节。删除已转分期的交易 = 先作废计划、再删除交易两次仓库调用（都用已有方法）；作废成功而删除失败时，
  计划保持作废、原消费回到未出账，界面给出失败原因。
- **分期成本**：组件测试在伪时钟里等不到后台 isolate，`pumpCardFlowApp` 默认改成就地计算（`inlineInstallmentCosts`），R-04 的测试用
  真正的后台 isolate（在根 zone 里发起，才能在 `runAsync` 里拿到结果）。Web 构建没有 isolate，就地计算（只作编译烟雾测试）。
- **切换空间**：其余 Tab 的旧栈在下次点进时才清（go_router 没有一次清掉全部分支栈的公开方法）；从没有工作空间（P-22）进入时不强制
  回首页（「手工建卡」要去新建卡片）。
- **CI（审查 R-11）**：Verify IPA 断言版本名 = pubspec 版本名、标签构建时 = 标签去掉 `ios-v`、构建号 = 运行序号；Required Reason 扫描对
  "须由 App 清单承担、App 清单却未登记"的类别失败（登记了而没命中的只报告）。三处 flutter-action 都 `cache: false`，先 dry-run 取路径与键，
  再用固定 SHA 的 `actions/cache`（v5.1.0）缓存 Flutter SDK 与 pub 缓存（沿用原来的缓存键，第一次运行就命中）——flutter-action 里引用
  `actions/cache@v5` 的两个步骤从此不执行。**接受的残余**：运行器建立 job 时仍按标签下载 flutter-action 引用的 `actions/cache@v5`
  （作业日志 "Download action repository 'actions/cache@v5'"，本次解析到与我们固定的同一提交 caa29612…），只下载、不执行；要彻底
  去掉只能换掉 flutter-action（例如自己下载 SDK），不在本任务范围。ios-unsigned 的改动在本任务里没有运行（不触发 iOS 构建），
  断言语句在本机按同样的输入模拟过（`evidence/f1/ci-r11-local.txt`），下次推 `ios-v*` 标签时首次在 macOS 上运行。
- **删除币种子账户**：说明写出是哪几类记录（交易、账单、还款、分期），不写条数；已删除/作废的记录也算（它们仍引用这个子账户）。

## 领域层（I-0c）：`packages/cardflow_domain`

**分层**：领域层是独立的纯 Dart 包（不依赖 Flutter、drift、数据库），App 在 `pubspec.yaml` 里以 path
依赖引入。依赖只向下：页面/Provider → 用例 → 领域包；数据层（drift 加密库）负责把表行映射成领域对象
或协议 v1 文档，领域包本身不读写数据库。语义与服务端 Python 引擎 1.1.0
（`services/api/cardflow/planner/engine/`）一一对应，以 `docs/30-rules-engine/engine-spec.md` §12/§12.1 为准。
金额展示组件 `MoneyText` 的最小单位位数表就是领域包的 `minorDigits`（`lib/app/money/money_format.dart`
只转导出，不再自带一份）。

| 库 | 内容 |
|---|---|
| `package:cardflow_domain/cardflow_domain.dart` | `Money`/`minorDigits`/`toMinor`/`fromMinor`/`applyRate`/`decimalText`/`Rational`/`RoundingMode`；`LocalDate`/`Timestamp`/`TimePrecision`；`BillingRule`/`cyclesForTransaction`/`selectRule`/`resolveCycle`；`CashEvent`/`Snapshot`/`Scenario`/`buildTimeline`/`evaluate`；`CardOption`/`PlanRequest`/`ModelInputs`/`capacityLayers`/`classify`；`verify`；`dataIssues`/`baselineCheck`；`boundedSearch`；分期（I-1c）：`RemainderTo`/`splitInstallments`/`installmentCashFlows`/`irrMonthly`/`installmentIrrFlows`/`annualize`；协议 v1：`parseJson`、`canonicalJson`、`protocolInputHash`、`inputsFromProtocol`、`inputsToProtocol`、`verifyFromProtocol`、`cardCyclesToProtocol` |
| `package:cardflow_domain/fixture_runner.dart` | golden fixture 运行器（依赖 dart:io，App 不引用） |
| `package:cardflow_domain/testing.dart` | 测试辅助：按 Python 测试写法构造协议文档（`protocolCard`、`protocolDocument`…）、带种子的随机文档（`randomPlanInput`） |

**分期模块**（I-1c，`lib/src/installment.dart`，主会话裁决）：`splitInstallments(principalMinor, periods, [remainderTo])`、
`installmentCashFlows(principalMinor, periods, perPeriodRate, {remainderTo, rateRounding})`、`irrMonthly(flows, {tol})`（默认 10^-12，
至多 200 次二分）、`installmentIrrFlows`、`annualize(monthlyRate)` → `(nominalX12, effectiveCompound)`，与 Python `money.py` 的
`split_installments`、`installment_cash_flows`、`irr_monthly`、`annualize` 逐条同义；只用 `int`/`BigInt`/`Rational`。IRR 的符号以
Python 代码的行为为准：月 0 放款为负、各期还款为正（Python 的 docstring 写反了）。测试 `test/installment_test.dart`：移植 Python 的
拆分守恒性质（200 例）、F-36、F-37、符号约定，以及 7 组 Python 对照样本（命令与原文见 `evidence/i1/I1-c/installment-parity.txt`）。

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


### 数据层 → 领域对象映射：账单（I-1c，`lib/data/mapping/ledger_mapping.dart`）

| 本地数据 | 领域对象 / 函数 | 说明 |
|---|---|---|
| 交易 + 规则版本 + 已出账单 | `transactionCycle` → `resolveCycle`，或 `selectRule` + `cyclesForTransaction` | 入账日已知取一个账期（已出账单优先）；未知取入账延迟区间内的可能账期（F-15） |
| 本子账户的账单 | `IssuedStatement(账单日, 到期日, 来源)` | 已出账单优先于规则预测（交易归属与分期各期都这样用） |
| 分期条款 | `installmentPeriodsOf` → `splitInstallments`、`installmentCashFlows`、`applyRate` | 每期收取与 Python 同义；首期一次收取见偏离 |
| 分期条款 + 各期 | `InstallmentCost.of` → `installmentIrrFlows`、`irrMonthly`、`annualize` | 名义 ×12 与实际年化（IRR 复利）；`percentText` 至多 4 位小数 |
| 还款 + 规则版本 | `creditDateOf` → `postingDateFor` | 负债核销日（信用账户业务时区，截止时点） |
| 分配 + 还款 + 入账日 | `paidOnStatement` | 只给存储状态的结清记录用（动作记录）：已入账才核销；未处理的疑似重复只计一次；`bankConfirmedOnly` 判断结清 |
| 子账户的还款 + 入账日 + 本期账单日 | `creditedAfter` | 入账日晚于本期账单日的银行已入账还款，不论分配（PRD §6.2 裁决段）；疑似重复只计一次 |
| 本期账单 + 当前版本 + 分期计划与各期 + 交易账期 | `installmentAdjustmentsFor` | 已出账消费转分期的调整（版本录入严格早于计划建立时） |
| 新增账单、入账/确认的还款、调整、到期日、今天 | `effectiveStatusOf` → `EffectiveStatementStatus` | 有效状态（纯函数，表驱动测试） |
| 本期账单 + 交易账期 + 分期各期 | `liabilityOf` → `LiabilityBreakdown` | 负债四分法（F-30；未来分期本金按账单日） |
| 分期条款 + 各期 | `InstallmentCostInput` → `InstallmentCost` | 可发到后台 isolate 的成本输入（审查 R-04） |
| 还款 + 快照日 + 释放时滞 | `releasedRepaymentsOn` | 时滞未知不释放（F-28） |


## 给 I-2 的接口（消费规划：从本地数据组装规划输入）

I-2 在本地规划"一笔消费怎么刷"：把本地数据组装成领域包的 `ModelInputs`，经 `inputsToProtocol`（它会再跑一遍
`inputsFromProtocol` 的全部交叉校验）得到协议 v1 文档，再交给 `verify`/`boundedSearch`。各部分的现成来源：

| 输入 | 本地来源 | 要点 |
|---|---|---|
| 卡（`CardOption`） | `CapacityModel.build(...)`（`domain_mapping.dart`）：每张未停用的卡一个，同账户共享可用额，预授权只记一张 | 目前用占位规则、`repayFrom` 为空串（容量计算不读它们）：I-2 要换成该账户在交易日生效的真实规则（`BillingRuleRepository.effectiveOn` 或 `billingRuleFromRow` + `selectRule`）与还款现金账户 id（须"计入可用现金"，`CashAvailability`） |
| 额度三层（卡 ≤ 信用账户 ≤ 授信池） | 同上，`capacityLayers`/`cardLimit`；池可用原值 = 池上限 − Σ 成员 `used_minor` | 临额到期回落（F-27）、负可用截零（F-26）、预授权（F-25）都已在映射里；有成员缺快照时池未知，不以 0 代替 |
| 现金账户、快照、事件 | `CashForecastReader.loadInputs()` → `CashDomainInputs`（`accounts`、`snapshots`、`events`、`issues`） | 只含"计入可用现金"且有快照的账户；陈旧（> 7 天）时结果是"假设分析"；先过 `checkCashTimelineInputs` |
| 情景 | `ScenarioRepository.list()`/`byKey` → `ScenarioParams` → `scenarioFromParams`（`cash_mapping.dart`） | 内置"已确认""基准预期"与用户压力情景；额度变化（`limitChanges`）本期只保存与校验，I-2 接进容量 |
| 已出账单 | `StatementRepository.list(currencyAccountId:)` → `IssuedStatement` | 交给 `resolveCycle`：已出账单优先于规则预测 |
| 应还与还款 | `LedgerReader.load()` → `LedgerData.currentStatementOf(子账户)`（本期账单的剩余应还 `remaining`、有效状态 `status`）、`liabilities`（负债四分法）；更早的账单已并入本期，不要另加 | 已登记还款的扣款已经是 `cash_events` 里带 `linked_repayment_id` 的事件（计划或确定），规划不要再重复计入 |
| 分期未来各期 | `CashDomainInputs.installmentDue`（`TailObligation`：到期日、本金 + 费用） | 资金日历窗口外的进入尾部责任 |

**预留（plan_reservations）将挂在哪里**：data-model §3 的 `plan_reservations(id, workspace_id, plan_id, currency_account_id,
cash_account_id, amount_minor, status active/converted/released, linked_transaction_id)`。按"加表与迁移"的步骤在 v5 加表（带
`workspace_id`、进 `workspaceDataTables`、演示数据写一行、隔离测试覆盖），并且：
- 额度侧：`CapacityModel.build` 算可用额时扣减该币种子账户 `active` 的预留（预留是计划中的占用，与快照的 `used_minor` 不重复）；
- 现金侧：采纳方案生成的还款计划用 v3 已有的 `cash_events.linked_plan_run_id`（层级 `planned`；同 `linked_repayment_id`，P-08 不可改，
  `CashEventRepository` 已拒绝直接修改这类事件），过期或转换时作废；
- 关联真实交易：`linked_transaction_id` 指向 `transactions.id`（同一币种子账户，携带账户列的复合外键），转换后不再占用。

**测试工厂**（`test/data/repositories/repository_test_support.dart`）：建库 `openRealTestDatabase`、`createTestWorkspace`；卡与账户
`createTestCard`、`declareTestRule`（默认 10 日出账、当月 28 日到期）、`primaryCurrencyAccount`、`recordTestSnapshot`；现金
`createTestCashAccount`、`addTestCashEvent`、`recordTestCashSnapshot`、`StaleAwareClock`；账单与还款 `recordTestStatement`、
`addTestTransaction`、`registerTestRepayment`、`insertTestRepaymentRow`；可以拨快的时钟 `SteppingClock`（同一测试里区分先录账单、
后转分期）；`expectRepositoryError`。组件测试：`pumpCardFlowApp`（`TestWorkspace.none/real/demo`、`seed`、`realClock`；分期成本默认
就地计算 `inlineInstallmentCosts`，`backgroundCosts: true` 保留后台 isolate）、`readWallet`、`readCashPlan`、`withCurrentScope`，账单读模型 `readLedger`
与种子 `seedLedger`（`test/features/statements/statement_pages_test.dart`），整页检查 `forEachScreen`、`expectNoForbiddenRepaymentUi`
（`test/support/forbidden_ui.dart`）。
