/// 随机的小型 PlanInput 文档（带固定种子），用于性质测试与跨语言一致性检查。
///
/// 移植自 Python `services/api/tests/engine/diff_reference.py` 的 `gen_doc`（引擎 1.1.0 的差分测试
/// 生成器）：同样的结构与取值范围——共享信用账户的附属卡、池内卡的预授权与预留、快照包含快照日
/// 及以前的事件、带时区偏移的时间戳与被情景改期的事件、晚于 horizon_end 的还款、几乎相同的卡
/// （平局）；按构造是合法的 v1 文档，业务层面的问题（缺快照、快照过期、规则需要日历……）以低概率
/// 出现。随机数只用整数（概率写成千分比），不使用浮点；Dart 的 `Random(seed)` 序列与 Python 不同，
/// 因此同一种子不会得到与 Python 相同的文档。
library;

import 'dart:math';

import '../time.dart';

/// 生成器用到的随机数操作（与 Python `random.Random` 的接口同名）。
final class TestRandom {
  /// 带种子的随机数。
  TestRandom(int seed) : _random = Random(seed);

  final Random _random;

  /// `[a, b]` 内的整数。
  int randint(int a, int b) => a + _random.nextInt(b - a + 1);

  /// `[0, n)` 内的整数。
  int randrange(int n) => _random.nextInt(n);

  /// 以千分之 [permille] 的概率为真。
  bool chance(int permille) => _random.nextInt(1000) < permille;

  /// 均匀选一个。
  T choice<T>(List<T> items) => items[_random.nextInt(items.length)];

  /// 按整数权重选一个。
  T weighted<T>(List<T> items, List<int> weights) {
    var total = 0;
    for (final w in weights) {
      total += w;
    }
    var pick = _random.nextInt(total);
    for (var i = 0; i < items.length; i++) {
      pick -= weights[i];
      if (pick < 0) {
        return items[i];
      }
    }
    return items.last;
  }

  /// 不放回地取 [k] 个（保持抽取顺序）。
  List<T> sample<T>(List<T> items, int k) {
    final pool = List<T>.of(items);
    return [
      for (var i = 0; i < k; i++) pool.removeAt(_random.nextInt(pool.length)),
    ];
  }
}

Map<String, Object?> _scenario(String id, bool includeExpected, String order) =>
    <String, Object?>{
      'scenario_id': id,
      'include_expected': includeExpected,
      'income_delay_days': 0,
      'income_scale': '1',
      'expense_scale': '1',
      'event_overrides': <Object?>[],
      'same_day_order': order,
    };

String _two(int v) => v.toString().padLeft(2, '0');

/// 一份随机的小型 PlanInput（金额 1–16 个最小单位、1–4 张卡、1–3 个现金账户、0–16 笔事件、
/// 2–4 个情景）。
Map<String, Object?> randomPlanInput(TestRandom rng) {
  final txn = LocalDate(2026, 1, 1).addDays(rng.randrange(400));
  final accountIds = [for (var i = 0; i < rng.randint(1, 3); i++) 'cash-$i'];
  final offset = rng.choice(const ['+00:00', '+08:00', '-05:00']);
  final accounts = <Object?>[];
  final snapshots = <Map<String, Object?>>[];
  for (final id in accountIds) {
    accounts.add(<String, Object?>{
      'cash_account_id': id,
      'currency': 'CNY',
      'reserve_floor_minor': rng.choice(const [0, 0, 0, 1, 3, 5]),
      'usable_for_repayment': rng.chance(970),
    });
    if (rng.chance(980)) {
      final ages = [0, 0, 0, 1, 2, 3, if (rng.chance(40)) 9];
      snapshots.add(<String, Object?>{
        'cash_account_id': id,
        'balance_minor': rng.chance(80)
            ? rng.randint(-2, 60)
            : rng.randint(8, 60),
        'as_of': '${txn.addDays(-rng.choice(ages))}',
        'includes_event_ids': <Object?>[],
      });
    }
  }
  final timed = rng.chance(350);
  final events = <Map<String, Object?>>[];
  final eventCount = rng.randint(0, 16);
  for (var k = 0; k < eventCount; k++) {
    final on = txn.addDays(rng.randint(-5, 70));
    final event = <String, Object?>{
      'event_id': 'e$k',
      'cash_account_id': rng.choice(accountIds),
      'on': '$on',
      'amount_minor': rng.chance(550)
          ? -rng.randint(1, 12)
          : rng.randint(1, 20),
      'cls': rng.weighted(
        const ['confirmed', 'expected', 'planned'],
        const [6, 4, 1],
      ),
      'category': rng.weighted(
        const ['living', 'bill', 'income', 'other', 'fee'],
        const [4, 3, 3, 1, 1],
      ),
    };
    if (timed && rng.chance(900)) {
      final minutes = rng.randrange(1440);
      event['at'] =
          '${on}T${_two(minutes ~/ 60)}:${_two(minutes % 60)}:00$offset';
    }
    events.add(event);
  }
  for (final s in snapshots) {
    // 包含关系：本账户、日期不晚于快照日的事件（§12.2）
    final asOf = s['as_of']! as String;
    s['includes_event_ids'] = <Object?>[
      for (final e in events)
        if (e['cash_account_id'] == s['cash_account_id'] &&
            (e['on']! as String).compareTo(asOf) <= 0 &&
            rng.chance(500))
          e['event_id'],
    ];
  }
  final cards = <Map<String, Object?>>[];
  final twin = rng.chance(200); // 几乎相同的卡：平局规则
  final cardCount = rng.choice(const [1, 2, 2, 3, 3, 4]);
  for (var i = 0; i < cardCount; i++) {
    final id = 'ABCD'[i];
    if (twin && cards.isNotEmpty) {
      cards.add(<String, Object?>{
        ...cards.first,
        'card_id': id,
        'credit_account_id': 'acc-$id',
      });
      continue;
    }
    final statementDay = rng.randint(1, 31);
    final Map<String, Object?> due;
    if (rng.chance(800)) {
      var offsetMonths = rng.choice(const [0, 1, 1, 2]);
      var day = rng.randint(1, 31);
      if (offsetMonths == 0 && rng.chance(900)) {
        if (statementDay >= 28) {
          offsetMonths = 1;
        } else {
          day = rng.randint(statementDay + 1, 31);
        }
      }
      due = <String, Object?>{
        'kind': 'fixed_day',
        'day': day,
        'month_offset': offsetMonths,
      };
    } else {
      due = <String, Object?>{
        'kind': 'days_after_statement',
        'days': rng.randint(1, 60),
        'day_kind': rng.chance(980) ? 'calendar' : 'business',
      };
    }
    final rule = <String, Object?>{
      'rule_id': 'r$id',
      'statement_day': statementDay,
      'statement_day_inclusive': rng.chance(700),
      'due': due,
      'holiday_rollover': 'none',
    };
    if (rng.chance(150)) {
      rule['effective_to'] = '${txn.addDays(rng.randint(4, 40))}';
    }
    final card = <String, Object?>{
      'card_id': id,
      'credit_account_id': 'acc-$id',
      'raw_available_minor': rng.chance(850)
          ? rng.randint(4, 40)
          : rng.randint(-3, 3),
      'holds_uncounted_minor': rng.choice(const [0, 0, 0, 1, 3]),
      'reservations_minor': rng.choice(const [0, 0, 0, 2, 5]),
      'billing_rule': rule,
      'repay_from_cash_account_id': rng.choice(accountIds),
      'channel_ok': rng.chance(980),
      'currency_ok': rng.chance(980),
      'status_ok': rng.chance(980),
      'fee_rate': rng.choice(const [
        '0',
        '0',
        '0',
        '0.006',
        '0.1',
        '0.33333',
        '0.5',
      ]),
      'fee_fixed_minor': rng.choice(const [0, 0, 0, 1, 2]),
      'verified_benefit_rate': rng.choice(const [
        '0',
        '0',
        '0.01',
        '0.25',
        '0.33333',
      ]),
      'potential_benefit_rate': rng.choice(const ['0', '0.05', '0.5']),
      'posting_delay_min_days': 0,
      'posting_delay_max_days': 0,
    };
    if (rng.chance(150)) {
      final lo = rng.randint(0, 3);
      card['posting_delay_min_days'] = lo;
      card['posting_delay_max_days'] = lo + rng.randint(0, 3);
    }
    if (rng.chance(300)) {
      card['pool_id'] = rng.choice(const ['p1', 'p2']);
    }
    if (rng.chance(200)) {
      card['per_txn_cap_minor'] = rng.randint(0, 25);
    }
    if (rng.chance(200)) {
      card['min_split_minor'] = rng.randint(1, 12);
    }
    if (rng.chance(200)) {
      card['verified_benefit_cap_minor'] = rng.randint(0, 3);
    }
    if (cards.isNotEmpty && rng.chance(250)) {
      // 前面某张卡所在信用账户的附属卡：同一可用额、同一个池
      final host = rng.choice(cards);
      card['credit_account_id'] = host['credit_account_id'];
      card['raw_available_minor'] = host['raw_available_minor'];
      if (host.containsKey('pool_id')) {
        card['pool_id'] = host['pool_id'];
      } else {
        card.remove('pool_id');
      }
    }
    cards.add(card);
  }
  final poolsUsed = <String>{
    for (final c in cards)
      if (c.containsKey('pool_id')) c['pool_id']! as String,
  }.toList()..sort();
  final pools = <Object?>[
    for (final p in poolsUsed)
      if (rng.chance(980))
        <String, Object?>{
          'pool_id': p,
          'available_minor': rng.chance(850)
              ? rng.randint(6, 45)
              : rng.randint(-4, 5),
        },
  ];
  final request = <String, Object?>{
    'amount_minor': rng.randint(1, 16),
    'currency': 'CNY',
    'txn_date': '$txn',
    'allow_split': rng.chance(700),
    'max_cards': rng.randint(1, 4),
    'min_split_minor': rng.choice(const [1, 1, 1, 2, 3, 5]),
    'payment_lead_days': rng.choice(const [0, 0, 0, 1, 3, 7, 15, 30]),
    'channel': 'pos',
  };
  final order = timed && rng.chance(750) ? 'timestamp' : 'conservative';
  final scenarios = <Map<String, Object?>>[
    _scenario('confirmed', false, order),
    _scenario('baseline', true, order),
  ];
  final stressCount = rng.randint(0, 2);
  for (var j = 0; j < stressCount; j++) {
    final overrides = <Object?>[];
    final picked = rng.sample(events, min(events.length, rng.randint(0, 3)));
    for (final e in picked) {
      final o = <String, Object?>{'event_id': e['event_id']};
      if (rng.chance(600)) {
        // 可能把事件移到快照日之前（§12.2）
        o['on'] =
            '${LocalDate.parse(e['on']! as String).addDays(rng.randint(-8, 6))}';
      }
      if (rng.chance(500) || !o.containsKey('on')) {
        o['amount_minor'] = rng.randint(-25, 25);
      }
      overrides.add(o);
    }
    scenarios.add(<String, Object?>{
      ..._scenario('stress$j', true, rng.choice([order, 'conservative'])),
      'income_delay_days': rng.choice(const [0, 1, 3, 7]),
      'income_scale': rng.choice(const ['1', '0.5', '0.8', '0.33']),
      'expense_scale': rng.choice(const ['1', '1.2', '1.5', '2']),
      'event_overrides': overrides,
    });
  }
  final decision = rng.weighted(
    [for (final s in scenarios) s['scenario_id']! as String],
    [1, 4, for (var i = 2; i < scenarios.length; i++) 2],
  );
  return <String, Object?>{
    'protocol_version': '1',
    'request': request,
    'cards': cards,
    'pools': pools,
    'cash_accounts': accounts,
    'snapshots': snapshots,
    'events': events,
    'scenarios': scenarios,
    // 多数是 API 的检查区间（>= 交易日 + 180 天，§12.7），少数较短、会截掉还款（REPAY_AFTER_HORIZON）
    'horizon_end':
        '${txn.addDays(rng.chance(250) ? rng.randint(5, 60) : rng.randint(150, 200))}',
    'options': <String, Object?>{
      'profile': rng.choice(const [
        'cash_safety',
        'verified_benefit',
        'fewer_cards',
      ]),
      'decision_scenario': decision,
      'time_limit_s': 10,
      'workers': rng.choice(const [8, 8, 1]),
      'seed': 0,
      'stale_after_days': 7,
      'global_reserve_floor_minor': rng.choice(const [
        0,
        0,
        0,
        0,
        0,
        5,
        20,
        40,
      ]),
    },
  };
}

/// [document] 上的一组随机分配（卡 ID → 正金额），用于验证器的一致性检查：一半把请求金额恰好拆到
/// 1–3 张卡上（结构上多半合法），一半是任意金额 1–20（多为结构违规）；偶尔混入未知卡 `Z`。
List<Map<String, int>> randomAllocations(
  TestRandom rng,
  Map<String, Object?> document,
  int count,
) {
  final cards = [
    for (final c in document['cards']! as List<Object?>)
      (c! as Map<String, Object?>)['card_id']! as String,
  ];
  final amount =
      (document['request']! as Map<String, Object?>)['amount_minor']! as int;
  final out = <Map<String, int>>[];
  for (var i = 0; i < count; i++) {
    final pool = [...cards, if (rng.chance(100)) 'Z'];
    if (rng.chance(500)) {
      final k = rng.randint(1, min(3, min(pool.length, amount)));
      final ids = rng.sample(pool, k);
      final cuts = (rng.sample([for (var c = 1; c < amount; c++) c], k - 1)
        ..sort());
      final bounds = [0, ...cuts, amount];
      out.add({for (var j = 0; j < k; j++) ids[j]: bounds[j + 1] - bounds[j]});
    } else {
      final ids = rng.sample(pool, rng.randint(1, min(3, pool.length)));
      out.add({for (final id in ids) id: rng.randint(1, 20)});
    }
  }
  return out;
}
