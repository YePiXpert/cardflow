/// 数据层的 Riverpod provider：当前工作空间、时钟、各仓库与读模型。
///
/// 依赖链：`databaseProvider`（加密本地库）→ [workspaceRepositoryProvider] →
/// [currentWorkspaceProvider] → [clockProvider] / [workspaceScopeProvider] → 各仓库 provider。
/// 切换工作空间时 scope 与仓库全部重建，页面读到的永远是当前工作空间的数据。
///
/// 读 provider（如 [walletProvider]）watch [localDataRevisionProvider]：任何经 drift 的写入
/// （仓库的写方法、清除演示数据）都会让它们自动重算，页面不需要手动刷新。
///
/// 与数据库 provider 一样不自动重试（`noDatabaseRetry`）：这里的失败（没有当前工作空间、库打不开）
/// 都是确定性的；页面的「重试」用 `ref.invalidate`。
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/diagnostics/diagnostic_log.dart';
import '../db/database_providers.dart';
import '../demo/demo_workspace.dart';
import '../time/clock.dart';
import 'bank_repository.dart';
import 'billing_rule_repository.dart';
import 'card_repository.dart';
import 'card_wallet_reader.dart';
import 'cash_account_repository.dart';
import 'cash_event_repository.dart';
import 'cash_forecast_reader.dart';
import 'cash_plan_reader.dart';
import 'credit_account_repository.dart';
import 'credit_pool_repository.dart';
import 'installment_repository.dart';
import 'ledger_reader.dart';
import 'limit_snapshot_repository.dart';
import 'models.dart';
import 'reconciliation_repository.dart';
import 'recurring_item_repository.dart';
import 'repayment_repository.dart';
import 'scenario_repository.dart';
import 'statement_repository.dart';
import 'transaction_repository.dart';
import 'workspace_repository.dart';
import 'workspace_scope.dart';

part 'providers.g.dart';

/// 没有当前工作空间（应先经 P-22 选择开始方式）。路由在这种情况下总是先进 P-22，所以页面
/// 正常情况下见不到它。
final class NoCurrentWorkspaceException implements Exception {
  const NoCurrentWorkspaceException();

  @override
  String toString() => 'NoCurrentWorkspaceException';
}

/// 工作空间仓库（全局）。
@Riverpod(keepAlive: true, retry: noDatabaseRetry)
Future<WorkspaceRepository> workspaceRepository(Ref ref) async =>
    WorkspaceRepository(await ref.watch(databaseProvider.future));

/// 当前工作空间；null = 还没有（首次启动或演示清除后没有真实空间）→ 路由先进 P-22。
///
/// 切换操作只记事件（`workspace/started`、`workspace/switched`、`workspace/demo_cleared`，
/// detail 只有 real/demo/none），不记任何内容。
@Riverpod(keepAlive: true, retry: noDatabaseRetry)
class CurrentWorkspace extends _$CurrentWorkspace {
  @override
  Future<Workspace?> build() async {
    final repo = await ref.watch(workspaceRepositoryProvider.future);
    final row = await repo.current();
    return row == null ? null : Workspace.fromRow(row);
  }

  /// 进入真实空间（没有则新建）。
  Future<Workspace> enterReal() async {
    final repo = await ref.read(workspaceRepositoryProvider.future);
    final existed = await repo.live(WorkspaceKind.real);
    final workspace = Workspace.fromRow(await repo.ensure(WorkspaceKind.real));
    await repo.setCurrent(workspace.id);
    if (existed == null) {
      _log('started', 'real');
    }
    _log('switched', 'real');
    state = AsyncData(workspace);
    return workspace;
  }

  /// 进入演示空间（没有则新建并写入合成数据；失败不留下任何演示数据）。
  Future<Workspace> enterDemo() async {
    final repo = await ref.read(workspaceRepositoryProvider.future);
    final db = await ref.read(databaseProvider.future);
    final existed = await repo.live(WorkspaceKind.demo);
    final workspace = Workspace.fromRow(await ensureDemoWorkspace(db));
    await repo.setCurrent(workspace.id);
    if (existed == null) {
      _log('started', 'demo');
    }
    _log('switched', 'demo');
    state = AsyncData(workspace);
    return workspace;
  }

  /// 退出演示：有真实空间则回到真实空间，否则没有当前工作空间（回到 P-22）。演示数据保留。
  Future<void> exitDemo() async {
    final repo = await ref.read(workspaceRepositoryProvider.future);
    final real = await repo.live(WorkspaceKind.real);
    await repo.setCurrent(real?.id);
    _log('switched', real == null ? 'none' : 'real');
    state = AsyncData(real == null ? null : Workspace.fromRow(real));
  }

  /// 清除演示数据：删除演示空间的全部行；若当前在演示空间，回到真实空间（没有则回到 P-22）。
  Future<void> clearDemo() async {
    final repo = await ref.read(workspaceRepositoryProvider.future);
    final demo = await repo.live(WorkspaceKind.demo);
    if (demo != null) {
      await repo.deleteWorkspace(demo.id);
      _log('demo_cleared', null);
    }
    var current = await repo.current();
    if (current == null) {
      final real = await repo.live(WorkspaceKind.real);
      if (real != null) {
        await repo.setCurrent(real.id);
        current = real;
      }
    }
    state = AsyncData(current == null ? null : Workspace.fromRow(current));
  }

  void _log(String event, String? detail) =>
      ref.read(diagnosticLogProvider).info('workspace', event, detail: detail);
}

/// 演示空间的概况：是否存在，以及各表行数（P-22 的「清除演示数据」写明影响数量）。
@Riverpod(retry: noDatabaseRetry)
Future<Map<String, int>?> demoWorkspaceRows(Ref ref) async {
  ref.watch(localDataRevisionProvider);
  final repo = await ref.watch(workspaceRepositoryProvider.future);
  final demo = await repo.live(WorkspaceKind.demo);
  return demo == null ? null : repo.countRows(demo.id);
}

/// "现在"：演示空间固定为 2026-10-16（陈旧判定不触发），真实空间用系统时间。测试里替换。
@Riverpod(keepAlive: true)
AppClock clock(Ref ref) {
  final workspace = ref.watch(currentWorkspaceProvider).value;
  return workspace != null && workspace.isDemo
      ? demoClock
      : const SystemClock();
}

/// 当前工作空间的作用域（数据库 + 工作空间 id + 时钟）；没有当前工作空间时失败
/// （[NoCurrentWorkspaceException]）。
@Riverpod(keepAlive: true, retry: noDatabaseRetry)
Future<WorkspaceScope> workspaceScope(Ref ref) async {
  final clock = ref.watch(clockProvider);
  final db = await ref.watch(databaseProvider.future);
  final workspace = await ref.watch(currentWorkspaceProvider.future);
  if (workspace == null) {
    throw const NoCurrentWorkspaceException();
  }
  return WorkspaceScope(db: db, workspaceId: workspace.id, clock: clock);
}

/// 本地数据的变更计数：经 drift 的任何写入提交后加 1。读 provider watch 它以自动重算。
@Riverpod(keepAlive: true, retry: noDatabaseRetry)
Stream<int> localDataRevision(Ref ref) async* {
  final db = await ref.watch(databaseProvider.future);
  var revision = 0;
  yield revision;
  await for (final _ in db.tableUpdates()) {
    yield ++revision;
  }
}

/// 银行仓库（当前工作空间）。
@Riverpod(retry: noDatabaseRetry)
Future<BankRepository> bankRepository(Ref ref) async =>
    BankRepository(await ref.watch(workspaceScopeProvider.future));

/// 信用账户与币种子账户仓库（当前工作空间）。
@Riverpod(retry: noDatabaseRetry)
Future<CreditAccountRepository> creditAccountRepository(Ref ref) async =>
    CreditAccountRepository(await ref.watch(workspaceScopeProvider.future));

/// 卡片仓库（当前工作空间）。
@Riverpod(retry: noDatabaseRetry)
Future<CardRepository> cardRepository(Ref ref) async =>
    CardRepository(await ref.watch(workspaceScopeProvider.future));

/// 授信池仓库（当前工作空间）。
@Riverpod(retry: noDatabaseRetry)
Future<CreditPoolRepository> creditPoolRepository(Ref ref) async =>
    CreditPoolRepository(await ref.watch(workspaceScopeProvider.future));

/// 账期规则版本仓库（当前工作空间）。
@Riverpod(retry: noDatabaseRetry)
Future<BillingRuleRepository> billingRuleRepository(Ref ref) async =>
    BillingRuleRepository(await ref.watch(workspaceScopeProvider.future));

/// 额度快照仓库（当前工作空间）。
@Riverpod(retry: noDatabaseRetry)
Future<LimitSnapshotRepository> limitSnapshotRepository(Ref ref) async =>
    LimitSnapshotRepository(await ref.watch(workspaceScopeProvider.future));

/// 卡包读模型（P-01/P-02/P-03）：数据变化时自动重算。
@Riverpod(retry: noDatabaseRetry)
Future<WalletView> wallet(Ref ref) async {
  ref.watch(localDataRevisionProvider);
  final scope = await ref.watch(workspaceScopeProvider.future);
  return CardWalletReader(scope).load();
}

/// 现金账户与余额快照仓库（当前工作空间）。
@Riverpod(retry: noDatabaseRetry)
Future<CashAccountRepository> cashAccountRepository(Ref ref) async =>
    CashAccountRepository(await ref.watch(workspaceScopeProvider.future));

/// 现金余额快照仓库（当前工作空间）。
@Riverpod(retry: noDatabaseRetry)
Future<CashSnapshotRepository> cashSnapshotRepository(Ref ref) async =>
    CashSnapshotRepository(await ref.watch(workspaceScopeProvider.future));

/// 现金事件仓库（收支计划、调拨、还款扣款；当前工作空间）。
@Riverpod(retry: noDatabaseRetry)
Future<CashEventRepository> cashEventRepository(Ref ref) async =>
    CashEventRepository(await ref.watch(workspaceScopeProvider.future));

/// 周期事项仓库（当前工作空间）。
@Riverpod(retry: noDatabaseRetry)
Future<RecurringItemRepository> recurringItemRepository(Ref ref) async =>
    RecurringItemRepository(await ref.watch(workspaceScopeProvider.future));

/// 情景仓库（当前工作空间）。
@Riverpod(retry: noDatabaseRetry)
Future<ScenarioRepository> scenarioRepository(Ref ref) async =>
    ScenarioRepository(await ref.watch(workspaceScopeProvider.future));

/// 现金与收支计划（P-08）读模型：数据变化时自动重算。
@Riverpod(retry: noDatabaseRetry)
Future<CashPlanView> cashPlan(Ref ref) async {
  ref.watch(localDataRevisionProvider);
  final scope = await ref.watch(workspaceScopeProvider.future);
  return CashPlanReader(scope).load();
}

/// 现金账户详情（P-08）；账户不在当前空间时失败（NotFoundException）。
@Riverpod(retry: noDatabaseRetry)
Future<CashAccountDetailView> cashAccountDetail(
  Ref ref,
  String accountId,
) async {
  ref.watch(localDataRevisionProvider);
  final scope = await ref.watch(workspaceScopeProvider.future);
  return CashPlanReader(scope).loadAccount(accountId);
}

/// 周期事项详情（P-08）；不在当前空间时失败（NotFoundException）。
@Riverpod(retry: noDatabaseRetry)
Future<RecurringDetailView> recurringDetail(Ref ref, String itemId) async {
  ref.watch(localDataRevisionProvider);
  final scope = await ref.watch(workspaceScopeProvider.future);
  return CashPlanReader(scope).loadRecurring(itemId);
}

/// 资金日历（P-07）与总览现金压力卡（P-01）：数据变化时自动重算（provider 依赖）。
@Riverpod(retry: noDatabaseRetry)
Future<CashForecast> cashForecast(Ref ref, CashForecastQuery query) async {
  ref.watch(localDataRevisionProvider);
  final scope = await ref.watch(workspaceScopeProvider.future);
  return CashForecastReader(scope).forecast(query);
}

/// 情景列表（P-09）：每个情景的计算版本（新的在前）与最新版本是否已过期。
@Riverpod(retry: noDatabaseRetry)
Future<ScenarioBoard> scenarioBoard(Ref ref) async {
  ref.watch(localDataRevisionProvider);
  final scope = await ref.watch(workspaceScopeProvider.future);
  return ScenarioBoard.load(scope);
}

/// 交易仓库（当前工作空间，I-1c）。
@Riverpod(retry: noDatabaseRetry)
Future<TransactionRepository> transactionRepository(Ref ref) async =>
    TransactionRepository(await ref.watch(workspaceScopeProvider.future));

/// 账单与账单版本仓库（当前工作空间）。
@Riverpod(retry: noDatabaseRetry)
Future<StatementRepository> statementRepository(Ref ref) async =>
    StatementRepository(await ref.watch(workspaceScopeProvider.future));

/// 分期计划仓库（当前工作空间）。
@Riverpod(retry: noDatabaseRetry)
Future<InstallmentRepository> installmentRepository(Ref ref) async =>
    InstallmentRepository(await ref.watch(workspaceScopeProvider.future));

/// 还款仓库（当前工作空间）。
@Riverpod(retry: noDatabaseRetry)
Future<RepaymentRepository> repaymentRepository(Ref ref) async =>
    RepaymentRepository(await ref.watch(workspaceScopeProvider.future));

/// 差异项仓库（当前工作空间）。
@Riverpod(retry: noDatabaseRetry)
Future<ReconciliationRepository> reconciliationRepository(Ref ref) async =>
    ReconciliationRepository(await ref.watch(workspaceScopeProvider.future));

/// 账单、交易、分期、还款与差异项的读模型（P-05/P-06/P-03/P-01）：数据变化时自动重算。
@Riverpod(retry: noDatabaseRetry)
Future<LedgerData> ledger(Ref ref) async {
  ref.watch(localDataRevisionProvider);
  final scope = await ref.watch(workspaceScopeProvider.future);
  return LedgerReader(scope).load();
}
