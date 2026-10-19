import 'package:drift/drift.dart';

import 'database_errors.dart';

/// 本地库 schema 的定义与迁移。
///
/// 结构的两条路径：
/// - **新库**（[createSchema]）：meta 表 + drift 表 DSL（`tables.dart`）生成的全部业务表 +
///   当前版本的索引与触发器；
/// - **旧库升级**（[migrateSchema] + [schemaMigrations]）：逐步执行**冻结**在各版本的 SQL
///   （例如 [SchemaV2]）。冻结的意思是：以后再改 `tables.dart`，已发布版本的迁移步骤也不跟着
///   变——变化只能写进新的一步。
///
/// `test/data/db/schema_test.dart` 要求两条路径得到的 `sqlite_master`（表、列、索引、触发器）
/// 完全一致，所以改了 `tables.dart` 却没有写迁移、或冻结 SQL 抄错，测试都会失败。
///
/// 加表与迁移（I-1b 的 v3、I-1c 的 v4 即照此办理）：
/// 1. 在 `tables.dart` 加表或加列（drift 表 DSL），`app_database.dart` 的 `@DriftDatabase` 登记新表，
///    运行 `dart run build_runner build` 与 `dart format .`；
/// 2. [LocalSchema.currentSchemaVersion] 加 1；
/// 3. 新建 `SchemaV<n>`：冻结这一版**新增**的建表语句（`CREATE TABLE IF NOT EXISTS`，内容与 drift
///    生成的一字不差，可用 schema_test 里打印的新库结构对照）、索引与触发器（都带 `IF NOT EXISTS`）；
///    只做 expand（加表、加列、建索引/触发器），不改写金额原值（data-model §7）；
/// 4. 在 [schemaMigrations] 登记 `n-1 → n` 的一步，[latestIndexes]/[latestTriggers] 改成包含新版的；
/// 5. schema_test 增加"从 n-1 升级"的一致性比较（从 v1 升级的比较保留）。
///
/// 迁移在一个事务里执行，任何一步失败都整体回滚，并以
/// [DatabaseErrorCode.migrationFailed] 拒绝打开。
///
/// 幂等（审查 §4 第 5 条）：drift 在迁移回调返回**之后**才写 `PRAGMA user_version`，若 App 恰好
/// 在两者之间退出，下次启动会重跑同一步。因此 [createSchema] 与 [migrateSchema] 在自己的事务里
/// 同时写 `user_version`（与结构变更一起提交或一起回滚），各迁移步骤里的建表、建索引、建触发器
/// 也一律写 `IF NOT EXISTS`，重跑不报错（schema_test 有"重跑 1→2"的测试）。
abstract final class LocalSchema {
  /// 当前 schema 版本（drift 的 `PRAGMA user_version` 与 meta 表同时记录）。
  static const int currentSchemaVersion = 4;

  /// v1：meta 表（单行）——schema 版本与建库时间（UTC，ISO-8601）。
  static const String createMetaTable = '''
CREATE TABLE meta (
  id INTEGER NOT NULL PRIMARY KEY CHECK (id = 1),
  schema_version INTEGER NOT NULL,
  created_at TEXT NOT NULL
) STRICT''';
}

/// v2（I-1a）：工作空间、App 设置、银行、授信池、信用账户、币种子账户、卡片、账期规则版本、
/// 额度快照。表定义见 `tables.dart`；这里是冻结的 SQL（v1 → v2 的迁移步骤使用）。
abstract final class SchemaV2 {
  /// v2 新增的表（与 drift 由 `tables.dart` 生成的建表语句一字不差，只多了 `IF NOT EXISTS`；
  /// SQLite 在 sqlite_master 里保存语句时会去掉 `IF NOT EXISTS`）。
  static const List<String> tables = <String>[
    // workspaces
    'CREATE TABLE IF NOT EXISTS "workspaces" ('
        '"id" TEXT NOT NULL, '
        '"kind" TEXT NOT NULL, '
        '"name" TEXT NOT NULL, '
        '"created_at" TEXT NOT NULL, '
        '"deleted_at" TEXT NULL, '
        'PRIMARY KEY ("id"), '
        'CHECK (kind IN (\'real\', \'demo\')), '
        'CHECK (length(name) BETWEEN 1 AND 20)'
        ') STRICT',
    // app_settings
    'CREATE TABLE IF NOT EXISTS "app_settings" ('
        '"key" TEXT NOT NULL, '
        '"value" TEXT NOT NULL, '
        'PRIMARY KEY ("key"), '
        'CHECK (length("key") BETWEEN 1 AND 64)'
        ') STRICT',
    // banks
    'CREATE TABLE IF NOT EXISTS "banks" ('
        '"id" TEXT NOT NULL, '
        '"workspace_id" TEXT NOT NULL, '
        '"name" TEXT NOT NULL, '
        '"country" TEXT NOT NULL DEFAULT \'CN\', '
        '"business_tz_default" TEXT NOT NULL DEFAULT \'Asia/Shanghai\', '
        '"is_builtin" INTEGER NOT NULL DEFAULT 0 CHECK ("is_builtin" IN (0, 1)), '
        '"created_at" TEXT NOT NULL, '
        'PRIMARY KEY ("id"), '
        'UNIQUE ("workspace_id", "id"), '
        'UNIQUE ("workspace_id", "name"), '
        'FOREIGN KEY (workspace_id) REFERENCES workspaces (id), '
        'CHECK (length(name) BETWEEN 1 AND 20), '
        'CHECK (name NOT GLOB \'*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*\'), '
        'CHECK (length(country) = 2 AND country GLOB \'[A-Z][A-Z]\')'
        ') STRICT',
    // credit_pools
    'CREATE TABLE IF NOT EXISTS "credit_pools" ('
        '"id" TEXT NOT NULL, '
        '"workspace_id" TEXT NOT NULL, '
        '"bank_id" TEXT NOT NULL, '
        '"name" TEXT NOT NULL, '
        '"parent_pool_id" TEXT NULL, '
        '"shared_limit_minor" INTEGER NOT NULL, '
        '"currency" TEXT NOT NULL, '
        '"row_version" INTEGER NOT NULL DEFAULT 1, '
        '"created_at" TEXT NOT NULL, '
        '"updated_at" TEXT NOT NULL, '
        'PRIMARY KEY ("id"), '
        'UNIQUE ("workspace_id", "id"), '
        'UNIQUE ("workspace_id", "bank_id", "name"), '
        'FOREIGN KEY (workspace_id) REFERENCES workspaces (id), '
        'FOREIGN KEY (workspace_id, bank_id) REFERENCES banks (workspace_id, id), '
        'FOREIGN KEY (workspace_id, parent_pool_id) REFERENCES credit_pools (workspace_id, id), '
        'CHECK (parent_pool_id IS NULL OR parent_pool_id <> id), '
        'CHECK (length(name) BETWEEN 1 AND 20), '
        'CHECK (name NOT GLOB \'*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*\'), '
        'CHECK (shared_limit_minor BETWEEN 0 AND 10000000000000), '
        'CHECK (currency IN (\'CNY\', \'USD\', \'EUR\', \'HKD\', \'GBP\', \'MOP\', \'TWD\', \'JPY\', \'KRW\', \'VND\', \'KWD\', \'BHD\', \'JOD\')), '
        'CHECK (row_version >= 1)'
        ') STRICT',
    // credit_accounts
    'CREATE TABLE IF NOT EXISTS "credit_accounts" ('
        '"id" TEXT NOT NULL, '
        '"workspace_id" TEXT NOT NULL, '
        '"bank_id" TEXT NOT NULL, '
        '"product_name" TEXT NULL, '
        '"holder_alias" TEXT NOT NULL, '
        '"business_tz" TEXT NOT NULL DEFAULT \'Asia/Shanghai\', '
        '"status" TEXT NOT NULL DEFAULT \'active\', '
        '"opened_on" TEXT NULL, '
        '"closed_on" TEXT NULL, '
        '"pool_id" TEXT NULL, '
        '"row_version" INTEGER NOT NULL DEFAULT 1, '
        '"created_at" TEXT NOT NULL, '
        '"updated_at" TEXT NOT NULL, '
        '"deleted_at" TEXT NULL, '
        'PRIMARY KEY ("id"), '
        'UNIQUE ("workspace_id", "id"), '
        'FOREIGN KEY (workspace_id) REFERENCES workspaces (id), '
        'FOREIGN KEY (workspace_id, bank_id) REFERENCES banks (workspace_id, id), '
        'FOREIGN KEY (workspace_id, pool_id) REFERENCES credit_pools (workspace_id, id), '
        'CHECK (product_name IS NULL OR length(product_name) BETWEEN 1 AND 20), '
        'CHECK (product_name NOT GLOB \'*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*\'), '
        'CHECK (length(holder_alias) BETWEEN 1 AND 20), '
        'CHECK (holder_alias NOT GLOB \'*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*\'), '
        'CHECK (status IN (\'active\', \'frozen\', \'closed\')), '
        'CHECK (opened_on IS NULL OR opened_on GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]\'), '
        'CHECK (closed_on IS NULL OR closed_on GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]\'), '
        'CHECK (closed_on IS NULL OR opened_on IS NULL OR closed_on >= opened_on), '
        'CHECK (row_version >= 1)'
        ') STRICT',
    // currency_accounts
    'CREATE TABLE IF NOT EXISTS "currency_accounts" ('
        '"id" TEXT NOT NULL, '
        '"workspace_id" TEXT NOT NULL, '
        '"credit_account_id" TEXT NOT NULL, '
        '"currency" TEXT NOT NULL, '
        '"is_primary" INTEGER NOT NULL DEFAULT 0 CHECK ("is_primary" IN (0, 1)), '
        '"row_version" INTEGER NOT NULL DEFAULT 1, '
        '"created_at" TEXT NOT NULL, '
        'PRIMARY KEY ("id"), '
        'UNIQUE ("workspace_id", "id"), '
        'UNIQUE ("credit_account_id", "currency"), '
        'FOREIGN KEY (workspace_id, credit_account_id) REFERENCES credit_accounts (workspace_id, id), '
        'CHECK (currency IN (\'CNY\', \'USD\', \'EUR\', \'HKD\', \'GBP\', \'MOP\', \'TWD\', \'JPY\', \'KRW\', \'VND\', \'KWD\', \'BHD\', \'JOD\')), '
        'CHECK (row_version >= 1)'
        ') STRICT',
    // cards
    'CREATE TABLE IF NOT EXISTS "cards" ('
        '"id" TEXT NOT NULL, '
        '"workspace_id" TEXT NOT NULL, '
        '"credit_account_id" TEXT NOT NULL, '
        '"last4" TEXT NOT NULL, '
        '"network" TEXT NULL, '
        '"holder_kind" TEXT NOT NULL, '
        '"primary_card_id" TEXT NULL, '
        '"status" TEXT NOT NULL, '
        '"expires_ym" TEXT NULL, '
        '"replaced_by_card_id" TEXT NULL, '
        '"alias" TEXT NULL, '
        '"effective_from" TEXT NULL, '
        '"closed_on" TEXT NULL, '
        '"row_version" INTEGER NOT NULL DEFAULT 1, '
        '"created_at" TEXT NOT NULL, '
        '"updated_at" TEXT NOT NULL, '
        'PRIMARY KEY ("id"), '
        'UNIQUE ("workspace_id", "id"), '
        'UNIQUE ("workspace_id", "credit_account_id", "id"), '
        'FOREIGN KEY (workspace_id, credit_account_id) REFERENCES credit_accounts (workspace_id, id), '
        'FOREIGN KEY (workspace_id, credit_account_id, primary_card_id) REFERENCES cards (workspace_id, credit_account_id, id), '
        'FOREIGN KEY (workspace_id, credit_account_id, replaced_by_card_id) REFERENCES cards (workspace_id, credit_account_id, id), '
        'CHECK (length(last4) = 4 AND last4 NOT GLOB \'*[^0-9]*\'), '
        'CHECK (network IS NULL OR network IN (\'unionpay\', \'visa\', \'mastercard\', \'amex\', \'jcb\', \'discover\', \'other\')), '
        'CHECK (holder_kind IN (\'primary\', \'supplementary\')), '
        'CHECK ((holder_kind = \'primary\' AND primary_card_id IS NULL) OR (holder_kind = \'supplementary\' AND primary_card_id IS NOT NULL AND primary_card_id <> id)), '
        'CHECK (status IN (\'draft\', \'active\', \'frozen\', \'replaced\', \'closed\')), '
        'CHECK ((status = \'replaced\') = (replaced_by_card_id IS NOT NULL)), '
        'CHECK (replaced_by_card_id IS NULL OR replaced_by_card_id <> id), '
        'CHECK ((status = \'closed\') = (closed_on IS NOT NULL)), '
        'CHECK (expires_ym IS NULL OR (expires_ym GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]\' AND substr(expires_ym, 6, 2) BETWEEN \'01\' AND \'12\')), '
        'CHECK (alias IS NULL OR length(alias) BETWEEN 1 AND 20), '
        'CHECK (alias NOT GLOB \'*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*\'), '
        'CHECK (effective_from IS NULL OR effective_from GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]\'), '
        'CHECK (closed_on IS NULL OR closed_on GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]\'), '
        'CHECK (row_version >= 1)'
        ') STRICT',
    // billing_rule_versions
    'CREATE TABLE IF NOT EXISTS "billing_rule_versions" ('
        '"id" TEXT NOT NULL, '
        '"workspace_id" TEXT NOT NULL, '
        '"subject_kind" TEXT NOT NULL, '
        '"subject_id" TEXT NOT NULL, '
        '"statement_day" INTEGER NOT NULL, '
        '"statement_day_inclusive" INTEGER NOT NULL DEFAULT 1 CHECK ("statement_day_inclusive" IN (0, 1)), '
        '"due_kind" TEXT NOT NULL, '
        '"due_day" INTEGER NULL, '
        '"due_month_offset" INTEGER NOT NULL DEFAULT 0, '
        '"due_days" INTEGER NULL, '
        '"due_day_kind" TEXT NOT NULL DEFAULT \'calendar\', '
        '"holiday_rollover" TEXT NOT NULL DEFAULT \'none\', '
        '"cutoff_time" TEXT NULL, '
        '"posting_delay_min_days" INTEGER NOT NULL DEFAULT 0, '
        '"posting_delay_max_days" INTEGER NOT NULL DEFAULT 0, '
        '"source" TEXT NOT NULL, '
        '"effective_from" TEXT NULL, '
        '"effective_to" TEXT NULL, '
        '"verified_on" TEXT NULL, '
        '"version" INTEGER NOT NULL, '
        '"review_status" TEXT NOT NULL, '
        '"exceptions" TEXT NULL, '
        '"created_at" TEXT NOT NULL, '
        'PRIMARY KEY ("id"), '
        'UNIQUE ("workspace_id", "id"), '
        'UNIQUE ("workspace_id", "subject_kind", "subject_id", "version"), '
        'FOREIGN KEY (workspace_id) REFERENCES workspaces (id), '
        'CHECK (subject_kind IN (\'credit_account\', \'currency_account\')), '
        'CHECK (statement_day BETWEEN 1 AND 31), '
        'CHECK (due_kind IN (\'fixed_day\', \'days_after_statement\')), '
        'CHECK (due_day IS NULL OR due_day BETWEEN 1 AND 31), '
        'CHECK (due_month_offset IN (0, 1, 2)), '
        'CHECK (due_days IS NULL OR due_days BETWEEN 1 AND 60), '
        'CHECK ((due_kind = \'fixed_day\' AND due_day IS NOT NULL AND due_days IS NULL) OR (due_kind = \'days_after_statement\' AND due_days IS NOT NULL AND due_day IS NULL)), '
        'CHECK (due_day_kind IN (\'calendar\', \'business\')), '
        'CHECK (holiday_rollover IN (\'none\', \'next_business_day\')), '
        'CHECK (cutoff_time IS NULL OR (cutoff_time GLOB \'[0-2][0-9]:[0-5][0-9]\' AND cutoff_time <= \'23:59\')), '
        'CHECK (posting_delay_min_days BETWEEN 0 AND 366 AND posting_delay_max_days BETWEEN posting_delay_min_days AND 366), '
        'CHECK (source IN (\'user_declared\', \'official_template\')), '
        'CHECK (effective_from IS NULL OR effective_from GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]\'), '
        'CHECK (effective_to IS NULL OR effective_to GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]\'), '
        'CHECK (effective_to IS NULL OR effective_from IS NULL OR effective_to >= effective_from), '
        'CHECK (verified_on IS NULL OR verified_on GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]\'), '
        'CHECK (version >= 1), '
        'CHECK (review_status IN (\'draft\', \'in_review\', \'user_declared\', \'expired\')), '
        'CHECK (exceptions IS NULL OR length(exceptions) BETWEEN 1 AND 200), '
        'CHECK (exceptions NOT GLOB \'*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*\')'
        ') STRICT',
    // limit_snapshots
    'CREATE TABLE IF NOT EXISTS "limit_snapshots" ('
        '"id" TEXT NOT NULL, '
        '"workspace_id" TEXT NOT NULL, '
        '"currency_account_id" TEXT NOT NULL, '
        '"fixed_minor" INTEGER NOT NULL, '
        '"temp_minor" INTEGER NOT NULL DEFAULT 0, '
        '"temp_expires_on" TEXT NULL, '
        '"special_minor" INTEGER NOT NULL DEFAULT 0, '
        '"special_purpose" TEXT NULL, '
        '"used_minor" INTEGER NOT NULL, '
        '"available_raw_minor" INTEGER NOT NULL, '
        '"holds_minor" INTEGER NOT NULL DEFAULT 0, '
        '"includes_holds" INTEGER NOT NULL CHECK ("includes_holds" IN (0, 1)), '
        '"source_kind" TEXT NOT NULL, '
        '"source_document_id" TEXT NULL, '
        '"balance_as_of" TEXT NOT NULL, '
        '"observed_at" TEXT NOT NULL, '
        '"recorded_at" TEXT NOT NULL, '
        '"confirmation_level" TEXT NOT NULL, '
        'PRIMARY KEY ("id"), '
        'UNIQUE ("workspace_id", "id"), '
        'FOREIGN KEY (workspace_id, currency_account_id) REFERENCES currency_accounts (workspace_id, id), '
        'CHECK (fixed_minor BETWEEN 0 AND 10000000000000), '
        'CHECK (temp_minor BETWEEN 0 AND 10000000000000), '
        'CHECK (temp_minor = 0 OR temp_expires_on IS NOT NULL), '
        'CHECK (temp_expires_on IS NULL OR temp_expires_on GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]\'), '
        'CHECK (special_minor BETWEEN 0 AND 10000000000000), '
        'CHECK (special_minor = 0 OR special_purpose IS NOT NULL), '
        'CHECK (special_purpose IS NULL OR length(special_purpose) BETWEEN 1 AND 20), '
        'CHECK (special_purpose NOT GLOB \'*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*\'), '
        'CHECK (used_minor BETWEEN 0 AND 10000000000000), '
        'CHECK (available_raw_minor BETWEEN -10000000000000 AND 10000000000000), '
        'CHECK (holds_minor BETWEEN 0 AND 10000000000000), '
        'CHECK (source_kind IN (\'bank_app\', \'statement\', \'user\', \'import\')), '
        'CHECK (balance_as_of GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*\'), '
        'CHECK (observed_at GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*\'), '
        'CHECK (recorded_at GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*\'), '
        'CHECK (confirmation_level IN (\'system_estimated\', \'user_confirmed\', \'bank_confirmed\'))'
        ') STRICT',
  ];

  /// v2 的索引（外键子表列、部分唯一索引）。
  static const List<String> indexes = <String>[
    // 同一种工作空间（真实/演示）最多一个未删除的。
    'CREATE UNIQUE INDEX IF NOT EXISTS workspaces_one_live_per_kind '
        'ON workspaces (kind) WHERE deleted_at IS NULL',
    'CREATE INDEX IF NOT EXISTS credit_pools_bank '
        'ON credit_pools (workspace_id, bank_id)',
    'CREATE INDEX IF NOT EXISTS credit_pools_parent '
        'ON credit_pools (workspace_id, parent_pool_id)',
    'CREATE INDEX IF NOT EXISTS credit_accounts_bank '
        'ON credit_accounts (workspace_id, bank_id)',
    'CREATE INDEX IF NOT EXISTS credit_accounts_pool '
        'ON credit_accounts (workspace_id, pool_id)',
    // 每个信用账户恰好一个主子账户（"恰好"的另一半由仓库保证：建账户时同时建主子账户）。
    'CREATE UNIQUE INDEX IF NOT EXISTS currency_accounts_one_primary '
        'ON currency_accounts (credit_account_id) WHERE is_primary = 1',
    'CREATE INDEX IF NOT EXISTS currency_accounts_account '
        'ON currency_accounts (workspace_id, credit_account_id)',
    'CREATE INDEX IF NOT EXISTS cards_primary_card '
        'ON cards (workspace_id, credit_account_id, primary_card_id)',
    'CREATE INDEX IF NOT EXISTS cards_replaced_by '
        'ON cards (workspace_id, credit_account_id, replaced_by_card_id)',
    'CREATE INDEX IF NOT EXISTS limit_snapshots_account '
        'ON limit_snapshots (workspace_id, currency_account_id, balance_as_of DESC)',
  ];

  /// v2 的触发器：仓库层规则的数据库兜底（错误消息只有表名与规则，不含任何数据）。
  static const List<String> triggers = <String>[
    // 所有业务表的 workspace_id 不可改（R2-11），归属关系列不可改（R2-04）。
    '''
CREATE TRIGGER IF NOT EXISTS banks_immutable
BEFORE UPDATE OF workspace_id ON banks
WHEN NEW.workspace_id IS NOT OLD.workspace_id
BEGIN SELECT RAISE(ABORT, 'banks: immutable column'); END''',
    '''
CREATE TRIGGER IF NOT EXISTS credit_pools_immutable
BEFORE UPDATE OF workspace_id, bank_id, currency ON credit_pools
WHEN NEW.workspace_id IS NOT OLD.workspace_id
  OR NEW.bank_id IS NOT OLD.bank_id
  OR NEW.currency IS NOT OLD.currency
BEGIN SELECT RAISE(ABORT, 'credit_pools: immutable column'); END''',
    '''
CREATE TRIGGER IF NOT EXISTS credit_accounts_immutable
BEFORE UPDATE OF workspace_id, bank_id ON credit_accounts
WHEN NEW.workspace_id IS NOT OLD.workspace_id
  OR NEW.bank_id IS NOT OLD.bank_id
BEGIN SELECT RAISE(ABORT, 'credit_accounts: immutable column'); END''',
    '''
CREATE TRIGGER IF NOT EXISTS currency_accounts_immutable
BEFORE UPDATE OF workspace_id, credit_account_id, currency ON currency_accounts
WHEN NEW.workspace_id IS NOT OLD.workspace_id
  OR NEW.credit_account_id IS NOT OLD.credit_account_id
  OR NEW.currency IS NOT OLD.currency
BEGIN SELECT RAISE(ABORT, 'currency_accounts: immutable column'); END''',
    // 卡片不在账户之间移动；换卡/补卡是新卡（F-24：历史不变）。
    '''
CREATE TRIGGER IF NOT EXISTS cards_immutable
BEFORE UPDATE OF workspace_id, credit_account_id, last4, holder_kind, primary_card_id ON cards
WHEN NEW.workspace_id IS NOT OLD.workspace_id
  OR NEW.credit_account_id IS NOT OLD.credit_account_id
  OR NEW.last4 IS NOT OLD.last4
  OR NEW.holder_kind IS NOT OLD.holder_kind
  OR NEW.primary_card_id IS NOT OLD.primary_card_id
BEGIN SELECT RAISE(ABORT, 'cards: immutable column'); END''',
    // 卡片状态机（PRD §6.1）。
    '''
CREATE TRIGGER IF NOT EXISTS cards_status_transition
BEFORE UPDATE OF status ON cards
WHEN NEW.status IS NOT OLD.status AND NOT (
  (OLD.status = 'draft' AND NEW.status = 'active')
  OR (OLD.status = 'active' AND NEW.status IN ('frozen', 'replaced', 'closed'))
  OR (OLD.status = 'frozen' AND NEW.status IN ('active', 'closed'))
)
BEGIN SELECT RAISE(ABORT, 'cards: status transition not allowed'); END''',
    // 规则主体必须是同一工作空间里的信用账户或币种子账户（规则表没有外键能表达多态主体）。
    '''
CREATE TRIGGER IF NOT EXISTS billing_rule_versions_subject
BEFORE INSERT ON billing_rule_versions
WHEN NOT EXISTS (
  SELECT 1 FROM credit_accounts AS a
  WHERE NEW.subject_kind = 'credit_account'
    AND a.workspace_id = NEW.workspace_id AND a.id = NEW.subject_id
) AND NOT EXISTS (
  SELECT 1 FROM currency_accounts AS c
  WHERE NEW.subject_kind = 'currency_account'
    AND c.workspace_id = NEW.workspace_id AND c.id = NEW.subject_id
)
BEGIN SELECT RAISE(ABORT, 'billing_rule_versions: subject not in workspace'); END''',
    // 规则版本只能"封口"：effective_to 只能变早（或由空变为有值），状态只能变为 expired；其余列不可改。
    '''
CREATE TRIGGER IF NOT EXISTS billing_rule_versions_immutable
BEFORE UPDATE ON billing_rule_versions
WHEN NEW.id IS NOT OLD.id
  OR NEW.workspace_id IS NOT OLD.workspace_id
  OR NEW.subject_kind IS NOT OLD.subject_kind
  OR NEW.subject_id IS NOT OLD.subject_id
  OR NEW.statement_day IS NOT OLD.statement_day
  OR NEW.statement_day_inclusive IS NOT OLD.statement_day_inclusive
  OR NEW.due_kind IS NOT OLD.due_kind
  OR NEW.due_day IS NOT OLD.due_day
  OR NEW.due_month_offset IS NOT OLD.due_month_offset
  OR NEW.due_days IS NOT OLD.due_days
  OR NEW.due_day_kind IS NOT OLD.due_day_kind
  OR NEW.holiday_rollover IS NOT OLD.holiday_rollover
  OR NEW.cutoff_time IS NOT OLD.cutoff_time
  OR NEW.posting_delay_min_days IS NOT OLD.posting_delay_min_days
  OR NEW.posting_delay_max_days IS NOT OLD.posting_delay_max_days
  OR NEW.source IS NOT OLD.source
  OR NEW.effective_from IS NOT OLD.effective_from
  OR NEW.verified_on IS NOT OLD.verified_on
  OR NEW.version IS NOT OLD.version
  OR NEW.exceptions IS NOT OLD.exceptions
  OR NEW.created_at IS NOT OLD.created_at
  OR (NEW.review_status IS NOT OLD.review_status AND NEW.review_status <> 'expired')
  OR (NEW.effective_to IS NOT OLD.effective_to AND NOT (
    NEW.effective_to IS NOT NULL
    AND (OLD.effective_to IS NULL OR NEW.effective_to <= OLD.effective_to)
  ))
BEGIN SELECT RAISE(ABORT, 'billing_rule_versions: only sealing is allowed'); END''',
    // 同一主体的生效区间 [effective_from, effective_to) 不得重叠（服务端用 EXCLUDE 约束，
    // SQLite 没有）。空区间（被更正取代的版本）不参与。只需检查插入：已有版本只能封口（变短）。
    '''
CREATE TRIGGER IF NOT EXISTS billing_rule_versions_no_overlap
BEFORE INSERT ON billing_rule_versions
WHEN NOT (
  NEW.effective_to IS NOT NULL
  AND NEW.effective_to <= COALESCE(NEW.effective_from, '0001-01-01')
) AND EXISTS (
  SELECT 1 FROM billing_rule_versions AS o
  WHERE o.workspace_id = NEW.workspace_id
    AND o.subject_kind = NEW.subject_kind
    AND o.subject_id = NEW.subject_id
    AND NOT (
      o.effective_to IS NOT NULL
      AND o.effective_to <= COALESCE(o.effective_from, '0001-01-01')
    )
    AND (o.effective_to IS NULL OR NEW.effective_from IS NULL OR NEW.effective_from < o.effective_to)
    AND (NEW.effective_to IS NULL OR o.effective_from IS NULL OR o.effective_from < NEW.effective_to)
)
BEGIN SELECT RAISE(ABORT, 'billing_rule_versions: effective ranges overlap'); END''',
    // 额度快照只追加，不修改（data-model §10.3）。
    '''
CREATE TRIGGER IF NOT EXISTS limit_snapshots_immutable
BEFORE UPDATE ON limit_snapshots
BEGIN SELECT RAISE(ABORT, 'limit_snapshots: append only'); END''',
  ];

  /// v1 → v2 的全部语句（顺序：表、索引、触发器）。
  static const List<String> migration = <String>[
    ...tables,
    ...indexes,
    ...triggers,
  ];
}

/// v3（I-1b）：现金账户、余额快照与已包含事件、现金事件、周期事项与单期覆盖、情景与情景计算版本。
/// 表定义见 `tables.dart`；这里是冻结的 SQL（v2 → v3 的迁移步骤使用；只做 expand：只加表、索引与
/// 触发器，不动 v2 的任何表与数据）。
abstract final class SchemaV3 {
  /// v3 新增的表（与 drift 由 `tables.dart` 生成的建表语句一字不差，只多了 `IF NOT EXISTS`）。
  static const List<String> tables = <String>[
    // cash_accounts
    'CREATE TABLE IF NOT EXISTS "cash_accounts" ('
        '"id" TEXT NOT NULL, '
        '"workspace_id" TEXT NOT NULL, '
        '"name" TEXT NOT NULL, '
        '"currency" TEXT NOT NULL, '
        '"kind" TEXT NOT NULL, '
        '"usable_for_repayment" INTEGER NOT NULL DEFAULT 1 CHECK ("usable_for_repayment" IN (0, 1)), '
        '"available_from" TEXT NULL, '
        '"reserve_floor_minor" INTEGER NOT NULL DEFAULT 0, '
        '"status" TEXT NOT NULL DEFAULT \'active\', '
        '"row_version" INTEGER NOT NULL DEFAULT 1, '
        '"created_at" TEXT NOT NULL, '
        '"updated_at" TEXT NOT NULL, '
        '"deleted_at" TEXT NULL, '
        'PRIMARY KEY ("id"), '
        'UNIQUE ("workspace_id", "id"), '
        'FOREIGN KEY (workspace_id) REFERENCES workspaces (id), '
        'CHECK (length(name) BETWEEN 1 AND 20), '
        'CHECK (name NOT GLOB \'*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*\'), '
        'CHECK (currency IN (\'CNY\', \'USD\', \'EUR\', \'HKD\', \'GBP\', \'MOP\', \'TWD\', \'JPY\', \'KRW\', \'VND\', \'KWD\', \'BHD\', \'JOD\')), '
        'CHECK (kind IN (\'bank\', \'wallet\', \'wealth\', \'restricted\')), '
        'CHECK (kind <> \'restricted\' OR usable_for_repayment = 0), '
        'CHECK (available_from IS NULL OR available_from GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]\'), '
        'CHECK (reserve_floor_minor BETWEEN 0 AND 10000000000000), '
        'CHECK (status IN (\'active\', \'closed\')), '
        'CHECK (row_version >= 1)'
        ') STRICT',
    // cash_balance_snapshots
    'CREATE TABLE IF NOT EXISTS "cash_balance_snapshots" ('
        '"id" TEXT NOT NULL, '
        '"workspace_id" TEXT NOT NULL, '
        '"cash_account_id" TEXT NOT NULL, '
        '"balance_minor" INTEGER NOT NULL, '
        '"balance_as_of" TEXT NOT NULL, '
        '"observed_at" TEXT NOT NULL, '
        '"source_kind" TEXT NOT NULL, '
        '"confirmation_level" TEXT NOT NULL, '
        '"recorded_at" TEXT NOT NULL, '
        'PRIMARY KEY ("id"), '
        'UNIQUE ("workspace_id", "id"), '
        'UNIQUE ("workspace_id", "cash_account_id", "id"), '
        'FOREIGN KEY (workspace_id, cash_account_id) REFERENCES cash_accounts (workspace_id, id), '
        'CHECK (balance_minor BETWEEN -10000000000000 AND 10000000000000), '
        'CHECK (balance_as_of GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]\'), '
        'CHECK (observed_at GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*\'), '
        'CHECK (recorded_at GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*\'), '
        'CHECK (source_kind IN (\'bank_app\', \'statement\', \'user\', \'import\')), '
        'CHECK (confirmation_level IN (\'system_estimated\', \'user_confirmed\', \'bank_confirmed\'))'
        ') STRICT',
    // snapshot_included_events
    'CREATE TABLE IF NOT EXISTS "snapshot_included_events" ('
        '"workspace_id" TEXT NOT NULL, '
        '"cash_account_id" TEXT NOT NULL, '
        '"snapshot_id" TEXT NOT NULL, '
        '"cash_event_id" TEXT NOT NULL, '
        'PRIMARY KEY ("snapshot_id", "cash_event_id"), '
        'FOREIGN KEY (workspace_id, cash_account_id, snapshot_id) REFERENCES cash_balance_snapshots (workspace_id, cash_account_id, id), '
        'FOREIGN KEY (workspace_id, cash_account_id, cash_event_id) REFERENCES cash_events (workspace_id, cash_account_id, id)'
        ') STRICT',
    // cash_events
    'CREATE TABLE IF NOT EXISTS "cash_events" ('
        '"id" TEXT NOT NULL, '
        '"workspace_id" TEXT NOT NULL, '
        '"cash_account_id" TEXT NOT NULL, '
        '"event_on" TEXT NOT NULL, '
        '"event_at" TEXT NULL, '
        '"amount_minor" INTEGER NOT NULL, '
        '"cls" TEXT NOT NULL, '
        '"category" TEXT NOT NULL, '
        '"label" TEXT NULL, '
        '"posting_status" TEXT NOT NULL DEFAULT \'planned\', '
        '"recurring_item_id" TEXT NULL, '
        '"occurrence_key" TEXT NULL, '
        '"transfer_group_id" TEXT NULL, '
        '"linked_repayment_id" TEXT NULL, '
        '"linked_plan_run_id" TEXT NULL, '
        '"row_version" INTEGER NOT NULL DEFAULT 1, '
        '"created_at" TEXT NOT NULL, '
        '"updated_at" TEXT NOT NULL, '
        '"deleted_at" TEXT NULL, '
        'PRIMARY KEY ("id"), '
        'UNIQUE ("workspace_id", "id"), '
        'UNIQUE ("workspace_id", "cash_account_id", "id"), '
        'FOREIGN KEY (workspace_id, cash_account_id) REFERENCES cash_accounts (workspace_id, id), '
        'FOREIGN KEY (workspace_id, cash_account_id, recurring_item_id) REFERENCES recurring_items (workspace_id, cash_account_id, id), '
        'CHECK (event_on GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]\'), '
        'CHECK (event_at IS NULL OR (event_at GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*\' AND substr(event_at, 1, 10) = event_on)), '
        'CHECK (amount_minor <> 0 AND amount_minor BETWEEN -10000000000000 AND 10000000000000), '
        'CHECK (cls IN (\'confirmed\', \'expected\', \'planned\')), '
        'CHECK (category IN (\'income\', \'bill\', \'living\', \'repayment\', \'transfer_in\', \'transfer_out\', \'fee\', \'other\')), '
        'CHECK ((category IN (\'income\', \'transfer_in\') AND amount_minor > 0) OR (category IN (\'bill\', \'living\', \'repayment\', \'transfer_out\', \'fee\') AND amount_minor < 0) OR category = \'other\'), '
        'CHECK (label IS NULL OR length(label) BETWEEN 1 AND 20), '
        'CHECK (label NOT GLOB \'*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*\'), '
        'CHECK (posting_status IN (\'planned\', \'posted\')), '
        'CHECK (posting_status = \'planned\' OR cls = \'confirmed\'), '
        'CHECK ((recurring_item_id IS NULL) = (occurrence_key IS NULL)), '
        'CHECK (occurrence_key IS NULL OR occurrence_key GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]\'), '
        'CHECK ((transfer_group_id IS NOT NULL) = (category IN (\'transfer_in\', \'transfer_out\'))), '
        'CHECK (transfer_group_id IS NULL OR recurring_item_id IS NULL), '
        'CHECK (row_version >= 1)'
        ') STRICT',
    // recurring_items
    'CREATE TABLE IF NOT EXISTS "recurring_items" ('
        '"id" TEXT NOT NULL, '
        '"workspace_id" TEXT NOT NULL, '
        '"cash_account_id" TEXT NOT NULL, '
        '"label" TEXT NOT NULL, '
        '"amount_minor" INTEGER NOT NULL, '
        '"cls" TEXT NOT NULL, '
        '"category" TEXT NOT NULL, '
        '"frequency" TEXT NOT NULL, '
        '"anchor_on" TEXT NOT NULL, '
        '"day_rule" TEXT NOT NULL DEFAULT \'anchor_day\', '
        '"start_on" TEXT NOT NULL, '
        '"end_on" TEXT NULL, '
        '"active" INTEGER NOT NULL DEFAULT 1 CHECK ("active" IN (0, 1)), '
        '"row_version" INTEGER NOT NULL DEFAULT 1, '
        '"created_at" TEXT NOT NULL, '
        '"updated_at" TEXT NOT NULL, '
        'PRIMARY KEY ("id"), '
        'UNIQUE ("workspace_id", "id"), '
        'UNIQUE ("workspace_id", "cash_account_id", "id"), '
        'FOREIGN KEY (workspace_id, cash_account_id) REFERENCES cash_accounts (workspace_id, id), '
        'CHECK (length(label) BETWEEN 1 AND 20), '
        'CHECK (label NOT GLOB \'*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*\'), '
        'CHECK (amount_minor <> 0 AND amount_minor BETWEEN -10000000000000 AND 10000000000000), '
        'CHECK (cls IN (\'confirmed\', \'expected\', \'planned\')), '
        'CHECK (category IN (\'income\', \'bill\', \'living\', \'repayment\', \'fee\', \'other\')), '
        'CHECK ((category = \'income\' AND amount_minor > 0) OR (category IN (\'bill\', \'living\', \'repayment\', \'fee\') AND amount_minor < 0) OR category = \'other\'), '
        'CHECK (frequency IN (\'monthly\', \'weekly\', \'biweekly\', \'yearly\')), '
        'CHECK (day_rule IN (\'anchor_day\', \'month_end\')), '
        'CHECK (day_rule = \'anchor_day\' OR frequency IN (\'monthly\', \'yearly\')), '
        'CHECK (anchor_on GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]\'), '
        'CHECK (start_on GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]\'), '
        'CHECK (end_on IS NULL OR end_on GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]\'), '
        'CHECK (start_on >= anchor_on), '
        'CHECK (end_on IS NULL OR end_on >= start_on), '
        'CHECK (row_version >= 1)'
        ') STRICT',
    // recurring_overrides
    'CREATE TABLE IF NOT EXISTS "recurring_overrides" ('
        '"workspace_id" TEXT NOT NULL, '
        '"recurring_item_id" TEXT NOT NULL, '
        '"occurrence_key" TEXT NOT NULL, '
        '"action" TEXT NOT NULL, '
        '"amount_minor" INTEGER NULL, '
        '"event_on" TEXT NULL, '
        '"event_at" TEXT NULL, '
        '"created_at" TEXT NOT NULL, '
        '"updated_at" TEXT NOT NULL, '
        'PRIMARY KEY ("recurring_item_id", "occurrence_key"), '
        'FOREIGN KEY (workspace_id, recurring_item_id) REFERENCES recurring_items (workspace_id, id), '
        'CHECK (occurrence_key GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]\'), '
        'CHECK (action IN (\'skip\', \'override\')), '
        'CHECK ((action = \'skip\' AND amount_minor IS NULL AND event_on IS NULL AND event_at IS NULL) OR (action = \'override\' AND (amount_minor IS NOT NULL OR event_on IS NOT NULL))), '
        'CHECK (amount_minor IS NULL OR (amount_minor <> 0 AND amount_minor BETWEEN -10000000000000 AND 10000000000000)), '
        'CHECK (event_on IS NULL OR event_on GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]\'), '
        'CHECK (event_at IS NULL OR (event_on IS NOT NULL AND event_at GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*\' AND substr(event_at, 1, 10) = event_on))'
        ') STRICT',
    // scenarios
    'CREATE TABLE IF NOT EXISTS "scenarios" ('
        '"id" TEXT NOT NULL, '
        '"workspace_id" TEXT NOT NULL, '
        '"name" TEXT NOT NULL, '
        '"kind" TEXT NOT NULL, '
        '"include_expected" INTEGER NOT NULL CHECK ("include_expected" IN (0, 1)), '
        '"income_delay_days" INTEGER NOT NULL DEFAULT 0, '
        '"income_scale" TEXT NOT NULL DEFAULT \'1\', '
        '"expense_scale" TEXT NOT NULL DEFAULT \'1\', '
        '"same_day_order" TEXT NOT NULL DEFAULT \'conservative\', '
        '"limit_changes" TEXT NOT NULL DEFAULT \'[]\', '
        '"event_overrides" TEXT NOT NULL DEFAULT \'[]\', '
        '"row_version" INTEGER NOT NULL DEFAULT 1, '
        '"created_at" TEXT NOT NULL, '
        '"updated_at" TEXT NOT NULL, '
        'PRIMARY KEY ("id"), '
        'UNIQUE ("workspace_id", "id"), '
        'UNIQUE ("workspace_id", "name"), '
        'FOREIGN KEY (workspace_id) REFERENCES workspaces (id), '
        'CHECK (length(name) BETWEEN 1 AND 20), '
        'CHECK (name NOT GLOB \'*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*\'), '
        'CHECK (kind IN (\'builtin_confirmed\', \'builtin_baseline\', \'user_stress\')), '
        'CHECK (income_delay_days BETWEEN 0 AND 180), '
        'CHECK (length(income_scale) BETWEEN 1 AND 12 AND income_scale NOT GLOB \'*[^0-9.]*\'), '
        'CHECK (length(expense_scale) BETWEEN 1 AND 12 AND expense_scale NOT GLOB \'*[^0-9.]*\'), '
        'CHECK (same_day_order IN (\'conservative\', \'timestamp\')), '
        'CHECK (json_valid(limit_changes) AND json_type(limit_changes) = \'array\'), '
        'CHECK (json_valid(event_overrides) AND json_type(event_overrides) = \'array\'), '
        'CHECK (kind = \'user_stress\' OR (income_delay_days = 0 AND income_scale = \'1\' AND expense_scale = \'1\' AND same_day_order = \'conservative\' AND limit_changes = \'[]\' AND event_overrides = \'[]\')), '
        'CHECK ((kind = \'builtin_confirmed\') = (include_expected = 0)), '
        'CHECK (row_version >= 1)'
        ') STRICT',
    // scenario_runs
    'CREATE TABLE IF NOT EXISTS "scenario_runs" ('
        '"id" TEXT NOT NULL, '
        '"workspace_id" TEXT NOT NULL, '
        '"scenario_id" TEXT NOT NULL, '
        '"version_no" INTEGER NOT NULL, '
        '"computed_at" TEXT NOT NULL, '
        '"horizon_from" TEXT NOT NULL, '
        '"horizon_to" TEXT NOT NULL, '
        '"inputs_hash" TEXT NOT NULL, '
        '"result" TEXT NOT NULL, '
        'PRIMARY KEY ("id"), '
        'UNIQUE ("workspace_id", "id"), '
        'UNIQUE ("scenario_id", "version_no"), '
        'FOREIGN KEY (workspace_id, scenario_id) REFERENCES scenarios (workspace_id, id), '
        'CHECK (version_no >= 1), '
        'CHECK (computed_at GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*\'), '
        'CHECK (horizon_from GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]\'), '
        'CHECK (horizon_to GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]\'), '
        'CHECK (horizon_to >= horizon_from), '
        'CHECK (length(inputs_hash) = 64 AND inputs_hash NOT GLOB \'*[^0-9a-f]*\'), '
        'CHECK (json_valid(result) AND json_type(result) = \'object\')'
        ') STRICT',
  ];

  /// v3 的索引（外键子表列、部分唯一索引）。
  static const List<String> indexes = <String>[
    // 同一工作空间里未删除的现金账户不重名（P-08 的选择、"余额是否已包含"的提问都按名称）。
    'CREATE UNIQUE INDEX IF NOT EXISTS cash_accounts_live_name '
        'ON cash_accounts (workspace_id, name) WHERE deleted_at IS NULL',
    'CREATE INDEX IF NOT EXISTS cash_balance_snapshots_account '
        'ON cash_balance_snapshots (workspace_id, cash_account_id, balance_as_of DESC)',
    'CREATE INDEX IF NOT EXISTS snapshot_included_events_snapshot '
        'ON snapshot_included_events (workspace_id, cash_account_id, snapshot_id)',
    'CREATE INDEX IF NOT EXISTS snapshot_included_events_event '
        'ON snapshot_included_events (workspace_id, cash_account_id, cash_event_id)',
    // data-model §5：按账户与日期的范围查询。
    'CREATE INDEX IF NOT EXISTS cash_events_account_on '
        'ON cash_events (workspace_id, cash_account_id, event_on) WHERE deleted_at IS NULL',
    'CREATE INDEX IF NOT EXISTS cash_events_recurring '
        'ON cash_events (workspace_id, cash_account_id, recurring_item_id)',
    // 周期事项每一期最多一条未删除的事件（展开幂等：重复展开被忽略）。
    'CREATE UNIQUE INDEX IF NOT EXISTS cash_events_occurrence '
        'ON cash_events (recurring_item_id, occurrence_key) '
        'WHERE recurring_item_id IS NOT NULL AND deleted_at IS NULL',
    'CREATE INDEX IF NOT EXISTS cash_events_transfer '
        'ON cash_events (workspace_id, transfer_group_id) WHERE transfer_group_id IS NOT NULL',
    // 一笔还款（I-1c）最多对应一条未删除的现金事件。
    'CREATE UNIQUE INDEX IF NOT EXISTS cash_events_linked_repayment '
        'ON cash_events (workspace_id, linked_repayment_id) '
        'WHERE linked_repayment_id IS NOT NULL AND deleted_at IS NULL',
    'CREATE INDEX IF NOT EXISTS recurring_items_account '
        'ON recurring_items (workspace_id, cash_account_id)',
    'CREATE INDEX IF NOT EXISTS recurring_overrides_item '
        'ON recurring_overrides (workspace_id, recurring_item_id)',
    // 每个工作空间的两条内置情景各最多一条。
    'CREATE UNIQUE INDEX IF NOT EXISTS scenarios_one_builtin '
        "ON scenarios (workspace_id, kind) WHERE kind <> 'user_stress'",
    'CREATE INDEX IF NOT EXISTS scenario_runs_scenario '
        'ON scenario_runs (workspace_id, scenario_id, version_no)',
  ];

  /// v3 的触发器：仓库层规则的数据库兜底（错误消息只有表名与规则，不含任何数据）。
  static const List<String> triggers = <String>[
    // 工作空间与币种不可改（R2-04、R2-11）。
    '''
CREATE TRIGGER IF NOT EXISTS cash_accounts_immutable
BEFORE UPDATE OF workspace_id, currency ON cash_accounts
WHEN NEW.workspace_id IS NOT OLD.workspace_id
  OR NEW.currency IS NOT OLD.currency
BEGIN SELECT RAISE(ABORT, 'cash_accounts: immutable column'); END''',
    // 余额快照只追加，不修改（data-model §10.3）。
    '''
CREATE TRIGGER IF NOT EXISTS cash_balance_snapshots_immutable
BEFORE UPDATE ON cash_balance_snapshots
BEGIN SELECT RAISE(ABORT, 'cash_balance_snapshots: append only'); END''',
    // 快照的包含关系与快照一起写入，之后不改。
    '''
CREATE TRIGGER IF NOT EXISTS snapshot_included_events_immutable
BEFORE UPDATE ON snapshot_included_events
BEGIN SELECT RAISE(ABORT, 'snapshot_included_events: append only'); END''',
    // 快照只能包含快照日当天及以前的事件（规则协议 v1 的交叉规则 R3E-14）。
    '''
CREATE TRIGGER IF NOT EXISTS snapshot_included_events_on_or_before
BEFORE INSERT ON snapshot_included_events
WHEN (
  SELECT e.event_on FROM cash_events AS e
  WHERE e.workspace_id = NEW.workspace_id AND e.id = NEW.cash_event_id
) > (
  SELECT s.balance_as_of FROM cash_balance_snapshots AS s
  WHERE s.workspace_id = NEW.workspace_id AND s.id = NEW.snapshot_id
)
BEGIN SELECT RAISE(ABORT, 'snapshot_included_events: event after snapshot day'); END''',
    // 现金事件：归属与来源列不可改；已发生的不能退回尚未发生；删除（tombstone）后不再改动；
    // 调拨两端的日期、时刻、金额与方向不可改（改调拨 = 删除两端后重建）。
    '''
CREATE TRIGGER IF NOT EXISTS cash_events_immutable
BEFORE UPDATE ON cash_events
WHEN NEW.id IS NOT OLD.id
  OR NEW.workspace_id IS NOT OLD.workspace_id
  OR NEW.cash_account_id IS NOT OLD.cash_account_id
  OR NEW.recurring_item_id IS NOT OLD.recurring_item_id
  OR NEW.occurrence_key IS NOT OLD.occurrence_key
  OR NEW.transfer_group_id IS NOT OLD.transfer_group_id
  OR NEW.created_at IS NOT OLD.created_at
  OR OLD.deleted_at IS NOT NULL
  OR (OLD.posting_status = 'posted' AND NEW.posting_status <> 'posted')
  OR (OLD.transfer_group_id IS NOT NULL AND (
    NEW.event_on IS NOT OLD.event_on
    OR NEW.event_at IS NOT OLD.event_at
    OR NEW.amount_minor IS NOT OLD.amount_minor
    OR NEW.category IS NOT OLD.category
  ))
BEGIN SELECT RAISE(ABORT, 'cash_events: immutable column'); END''',
    // 调拨：一组最多两条；两端账户不同、币种相同、方向相反、金额相反、到账日不早于转出日。
    '''
CREATE TRIGGER IF NOT EXISTS cash_events_transfer_pair
BEFORE INSERT ON cash_events
WHEN NEW.transfer_group_id IS NOT NULL AND (
  (SELECT COUNT(*) FROM cash_events AS o
   WHERE o.workspace_id = NEW.workspace_id
     AND o.transfer_group_id = NEW.transfer_group_id) >= 2
  OR EXISTS (
    SELECT 1 FROM cash_events AS o
    JOIN cash_accounts AS oa
      ON oa.workspace_id = o.workspace_id AND oa.id = o.cash_account_id
    JOIN cash_accounts AS na
      ON na.workspace_id = NEW.workspace_id AND na.id = NEW.cash_account_id
    WHERE o.workspace_id = NEW.workspace_id
      AND o.transfer_group_id = NEW.transfer_group_id
      AND (o.cash_account_id = NEW.cash_account_id
        OR o.category = NEW.category
        OR o.amount_minor <> -NEW.amount_minor
        OR oa.currency <> na.currency
        OR (NEW.category = 'transfer_in' AND NEW.event_on < o.event_on)
        OR (NEW.category = 'transfer_out' AND NEW.event_on > o.event_on))
  )
)
BEGIN SELECT RAISE(ABORT, 'cash_events: invalid transfer pair'); END''',
    '''
CREATE TRIGGER IF NOT EXISTS recurring_items_immutable
BEFORE UPDATE OF workspace_id, cash_account_id ON recurring_items
WHEN NEW.workspace_id IS NOT OLD.workspace_id
  OR NEW.cash_account_id IS NOT OLD.cash_account_id
BEGIN SELECT RAISE(ABORT, 'recurring_items: immutable column'); END''',
    // 内置情景只读；情景的种类与工作空间不可改。
    '''
CREATE TRIGGER IF NOT EXISTS scenarios_builtin_readonly
BEFORE UPDATE ON scenarios
WHEN OLD.kind <> 'user_stress'
  OR NEW.kind IS NOT OLD.kind
  OR NEW.workspace_id IS NOT OLD.workspace_id
BEGIN SELECT RAISE(ABORT, 'scenarios: built-in scenarios are read-only'); END''',
    // 情景计算版本只追加，不修改（旧版本保留用于对比）。
    '''
CREATE TRIGGER IF NOT EXISTS scenario_runs_immutable
BEFORE UPDATE ON scenario_runs
BEGIN SELECT RAISE(ABORT, 'scenario_runs: append only'); END''',
  ];

  /// v2 → v3 的全部语句（顺序：表、索引、触发器）。
  static const List<String> migration = <String>[
    ...tables,
    ...indexes,
    ...triggers,
  ];
}

/// v4（I-1c）：交易、账单与账单版本、分期计划与各期、还款与分配、差异项。表定义见 `tables.dart`；这里是
/// 冻结的 SQL（v3 → v4 的迁移步骤使用；只做 expand：只加表、索引与触发器，不动 v2/v3 的表与数据——
/// v3 的 `cash_events` 不重建，`linked_repayment_id` 的约束用触发器补上，简报 §6 第 2 条）。
abstract final class SchemaV4 {
  /// v4 新增的表（与 drift 由 `tables.dart` 生成的建表语句一字不差，只多了 `IF NOT EXISTS`）。
  static const List<String> tables = <String>[
    // transactions
    'CREATE TABLE IF NOT EXISTS "transactions" ('
        '"id" TEXT NOT NULL, '
        '"workspace_id" TEXT NOT NULL, '
        '"currency_account_id" TEXT NOT NULL, '
        '"card_id" TEXT NULL, '
        '"txn_type" TEXT NOT NULL, '
        '"amount_minor" INTEGER NOT NULL, '
        '"currency" TEXT NOT NULL, '
        '"txn_at" TEXT NOT NULL, '
        '"txn_tz" TEXT NOT NULL, '
        '"time_precision" TEXT NOT NULL, '
        '"posted_on" TEXT NULL, '
        '"merchant" TEXT NULL, '
        '"category" TEXT NULL, '
        '"status" TEXT NOT NULL, '
        '"parent_transaction_id" TEXT NULL, '
        '"fingerprint" TEXT NOT NULL, '
        '"source_kind" TEXT NOT NULL, '
        '"confirmation_level" TEXT NOT NULL, '
        '"row_version" INTEGER NOT NULL DEFAULT 1, '
        '"recorded_at" TEXT NOT NULL, '
        '"updated_at" TEXT NOT NULL, '
        '"deleted_at" TEXT NULL, '
        'PRIMARY KEY ("id"), '
        'UNIQUE ("workspace_id", "id"), '
        'UNIQUE ("workspace_id", "currency_account_id", "id"), '
        'FOREIGN KEY (workspace_id, currency_account_id, currency) REFERENCES currency_accounts (workspace_id, id, currency), '
        'FOREIGN KEY (workspace_id, card_id) REFERENCES cards (workspace_id, id), '
        'FOREIGN KEY (workspace_id, currency_account_id, parent_transaction_id) REFERENCES transactions (workspace_id, currency_account_id, id), '
        'CHECK (txn_type IN (\'purchase\', \'refund\', \'repayment\', \'transfer\', \'fee\', \'interest\', \'installment_principal\', \'installment_fee\', \'adjustment\')), '
        'CHECK (amount_minor <> 0 AND amount_minor BETWEEN -10000000000000 AND 10000000000000), '
        'CHECK ((txn_type IN (\'purchase\', \'fee\', \'interest\', \'installment_principal\', \'installment_fee\') AND amount_minor > 0) OR (txn_type IN (\'refund\', \'repayment\') AND amount_minor < 0) OR txn_type IN (\'transfer\', \'adjustment\')), '
        'CHECK (currency IN (\'CNY\', \'USD\', \'EUR\', \'HKD\', \'GBP\', \'MOP\', \'TWD\', \'JPY\', \'KRW\', \'VND\', \'KWD\', \'BHD\', \'JOD\')), '
        'CHECK (txn_at GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*\'), '
        'CHECK (length(txn_tz) BETWEEN 1 AND 64), '
        'CHECK (time_precision IN (\'datetime\', \'date\', \'month\')), '
        'CHECK (posted_on IS NULL OR posted_on GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]\'), '
        'CHECK (merchant IS NULL OR length(merchant) BETWEEN 1 AND 20), '
        'CHECK (merchant NOT GLOB \'*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*\'), '
        'CHECK (category IS NULL OR length(category) BETWEEN 1 AND 20), '
        'CHECK (category NOT GLOB \'*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*\'), '
        'CHECK (status IN (\'pending\', \'posted\', \'reversed\')), '
        'CHECK (parent_transaction_id IS NULL OR parent_transaction_id <> id), '
        'CHECK (length(fingerprint) = 64 AND fingerprint NOT GLOB \'*[^0-9a-f]*\'), '
        'CHECK (source_kind IN (\'manual\', \'import\')), '
        'CHECK (confirmation_level IN (\'system_estimated\', \'user_confirmed\', \'bank_confirmed\')), '
        'CHECK (recorded_at GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*\'), '
        'CHECK (updated_at GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*\'), '
        'CHECK (deleted_at IS NULL OR deleted_at GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*\'), '
        'CHECK (row_version >= 1)'
        ') STRICT',
    // statements
    'CREATE TABLE IF NOT EXISTS "statements" ('
        '"id" TEXT NOT NULL, '
        '"workspace_id" TEXT NOT NULL, '
        '"currency_account_id" TEXT NOT NULL, '
        '"statement_date" TEXT NOT NULL, '
        '"due_date" TEXT NOT NULL, '
        '"status" TEXT NOT NULL, '
        '"current_version_id" TEXT NULL, '
        '"row_version" INTEGER NOT NULL DEFAULT 1, '
        '"created_at" TEXT NOT NULL, '
        '"updated_at" TEXT NOT NULL, '
        'PRIMARY KEY ("id"), '
        'UNIQUE ("workspace_id", "id"), '
        'UNIQUE ("workspace_id", "currency_account_id", "id"), '
        'UNIQUE ("workspace_id", "currency_account_id", "statement_date"), '
        'FOREIGN KEY (workspace_id, currency_account_id) REFERENCES currency_accounts (workspace_id, id), '
        'FOREIGN KEY (workspace_id, id, current_version_id) REFERENCES statement_versions (workspace_id, statement_id, id) DEFERRABLE INITIALLY DEFERRED, '
        'CHECK (statement_date GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]\'), '
        'CHECK (due_date GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]\'), '
        'CHECK (due_date > statement_date), '
        'CHECK (status IN (\'predicted\', \'issued\', \'amended\', \'partially_settled\', \'settled\', \'overdue\')), '
        'CHECK (row_version >= 1), '
        'CHECK (created_at GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*\'), '
        'CHECK (updated_at GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*\')'
        ') STRICT',
    // statement_versions
    'CREATE TABLE IF NOT EXISTS "statement_versions" ('
        '"id" TEXT NOT NULL, '
        '"workspace_id" TEXT NOT NULL, '
        '"statement_id" TEXT NOT NULL, '
        '"version_no" INTEGER NOT NULL, '
        '"source_kind" TEXT NOT NULL, '
        '"previous_balance_minor" INTEGER NULL, '
        '"new_balance_minor" INTEGER NOT NULL, '
        '"min_due_minor" INTEGER NULL, '
        '"payments_minor" INTEGER NULL, '
        '"credits_minor" INTEGER NULL, '
        '"fees_minor" INTEGER NULL, '
        '"interest_minor" INTEGER NULL, '
        '"installment_due_minor" INTEGER NULL, '
        '"credit_balance_minor" INTEGER NULL, '
        '"due_date" TEXT NOT NULL, '
        '"recorded_by" TEXT NOT NULL, '
        '"reason" TEXT NULL, '
        '"recorded_at" TEXT NOT NULL, '
        'PRIMARY KEY ("id"), '
        'UNIQUE ("workspace_id", "id"), '
        'UNIQUE ("workspace_id", "statement_id", "id"), '
        'UNIQUE ("statement_id", "version_no"), '
        'FOREIGN KEY (workspace_id, statement_id) REFERENCES statements (workspace_id, id), '
        'CHECK (version_no >= 1), '
        'CHECK (source_kind IN (\'manual\', \'import\', \'correction\')), '
        'CHECK (source_kind <> \'correction\' OR version_no > 1), '
        'CHECK (previous_balance_minor IS NULL OR previous_balance_minor BETWEEN -10000000000000 AND 10000000000000), '
        'CHECK (new_balance_minor BETWEEN -10000000000000 AND 10000000000000), '
        'CHECK (min_due_minor IS NULL OR min_due_minor BETWEEN 0 AND 10000000000000), '
        'CHECK (payments_minor IS NULL OR payments_minor BETWEEN 0 AND 10000000000000), '
        'CHECK (credits_minor IS NULL OR credits_minor BETWEEN 0 AND 10000000000000), '
        'CHECK (fees_minor IS NULL OR fees_minor BETWEEN 0 AND 10000000000000), '
        'CHECK (interest_minor IS NULL OR interest_minor BETWEEN 0 AND 10000000000000), '
        'CHECK (installment_due_minor IS NULL OR installment_due_minor BETWEEN 0 AND 10000000000000), '
        'CHECK (credit_balance_minor IS NULL OR credit_balance_minor BETWEEN 0 AND 10000000000000), '
        'CHECK (credit_balance_minor IS NULL OR credit_balance_minor = 0 OR new_balance_minor <= 0), '
        'CHECK (min_due_minor IS NULL OR min_due_minor <= max(new_balance_minor, 0)), '
        'CHECK (due_date GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]\'), '
        'CHECK (recorded_by IN (\'user\', \'import\')), '
        'CHECK (source_kind <> \'correction\' OR reason IS NOT NULL), '
        'CHECK (reason IS NULL OR length(reason) BETWEEN 1 AND 200), '
        'CHECK (reason NOT GLOB \'*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*\'), '
        'CHECK (recorded_at GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*\')'
        ') STRICT',
    // installment_plans
    'CREATE TABLE IF NOT EXISTS "installment_plans" ('
        '"id" TEXT NOT NULL, '
        '"workspace_id" TEXT NOT NULL, '
        '"currency_account_id" TEXT NOT NULL, '
        '"transaction_id" TEXT NOT NULL, '
        '"principal_minor" INTEGER NOT NULL, '
        '"periods" INTEGER NOT NULL, '
        '"per_period_rate" TEXT NOT NULL, '
        '"fee_mode" TEXT NOT NULL, '
        '"remainder_policy" TEXT NOT NULL, '
        '"rounding" TEXT NOT NULL, '
        '"status" TEXT NOT NULL, '
        '"early_settled_at" TEXT NULL, '
        '"row_version" INTEGER NOT NULL DEFAULT 1, '
        '"created_at" TEXT NOT NULL, '
        '"updated_at" TEXT NOT NULL, '
        'PRIMARY KEY ("id"), '
        'UNIQUE ("workspace_id", "id"), '
        'UNIQUE ("workspace_id", "transaction_id"), '
        'FOREIGN KEY (workspace_id, currency_account_id, transaction_id) REFERENCES transactions (workspace_id, currency_account_id, id), '
        'CHECK (principal_minor BETWEEN 1 AND 10000000000000), '
        'CHECK (periods BETWEEN 1 AND 60), '
        'CHECK (length(per_period_rate) BETWEEN 1 AND 12 AND (per_period_rate = \'0\' OR (per_period_rate GLOB \'0.[0-9]*\' AND substr(per_period_rate, 3) NOT GLOB \'*[^0-9]*\' AND per_period_rate NOT GLOB \'*0\'))), '
        'CHECK (fee_mode IN (\'per_period\', \'upfront\')), '
        'CHECK (remainder_policy IN (\'last\', \'first\')), '
        'CHECK (rounding IN (\'HALF_UP\')), '
        'CHECK (status IN (\'active\', \'completed\', \'early_settled\', \'cancelled\')), '
        'CHECK ((status = \'early_settled\') = (early_settled_at IS NOT NULL)), '
        'CHECK (early_settled_at IS NULL OR early_settled_at GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*\'), '
        'CHECK (row_version >= 1), '
        'CHECK (created_at GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*\'), '
        'CHECK (updated_at GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*\')'
        ') STRICT',
    // installment_schedule
    'CREATE TABLE IF NOT EXISTS "installment_schedule" ('
        '"workspace_id" TEXT NOT NULL, '
        '"plan_id" TEXT NOT NULL, '
        '"period_no" INTEGER NOT NULL, '
        '"principal_minor" INTEGER NOT NULL, '
        '"fee_minor" INTEGER NOT NULL, '
        '"statement_date" TEXT NOT NULL, '
        '"due_date" TEXT NOT NULL, '
        '"status" TEXT NOT NULL, '
        'PRIMARY KEY ("plan_id", "period_no"), '
        'FOREIGN KEY (workspace_id, plan_id) REFERENCES installment_plans (workspace_id, id), '
        'CHECK (period_no BETWEEN 1 AND 60), '
        'CHECK (principal_minor BETWEEN 0 AND 10000000000000), '
        'CHECK (fee_minor BETWEEN 0 AND 10000000000000), '
        'CHECK (statement_date GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]\'), '
        'CHECK (due_date GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]\'), '
        'CHECK (due_date > statement_date), '
        'CHECK (status IN (\'scheduled\', \'billed\', \'settled\', \'cancelled\'))'
        ') STRICT',
    // repayments
    'CREATE TABLE IF NOT EXISTS "repayments" ('
        '"id" TEXT NOT NULL, '
        '"workspace_id" TEXT NOT NULL, '
        '"currency_account_id" TEXT NOT NULL, '
        '"cash_account_id" TEXT NULL, '
        '"amount_minor" INTEGER NOT NULL, '
        '"currency" TEXT NOT NULL, '
        '"status" TEXT NOT NULL, '
        '"method" TEXT NOT NULL, '
        '"payment_initiated_at" TEXT NULL, '
        '"expected_debit_on" TEXT NULL, '
        '"cash_debited_at" TEXT NULL, '
        '"credit_posted_at" TEXT NULL, '
        '"bank_confirmed_at" TEXT NULL, '
        '"evidence_note" TEXT NULL, '
        '"row_version" INTEGER NOT NULL DEFAULT 1, '
        '"created_at" TEXT NOT NULL, '
        '"updated_at" TEXT NOT NULL, '
        '"deleted_at" TEXT NULL, '
        'PRIMARY KEY ("id"), '
        'UNIQUE ("workspace_id", "id"), '
        'UNIQUE ("workspace_id", "currency_account_id", "id"), '
        'FOREIGN KEY (workspace_id, currency_account_id, currency) REFERENCES currency_accounts (workspace_id, id, currency), '
        'FOREIGN KEY (workspace_id, cash_account_id, currency) REFERENCES cash_accounts (workspace_id, id, currency), '
        'CHECK (amount_minor BETWEEN 1 AND 10000000000000), '
        'CHECK (currency IN (\'CNY\', \'USD\', \'EUR\', \'HKD\', \'GBP\', \'MOP\', \'TWD\', \'JPY\', \'KRW\', \'VND\', \'KWD\', \'BHD\', \'JOD\')), '
        'CHECK (status IN (\'recorded\', \'processing\', \'cash_debited\', \'credit_posted\', \'bank_confirmed\', \'failed\', \'user_marked_paid\', \'needs_review\', \'reversed\')), '
        'CHECK (method IN (\'auto_debit\', \'manual\', \'third_party\', \'other\')), '
        'CHECK (payment_initiated_at IS NULL OR payment_initiated_at GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*\'), '
        'CHECK (expected_debit_on IS NULL OR expected_debit_on GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]\'), '
        'CHECK (cash_debited_at IS NULL OR cash_debited_at GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*\'), '
        'CHECK (credit_posted_at IS NULL OR credit_posted_at GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*\'), '
        'CHECK (bank_confirmed_at IS NULL OR bank_confirmed_at GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*\'), '
        'CHECK (status <> \'processing\' OR payment_initiated_at IS NOT NULL), '
        'CHECK (status NOT IN (\'cash_debited\', \'credit_posted\') OR cash_debited_at IS NOT NULL), '
        'CHECK (status <> \'credit_posted\' OR credit_posted_at IS NOT NULL), '
        'CHECK (status NOT IN (\'bank_confirmed\', \'reversed\') OR bank_confirmed_at IS NOT NULL), '
        'CHECK (evidence_note IS NULL OR length(evidence_note) BETWEEN 1 AND 200), '
        'CHECK (evidence_note NOT GLOB \'*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*\'), '
        'CHECK (row_version >= 1), '
        'CHECK (created_at GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*\'), '
        'CHECK (updated_at GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*\'), '
        'CHECK (deleted_at IS NULL OR deleted_at GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*\')'
        ') STRICT',
    // repayment_allocations
    'CREATE TABLE IF NOT EXISTS "repayment_allocations" ('
        '"workspace_id" TEXT NOT NULL, '
        '"currency_account_id" TEXT NOT NULL, '
        '"repayment_id" TEXT NOT NULL, '
        '"statement_id" TEXT NOT NULL, '
        '"amount_minor" INTEGER NOT NULL, '
        'PRIMARY KEY ("repayment_id", "statement_id"), '
        'FOREIGN KEY (workspace_id, currency_account_id, repayment_id) REFERENCES repayments (workspace_id, currency_account_id, id), '
        'FOREIGN KEY (workspace_id, currency_account_id, statement_id) REFERENCES statements (workspace_id, currency_account_id, id), '
        'CHECK (amount_minor BETWEEN 1 AND 10000000000000)'
        ') STRICT',
    // reconciliation_items
    'CREATE TABLE IF NOT EXISTS "reconciliation_items" ('
        '"id" TEXT NOT NULL, '
        '"workspace_id" TEXT NOT NULL, '
        '"kind" TEXT NOT NULL, '
        '"refs" TEXT NOT NULL, '
        '"status" TEXT NOT NULL DEFAULT \'open\', '
        '"resolution" TEXT NULL, '
        '"resolved_by" TEXT NULL, '
        '"resolved_at" TEXT NULL, '
        '"row_version" INTEGER NOT NULL DEFAULT 1, '
        '"created_at" TEXT NOT NULL, '
        '"updated_at" TEXT NOT NULL, '
        'PRIMARY KEY ("id"), '
        'UNIQUE ("workspace_id", "id"), '
        'UNIQUE ("workspace_id", "kind", "refs"), '
        'FOREIGN KEY (workspace_id) REFERENCES workspaces (id), '
        'CHECK (kind IN (\'amount_mismatch\', \'duplicate_repayment\', \'refund_pending\', \'unmatched_repayment\')), '
        'CHECK (json_valid(refs) AND json_type(refs) = \'object\'), '
        'CHECK (status IN (\'open\', \'resolved\', \'dismissed\')), '
        'CHECK ((status = \'open\') = (resolved_at IS NULL)), '
        'CHECK ((status = \'open\') = (resolution IS NULL)), '
        'CHECK ((status = \'open\') = (resolved_by IS NULL)), '
        'CHECK (resolution IS NULL OR resolution IN (\'distinct\', \'same_payment\', \'offset\', \'not_offset\', \'acknowledged\', \'registered\', \'dismissed\')), '
        'CHECK (resolved_by IS NULL OR resolved_by IN (\'user\', \'system\')), '
        'CHECK (resolved_at IS NULL OR resolved_at GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*\'), '
        'CHECK (row_version >= 1), '
        'CHECK (created_at GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*\'), '
        'CHECK (updated_at GLOB \'[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]*\')'
        ') STRICT',
  ];

  /// v4 的索引：父表上补的 `(workspace_id, id, currency)` 唯一键（交易、还款的币种与账户一致，
  /// data-model §10.4）、外键子表列、范围查询。
  static const List<String> indexes = <String>[
    'CREATE UNIQUE INDEX IF NOT EXISTS currency_accounts_currency_key '
        'ON currency_accounts (workspace_id, id, currency)',
    'CREATE UNIQUE INDEX IF NOT EXISTS cash_accounts_currency_key '
        'ON cash_accounts (workspace_id, id, currency)',
    // data-model §5：按子账户与入账日的范围查询。
    'CREATE INDEX IF NOT EXISTS transactions_account_posted '
        'ON transactions (workspace_id, currency_account_id, posted_on) WHERE deleted_at IS NULL',
    'CREATE INDEX IF NOT EXISTS transactions_currency '
        'ON transactions (workspace_id, currency_account_id, currency)',
    'CREATE INDEX IF NOT EXISTS transactions_card '
        'ON transactions (workspace_id, card_id)',
    'CREATE INDEX IF NOT EXISTS transactions_parent '
        'ON transactions (workspace_id, currency_account_id, parent_transaction_id)',
    'CREATE INDEX IF NOT EXISTS transactions_fingerprint '
        'ON transactions (workspace_id, fingerprint)',
    'CREATE INDEX IF NOT EXISTS installment_plans_transaction '
        'ON installment_plans (workspace_id, currency_account_id, transaction_id)',
    'CREATE INDEX IF NOT EXISTS installment_schedule_plan '
        'ON installment_schedule (workspace_id, plan_id)',
    'CREATE INDEX IF NOT EXISTS repayments_account '
        'ON repayments (workspace_id, currency_account_id, currency)',
    'CREATE INDEX IF NOT EXISTS repayments_cash_account '
        'ON repayments (workspace_id, cash_account_id, currency)',
    'CREATE INDEX IF NOT EXISTS repayment_allocations_repayment '
        'ON repayment_allocations (workspace_id, currency_account_id, repayment_id)',
    'CREATE INDEX IF NOT EXISTS repayment_allocations_statement '
        'ON repayment_allocations (workspace_id, currency_account_id, statement_id)',
    'CREATE INDEX IF NOT EXISTS reconciliation_items_status '
        'ON reconciliation_items (workspace_id, status)',
  ];

  /// v4 的触发器：仓库层规则的数据库兜底（错误消息只有表名与规则，不含任何数据）。
  static const List<String> triggers = <String>[
    // 交易：归属、介质、币种、类型与来源不可改；删除（tombstone）后不再改动（F-24：换卡不迁移交易）。
    '''
CREATE TRIGGER IF NOT EXISTS transactions_immutable
BEFORE UPDATE ON transactions
WHEN NEW.id IS NOT OLD.id
  OR NEW.workspace_id IS NOT OLD.workspace_id
  OR NEW.currency_account_id IS NOT OLD.currency_account_id
  OR NEW.card_id IS NOT OLD.card_id
  OR NEW.currency IS NOT OLD.currency
  OR NEW.txn_type IS NOT OLD.txn_type
  OR NEW.parent_transaction_id IS NOT OLD.parent_transaction_id
  OR NEW.source_kind IS NOT OLD.source_kind
  OR NEW.recorded_at IS NOT OLD.recorded_at
  OR OLD.deleted_at IS NOT NULL
BEGIN SELECT RAISE(ABORT, 'transactions: immutable column'); END''',
    // 交易的卡片必须属于该币种子账户所在的信用账户（data-model §10.5）。
    '''
CREATE TRIGGER IF NOT EXISTS transactions_card_account
BEFORE INSERT ON transactions
WHEN NEW.card_id IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM cards AS k
  JOIN currency_accounts AS c
    ON c.workspace_id = k.workspace_id AND c.credit_account_id = k.credit_account_id
  WHERE k.workspace_id = NEW.workspace_id AND k.id = NEW.card_id
    AND c.id = NEW.currency_account_id
)
BEGIN SELECT RAISE(ABORT, 'transactions: card not in the credit account'); END''',
    // 账单：归属与账单日不可改。
    '''
CREATE TRIGGER IF NOT EXISTS statements_immutable
BEFORE UPDATE ON statements
WHEN NEW.id IS NOT OLD.id
  OR NEW.workspace_id IS NOT OLD.workspace_id
  OR NEW.currency_account_id IS NOT OLD.currency_account_id
  OR NEW.statement_date IS NOT OLD.statement_date
  OR NEW.created_at IS NOT OLD.created_at
BEGIN SELECT RAISE(ABORT, 'statements: immutable column'); END''',
    // 账单状态机（PRD §6.2；"已修正后逾期"同"已出账后逾期"，见 README 偏离）。
    '''
CREATE TRIGGER IF NOT EXISTS statements_status_transition
BEFORE UPDATE OF status ON statements
WHEN NEW.status IS NOT OLD.status AND NOT (
  (OLD.status = 'predicted' AND NEW.status = 'issued')
  OR (OLD.status IN ('issued', 'amended')
    AND NEW.status IN ('amended', 'partially_settled', 'settled', 'overdue'))
  OR (OLD.status = 'partially_settled' AND NEW.status IN ('settled', 'overdue'))
  OR (OLD.status = 'overdue' AND NEW.status = 'settled')
)
BEGIN SELECT RAISE(ABORT, 'statements: status transition not allowed'); END''',
    // 当前版本只能前移到版本号更大的版本（旧版本保留，原值可查）。
    '''
CREATE TRIGGER IF NOT EXISTS statements_current_version_forward
BEFORE UPDATE OF current_version_id ON statements
WHEN NEW.current_version_id IS NOT OLD.current_version_id AND (
  NEW.current_version_id IS NULL
  OR (OLD.current_version_id IS NOT NULL AND (
    SELECT v.version_no FROM statement_versions AS v
    WHERE v.workspace_id = NEW.workspace_id AND v.id = NEW.current_version_id
  ) <= (
    SELECT v.version_no FROM statement_versions AS v
    WHERE v.workspace_id = OLD.workspace_id AND v.id = OLD.current_version_id
  ))
)
BEGIN SELECT RAISE(ABORT, 'statements: current version only moves forward'); END''',
    // 账单版本追加只读（R-STMT-07）：任何列都不能 UPDATE；更正 = 新版本。
    '''
CREATE TRIGGER IF NOT EXISTS statement_versions_append_only
BEFORE UPDATE ON statement_versions
BEGIN SELECT RAISE(ABORT, 'statement_versions: append only; insert a new version'); END''',
    // 版本号紧接本账单的最新版本（不跳号、不复用）。
    '''
CREATE TRIGGER IF NOT EXISTS statement_versions_sequence
BEFORE INSERT ON statement_versions
WHEN NEW.version_no <> 1 + COALESCE((
  SELECT MAX(v.version_no) FROM statement_versions AS v
  WHERE v.statement_id = NEW.statement_id
), 0)
BEGIN SELECT RAISE(ABORT, 'statement_versions: version_no must follow the latest version'); END''',
    // 到期还款日晚于账单日。
    '''
CREATE TRIGGER IF NOT EXISTS statement_versions_due_after_statement
BEFORE INSERT ON statement_versions
WHEN NEW.due_date <= (
  SELECT s.statement_date FROM statements AS s
  WHERE s.workspace_id = NEW.workspace_id AND s.id = NEW.statement_id
)
BEGIN SELECT RAISE(ABORT, 'statement_versions: due date must be after the statement date'); END''',
    // 分期条款不可改；状态只能从进行中变为已完成、已提前结清或已作废。
    '''
CREATE TRIGGER IF NOT EXISTS installment_plans_immutable
BEFORE UPDATE ON installment_plans
WHEN NEW.id IS NOT OLD.id
  OR NEW.workspace_id IS NOT OLD.workspace_id
  OR NEW.currency_account_id IS NOT OLD.currency_account_id
  OR NEW.transaction_id IS NOT OLD.transaction_id
  OR NEW.principal_minor IS NOT OLD.principal_minor
  OR NEW.periods IS NOT OLD.periods
  OR NEW.per_period_rate IS NOT OLD.per_period_rate
  OR NEW.fee_mode IS NOT OLD.fee_mode
  OR NEW.remainder_policy IS NOT OLD.remainder_policy
  OR NEW.rounding IS NOT OLD.rounding
  OR NEW.created_at IS NOT OLD.created_at
  OR (NEW.status IS NOT OLD.status AND NOT (
    OLD.status = 'active' AND NEW.status IN ('completed', 'early_settled', 'cancelled')
  ))
BEGIN SELECT RAISE(ABORT, 'installment_plans: terms are immutable'); END''',
    // 各期只改状态：未出账 → 已出账 → 已结清；未出账或已出账 → 作废。
    '''
CREATE TRIGGER IF NOT EXISTS installment_schedule_immutable
BEFORE UPDATE ON installment_schedule
WHEN NEW.workspace_id IS NOT OLD.workspace_id
  OR NEW.plan_id IS NOT OLD.plan_id
  OR NEW.period_no IS NOT OLD.period_no
  OR NEW.principal_minor IS NOT OLD.principal_minor
  OR NEW.fee_minor IS NOT OLD.fee_minor
  OR NEW.statement_date IS NOT OLD.statement_date
  OR NEW.due_date IS NOT OLD.due_date
  OR (NEW.status IS NOT OLD.status AND NOT (
    (OLD.status = 'scheduled' AND NEW.status IN ('billed', 'cancelled'))
    OR (OLD.status = 'billed' AND NEW.status IN ('settled', 'cancelled'))
  ))
BEGIN SELECT RAISE(ABORT, 'installment_schedule: only the status may change'); END''',
    '''
CREATE TRIGGER IF NOT EXISTS installment_schedule_period_range
BEFORE INSERT ON installment_schedule
WHEN NEW.period_no > (
  SELECT p.periods FROM installment_plans AS p
  WHERE p.workspace_id = NEW.workspace_id AND p.id = NEW.plan_id
)
BEGIN SELECT RAISE(ABORT, 'installment_schedule: period beyond the plan'); END''',
    // 还款：归属、币种、金额与方式不可改；作废（tombstone）后不再改动。
    '''
CREATE TRIGGER IF NOT EXISTS repayments_immutable
BEFORE UPDATE ON repayments
WHEN NEW.id IS NOT OLD.id
  OR NEW.workspace_id IS NOT OLD.workspace_id
  OR NEW.currency_account_id IS NOT OLD.currency_account_id
  OR NEW.currency IS NOT OLD.currency
  OR NEW.amount_minor IS NOT OLD.amount_minor
  OR NEW.method IS NOT OLD.method
  OR NEW.created_at IS NOT OLD.created_at
  OR OLD.deleted_at IS NOT NULL
BEGIN SELECT RAISE(ABORT, 'repayments: immutable column'); END''',
    // 还款状态机（PRD §6.3；"待核对后取得证据"同"用户已标记后取得证据"，见 README 偏离）。
    '''
CREATE TRIGGER IF NOT EXISTS repayments_status_transition
BEFORE UPDATE OF status ON repayments
WHEN NEW.status IS NOT OLD.status AND NOT (
  (OLD.status = 'recorded' AND NEW.status IN ('processing', 'user_marked_paid'))
  OR (OLD.status = 'processing' AND NEW.status IN ('cash_debited', 'failed'))
  OR (OLD.status = 'cash_debited' AND NEW.status = 'credit_posted')
  OR (OLD.status = 'credit_posted' AND NEW.status = 'bank_confirmed')
  OR (OLD.status = 'failed' AND NEW.status = 'recorded')
  OR (OLD.status = 'user_marked_paid' AND NEW.status IN ('bank_confirmed', 'needs_review'))
  OR (OLD.status = 'needs_review' AND NEW.status = 'bank_confirmed')
  OR (OLD.status = 'bank_confirmed' AND NEW.status = 'reversed')
)
BEGIN SELECT RAISE(ABORT, 'repayments: status transition not allowed'); END''',
    // 还款被删除或作废前，指向它的现金事件必须先作废（简报 §6 第 2 条）。
    '''
CREATE TRIGGER IF NOT EXISTS repayments_delete_linked
BEFORE DELETE ON repayments
WHEN EXISTS (
  SELECT 1 FROM cash_events AS e
  WHERE e.workspace_id = OLD.workspace_id AND e.linked_repayment_id = OLD.id
    AND e.deleted_at IS NULL
)
BEGIN SELECT RAISE(ABORT, 'repayments: live cash events still point to it'); END''',
    '''
CREATE TRIGGER IF NOT EXISTS repayments_tombstone_linked
BEFORE UPDATE OF deleted_at ON repayments
WHEN NEW.deleted_at IS NOT NULL AND EXISTS (
  SELECT 1 FROM cash_events AS e
  WHERE e.workspace_id = OLD.workspace_id AND e.linked_repayment_id = OLD.id
    AND e.deleted_at IS NULL
)
BEGIN SELECT RAISE(ABORT, 'repayments: live cash events still point to it'); END''',
    // v3 的 cash_events.linked_repayment_id：非空值必须指向同一工作空间的还款（简报 §6 第 2 条；
    // 不重建 cash_events 表，新建库与升级上来的库用同一组触发器）。
    '''
CREATE TRIGGER IF NOT EXISTS cash_events_linked_repayment_insert
BEFORE INSERT ON cash_events
WHEN NEW.linked_repayment_id IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM repayments AS r
  WHERE r.workspace_id = NEW.workspace_id AND r.id = NEW.linked_repayment_id
)
BEGIN SELECT RAISE(ABORT, 'cash_events: linked repayment not in workspace'); END''',
    '''
CREATE TRIGGER IF NOT EXISTS cash_events_linked_repayment_update
BEFORE UPDATE OF linked_repayment_id ON cash_events
WHEN NEW.linked_repayment_id IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM repayments AS r
  WHERE r.workspace_id = NEW.workspace_id AND r.id = NEW.linked_repayment_id
)
BEGIN SELECT RAISE(ABORT, 'cash_events: linked repayment not in workspace'); END''',
    // 分配合计不超过还款额（F-33 的数据库兜底；界面要求等于）。分配行不改，只删了重写。
    '''
CREATE TRIGGER IF NOT EXISTS repayment_allocations_within_amount
BEFORE INSERT ON repayment_allocations
WHEN NEW.amount_minor + COALESCE((
  SELECT SUM(a.amount_minor) FROM repayment_allocations AS a
  WHERE a.repayment_id = NEW.repayment_id AND a.statement_id <> NEW.statement_id
), 0) > (
  SELECT r.amount_minor FROM repayments AS r
  WHERE r.workspace_id = NEW.workspace_id AND r.id = NEW.repayment_id
)
BEGIN SELECT RAISE(ABORT, 'repayment_allocations: total exceeds the repayment'); END''',
    '''
CREATE TRIGGER IF NOT EXISTS repayment_allocations_immutable
BEFORE UPDATE ON repayment_allocations
BEGIN SELECT RAISE(ABORT, 'repayment_allocations: delete and insert instead'); END''',
    // 差异项：类型与引用不可改；只有未处理的才能处理一次（不重开）。
    '''
CREATE TRIGGER IF NOT EXISTS reconciliation_items_immutable
BEFORE UPDATE ON reconciliation_items
WHEN NEW.id IS NOT OLD.id
  OR NEW.workspace_id IS NOT OLD.workspace_id
  OR NEW.kind IS NOT OLD.kind
  OR NEW.refs IS NOT OLD.refs
  OR NEW.created_at IS NOT OLD.created_at
  OR OLD.status <> 'open'
BEGIN SELECT RAISE(ABORT, 'reconciliation_items: only an open item can be resolved once'); END''',
  ];

  /// v3 → v4 的全部语句（顺序：表、索引、触发器）。
  static const List<String> migration = <String>[
    ...tables,
    ...indexes,
    ...triggers,
  ];
}

/// 新库（[createSchema]）使用的索引：当前版本的完整集合。
const List<String> latestIndexes = <String>[
  ...SchemaV2.indexes,
  ...SchemaV3.indexes,
  ...SchemaV4.indexes,
];

/// 新库（[createSchema]）使用的触发器：当前版本的完整集合。
const List<String> latestTriggers = <String>[
  ...SchemaV2.triggers,
  ...SchemaV3.triggers,
  ...SchemaV4.triggers,
];

/// 一步迁移：把库从版本 v 升到 v + 1。
typedef SchemaMigrationStep = Future<void> Function(GeneratedDatabase db);

Future<void> _migrateV1ToV2(GeneratedDatabase db) async {
  for (final statement in SchemaV2.migration) {
    await db.customStatement(statement);
  }
}

Future<void> _migrateV2ToV3(GeneratedDatabase db) async {
  for (final statement in SchemaV3.migration) {
    await db.customStatement(statement);
  }
}

Future<void> _migrateV3ToV4(GeneratedDatabase db) async {
  for (final statement in SchemaV4.migration) {
    await db.customStatement(statement);
  }
}

/// 已登记的迁移步骤：键为旧版本 v，值把库从 v 升到 v + 1。
const Map<int, SchemaMigrationStep> schemaMigrations =
    <int, SchemaMigrationStep>{
      1: _migrateV1ToV2,
      2: _migrateV2ToV3,
      3: _migrateV3ToV4,
    };

/// 新库：在一个事务里建出最新版本的完整结构（meta、`db.allTables` 里的全部 drift 表、当前的
/// 索引与触发器）、写入 meta，并写 `PRAGMA user_version`。
///
/// [migrator] 是 drift 交给 `onCreate` 的那个（它按 `tables.dart` 的定义生成建表语句）。
Future<void> createSchema(
  GeneratedDatabase db,
  Migrator migrator, {
  required DateTime createdAt,
  int version = LocalSchema.currentSchemaVersion,
}) {
  return db.transaction(() async {
    await db.customStatement(LocalSchema.createMetaTable);
    await db.customStatement(
      'INSERT INTO meta (id, schema_version, created_at) VALUES (1, ?, ?)',
      <Object>[version, createdAt.toUtc().toIso8601String()],
    );
    for (final table in db.allTables) {
      await migrator.createTable(table);
    }
    for (final statement in <String>[...latestIndexes, ...latestTriggers]) {
      await db.customStatement(statement);
    }
    await writeUserVersion(db, version);
  });
}

/// 写 `PRAGMA user_version`（drift 用它判断库的版本）。在事务里执行时随事务提交或回滚。
Future<void> writeUserVersion(GeneratedDatabase db, int version) {
  // PRAGMA 不能绑定参数；version 是 int，直接拼接没有注入问题。
  return db.customStatement('PRAGMA user_version = $version');
}

/// 旧库：按 [steps] 从 [from] 逐步升到 [to]，并在同一事务里更新 meta 与 `user_version`。
///
/// [from] 大于 [to]（库由更新版本的 App 创建）时抛 [DatabaseErrorCode.schemaTooNew]，
/// 不做任何改动；缺少某一步或某一步出错时抛 [DatabaseErrorCode.migrationFailed]。
Future<void> migrateSchema(
  GeneratedDatabase db, {
  required int from,
  required int to,
  Map<int, SchemaMigrationStep> steps = schemaMigrations,
}) async {
  if (from > to) {
    throw const DatabaseOpenException(DatabaseErrorCode.schemaTooNew);
  }
  for (var version = from; version < to; version++) {
    if (!steps.containsKey(version)) {
      throw const DatabaseOpenException(DatabaseErrorCode.migrationFailed);
    }
  }
  try {
    await db.transaction(() async {
      for (var version = from; version < to; version++) {
        await steps[version]!(db);
      }
      await db.customStatement(
        'UPDATE meta SET schema_version = ? WHERE id = 1',
        <Object>[to],
      );
      await writeUserVersion(db, to);
    });
  } on DatabaseOpenException {
    rethrow;
  } on Object {
    throw const DatabaseOpenException(DatabaseErrorCode.migrationFailed);
  }
}
