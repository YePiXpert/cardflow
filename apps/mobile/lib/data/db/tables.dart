/// 本地库的业务表（drift 表 DSL；`dart run build_runner build` 生成 `app_database.g.dart`）：
/// v2（I-1a）的工作空间、银行、信用账户与额度，v3（I-1b）的现金账户、现金事件与情景。
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

// ---------------------------------------------------------------------------
// v3（I-1b）：现金账户、余额快照与已包含事件、现金事件（唯一现金事实表）、周期事项与单期覆盖、
// 情景与情景计算版本。约定同上；另见 data-model §3/§4、§10.5（同账户一致用携带账户列的复合外键）。
// ---------------------------------------------------------------------------

/// 现金账户（R-CASH-01）：可用于还款的资金账户。
///
/// 可用性（数据层 → 领域映射见 `lib/data/mapping/cash_mapping.dart`）：`kind = restricted` 或
/// `usable_for_repayment = 0` 且没有 `available_from` 的账户不进入可用现金；有 `available_from`
/// 的从该日起可用。受限账户不能直接标为可用于还款（CHECK），只能设可用日期。
/// 现金账户没有业务时区列：日期与时刻按默认业务时区（Asia/Shanghai）解释。
@DataClassName('CashAccountRow')
class CashAccounts extends Table {
  TextColumn get id => text()();

  TextColumn get workspaceId => text()();

  TextColumn get name => text()();

  TextColumn get currency => text()();

  /// `bank` / `wallet` / `wealth` / `restricted`。
  TextColumn get kind => text()();

  BoolColumn get usableForRepayment =>
      boolean().withDefault(const Constant(true))();

  /// 理财/受限资金可用于还款的起始日（`YYYY-MM-DD`）；空 = 未设置。
  TextColumn get availableFrom => text().nullable()();

  /// 用户最低储备（硬约束，≥0）。
  IntColumn get reserveFloorMinor => integer().withDefault(const Constant(0))();

  /// `active` / `closed`（已停用：不进入资金日历，历史保留）。
  TextColumn get status => text().withDefault(const Constant('active'))();

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
    'CHECK (length(name) BETWEEN 1 AND 20)',
    "CHECK (name NOT GLOB '*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*')",
    "CHECK (currency IN ('CNY', 'USD', 'EUR', 'HKD', 'GBP', 'MOP', 'TWD', 'JPY', 'KRW', 'VND', 'KWD', 'BHD', 'JOD'))",
    "CHECK (kind IN ('bank', 'wallet', 'wealth', 'restricted'))",
    "CHECK (kind <> 'restricted' OR usable_for_repayment = 0)",
    "CHECK (available_from IS NULL OR available_from GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]')",
    'CHECK (reserve_floor_minor BETWEEN 0 AND 10000000000000)',
    "CHECK (status IN ('active', 'closed'))",
    'CHECK (row_version >= 1)',
  ];
}

/// 现金余额快照（R-CASH-01/06）：`balance_as_of` 是余额对应的业务日期，`observed_at` 是实际时点
/// （G3：不晚于现在，缺实际时点不可存）。只追加，不修改（触发器）。快照当天、余额已经包含的事件
/// 记在 [SnapshotIncludedEvents]。
@DataClassName('CashSnapshotRow')
class CashBalanceSnapshots extends Table {
  TextColumn get id => text()();

  TextColumn get workspaceId => text()();

  TextColumn get cashAccountId => text()();

  /// 余额（最小单位，可为负：透支）。
  IntColumn get balanceMinor => integer()();

  /// `YYYY-MM-DD`。
  TextColumn get balanceAsOf => text()();

  /// RFC 3339。
  TextColumn get observedAt => text()();

  /// `bank_app` / `statement` / `user` / `import`。
  TextColumn get sourceKind => text()();

  /// `system_estimated` / `user_confirmed` / `bank_confirmed`。
  TextColumn get confirmationLevel => text()();

  TextColumn get recordedAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {workspaceId, id},
    {workspaceId, cashAccountId, id},
  ];

  @override
  bool get isStrict => true;

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (workspace_id, cash_account_id) REFERENCES cash_accounts (workspace_id, id)',
    'CHECK (balance_minor BETWEEN -10000000000000 AND 10000000000000)',
    "CHECK (balance_as_of GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]')",
    "CHECK (observed_at GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*')",
    "CHECK (recorded_at GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*')",
    "CHECK (source_kind IN ('bank_app', 'statement', 'user', 'import'))",
    "CHECK (confirmation_level IN ('system_estimated', 'user_confirmed', 'bank_confirmed'))",
  ];
}

/// 快照当天（及以前）余额已经包含的事件（R-CASH-06）。复合外键带 `cash_account_id`：只能列
/// 本账户的事件；事件日期不得晚于快照日（仓库校验，触发器兜底；规则协议 v1 的交叉规则 R3E-14）。
@DataClassName('SnapshotIncludedEventRow')
class SnapshotIncludedEvents extends Table {
  TextColumn get workspaceId => text()();

  TextColumn get cashAccountId => text()();

  TextColumn get snapshotId => text()();

  TextColumn get cashEventId => text()();

  @override
  Set<Column<Object>> get primaryKey => {snapshotId, cashEventId};

  @override
  bool get isStrict => true;

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (workspace_id, cash_account_id, snapshot_id) REFERENCES cash_balance_snapshots (workspace_id, cash_account_id, id)',
    'FOREIGN KEY (workspace_id, cash_account_id, cash_event_id) REFERENCES cash_events (workspace_id, cash_account_id, id)',
  ];
}

/// 现金事件：唯一的现金事实表（data-model §3）。收入为正、支出为负（符号按类别约束，R2-16）。
///
/// - `cls`：`confirmed` 确定 / `expected` 预计 / `planned` 计划（系统生成：还款、计划运行）；没有任何
///   "概率"字段（R-CASH-03）；
/// - `posting_status`：`planned` 尚未发生 / `posted` 已发生（已发生的必为确定）；
/// - 周期事项展开的事件带 `recurring_item_id` + `occurrence_key`（该期原定日期）；
/// - 调拨是两条事件共享 `transfer_group_id`（转出为负、到账为正，到账日不早于转出日，两端账户
///   不同、币种相同；触发器兜底），两条腿只能一起删除；
/// - `linked_repayment_id`（I-1c 的还款）与 `linked_plan_run_id`（I-2 的计划运行）暂无外键。
@DataClassName('CashEventRow')
class CashEvents extends Table {
  TextColumn get id => text()();

  TextColumn get workspaceId => text()();

  TextColumn get cashAccountId => text()();

  /// 业务日期 `YYYY-MM-DD`。
  TextColumn get eventOn => text()();

  /// 精确时刻（RFC 3339，按其自身偏移的日期必须等于 `event_on`）；空 = 只知道日期。
  TextColumn get eventAt => text().nullable()();

  IntColumn get amountMinor => integer()();

  /// `confirmed` / `expected` / `planned`。
  TextColumn get cls => text()();

  /// `income` / `bill` / `living` / `repayment` / `transfer_in` / `transfer_out` / `fee` / `other`。
  TextColumn get category => text()();

  TextColumn get label => text().nullable()();

  /// `planned` / `posted`。
  TextColumn get postingStatus =>
      text().withDefault(const Constant('planned'))();

  TextColumn get recurringItemId => text().nullable()();

  /// 周期事项的期键：该期的原定日期 `YYYY-MM-DD`。
  TextColumn get occurrenceKey => text().nullable()();

  TextColumn get transferGroupId => text().nullable()();

  TextColumn get linkedRepaymentId => text().nullable()();

  TextColumn get linkedPlanRunId => text().nullable()();

  IntColumn get rowVersion => integer().withDefault(const Constant(1))();

  TextColumn get createdAt => text()();

  TextColumn get updatedAt => text()();

  TextColumn get deletedAt => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {workspaceId, id},
    {workspaceId, cashAccountId, id},
  ];

  @override
  bool get isStrict => true;

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (workspace_id, cash_account_id) REFERENCES cash_accounts (workspace_id, id)',
    'FOREIGN KEY (workspace_id, cash_account_id, recurring_item_id) REFERENCES recurring_items (workspace_id, cash_account_id, id)',
    "CHECK (event_on GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]')",
    "CHECK (event_at IS NULL OR (event_at GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*' AND substr(event_at, 1, 10) = event_on))",
    'CHECK (amount_minor <> 0 AND amount_minor BETWEEN -10000000000000 AND 10000000000000)',
    "CHECK (cls IN ('confirmed', 'expected', 'planned'))",
    "CHECK (category IN ('income', 'bill', 'living', 'repayment', 'transfer_in', 'transfer_out', 'fee', 'other'))",
    "CHECK ((category IN ('income', 'transfer_in') AND amount_minor > 0) OR (category IN ('bill', 'living', 'repayment', 'transfer_out', 'fee') AND amount_minor < 0) OR category = 'other')",
    'CHECK (label IS NULL OR length(label) BETWEEN 1 AND 20)',
    "CHECK (label NOT GLOB '*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*')",
    "CHECK (posting_status IN ('planned', 'posted'))",
    "CHECK (posting_status = 'planned' OR cls = 'confirmed')",
    'CHECK ((recurring_item_id IS NULL) = (occurrence_key IS NULL))',
    "CHECK (occurrence_key IS NULL OR occurrence_key GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]')",
    "CHECK ((transfer_group_id IS NOT NULL) = (category IN ('transfer_in', 'transfer_out')))",
    'CHECK (transfer_group_id IS NULL OR recurring_item_id IS NULL)',
    'CHECK (row_version >= 1)',
  ];
}

/// 周期事项（R-CASH-02）：按需展开成 [CashEvents]（展开到 horizon，`occurrence_key` = 该期原定日期），
/// 单期可覆盖/跳过而不影响他期（[RecurringOverrides]）。
///
/// 期的规则：`anchor_on + k·周期`（k ≥ 0）落在 `[start_on, end_on]` 内；按月/按年时 `day_rule`
/// 为 `anchor_day`（锚定日的日号，小月截到月末）或 `month_end`（每月最后一天）。不支持工作日规则
/// （本阶段没有已核验的节假日日历）。调拨不能做成周期事项。
@DataClassName('RecurringItemRow')
class RecurringItems extends Table {
  TextColumn get id => text()();

  TextColumn get workspaceId => text()();

  TextColumn get cashAccountId => text()();

  TextColumn get label => text()();

  IntColumn get amountMinor => integer()();

  /// `confirmed` / `expected` / `planned`。
  TextColumn get cls => text()();

  /// `income` / `bill` / `living` / `repayment` / `fee` / `other`。
  TextColumn get category => text()();

  /// `monthly` / `weekly` / `biweekly` / `yearly`。
  TextColumn get frequency => text()();

  TextColumn get anchorOn => text()();

  /// `anchor_day` / `month_end`。
  TextColumn get dayRule => text().withDefault(const Constant('anchor_day'))();

  TextColumn get startOn => text()();

  TextColumn get endOn => text().nullable()();

  BoolColumn get active => boolean().withDefault(const Constant(true))();

  IntColumn get rowVersion => integer().withDefault(const Constant(1))();

  TextColumn get createdAt => text()();

  TextColumn get updatedAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {workspaceId, id},
    {workspaceId, cashAccountId, id},
  ];

  @override
  bool get isStrict => true;

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (workspace_id, cash_account_id) REFERENCES cash_accounts (workspace_id, id)',
    'CHECK (length(label) BETWEEN 1 AND 20)',
    "CHECK (label NOT GLOB '*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*')",
    'CHECK (amount_minor <> 0 AND amount_minor BETWEEN -10000000000000 AND 10000000000000)',
    "CHECK (cls IN ('confirmed', 'expected', 'planned'))",
    "CHECK (category IN ('income', 'bill', 'living', 'repayment', 'fee', 'other'))",
    "CHECK ((category = 'income' AND amount_minor > 0) OR (category IN ('bill', 'living', 'repayment', 'fee') AND amount_minor < 0) OR category = 'other')",
    "CHECK (frequency IN ('monthly', 'weekly', 'biweekly', 'yearly'))",
    "CHECK (day_rule IN ('anchor_day', 'month_end'))",
    "CHECK (day_rule = 'anchor_day' OR frequency IN ('monthly', 'yearly'))",
    "CHECK (anchor_on GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]')",
    "CHECK (start_on GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]')",
    "CHECK (end_on IS NULL OR end_on GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]')",
    'CHECK (start_on >= anchor_on)',
    'CHECK (end_on IS NULL OR end_on >= start_on)',
    'CHECK (row_version >= 1)',
  ];
}

/// 周期事项的单期例外：`skip` 跳过该期；`override` 改该期的金额和/或日期、时刻。
@DataClassName('RecurringOverrideRow')
class RecurringOverrides extends Table {
  TextColumn get workspaceId => text()();

  TextColumn get recurringItemId => text()();

  /// 被覆盖的那一期的原定日期。
  TextColumn get occurrenceKey => text()();

  /// `skip` / `override`。
  TextColumn get action => text()();

  IntColumn get amountMinor => integer().nullable()();

  TextColumn get eventOn => text().nullable()();

  TextColumn get eventAt => text().nullable()();

  TextColumn get createdAt => text()();

  TextColumn get updatedAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {recurringItemId, occurrenceKey};

  @override
  bool get isStrict => true;

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (workspace_id, recurring_item_id) REFERENCES recurring_items (workspace_id, id)',
    "CHECK (occurrence_key GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]')",
    "CHECK (action IN ('skip', 'override'))",
    "CHECK ((action = 'skip' AND amount_minor IS NULL AND event_on IS NULL AND event_at IS NULL) OR (action = 'override' AND (amount_minor IS NOT NULL OR event_on IS NOT NULL)))",
    'CHECK (amount_minor IS NULL OR (amount_minor <> 0 AND amount_minor BETWEEN -10000000000000 AND 10000000000000))',
    "CHECK (event_on IS NULL OR event_on GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]')",
    "CHECK (event_at IS NULL OR (event_on IS NOT NULL AND event_at GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*' AND substr(event_at, 1, 10) = event_on))",
  ];
}

/// 现金情景（R-CASH-04，engine-spec §2 Scenario）。内置两条（`builtin_confirmed` 已确认、
/// `builtin_baseline` 基准）只读，参数固定（CHECK + 触发器）；用户压力情景 `user_stress` 只允许变差：
/// 收入延迟 0–180 天、收入比例 0–1、支出比例 1–10（规则协议 v1 的 ScaleFactor 上限）。系数存规范
/// 十进制文本（`Rational.parseDecimal` 可读）。`limit_changes`（额度变化，I-2 使用）与
/// `event_overrides` 是 JSON 数组。
@DataClassName('ScenarioRow')
class Scenarios extends Table {
  TextColumn get id => text()();

  TextColumn get workspaceId => text()();

  TextColumn get name => text()();

  /// `builtin_confirmed` / `builtin_baseline` / `user_stress`。
  TextColumn get kind => text()();

  BoolColumn get includeExpected => boolean()();

  IntColumn get incomeDelayDays => integer().withDefault(const Constant(0))();

  TextColumn get incomeScale => text().withDefault(const Constant('1'))();

  TextColumn get expenseScale => text().withDefault(const Constant('1'))();

  /// `conservative` / `timestamp`。
  TextColumn get sameDayOrder =>
      text().withDefault(const Constant('conservative'))();

  /// `[{"credit_account_id", "on", "change_minor"}]`。
  TextColumn get limitChanges => text().withDefault(const Constant('[]'))();

  /// `[{"event_id", "on"?, "amount_minor"?}]`。
  TextColumn get eventOverrides => text().withDefault(const Constant('[]'))();

  IntColumn get rowVersion => integer().withDefault(const Constant(1))();

  TextColumn get createdAt => text()();

  TextColumn get updatedAt => text()();

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
    "CHECK (kind IN ('builtin_confirmed', 'builtin_baseline', 'user_stress'))",
    'CHECK (income_delay_days BETWEEN 0 AND 180)',
    "CHECK (length(income_scale) BETWEEN 1 AND 12 AND income_scale NOT GLOB '*[^0-9.]*')",
    "CHECK (length(expense_scale) BETWEEN 1 AND 12 AND expense_scale NOT GLOB '*[^0-9.]*')",
    "CHECK (same_day_order IN ('conservative', 'timestamp'))",
    "CHECK (json_valid(limit_changes) AND json_type(limit_changes) = 'array')",
    "CHECK (json_valid(event_overrides) AND json_type(event_overrides) = 'array')",
    "CHECK (kind = 'user_stress' OR (income_delay_days = 0 AND income_scale = '1' AND expense_scale = '1' AND same_day_order = 'conservative' AND limit_changes = '[]' AND event_overrides = '[]'))",
    "CHECK ((kind = 'builtin_confirmed') = (include_expected = 0))",
    'CHECK (row_version >= 1)',
  ];
}

/// 情景的一次计算（P-09「重算」）：版本号逐个递增，旧版本保留用于对比；只追加，不修改。
/// `result` 是 JSON 对象（逐账户最低点与缺口点、假设、数据问题，见 `cash_mapping.dart`）。
@DataClassName('ScenarioRunRow')
class ScenarioRuns extends Table {
  TextColumn get id => text()();

  TextColumn get workspaceId => text()();

  TextColumn get scenarioId => text()();

  IntColumn get versionNo => integer()();

  TextColumn get computedAt => text()();

  TextColumn get horizonFrom => text()();

  TextColumn get horizonTo => text()();

  /// 输入的 sha256（小写十六进制）：与当前输入不同即"过期"。
  TextColumn get inputsHash => text()();

  TextColumn get result => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {workspaceId, id},
    {scenarioId, versionNo},
  ];

  @override
  bool get isStrict => true;

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (workspace_id, scenario_id) REFERENCES scenarios (workspace_id, id)',
    'CHECK (version_no >= 1)',
    "CHECK (computed_at GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*')",
    "CHECK (horizon_from GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]')",
    "CHECK (horizon_to GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]')",
    'CHECK (horizon_to >= horizon_from)',
    "CHECK (length(inputs_hash) = 64 AND inputs_hash NOT GLOB '*[^0-9a-f]*')",
    "CHECK (json_valid(result) AND json_type(result) = 'object')",
  ];
}
