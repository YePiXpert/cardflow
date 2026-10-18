// 三层容量与建模前的资格判定（Python allocation.capacity_layers / card_limit / classify）：
// test_review_wave3_fixes.py 的 R3E-04、R3E-08、R3E-10、R3E-19，test_robustness.py 的
// REPAY_BEFORE_TXN_DATE 与耗尽的额度池；排除顺序与 engine-spec §12.1 相同。
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:cardflow_domain/testing.dart';
import 'package:test/test.dart';

import 'support/repo.dart';

Map<String, (String, String?)?> exclusions(Map<String, Object?> doc) {
  final p = inputsFromProtocol(doc);
  final layers = capacityLayers(p.inputs);
  return {
    for (final c in p.inputs.cards)
      c.id: switch (classify(c, p.inputs, layers: layers)) {
        (_, null) => null,
        (_, final Exclusion e) => (e.code, e.detail),
      },
  };
}

(int, String) limitOf(Map<String, Object?> doc, String cardId) {
  final p = inputsFromProtocol(doc);
  return cardLimit(
    p.inputs.cards.firstWhere((c) => c.id == cardId),
    capacityLayers(p.inputs),
  );
}

void main() {
  test('R3E-10: NO_CAPACITY names the exhausted layer (card, credit account or pool)', () {
    final cards = [
      protocolCard('A', available: 0),
      protocolCard('B', pool: 'p'),
      protocolCard('C', account: 'acc-x', available: 500, reservations: 300),
      protocolCard('D', account: 'acc-x', available: 500, holds: 200),
      protocolCard('E'),
    ];
    final doc = protocolDocument(
      cards,
      amount: 100,
      balance: 1000000,
      pools: [('p', 0)],
    );
    expect(exclusions(doc), {
      'A': ('NO_CAPACITY', 'the card has no capacity left'),
      'B': ('NO_CAPACITY', 'pool p has no capacity left'),
      'C': ('NO_CAPACITY', 'credit account acc-x has no capacity left'),
      'D': ('NO_CAPACITY', 'credit account acc-x has no capacity left'),
      'E': null,
    });
  });

  test(
    'R3E-10: the binding layer of a card limit (pool, per-transaction cap)',
    () {
      expect(
        limitOf(
          protocolDocument(
            [protocolCard('A', pool: 'p')],
            amount: 800000,
            balance: 100000000,
            pools: [('p', 500000)],
          ),
          'A',
        ),
        (500000, 'pool p'),
      );
      expect(
        limitOf(
          protocolDocument(
            [
              protocolCard('A', extra: {'per_txn_cap_minor': 500000}),
            ],
            amount: 800000,
            balance: 100000000,
          ),
          'A',
        ),
        (500000, 'the per-transaction cap'),
      );
      expect(limitOf(f18Input(), 'C'), (600000, "the card's available credit"));
    },
  );

  test('R3E-10: a minimum part above the amount is its own reason', () {
    final doc = protocolDocument(
      [
        protocolCard('A', extra: {'min_split_minor': 900000}),
      ],
      amount: 800000,
      balance: 100000000,
    );
    expect(exclusions(doc), {
      'A': (
        'MIN_SPLIT_ABOVE_AMOUNT',
        'the minimum part on this card exceeds the amount',
      ),
    });
  });

  test('R3E-04: cards of one credit account share its available credit', () {
    final doc = protocolDocument(
      [
        protocolCard('main', available: 600000, account: 'acc-1'),
        protocolCard('supp', available: 600000, account: 'acc-1'),
      ],
      amount: 1000000,
      balance: 100000000,
      split: true,
      maxCards: 3,
    );
    final p = inputsFromProtocol(doc);
    expect(capacityLayers(p.inputs).account, {'acc-1': 600000});
    expect(limitOf(doc, 'main'), (600000, 'credit account acc-1'));
  });

  for (final member in ['reservations', 'holds']) {
    test('R3E-04: a pool deducts its members\' $member', () {
      final a = protocolCard(
        'A',
        pool: 'p',
        reservations: member == 'reservations' ? 800000 : 0,
        holds: member == 'holds' ? 800000 : 0,
      );
      final doc = protocolDocument(
        [a, protocolCard('B', pool: 'p')],
        amount: 1000000,
        balance: 100000000,
        pools: [('p', 1000000)],
        split: true,
        maxCards: 2,
      );
      expect(capacityLayers(inputsFromProtocol(doc).inputs).pool, {
        'p': 200000,
      });
      expect(limitOf(doc, 'A'), (200000, 'pool p'));
      expect(limitOf(doc, 'B'), (200000, 'pool p'));
    });
  }

  test(
    'R3E-08 / R3E-19: repayments before the purchase or after the horizon',
    () {
      final early = protocolDocument(
        [protocolCard('B')],
        amount: 100,
        balance: 1000000,
        lead: 25,
      );
      expect(exclusions(early), {'B': ('REPAY_BEFORE_TXN_DATE', null)});
      final late = protocolDocument(
        [
          protocolCard('A', available: 1000),
          protocolCard(
            'B',
            statementDay: 1,
            dueDay: 28,
            monthOffset: 1,
            available: 50,
          ),
        ],
        amount: 100,
        balance: 500,
        horizon: '2026-11-30',
      );
      expect(exclusions(late), {'A': null, 'B': ('REPAY_AFTER_HORIZON', null)});
    },
  );

  test('test_robustness.py: a 30-day lead excludes B only; an exhausted pool clamps to zero', () {
    final doc = f18Input();
    obj(doc['request'])['payment_lead_days'] = 30;
    expect(exclusions(doc), {
      'A': null,
      'B': ('REPAY_BEFORE_TXN_DATE', null),
      'C': null,
    });
    for (final available in [0, -100]) {
      final pooled = f18Input();
      obj(arr(pooled['cards'])[1])['pool_id'] = 'pool-B';
      pooled['pools'] = <Object?>[
        <String, Object?>{'pool_id': 'pool-B', 'available_minor': available},
      ];
      expect(exclusions(pooled), {
        'A': null,
        'B': ('NO_CAPACITY', 'pool pool-B has no capacity left'),
        'C': null,
      });
    }
  });

  test('exclusion order: status, currency, channel, repayment account, capacity, ...', () {
    final p = f18();
    final rule = p.inputs.cards.first.billingRule;
    CardOption card(
      String id, {
      bool status = true,
      bool currency = true,
      bool channel = true,
      String repay = 'cash-main',
      int available = 100,
    }) => CardOption(
      id: id,
      accountId: 'acc-$id',
      name: id,
      rawAvailable: available,
      billingRule: rule,
      repayFrom: repay,
      statusOk: status,
      currencyOk: currency,
      channelOk: channel,
    );
    final restricted = const CashAccount(
      id: 'locked',
      name: 'locked',
      usableForRepayment: false,
    );
    final inputs = p.inputs.copyWith(
      cards: [
        card('s', status: false, currency: false, available: 0),
        card('c', currency: false, channel: false),
        card('h', channel: false, repay: 'nope'),
        card('m', repay: 'nope', available: 0),
        card('r', repay: 'locked', available: 0),
        card('n', available: 0),
      ],
    );
    final withLocked = ModelInputs(
      request: inputs.request,
      cards: inputs.cards,
      pools: inputs.pools,
      accounts: [...inputs.accounts, restricted],
      snapshots: inputs.snapshots,
      events: inputs.events,
      horizonEnd: inputs.horizonEnd,
    );
    expect(
      [for (final c in withLocked.cards) classify(c, withLocked).$2!.code],
      [
        'CARD_STATUS',
        'CURRENCY_NOT_SUPPORTED',
        'CHANNEL_NOT_SUPPORTED',
        'REPAY_ACCOUNT_MISSING',
        'REPAY_ACCOUNT_RESTRICTED',
        'NO_CAPACITY',
      ],
    );
  });

  test('eligibleInfos keeps the input order and can skip rule errors (date-shift search)', () {
    final doc = f18Input();
    obj(obj(arr(doc['cards'])[2])['billing_rule'])['effective_to'] =
        '2026-10-18';
    final p = inputsFromProtocol(doc);
    expect(
      [for (final i in eligibleInfos(p.inputs)) i.card.id],
      ['A', 'B', 'C'],
    );
    final shifted = p.inputs.request.copyWith(txnDate: LocalDate(2026, 10, 18));
    expect(
      () => eligibleInfos(p.inputs, request: shifted),
      throwsA(isA<BillingRuleError>()),
    );
    expect(
      [
        for (final i in eligibleInfos(
          p.inputs,
          request: shifted,
          skipRuleErrors: true,
        ))
          i.card.id,
      ],
      ['A', 'B'],
    );
  });
}
