/// 本地库 v2 的业务表（drift 表 DSL；`dart run build_runner build` 生成 `app_database.g.dart`）。
///
/// 约定（data-model §10.14、I-1a 简报 §1）：
/// - 主键 `id` 是 TEXT 的 UUID v4（`lib/data/ids.dart`）；
/// - 日期是 TEXT `YYYY-MM-DD`（账户业务时区里的日历日期）；时刻是 TEXT RFC 3339、带偏移
///   （与领域包 `Timestamp.parse` 一致）；
/// - 金额是 INTEGER 最小单位，绝对值不超过 10^13（规则协议 v1 的 MinorAmount 上限）；
/// - 币种只允许领域包 `minorDigits` 的 13 种（CHECK，审查 §4 第 8 条；`schema_test` 逐个核对）；
/// - 所有业务表带 `workspace_id`，表间关联一律用 `(workspace_id, …)` 复合外键，数据库层面不能
///   跨工作空间关联（data-model §6）；
/// - 自由文本列带 G2 兜底 CHECK：不得含 13 位及以上连续数字（ui-spec §4.4；应用层校验更严，
///   见 `lib/data/validation/text_rules.dart`）；名称 ≤20 字、说明 ≤200 字（G5）；
/// - 表一律 STRICT；同步列（`local_seq`、`sync_state`、`server_row_version`）在纯本地阶段不建，
///   `row_version`/`updated_at` 保留。
///
/// 索引与触发器不在这里定义，而在 `schema.dart` 里以 SQL 写出（都带 `IF NOT EXISTS`，迁移可重跑）。
/// 改了这里的任何定义，都必须同时登记一步迁移并让 `test/data/db/schema_test.dart` 通过
/// （新建库与逐步升级上来的库结构完全一致）。
library;

import 'package:drift/drift.dart';

/// 工作空间：一个真实空间、一个演示空间（R-SYS-13；同一种最多一个未删除的，见索引）。
@DataClassName('WorkspaceRow')
class Workspaces extends Table {
  TextColumn get id => text()();

  /// `real` / `demo`。
  TextColumn get kind => text()();

  TextColumn get name => text()();

  /// RFC 3339。
  TextColumn get createdAt => text()();

  TextColumn get deletedAt => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  bool get isStrict => true;

  @override
  List<String> get customConstraints => [
    "CHECK (kind IN ('real', 'demo'))",
    'CHECK (length(name) BETWEEN 1 AND 20)',
  ];
}

/// App 级设置（不属于任何工作空间）：当前工作空间 id 等。
@DataClassName('AppSettingRow')
class AppSettings extends Table {
  TextColumn get key => text()();

  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};

  @override
  bool get isStrict => true;

  @override
  List<String> get customConstraints => [
    'CHECK (length("key") BETWEEN 1 AND 64)',
  ];
}

/// 银行（只有名称与默认业务时区，不带任何规则）。内置常用银行在第一次被选用时才写入本表
/// （`is_builtin = 1`），所以新建的工作空间里没有任何行。
@DataClassName('BankRow')
class Banks extends Table {
  TextColumn get id => text()();

  TextColumn get workspaceId => text()();

  TextColumn get name => text()();

  TextColumn get country => text().withDefault(const Constant('CN'))();

  TextColumn get businessTzDefault =>
      text().withDefault(const Constant('Asia/Shanghai'))();

  BoolColumn get isBuiltin => boolean().withDefault(const Constant(false))();

  TextColumn get createdAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {workspaceId, id},
    {workspaceId, name},
  ];

  @override
  bool get isStrict => true;

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (workspace_id) REFERENCES workspaces (id)',
    'CHECK (length(name) BETWEEN 1 AND 20)',
    "CHECK (name NOT GLOB '*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*')",
    "CHECK (length(country) = 2 AND country GLOB '[A-Z][A-Z]')",
  ];
}

/// 授信池：跨信用账户共享的额度上限（F-23）。
///
/// `shared_limit_minor` 与 `currency` 是本地新增的列（data-model §10.14，服务端表原缺池上限）。
/// 池可用原值 = 池上限 − Σ 成员账户该币种子账户最新快照的 `used_minor`，可为负；容量截零由
/// 领域包 `capacityLayers` 完成。`parent_pool_id` 保留与服务端一致，但协议 v1 只有一层池
/// （engine-spec §12.3：不得用一层池近似多层），本期仓库与界面只建单层池。
@DataClassName('CreditPoolRow')
class CreditPools extends Table {
  TextColumn get id => text()();

  TextColumn get workspaceId => text()();

  TextColumn get bankId => text()();

  TextColumn get name => text()();

  TextColumn get parentPoolId => text().nullable()();

  IntColumn get sharedLimitMinor => integer()();

  TextColumn get currency => text()();

  IntColumn get rowVersion => integer().withDefault(const Constant(1))();

  TextColumn get createdAt => text()();

  TextColumn get updatedAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {workspaceId, id},
    {workspaceId, bankId, name},
  ];

  @override
  bool get isStrict => true;

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (workspace_id) REFERENCES workspaces (id)',
    'FOREIGN KEY (workspace_id, bank_id) REFERENCES banks (workspace_id, id)',
    'FOREIGN KEY (workspace_id, parent_pool_id) REFERENCES credit_pools (workspace_id, id)',
    'CHECK (parent_pool_id IS NULL OR parent_pool_id <> id)',
    'CHECK (length(name) BETWEEN 1 AND 20)',
    "CHECK (name NOT GLOB '*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*')",
    'CHECK (shared_limit_minor BETWEEN 0 AND 10000000000000)',
    "CHECK (currency IN ('CNY', 'USD', 'EUR', 'HKD', 'GBP', 'MOP', 'TWD', 'JPY', 'KRW', 'VND', 'KWD', 'BHD', 'JOD'))",
    'CHECK (row_version >= 1)',
  ];
}

/// 信用账户：账单主体；账单日、还款日、规则版本挂在这里（R-CARD-03）。
///
/// `holder_alias` 是持卡人的称呼（例如"本人"，不是真实姓名）；账户在界面上的名字取主卡别名，
/// 没有时取产品名、再取银行名（`lib/data/repositories/card_wallet_reader.dart`）。
@DataClassName('CreditAccountRow')
class CreditAccounts extends Table {
  TextColumn get id => text()();

  TextColumn get workspaceId => text()();

  TextColumn get bankId => text()();

  TextColumn get productName => text().nullable()();

  TextColumn get holderAlias => text()();

  TextColumn get businessTz =>
      text().withDefault(const Constant('Asia/Shanghai'))();

  /// `active` / `frozen` / `closed`。
  TextColumn get status => text().withDefault(const Constant('active'))();

  TextColumn get openedOn => text().nullable()();

  TextColumn get closedOn => text().nullable()();

  TextColumn get poolId => text().nullable()();

  IntColumn get rowVersion => integer().withDefault(const Constant(1))();

  TextColumn get createdAt => text()();

  TextColumn get updatedAt => text()();

  TextColumn get deletedAt => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {workspaceId, id},
  ];

  @override
  bool get isStrict => true;

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (workspace_id) REFERENCES workspaces (id)',
    'FOREIGN KEY (workspace_id, bank_id) REFERENCES banks (workspace_id, id)',
    'FOREIGN KEY (workspace_id, pool_id) REFERENCES credit_pools (workspace_id, id)',
    'CHECK (product_name IS NULL OR length(product_name) BETWEEN 1 AND 20)',
    "CHECK (product_name NOT GLOB '*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*')",
    'CHECK (length(holder_alias) BETWEEN 1 AND 20)',
    "CHECK (holder_alias NOT GLOB '*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*')",
    "CHECK (status IN ('active', 'frozen', 'closed'))",
    "CHECK (opened_on IS NULL OR opened_on GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]')",
    "CHECK (closed_on IS NULL OR closed_on GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]')",
    'CHECK (closed_on IS NULL OR opened_on IS NULL OR closed_on >= opened_on)',
    'CHECK (row_version >= 1)',
  ];
}

/// 币种子账户：同一信用账户下按币种分设（账单与交易挂在这里）；建账户时默认建 CNY 主子账户。
@DataClassName('CurrencyAccountRow')
class CurrencyAccounts extends Table {
  TextColumn get id => text()();

  TextColumn get workspaceId => text()();

  TextColumn get creditAccountId => text()();

  TextColumn get currency => text()();

  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();

  IntColumn get rowVersion => integer().withDefault(const Constant(1))();

  TextColumn get createdAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {workspaceId, id},
    {creditAccountId, currency},
  ];

  @override
  bool get isStrict => true;

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (workspace_id, credit_account_id) REFERENCES credit_accounts (workspace_id, id)',
    "CHECK (currency IN ('CNY', 'USD', 'EUR', 'HKD', 'GBP', 'MOP', 'TWD', 'JPY', 'KRW', 'VND', 'KWD', 'BHD', 'JOD'))",
    'CHECK (row_version >= 1)',
  ];
}

/// 卡片：只是支付介质（末四位、卡组织、主/附、到期），不承载账单（PRD 术语表）。
///
/// 状态机见 PRD §6.1（`draft → active`、`active ⇄ frozen`、`active → replaced/closed`、
/// `frozen → closed`），非法转移由仓库拒绝，触发器兜底。附属卡的主卡、换卡后的新卡都必须在
/// 同一信用账户（复合外键带 `credit_account_id`）。
@DataClassName('CardRow')
class Cards extends Table {
  TextColumn get id => text()();

  TextColumn get workspaceId => text()();

  TextColumn get creditAccountId => text()();

  TextColumn get last4 => text()();

  /// `unionpay` / `visa` / `mastercard` / `amex` / `jcb` / `discover` / `other`。
  TextColumn get network => text().nullable()();

  /// `primary` / `supplementary`。
  TextColumn get holderKind => text()();

  TextColumn get primaryCardId => text().nullable()();

  /// `draft` / `active` / `frozen` / `replaced` / `closed`。
  TextColumn get status => text()();

  /// `YYYY-MM`。
  TextColumn get expiresYm => text().nullable()();

  TextColumn get replacedByCardId => text().nullable()();

  TextColumn get alias => text().nullable()();

  /// 卡片生效日（换卡/补卡时为新卡的生效日）。
  TextColumn get effectiveFrom => text().nullable()();

  /// 销卡日。
  TextColumn get closedOn => text().nullable()();

  IntColumn get rowVersion => integer().withDefault(const Constant(1))();

  TextColumn get createdAt => text()();

  TextColumn get updatedAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {workspaceId, id},
    {workspaceId, creditAccountId, id},
  ];

  @override
  bool get isStrict => true;

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (workspace_id, credit_account_id) REFERENCES credit_accounts (workspace_id, id)',
    'FOREIGN KEY (workspace_id, credit_account_id, primary_card_id) REFERENCES cards (workspace_id, credit_account_id, id)',
    'FOREIGN KEY (workspace_id, credit_account_id, replaced_by_card_id) REFERENCES cards (workspace_id, credit_account_id, id)',
    "CHECK (length(last4) = 4 AND last4 NOT GLOB '*[^0-9]*')",
    "CHECK (network IS NULL OR network IN ('unionpay', 'visa', 'mastercard', 'amex', 'jcb', 'discover', 'other'))",
    "CHECK (holder_kind IN ('primary', 'supplementary'))",
    "CHECK ((holder_kind = 'primary' AND primary_card_id IS NULL) OR (holder_kind = 'supplementary' AND primary_card_id IS NOT NULL AND primary_card_id <> id))",
    "CHECK (status IN ('draft', 'active', 'frozen', 'replaced', 'closed'))",
    "CHECK ((status = 'replaced') = (replaced_by_card_id IS NOT NULL))",
    'CHECK (replaced_by_card_id IS NULL OR replaced_by_card_id <> id)',
    "CHECK ((status = 'closed') = (closed_on IS NOT NULL))",
    "CHECK (expires_ym IS NULL OR (expires_ym GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]' AND substr(expires_ym, 6, 2) BETWEEN '01' AND '12'))",
    'CHECK (alias IS NULL OR length(alias) BETWEEN 1 AND 20)',
    "CHECK (alias NOT GLOB '*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*')",
    "CHECK (effective_from IS NULL OR effective_from GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]')",
    "CHECK (closed_on IS NULL OR closed_on GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]')",
    'CHECK (row_version >= 1)',
  ];
}

/// 账期规则版本（bank-rules-spec §2/§3）。保存新规则 = 新版本，旧版 `effective_to` 封口并标
/// `expired`（F-14）；同一主体的生效区间 `[effective_from, effective_to)` 不得重叠（仓库保证，
/// 触发器兜底）。
///
/// 本地与服务端 DDL 的差异：`effective_from` 可空（空 = 不限，适用于全部历史，与领域包
/// `BillingRule.effectiveFrom` 和协议 v1 一致）；新增入账延迟区间 `posting_delay_min_days`/
/// `posting_delay_max_days`（data-model §10.14）；`cutoff_time` 是业务时区里的 `HH:MM`
/// （入账时点晚于它则入账日加一天，F-19）。被"更正"取代的版本区间为空（`effective_to` ≤
/// `effective_from`，`effective_from` 为空时 `effective_to = '0001-01-01'`），任何日期都不选中它。
@DataClassName('BillingRuleVersionRow')
class BillingRuleVersions extends Table {
  TextColumn get id => text()();

  TextColumn get workspaceId => text()();

  /// `credit_account` / `currency_account`。
  TextColumn get subjectKind => text()();

  TextColumn get subjectId => text()();

  IntColumn get statementDay => integer()();

  BoolColumn get statementDayInclusive =>
      boolean().withDefault(const Constant(true))();

  /// `fixed_day` / `days_after_statement`。
  TextColumn get dueKind => text()();

  IntColumn get dueDay => integer().nullable()();

  IntColumn get dueMonthOffset => integer().withDefault(const Constant(0))();

  IntColumn get dueDays => integer().nullable()();

  /// `calendar` / `business`。
  TextColumn get dueDayKind => text().withDefault(const Constant('calendar'))();

  /// `none` / `next_business_day`。
  TextColumn get holidayRollover =>
      text().withDefault(const Constant('none'))();

  /// 业务时区里的 `HH:MM`；空 = 不按时刻判断入账日。
  TextColumn get cutoffTime => text().nullable()();

  IntColumn get postingDelayMinDays =>
      integer().withDefault(const Constant(0))();

  IntColumn get postingDelayMaxDays =>
      integer().withDefault(const Constant(0))();

  /// `user_declared` / `official_template`。
  TextColumn get source => text()();

  TextColumn get effectiveFrom => text().nullable()();

  TextColumn get effectiveTo => text().nullable()();

  TextColumn get verifiedOn => text().nullable()();

  IntColumn get version => integer()();

  /// 与服务端同一取值集合；工作空间私有规则不得为 `verified`/`published`（R2-13）。
  TextColumn get reviewStatus => text()();

  TextColumn get exceptions => text().nullable()();

  TextColumn get createdAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {workspaceId, id},
    {workspaceId, subjectKind, subjectId, version},
  ];

  @override
  bool get isStrict => true;

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (workspace_id) REFERENCES workspaces (id)',
    "CHECK (subject_kind IN ('credit_account', 'currency_account'))",
    'CHECK (statement_day BETWEEN 1 AND 31)',
    "CHECK (due_kind IN ('fixed_day', 'days_after_statement'))",
    'CHECK (due_day IS NULL OR due_day BETWEEN 1 AND 31)',
    'CHECK (due_month_offset IN (0, 1, 2))',
    'CHECK (due_days IS NULL OR due_days BETWEEN 1 AND 60)',
    "CHECK ((due_kind = 'fixed_day' AND due_day IS NOT NULL AND due_days IS NULL) OR (due_kind = 'days_after_statement' AND due_days IS NOT NULL AND due_day IS NULL))",
    "CHECK (due_day_kind IN ('calendar', 'business'))",
    "CHECK (holiday_rollover IN ('none', 'next_business_day'))",
    "CHECK (cutoff_time IS NULL OR (cutoff_time GLOB '[0-2][0-9]:[0-5][0-9]' AND cutoff_time <= '23:59'))",
    'CHECK (posting_delay_min_days BETWEEN 0 AND 366 AND posting_delay_max_days BETWEEN posting_delay_min_days AND 366)',
    "CHECK (source IN ('user_declared', 'official_template'))",
    "CHECK (effective_from IS NULL OR effective_from GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]')",
    "CHECK (effective_to IS NULL OR effective_to GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]')",
    'CHECK (effective_to IS NULL OR effective_from IS NULL OR effective_to >= effective_from)',
    "CHECK (verified_on IS NULL OR verified_on GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]')",
    'CHECK (version >= 1)',
    "CHECK (review_status IN ('draft', 'in_review', 'user_declared', 'expired'))",
    'CHECK (exceptions IS NULL OR length(exceptions) BETWEEN 1 AND 200)',
    "CHECK (exceptions NOT GLOB '*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*')",
  ];
}

/// 额度快照（bank-rules-spec §5，data-model §4 DDL）。只追加，不修改（触发器）。
///
/// 本地新增 `holds_minor`：快照时点已知的预授权占用合计。`includes_holds = 1`（银行显示的
/// 可用额已扣除预授权）时它只作展示，不再扣减；为 0 时从可用额里扣减一次（F-25）。服务端把
/// 预授权放在单独的 `preauth_holds` 表，本期不建。
@DataClassName('LimitSnapshotRow')
class LimitSnapshots extends Table {
  TextColumn get id => text()();

  TextColumn get workspaceId => text()();

  TextColumn get currencyAccountId => text()();

  IntColumn get fixedMinor => integer()();

  IntColumn get tempMinor => integer().withDefault(const Constant(0))();

  TextColumn get tempExpiresOn => text().nullable()();

  IntColumn get specialMinor => integer().withDefault(const Constant(0))();

  TextColumn get specialPurpose => text().nullable()();

  IntColumn get usedMinor => integer()();

  /// 银行显示的可用额度原值，可为负（超限原值保留，F-26）。
  IntColumn get availableRawMinor => integer()();

  IntColumn get holdsMinor => integer().withDefault(const Constant(0))();

  BoolColumn get includesHolds => boolean()();

  /// `bank_app` / `statement` / `user` / `import`。
  TextColumn get sourceKind => text()();

  TextColumn get sourceDocumentId => text().nullable()();

  /// 实际余额时点（RFC 3339）。
  TextColumn get balanceAsOf => text()();

  TextColumn get observedAt => text()();

  TextColumn get recordedAt => text()();

  /// `system_estimated` / `user_confirmed` / `bank_confirmed`。
  TextColumn get confirmationLevel => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {workspaceId, id},
  ];

  @override
  bool get isStrict => true;

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (workspace_id, currency_account_id) REFERENCES currency_accounts (workspace_id, id)',
    'CHECK (fixed_minor BETWEEN 0 AND 10000000000000)',
    'CHECK (temp_minor BETWEEN 0 AND 10000000000000)',
    'CHECK (temp_minor = 0 OR temp_expires_on IS NOT NULL)',
    "CHECK (temp_expires_on IS NULL OR temp_expires_on GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]')",
    'CHECK (special_minor BETWEEN 0 AND 10000000000000)',
    'CHECK (special_minor = 0 OR special_purpose IS NOT NULL)',
    'CHECK (special_purpose IS NULL OR length(special_purpose) BETWEEN 1 AND 20)',
    "CHECK (special_purpose NOT GLOB '*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*')",
    'CHECK (used_minor BETWEEN 0 AND 10000000000000)',
    'CHECK (available_raw_minor BETWEEN -10000000000000 AND 10000000000000)',
    'CHECK (holds_minor BETWEEN 0 AND 10000000000000)',
    "CHECK (source_kind IN ('bank_app', 'statement', 'user', 'import'))",
    "CHECK (balance_as_of GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*')",
    "CHECK (observed_at GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*')",
    "CHECK (recorded_at GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*')",
    "CHECK (confirmation_level IN ('system_estimated', 'user_confirmed', 'bank_confirmed'))",
  ];
}
