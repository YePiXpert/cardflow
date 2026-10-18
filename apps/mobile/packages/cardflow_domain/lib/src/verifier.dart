/// 独立验证器（Python `engine/verifier.py`，模型 1.1.0）：不用求解器，从分配重新计算每条硬约束
/// 与每个账户、每个情景、每个检查点的现金时间线。求解器（或本地有限搜索）的答案从不未经验证地采信。
///
/// * 时间线到 `horizon_end` 为止，不延长；还款日晚于它的卡违规 `ineligible (REPAY_AFTER_HORIZON)`；
/// * 计划还款额 = 分配金额 + 该卡费用（§12.6）；在按时间戳排序的日子里排在当日最前（§12.4）；
/// * 早于快照日的计划还款按快照日计入并记违规（不跳过）；
/// * 信用账户层与池层按扣除成员卡预授权与预留后的容量检查（§12.3）；全局底线与基线同一规则（§12.8）。
library;

import 'allocation.dart';
import 'cash.dart';
import 'money.dart';
import 'pytext.dart';
import 'rational.dart';
import 'sort.dart';
import 'time.dart';

/// 验证检查中的一个缺口点。
final class ScenarioBreach {
  /// 缺口点。
  const ScenarioBreach({
    required this.account,
    required this.on,
    required this.balance,
    required this.gapToZero,
    required this.gapToReserve,
    required this.events,
  });

  /// 现金账户 ID。
  final String account;

  /// 日期。
  final LocalDate on;

  /// 余额（当日流出后的最低点，或快照余额）。
  final int balance;

  /// 距零。
  final int gapToZero;

  /// 距储备。
  final int gapToReserve;

  /// 当日的流出事件（含计划还款 `plan_repay_<卡>`）。
  final List<String> events;
}

/// 全局底线缺口：所有现金账户合计低于 `global_reserve_floor` 的日子。
final class GlobalBreach {
  /// 全局缺口。
  const GlobalBreach(this.on, this.total, this.gap);

  /// 日期。
  final LocalDate on;

  /// 合计。
  final int total;

  /// 缺口（底线 − 合计）。
  final int gap;
}

/// 一个情景的检查结果。
final class ScenarioCheck {
  /// 检查结果。
  const ScenarioCheck({
    required this.scenarioId,
    required this.ok,
    required this.okZero,
    required this.minBalanceByAccount,
    required this.minOnByAccount,
    required this.endBalanceByAccount,
    required this.breaches,
    required this.firstBreach,
    required this.globalBreaches,
    required this.assumptions,
  });

  /// 情景 ID。
  final String scenarioId;

  /// 任何账户都没有低于储备的缺口点，且全局底线满足。
  final bool ok;

  /// 任何账户都没有低于零的点。
  final bool okZero;

  /// 账户 → 最低余额。
  final Map<String, int> minBalanceByAccount;

  /// 账户 → 最低余额首次出现的日期。
  final Map<String, LocalDate> minOnByAccount;

  /// 账户 → 期末余额。
  final Map<String, int> endBalanceByAccount;

  /// **全部**缺口点，按（日期, 账户）排序（稳定）。
  final List<ScenarioBreach> breaches;

  /// 第一个缺口点。
  final ScenarioBreach? firstBreach;

  /// 全局底线缺口。
  final List<GlobalBreach> globalBreaches;

  /// 假设说明。
  final List<String> assumptions;
}

/// 分配行（每张用到的已知卡一行，按分配的顺序）。
final class AllocationLine {
  /// 分配行。
  const AllocationLine({
    required this.card,
    required this.amount,
    required this.statementDate,
    required this.dueDate,
    required this.repayOn,
    required this.repayFrom,
    required this.bufferDays,
    required this.fee,
    required this.verifiedBenefit,
    required this.potentialBenefit,
    required this.cycleAssumptions,
    required this.alternativeCycles,
  });

  /// 卡 ID。
  final String card;

  /// 金额。
  final int amount;

  /// 保守账期的账单日。
  final LocalDate statementDate;

  /// 保守账期的到期日。
  final LocalDate dueDate;

  /// 计划现金扣款日；当天从还款账户流出 [amount] + [fee]。
  final LocalDate repayOn;

  /// 还款现金账户。
  final String repayFrom;

  /// `repayOn − 交易日`。
  final int bufferDays;

  /// 手续费（费率部分向上取整 + 固定费）。
  final int fee;

  /// 已核实收益（向下取整、封顶）。
  final int verifiedBenefit;

  /// 潜在收益（向下取整；仅展示）。
  final int potentialBenefit;

  /// 账期假设。
  final List<String> cycleAssumptions;

  /// 入账窗口内也可能出现的较晚账期（账单日, 到期日）。
  final List<(LocalDate, LocalDate)> alternativeCycles;
}

/// 验证结果。
final class Verification {
  /// 验证结果。
  const Verification({
    required this.ok,
    required this.structuralOk,
    required this.violations,
    required this.decisionScenario,
    required this.checks,
    required this.weightedBufferDays,
    required this.fees,
    required this.verifiedBenefit,
    required this.potentialBenefit,
    required this.lines,
  });

  /// 结构检查通过且决策情景没有缺口。
  final bool ok;

  /// 结构检查通过（额度、拆单、用卡数、守恒、资格、快照前还款）。
  final bool structuralOk;

  /// 结构违规（如 `UNKNOWN_CARD: ...`、`amount conservation violated: ...`）。
  final List<String> violations;

  /// 决策情景 ID。
  final String decisionScenario;

  /// 情景 ID → 检查结果（情景输入顺序）。
  final Map<String, ScenarioCheck> checks;

  /// 金额加权的还款缓冲天数，HALF_UP 到 0.1（与 Python `str(Decimal)` 逐字相同，如 `42.4`）。
  final String weightedBufferDays;

  /// 费用合计。
  final int fees;

  /// 已核实收益合计。
  final int verifiedBenefit;

  /// 潜在收益合计。
  final int potentialBenefit;

  /// 分配行。
  final List<AllocationLine> lines;
}

/// 所有现金账户**合计**低于全局底线的日子（[floor] 为 0 = 不启用）：检查点为每个快照日与任一
/// 账户有当日最低点的每一天；各账户取当日最低点，或此前最后一天的期末余额（首个事件日之前取
/// 快照余额）。基线与验证器同一规则（engine-spec §12.8，R3E-09）。
List<GlobalBreach> globalFloorBreaches(
  Map<String, CashReport> reports,
  int floor,
) {
  if (floor <= 0) {
    return const <GlobalBreach>[];
  }
  final dateSet = <int>{};
  for (final r in reports.values) {
    for (final p in r.timeline.points) {
      if (p.phase == PointPhase.snapshot || p.phase == PointPhase.low) {
        dateSet.add(p.on.epochDay);
      }
    }
  }
  final dates = [
    for (final d in dateSet.toList()..sort()) LocalDate.fromEpochDay(d),
  ];
  final series = <List<int>>[
    for (final r in reports.values) lowSeries(r.timeline, dates),
  ];
  final out = <GlobalBreach>[];
  for (var i = 0; i < dates.length; i++) {
    var total = 0;
    for (final s in series) {
      total += s[i];
    }
    if (total < floor) {
      out.add(GlobalBreach(dates[i], total, floor - total));
    }
  }
  return out;
}

/// [card] 上 [amount] 的费用：费率部分向上取整，使用该卡（金额 > 0）时加固定费。
int cardFee(CardOption card, int amount) {
  final ratePart = card.feeRate.isZero
      ? 0
      : applyRate(amount, card.feeRate, RoundingMode.up);
  return ratePart + (amount > 0 ? card.feeFixed : 0);
}

/// 计划的现金还款：每张卡"金额 + 费用"，在 repay_on 当天（engine-spec §12.6）。
List<CashEvent> plannedRepaymentEvents(
  Map<String, CardPlanInfo> infos,
  Map<String, int> allocation, [
  Map<String, int>? fees,
]) => [
  for (final MapEntry(key: cardId, value: amount) in allocation.entries)
    CashEvent(
      id: 'plan_repay_$cardId',
      account: infos[cardId]!.card.repayFrom,
      on: infos[cardId]!.repayOn,
      amount: -(amount + (fees?[cardId] ?? 0)),
      cls: EventClass.planned,
      category: 'repayment',
      label: '计划还款 $cardId',
    ),
];

/// 一个情景下的检查。
ScenarioCheck checkScenario(
  ModelInputs inputs,
  Map<String, CardPlanInfo> infos,
  Map<String, int> allocation,
  Scenario scenario, [
  Map<String, int>? fees,
]) {
  final assumptions = <String>[];
  final planned = <CashEvent>[];
  for (final event in plannedRepaymentEvents(infos, allocation, fees)) {
    final snapshot = inputs.snapshots[event.account];
    if (snapshot != null && event.on < snapshot.asOf) {
      // 时间线把快照日之前的事件当作已反映在余额里；计划还款从来不是。改在快照日计入而不是
      // 跳过（保守）；verify() 记为违规。
      assumptions.add(
        '${event.account}: ${event.id} dated ${event.on} precedes the snapshot of '
        '${snapshot.asOf}; applied on the snapshot day',
      );
      planned.add(event.copyWith(on: snapshot.asOf));
    } else {
      planned.add(event);
    }
  }
  final reports = evaluateAccounts(
    inputs.accounts,
    inputs.snapshots,
    inputs.events,
    scenario,
    inputs.horizonEnd,
    planned: planned,
  );
  final unsorted = <ScenarioBreach>[];
  reports.forEach((accountId, r) {
    for (final a in r.assumptions) {
      assumptions.add('$accountId: $a');
    }
    for (final b in r.breaches) {
      unsorted.add(
        ScenarioBreach(
          account: accountId,
          on: b.on,
          balance: b.balance,
          gapToZero: b.gapToZero,
          gapToReserve: b.gapToReserve,
          events: List<String>.of(b.eventIds),
        ),
      );
    }
  });
  final breaches = stableSorted(unsorted, (a, b) {
    final byDate = a.on.compareTo(b.on);
    return byDate != 0 ? byDate : compareCodePoints(a.account, b.account);
  });
  final globalBreaches = globalFloorBreaches(
    reports,
    inputs.globalReserveFloor,
  );
  return ScenarioCheck(
    scenarioId: scenario.id,
    ok: breaches.isEmpty && globalBreaches.isEmpty,
    okZero: reports.values.every((r) => r.okZero),
    minBalanceByAccount: {
      for (final MapEntry(:key, :value) in reports.entries)
        key: value.minBalance,
    },
    minOnByAccount: {
      for (final MapEntry(:key, :value) in reports.entries) key: value.minOn,
    },
    endBalanceByAccount: {
      for (final MapEntry(:key, :value) in reports.entries)
        key: value.endBalance,
    },
    breaches: breaches,
    firstBreach: breaches.isEmpty ? null : breaches.first,
    globalBreaches: globalBreaches,
    assumptions: assumptions,
  );
}

/// 金额加权缓冲天数，HALF_UP 到 0.1，写法与 Python `str(Decimal.quantize(Decimal('0.1')))`
/// 相同：总带一位小数，负值保留符号（极小的负值写作 `-0.0`，与 Decimal 的带符号零一致）。
String weightedBufferText(BigInt weightedDays, int amount) {
  if (amount == 0) {
    return '0';
  }
  final negative = weightedDays.isNegative != amount.isNegative;
  final tenths = Rational(
    weightedDays.abs() * BigInt.from(10),
    BigInt.from(amount).abs(),
  ).round(RoundingMode.halfUp);
  final ten = BigInt.from(10);
  return '${negative ? '-' : ''}${tenths ~/ ten}.${tenths % ten}';
}

/// 独立验证 [allocation]（卡 ID → 金额，按给定顺序），检查 [scenarios] 中每个情景；
/// `ok` = 结构检查通过且 [decisionScenarioId] 情景没有缺口。
///
/// 金额是 `int` 最小单位（类型保证，不会有浮点或截断）；协议入口另行拒绝浮点、布尔与字符串金额。
/// 不在计划内的卡记为 `UNKNOWN_CARD` 违规；其余检查只覆盖已知卡。调用方应先做数据检查
/// （[dataIssues]），否则规则错误会以 [BillingRuleError] 抛出。
Verification verify(
  ModelInputs inputs,
  Map<String, int> allocation,
  Map<String, Scenario> scenarios,
  String decisionScenarioId,
) {
  if (!scenarios.containsKey(decisionScenarioId)) {
    throw ArgumentError.value(
      decisionScenarioId,
      'decisionScenarioId',
      'not among the scenarios',
    );
  }
  final req = inputs.request;
  final cards = <String, CardOption>{for (final c in inputs.cards) c.id: c};
  final layers = capacityLayers(inputs);
  final violations = <String>[];
  final alloc = <String, int>{
    for (final MapEntry(:key, :value) in allocation.entries)
      if (value != 0) key: value,
  };
  alloc.forEach((cardId, amount) {
    final card = cards[cardId];
    if (card == null) {
      violations.add(
        "UNKNOWN_CARD: ${pyRepr(cardId)} is not one of the plan's cards",
      );
      return;
    }
    if (amount < 0) {
      violations.add('$cardId: negative amount');
    }
    final (_, exclusion) = classify(card, inputs, layers: layers);
    if (exclusion != null) {
      violations.add('$cardId: ineligible (${exclusion.code})');
    }
    if (amount > card.capacity) {
      violations.add(
        '$cardId: amount $amount exceeds capacity ${card.capacity}',
      );
    }
    final perTxn = card.perTxnCap;
    if (perTxn != null && amount > perTxn) {
      violations.add(
        '$cardId: amount $amount exceeds per-transaction cap $perTxn',
      );
    }
    final minSplit = card.minSplit ?? req.minSplit;
    if (amount < minSplit) {
      violations.add('$cardId: amount $amount below minimum split $minSplit');
    }
  });
  var total = 0;
  for (final amount in alloc.values) {
    total += amount;
  }
  if (total != req.amount) {
    violations.add('amount conservation violated: $total != ${req.amount}');
  }
  if (alloc.length > req.k) {
    violations.add('uses ${alloc.length} cards > allowed ${req.k}');
  }
  final accountSums = <String, int>{};
  final poolSums = <String, int>{};
  alloc.forEach((cardId, amount) {
    final card = cards[cardId];
    if (card == null) {
      return;
    }
    if (layers.account.containsKey(card.accountId)) {
      accountSums[card.accountId] = (accountSums[card.accountId] ?? 0) + amount;
    }
    final poolId = card.poolId;
    if (poolId != null && poolId.isNotEmpty) {
      poolSums[poolId] = (poolSums[poolId] ?? 0) + amount;
    }
  });
  accountSums.forEach((accountId, sum) {
    final cap = layers.account[accountId]!;
    if (sum > cap) {
      violations.add(
        'credit account $accountId: $sum exceeds shared capacity $cap',
      );
    }
  });
  poolSums.forEach((poolId, sum) {
    final cap = layers.pool[poolId];
    if (cap == null) {
      violations.add('pool $poolId: no capacity snapshot');
    } else if (sum > cap) {
      // 扣除成员卡的预授权与预留后、截零的容量（§12.3）
      violations.add('pool $poolId: $sum exceeds shared capacity $cap');
    }
  });
  // 计划外的卡没有账期规则也没有还款账户；它已是 UNKNOWN_CARD 违规（分配被拒），以下的现金
  // 检查、缓冲、费用与分配行只覆盖已知卡。
  final known = <String, int>{
    for (final MapEntry(:key, :value) in alloc.entries)
      if (cards.containsKey(key)) key: value,
  };
  final infos = <String, CardPlanInfo>{
    for (final cardId in known.keys)
      cardId: deriveCardInfo(cards[cardId]!, req),
  };
  infos.forEach((cardId, info) {
    final snapshot = inputs.snapshots[info.card.repayFrom];
    if (snapshot != null && info.repayOn < snapshot.asOf) {
      violations.add(
        'PLANNED_REPAYMENT_BEFORE_SNAPSHOT: $cardId repays on ${info.repayOn}, before '
        'the ${info.card.repayFrom} snapshot of ${snapshot.asOf} (applied on that day)',
      );
    }
  });
  final structuralOk = violations.isEmpty;
  final feesByCard = <String, int>{
    for (final MapEntry(:key, :value) in known.entries)
      key: cardFee(cards[key]!, value),
  };
  final checks = <String, ScenarioCheck>{
    for (final MapEntry(:key, :value) in scenarios.entries)
      key: checkScenario(inputs, infos, known, value, feesByCard),
  };
  var bufferNumerator = BigInt.zero;
  infos.forEach((cardId, info) {
    bufferNumerator +=
        BigInt.from(known[cardId]!) * BigInt.from(info.bufferDays);
  });
  var fees = 0;
  var benefit = 0;
  var potential = 0;
  final lines = <AllocationLine>[];
  known.forEach((cardId, amount) {
    final card = cards[cardId]!;
    final fee = feesByCard[cardId]!;
    var b = card.verifiedBenefitRate.isZero
        ? 0
        : applyRate(amount, card.verifiedBenefitRate, RoundingMode.down);
    final cap = card.verifiedBenefitCap;
    if (cap != null && cap < b) {
      b = cap;
    }
    final p = card.potentialBenefitRate.isZero
        ? 0
        : applyRate(amount, card.potentialBenefitRate, RoundingMode.down);
    fees += fee;
    benefit += b;
    potential += p;
    final info = infos[cardId]!;
    lines.add(
      AllocationLine(
        card: cardId,
        amount: amount,
        statementDate: info.cycle.statementDate,
        dueDate: info.cycle.dueDate,
        repayOn: info.repayOn,
        repayFrom: card.repayFrom,
        bufferDays: info.bufferDays,
        fee: fee,
        verifiedBenefit: b,
        potentialBenefit: p,
        cycleAssumptions: List<String>.of(info.cycle.assumptions),
        alternativeCycles: [
          for (final c in info.allCycles.skip(1)) (c.statementDate, c.dueDate),
        ],
      ),
    );
  });
  return Verification(
    ok: structuralOk && checks[decisionScenarioId]!.ok,
    structuralOk: structuralOk,
    violations: violations,
    decisionScenario: decisionScenarioId,
    checks: checks,
    weightedBufferDays: weightedBufferText(bufferNumerator, req.amount),
    fees: fees,
    verifiedBenefit: benefit,
    potentialBenefit: potential,
    lines: lines,
  );
}
