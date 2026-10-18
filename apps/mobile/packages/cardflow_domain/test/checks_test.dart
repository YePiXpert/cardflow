// 数据检查与基线（Python plan.data_issues / baseline_check）：test_review_wave3_fixes.py 的
// R3E-03（快照反映先于情景）、R3E-05（改期丢弃时间戳）、R3E-09（基线包含全局底线），
// test_regression_sample.py 的过期快照；期望值与 Python 测试相同。
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:cardflow_domain/testing.dart';
import 'package:test/test.dart';

import 'support/repo.dart';

typedef Doc = Map<String, Object?>;

Map<String, BaselineCheck> baselines(Doc doc) {
  final p = inputsFromProtocol(doc);
  return {
    for (final MapEntry(:key, :value) in p.scenarios.entries)
      key: baselineCheck(p.inputs, value),
  };
}

Doc doubleCount(List<String> includes, String salaryOn, Doc stress) =>
    protocolDocument(
      [protocolCard('A')],
      amount: 100000,
      balance: 50000,
      events: [
        protocolEvent('sal', salaryOn, 200000, extra: {'cls': 'expected'}),
        protocolEvent('rent', '2026-11-01', -40000),
      ],
      includes: includes,
      scenarios: [protocolScenario('baseline'), stress],
      decision: 'stress',
    );

void main() {
  group('R3E-03: snapshot reflection is judged before the scenario', () {
    final cases = <String, (List<String>, String, Doc)>{
      'included-then-delayed': (
        ['sal'],
        '2026-10-16',
        protocolScenario('stress', delay: 3),
      ),
      'before-snapshot-then-delayed': (
        <String>[],
        '2026-10-14',
        protocolScenario('stress', delay: 3),
      ),
      'included-then-moved': (
        ['sal'],
        '2026-10-16',
        protocolScenario(
          'stress',
          overrides: [
            {'event_id': 'sal', 'on': '2026-10-20'},
          ],
        ),
      ),
    };
    cases.forEach((name, value) {
      final (includes, salaryOn, stress) = value;
      test('a reflected inflow is not counted again ($name)', () {
        final doc = doubleCount(includes, salaryOn, stress);
        final b = baselines(doc);
        for (final id in ['baseline', 'stress']) {
          final acc = b[id]!.accounts['cash']!;
          // 500.00 − 400.00（房租）= 100.00；评审曾看到 2,100.00
          expect((acc.minBalance, acc.endBalance), (10000, 10000), reason: id);
        }
        final p = inputsFromProtocol(doc);
        final v = verify(p.inputs, {'A': 100000}, p.scenarios, 'stress');
        expect(v.ok, isFalse); // Python：A 为 CASH_BREACH_ALONE，INFEASIBLE
      });
    });

    test('an event moved before the snapshot counts on the snapshot day', () {
      final doc = protocolDocument(
        [protocolCard('A')],
        amount: 1000,
        balance: 50000,
        events: [protocolEvent('bill', '2026-11-01', -40000)],
        scenarios: [
          protocolScenario('baseline'),
          protocolScenario(
            'early',
            overrides: [
              {'event_id': 'bill', 'on': '2026-10-10'},
            ],
          ),
        ],
        decision: 'early',
      );
      final early = baselines(doc)['early']!;
      final acc = early.accounts['cash']!;
      expect((acc.minBalance, acc.endBalance), (10000, 10000));
      expect(acc.minOn, LocalDate(2026, 10, 16));
      expect(early.assumptions.any((a) => a.contains('bill')), isTrue);
      final p = inputsFromProtocol(doc);
      expect(verify(p.inputs, {'A': 1000}, p.scenarios, 'early').ok, isTrue);
    });
  });

  test('R3E-05: a delayed income loses its timestamp (conservative order on the new day)', () {
    final doc = protocolDocument(
      [
        protocolCard(
          'A',
          statementDay: 10,
          dueDay: 28,
          monthOffset: 0,
          available: 1000,
        ),
      ],
      amount: 3,
      balance: 10,
      events: [
        protocolEvent(
          'sal',
          '2026-11-05',
          20,
          extra: {'cls': 'expected', 'at': '2026-11-05T09:00:00+08:00'},
        ),
        protocolEvent(
          'bill',
          '2026-11-08',
          -15,
          extra: {'at': '2026-11-08T10:00:00+08:00'},
        ),
      ],
      scenarios: [
        protocolScenario('base', order: 'timestamp'),
        protocolScenario('stress', order: 'timestamp', delay: 3),
      ],
      decision: 'stress',
    );
    final stress = baselines(doc)['stress']!;
    expect(stress.ok, isFalse);
    expect(stress.accounts['cash']!.minBalance, -5);
  });

  group('R3E-09: the baseline checks the global floor', () {
    test(
      'two accounts above their reserves, the total below the global floor',
      () {
        final doc = protocolDocument(
          [protocolCard('A')],
          amount: 1,
          balance: 50,
          events: [protocolEvent('x', '2026-10-20', -1)],
          globalFloor: 120,
        );
        arr(doc['cash_accounts']).add({
          ...obj(arr(doc['cash_accounts']).first),
          'cash_account_id': 'cash-2',
        });
        arr(doc['snapshots']).add({
          ...obj(arr(doc['snapshots']).first),
          'cash_account_id': 'cash-2',
        });
        final base = baselines(doc)['base']!;
        expect(base.ok, isFalse);
        expect(
          jsonEquals(
            baselineCheckToProtocol(base)['global_breaches'],
            <Object?>[
              <String, Object?>{'on': '2026-10-16', 'total': 100, 'gap': 20},
              <String, Object?>{'on': '2026-10-20', 'total': 99, 'gap': 21},
            ],
          ),
          isTrue,
        );
        expect(base.accounts.values.every((a) => a.breaches.isEmpty), isTrue);
      },
    );

    test('a starting total below the global floor is a shortfall', () {
      final base = baselines(
        protocolDocument(
          [protocolCard('A')],
          amount: 1,
          balance: 10,
          globalFloor: 40,
        ),
      )['base']!;
      expect(base.ok, isFalse);
      expect(
        [for (final g in base.globalBreaches) (g.on, g.total, g.gap)],
        [(LocalDate(2026, 10, 16), 10, 30)],
      );
    });
  });

  group('data issues', () {
    test(
      'F-18 has none; a purchase 14 days after the snapshot is STALE_SNAPSHOT',
      () {
        final p = f18();
        expect(dataIssues(p.inputs, 7), isEmpty);
        final late = p.inputs.copyWith(
          request: p.inputs.request.copyWith(txnDate: LocalDate(2026, 10, 30)),
        );
        final issues = dataIssues(late, 7);
        expect(
          [for (final i in issues) (i.code, i.account, i.ageDays)],
          [('STALE_SNAPSHOT', 'cash-main', 14)],
        );
      },
    );

    test(
      'issues are listed accounts first, then cards, and written like Python',
      () {
        final doc = f18Input();
        obj(doc['request'])['txn_date'] = '2026-10-15'; // 快照晚于交易日
        obj(arr(doc['cards'])[1])['pool_id'] = 'p9';
        obj(obj(arr(doc['cards'])[2])['billing_rule'])['effective_from'] =
            '2026-10-20';
        final p = inputsFromProtocol(doc);
        final written = dataIssuesToProtocol(dataIssues(p.inputs, 7));
        expect(
          jsonEquals(written, <Object?>[
            <String, Object?>{
              'code': 'SNAPSHOT_AFTER_TXN_DATE',
              'cash_account_id': 'cash-main',
              'as_of': '2026-10-16',
            },
            <String, Object?>{
              'code': 'MISSING_POOL_SNAPSHOT',
              'card_id': 'B',
              'pool_id': 'p9',
            },
            <String, Object?>{
              'code': 'BILLING_RULE_INVALID',
              'card_id': 'C',
              'detail': 'rule rule-C not effective on 2026-10-15',
            },
          ]),
          isTrue,
          reason: '$written',
        );
      },
    );
  });
}
