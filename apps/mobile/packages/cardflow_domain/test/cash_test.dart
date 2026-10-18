// 移植自 services/api/tests/engine/test_cash.py（9 项）：断言与期望值不变。
// 另：时间线假设说明的中文模板与 cash.py 逐字一致（读取 Python 源码比对；parity 要求输出逐字节相同）。
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:test/test.dart';

import 'support/repo.dart';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

const acc = CashAccount(id: 'm', name: 'main', reserveFloor: 200000);
final sc = Scenario(id: 'base');
final horizon = d(2026, 12, 31);

CashEvent ev(
  String id,
  LocalDate on,
  int amount, {
  EventClass cls = EventClass.confirmed,
  String category = 'bill',
  Timestamp? at,
}) => CashEvent(
  id: id,
  account: 'm',
  on: on,
  amount: amount,
  cls: cls,
  category: category,
  at: at,
);

Snapshot snap(int balance, LocalDate asOf, {Set<String> includes = const {}}) =>
    Snapshot(
      account: 'm',
      balance: balance,
      asOf: asOf,
      includesEventIds: includes,
    );

List<int> lows(Timeline t) => [
  for (final p in t.points)
    if (p.phase == PointPhase.low) p.balance,
];

void main() {
  group('test_cash.py', () {
    test('a same-day event not in the snapshot is applied', () {
      final tl = buildTimeline(
        acc,
        snap(500000, d(2026, 10, 16)),
        [ev('x', d(2026, 10, 16), -100000)],
        sc,
        horizon,
      );
      expect(lows(tl), [400000]);
      expect(tl.assumptions.any((a) => a.contains('快照当天')), isTrue);
    });

    test('a same-day event marked as included is skipped', () {
      final tl = buildTimeline(
        acc,
        snap(500000, d(2026, 10, 16), includes: {'x'}),
        [ev('x', d(2026, 10, 16), -100000)],
        sc,
        horizon,
      );
      expect(tl.skippedEventIds, ['x']);
      expect(tl.points.last.balance, 500000);
    });

    test('conservative same-day order captures the intraday low', () {
      final tl = buildTimeline(
        acc,
        snap(100000, d(2026, 10, 1)),
        [
          ev('in', d(2026, 10, 5), 300000, category: 'income'),
          ev('out', d(2026, 10, 5), -250000),
        ],
        sc,
        horizon,
      );
      final low = {
        for (final p in tl.points)
          if (p.phase == PointPhase.low) p.on: p.balance,
      };
      expect(low[d(2026, 10, 5)], -150000);
      expect(tl.points.last.balance, 150000);
      expect(tl.assumptions.any((a) => a.contains('同日收支顺序未知')), isTrue);
    });

    test('timestamp order when all events are timed', () {
      final tl = buildTimeline(
        acc,
        snap(100000, d(2026, 10, 1)),
        [
          ev(
            'in',
            d(2026, 10, 5),
            300000,
            category: 'income',
            at: Timestamp.parse('2026-10-05T09:00:00Z'),
          ),
          ev(
            'out',
            d(2026, 10, 5),
            -250000,
            at: Timestamp.parse('2026-10-05T15:00:00Z'),
          ),
        ],
        Scenario(id: 'ts', sameDayOrder: SameDayOrder.timestamp),
        horizon,
      );
      final low = {
        for (final p in tl.points)
          if (p.phase == PointPhase.low) p.on: p.balance,
      };
      expect(low[d(2026, 10, 5)], 100000);
      expect(tl.assumptions, isEmpty);
    });

    test('expected income: excluded when confirmed-only, delayed and scaled under stress', () {
      final evs = [
        ev(
          'pay',
          d(2026, 11, 6),
          850000,
          cls: EventClass.expected,
          category: 'income',
        ),
        ev('b', d(2026, 11, 8), -500000),
      ];
      final conf = buildTimeline(
        acc,
        snap(100000, d(2026, 10, 1)),
        evs,
        Scenario(id: 'c', includeExpected: false),
        horizon,
      );
      expect(conf.points.last.balance, -400000);
      final stress = buildTimeline(
        acc,
        snap(100000, d(2026, 10, 1)),
        evs,
        Scenario(
          id: 's',
          incomeDelayDays: 3,
          incomeScale: Rational.parseDecimal('0.5'),
        ),
        horizon,
      );
      expect(
        [
          for (final p in stress.points)
            if (p.phase == PointPhase.end) (p.on, p.balance),
        ],
        [(d(2026, 11, 8), -400000), (d(2026, 11, 9), 25000)],
      );
    });

    test('evaluate reports every breach and both gaps', () {
      final rep = evaluate(
        buildTimeline(
          acc,
          snap(300000, d(2026, 10, 1)),
          [
            ev('a', d(2026, 10, 5), -200000),
            ev('b', d(2026, 10, 9), -300000),
            ev('c', d(2026, 10, 12), 100000, category: 'income'),
          ],
          sc,
          horizon,
        ),
        acc.reserveFloor,
      );
      expect(rep.ok, isFalse);
      expect(
        [for (final b in rep.breaches) b.on],
        [d(2026, 10, 5), d(2026, 10, 9)],
      );
      expect(
        (rep.breaches[0].gapToZero, rep.breaches[0].gapToReserve),
        (0, 100000),
      );
      expect(
        (rep.breaches[1].gapToZero, rep.breaches[1].gapToReserve),
        (200000, 400000),
      );
      expect(rep.minBalance, -200000);
      expect(rep.firstZeroBreach!.on, d(2026, 10, 9));
    });

    test('accounts are isolated', () {
      const other = CashAccount(id: 'o', name: 'other');
      final reports = evaluateAccounts(
        [acc, other],
        {
          'm': snap(100000, d(2026, 10, 1)),
          'o': Snapshot(account: 'o', balance: 10000000, asOf: d(2026, 10, 1)),
        },
        [ev('x', d(2026, 10, 3), -500000)],
        sc,
        horizon,
      );
      // 另一个账户的余额从不抵补 m 的扣款
      expect(reports['m']!.ok, isFalse);
      expect(reports['o']!.ok, isTrue);
    });

    test(
      'a snapshot below the reserve is a baseline breach even without events',
      () {
        final rep = evaluate(
          buildTimeline(
            acc,
            snap(100000, d(2026, 10, 1)),
            const [],
            sc,
            horizon,
          ),
          acc.reserveFloor,
        );
        expect(rep.ok, isFalse);
        expect(rep.breaches[0].phase, PointPhase.snapshot);
        expect(rep.breaches[0].gapToReserve, 100000);
        expect(rep.okZero, isTrue);
      },
    );

    test(
      'an inflow-only day adds no breach entry, but min and end are visible',
      () {
        final rep = evaluate(
          buildTimeline(
            acc,
            snap(300000, d(2026, 10, 1)),
            [
              ev('a', d(2026, 10, 5), -600000),
              ev('c', d(2026, 10, 12), 100000, category: 'income'),
            ],
            sc,
            horizon,
          ),
          acc.reserveFloor,
        );
        expect([for (final b in rep.breaches) b.on], [d(2026, 10, 5)]);
        expect(rep.minBalance, -300000);
        expect(rep.endBalance, -200000);
        expect(rep.ok, isFalse);
      },
    );
  });

  test(
    'assumption texts are the f-strings of cash.py, character for character',
    () {
      final source = engineSource('cash.py');
      final templates = [
        for (final m in RegExp(
          r'assumptions\.append\(f"([^"]*)"\)',
        ).allMatches(source))
          m.group(1)!,
      ];
      expect(templates, hasLength(4));
      final asOf = d(2026, 10, 16);
      // 触发全部四条：移到快照日之前、快照当天未包含、计划还款排最前、同日收支顺序未知
      final early = Scenario(
        id: 'early',
        sameDayOrder: SameDayOrder.timestamp,
        eventOverrides: {'moved': EventOverride(on: d(2026, 10, 1))},
      );
      final timed = Timestamp.parse('2026-10-20T09:00:00+08:00');
      final tl = buildTimeline(
        acc,
        snap(500000, asOf),
        [
          ev('today', asOf, -1000),
          ev('moved', d(2026, 10, 30), -1000),
          ev('t1', d(2026, 10, 20), 5000, category: 'income', at: timed),
          ev('c1', d(2026, 10, 25), 5000, category: 'income'),
          ev('c2', d(2026, 10, 25), -2000),
        ],
        early,
        horizon,
        planned: [
          CashEvent(
            id: 'plan_repay_A',
            account: 'm',
            on: d(2026, 10, 20),
            amount: -100,
            cls: EventClass.planned,
            category: 'repayment',
          ),
        ],
      );
      String fill(String template, Map<String, String> values) =>
          template.replaceAllMapped(
            RegExp(r'\{([a-z_.]+)\}'),
            (m) => values[m.group(1)!]!,
          );
      expect(tl.assumptions, [
        fill(templates[0], {'t.id': 'moved', 'as_of': '2026-10-16'}),
        fill(templates[1], {'as_of': '2026-10-16'}),
        fill(templates[2], {'d': '2026-10-20'}),
        fill(templates[3], {'d': '2026-10-25'}),
      ]);
    },
  );
}
