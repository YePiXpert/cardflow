// 审查带入项（I-1b 简报 §5，I-0 审查 §4 第 2 条）：只用现金时间线的资金日历不经过规则协议适配层，
// 由数据层复刻 `inputsFromProtocol` 里与现金有关的交叉规则（`checkCashTimelineInputs`）：事件 `at`
// 按自身偏移的日期等于 `on`；`includes` 只列快照日当天及以前的本账户事件；金额绝对值 ≤ 10^13；ID 唯一；
// 币种一致（含调拨两端）。领域对象的构造函数不做这些检查：这里用直接构造的领域对象逐条违反规则，
// 另在真实库上去掉数据库兜底（触发器）后写入违规的包含关系，确认读模型在交给领域包之前拦下。
import 'package:cardflow/data/mapping/cash_mapping.dart';
import 'package:cardflow/data/repositories/cash_forecast_reader.dart';
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'repository_test_support.dart';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

const String a1 = '00000000-0000-4000-8000-0000000000a1';
const String a2 = '00000000-0000-4000-8000-0000000000a2';

CashEvent ev(
  String id, {
  String account = a1,
  LocalDate? on,
  int amount = -1000,
  Timestamp? at,
}) => CashEvent(
  id: id,
  account: account,
  on: on ?? d(2026, 10, 20),
  amount: amount,
  cls: EventClass.confirmed,
  category: amount < 0 ? 'bill' : 'income',
  at: at,
);

Snapshot snap({
  String account = a1,
  int balance = 500000,
  Set<String> includes = const <String>{},
}) => Snapshot(
  account: account,
  balance: balance,
  asOf: d(2026, 10, 20),
  includesEventIds: includes,
);

/// 断言违反规则 [rule]。
void expectRule(String rule, void Function() check) {
  expect(
    check,
    throwsA(isA<CashInputsException>().having((e) => e.rule, 'rule', rule)),
    reason: rule,
  );
}

void main() {
  final accounts = <CashAccount>[
    const CashAccount(id: a1, name: '工资卡', reserveFloor: 200000),
    const CashAccount(id: a2, name: '零钱'),
  ];

  test('合规的数据通过（含按自身偏移取日期的时刻、快照当天及以前的包含、合规的调拨）', () {
    checkCashTimelineInputs(
      accounts: accounts,
      snapshots: {
        a1: snap(includes: {'e-same', 'e-before'}),
      },
      events: [
        ev('e-before', on: d(2026, 10, 19)),
        ev('e-same', at: Timestamp.parse('2026-10-20T23:30:00+08:00')),
        // 同一瞬间按 UTC 写是 10-20T15:30Z：按自身偏移仍是 10-20。
        ev('e-utc', at: Timestamp.parse('2026-10-20T15:30:00Z')),
        ev('t-out', amount: -5000),
        ev('t-in', account: a2, on: d(2026, 10, 21), amount: 5000),
      ],
      transferGroups: {
        'g1': ['t-out', 't-in'],
      },
      overrides: const [EventOverrideSpec(eventId: 'e-same', amountMinor: -1)],
    );
  });

  test('事件 at 按自身偏移的日期必须等于 on', () {
    expectRule('event_at_date', () {
      checkCashTimelineInputs(
        accounts: accounts,
        snapshots: const {},
        // 北京时间 10-21 00:30 = UTC 10-20 16:30：按自身偏移是 10-21。
        events: [ev('e', at: Timestamp.parse('2026-10-21T00:30:00+08:00'))],
      );
    });
  });

  test('includes 只能列快照日当天及以前的、本账户的已有事件', () {
    expectRule('includes_after_as_of', () {
      checkCashTimelineInputs(
        accounts: accounts,
        snapshots: {
          a1: snap(includes: {'later'}),
        },
        events: [ev('later', on: d(2026, 10, 21))],
      );
    });
    expectRule('includes_other_account', () {
      checkCashTimelineInputs(
        accounts: accounts,
        snapshots: {
          a1: snap(includes: {'other'}),
        },
        events: [ev('other', account: a2)],
      );
    });
    expectRule('includes_other_account', () {
      checkCashTimelineInputs(
        accounts: accounts,
        snapshots: {
          a1: snap(includes: {'missing'}),
        },
        events: const [],
      );
    });
  });

  test('金额绝对值 ≤ 10^13（事件、快照余额、储备、情景覆盖）', () {
    expectRule('amount_range', () {
      checkCashTimelineInputs(
        accounts: accounts,
        snapshots: const {},
        events: [ev('e', amount: -10000000000001)],
      );
    });
    expectRule('amount_range', () {
      checkCashTimelineInputs(
        accounts: accounts,
        snapshots: {a1: snap(balance: 10000000000001)},
        events: const [],
      );
    });
    expectRule('reserve_range', () {
      checkCashTimelineInputs(
        accounts: const [
          CashAccount(id: a1, name: '工资卡', reserveFloor: 10000000000001),
        ],
        snapshots: const {},
        events: const [],
      );
    });
    expectRule('amount_range', () {
      checkCashTimelineInputs(
        accounts: accounts,
        snapshots: const {},
        events: [ev('e')],
        overrides: const [
          EventOverrideSpec(eventId: 'e', amountMinor: -10000000000001),
        ],
      );
    });
    // 恰好 10^13 合规。
    checkCashTimelineInputs(
      accounts: accounts,
      snapshots: {a1: snap(balance: -10000000000000)},
      events: [ev('e', amount: 10000000000000)],
    );
  });

  test('ID 唯一且符合协议格式（事件 ID 不以 plan_repay_ 开头）', () {
    expectRule('duplicate_event_id', () {
      checkCashTimelineInputs(
        accounts: accounts,
        snapshots: const {},
        events: [
          ev('e'),
          ev('e', on: d(2026, 10, 22)),
        ],
      );
    });
    expectRule('duplicate_account_id', () {
      checkCashTimelineInputs(
        accounts: [accounts.first, accounts.first],
        snapshots: const {},
        events: const [],
      );
    });
    expectRule('event_id_format', () {
      checkCashTimelineInputs(
        accounts: accounts,
        snapshots: const {},
        events: [ev('plan_repay_A')],
      );
    });
    expectRule('event_id_format', () {
      checkCashTimelineInputs(
        accounts: accounts,
        snapshots: const {},
        events: [ev('带空格 的id')],
      );
    });
    expectRule('event_unknown_account', () {
      checkCashTimelineInputs(
        accounts: accounts,
        snapshots: const {},
        events: [ev('e', account: 'nope')],
      );
    });
    expectRule('override_twice', () {
      checkCashTimelineInputs(
        accounts: accounts,
        snapshots: const {},
        events: [ev('e')],
        overrides: const [
          EventOverrideSpec(eventId: 'e', amountMinor: -1),
          EventOverrideSpec(eventId: 'e', amountMinor: -2),
        ],
      );
    });
    expectRule('override_unknown_event', () {
      checkCashTimelineInputs(
        accounts: accounts,
        snapshots: const {},
        events: const [],
        overrides: const [EventOverrideSpec(eventId: 'gone', amountMinor: -1)],
      );
    });
  });

  test('币种一致：账户币种为 13 种之一；调拨两端币种相同；调拨两端不同账户、方向相反、金额相反、到账不早于转出', () {
    expectRule('currency', () {
      checkCashTimelineInputs(
        accounts: const [CashAccount(id: a1, name: '工资卡', currency: 'RMB')],
        snapshots: const {},
        events: const [],
      );
    });
    final mixed = [
      accounts.first,
      const CashAccount(id: a2, name: '美元户', currency: 'USD'),
    ];
    expectRule('currency', () {
      checkCashTimelineInputs(
        accounts: mixed,
        snapshots: const {},
        events: [
          ev('out', amount: -5000),
          ev('in', account: a2, amount: 5000),
        ],
        transferGroups: {
          'g': ['out', 'in'],
        },
      );
    });
    for (final (name, legs) in <(String, List<CashEvent>)>[
      ('同一账户', [ev('out', amount: -5000), ev('in', amount: 5000)]),
      (
        '到账早于转出',
        [
          ev('out', amount: -5000),
          ev('in', account: a2, on: d(2026, 10, 19), amount: 5000),
        ],
      ),
      (
        '金额不相反',
        [ev('out', amount: -5000), ev('in', account: a2, amount: 4000)],
      ),
    ]) {
      expect(
        () => checkCashTimelineInputs(
          accounts: accounts,
          snapshots: const {},
          events: legs,
          transferGroups: {
            'g': ['out', 'in'],
          },
        ),
        throwsA(
          isA<CashInputsException>().having(
            (e) => e.rule,
            'rule',
            'transfer_pair',
          ),
        ),
        reason: name,
      );
    }
    expectRule('transfer_pair', () {
      checkCashTimelineInputs(
        accounts: accounts,
        snapshots: const {},
        events: [ev('out', amount: -5000)],
        transferGroups: {
          'g': ['out'],
        },
      );
    });
  });

  test('读模型在交给领域包之前做同样的检查：去掉数据库兜底后写入的违规包含关系被拦下', () async {
    final db = await openRealTestDatabase();
    final scope = await createTestWorkspace(db);
    final acc = await createTestCashAccount(scope);
    final later = await addTestCashEvent(scope, acc.id, d(2026, 10, 18), -1000);
    final snapshot = await recordTestCashSnapshot(
      scope,
      acc.id,
      d(2026, 10, 16),
      500000,
    );
    await CashForecastReader(scope).loadInputs();
    await db.customStatement(
      'DROP TRIGGER snapshot_included_events_on_or_before',
    );
    await db.customStatement(
      'INSERT INTO snapshot_included_events (workspace_id, cash_account_id, snapshot_id, '
      "cash_event_id) VALUES ('${scope.workspaceId}', '${acc.id}', '${snapshot.id}', "
      "'${later.id}')",
    );
    await expectLater(
      CashForecastReader(scope).loadInputs(),
      throwsA(
        isA<CashInputsException>().having(
          (e) => e.rule,
          'rule',
          'includes_after_as_of',
        ),
      ),
    );
  });
}
