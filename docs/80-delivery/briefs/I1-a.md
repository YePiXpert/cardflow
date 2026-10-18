# 简报 I-1a · 本地库 v2 + 工作空间（真实/演示）+ 建卡/信用账户/账期规则/额度快照（UF-1 步骤 1–3）

派发：待 I-0 阶段末审查的 blocker/major 修完后。对应 `ios-first-plan.md` §3 的 I-1 第一段。本任务**不出 IPA**，不触发 iOS 构建。若需重新派发，在开头加一句"先核对磁盘与 git 现状，不要重复创建"。

## 环境与规则
- 仓库 /projects/cardflow = `YePiXpert/cardflow`（公开，main）；`gh` 已登录；git 身份已配置。提交、代码、文档、CI 中不得出现 Claude/AI 署名或 trailer。
- Flutter 3.47.7 在 /opt/flutter-sdk（`export PATH=/opt/flutter-sdk/bin:$PATH`）。本机只能 analyze / test / build web；`flutter test` 会运行 sqlite3 钩子（真实 sqlite3mc）。
- 宿主是生产 VPS：不运行 docker；不改 /opt 下除 flutter-sdk 外的目录；不装系统包；不连接 127.0.0.1:5432。
- 范围：`apps/mobile/`（lib、test、README）、`evidence/i1/I1-a/`、根 README 的 `apps/mobile` 一行。**不改** `packages/cardflow_domain/`（领域包；发现缺口先停下汇报）、`packages/rules-protocol/`、`services/api/`、docs/。
- Dart 依赖只能来自 architecture §11 版本表。可用：drift 2.35.2、drift_flutter 0.3.1、sqlite3 3.7.1、drift_dev 2.35.1（已登记，可用表 DSL + 代码生成）、flutter_riverpod/riverpod_annotation/riverpod_generator、go_router 18.1.0、intl 0.20.3、flutter_secure_storage 11.2.0、path_provider 2.1.6、crypto 3.0.7。**不引入** uuid、timezone、freezed、json_serializable：UUID v4 用 `Random.secure()` 取 16 字节自写；时区见下文。表外依赖先停下汇报。
- 直接在 main 小步提交推送，不开 PR；每次推送后 CI dart job 必须绿；推送前核对未加入 build/、.dart_tool/、ephemeral、secrets。因用量上限可能中断，**每完成一小步就提交推送**。
- 改了带 `@riverpod`/drift 注解的文件后：`dart run build_runner build`，再 `dart format .`，生成的 `*.g.dart`/`*.drift.dart` 随源码提交（CI 不跑生成）。
- 证据存 evidence/i1/I1-a/（tee）。不把 mock 当完成；规格矛盾选最保守做法并写进"偏离/疑问"。
- 必读：docs/10-product/prd.md §4.1（R-CARD-01~06）、§4.9 R-SYS-13、§6.1、§10、UF-1；docs/50-ui/ui-spec.md §1、§2、§3、§4.2、§4.4、§4.5、P-01（只做本任务涉及的部分）、P-02、P-03、P-04、P-22、UF-1；docs/40-data-api/data-model.md §3、§4（credit_accounts/currency_accounts/cards/billing_rule_versions/limit_snapshots 的 DDL）、§8；docs/30-rules-engine/bank-rules-spec.md §3/§5；ADR-001、ADR-008；docs/60-ops-security/security-privacy.md §3；apps/mobile/README.md 全文（加密本地库"加表与迁移"、领域层 API）；`packages/rules-protocol/README.md` 末节的"从本地数据库映射到协议输入"；领域包源码 `lib/src/billing.dart`、`time.dart`、`allocation.dart`（`CardOption`、`ModelInputs`、`capacityLayers`）。

## 1. 本地库 v2（lib/data/db/）
- 用 drift 表 DSL + drift_dev 代码生成定义业务表；保留现有 `openAppDatabase` 失败即止流程与错误码。`LocalSchema.currentSchemaVersion` → 2；`schemaMigrations` 登记 1→2（只 expand）；`createSchema` 建出完整 v2。**测试**：新建库与 1→2 升级后的 `sqlite_master`（表、列、索引、触发器）完全一致；迁移在事务中，失败整体回滚；旧版 App 打开新库仍报 `schema_too_new`。
- 约定：id 为 TEXT UUID v4；日期 TEXT `YYYY-MM-DD`；时刻 TEXT RFC 3339 带偏移（与领域包 `Timestamp.parse` 一致）；金额 INTEGER 最小单位 + currency；利率/系数 TEXT 十进制规范形式（`Rational.parseDecimal` 可读）。所有业务表带 `workspace_id`，所有仓库查询都按当前工作空间过滤（见 §2 隔离测试）。
- 表（列以 data-model §3/§4 为准，本地省略同步列，`row_version`/`updated_at` 保留）：
  - `workspaces`(id, kind `real`/`demo`, name, created_at, deleted_at)；`app_settings`(key PRIMARY KEY, value)：当前工作空间 id 等。
  - `banks`(id, workspace_id, name, country 默认 `CN`, business_tz_default 默认 `Asia/Shanghai`, is_builtin)：内置常用银行名称列表（仅名称，不带任何规则）；用户可增。
  - `credit_pools`(id, workspace_id, bank_id, name, parent_pool_id, shared_limit_minor, currency)：data-model 缺上限字段，本地加 `shared_limit_minor`，**记入偏离**。池可用 = 池上限 − Σ 成员币种子账户最新快照 `used_minor`（同币种）；原值可负，容量截零由领域包 `capacityLayers` 完成。
  - `credit_accounts`(id, workspace_id, bank_id, product_name, holder_alias, business_tz, status `active`/`frozen`/`closed`, opened_on, closed_on, pool_id, created_at, updated_at, deleted_at)。
  - `currency_accounts`(id, workspace_id, credit_account_id, currency, is_primary) UNIQUE(credit_account_id, currency)；建账户时默认建 CNY 主子账户。
  - `cards`(id, workspace_id, credit_account_id, last4 CHECK 恰 4 位数字, network, holder_kind `primary`/`supplementary`, primary_card_id, status `draft`/`active`/`frozen`/`replaced`/`closed`, expires_ym, replaced_by_card_id, alias, effective_from, closed_on)。状态机 PRD §6.1：非法转移在仓库层拒绝并测试。
  - `billing_rule_versions`(id, workspace_id, subject_kind `credit_account`/`currency_account`, subject_id, statement_day 1–31, statement_day_inclusive, due_kind, due_day, due_month_offset 0/1/2, due_days 1–60, due_day_kind, holiday_rollover, cutoff_time, posting_delay_min_days, posting_delay_max_days, source `user_declared`/`official_template`, effective_from, effective_to, verified_on, version, review_status, exceptions, created_at)。同主体生效区间不得重叠（SQLite 无 EXCLUDE，仓库层保证并测试）；保存新规则 = 新版本，旧版 `effective_to` 封口、`review_status=expired`（F-14 的数据侧）。
  - `limit_snapshots`：按 DDL（fixed/temp/temp_expires_on/special/special_purpose/used/available_raw 可负/includes_holds/source_kind/balance_as_of/observed_at/recorded_at/confirmation_level）。
- 时区：领域包不带 tz 数据库。本任务只支持无夏令时的固定偏移时区（Asia/Shanghai、Asia/Hong_Kong、Asia/Macau、Asia/Taipei、Asia/Singapore、Asia/Tokyo、Asia/Seoul、UTC），放在 `lib/data/time/business_tz.dart` 的表里；UI 只允许选这些，其余标"后续支持"。业务日期 = 时刻按账户 `business_tz` 的偏移换算，与手机时区无关（F-20）。入账时点晚于规则 `cutoff_time`（按业务时区）则入账日 +1（F-19）；此推导在数据层，领域包只接收入账日。先核对 Python `billing.py` 是否已有 cutoff 语义：有则必须同义，没有则按上述实现并记入偏离。
- 把 `features/diagnostics/diagnostic_log.dart` 挪到 `lib/app/diagnostics/`（BL-06，数据层不得向上依赖 features）。
- 打开库报 `key_missing`/`wrong_key` 时的错误页加「重置本地数据」入口（BL-07）：按 ui-spec §4.5 确认页（写明影响、输入"删除"），删除数据库文件与钥匙串密钥后重新初始化；诊断日志记 `db/reset`（无内容）。

## 2. 工作空间与演示模式
- 首次启动无工作空间 → P-22；「手工建卡」创建真实空间后进 P-02 建卡；「体验演示」创建/进入演示空间。「从账单文件开始」「从备份恢复」「连接服务器」显示但禁用并注明所属阶段（I-3/I-4/后置）。
- 演示空间：合成数据卡 A/B/C（三个不同银行、其中两张卡属同一信用账户以体现 F-21；一个两账户共享池体现 F-23；一张负可用额度体现 F-26；一张临时额度带到期日体现 F-27），固定"今天"= 2026-10-16（通过 `clockProvider` 注入，真实空间用系统时间；陈旧判定在演示空间不触发）。每页顶部常驻紫色横幅"演示数据 · 与真实数据隔离"+「退出演示」，不可关闭；真实↔演示切换须确认；「清除演示数据」一键删空演示空间全部行。
- **隔离测试**：演示空间写入全部表后，以真实空间为当前空间运行每个仓库的全部查询，结果必须为空；反向亦然。

## 3. 页面（文案中文；颜色/字号/间距只从 tokens 取；金额只用 MoneyText；每页至少实现 首次空白/加载/错误/成功 四态，其余九态按 ui-spec 能做则做）
- **P-02 卡包**：授信池 › 信用账户 › 币种子账户 › 卡片 的层级列表；账户行显示别名、规则来源徽标（用户声明/官方模板）、可用容量、快照"{n} 天前"；已停用折叠；「+」新建弹层（银行、产品名、别名、末四位、卡组织、持卡人、主/附、到期年月；附卡须指定主卡）。校验：G2（任意文本 ≥13 位连续数字拒绝保存并提示"卡序不保存完整卡号"，含粘贴）、末四位恰 4 位数字、同银行同末四位 → "可能是同一信用账户的另一张卡"（加入既有账户 / 新建账户）、G5 长度；关闭系统卡号自动填充（`autofillHints` 不设卡号）。保存同时生成信用账户（默认 CNY 子账户）与卡片，状态 draft→active。
- **P-03 详情（最小版）**：头部（别名、规则来源、子账户切换）；本期区显示"预测账期（未出账）"：用领域包规则函数算出下一个账单日与到期日（无规则 → "未设置"› P-04；规则非法 → "规则非法，无法计算账期"）；额度区（固定/临时/专项、银行可用原值、是否已含预授权、可用容量、快照时点；负可用显示"超限"、容量 0）；卡片列表；「更新额度」「换卡/补卡」「销卡」「冻结/解冻」；规则说明区（当天归属、顺延、入账延迟）。换卡：新末四位 + 生效日，旧卡 replaced、新卡 active；销卡日 ≤ 今天，有欠款提示文案先放占位（账单在 I-1c）。本期应还/负债四分法/账单列表/活动权益区留空位并标"I-1c/I-4"。
- **P-04 信用账户设置**：账期规则编辑（来源、账单日 1–31 含月末截断提示、当天归属、到期类型 固定日/账单后 N 天、次月偏移、工作日/顺延、时区、入账延迟 min≤max、cutoff）+ **3 期预览**（用领域包算未来 3 个账单日与到期日，必须与领域包测试的 F-12/F-16 例子一致）；校验：到期须晚于账单日（阻止保存）；顺延/工作日开关在无已核验日历时禁用并说明（本阶段无日历，始终禁用）；时区默认 Asia/Shanghai；临时额度须到期日、专项须用途；银行可用可负；`balance_as_of`/`observed_at` ≤ 现在（G3）。额度快照表单 + 历史列表；币种子账户增删（主子账户不可删）；授信池：新建/加入/移出，显示池上限与池内合计（F-23）。保存规则 → 新版本、旧版封口；提示"已保存"（"{m} 个方案需重算"留到 I-2）。
- **P-22**：按 §2。
- **P-01 总览（最小版）**：每个账户一行"预测账期（未出账）"+ 到期日；无现金账户 → "数据不全：还没有现金账户"（入口留给 I-1b）；顶栏空间标识（真实/演示）与状态胶囊"纯本地"。
- 路由：卡包栈 P-02 → P-03 → P-04；无工作空间时任何路由先进 P-22（BL-04 的这一项）。
- 可访问性：新页面加入 `test/app/accessibility_test.dart` 的 3.0x 放大检查。

## 4. 测试（`flutter test`，真实 sqlite3mc）
- 迁移：新建 vs 升级结构一致；`schema_too_new`；回滚。
- 仓库：F-21（同账户两卡 → 一个信用账户、一个币种子账户、一个预测账期）；F-22（同银行两独立授信 → 两账户、两套预测账期）；F-23（池内账户可用合计不超池上限：构造 `ModelInputs` 调 `capacityLayers`，池层容量 = min(池上限 − Σused, Σ账户容量)，与领域包语义一致）；F-24（换卡后旧卡 replaced、账户与子账户 id 不变、新卡挂同一子账户；"交易不迁移"在 I-1c 复测）；F-25（`includes_holds=true` 时预授权不重复扣减；false 时扣减一次）；F-26（负可用原值保留，容量 0，UI 显示"超限"）；F-27（临额到期日后容量回落：同一快照在到期前/后两个日期的容量）；F-19（cutoff 前后两笔同日时刻入账日差 1）；F-20（同一瞬间以 +08:00、+00:00、−07:00 三种偏移写入，业务日期只取决于账户时区）；F-14 数据侧（新规则版本后旧版封口、按日期选版本用领域包 `selectRule`）；规则区间不重叠；卡状态机非法转移拒绝；G2 校验（13 位数字、粘贴）；末四位；工作空间隔离（§2）。
- 组件：P-02/P-03/P-04/P-22/P-01 的四态；新建卡流程；演示横幅不可关闭与退出确认；3.0x 放大。
- 日志：诊断日志与报告不含金额、末四位以外的卡片数字、别名；现有 `containsKeyMaterial` 类检查继续通过。
- `flutter analyze --fatal-infos` 零输出、`dart format` 无改动、`flutter build web` 通过。

## 5. 文档
- `apps/mobile/README.md`：目录表加 `lib/data/repositories/`、`lib/data/time/`；"加密本地库"加 v2 表清单与"加表步骤"实际做法（drift DSL + 生成）；新增"工作空间与演示模式"一节；"领域层"一节加"数据层 → 领域对象映射"小节（账户/卡/规则/快照 → `BillingRule`、`CardOption`、`ModelInputs`）。
- 根 README `apps/mobile` 一行状态改为"I-1a（建卡/账期/额度）"。

## 验收（evidence/i1/I1-a/）
analyze.txt、format.txt、test.txt、schema-diff.txt（新建 vs 升级的 sqlite_master 对比命令与输出）、isolation.txt（隔离测试输出）、build-web.txt、ci-dart-run.txt、git-log.txt。

## 回复格式
1. 完成项与路径；2. 验收结果（引用证据）；3. 偏离/疑问（含 credit_pools 上限字段、时区范围、cutoff 语义核对结果、任何表外依赖诉求）；4. 给 I-1b 的接口说明：仓库 API 与 provider（当前工作空间、clock、各仓库）、如何加 v3 表与迁移、测试辅助（建库/建演示空间/造账户与卡的工厂函数）、页面骨架与路由约定。
