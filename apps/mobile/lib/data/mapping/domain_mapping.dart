/// 数据层 → 领域对象的映射（I-1a）：规则版本行 → `BillingRule`；预测账期与 3 期预览；额度快照
/// 与授信池 → `CardOption`/`ModelInputs` → `capacityLayers`（三层容量）。
///
/// 领域包本身不读写数据库；这里只做映射与少量数据层语义（入账日的截止时点、临时额度到期、
/// 预授权是否已含在可用额里），计算一律交给领域包。
library;

import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../time/business_tz.dart';

/// `YYYY-MM-DD` → [LocalDate]；空为 null。
LocalDate? parseOptionalDate(String? text) =>
    text == null ? null : LocalDate.parse(text);

/// 规则版本行 → 领域包 [BillingRule]（`ruleId` 用版本行的 id）。
///
/// 审核状态映射：`user_declared`、`expired`（由用户声明的版本封口而来）→ `user_declared`；
/// `draft`、`in_review` → `draft`。
BillingRule billingRuleFromRow(BillingRuleVersionRow row) {
  final DueRule due = row.dueKind == DueKind.fixedDay.code
      ? DueRule.fixedDay(day: row.dueDay!, monthOffset: row.dueMonthOffset)
      : DueRule.daysAfterStatement(
          days: row.dueDays!,
          dayKind: row.dueDayKind == DayKind.business.code
              ? DayKind.business
              : DayKind.calendar,
        );
  return BillingRule(
    ruleId: row.id,
    statementDay: row.statementDay,
    due: due,
    statementDayInclusive: row.statementDayInclusive,
    holidayRollover: row.holidayRollover == HolidayRollover.nextBusinessDay.code
        ? HolidayRollover.nextBusinessDay
        : HolidayRollover.none,
    effectiveFrom: parseOptionalDate(row.effectiveFrom),
    effectiveTo: parseOptionalDate(row.effectiveTo),
    source: row.source,
    verifiedOn: parseOptionalDate(row.verifiedOn),
    status: switch (row.reviewStatus) {
      'draft' || 'in_review' => RuleStatus.draft,
      _ => RuleStatus.userDeclared,
    },
  );
}

/// 规则版本的截止时点（空为 null）。
CutoffTime? cutoffOf(BillingRuleVersionRow row) {
  final text = row.cutoffTime;
  return text == null ? null : CutoffTime.parse(text);
}

/// 交易在银行的入账时点 [postedAt] → 入账日：按账户业务时区换算，晚于该日生效版本的截止时点
/// 则加一天（F-19）。版本按入账当天的业务日期选择（领域包 `selectRule`）。
LocalDate postingDateFor(
  Timestamp postedAt, {
  required CreditAccountRow account,
  required List<BillingRuleVersionRow> versions,
}) {
  final zone = businessTimeZoneOf(account.businessTz);
  final businessDate = businessDateOf(postedAt, zone);
  if (versions.isEmpty) {
    return businessDate;
  }
  final selected = selectRule(
    versions.map(billingRuleFromRow).toList(),
    businessDate,
  );
  final row = versions.firstWhere((r) => r.id == selected.ruleId);
  return postingDateOf(postedAt, zone, cutoff: cutoffOf(row));
}

/// 账期预测的结果。
sealed class CycleForecast {
  const CycleForecast();
}

/// 没有任何规则版本：显示"未设置"并引导到 P-04。
final class ForecastNoRule extends CycleForecast {
  const ForecastNoRule();
}

/// 规则给不出账期（到期不晚于账单日、需要工作日日历、版本不覆盖等）：显示"规则非法，无法计算账期"。
final class ForecastInvalid extends CycleForecast {
  const ForecastInvalid(this.error);

  /// 领域包的错误消息（英文，与 Python 一致；只用于诊断，不直接给用户看）。
  final String error;
}

/// 预测账期（未出账）：入账窗口内全部可能账期，最早到期在前（多于一个 = 可能账期）。
final class ForecastPredicted extends CycleForecast {
  const ForecastPredicted(this.cycles, {required this.ruleVersionId});

  final List<Cycle> cycles;

  /// 计算所用的版本 id。
  final String ruleVersionId;

  /// 保守账期（最早到期）。
  Cycle get conservative => cycles.first;
}

/// 交易日 [txnDate] 的预测账期：用在该日生效的版本（`selectRule`）及其入账延迟区间，调用领域包
/// `cyclesForTransaction`。没有版本 → [ForecastNoRule]；任何 [BillingRuleError] → [ForecastInvalid]。
CycleForecast forecastCycles(
  List<BillingRuleVersionRow> versions,
  LocalDate txnDate,
) {
  if (versions.isEmpty) {
    return const ForecastNoRule();
  }
  try {
    final rules = versions.map(billingRuleFromRow).toList();
    final selected = selectRule(rules, txnDate);
    final row = versions.firstWhere((r) => r.id == selected.ruleId);
    final cycles = cyclesForTransaction(
      selected,
      txnDate,
      postingDelayMin: row.postingDelayMinDays,
      postingDelayMax: row.postingDelayMaxDays,
    );
    return ForecastPredicted(cycles, ruleVersionId: row.id);
  } on BillingRuleError catch (error) {
    return ForecastInvalid(error.message);
  }
}

/// 今天及以前最近的预测账单日与它的到期日（卡账首页"记本期账单"的默认账单日；有账单出了而没录入时的提示）。
///
/// 先求今天入账所属的账单日 S（领域包 `statementDateForPosting`，含当天归属规则）：S 就是今天时取今天，否则取
/// S 的上一个月的账单日（月末截断）。到期日用该账单日生效的版本（`selectRule` + `dueDateForStatement`）。没有版本
/// 或规则给不出账期时为 null。
Cycle? recentStatementCycle(
  List<BillingRuleVersionRow> versions,
  LocalDate today,
) {
  if (versions.isEmpty) {
    return null;
  }
  try {
    final rules = versions.map(billingRuleFromRow).toList();
    final current = selectRule(rules, today);
    final next = statementDateForPosting(current, today);
    final LocalDate recent;
    if (next == today) {
      recent = today;
    } else {
      final (year, month) = addMonths(next, -1);
      recent = clampDay(year, month, current.statementDay);
    }
    final rule = selectRule(rules, recent);
    return Cycle(recent, dueDateForStatement(rule, recent), rule.ruleId);
  } on BillingRuleError {
    return null;
  }
}

/// P-04 的"3 期预览"：从入账日 [from] 起的连续 [count] 个账期（账单日与到期日）。第一个是 [from]
/// 当天入账所属的账期，之后每个从上一个账单日的次日开始（次日总是落在下一期，无论当天归属开关）。
/// 规则给不出账期时抛领域包的 [BillingRuleError]。
List<Cycle> previewCycles(BillingRule rule, LocalDate from, {int count = 3}) {
  final cycles = <Cycle>[];
  var posting = from;
  for (var i = 0; i < count; i++) {
    final cycle = cycleForPosting(rule, posting);
    cycles.add(cycle);
    posting = cycle.statementDate.addDays(1);
  }
  return cycles;
}

/// 快照在日期 [on] 可用于新增消费的银行可用额原值（可为负）：临时额度在到期日**当天起**不再
/// 计入（F-27；"到期日"按保守口径理解为当天已失效）。
int availableOn(LimitSnapshotRow snapshot, LocalDate on) {
  final expires = parseOptionalDate(snapshot.tempExpiresOn);
  if (snapshot.tempMinor > 0 && expires != null && on >= expires) {
    return snapshot.availableRawMinor - snapshot.tempMinor;
  }
  return snapshot.availableRawMinor;
}

/// 快照未包含的预授权（F-25）：银行显示的可用额已扣除预授权（`includes_holds`）时为 0，
/// 否则为 `holds_minor`（在账户层只扣一次）。
int uncountedHoldsOf(LimitSnapshotRow snapshot) =>
    snapshot.includesHolds ? 0 : snapshot.holdsMinor;

/// 一个信用账户在某币种上的容量输入。
@immutable
final class AccountCapacityInput {
  const AccountCapacityInput({
    required this.accountId,
    required this.snapshot,
    required this.cards,
    this.poolId,
    this.on,
  });

  final String accountId;

  /// 判断临时额度是否到期所用的日期（账户业务时区里的今天）；空时用模型的 [CapacityModel.on]。
  final LocalDate? on;

  /// 该币种子账户的最新快照；没有时该账户容量未知（不进入模型）。
  final LimitSnapshotRow? snapshot;

  /// 账户的卡片（只用未停用的：已启用、已冻结）。
  final List<CardRow> cards;

  final String? poolId;
}

/// 一个授信池的容量输入。
@immutable
final class PoolCapacityInput {
  const PoolCapacityInput({
    required this.poolId,
    required this.sharedLimitMinor,
    required this.memberAccountIds,
  });

  final String poolId;
  final int sharedLimitMinor;
  final List<String> memberAccountIds;
}

/// 只用于容量计算的占位规则：`capacityLayers` 与 `cardLimit` 不读账期规则，但 [CardOption]
/// 的构造要求有一条。
final BillingRule _capacityOnlyRule = BillingRule(
  ruleId: 'capacity-only',
  statementDay: 1,
  due: const DueRule.fixedDay(day: 2),
);

/// 一个币种在日期 [on] 的额度容量模型：账户（经其卡片）→ [CardOption]，授信池 → 池可用原值，
/// 交给领域包 [capacityLayers]（engine-spec §12.3：卡 ≤ 信用账户 ≤ 池，逐层截零）。
///
/// 映射规则：
/// - 每张未停用的卡一个 [CardOption]，同一账户的卡报告同一可用额（账户共享，F-21），未计入的预授权
///   只记在第一张卡上（协议：每笔预授权只记在账户的一张卡上）；没有未停用卡片的账户用一个以账户 id
///   为名的占位选项，账户容量照样计算；
/// - 卡的可用额 = [availableOn]（临时额度到期回落，F-27），未计入预授权 = [uncountedHoldsOf]（F-25）；
/// - 池可用原值 = 池上限 − Σ 成员账户该币种子账户最新快照的 `used_minor`，可为负（data-model §10.14）；
///   有成员缺快照时池可用未知，不进入模型（不以 0 代替）；
/// - 只建本币种的池；没有现金账户与计划预留（I-1b/I-2），`repayFrom` 为空串。
final class CapacityModel {
  CapacityModel._(
    this.currency,
    this.on,
    this.inputs,
    this.layers,
    this._optionsByAccount,
    this._poolRaw,
    this._poolMissing,
  );

  factory CapacityModel.build({
    required String currency,
    required LocalDate on,
    required List<AccountCapacityInput> accounts,
    List<PoolCapacityInput> pools = const <PoolCapacityInput>[],
  }) {
    final byAccount = {for (final a in accounts) a.accountId: a};
    final poolRaw = <String, int>{};
    final poolMissing = <String, int>{};
    for (final pool in pools) {
      var used = 0;
      var missing = 0;
      for (final memberId in pool.memberAccountIds) {
        final snapshot = byAccount[memberId]?.snapshot;
        if (snapshot == null) {
          missing++;
        } else {
          used += snapshot.usedMinor;
        }
      }
      poolMissing[pool.poolId] = missing;
      if (missing == 0) {
        poolRaw[pool.poolId] = pool.sharedLimitMinor - used;
      }
    }

    final options = <CardOption>[];
    final optionsByAccount = <String, List<CardOption>>{};
    final request = PlanRequest(amount: 1, currency: currency, txnDate: on);
    for (final account in accounts) {
      final snapshot = account.snapshot;
      if (snapshot == null) {
        continue;
      }
      final raw = availableOn(snapshot, account.on ?? on);
      final holds = uncountedHoldsOf(snapshot);
      final poolId =
          account.poolId != null && poolRaw.containsKey(account.poolId)
          ? account.poolId
          : null;
      final usable = account.cards
          .where((c) => c.status == 'active' || c.status == 'frozen')
          .toList();
      final ids = usable.isEmpty
          ? <String>['account:${account.accountId}']
          : usable.map((c) => c.id).toList();
      final accountOptions = <CardOption>[
        for (var i = 0; i < ids.length; i++)
          CardOption(
            id: ids[i],
            accountId: account.accountId,
            name: ids[i],
            rawAvailable: raw,
            uncountedHolds: i == 0 ? holds : 0,
            billingRule: _capacityOnlyRule,
            repayFrom: '',
            poolId: poolId,
            statusOk: usable.isEmpty || usable[i].status == 'active',
          ),
      ];
      options.addAll(accountOptions);
      optionsByAccount[account.accountId] = accountOptions;
    }
    final inputs = ModelInputs(
      request: request,
      cards: options,
      pools: poolRaw,
      accounts: const <CashAccount>[],
      snapshots: const <String, Snapshot>{},
      events: const <CashEvent>[],
      horizonEnd: on,
    );
    return CapacityModel._(
      currency,
      on,
      inputs,
      capacityLayers(inputs),
      optionsByAccount,
      poolRaw,
      poolMissing,
    );
  }

  final String currency;
  final LocalDate on;

  /// 交给领域包的输入（测试与 I-2 复用）。
  final ModelInputs inputs;

  /// 领域包算出的共享容量层。
  final CapacityLayers layers;

  final Map<String, List<CardOption>> _optionsByAccount;
  final Map<String, int> _poolRaw;
  final Map<String, int> _poolMissing;

  /// 账户自身（卡层与账户层，不含池）的容量；没有快照时为 null。
  int? accountOwnCapacity(String accountId) {
    final options = _optionsByAccount[accountId];
    if (options == null) {
      return null;
    }
    final shared = layers.account[accountId];
    var best = 0;
    for (final option in options) {
      var cap = option.capacity;
      if (shared != null && shared < cap) {
        cap = shared;
      }
      if (cap > best) {
        best = cap;
      }
    }
    return best;
  }

  /// 账户可供新增消费的容量（卡、信用账户、池三层取最小，领域包 `cardLimit`）；没有快照时为 null。
  int? accountCapacity(String accountId) {
    final options = _optionsByAccount[accountId];
    if (options == null) {
      return null;
    }
    var best = 0;
    for (final option in options) {
      final (cap, _) = cardLimit(option, layers);
      if (cap > best) {
        best = cap;
      }
    }
    return best;
  }

  /// 池可用原值（池上限 − Σ 成员已用，可为负）；有成员缺快照时为 null。
  int? poolRawAvailable(String poolId) => _poolRaw[poolId];

  /// 缺快照的成员数。
  int poolMissingSnapshots(String poolId) => _poolMissing[poolId] ?? 0;

  /// 池层容量（截零、已扣成员的预授权）；未知时为 null。
  int? poolCapacity(String poolId) => layers.pool[poolId];

  /// 池内账户可用合计：min(池层容量, Σ 成员账户自身容量)（F-23：合计不超过池可用）。
  int? poolCombinedCapacity(String poolId, List<String> memberAccountIds) {
    final pool = poolCapacity(poolId);
    if (pool == null) {
      return null;
    }
    var sum = 0;
    for (final id in memberAccountIds) {
      sum += accountOwnCapacity(id) ?? 0;
    }
    return sum < pool ? sum : pool;
  }
}
