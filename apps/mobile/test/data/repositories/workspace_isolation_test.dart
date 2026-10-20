// 工作空间隔离（R-SYS-13、I-1a 简报 §2）：演示空间写满全部业务表后，以真实空间为当前空间运行
// 每个仓库的全部查询（含用演示空间的 id 去查），结果必须为空；反向亦然。真实 sqlite3mc。
//
// 新增仓库或查询方法时，必须加进下面的 [runAllQueries]。
// 设环境变量 CARDFLOW_EVIDENCE=1 时逐条打印查询与结果行数（证据 isolation.txt）。
import 'dart:io';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/demo/demo_workspace.dart';
import 'package:cardflow/data/repositories/bank_repository.dart';
import 'package:cardflow/data/repositories/billing_rule_repository.dart';
import 'package:cardflow/data/repositories/card_repository.dart';
import 'package:cardflow/data/repositories/card_wallet_reader.dart';
import 'package:cardflow/data/repositories/cash_account_repository.dart';
import 'package:cardflow/data/repositories/cash_event_repository.dart';
import 'package:cardflow/data/repositories/cash_forecast_reader.dart';
import 'package:cardflow/data/repositories/credit_account_repository.dart';
import 'package:cardflow/data/repositories/credit_pool_repository.dart';
import 'package:cardflow/data/repositories/installment_repository.dart';
import 'package:cardflow/data/repositories/ledger_models.dart';
import 'package:cardflow/data/repositories/ledger_reader.dart';
import 'package:cardflow/data/repositories/limit_snapshot_repository.dart';
import 'package:cardflow/data/repositories/models.dart';
import 'package:cardflow/data/repositories/reconciliation_repository.dart';
import 'package:cardflow/data/repositories/recurring_item_repository.dart';
import 'package:cardflow/data/repositories/repayment_repository.dart';
import 'package:cardflow/data/repositories/repository_errors.dart';
import 'package:cardflow/data/repositories/scenario_repository.dart';
import 'package:cardflow/data/repositories/statement_repository.dart';
import 'package:cardflow/data/repositories/transaction_repository.dart';
import 'package:cardflow/data/repositories/workspace_repository.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow/data/time/clock.dart';
import 'package:cardflow_domain/cardflow_domain.dart'
    show DueRule, LocalDate, Rational;
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';

import 'repository_test_support.dart';

final bool _evidence = Platform.environment['CARDFLOW_EVIDENCE'] == '1';

void _log(String line) {
  if (_evidence) {
    // ignore: avoid_print
    print(line);
  }
}

/// 没有 `id` 列的表（复合主键）用来标识一行的表达式。
const Map<String, String> _rowKeys = <String, String>{
  'snapshot_included_events': "snapshot_id || '/' || cash_event_id",
  'recurring_overrides': "recurring_item_id || '/' || occurrence_key",
  'installment_schedule': "plan_id || '/' || period_no",
  'repayment_allocations': "repayment_id || '/' || statement_id",
};

/// 某工作空间里全部业务行的 id（按表；复合主键的表是 `键1/键2`）。
Future<Map<String, List<String>>> idsByTable(
  AppDatabase db,
  String workspaceId,
) async => <String, List<String>>{
  for (final table in workspaceDataTables)
    table:
        (await db
                .customSelect(
                  'SELECT ${_rowKeys[table] ?? 'id'} AS id FROM $table '
                  'WHERE workspace_id = ? ORDER BY 1',
                  variables: [Variable<String>(workspaceId)],
                )
                .get())
            .map((r) => r.read<String>('id'))
            .toList(),
};

/// 以 [scope] 为当前工作空间运行每个仓库的全部查询；查询参数用另一个工作空间的 id
/// （[foreign]）。返回 查询名 → 结果行数（null/抛 NotFound 记 0）。
Future<Map<String, int>> runAllQueries(
  WorkspaceScope scope,
  Map<String, List<String>> foreign,
) async {
  final results = <String, int>{};
  Future<void> run(String name, Future<Object?> Function() query) async {
    Object? value;
    try {
      value = await query();
    } on NotFoundException {
      value = null;
    }
    final count = switch (value) {
      null => 0,
      final Iterable<Object?> rows => rows.length,
      final Map<Object?, Object?> map => map.length,
      final WalletView wallet => wallet.accounts.length + wallet.pools.length,
      final CashDomainInputs inputs =>
        inputs.accountRows.length +
            inputs.eventRows.length +
            inputs.latestSnapshots.length +
            inputs.installmentDue.length,
      final LedgerData data =>
        data.statements.length +
            data.transactions.length +
            data.repayments.length +
            data.allocations.length +
            data.plans.length +
            data.items.length,
      _ => 1,
    };
    results[name] = count;
  }

  String any(String table) => foreign[table]!.first;
  final banks = BankRepository(scope);
  final accounts = CreditAccountRepository(scope);
  final cards = CardRepository(scope);
  final pools = CreditPoolRepository(scope);
  final rules = BillingRuleRepository(scope);
  final snapshots = LimitSnapshotRepository(scope);

  await run('BankRepository.listStored()', banks.listStored);
  await run('BankRepository.byId(他空间银行)', () => banks.byId(any('banks')));
  await run(
    'BankRepository.choices() 中已写库的',
    () async => (await banks.choices()).where((c) => c.bankId != null).toList(),
  );
  await run('CreditAccountRepository.list()', accounts.list);
  for (final id in foreign['credit_accounts']!) {
    await run('CreditAccountRepository.byId($id)', () => accounts.byId(id));
    await run(
      'CreditAccountRepository.require($id)',
      () => accounts.require(id),
    );
    await run(
      'CreditAccountRepository.currencyAccounts($id)',
      () => accounts.currencyAccounts(id),
    );
  }
  await run(
    'CreditAccountRepository.currencyAccounts()',
    accounts.currencyAccounts,
  );
  for (final id in foreign['currency_accounts']!) {
    await run(
      'CreditAccountRepository.currencyAccountById($id)',
      () => accounts.currencyAccountById(id),
    );
    await run(
      'LimitSnapshotRepository.history($id)',
      () => snapshots.history(id),
    );
    await run(
      'BillingRuleRepository.versions(子账户 $id)',
      () => rules.versions(RuleSubject.currencyAccount(id)),
    );
  }
  for (final id in foreign['credit_pools']!) {
    await run(
      'CreditAccountRepository.poolMembers($id)',
      () => accounts.poolMembers(id),
    );
    await run('CreditPoolRepository.byId($id)', () => pools.byId(id));
  }
  await run('CreditPoolRepository.list()', pools.list);
  for (final id in foreign['banks']!) {
    await run('CreditPoolRepository.forBank($id)', () => pools.forBank(id));
  }
  await run('CardRepository.list()', cards.list);
  for (final id in foreign['cards']!) {
    await run('CardRepository.byId($id)', () => cards.byId(id));
    await run('CardRepository.require($id)', () => cards.require(id));
  }
  for (final id in foreign['credit_accounts']!) {
    await run(
      'CardRepository.list(creditAccountId: $id)',
      () => cards.list(creditAccountId: id),
    );
    await run(
      'BillingRuleRepository.versions(账户 $id)',
      () => rules.versions(RuleSubject.creditAccount(id)),
    );
    await run(
      'BillingRuleRepository.effectiveOn(账户 $id)',
      () => rules.effectiveOn(
        RuleSubject.creditAccount(id),
        LocalDate(2026, 10, 16),
      ),
    );
  }
  for (final bank in <String>['星海银行', '长江银行', '北辰银行']) {
    for (final last4 in <String>['1001', '1002', '2001', '3001', '4001']) {
      await run(
        'CardRepository.sameBankSameLast4($bank, $last4)',
        () => cards.sameBankSameLast4(bankName: bank, last4: last4),
      );
    }
  }
  await run('BillingRuleRepository.all()', rules.all);
  await run('LimitSnapshotRepository.all()', snapshots.all);
  await run(
    'LimitSnapshotRepository.latestByCurrencyAccount()',
    snapshots.latestByCurrencyAccount,
  );
  await run('CardWalletReader.load()', CardWalletReader(scope).load);

  // v3（I-1b）：现金账户、快照、事件、周期事项、情景。
  final cashAccounts = CashAccountRepository(scope);
  final cashSnapshots = CashSnapshotRepository(scope);
  final cashEvents = CashEventRepository(scope);
  final recurring = RecurringItemRepository(scope);
  final scenarios = ScenarioRepository(scope);
  await run('CashAccountRepository.list()', cashAccounts.list);
  for (final id in foreign['cash_accounts']!) {
    await run('CashAccountRepository.byId($id)', () => cashAccounts.byId(id));
    await run(
      'CashAccountRepository.require($id)',
      () => cashAccounts.require(id),
    );
    await run(
      'CashSnapshotRepository.history($id)',
      () => cashSnapshots.history(id),
    );
    await run(
      'CashSnapshotRepository.sameDayEvents($id)',
      () => cashSnapshots.sameDayEvents(id, LocalDate(2026, 10, 16)),
    );
    await run(
      'CashEventRepository.list(cashAccountId: $id)',
      () => cashEvents.list(cashAccountId: id),
    );
  }
  await run('CashSnapshotRepository.all()', cashSnapshots.all);
  await run(
    'CashSnapshotRepository.latestByAccount()',
    cashSnapshots.latestByAccount,
  );
  await run(
    'CashSnapshotRepository.includedEventIds()',
    cashSnapshots.includedEventIds,
  );
  for (final id in foreign['cash_balance_snapshots']!) {
    await run(
      'CashSnapshotRepository.includedIn($id)',
      () => cashSnapshots.includedIn(id),
    );
  }
  await run('CashEventRepository.list()', cashEvents.list);
  await run('CashEventRepository.transfers()', cashEvents.transfers);
  for (final id in foreign['cash_events']!) {
    await run('CashEventRepository.byId($id)', () => cashEvents.byId(id));
    await run('CashEventRepository.require($id)', () => cashEvents.require(id));
  }
  await run('RecurringItemRepository.list()', recurring.list);
  for (final id in foreign['recurring_items']!) {
    await run('RecurringItemRepository.byId($id)', () => recurring.byId(id));
    await run(
      'RecurringItemRepository.require($id)',
      () => recurring.require(id),
    );
    await run(
      'RecurringItemRepository.overridesOf($id)',
      () => recurring.overridesOf(id),
    );
    await run(
      'RecurringItemRepository.occurrences($id)',
      () => recurring.occurrences(id),
    );
  }
  await run('ScenarioRepository.rows()', scenarios.rows);
  await run(
    'ScenarioRepository.list() 中已保存的',
    () async => (await scenarios.list()).where((s) => s.row != null).toList(),
  );
  await run('ScenarioRepository.allRuns()', scenarios.allRuns);
  for (final id in foreign['scenarios']!) {
    await run('ScenarioRepository.byKey($id)', () => scenarios.byKey(id));
    await run('ScenarioRepository.runs($id)', () => scenarios.runs(id));
  }
  for (final id in foreign['scenario_runs']!) {
    await run('ScenarioRepository.runById($id)', () => scenarios.runById(id));
  }
  await run(
    'CashForecastReader.loadInputs()',
    CashForecastReader(scope).loadInputs,
  );

  // v4（I-1c）：交易、账单与版本、分期、还款与分配、差异项。
  final transactions = TransactionRepository(scope);
  final statements = StatementRepository(scope);
  final installments = InstallmentRepository(scope);
  final repayments = RepaymentRepository(scope);
  final items = ReconciliationRepository(scope);
  await run('TransactionRepository.list()', transactions.list);
  await run('StatementRepository.list()', statements.list);
  await run('StatementRepository.allVersions()', statements.allVersions);
  await run('InstallmentRepository.plans()', installments.plans);
  await run('InstallmentRepository.allPeriods()', installments.allPeriods);
  await run('RepaymentRepository.list()', repayments.list);
  await run('RepaymentRepository.allAllocations()', repayments.allAllocations);
  await run('ReconciliationRepository.list()', items.list);
  await run(
    'ReconciliationRepository.openDuplicatePairs()',
    items.openDuplicatePairs,
  );
  await run('ReconciliationRepository.offsetRefunds()', items.offsetRefunds);
  for (final id in foreign['currency_accounts']!) {
    await run(
      'TransactionRepository.list(currencyAccountId: $id)',
      () => transactions.list(currencyAccountId: id),
    );
    await run(
      'StatementRepository.list(currencyAccountId: $id)',
      () => statements.list(currencyAccountId: id),
    );
    await run(
      'InstallmentRepository.plans(currencyAccountId: $id)',
      () => installments.plans(currencyAccountId: id),
    );
    await run(
      'RepaymentRepository.list(currencyAccountId: $id)',
      () => repayments.list(currencyAccountId: id),
    );
  }
  for (final id in foreign['transactions']!) {
    await run('TransactionRepository.byId($id)', () => transactions.byId(id));
    await run(
      'TransactionRepository.require($id)',
      () => transactions.require(id),
    );
    await run(
      'InstallmentRepository.byTransaction($id)',
      () => installments.byTransaction(id),
    );
  }
  for (final id in foreign['statements']!) {
    await run('StatementRepository.byId($id)', () => statements.byId(id));
    await run('StatementRepository.require($id)', () => statements.require(id));
    await run(
      'StatementRepository.versions($id)',
      () => statements.versions(id),
    );
  }
  for (final id in foreign['installment_plans']!) {
    await run('InstallmentRepository.byId($id)', () => installments.byId(id));
    await run(
      'InstallmentRepository.require($id)',
      () => installments.require(id),
    );
    await run(
      'InstallmentRepository.schedule($id)',
      () => installments.schedule(id),
    );
  }
  for (final id in foreign['repayments']!) {
    await run('RepaymentRepository.byId($id)', () => repayments.byId(id));
    await run('RepaymentRepository.require($id)', () => repayments.require(id));
    await run(
      'RepaymentRepository.allocationsOf($id)',
      () => repayments.allocationsOf(id),
    );
    await run(
      'CashEventRepository.byRepayment($id)',
      () => cashEvents.byRepayment(id),
    );
  }
  for (final id in foreign['reconciliation_items']!) {
    await run('ReconciliationRepository.byId($id)', () => items.byId(id));
    await run('ReconciliationRepository.require($id)', () => items.require(id));
  }
  await run('LedgerReader.load()', () => LedgerReader(scope).load());
  return results;
}

/// 以 [scope] 为当前工作空间、用另一个空间的 id 改账单、交易、分期、还款与差异项：一律"已不存在"。
Future<void> expectForeignLedgerWritesRejected(
  WorkspaceScope scope,
  Map<String, List<String>> foreign,
) async {
  await expectRepositoryError<NotFoundException>(
    () => TransactionRepository(scope).delete(foreign['transactions']!.first),
  );
  await expectRepositoryError<NotFoundException>(
    () => StatementRepository(scope).correct(
      foreign['statements']!.first,
      figures: const StatementFigures(newBalanceMinor: 1),
      reason: '跨空间修正',
    ),
  );
  await expectRepositoryError<NotFoundException>(
    () =>
        InstallmentRepository(scope)
            .cancel(foreign['installment_plans']!.first),
  );
  await expectRepositoryError<NotFoundException>(
    () => RepaymentRepository(scope).markUserPaid(foreign['repayments']!.first),
  );
  await expectRepositoryError<NotFoundException>(
    () =>
        ReconciliationRepository(scope)
            .dismiss(foreign['reconciliation_items']!.first),
  );
}

/// 以 [scope] 为当前工作空间、用另一个空间的 id 写入现金数据：一律"已不存在"。
Future<void> expectForeignCashWritesRejected(
  WorkspaceScope scope,
  Map<String, List<String>> foreign,
) async {
  final account = foreign['cash_accounts']!.first;
  final event = foreign['cash_events']!.first;
  final item = foreign['recurring_items']!.first;
  final scenario = foreign['scenarios']!.first;
  await expectRepositoryError<NotFoundException>(
    () => CashAccountRepository(scope).update(account, reserveFloorMinor: 1),
  );
  await expectRepositoryError<NotFoundException>(
    () => CashEventRepository(scope).delete(event),
  );
  await expectRepositoryError<NotFoundException>(
    () => CashEventRepository(scope).markPosted(event),
  );
  await expectRepositoryError<NotFoundException>(
    () => RecurringItemRepository(scope).skip(item, LocalDate(2026, 11, 27)),
  );
  await expectRepositoryError<NotFoundException>(
    () => ScenarioRepository(scope).delete(scenario),
  );
  await expectRepositoryError<NotFoundException>(
    () => recordTestCashSnapshot(
      scope,
      account,
      LocalDate(2026, 10, 16),
      1,
      observedAt: '2026-10-16T09:00:00+08:00',
    ),
  );
}

/// 给演示数据再加一些行：USD 子账户、子账户层的规则与快照、一张已换卡的旧卡，让每条查询路径都有数据。
Future<void> _enrich(WorkspaceScope scope) async {
  final accounts = CreditAccountRepository(scope);
  final cards = CardRepository(scope);
  final first = (await accounts.list()).first;
  final usd = await accounts.addCurrencyAccount(first.id, 'USD');
  await BillingRuleRepository(scope).saveVersion(
    RuleSubject.currencyAccount(usd.id),
    const BillingRuleDraft(
      statementDay: 12,
      due: DueRule.daysAfterStatement(days: 18),
    ),
  );
  await recordTestSnapshot(
    scope,
    usd.id,
    fixed: 300000,
    balanceAsOf: '2026-10-15T09:00:00+08:00',
  );
  final card = (await cards.list(creditAccountId: first.id)).first;
  await cards.replace(
    card.id,
    newLast4: '1009',
    effectiveFrom: LocalDate(2026, 10, 16),
  );
  await _enrichLedger(scope, first.id);
}

/// v4 的表各写一行（经仓库）：9 月的交易与账单（避开演示数据的 10 月账单）、6 期分期、一笔还款（带计划
/// 扣款）与分配（分到本期账单）、一笔退款（退款待核对）。
Future<void> _enrichLedger(WorkspaceScope scope, String creditAccountId) async {
  final sub = (await primaryCurrencyAccount(scope, creditAccountId)).id;
  final card = (await CardRepository(
    scope,
  ).list(creditAccountId: creditAccountId)).first;
  final cash = (await CashAccountRepository(scope).list()).first;
  final txn = await addTestTransaction(
    scope,
    sub,
    amount: 600000,
    txnAt: '2026-08-21T10:00:00+08:00',
    cardId: card.id,
  );
  final statement = await recordTestStatement(
    scope,
    sub,
    statementDate: LocalDate(2026, 9, 10),
    dueDate: LocalDate(2026, 9, 28),
  );
  await InstallmentRepository(scope).create(
    InstallmentDraft(
      transactionId: txn.id,
      periods: 6,
      perPeriodRate: Rational.parseDecimal('0.006'),
      firstStatementOn: LocalDate(2026, 9, 10),
    ),
  );
  // 还款只分配到本期（这个子账户最近一期账单；9 月的已并入下一期）。
  final current = (await StatementRepository(
    scope,
  ).list(currencyAccountId: sub)).first;
  expect(current.statementDate.compareTo(statement.statementDate) >= 0, isTrue);
  await registerTestRepayment(
    scope,
    currencyAccountId: sub,
    cashAccountId: cash.id,
    amount: 100000,
    statementId: current.id,
    expectedDebitOn: LocalDate(2026, 9, 25),
  );
  await addTestTransaction(
    scope,
    sub,
    type: TxnType.refund,
    amount: -100,
    txnAt: '2026-09-02T10:00:00+08:00',
  );
}

void main() {
  late AppDatabase db;

  setUp(() async => db = await openRealTestDatabase());

  test('workspaceDataTables 覆盖 sqlite_master 里所有带 workspace_id 的表', () async {
    final tables = await db
        .customSelect(
          "SELECT m.name AS name FROM sqlite_master AS m WHERE m.type = 'table' "
          'AND EXISTS (SELECT 1 FROM pragma_table_info(m.name) AS c '
          "WHERE c.name = 'workspace_id') ORDER BY m.name",
        )
        .get();
    expect(
      tables.map((r) => r.read<String>('name')).toSet(),
      workspaceDataTables.toSet(),
    );
  });

  test('演示空间写满全部表 → 以真实空间为当前空间，每个仓库的全部查询都为空', () async {
    final real = await createTestWorkspace(db);
    final demoRow = await ensureDemoWorkspace(db);
    final demo = WorkspaceScope(
      db: db,
      workspaceId: demoRow.id,
      clock: demoClock,
    );
    await _enrich(demo);

    final demoIds = await idsByTable(db, demo.workspaceId);
    for (final entry in demoIds.entries) {
      expect(entry.value, isNotEmpty, reason: '演示空间的 ${entry.key} 应有数据');
      _log('演示空间 ${entry.key}: ${entry.value.length} 行');
    }

    final results = await runAllQueries(real, demoIds);
    for (final entry in results.entries) {
      _log('真实空间为当前：${entry.key} → ${entry.value} 行');
      expect(entry.value, 0, reason: entry.key);
    }
    _log('真实空间为当前：共 ${results.length} 条查询，全部为空');
    expect(results.length, greaterThan(40));

    // 写入也不能跨空间：用演示空间的 id 改数据一律"已不存在"，演示数据不变。
    final foreignCard = demoIds['cards']!.first;
    await expectRepositoryError<NotFoundException>(
      () => CardRepository(real).freeze(foreignCard),
    );
    await expectRepositoryError<NotFoundException>(
      () =>
          CreditAccountRepository(real)
              .leavePool(demoIds['credit_accounts']!.first),
    );
    await expectForeignCashWritesRejected(real, demoIds);
    await expectForeignLedgerWritesRejected(real, demoIds);
    expect(await idsByTable(db, demo.workspaceId), demoIds);
  });

  test('反向：真实空间写满全部表 → 以演示空间为当前空间，每个仓库的全部查询都为空', () async {
    final real = await createTestWorkspace(db, clock: demoClock);
    await seedDemoWorkspace(real);
    await _enrich(real);
    final demoRow = await WorkspaceRepository(db).ensure(WorkspaceKind.demo);
    final demo = WorkspaceScope(
      db: db,
      workspaceId: demoRow.id,
      clock: demoClock,
    );

    final realIds = await idsByTable(db, real.workspaceId);
    for (final entry in realIds.entries) {
      expect(entry.value, isNotEmpty, reason: '真实空间的 ${entry.key} 应有数据');
      _log('真实空间 ${entry.key}: ${entry.value.length} 行');
    }
    final results = await runAllQueries(demo, realIds);
    for (final entry in results.entries) {
      _log('演示空间为当前：${entry.key} → ${entry.value} 行');
      expect(entry.value, 0, reason: entry.key);
    }
    _log('演示空间为当前：共 ${results.length} 条查询，全部为空');
    await expectForeignCashWritesRejected(demo, realIds);
    await expectForeignLedgerWritesRejected(demo, realIds);
    expect(await idsByTable(db, real.workspaceId), realIds);
  });

  test('两个空间都有数据：各自只看到自己的行；清除演示数据只删演示空间（含 v4 的全部表）', () async {
    final real = await createTestWorkspace(db);
    await createTestCard(real, bank: '星海银行', last4: '1001');
    final demoRow = await ensureDemoWorkspace(db);
    final demo = WorkspaceScope(
      db: db,
      workspaceId: demoRow.id,
      clock: demoClock,
    );
    await _enrich(demo);

    final realIds = await idsByTable(db, real.workspaceId);
    final demoIds = await idsByTable(db, demo.workspaceId);
    final realWallet = await CardWalletReader(real).load();
    final demoWallet = await CardWalletReader(demo).load();
    expect(realWallet.accounts.map((a) => a.id), realIds['credit_accounts']);
    expect(
      demoWallet.accounts.map((a) => a.id).toSet(),
      demoIds['credit_accounts']!.toSet(),
    );
    // 同名银行、同末四位：只在本空间里提示"可能是同一账户的另一张卡"。
    expect(
      await CardRepository(real)
          .sameBankSameLast4(bankName: '星海银行', last4: '1001'),
      hasLength(1),
    );

    final workspaces = WorkspaceRepository(db);
    await workspaces.setCurrent(demo.workspaceId);
    await workspaces.deleteWorkspace(demo.workspaceId);
    expect(await idsByTable(db, demo.workspaceId), <String, List<String>>{
      for (final t in workspaceDataTables) t: <String>[],
    });
    expect(await idsByTable(db, real.workspaceId), realIds);
    expect(await workspaces.current(), isNull, reason: '删掉的是当前工作空间：当前指针一并清除');
    expect(await workspaces.live(WorkspaceKind.demo), isNull);
    expect(await workspaces.live(WorkspaceKind.real), isNotNull);
  });
}
