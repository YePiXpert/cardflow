// 仓库 → 领域映射与领域包直算逐字段一致（I-1b 简报 §3）：F-01（已确认口径排除预计收入）、F-02（收入
// 延迟 3 天、收入减半的情景）、F-03（两账户隔离）、F-04（快照当天未包含的事件计入；已包含的跳过；
// 同日只有日期时先支出后收入并记假设；全部有时刻时按时刻）、F-05（全部缺口点、距零/距储备）、F-07
// （快照 > 7 天 → 数据问题、"假设分析"，不补零；缺快照的账户不计入、不补零）。
//
// 每个用例用与领域包测试（packages/cardflow_domain/test/cash_test.dart、checks_test.dart）相同的数值
// 写入真实的 sqlite3mc 库：经仓库、`CashForecastReader` 与 `cash_mapping.dart` 映射后调用领域包；
// 另用同样的数值直接构造领域对象调用领域包（事件 id 取库里的 UUID）；两份结果的全部字段（含时间线
// 每个点、假设说明、跳过的事件、缺口的事件列表）必须完全相同，并且等于领域包测试的期望值。
// 设环境变量 CARDFLOW_EVIDENCE=1 时打印两份结果（证据 parity-with-domain.txt）。
import 'dart:io';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/repositories/cash_forecast_reader.dart';
import 'package:cardflow/data/repositories/cash_models.dart';
import 'package:cardflow/data/repositories/scenario_repository.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'repository_test_support.dart';

final bool _evidence = Platform.environment['CARDFLOW_EVIDENCE'] == '1';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

/// 领域包测试的时间线终点。
final LocalDate _horizon = d(2026, 12, 31);

Map<String, Object?> _breach(Breach? b) => b == null
    ? <String, Object?>{'none': true}
    : <String, Object?>{
        'on': '${b.on}',
        'phase': b.phase.code,
        'balance': b.balance,
        'gap_to_zero': b.gapToZero,
        'gap_to_reserve': b.gapToReserve,
        'event_ids': b.eventIds,
      };

/// 一个 [CashReport] 的全部字段（含时间线），规范化 JSON 文本。
String describeReport(CashReport r) {
  final t = r.timeline;
  return canonicalJsonText(<String, Object?>{
    'account': r.account,
    'scenario': r.scenario,
    'ok': r.ok,
    'ok_zero': r.okZero,
    'min_balance': r.minBalance,
    'min_on': '${r.minOn}',
    'breaches': <Object?>[for (final b in r.breaches) _breach(b)],
    'first_breach': _breach(r.firstBreach),
    'first_zero_breach': _breach(r.firstZeroBreach),
    'end_balance': r.endBalance,
    'assumptions': r.assumptions,
    'timeline': <String, Object?>{
      'account': t.account,
      'scenario': t.scenario,
      'snapshot': <String, Object?>{
        'account': t.snapshot.account,
        'balance': t.snapshot.balance,
        'as_of': '${t.snapshot.asOf}',
        'observed_at': t.snapshot.observedAt?.isoformat(),
        'includes': t.snapshot.includesEventIds.toList()..sort(),
      },
      'points': <Object?>[
        for (final p in t.points)
          <Object?>['${p.on}', p.phase.code, p.balance, p.eventIds],
      ],
      'assumptions': t.assumptions,
      'skipped': t.skippedEventIds,
    },
  });
}

String describeIssues(List<DataIssue> issues) => canonicalJsonText(<Object?>[
  for (final i in issues)
    <String, Object?>{
      'code': i.code,
      'account': i.account,
      'card': i.card,
      'pool': i.pool,
      'scenario': i.scenario,
      'as_of': i.asOf?.toString(),
      'age_days': i.ageDays,
      'detail': i.detail,
    },
]);

/// 两份结果逐字段一致；打印证据。
void expectParity(String name, CashReport viaRepository, CashReport direct) {
  final a = describeReport(viaRepository);
  final b = describeReport(direct);
  if (_evidence) {
    // ignore: avoid_print
    print('[$name] 经仓库映射：$a');
    // ignore: avoid_print
    print('[$name] 领域包直算：$b');
    // ignore: avoid_print
    print('[$name] 逐字段一致：${a == b}');
  }
  expect(a, b, reason: name);
}

List<int> lows(Timeline t) => [
  for (final p in t.points)
    if (p.phase == PointPhase.low) p.balance,
];

void main() {
  late AppDatabase db;
  late WorkspaceScope scope;

  setUp(() async {
    db = await openRealTestDatabase();
    scope = await createTestWorkspace(db);
  });

  /// 经仓库读入、映射、调用领域包（窗口截止到 2026-12-31，与领域包测试相同）。
  Future<CashForecast> viaRepository(
    WorkspaceScope scope,
    ScenarioView scenario,
  ) async {
    final reader = CashForecastReader(scope);
    final inputs = await reader.loadInputs();
    return forecastFrom(
      inputs,
      scenario,
      windowDays: _horizon.differenceInDays(inputs.today) + 1,
    );
  }

  Future<ScenarioView> builtin(ScenarioKind kind) async =>
      (await ScenarioRepository(
        scope,
      ).list()).firstWhere((s) => s.kind == kind);

  Snapshot directSnapshot(
    CashSnapshotRow row,
    int balance,
    LocalDate asOf, {
    Set<String> includes = const <String>{},
  }) => Snapshot(
    account: row.cashAccountId,
    balance: balance,
    asOf: asOf,
    observedAt: Timestamp.parse('${asOf}T20:00:00+08:00'),
    includesEventIds: includes,
  );

  group('F-04 快照包含关系与同日顺序', () {
    test('快照当天、未标记为已包含的事件计入当日（并记假设）', () async {
      final acc = await createTestCashAccount(
        scope,
        name: 'main',
        reserve: 200000,
      );
      final x = await addTestCashEvent(scope, acc.id, d(2026, 10, 16), -100000);
      final snap = await recordTestCashSnapshot(
        scope,
        acc.id,
        d(2026, 10, 16),
        500000,
      );
      final baseline = await builtin(ScenarioKind.builtinBaseline);
      final forecast = await viaRepository(scope, baseline);
      final mapped = forecast.accounts.single.report;

      final direct = evaluateAccounts(
        [CashAccount(id: acc.id, name: 'main', reserveFloor: 200000)],
        {acc.id: directSnapshot(snap, 500000, d(2026, 10, 16))},
        [
          CashEvent(
            id: x.id,
            account: acc.id,
            on: d(2026, 10, 16),
            amount: -100000,
            cls: EventClass.confirmed,
            category: 'bill',
          ),
        ],
        Scenario(id: baseline.domainId, description: baseline.name),
        _horizon,
      )[acc.id]!;
      expectParity('F-04 当天未包含', mapped, direct);
      expect(lows(mapped.timeline), [400000]);
      expect(
        mapped.timeline.assumptions.any((a) => a.contains('快照当天')),
        isTrue,
      );
      expect(forecast.assumptions.any((a) => a.contains('快照当天')), isTrue);
    });

    test('快照当天、标记为已包含的事件被跳过', () async {
      final acc = await createTestCashAccount(
        scope,
        name: 'main',
        reserve: 200000,
      );
      final x = await addTestCashEvent(scope, acc.id, d(2026, 10, 16), -100000);
      final snap = await recordTestCashSnapshot(
        scope,
        acc.id,
        d(2026, 10, 16),
        500000,
        included: {x.id},
      );
      final baseline = await builtin(ScenarioKind.builtinBaseline);
      final mapped = (await viaRepository(
        scope,
        baseline,
      )).accounts.single.report;
      final direct = evaluateAccounts(
        [CashAccount(id: acc.id, name: 'main', reserveFloor: 200000)],
        {
          acc.id: directSnapshot(
            snap,
            500000,
            d(2026, 10, 16),
            includes: {x.id},
          ),
        },
        [
          CashEvent(
            id: x.id,
            account: acc.id,
            on: d(2026, 10, 16),
            amount: -100000,
            cls: EventClass.confirmed,
            category: 'bill',
          ),
        ],
        Scenario(id: baseline.domainId, description: baseline.name),
        _horizon,
      )[acc.id]!;
      expectParity('F-04 当天已包含', mapped, direct);
      expect(mapped.timeline.skippedEventIds, [x.id]);
      expect(mapped.timeline.points.last.balance, 500000);
    });

    test('同日只有日期：先支出后收入，捕捉当日最低点并记假设', () async {
      final acc = await createTestCashAccount(
        scope,
        name: 'main',
        reserve: 200000,
      );
      final snap = await recordTestCashSnapshot(
        scope,
        acc.id,
        d(2026, 10, 1),
        100000,
      );
      final into = await addTestCashEvent(
        scope,
        acc.id,
        d(2026, 10, 5),
        300000,
      );
      final out = await addTestCashEvent(
        scope,
        acc.id,
        d(2026, 10, 5),
        -250000,
      );
      final baseline = await builtin(ScenarioKind.builtinBaseline);
      final mapped = (await viaRepository(
        scope,
        baseline,
      )).accounts.single.report;
      final direct = evaluateAccounts(
        [CashAccount(id: acc.id, name: 'main', reserveFloor: 200000)],
        {acc.id: directSnapshot(snap, 100000, d(2026, 10, 1))},
        [
          CashEvent(
            id: into.id,
            account: acc.id,
            on: d(2026, 10, 5),
            amount: 300000,
            cls: EventClass.confirmed,
            category: 'income',
          ),
          CashEvent(
            id: out.id,
            account: acc.id,
            on: d(2026, 10, 5),
            amount: -250000,
            cls: EventClass.confirmed,
            category: 'bill',
          ),
        ],
        Scenario(id: baseline.domainId, description: baseline.name),
        _horizon,
      )[acc.id]!;
      expectParity('F-04 先支出后收入', mapped, direct);
      final low = {
        for (final p in mapped.timeline.points)
          if (p.phase == PointPhase.low) p.on: p.balance,
      };
      expect(low[d(2026, 10, 5)], -150000);
      expect(mapped.timeline.points.last.balance, 150000);
      expect(
        mapped.timeline.assumptions.any((a) => a.contains('同日收支顺序未知')),
        isTrue,
      );
    });

    test('情景按时刻排序且当日事件都有时刻：按时刻（无假设）', () async {
      final acc = await createTestCashAccount(
        scope,
        name: 'main',
        reserve: 200000,
      );
      final snap = await recordTestCashSnapshot(
        scope,
        acc.id,
        d(2026, 10, 1),
        100000,
      );
      final into = await addTestCashEvent(
        scope,
        acc.id,
        d(2026, 10, 5),
        300000,
        at: Timestamp.parse('2026-10-05T09:00:00Z'),
      );
      final out = await addTestCashEvent(
        scope,
        acc.id,
        d(2026, 10, 5),
        -250000,
        at: Timestamp.parse('2026-10-05T15:00:00Z'),
      );
      final row = await ScenarioRepository(scope).create(
        const ScenarioDraft(
          name: '按时刻',
          sameDayOrder: SameDayOrderChoice.timestamp,
        ),
      );
      final ts = ScenarioView.fromRow(row);
      final mapped = (await viaRepository(scope, ts)).accounts.single.report;
      final direct = evaluateAccounts(
        [CashAccount(id: acc.id, name: 'main', reserveFloor: 200000)],
        {acc.id: directSnapshot(snap, 100000, d(2026, 10, 1))},
        [
          CashEvent(
            id: into.id,
            account: acc.id,
            on: d(2026, 10, 5),
            amount: 300000,
            cls: EventClass.confirmed,
            category: 'income',
            at: Timestamp.parse('2026-10-05T09:00:00Z'),
          ),
          CashEvent(
            id: out.id,
            account: acc.id,
            on: d(2026, 10, 5),
            amount: -250000,
            cls: EventClass.confirmed,
            category: 'bill',
            at: Timestamp.parse('2026-10-05T15:00:00Z'),
          ),
        ],
        Scenario(
          id: row.id,
          sameDayOrder: SameDayOrder.timestamp,
          description: '按时刻',
        ),
        _horizon,
      )[acc.id]!;
      expectParity('F-04 按时刻', mapped, direct);
      final low = {
        for (final p in mapped.timeline.points)
          if (p.phase == PointPhase.low) p.on: p.balance,
      };
      expect(low[d(2026, 10, 5)], 100000);
      expect(mapped.timeline.assumptions, isEmpty);
    });
  });

  group('F-01/F-02 已确认口径与收入延迟情景', () {
    late CashAccountRow acc;
    late CashSnapshotRow snap;
    late CashEventRow pay;
    late CashEventRow bill;

    setUp(() async {
      acc = await createTestCashAccount(scope, name: 'main', reserve: 200000);
      snap = await recordTestCashSnapshot(
        scope,
        acc.id,
        d(2026, 10, 1),
        100000,
      );
      pay = await addTestCashEvent(
        scope,
        acc.id,
        d(2026, 11, 6),
        850000,
        cls: CashEventClass.expected,
      );
      bill = await addTestCashEvent(scope, acc.id, d(2026, 11, 8), -500000);
    });

    List<CashEvent> directEvents() => [
      CashEvent(
        id: pay.id,
        account: acc.id,
        on: d(2026, 11, 6),
        amount: 850000,
        cls: EventClass.expected,
        category: 'income',
      ),
      CashEvent(
        id: bill.id,
        account: acc.id,
        on: d(2026, 11, 8),
        amount: -500000,
        cls: EventClass.confirmed,
        category: 'bill',
      ),
    ];

    test('F-01：内置"已确认"口径排除全部预计收入', () async {
      final confirmed = await builtin(ScenarioKind.builtinConfirmed);
      expect(confirmed.params.includeExpected, isFalse);
      final mapped = (await viaRepository(
        scope,
        confirmed,
      )).accounts.single.report;
      final direct = evaluateAccounts(
        [CashAccount(id: acc.id, name: 'main', reserveFloor: 200000)],
        {acc.id: directSnapshot(snap, 100000, d(2026, 10, 1))},
        directEvents(),
        Scenario(
          id: confirmed.domainId,
          includeExpected: false,
          description: confirmed.name,
        ),
        _horizon,
      )[acc.id]!;
      expectParity('F-01 已确认口径', mapped, direct);
      expect(mapped.timeline.points.last.balance, -400000);
      expect(
        mapped.timeline.points.expand((p) => p.eventIds),
        isNot(contains(pay.id)),
      );
    });

    test('F-02：压力情景（收入延迟 3 天、收入减半）的日终余额按期望变化', () async {
      final row = await ScenarioRepository(scope).create(
        ScenarioDraft(
          name: '收入推迟',
          incomeDelayDays: 3,
          incomeScale: Rational.parseDecimal('0.5'),
        ),
      );
      final stress = ScenarioView.fromRow(row);
      expect(row.incomeScale, '0.5');
      final mapped = (await viaRepository(
        scope,
        stress,
      )).accounts.single.report;
      final direct = evaluateAccounts(
        [CashAccount(id: acc.id, name: 'main', reserveFloor: 200000)],
        {acc.id: directSnapshot(snap, 100000, d(2026, 10, 1))},
        directEvents(),
        Scenario(
          id: row.id,
          incomeDelayDays: 3,
          incomeScale: Rational.parseDecimal('0.5'),
          description: '收入推迟',
        ),
        _horizon,
      )[acc.id]!;
      expectParity('F-02 收入延迟 3 天', mapped, direct);
      expect(
        [
          for (final p in mapped.timeline.points)
            if (p.phase == PointPhase.end) (p.on, p.balance),
        ],
        [(d(2026, 11, 8), -400000), (d(2026, 11, 9), 25000)],
      );
      // 基准口径：收入在 11-08 之前到账，最低现金是快照余额 1,000；延迟 3 天后 11-08 降到 −4,000。
      final baseline = (await viaRepository(
        scope,
        await builtin(ScenarioKind.builtinBaseline),
      )).accounts.single.report;
      expect(baseline.minBalance, 100000);
      expect(mapped.minBalance, -400000);
      expect(mapped.minOn, d(2026, 11, 8));
    });
  });

  test('F-05：列出全部缺口点与距零/距储备两种缺口，最低点与首个低于零的点', () async {
    final acc = await createTestCashAccount(
      scope,
      name: 'main',
      reserve: 200000,
    );
    final snap = await recordTestCashSnapshot(
      scope,
      acc.id,
      d(2026, 10, 1),
      300000,
    );
    final a = await addTestCashEvent(scope, acc.id, d(2026, 10, 5), -200000);
    final b = await addTestCashEvent(scope, acc.id, d(2026, 10, 9), -300000);
    final c = await addTestCashEvent(scope, acc.id, d(2026, 10, 12), 100000);
    final baseline = await builtin(ScenarioKind.builtinBaseline);
    final forecast = await viaRepository(scope, baseline);
    final mapped = forecast.accounts.single.report;
    final direct = evaluateAccounts(
      [CashAccount(id: acc.id, name: 'main', reserveFloor: 200000)],
      {acc.id: directSnapshot(snap, 300000, d(2026, 10, 1))},
      [
        CashEvent(
          id: a.id,
          account: acc.id,
          on: d(2026, 10, 5),
          amount: -200000,
          cls: EventClass.confirmed,
          category: 'bill',
        ),
        CashEvent(
          id: b.id,
          account: acc.id,
          on: d(2026, 10, 9),
          amount: -300000,
          cls: EventClass.confirmed,
          category: 'bill',
        ),
        CashEvent(
          id: c.id,
          account: acc.id,
          on: d(2026, 10, 12),
          amount: 100000,
          cls: EventClass.confirmed,
          category: 'income',
        ),
      ],
      Scenario(id: baseline.domainId, description: baseline.name),
      _horizon,
    )[acc.id]!;
    expectParity('F-05 全部缺口点', mapped, direct);
    expect(mapped.ok, isFalse);
    expect(
      [for (final x in mapped.breaches) x.on],
      [d(2026, 10, 5), d(2026, 10, 9)],
    );
    expect(
      (mapped.breaches[0].gapToZero, mapped.breaches[0].gapToReserve),
      (0, 100000),
    );
    expect(
      (mapped.breaches[1].gapToZero, mapped.breaches[1].gapToReserve),
      (200000, 400000),
    );
    expect(mapped.minBalance, -200000);
    expect(mapped.firstZeroBreach!.on, d(2026, 10, 9));
    // 读模型：缺口列表与摘要来自同一份结果。
    expect(forecast.gaps.map((g) => g.breach.on), [
      d(2026, 10, 5),
      d(2026, 10, 9),
    ]);
    final summary = forecast.summaries.single;
    expect(summary.gapCount, 2);
    expect(summary.lowestBalance, -200000);
    expect(summary.marginToZero, -200000);
    expect(summary.marginToReserve, -400000);
    expect(summary.firstGap!.breach.on, d(2026, 10, 5));
    final day9 = forecast.accounts.single.days.firstWhere(
      (r) => r.on == d(2026, 10, 9),
    );
    expect(
      (day9.outflow, day9.inflow, day9.low, day9.gap),
      (-300000, 0, -200000, true),
    );
  });

  test('F-03：两账户隔离，另一个账户的余额从不抵补本账户的扣款', () async {
    final m = await createTestCashAccount(scope, name: 'main', reserve: 200000);
    final o = await createTestCashAccount(scope, name: 'other');
    final sm = await recordTestCashSnapshot(
      scope,
      m.id,
      d(2026, 10, 1),
      100000,
    );
    final so = await recordTestCashSnapshot(
      scope,
      o.id,
      d(2026, 10, 1),
      10000000,
    );
    final x = await addTestCashEvent(scope, m.id, d(2026, 10, 3), -500000);
    final baseline = await builtin(ScenarioKind.builtinBaseline);
    final forecast = await viaRepository(scope, baseline);
    final direct = evaluateAccounts(
      [
        CashAccount(id: m.id, name: 'main', reserveFloor: 200000),
        CashAccount(id: o.id, name: 'other'),
      ],
      {
        m.id: directSnapshot(sm, 100000, d(2026, 10, 1)),
        o.id: directSnapshot(so, 10000000, d(2026, 10, 1)),
      },
      [
        CashEvent(
          id: x.id,
          account: m.id,
          on: d(2026, 10, 3),
          amount: -500000,
          cls: EventClass.confirmed,
          category: 'bill',
        ),
      ],
      Scenario(id: baseline.domainId, description: baseline.name),
      _horizon,
    );
    expect(forecast.accounts.map((a) => a.account.id), [m.id, o.id]);
    expectParity('F-03 账户 main', forecast.accounts[0].report, direct[m.id]!);
    expectParity('F-03 账户 other', forecast.accounts[1].report, direct[o.id]!);
    expect(forecast.accounts[0].report.ok, isFalse);
    expect(forecast.accounts[1].report.ok, isTrue);
    // 摘要的最低点是"最差的那个账户"的最低点，而不是两个账户的合计。
    expect(forecast.summaries.single.lowest.account.id, m.id);
    expect(forecast.summaries.single.lowestBalance, -400000);
  });

  test(
    'F-07：快照 14 天前 → STALE_SNAPSHOT（与领域包直算一致）、"假设分析"；不补零；缺快照的账户不计入',
    () async {
      // 真实空间的时钟：北京时间 2026-10-30 12:00（判断陈旧）。
      final clock = StaleAwareClock(DateTime.utc(2026, 10, 30, 4));
      final stale = WorkspaceScope(
        db: db,
        workspaceId: scope.workspaceId,
        clock: clock,
      );
      final acc = await createTestCashAccount(
        stale,
        name: '主现金账户',
        reserve: 200000,
      );
      final missing = await createTestCashAccount(stale, name: '新账户');
      final snap = await recordTestCashSnapshot(
        stale,
        acc.id,
        d(2026, 10, 16),
        500000,
      );
      // F-18 回归样本的事件（engine-spec §9）。
      final rows = <CashEventRow>[];
      final events = <CashEvent>[];
      for (final (on, amount, cls, type)
          in <(LocalDate, int, CashEventClass, CashPlanType)>[
            (
              d(2026, 10, 27),
              -100000,
              CashEventClass.confirmed,
              CashPlanType.living,
            ),
            (
              d(2026, 10, 28),
              -100000,
              CashEventClass.confirmed,
              CashPlanType.debt,
            ),
            (
              d(2026, 11, 6),
              850000,
              CashEventClass.expected,
              CashPlanType.income,
            ),
            (
              d(2026, 11, 8),
              -500000,
              CashEventClass.confirmed,
              CashPlanType.debt,
            ),
            (
              d(2026, 11, 16),
              -350000,
              CashEventClass.confirmed,
              CashPlanType.debt,
            ),
            (
              d(2026, 11, 20),
              700000,
              CashEventClass.expected,
              CashPlanType.income,
            ),
            (
              d(2026, 11, 22),
              -200000,
              CashEventClass.confirmed,
              CashPlanType.living,
            ),
            (
              d(2026, 11, 26),
              500000,
              CashEventClass.expected,
              CashPlanType.income,
            ),
          ]) {
        final row = await addTestCashEvent(
          stale,
          acc.id,
          on,
          amount,
          cls: cls,
          type: type,
        );
        rows.add(row);
        events.add(
          CashEvent(
            id: row.id,
            account: acc.id,
            on: on,
            amount: amount,
            cls: cls == CashEventClass.expected
                ? EventClass.expected
                : EventClass.confirmed,
            category: type.category.code,
          ),
        );
      }
      final inputs = await CashForecastReader(stale).loadInputs();
      final directIssues = dataIssues(
        ModelInputs(
          request: PlanRequest(
            amount: 1,
            currency: 'CNY',
            txnDate: d(2026, 10, 30),
          ),
          cards: const <CardOption>[],
          pools: const <String, int>{},
          accounts: [
            CashAccount(id: acc.id, name: '主现金账户', reserveFloor: 200000),
            CashAccount(id: missing.id, name: '新账户'),
          ],
          snapshots: {acc.id: directSnapshot(snap, 500000, d(2026, 10, 16))},
          events: events,
          horizonEnd: d(2027, 4, 28),
        ),
        7,
      );
      final mappedIssues = describeIssues(inputs.issues);
      if (_evidence) {
        // ignore: avoid_print
        print('[F-07 数据问题] 经仓库映射：$mappedIssues');
        // ignore: avoid_print
        print('[F-07 数据问题] 领域包直算：${describeIssues(directIssues)}');
        // ignore: avoid_print
        print(
          '[F-07 数据问题] 逐字段一致：${mappedIssues == describeIssues(directIssues)}',
        );
      }
      expect(mappedIssues, describeIssues(directIssues));
      expect(
        [for (final i in inputs.issues) (i.code, i.account, i.ageDays)],
        [
          ('STALE_SNAPSHOT', acc.id, 14),
          ('MISSING_SNAPSHOT', missing.id, null),
        ],
      );
      expect(inputs.missingSnapshot.map((a) => a.id), [missing.id]);

      final baseline = (await ScenarioRepository(stale).list())[1];
      final forecast = forecastFrom(
        inputs,
        baseline,
        windowDays: d(2027, 1, 14).differenceInDays(inputs.today) + 1,
      );
      final direct = evaluateAccounts(
        [CashAccount(id: acc.id, name: '主现金账户', reserveFloor: 200000)],
        {acc.id: directSnapshot(snap, 500000, d(2026, 10, 16))},
        events,
        Scenario(id: baseline.domainId, description: baseline.name),
        d(2027, 1, 14),
      )[acc.id]!;
      expect(forecast.accounts.map((a) => a.account.id), [
        acc.id,
      ], reason: '缺快照的账户不计入');
      expectParity('F-07 陈旧快照照常计算', forecast.accounts.single.report, direct);
      // 不补零：时间线从快照余额 5,000 起算；基准口径最低 3,000（10-28、11-16）。
      expect(
        forecast.accounts.single.report.timeline.points.first.balance,
        500000,
      );
      expect(forecast.accounts.single.report.minBalance, 300000);
      expect(forecast.accounts.single.stale, isTrue);
      expect(forecast.accounts.single.ageDays, 14);
      expect(forecast.assumptionAnalysis, isTrue);
      expect(forecast.assumptions.any((a) => a.contains('假设分析')), isTrue);
    },
  );
}
