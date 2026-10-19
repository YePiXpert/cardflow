import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../ids.dart';
import '../time/clock.dart';
import 'models.dart';

/// `app_settings` 里记录当前工作空间的键。
const String currentWorkspaceSettingKey = 'current_workspace_id';

/// 工作空间（真实/演示）与"当前工作空间"指针。不属于任何工作空间的全局仓库。
///
/// 规则（R-SYS-13、ui-spec §4.2）：真实空间与演示空间各最多一个未删除的；两者的数据互不可见
/// （业务仓库都按当前工作空间过滤）；"清除演示数据"删除演示空间的全部行与工作空间本身。
final class WorkspaceRepository {
  WorkspaceRepository(this._db, {this._clock = const SystemClock()});

  final AppDatabase _db;
  final AppClock _clock;

  /// 当前工作空间；没有（首次启动、演示清除后且无真实空间）时为 null。
  Future<WorkspaceRow?> current() async {
    final setting =
        await (_db.select(_db.appSettings)
              ..where((s) => s.key.equals(currentWorkspaceSettingKey)))
            .getSingleOrNull();
    if (setting == null) {
      return null;
    }
    return (_db.select(_db.workspaces)
          ..where((w) => w.id.equals(setting.value) & w.deletedAt.isNull()))
        .getSingleOrNull();
  }

  /// 某一种未删除的工作空间。
  Future<WorkspaceRow?> live(WorkspaceKind kind) =>
      (_db.select(_db.workspaces)
            ..where((w) => w.kind.equals(kind.code) & w.deletedAt.isNull()))
          .getSingleOrNull();

  /// 取得（没有则新建）某一种工作空间；不改变当前工作空间。
  Future<WorkspaceRow> ensure(WorkspaceKind kind) => _db.transaction(() async {
    final existing = await live(kind);
    if (existing != null) {
      return existing;
    }
    final id = newUuidV4();
    await _db
        .into(_db.workspaces)
        .insert(
          WorkspacesCompanion.insert(
            id: id,
            kind: kind.code,
            name: kind.defaultName,
            createdAt: _clock.nowText(),
          ),
        );
    return (await live(kind))!;
  });

  /// 设置当前工作空间（null = 没有当前工作空间，App 回到欢迎页）。
  Future<void> setCurrent(String? workspaceId) async {
    if (workspaceId == null) {
      await (_db.delete(
        _db.appSettings,
      )..where((s) => s.key.equals(currentWorkspaceSettingKey))).go();
      return;
    }
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: currentWorkspaceSettingKey,
            value: workspaceId,
          ),
        );
  }

  /// 工作空间 [workspaceId] 每张业务表的行数（"清除演示数据"确认框写明影响数量，ui-spec §4.5）。
  Future<Map<String, int>> countRows(String workspaceId) async => <String, int>{
    for (final table in workspaceDataTables)
      table:
          (await _db
                  .customSelect(
                    'SELECT COUNT(*) AS n FROM $table WHERE workspace_id = ?',
                    variables: <Variable<Object>>[
                      Variable<String>(workspaceId),
                    ],
                    readsFrom: <TableInfo<Table, Object?>>{
                      for (final t in _db.allTables)
                        if (t.actualTableName == table) t,
                    },
                  )
                  .getSingle())
              .read<int>('n'),
  };

  /// 删除工作空间 [workspaceId] 的全部业务行与工作空间本身（"清除演示数据"）；若它是当前工作
  /// 空间，当前指针一并清除。一个事务内完成。
  Future<void> deleteWorkspace(String workspaceId) => _db.transaction(() async {
    Future<void> purge(String table) => _db.customUpdate(
      'DELETE FROM $table WHERE workspace_id = ?',
      variables: <Variable<Object>>[Variable<String>(workspaceId)],
      updateKind: UpdateKind.delete,
      updates: <TableInfo<Table, Object?>>{
        for (final t in _db.allTables)
          if (t.actualTableName == table) t,
      },
    );
    // 顺序按外键依赖：先子表后父表；同表内的自引用（换卡链、附属卡）在一条语句内删除。
    for (final table in workspaceDataTables) {
      await purge(table);
    }
    await (_db.delete(
      _db.workspaces,
    )..where((w) => w.id.equals(workspaceId))).go();
    final current =
        await (_db.select(_db.appSettings)
              ..where((s) => s.key.equals(currentWorkspaceSettingKey)))
            .getSingleOrNull();
    if (current?.value == workspaceId) {
      await setCurrent(null);
    }
  });
}

/// 带 `workspace_id` 的业务表，按"先子表后父表"的删除顺序排列。新增的业务表必须加进来
/// （`workspace_isolation_test` 会检查本表覆盖了 sqlite_master 里所有带 workspace_id 的表）。
const List<String> workspaceDataTables = <String>[
  // v4（I-1c）：差异项、分配、分期各期与计划；账单版本先于账单（账单的当前版本是延迟检查的外键）。
  'reconciliation_items',
  'repayment_allocations',
  'installment_schedule',
  'installment_plans',
  'statement_versions',
  'statements',
  // v3（I-1b）
  'scenario_runs',
  'scenarios',
  'snapshot_included_events',
  'cash_balance_snapshots',
  'cash_events',
  // v4：还款在现金事件之后（触发器：仍有未删除的现金事件指向它时不能删除）。
  'repayments',
  'recurring_overrides',
  'recurring_items',
  'cash_accounts',
  // v4：交易在卡片与币种子账户之前（分期计划已先删）。
  'transactions',
  // v2（I-1a）
  'limit_snapshots',
  'billing_rule_versions',
  'cards',
  'currency_accounts',
  'credit_accounts',
  'credit_pools',
  'banks',
];
