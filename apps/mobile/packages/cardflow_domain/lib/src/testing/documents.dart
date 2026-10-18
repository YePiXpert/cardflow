/// 测试辅助：构造协议 v1 PlanInput 文档（与 Python `tests/engine/test_review_wave3_fixes.py`
/// 的 `card()`、`scenario()`、`event()`、`document()` 同一写法与默认值），供领域包与 App 的测试使用。
///
/// 默认：一个现金账户 `cash`（储备 0）、快照日 = 交易日 2026-10-16、情景 `base`；默认卡的规则是
/// "账单日 20 日、次月 8 日到期"，2026-10-16 的消费在 2026-11-08 还款。
library;

/// 深拷贝 JSON 值（Map/List 递归复制，其余原样）。
Object? deepCopyJson(Object? value) => switch (value) {
  Map<String, Object?>() => <String, Object?>{
    for (final MapEntry(:key, :value) in value.entries)
      key: deepCopyJson(value),
  },
  List<Object?>() => <Object?>[for (final v in value) deepCopyJson(v)],
  _ => value,
};

/// 一张卡（CardOption 文档）。[extra] 覆盖或补充成员。
Map<String, Object?> protocolCard(
  String id, {
  int statementDay = 20,
  int dueDay = 8,
  int monthOffset = 1,
  int available = 1000000,
  String? account,
  String? pool,
  int holds = 0,
  int reservations = 0,
  String repayFrom = 'cash',
  Map<String, Object?> extra = const <String, Object?>{},
}) => <String, Object?>{
  'card_id': id,
  'credit_account_id': account ?? 'acc-$id',
  'raw_available_minor': available,
  'holds_uncounted_minor': holds,
  'reservations_minor': reservations,
  'billing_rule': <String, Object?>{
    'rule_id': 'r$id',
    'statement_day': statementDay,
    'statement_day_inclusive': true,
    'due': <String, Object?>{
      'kind': 'fixed_day',
      'day': dueDay,
      'month_offset': monthOffset,
    },
    'holiday_rollover': 'none',
  },
  'repay_from_cash_account_id': repayFrom,
  'channel_ok': true,
  'currency_ok': true,
  'status_ok': true,
  'fee_rate': '0',
  'fee_fixed_minor': 0,
  'verified_benefit_rate': '0',
  'potential_benefit_rate': '0',
  'posting_delay_min_days': 0,
  'posting_delay_max_days': 0,
  'pool_id': ?pool,
  ...extra,
};

/// 一个情景（Scenario 文档）。
Map<String, Object?> protocolScenario(
  String id, {
  String order = 'conservative',
  int delay = 0,
  List<Map<String, Object?>> overrides = const <Map<String, Object?>>[],
  bool includeExpected = true,
}) => <String, Object?>{
  'scenario_id': id,
  'include_expected': includeExpected,
  'income_delay_days': delay,
  'income_scale': '1',
  'expense_scale': '1',
  'event_overrides': <Object?>[...overrides],
  'same_day_order': order,
};

/// 一笔现金事件（账户 `cash`；负数为 `bill`，正数为 `income`）。
Map<String, Object?> protocolEvent(
  String id,
  String on,
  int amount, {
  Map<String, Object?> extra = const <String, Object?>{},
}) => <String, Object?>{
  'event_id': id,
  'cash_account_id': 'cash',
  'on': on,
  'amount_minor': amount,
  'cls': 'confirmed',
  'category': amount < 0 ? 'bill' : 'income',
  ...extra,
};

/// 一份 PlanInput 文档。
Map<String, Object?> protocolDocument(
  List<Map<String, Object?>> cards, {
  required int amount,
  required int balance,
  List<Map<String, Object?>> events = const <Map<String, Object?>>[],
  List<Map<String, Object?>> scenarios = const <Map<String, Object?>>[],
  String decision = 'base',
  List<String> includes = const <String>[],
  List<(String, int)> pools = const <(String, int)>[],
  bool split = false,
  int maxCards = 1,
  int lead = 0,
  String horizon = '2026-12-31',
  int globalFloor = 0,
  Object timeLimit = 10,
  String txn = '2026-10-16',
}) => <String, Object?>{
  'protocol_version': '1',
  'request': <String, Object?>{
    'amount_minor': amount,
    'currency': 'CNY',
    'txn_date': txn,
    'allow_split': split,
    'max_cards': maxCards,
    'min_split_minor': 1,
    'payment_lead_days': lead,
    'channel': 'pos',
  },
  'cards': <Object?>[for (final c in cards) deepCopyJson(c)],
  'pools': <Object?>[
    for (final (poolId, available) in pools)
      <String, Object?>{'pool_id': poolId, 'available_minor': available},
  ],
  'cash_accounts': <Object?>[
    <String, Object?>{
      'cash_account_id': 'cash',
      'currency': 'CNY',
      'reserve_floor_minor': 0,
      'usable_for_repayment': true,
    },
  ],
  'snapshots': <Object?>[
    <String, Object?>{
      'cash_account_id': 'cash',
      'balance_minor': balance,
      'as_of': txn,
      'includes_event_ids': <Object?>[...includes],
    },
  ],
  'events': <Object?>[for (final e in events) deepCopyJson(e)],
  'scenarios': scenarios.isEmpty
      ? <Object?>[protocolScenario('base')]
      : <Object?>[for (final s in scenarios) deepCopyJson(s)],
  'horizon_end': horizon,
  'options': <String, Object?>{
    'profile': 'cash_safety',
    'decision_scenario': decision,
    'time_limit_s': timeLimit,
    'workers': 8,
    'seed': 0,
    'stale_after_days': 7,
    'global_reserve_floor_minor': globalFloor,
  },
};

/// 分配项文档 `[{card_id, amount_minor}, ...]`。
List<Object?> protocolAllocation(Map<String, int> allocation) => <Object?>[
  for (final MapEntry(:key, :value) in allocation.entries)
    <String, Object?>{'card_id': key, 'amount_minor': value},
];
