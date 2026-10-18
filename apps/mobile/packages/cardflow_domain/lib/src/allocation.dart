/// 候选卡、计划消费、三层容量与资格判定（Python `engine/allocation.py` 中与验证相关的部分）。
///
/// CP-SAT 模型本身不在 Dart 端（engine-spec §8）；这里只有验证器与有限搜索共用的事实：
/// 每张卡在交易日的保守账期、卡/信用账户/额度池三层容量（engine-spec §12.3）、建模前的排除
/// 原因及其顺序、目标层定义，以及模型检查点上的"当日最低点"序列。
library;

import 'billing.dart';
import 'cash.dart';
import 'rational.dart';
import 'time.dart';

/// 可承担本次消费一部分的卡（engine-spec §2 CardOption）。
final class CardOption {
  /// 候选卡（默认值与 Python `CardOption` 相同）。
  CardOption({
    required this.id,
    required this.accountId,
    required this.name,
    required this.rawAvailable,
    required this.billingRule,
    required this.repayFrom,
    this.uncountedHolds = 0,
    this.planReservations = 0,
    this.poolId,
    this.perTxnCap,
    this.minSplit,
    this.channelOk = true,
    this.currencyOk = true,
    this.statusOk = true,
    Rational? feeRate,
    this.feeFixed = 0,
    Rational? verifiedBenefitRate,
    this.verifiedBenefitCap,
    Rational? potentialBenefitRate,
    this.postingDelayMin = 0,
    this.postingDelayMax = 0,
  }) : feeRate = feeRate ?? Rational.zero,
       verifiedBenefitRate = verifiedBenefitRate ?? Rational.zero,
       potentialBenefitRate = potentialBenefitRate ?? Rational.zero;

  /// 卡 ID。
  final String id;

  /// 信用账户 ID（同一账户的主卡、附属卡共享账户可用额）。
  final String accountId;

  /// 名称。
  final String name;

  /// 银行口径的可用额度快照；可为负（超限），原值保留。
  final int rawAvailable;

  /// 账期规则。
  final BillingRule billingRule;

  /// 还款现金账户 ID。
  final String repayFrom;

  /// 快照尚未包含的预授权/占用。
  final int uncountedHolds;

  /// 其他已采纳计划的预留。
  final int planReservations;

  /// 额度池 ID。
  final String? poolId;

  /// 单笔上限。
  final int? perTxnCap;

  /// 本卡最小拆分额（null = 用请求的）。
  final int? minSplit;

  /// 渠道可用。
  final bool channelOk;

  /// 币种可用。
  final bool currencyOk;

  /// 卡状态正常。
  final bool statusOk;

  /// 费率（向上取整到最小单位）。
  final Rational feeRate;

  /// 固定费（使用该卡时）。
  final int feeFixed;

  /// 已核实收益率（进入目标函数；向下取整）。
  final Rational verifiedBenefitRate;

  /// 已核实收益上限。
  final int? verifiedBenefitCap;

  /// 潜在/未核实收益率（仅展示，不进入目标函数）。
  final Rational potentialBenefitRate;

  /// 最早入账：交易日后的天数。
  final int postingDelayMin;

  /// 最晚入账：交易日后的天数。
  final int postingDelayMax;

  /// 卡这一层可供新增消费的容量：`max(0, 可用额 − 未计预授权 − 预留)`。
  int get capacity {
    final value = rawAvailable - uncountedHolds - planReservations;
    return value > 0 ? value : 0;
  }
}

/// 计划消费（engine-spec §2 PlanRequest）。
final class PlanRequest {
  /// 计划消费（默认值与 Python `PlanRequest` 相同）。
  const PlanRequest({
    required this.amount,
    required this.currency,
    required this.txnDate,
    this.allowSplit = false,
    this.maxCards = 1,
    this.minSplit = 1,
    this.paymentLeadDays = 0,
    this.channel = 'pos',
  });

  /// 金额（最小单位，> 0）。
  final int amount;

  /// 币种。
  final String currency;

  /// 交易日。
  final LocalDate txnDate;

  /// 是否允许拆单。
  final bool allowSplit;

  /// 最多用卡数 K。
  final int maxCards;

  /// 每张用到的卡的最小金额。
  final int minSplit;

  /// 建议提前发起还款的天数（现金扣款日 = 到期日 − lead）。
  final int paymentLeadDays;

  /// 支付渠道。
  final String channel;

  /// 实际用卡上限：允许拆单时为 [maxCards]，否则 1。
  int get k => allowSplit ? maxCards : 1;

  /// 改交易日或金额后的副本。
  PlanRequest copyWith({LocalDate? txnDate, int? amount, bool? allowSplit}) =>
      PlanRequest(
        amount: amount ?? this.amount,
        currency: currency,
        txnDate: txnDate ?? this.txnDate,
        allowSplit: allowSplit ?? this.allowSplit,
        maxCards: maxCards,
        minSplit: minSplit,
        paymentLeadDays: paymentLeadDays,
        channel: channel,
      );
}

/// 一张卡在交易日的事实。
final class CardPlanInfo {
  /// 卡的事实。
  const CardPlanInfo(
    this.card,
    this.cycle,
    this.allCycles,
    this.repayOn,
    this.bufferDays,
  );

  /// 卡。
  final CardOption card;

  /// 保守账期（入账窗口内最早到期）。
  final Cycle cycle;

  /// 入账窗口内全部可能账期（最早到期在前）。
  final List<Cycle> allCycles;

  /// 计划的现金扣款日（到期日 − lead）。
  final LocalDate repayOn;

  /// `repayOn − 交易日` 的天数。
  final int bufferDays;
}

/// 卡在 [request] 交易日的保守账期、还款日与缓冲天数；规则给不出账期时抛 [BillingRuleError]。
CardPlanInfo deriveCardInfo(CardOption card, PlanRequest request) {
  final cycles = cyclesForTransaction(
    card.billingRule,
    request.txnDate,
    postingDelayMin: card.postingDelayMin,
    postingDelayMax: card.postingDelayMax,
  );
  final c = cycles.first;
  final repayOn = c.dueDate.addDays(-request.paymentLeadDays);
  return CardPlanInfo(
    card,
    c,
    cycles,
    repayOn,
    repayOn.differenceInDays(request.txnDate),
  );
}

/// 一次求解（或验证）的数据（不含情景与选项）。
final class ModelInputs {
  /// 数据。
  ModelInputs({
    required this.request,
    required this.cards,
    required this.pools,
    required this.accounts,
    required this.snapshots,
    required this.events,
    required this.horizonEnd,
    this.globalReserveFloor = 0,
  });

  /// 计划消费。
  final PlanRequest request;

  /// 候选卡（输入顺序有意义）。
  final List<CardOption> cards;

  /// 额度池 ID → 可用额（原值）。
  final Map<String, int> pools;

  /// 现金账户（输入顺序有意义）。
  final List<CashAccount> accounts;

  /// 账户 ID → 快照。
  final Map<String, Snapshot> snapshots;

  /// 已有现金事件（不含计划）。
  final List<CashEvent> events;

  /// 现金时间线的最后一天（不延长，engine-spec §12.7）。
  final LocalDate horizonEnd;

  /// 所有现金账户合计的最低值；0 = 不启用。
  final int globalReserveFloor;

  /// 改请求、卡或检查区间后的副本。
  ModelInputs copyWith({
    PlanRequest? request,
    List<CardOption>? cards,
    Map<String, int>? pools,
    LocalDate? horizonEnd,
  }) => ModelInputs(
    request: request ?? this.request,
    cards: cards ?? this.cards,
    pools: pools ?? this.pools,
    accounts: accounts,
    snapshots: snapshots,
    events: events,
    horizonEnd: horizonEnd ?? this.horizonEnd,
    globalReserveFloor: globalReserveFloor,
  );
}

/// 卡层之上的共享容量（engine-spec §12.3；bank-rules-spec §5：卡 ≤ 信用账户 ≤ 池，同时检查）。
final class CapacityLayers {
  /// 共享容量。
  const CapacityLayers(this.account, this.pool);

  /// 有两张及以上卡的信用账户 → 账户可用额（取各卡报告的最小值）减去其**所有**卡的预授权与
  /// 预留，截零。
  final Map<String, int> account;

  /// 池 ID → 池可用额减去全部成员卡的预授权与预留，截零。协议 v1 只有一层池。
  final Map<String, int> pool;
}

int _clampZero(int value) => value > 0 ? value : 0;

/// 计算共享容量层。
CapacityLayers capacityLayers(ModelInputs inputs) {
  final members = <String, List<CardOption>>{};
  for (final c in inputs.cards) {
    members.putIfAbsent(c.accountId, () => <CardOption>[]).add(c);
  }
  final account = <String, int>{};
  members.forEach((accountId, cards) {
    if (cards.length > 1) {
      var minAvailable = cards.first.rawAvailable;
      var used = 0;
      for (final c in cards) {
        if (c.rawAvailable < minAvailable) {
          minAvailable = c.rawAvailable;
        }
        used += c.uncountedHolds + c.planReservations;
      }
      account[accountId] = _clampZero(minAvailable - used);
    }
  });
  final pool = <String, int>{};
  inputs.pools.forEach((poolId, raw) {
    var used = 0;
    for (final c in inputs.cards) {
      if (c.poolId == poolId) {
        used += c.uncountedHolds + c.planReservations;
      }
    }
    pool[poolId] = _clampZero(raw - used);
  });
  return CapacityLayers(account, pool);
}

/// [card] 在本次计划中最多能承担的金额，以及决定它的那一层（相等时取外层：单笔上限、
/// 信用账户、池）。
(int, String) cardLimit(CardOption card, CapacityLayers layers) {
  var cap = card.capacity;
  var what = "the card's available credit";
  final perTxn = card.perTxnCap;
  if (perTxn != null && perTxn <= cap) {
    cap = perTxn;
    what = 'the per-transaction cap';
  }
  final shared = layers.account[card.accountId];
  if (shared != null && shared <= cap) {
    cap = shared;
    what = 'credit account ${card.accountId}';
  }
  final poolId = card.poolId;
  if (poolId != null && poolId.isNotEmpty) {
    final poolCap = layers.pool[poolId];
    if (poolCap != null && poolCap <= cap) {
      cap = poolCap;
      what = 'pool $poolId';
    }
  }
  return (cap, what);
}

/// 卡完全不能参与计划的原因（engine-spec §3 硬约束 6）。
final class Exclusion {
  /// 排除原因。
  const Exclusion(this.code, [this.detail]);

  /// 原因代码。
  final String code;

  /// 说明（如哪一层容量耗尽）。
  final String? detail;
}

/// 换一个交易日可能解除的排除原因（推迟日期搜索）。
const Set<String> dateDependentExclusions = <String>{'REPAY_BEFORE_TXN_DATE'};

/// 卡能参与时返回 `(info, null)`，否则 `(info 或 null, 排除原因)`。排除顺序：CARD_STATUS、
/// CURRENCY_NOT_SUPPORTED、CHANNEL_NOT_SUPPORTED、REPAY_ACCOUNT_MISSING、
/// REPAY_ACCOUNT_RESTRICTED、NO_CAPACITY（卡、信用账户、池）、MIN_SPLIT_ABOVE_AMOUNT、
/// REPAY_BEFORE_TXN_DATE、REPAY_AFTER_HORIZON。卡的规则对（可能平移过的）交易日给不出账期时
/// 抛 [BillingRuleError]。
(CardPlanInfo?, Exclusion?) classify(
  CardOption card,
  ModelInputs inputs, {
  PlanRequest? request,
  CapacityLayers? layers,
}) {
  final req = request ?? inputs.request;
  final shared = layers ?? capacityLayers(inputs);
  if (!card.statusOk) {
    return (null, const Exclusion('CARD_STATUS'));
  }
  if (!card.currencyOk) {
    return (null, const Exclusion('CURRENCY_NOT_SUPPORTED'));
  }
  if (!card.channelOk) {
    return (null, const Exclusion('CHANNEL_NOT_SUPPORTED'));
  }
  CashAccount? account;
  for (final a in inputs.accounts) {
    if (a.id == card.repayFrom) {
      account = a;
      break;
    }
  }
  if (account == null) {
    return (null, const Exclusion('REPAY_ACCOUNT_MISSING'));
  }
  if (!account.usableForRepayment) {
    return (null, const Exclusion('REPAY_ACCOUNT_RESTRICTED'));
  }
  // 容量逐层截零（R-RULE-08）：耗尽的信用账户或池使其卡全无容量，层外的卡不受影响。
  if (card.capacity <= 0) {
    return (
      null,
      const Exclusion('NO_CAPACITY', 'the card has no capacity left'),
    );
  }
  if ((shared.account[card.accountId] ?? 1) <= 0) {
    return (
      null,
      Exclusion(
        'NO_CAPACITY',
        'credit account ${card.accountId} has no capacity left',
      ),
    );
  }
  final poolId = card.poolId;
  if (poolId != null && poolId.isNotEmpty && (shared.pool[poolId] ?? 1) <= 0) {
    return (
      null,
      Exclusion('NO_CAPACITY', 'pool $poolId has no capacity left'),
    );
  }
  final minSplit = card.minSplit ?? req.minSplit;
  if (minSplit > req.amount) {
    return (
      null,
      const Exclusion(
        'MIN_SPLIT_ABOVE_AMOUNT',
        'the minimum part on this card exceeds the amount',
      ),
    );
  }
  final info = deriveCardInfo(card, req);
  // 现金还款日早于交易日：这样的账期无法计划（早于快照的还款也会被当成"已还"）。
  if (info.repayOn < req.txnDate) {
    return (info, const Exclusion('REPAY_BEFORE_TXN_DATE'));
  }
  // 现金时间线检查到 horizon_end 为止，从不延长（engine-spec §12.7）。
  if (info.repayOn > inputs.horizonEnd) {
    return (info, const Exclusion('REPAY_AFTER_HORIZON'));
  }
  return (info, null);
}

/// 能参与的卡（输入顺序）。[skipRuleErrors]：规则在该日给不出账期的卡当日不可用（推迟日期搜索，
/// engine-spec §12.9），否则抛 [BillingRuleError]。
List<CardPlanInfo> eligibleInfos(
  ModelInputs inputs, {
  PlanRequest? request,
  bool skipRuleErrors = false,
}) {
  final layers = capacityLayers(inputs);
  final out = <CardPlanInfo>[];
  for (final c in inputs.cards) {
    (CardPlanInfo?, Exclusion?) result;
    try {
      result = classify(c, inputs, request: request, layers: layers);
    } on BillingRuleError {
      if (skipRuleErrors) {
        continue;
      }
      rethrow;
    }
    final (info, exclusion) = result;
    if (exclusion == null && info != null) {
      out.add(info);
    }
  }
  return out;
}

/// 目标层（engine-spec §4）：画像 → [(层名, max/min)]。
const Map<String, List<(String, String)>> objectiveTiers =
    <String, List<(String, String)>>{
      'cash_safety': <(String, String)>[
        ('min_margin', 'max'),
        ('fees', 'min'),
        ('net_verified_benefit', 'max'),
        ('buffer', 'max'),
        ('cards', 'min'),
      ],
      'verified_benefit': <(String, String)>[
        ('net_verified_benefit', 'max'),
        ('min_margin', 'max'),
        ('buffer', 'max'),
        ('cards', 'min'),
      ],
      'fewer_cards': <(String, String)>[
        ('cards', 'min'),
        ('min_margin', 'max'),
        ('net_verified_benefit', 'max'),
        ('buffer', 'max'),
      ],
    };

/// [dates] 中每一天的当日最低余额：账户当天有点时取 low，否则沿用此前最后一天的期末余额
/// （首个事件日之前取快照余额）——模型检查点上看到的值（Python `_low_series`）。
List<int> lowSeries(Timeline timeline, List<LocalDate> dates) {
  final lows = <int, int>{};
  final ends = <int, int>{};
  for (final p in timeline.points) {
    if (p.phase == PointPhase.low) {
      lows[p.on.epochDay] = p.balance;
    } else if (p.phase == PointPhase.end) {
      ends[p.on.epochDay] = p.balance;
    }
  }
  final days = lows.keys.toList()..sort();
  final out = <int>[];
  var carry = timeline.snapshot.balance;
  var j = 0;
  for (final d in dates) {
    while (j < days.length && days[j] < d.epochDay) {
      carry = ends[days[j]]!;
      j++;
    }
    if (j < days.length && days[j] == d.epochDay) {
      out.add(lows[d.epochDay]!);
    } else {
      out.add(carry);
    }
  }
  return out;
}
