// 独立验证器：test_regression_sample.py 的 cycles/verify 部分、test_properties.py 的
// test_credit_limit_is_never_cash、test_robustness.py / test_production_fixes.py /
// test_review_wave3_mutants.py / test_review_wave3_fixes.py 中与验证器相关的用例。期望值与 Python
// 测试相同；Python 测试只通过 plan() 断言的少数值（如额度池分配）取自 Python 引擎的实际输出。
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:cardflow_domain/testing.dart';
import 'package:test/test.dart';

import 'support/repo.dart';

typedef Doc = Map<String, Object?>;

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

Verification verifyF18(Map<String, int> allocation, {ParsedPlanInput? parsed}) {
  final p = parsed ?? f18();
  return verify(p.inputs, allocation, p.scenarios, 'baseline');
}

Doc verifyDoc(Doc doc, Map<String, int> allocation, String decision) =>
    verifyFromProtocol(doc, protocolAllocation(allocation), decision);

Doc check(Doc result, String scenario) =>
    obj(obj(obj(result['verification'])['checks'])[scenario]);

void main() {
  group('test_regression_sample.py (cycles / verify)', () {
    test('cycles match the acceptance sample', () {
      final p = f18();
      final expected = {
        'A': (d(2026, 11, 10), d(2026, 11, 28)),
        'B': (d(2026, 10, 20), d(2026, 11, 8)),
        'C': (d(2026, 11, 5), d(2026, 11, 25)),
      };
      for (final c in p.inputs.cards) {
        final info = deriveCardInfo(c, p.inputs.request);
        expect(
          (info.cycle.statementDate, info.cycle.dueDate),
          expected[c.id],
          reason: c.id,
        );
      }
    });

    test('A 8,000 + C 2,000: baseline minimum cash 3,000 and buffer 42.4', () {
      final v = verifyF18({'A': 800000, 'C': 200000});
      expect(v.structuralOk && v.ok, isTrue);
      expect(v.checks['baseline']!.minBalanceByAccount['cash-main'], 300000);
      expect(v.weightedBufferDays, '42.4');
    });

    test('B alone reports every breach, not only the first', () {
      final chk = verifyF18({'B': 1000000}).checks['baseline']!;
      expect(chk.ok, isFalse);
      final byDate = {for (final b in chk.breaches) b.on: b.balance};
      expect(byDate[d(2026, 11, 8)], -350000);
      expect(byDate[d(2026, 11, 16)], -700000);
      expect(byDate[d(2026, 11, 22)], -200000);
      expect(chk.breaches, hasLength(3));
      expect(chk.firstBreach!.on, d(2026, 11, 8));
      expect(chk.minBalanceByAccount['cash-main'], -700000);
      expect(chk.minOnByAccount['cash-main'], d(2026, 11, 16));
    });

    test(
      'income delay stress on A + C distinguishes the zero and reserve gaps',
      () {
        final chk = verifyF18({'A': 800000, 'C': 200000})
            .checks['stress_income_delay']!;
        expect(chk.ok, isFalse);
        expect(chk.breaches, hasLength(1));
        final b = chk.breaches.single;
        expect((b.on, b.balance), (d(2026, 11, 28), -200000));
        expect((b.gapToZero, b.gapToReserve), (200000, 400000));
      },
    );

    test('shared pool: the solver plan A 8,000 + B 1,000 + C 1,000 sits on the reserve line', () {
      final doc = f18Input();
      obj(arr(doc['cards'])[0])['pool_id'] = 'pool-AC';
      obj(arr(doc['cards'])[2])['pool_id'] = 'pool-AC';
      doc['pools'] = <Object?>[
        <String, Object?>{'pool_id': 'pool-AC', 'available_minor': 900000},
      ];
      // CP-SAT 的分配（Python plan_from_protocol 的输出）
      final v = verifyF18({
        'A': 800000,
        'B': 100000,
        'C': 100000,
      }, parsed: inputsFromProtocol(doc));
      expect(v.ok, isTrue);
      expect(v.checks['baseline']!.minBalanceByAccount['cash-main'], 200000);
      final over = verifyF18({
        'A': 800000,
        'C': 200000,
      }, parsed: inputsFromProtocol(doc));
      expect(
        over.violations,
        contains('pool pool-AC: 1000000 exceeds shared capacity 900000'),
      );
    });
  });

  test('test_properties.py: credit limit is never cash', () {
    final p = f18();
    final rich = p.inputs.copyWith(
      cards: [
        for (final c in p.inputs.cards)
          CardOption(
            id: c.id,
            accountId: c.accountId,
            name: c.name,
            rawAvailable: 1000000000,
            billingRule: c.billingRule,
            repayFrom: c.repayFrom,
          ),
      ],
    );
    final v = verify(rich, {'B': 1000000}, p.scenarios, 'baseline');
    expect(v.checks['baseline']!.ok, isFalse);
    expect(v.checks['baseline']!.minBalanceByAccount['cash-main'], -700000);
  });

  group('test_robustness.py', () {
    test('a planned repayment dated before the snapshot is applied on the snapshot day and flagged', () {
      final doc = f18Input();
      obj(doc['request'])['payment_lead_days'] =
          60; // A 付 09-29、C 付 09-26，早于 10-16
      final v = verifyF18({
        'A': 800000,
        'C': 200000,
      }, parsed: inputsFromProtocol(doc));
      expect(v.ok, isFalse);
      expect(v.violations, [
        'A: ineligible (REPAY_BEFORE_TXN_DATE)',
        'C: ineligible (REPAY_BEFORE_TXN_DATE)',
        'PLANNED_REPAYMENT_BEFORE_SNAPSHOT: A repays on 2026-09-29, before the cash-main '
            'snapshot of 2026-10-16 (applied on that day)',
        'PLANNED_REPAYMENT_BEFORE_SNAPSHOT: C repays on 2026-09-26, before the cash-main '
            'snapshot of 2026-10-16 (applied on that day)',
      ]);
      final chk = v.checks['baseline']!;
      expect(chk.ok, isFalse);
      expect(chk.minBalanceByAccount['cash-main'], -700000);
      expect(
        (chk.breaches.first.on, chk.breaches.first.balance),
        (d(2026, 10, 16), -500000),
      );
      expect(chk.breaches.first.events, ['plan_repay_A', 'plan_repay_C']);
      expect(chk.assumptions, [
        'cash-main: plan_repay_A dated 2026-09-29 precedes the snapshot of 2026-10-16; applied on the snapshot day',
        'cash-main: plan_repay_C dated 2026-09-26 precedes the snapshot of 2026-10-16; applied on the snapshot day',
      ]);
    });

    test('any amount on a card of an exhausted pool is a violation', () {
      final doc = f18Input();
      obj(arr(doc['cards'])[1])['pool_id'] = 'pool-B';
      doc['pools'] = <Object?>[
        <String, Object?>{'pool_id': 'pool-B', 'available_minor': -100},
      ];
      final v = verifyF18({
        'A': 800000,
        'B': 200000,
      }, parsed: inputsFromProtocol(doc));
      expect(v.structuralOk, isFalse);
      expect(
        v.violations,
        contains('pool pool-B: 200000 exceeds shared capacity 0'),
      );
      expect(v.violations, contains('B: ineligible (NO_CAPACITY)'));
    });

    test('non-integer amounts are refused at the protocol boundary, never truncated', () {
      for (final amount in <Object?>[
        parseJsonText('800000.0'),
        parseJsonText('800000.5'),
        true,
        '800000',
      ]) {
        expect(
          () => verifyFromProtocol(f18Input(), <Object?>[
            <String, Object?>{'card_id': 'A', 'amount_minor': amount},
            <String, Object?>{'card_id': 'C', 'amount_minor': 200000},
          ], 'baseline'),
          throwsA(
            isA<ProtocolError>().having(
              (e) => e.path,
              'path',
              '/allocation/0/amount_minor',
            ),
          ),
          reason: '$amount',
        );
      }
    });
  });

  group('test_production_fixes.py', () {
    test('an unknown card is a violation, not an exception', () {
      final v = verifyF18({'A': 800000, 'Z': 200000});
      expect(v.ok, isFalse);
      expect(v.structuralOk, isFalse);
      final unknown = v.violations
          .where((m) => m.startsWith('UNKNOWN_CARD'))
          .toList();
      expect(unknown, ["UNKNOWN_CARD: 'Z' is not one of the plan's cards"]);
      expect([for (final l in v.lines) l.card], ['A']);
      expect(v.checks.keys, ['confirmed', 'baseline', 'stress_income_delay']);
    });

    test(
      'an allocation made only of unknown cards is rejected and has no lines',
      () {
        final v = verifyF18({'Z': 1000000});
        expect(v.ok, isFalse);
        expect(v.violations.first, startsWith('UNKNOWN_CARD'));
        expect(v.lines, isEmpty);
        final result = verifyDoc(f18Input(), {'Z': 1000000}, 'baseline');
        expect(arr(result['allocation']), isEmpty);
        expect(obj(result['verification'])['ok'], isFalse);
      },
    );
  });

  group('test_review_wave3_mutants.py', () {
    Doc singleCard(Map<String, Object?> card) {
      final doc = f18Input();
      doc['cards'] = <Object?>[
        <String, Object?>{...obj(arr(doc['cards'])[0]), ...card},
      ];
      obj(doc['request'])
        ..['amount_minor'] = 100000
        ..['allow_split'] = false
        ..['max_cards'] = 1;
      obj(arr(doc['snapshots'])[0])['balance_minor'] = 100000000;
      return doc;
    }

    for (final (lead, eligible) in [(5, true), (6, false)]) {
      test(
        'M05: a repayment on the transaction date is allowed (lead $lead)',
        () {
          final rule = <String, Object?>{
            ...obj(obj(arr(f18Input()['cards'])[0])['billing_rule']),
            'statement_day': 31,
            'due': <String, Object?>{
              'kind': 'fixed_day',
              'day': 5,
              'month_offset': 1,
            },
          };
          final doc = singleCard({'billing_rule': rule});
          obj(doc['request'])
            ..['txn_date'] = '2026-12-31'
            ..['payment_lead_days'] = lead;
          obj(arr(doc['snapshots'])[0])['as_of'] = '2026-12-31';
          doc['events'] = <Object?>[];
          doc['horizon_end'] = '2027-06-30';
          for (final s in arr(doc['scenarios'])) {
            obj(s)['event_overrides'] = <Object?>[];
          }
          final result = verifyDoc(doc, {'A': 100000}, 'baseline');
          final ver = obj(result['verification']);
          final line = obj(arr(result['allocation']).single);
          if (eligible) {
            expect(ver['ok'], isTrue);
            expect(
              (line['due_date'], line['repay_on'], line['buffer_days']),
              ('2027-01-05', '2026-12-31', 0),
            );
          } else {
            expect(
              arr(ver['violations']),
              contains('A: ineligible (REPAY_BEFORE_TXN_DATE)'),
            );
          }
        },
      );
    }

    test('M14: the fee is rounded UP and leaves cash with the repayment', () {
      final ends = <int>[];
      for (final rate in ['0.006', '0']) {
        final doc = singleCard({'fee_rate': rate});
        obj(doc['request'])['amount_minor'] = 1001;
        final result = verifyDoc(doc, {'A': 1001}, 'baseline');
        ends.add(
          obj(
                check(result, 'confirmed')['end_balance_by_account'],
              )['cash-main']!
              as int,
        );
        if (rate != '0') {
          expect(obj(arr(result['allocation']).single)['fee_minor'], 7);
          expect(obj(result['verification'])['fees'], 7);
        }
      }
      expect(ends[1] - ends[0], 7);
    });

    test('M15: the verified and potential benefits are rounded DOWN', () {
      final doc = singleCard({
        'verified_benefit_rate': '0.006',
        'potential_benefit_rate': '0.006',
      });
      obj(doc['request'])['amount_minor'] = 1001;
      final result = verifyDoc(doc, {'A': 1001}, 'baseline');
      final line = obj(arr(result['allocation']).single);
      expect(
        (line['verified_benefit_minor'], line['potential_benefit_minor']),
        (6, 6),
      );
      expect(obj(result['verification'])['verified_benefit'], 6);
    });

    for (final (txn, stale) in [('2026-10-23', false), ('2026-10-24', true)]) {
      test(
        'M20: a snapshot exactly stale_after_days old is not stale ($txn)',
        () {
          final doc = f18Input();
          obj(doc['request'])['txn_date'] = txn;
          final result = verifyDoc(doc, {'A': 800000, 'C': 200000}, 'baseline');
          final codes = [
            for (final i in arr(result['data_issues'])) obj(i)['code'],
          ];
          expect(codes, stale ? ['STALE_SNAPSHOT'] : <Object?>[]);
          expect(result['verification'] == null, stale);
        },
      );
    }

    test(
      'M26: the weighted buffer rounds HALF_UP to 0.1 (40.25 -> "40.3")',
      () {
        final p = f18();
        final small = p.inputs.copyWith(
          request: p.inputs.request.copyWith(amount: 12),
        );
        expect(
          verify(
            small,
            {'A': 1, 'C': 11},
            p.scenarios,
            'baseline',
          ).weightedBufferDays,
          '40.3',
        );
      },
    );

    test(
      'a tiny negative weighted buffer keeps its sign, like Decimal: "-0.0"',
      () {
        final doc = f18Input();
        obj(doc['request'])
          ..['payment_lead_days'] = 30
          ..['amount_minor'] = 23;
        // A 8 × 13 天 + B 15 × (−7 天) = −1；−1/23 = −0.04…（Python 输出 '-0.0'）
        final v = verifyF18({'A': 8, 'B': 15}, parsed: inputsFromProtocol(doc));
        expect(v.weightedBufferDays, '-0.0');
        expect(v.violations.first, 'B: ineligible (REPAY_BEFORE_TXN_DATE)');
        expect(weightedBufferText(BigInt.zero, 7), '0.0');
        expect(weightedBufferText(BigInt.from(-5), 100), '-0.1');
        expect(weightedBufferText(BigInt.from(5), 100), '0.1');
      },
    );
  });

  group('test_review_wave3_fixes.py (verifier)', () {
    test('R3E-04: the verifier checks the credit-account layer', () {
      final cards = [
        protocolCard('main', available: 600000, account: 'acc-1'),
        protocolCard('supp', available: 600000, account: 'acc-1'),
      ];
      final doc = protocolDocument(
        cards,
        amount: 1000000,
        balance: 100000000,
        split: true,
        maxCards: 3,
      );
      final result = verifyDoc(doc, {'main': 600000, 'supp': 400000}, 'base');
      expect(obj(result['verification'])['ok'], isFalse);
      expect(
        arr(obj(result['verification'])['violations']),
        contains(
          'credit account acc-1: 1000000 exceeds shared capacity 600000',
        ),
      );
    });

    test(
      'R3E-05: a planned repayment comes first on a timestamp-ordered day',
      () {
        final timed = [
          protocolEvent(
            'inc',
            '2026-11-08',
            20,
            extra: {'at': '2026-11-08T09:00:00+08:00'},
          ),
          protocolEvent(
            'exp',
            '2026-11-08',
            -25,
            extra: {'at': '2026-11-08T18:00:00+08:00'},
          ),
        ];
        final doc = protocolDocument(
          [protocolCard('B', available: 1000)],
          amount: 3,
          balance: 10,
          events: timed,
          scenarios: [protocolScenario('ts', order: 'timestamp')],
          decision: 'ts',
        );
        final chk = check(verifyDoc(doc, {'B': 3}, 'ts'), 'ts');
        // 0.10 → 0.07 → 0.27 → 0.02（最低 0.02）
        expect(chk['ok'], isTrue);
        expect(chk['min_balance_by_account'], {'cash': 2});
        expect(arr(chk['assumptions']), [
          'cash: 2026-11-08: 计划还款没有时间戳，按当日最先发生处理',
        ]);
      },
    );

    test('R3E-07: the fee is paid with the repayment', () {
      final doc = protocolDocument(
        [
          protocolCard(
            'A',
            available: 100000,
            extra: {'fee_rate': '0.006', 'fee_fixed_minor': 1000},
          ),
        ],
        amount: 10000,
        balance: 10000,
      );
      final result = verifyDoc(doc, {'A': 10000}, 'base');
      final breach = obj(arr(check(result, 'base')['breaches']).first);
      expect((breach['on'], breach['balance']), ('2026-11-08', -1060));
      expect(breach['events'], ['plan_repay_A']);
      expect(obj(arr(result['allocation']).single)['fee_minor'], 1060);
    });

    Doc horizonDoc(List<String> cards) {
      final pool = {
        'A': protocolCard('A', available: 1000), // 2026-11-08 还款
        'B': protocolCard(
          'B',
          statementDay: 1,
          dueDay: 28,
          monthOffset: 1,
          available: 50,
        ), // 将在 2026-12-28 还款
      };
      return protocolDocument(
        [for (final c in cards) pool[c]!],
        amount: 100,
        balance: 500,
        events: [protocolEvent('tax', '2026-12-15', -450)],
        horizon: '2026-11-30',
      );
    }

    test('R3E-08: an unusable card does not extend the horizon', () {
      for (final cards in [
        ['A', 'B'],
        ['A'],
      ]) {
        expect(
          obj(
            verifyDoc(horizonDoc(cards), {'A': 100}, 'base')['verification'],
          )['ok'],
          isTrue,
        );
      }
    });

    test(
      'R3E-08: a repayment after the horizon is a violation in the verifier',
      () {
        final result = verifyDoc(horizonDoc(['A', 'B']), {'B': 50}, 'base');
        expect(
          arr(obj(result['verification'])['violations']),
          contains('B: ineligible (REPAY_AFTER_HORIZON)'),
        );
      },
    );

    final needsData = <(String, void Function(Doc), String)>[
      (
        'missing-snapshot',
        (doc) => doc['snapshots'] = <Object?>[],
        'MISSING_SNAPSHOT',
      ),
      (
        'needs-calendar',
        (doc) =>
            obj(obj(arr(doc['cards'])[0])['billing_rule'])['holiday_rollover'] =
                'next_business_day',
        'BILLING_RULE_INVALID',
      ),
      (
        'missing-pool',
        (doc) => obj(arr(doc['cards'])[0])['pool_id'] = 'p1',
        'MISSING_POOL_SNAPSHOT',
      ),
      (
        'stale',
        (doc) => obj(doc['request'])['txn_date'] = '2026-10-30',
        'STALE_SNAPSHOT',
      ),
    ];
    for (final (name, mutate, code) in needsData) {
      test('R3E-13: verify reports $code instead of raising ($name)', () {
        final doc = f18Input();
        mutate(doc);
        final result = verifyDoc(doc, {'A': 800000, 'C': 200000}, 'baseline');
        expect([
          for (final i in arr(result['data_issues'])) obj(i)['code'],
        ], contains(code));
        expect(result['verification'], isNull);
        expect(arr(result['allocation']), isEmpty);
      });
    }

    test(
      'R3E-13: the rule error text is the data issue detail, as in Python',
      () {
        final doc = f18Input();
        obj(obj(arr(doc['cards'])[0])['billing_rule'])['holiday_rollover'] =
            'next_business_day';
        final issue = obj(
          arr(verifyDoc(doc, {'A': 1000000}, 'baseline')['data_issues']).single,
        );
        expect(issue, {
          'code': 'BILLING_RULE_INVALID',
          'card_id': 'A',
          'detail':
              'holiday_rollover requires a verified business-day calendar',
        });
      },
    );
  });
}
