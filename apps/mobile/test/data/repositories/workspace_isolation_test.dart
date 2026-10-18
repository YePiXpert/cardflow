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
import 'package:cardflow/data/repositories/credit_account_repository.dart';
import 'package:cardflow/data/repositories/credit_pool_repository.dart';
import 'package:cardflow/data/repositories/limit_snapshot_repository.dart';
import 'package:cardflow/data/repositories/models.dart';
import 'package:cardflow/data/repositories/repository_errors.dart';
import 'package:cardflow/data/repositories/workspace_repository.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow/data/time/clock.dart';
import 'package:cardflow_domain/cardflow_domain.dart' show DueRule, LocalDate;
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

/// 某工作空间里全部业务行的 id（按表）。
Future<Map<String, List<String>>> idsByTable(
  AppDatabase db,
  String workspaceId,
) async => <String, List<String>>{
  for (final table in workspaceDataTables)
    table:
        (await db
                .customSelect(
                  'SELECT id FROM $table WHERE workspace_id = ? ORDER BY id',
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
  for (final bank in <String>['演示银行甲', '演示银行乙', '演示银行丙']) {
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
  return results;
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
  });

  test('两个空间都有数据：各自只看到自己的行；清除演示数据只删演示空间', () async {
    final real = await createTestWorkspace(db);
    await createTestCard(real, bank: '演示银行甲', last4: '1001');
    final demoRow = await ensureDemoWorkspace(db);
    final demo = WorkspaceScope(
      db: db,
      workspaceId: demoRow.id,
      clock: demoClock,
    );

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
          .sameBankSameLast4(bankName: '演示银行甲', last4: '1001'),
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
