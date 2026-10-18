// 协议适配层：tests/protocol/test_rejections.py（BOTH 35 项 + ADAPTER_ONLY 14 项，期望的 JSON Pointer
// 与 Python 相同）、test_review_wave3_protocol.py 中适配层相关的用例（R3E-04/11/12/14/20/21）、
// test_adapter.py 的往返与可省略成员默认值。
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:cardflow_domain/testing.dart';
import 'package:test/test.dart';

import 'support/repo.dart';

typedef Doc = Map<String, Object?>;
typedef Mutation = void Function(Doc doc);

Object? token(String text) => parseJsonText(text);

/// 沿路径取父节点后设置/删除/追加。
Object? _node(Doc doc, List<Object> path) {
  Object? node = doc;
  for (final key in path) {
    node = key is int ? arr(node)[key] : obj(node)[key];
  }
  return node;
}

Mutation set(List<Object> path, Object? value) => (doc) {
  final parent = _node(doc, path.sublist(0, path.length - 1));
  final last = path.last;
  if (last is int) {
    arr(parent)[last] = value;
  } else {
    obj(parent)[last as String] = value;
  }
};

Mutation remove(List<Object> path) => (doc) {
  final parent = obj(_node(doc, path.sublist(0, path.length - 1)));
  parent.remove(path.last);
};

Mutation append(List<Object> path, Object? value) =>
    (doc) => arr(_node(doc, path)).add(deepCopyJson(value));

void duplicateSnapshot(Doc doc) {
  final snapshots = arr(doc['snapshots']);
  snapshots.add(deepCopyJson(snapshots.first));
}

void otherAccountsEventIncluded(Doc doc) {
  final accounts = arr(doc['cash_accounts']);
  accounts.add({
    ...obj(accounts.first),
    'cash_account_id': 'cash-2',
    'name': 'cash-2',
  });
  final events = arr(doc['events']);
  events.add({
    ...obj(events.first),
    'event_id': 'e9',
    'cash_account_id': 'cash-2',
    'on': '2026-10-16',
  });
  obj(arr(doc['snapshots']).first)['includes_event_ids'] = <Object?>['e9'];
}

ProtocolError rejection(Doc doc) {
  try {
    inputsFromProtocol(doc);
  } on ProtocolError catch (e) {
    return e;
  }
  fail('expected a ProtocolError');
}

bool accepted(Doc doc) {
  try {
    inputsFromProtocol(doc);
    return true;
  } on ProtocolError {
    return false;
  }
}

Doc mutated(Mutation m) => f18Input()..let(m);

extension<T> on T {
  T let(void Function(T) f) {
    f(this);
    return this;
  }
}

void main() {
  test('the unmodified F-18 document is valid', () {
    expect(accepted(f18Input()), isTrue);
  });

  group(
    'rejected by schema AND adapter (test_rejections.py BOTH; pointer prefix)',
    () {
      final both = <(String, Mutation, String)>[
        (
          'float-amount',
          set(['request', 'amount_minor'], token('1000000.5')),
          '/request/amount_minor',
        ),
        (
          'integral-float-amount',
          set(['request', 'amount_minor'], token('1000000.0')),
          '/request/amount_minor',
        ),
        (
          'float-balance',
          set(['snapshots', 0, 'balance_minor'], token('500000.0')),
          '/snapshots/0',
        ),
        (
          'float-rate',
          set(['cards', 0, 'fee_rate'], token('0.006')),
          '/cards/0/fee_rate',
        ),
        (
          'rate-exponent',
          set(['cards', 0, 'fee_rate'], '6E-3'),
          '/cards/0/fee_rate',
        ),
        (
          'rate-11-digits',
          set(['cards', 0, 'fee_rate'], '0.00000000001'),
          '/cards/0/fee_rate',
        ),
        (
          'bool-amount',
          set(['request', 'amount_minor'], true),
          '/request/amount_minor',
        ),
        (
          'bool-count',
          set(['request', 'max_cards'], true),
          '/request/max_cards',
        ),
        (
          'bool-floor',
          set(['cash_accounts', 0, 'reserve_floor_minor'], false),
          '/cash_accounts/0/reserve_floor_minor',
        ),
        (
          'string-amount',
          set(['request', 'amount_minor'], '1000000'),
          '/request/amount_minor',
        ),
        ('missing-currency', remove(['request', 'currency']), '/request'),
        ('missing-fee-rate', remove(['cards', 0, 'fee_rate']), '/cards/0'),
        ('missing-workers', remove(['options', 'workers']), '/options'),
        (
          'missing-includes',
          remove(['snapshots', 0, 'includes_event_ids']),
          '/snapshots/0',
        ),
        ('missing-options', remove(['options']), ''),
        ('extra-top-level', set(['extra'], 1), '/extra'),
        (
          'extra-daily-cap',
          set(['cards', 0, 'daily_cap_minor'], 0),
          '/cards/0/daily_cap_minor',
        ),
        (
          'extra-merchant',
          set(['request', 'merchant'], 'shop'),
          '/request/merchant',
        ),
        (
          'extra-due-member',
          set(['cards', 0, 'billing_rule', 'due', 'days'], 3),
          '/cards/0/billing_rule/due/days',
        ),
        (
          'negative-holds',
          set(['cards', 0, 'holds_uncounted_minor'], -1),
          '/cards/0/holds_uncounted_minor',
        ),
        (
          'int64-overflow',
          set(['request', 'amount_minor'], BigInt.two.pow(63)),
          '/request/amount_minor',
        ),
        (
          'zero-amount',
          set(['request', 'amount_minor'], 0),
          '/request/amount_minor',
        ),
        (
          'impossible-date',
          set(['request', 'txn_date'], '2026-02-30'),
          '/request/txn_date',
        ),
        (
          'compact-date',
          set(['request', 'txn_date'], '20261016'),
          '/request/txn_date',
        ),
        (
          'naive-timestamp',
          set(['snapshots', 0, 'observed_at'], '2026-10-16T09:00:00'),
          '/snapshots/0/observed_at',
        ),
        (
          'protocol-version',
          set(['protocol_version'], '2'),
          '/protocol_version',
        ),
        (
          'unknown-profile',
          set(['options', 'profile'], 'max_benefit'),
          '/options/profile',
        ),
        ('zero-workers', set(['options', 'workers'], 0), '/options/workers'),
        (
          'zero-time-limit',
          set(['options', 'time_limit_s'], 0),
          '/options/time_limit_s',
        ),
        (
          'string-time-limit',
          set(['options', 'time_limit_s'], '10'),
          '/options/time_limit_s',
        ),
        (
          'reserved-event-id',
          set(['events', 0, 'event_id'], 'plan_repay_A'),
          '/events/0/event_id',
        ),
        (
          'empty-category',
          set(['events', 0, 'category'], ''),
          '/events/0/category',
        ),
        ('unknown-cls', set(['events', 0, 'cls'], 'maybe'), '/events/0/cls'),
        (
          'override-without-change',
          set(
            ['scenarios', 2, 'event_overrides', 0],
            <String, Object?>{'event_id': 'e8'},
          ),
          '/scenarios/2/event_overrides/0',
        ),
        (
          'lowercase-currency',
          set(['request', 'currency'], 'cny'),
          '/request/currency',
        ),
      ];
      test('35 cases, as in Python', () => expect(both, hasLength(35)));
      for (final (name, mutate, pointer) in both) {
        test(
          name,
          () => expect(rejection(mutated(mutate)).path, startsWith(pointer)),
        );
      }
    },
  );

  group(
    'rules beyond JSON Schema (test_rejections.py ADAPTER_ONLY; exact pointer)',
    () {
      final adapterOnly = <(String, Mutation, String)>[
        (
          'duplicate-card',
          set(['cards', 1, 'card_id'], 'A'),
          '/cards/1/card_id',
        ),
        (
          'duplicate-event',
          set(['events', 1, 'event_id'], 'e1'),
          '/events/1/event_id',
        ),
        (
          'duplicate-scenario',
          set(['scenarios', 1, 'scenario_id'], 'confirmed'),
          '/scenarios/1/scenario_id',
        ),
        (
          'duplicate-snapshot',
          duplicateSnapshot,
          '/snapshots/1/cash_account_id',
        ),
        (
          'duplicate-pool',
          set(
            ['pools'],
            <Object?>[
              <String, Object?>{'pool_id': 'p', 'available_minor': 1},
              <String, Object?>{'pool_id': 'p', 'available_minor': 2},
            ],
          ),
          '/pools/1/pool_id',
        ),
        (
          'currency-mismatch',
          set(['cash_accounts', 0, 'currency'], 'USD'),
          '/cash_accounts/0/currency',
        ),
        (
          'unknown-repay-account',
          set(['cards', 0, 'repay_from_cash_account_id'], 'cash-x'),
          '/cards/0/repay_from_cash_account_id',
        ),
        (
          'unknown-event-account',
          set(['events', 0, 'cash_account_id'], 'cash-x'),
          '/events/0/cash_account_id',
        ),
        (
          'unknown-snapshot-account',
          set(['snapshots', 0, 'cash_account_id'], 'cash-x'),
          '/snapshots/0/cash_account_id',
        ),
        (
          'includes-unknown-event',
          set(['snapshots', 0, 'includes_event_ids'], <Object?>['e99']),
          '/snapshots/0/includes_event_ids/0',
        ),
        (
          'includes-other-accounts-event',
          otherAccountsEventIncluded,
          '/snapshots/0/includes_event_ids/0',
        ),
        (
          'override-unknown-event',
          set(['scenarios', 2, 'event_overrides', 0, 'event_id'], 'e99'),
          '/scenarios/2/event_overrides/0/event_id',
        ),
        (
          'override-twice',
          append(
            ['scenarios', 2, 'event_overrides'],
            <String, Object?>{'event_id': 'e8', 'amount_minor': 1},
          ),
          '/scenarios/2/event_overrides/1/event_id',
        ),
        (
          'posting-delay-inverted',
          set(['cards', 0, 'posting_delay_min_days'], 3),
          '/cards/0/posting_delay_max_days',
        ),
      ];
      test('14 cases, as in Python', () => expect(adapterOnly, hasLength(14)));
      for (final (name, mutate, pointer) in adapterOnly) {
        test(name, () => expect(rejection(mutated(mutate)).path, pointer));
      }
    },
  );

  group('review wave 3 (test_review_wave3_protocol.py)', () {
    Doc twoCardsOfOneAccount() {
      final doc = f18Input();
      final cards = arr(doc['cards']);
      obj(cards[1])['credit_account_id'] = obj(cards[0])['credit_account_id'];
      obj(cards[1])['raw_available_minor'] = obj(
        cards[0],
      )['raw_available_minor'];
      return doc;
    }

    test('R3E-04: cards of one credit account report one available credit and one pool', () {
      expect(accepted(twoCardsOfOneAccount()), isTrue);
      final differs = twoCardsOfOneAccount()
        ..let(set(['cards', 1, 'raw_available_minor'], 1));
      expect(rejection(differs).path, '/cards/1/raw_available_minor');
      final pooled = twoCardsOfOneAccount()
        ..let(set(['cards', 1, 'pool_id'], 'p'))
        ..let(
          set(
            ['pools'],
            <Object?>[
              <String, Object?>{'pool_id': 'p', 'available_minor': 1},
            ],
          ),
        );
      expect(rejection(pooled).path, '/cards/1/pool_id');
    });

    test('R3E-11: database NUMERICs enter the protocol in canonical text with equal hashes', () {
      const vectors = <String, String>{
        '0.0060000000': '0.006',
        '0E-10': '0',
        '1.0000000000': '1',
        '0.12345': '0.12345',
        '6E-3': '0.006',
      };
      final parsed = f18();
      vectors.forEach((stored, text) {
        CardOption withRate(Rational rate) {
          final c = parsed.inputs.cards.first;
          return CardOption(
            id: c.id,
            accountId: c.accountId,
            name: c.name,
            rawAvailable: c.rawAvailable,
            billingRule: c.billingRule,
            repayFrom: c.repayFrom,
            feeRate: rate,
          );
        }

        ModelInputs withCard(CardOption card) => parsed.inputs.copyWith(
          cards: [card, ...parsed.inputs.cards.skip(1)],
        );
        final doc = inputsToProtocol(
          withCard(withRate(Rational.parseDecimal(stored))),
          parsed.scenarios,
          parsed.options,
        );
        expect(obj(arr(doc['cards']).first)['fee_rate'], text);
        final plain = inputsToProtocol(
          withCard(withRate(Rational.parseDecimal(text))),
          parsed.scenarios,
          parsed.options,
        );
        expect(protocolInputHash(doc), protocolInputHash(plain));
      });
    });

    test('R3E-11: only canonical rates and factors are valid', () {
      final cases = <(List<Object>, String)>[
        (['cards', 0, 'fee_rate'], '0.00600'),
        (['cards', 0, 'fee_rate'], '0.0'),
        (['cards', 0, 'fee_rate'], '1.0'),
        (['cards', 0, 'fee_rate'], '1.00000'),
        (['cards', 0, 'fee_rate'], '0.'),
        (['scenarios', 0, 'income_scale'], '1.0'),
        (['scenarios', 0, 'expense_scale'], '10.0000000000'),
        (['scenarios', 0, 'expense_scale'], '01'),
      ];
      for (final (path, value) in cases) {
        expect(
          accepted(mutated(set(path, value))),
          isFalse,
          reason: '$path=$value',
        );
      }
    });

    test('R3E-12: errors name the pointer and the rule, never the value', () {
      final echo = <(List<Object>, Object?, String)>[
        (['request', 'amount_minor'], 100000000000000, '100000000000000'),
        (['request', 'amount_minor'], '1234567.89', '1234567'),
        (['events', 0, 'cls'], 123456789, '123456789'),
        (
          ['options', 'profile'],
          <String, Object?>{'balance_minor': 98765432},
          '98765432',
        ),
        (['protocol_version'], 31415926, '31415926'),
        (['options', 'time_limit_s'], token('98765.4321'), '98765'),
        (['cards', 0, 'card_id'], '6222 0212 3456 7890', '6222'),
        (['request', 'currency'], 'RMB-12345', '12345'),
        (['cards', 0, 'fee_rate'], '0.123456', '123456'),
        (['request', 'txn_date'], '2026-02-30', '2026-02-30'),
        (['request', 'txn_date'], '1999-99-99', '99-99'),
        (['snapshots', 0, 'observed_at'], '2026-10-16T09:00:00+99:00', '99:00'),
        (['cards', 0, 'repay_from_cash_account_id'], 'acct-998877', '998877'),
        (
          ['snapshots', 0, 'includes_event_ids'],
          <Object?>['e77665544'],
          '77665544',
        ),
        (
          ['scenarios', 2, 'event_overrides', 0, 'event_id'],
          'e55443322',
          '55443322',
        ),
        (['cash_accounts', 0, 'currency'], 'USD', 'USD'),
      ];
      for (final (path, value, secret) in echo) {
        final e = rejection(mutated(set(path, value)));
        expect('$e', isNot(contains(secret)), reason: '$path');
        expect(e.path, startsWith('/'));
      }
    });

    test(
      'R3E-14: includes_event_ids may only list events up to the snapshot day',
      () {
        final later = mutated(
          set(['snapshots', 0, 'includes_event_ids'], <Object?>['e1']),
        ); // e1: 10-27
        expect(rejection(later).path, '/snapshots/0/includes_event_ids/0');
        expect(
          accepted(later..let(set(['events', 0, 'on'], '2026-10-15'))),
          isTrue,
        );
        expect(
          accepted(later..let(set(['events', 0, 'on'], '2026-10-16'))),
          isTrue,
        );
      },
    );

    test("R3E-14: a timestamp lies on its event's date, in its own offset", () {
      const cases = <String, bool>{
        '2026-10-27T09:00:00+08:00': true,
        '2026-10-27T23:30:00-05:00': true, // UTC 已是 10-28：按自身偏移计
        '2026-10-26T23:30:00Z': false,
        '2026-10-28T00:00:00+08:00': false,
      };
      cases.forEach((at, ok) {
        final doc = mutated(set(['events', 0, 'at'], at));
        expect(accepted(doc), ok, reason: at);
        if (!ok) {
          expect(rejection(doc).path, '/events/0/at');
        }
      });
    });

    test('R3E-20: timestamps accepted exactly as the schema with its format checker accepts them', () {
      const cases = <String, bool>{
        '2026-10-16T09:00:00+08:00': true,
        '2026-10-16T23:59:59.999999Z': true,
        '2026-10-16T09:00:00+23:59': true,
        '2026-10-16T23:59:60Z': false,
        '2026-10-16T24:00:00Z': false,
        '2026-10-16T99:99:99+99:99': false,
        '2026-02-30T09:00:00Z': false,
        '2026-10-16T09:00:00+24:00': false,
        '2026-10-16T09:60:00Z': false,
        '2026-10-16T09:00:00.1234567Z': false,
        '2026-10-16t09:00:00z': false,
        '2026-13-01T09:00:00Z': false,
      };
      cases.forEach((value, ok) {
        expect(
          accepted(mutated(set(['snapshots', 0, 'observed_at'], value))),
          ok,
          reason: value,
        );
      });
    });

    test(
      'R3E-21: text length counts code points (runes), not UTF-16 units',
      () {
        expect(
          accepted(mutated(set(['events', 0, 'label'], '😀' * 1000))),
          isTrue,
        );
        expect(
          accepted(mutated(set(['events', 0, 'label'], '😀' * 1001))),
          isFalse,
        );
        expect(
          accepted(mutated(set(['events', 0, 'label'], 'a\ud800'))),
          isFalse,
        );
      },
    );
  });

  group('test_adapter.py', () {
    test('round trip PlanInput -> domain -> PlanInput is lossless', () {
      final doc = f18Input();
      final parsed = inputsFromProtocol(doc);
      final again = inputsToProtocol(
        parsed.inputs,
        parsed.scenarios,
        parsed.options,
      );
      expect(jsonEquals(again, doc), isTrue);
      expect(protocolInputHash(again), f18InputHash);
    });

    test('defaults of optional members', () {
      final doc = f18Input();
      obj(arr(doc['cards'])[0]).remove('name');
      obj(arr(doc['cash_accounts'])[0]).remove('name');
      obj(arr(doc['events'])[0]).remove('label');
      obj(arr(doc['scenarios'])[0]).remove('description');
      for (final card in arr(doc['cards'])) {
        obj(obj(card)['billing_rule'])
          ..remove('source')
          ..remove('status');
      }
      final parsed = inputsFromProtocol(doc);
      expect(parsed.inputs.cards.first.name, 'A');
      expect(parsed.inputs.accounts.first.name, 'cash-main');
      expect(parsed.inputs.events.first.label, '');
      expect(parsed.scenarios['confirmed']!.description, '');
      expect({for (final c in parsed.inputs.cards) c.billingRule.source}, {''});
      expect(
        {for (final c in parsed.inputs.cards) c.billingRule.status},
        {RuleStatus.userDeclared},
      );
      expect(parsed.inputs.cards.first.poolId, isNull);
      expect(parsed.inputs.snapshots['cash-main']!.observedAt, isNull);
    });

    test('scenarios keep the input order; options are read', () {
      final parsed = f18();
      expect(parsed.scenarios.keys, [
        'confirmed',
        'baseline',
        'stress_income_delay',
      ]);
      expect(parsed.options.decisionScenario, 'baseline');
      expect(parsed.options.staleAfterDays, 7);
      expect(
        parsed.scenarios['stress_income_delay']!.eventOverrides['e8']!.on,
        LocalDate(2026, 11, 29),
      );
    });

    test('verifyFromProtocol rejects invalid requests', () {
      final alloc = protocolAllocation({'A': 1000000});
      expect(
        () => verifyFromProtocol(f18Input(), alloc, 'nope'),
        throwsA(
          isA<ProtocolError>().having(
            (e) => e.message,
            'message',
            'unknown scenario',
          ),
        ),
      );
      expect(
        () => verifyFromProtocol(f18Input(), [...alloc, ...alloc], 'baseline'),
        throwsA(
          isA<ProtocolError>().having(
            (e) => e.message,
            'message',
            'duplicate card_id',
          ),
        ),
      );
      expect(
        () => verifyFromProtocol(f18Input(), <Object?>[
          <String, Object?>{'card_id': 'A', 'amount_minor': token('1e6')},
        ], 'baseline'),
        throwsA(
          isA<ProtocolError>().having(
            (e) => e.message,
            'message',
            startsWith('expected an integer'),
          ),
        ),
      );
    });
  });
}
