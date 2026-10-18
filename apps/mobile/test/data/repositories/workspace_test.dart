// 工作空间与演示数据（真实 sqlite3mc）：当前工作空间指针、真实/演示各一个、演示合成数据体现
// F-21/F-22/F-23/F-26/F-27 且账期与回归样本一致、清除演示数据。
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/demo/demo_workspace.dart';
import 'package:cardflow/data/mapping/domain_mapping.dart';
import 'package:cardflow/data/repositories/card_wallet_reader.dart';
import 'package:cardflow/data/repositories/cash_event_repository.dart';
import 'package:cardflow/data/repositories/cash_forecast_reader.dart';
import 'package:cardflow/data/repositories/models.dart';
import 'package:cardflow/data/repositories/recurring_item_repository.dart';
import 'package:cardflow/data/repositories/scenario_repository.dart';
import 'package:cardflow/data/repositories/workspace_repository.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow/data/time/clock.dart';
import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate;
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';

import 'repository_test_support.dart';

void main() {
  late AppDatabase db;
  late WorkspaceRepository workspaces;

  setUp(() async {
    db = await openRealTestDatabase();
    workspaces = WorkspaceRepository(db, clock: testClock);
  });

  test('新库没有工作空间；真实/演示各最多一个；当前指针可设可清', () async {
    expect(await workspaces.current(), isNull);
    final real = await workspaces.ensure(WorkspaceKind.real);
    expect(await workspaces.ensure(WorkspaceKind.real), real);
    expect(real.name, '我的数据');
    expect(await workspaces.current(), isNull, reason: 'ensure 不改变当前工作空间');
    await workspaces.setCurrent(real.id);
    expect((await workspaces.current())!.id, real.id);
    final demo = await workspaces.ensure(WorkspaceKind.demo);
    expect(demo.id, isNot(real.id));
    await workspaces.setCurrent(demo.id);
    expect((await workspaces.current())!.kind, 'demo');
    await workspaces.setCurrent(null);
    expect(await workspaces.current(), isNull);
  });

  group('演示数据（固定今天 2026-10-16）', () {
    late WorkspaceScope demo;
    late WalletView wallet;

    setUp(() async {
      final row = await ensureDemoWorkspace(db);
      demo = WorkspaceScope(db: db, workspaceId: row.id, clock: demoClock);
      wallet = await CardWalletReader(demo).load();
    });

    AccountView named(String name) =>
        wallet.accounts.firstWhere((a) => a.displayName == name);

    test('再次进入演示不会重复生成', () async {
      final again = await ensureDemoWorkspace(db);
      expect(again.id, demo.workspaceId);
      expect((await CardWalletReader(demo).load()).accounts, hasLength(4));
    });

    test('卡 A/B/C 属于三个不同银行；A 的主卡与附属卡同一信用账户（F-21）', () {
      expect(wallet.accounts.map((a) => a.displayName), <String>[
        '卡 A',
        '卡 B',
        '卡 D',
        '卡 C',
      ]);
      expect(<String>{
        named('卡 A').bank.name,
        named('卡 B').bank.name,
        named('卡 C').bank.name,
      }, hasLength(3));
      final a = named('卡 A');
      expect(a.cards.map((c) => (c.last4, c.kind)), <(String, HolderKind)>[
        ('1001', HolderKind.primary),
        ('1002', HolderKind.supplementary),
      ]);
      expect(a.currencies, hasLength(1));
    });

    test('账期与回归样本一致（交易日 10-16 当天入账）', () {
      String cycle(String name) {
        final f = named(name).forecast as ForecastPredicted;
        return '${f.conservative.statementDate}/${f.conservative.dueDate}';
      }

      expect(cycle('卡 A'), '2026-11-10/2026-11-28');
      expect(cycle('卡 B'), '2026-10-20/2026-11-08');
      expect(cycle('卡 C'), '2026-11-05/2026-11-25');
      expect(cycle('卡 D'), '2026-11-15/2026-12-05');
      expect(named('卡 A').today, LocalDate(2026, 10, 16));
    });

    test('B 与 D：同一银行的两个独立授信（F-22）共享池（F-23），D 超限（F-26），B 有临时额度（F-27）', () {
      final b = named('卡 B');
      final dAccount = named('卡 D');
      expect(b.bank.id, dAccount.bank.id);
      expect(b.id, isNot(dAccount.id));
      final pool = wallet.pools.single;
      expect(pool.pool.name, '乙行共享额度');
      expect(pool.members.map((m) => m.displayName), <String>['卡 B', '卡 D']);
      expect(pool.usedTotal, 520000);
      expect(pool.rawAvailable, 1480000);
      expect(pool.combinedCapacity, 1480000);
      expect(b.primaryCurrency.ownCapacity, 1500000);
      expect(b.primaryCurrency.capacity, 1480000, reason: '池层容量限制了 B');
      expect(dAccount.primaryCurrency.availableToday, -20000);
      expect(dAccount.primaryCurrency.overLimit, isTrue);
      expect(dAccount.primaryCurrency.capacity, 0);
      final temp = b.primaryCurrency.latestSnapshot!;
      expect(temp.tempMinor, 500000);
      expect(temp.tempExpiresOn, '2026-11-15');
    });

    test('现金：工资卡计入、受限的定期存款不计入；基准口径 30 天内一个可见缺口（11-01 余额 300 低于储备 2,000）；'
        '已确认与压力口径更差；快照包含、周期事项与覆盖、调拨、压力情景与计算版本都有', () async {
      final inputs = await CashForecastReader(demo).loadInputs();
      expect(inputs.accountRows.map((a) => a.name), <String>['工资卡', '定期存款']);
      expect(inputs.counted.map((a) => a.name), <String>['工资卡']);
      expect(inputs.excluded.map((a) => a.name), <String>['定期存款']);
      expect(inputs.issues, isEmpty, reason: '演示空间不判陈旧，没有缺快照');
      final scenarios = await ScenarioRepository(demo).list();
      expect(scenarios.map((s) => s.name), <String>['已确认', '基准预期', '收入推迟 3 天']);

      final baseline = forecastFrom(inputs, scenarios[1], windowDays: 30);
      expect(
        baseline.gaps.map(
          (g) => (g.breach.on, g.breach.balance, g.breach.gapToReserve),
        ),
        <(LocalDate, int, int)>[(LocalDate(2026, 11, 1), 30000, 170000)],
      );
      expect(baseline.summaries.single.lowestBalance, 30000);
      expect(baseline.summaries.single.lowestOn, LocalDate(2026, 11, 1));
      expect(
        baseline.assumptions.any((a) => a.contains('快照当天未标记为已包含的事件')),
        isTrue,
        reason: '水电费在快照当天、未包含',
      );
      final confirmed = forecastFrom(inputs, scenarios[0], windowDays: 30);
      expect(
        confirmed.gaps.map((g) => (g.breach.on, g.breach.balance)),
        <(LocalDate, int)>[
          (LocalDate(2026, 11, 1), 30000),
          (LocalDate(2026, 11, 8), -470000),
        ],
      );
      final stress = forecastFrom(inputs, scenarios[2], windowDays: 30);
      expect(stress.gaps.map((g) => g.breach.on), <LocalDate>[
        LocalDate(2026, 11, 1),
        LocalDate(2026, 11, 8),
      ]);

      final rent = (await RecurringItemRepository(demo).list()).single;
      final occurrences = await RecurringItemRepository(demo)
          .occurrences(rent.id);
      expect(
        occurrences
            .firstWhere((o) => o.key == LocalDate(2026, 12, 27))
            .event!
            .amountMinor,
        -120000,
      );
      expect(await CashEventRepository(demo).transfers(), hasLength(1));
      final board = await ScenarioBoard.load(demo);
      expect(board.items.map((i) => i.runs.length), <int>[0, 1, 1]);
      expect(board.items.every((i) => !i.stale), isTrue);
    });

    test('A 8,000、C 6,000 与回归样本的可用额一致；演示空间不判陈旧', () {
      expect(named('卡 A').primaryCurrency.capacity, 800000);
      expect(named('卡 C').primaryCurrency.capacity, 600000);
      for (final account in wallet.accounts) {
        expect(account.primaryCurrency.snapshotAgeDays, 1);
        expect(account.primaryCurrency.stale, isFalse);
        expect(account.ruleSource, RuleSource.userDeclared);
      }
    });
  });

  test('清除演示数据：演示空间的全部行与工作空间本身都删除，真实空间不受影响', () async {
    final real = await workspaces.ensure(WorkspaceKind.real);
    final realScope = WorkspaceScope(
      db: db,
      workspaceId: real.id,
      clock: testClock,
    );
    await createTestCard(realScope);
    final demo = await ensureDemoWorkspace(db);
    await workspaces.deleteWorkspace(demo.id);
    for (final table in workspaceDataTables) {
      final rows = await db
          .customSelect(
            'SELECT COUNT(*) AS n FROM $table WHERE workspace_id = ?',
            variables: [Variable<String>(demo.id)],
          )
          .getSingle();
      expect(rows.read<int>('n'), 0, reason: table);
    }
    expect(await workspaces.live(WorkspaceKind.demo), isNull);
    expect((await CardWalletReader(realScope).load()).accounts, hasLength(1));
    // 再次进入演示：重新生成一份（新的工作空间 id）。
    final again = await ensureDemoWorkspace(db);
    expect(again.id, isNot(demo.id));
  });
}
