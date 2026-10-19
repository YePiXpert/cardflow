/// 数据层 → 领域对象映射（I-1c）：交易的账期归属（领域包 `resolveCycle`/`cyclesForTransaction`）、
/// 账单余额与负债四分法（R-STMT-02、F-30）、分期的各期与成本（领域包 `installment.dart`，F-36/F-37）、
/// 还款的入账日与额度释放（F-28/F-31）。
///
/// 只做映射与少量数据层语义，金额计算一律是整数最小单位，费率与成本是 [Rational]（不用 double）。
library;

import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../repositories/ledger_models.dart';
import '../time/business_tz.dart';
import 'domain_mapping.dart';

// ---------------------------------------------------------------------------
// 账单余额
// ---------------------------------------------------------------------------

/// 账单版本的"本期应还"：有贷方余额（溢缴款）时为 0（F-38），否则为新余额（负数按 0）。
int amountDueOf(StatementVersionRow version) {
  if ((version.creditBalanceMinor ?? 0) > 0) {
    return 0;
  }
  return version.newBalanceMinor > 0 ? version.newBalanceMinor : 0;
}

/// 账单版本的贷方余额（溢缴款，≥0）：录入了贷方余额时用它，否则新余额为负时取其绝对值。
int creditBalanceOf(StatementVersionRow version) {
  final explicit = version.creditBalanceMinor;
  if (explicit != null && explicit > 0) {
    return explicit;
  }
  return version.newBalanceMinor < 0 ? -version.newBalanceMinor : 0;
}

/// 还款在信用账户业务时区里的入账日（F-31：负债按 `credit_posted_at` 的日期核销；截止时点按该日生效
/// 的规则版本，`postingDateFor`）。没有入账时点时为 null。
LocalDate? creditDateOf(
  RepaymentRow repayment, {
  required CreditAccountRow account,
  required List<BillingRuleVersionRow> versions,
}) {
  final text = repayment.creditPostedAt;
  if (text == null) {
    return null;
  }
  try {
    return postingDateFor(
      Timestamp.parse(text),
      account: account,
      versions: versions,
    );
  } on BillingRuleError {
    return businessDateOf(
      Timestamp.parse(text),
      businessTimeZoneOf(account.businessTz),
    );
  }
}

/// 一组未处理的疑似重复还款（F-32）：负债只核销一次，直到用户处理。
typedef DuplicatePair = (String, String);

/// 某账单的还款分配合计：只算已按银行入账核销的还款（`credit_posted`/`bank_confirmed`，F-31），入账日
/// 不晚于 [on]；[bankConfirmedOnly] 为真时只算银行确认的（结清只由它触发，PRD §6.2）。未处理的疑似重复
/// 两笔都已核销时只计较大的一笔（F-32）。已作废、已冲正、失败的还款不计（R2-15）。
int paidOnStatement({
  required String statementId,
  required Iterable<RepaymentAllocationRow> allocations,
  required Map<String, RepaymentRow> repayments,
  required Map<String, LocalDate?> creditDates,
  required LocalDate on,
  List<DuplicatePair> openDuplicates = const <DuplicatePair>[],
  bool bankConfirmedOnly = false,
}) {
  final byRepayment = <String, int>{};
  for (final a in allocations) {
    if (a.statementId != statementId) {
      continue;
    }
    final r = repayments[a.repaymentId];
    if (r == null || r.deletedAt != null) {
      continue;
    }
    final status = RepaymentStatus.of(r.status);
    final counts = bankConfirmedOnly
        ? status == RepaymentStatus.bankConfirmed
        : status.isCredited;
    final date = creditDates[r.id];
    if (!counts || date == null || date > on) {
      continue;
    }
    byRepayment[r.id] = (byRepayment[r.id] ?? 0) + a.amountMinor;
  }
  var total = 0;
  for (final amount in byRepayment.values) {
    total += amount;
  }
  for (final (a, b) in openDuplicates) {
    final x = byRepayment[a];
    final y = byRepayment[b];
    if (x != null && y != null) {
      total -= x < y ? x : y;
    }
  }
  return total;
}

/// 一份账单在某日的余额（当前版本）。
@immutable
final class StatementBalance {
  const StatementBalance({
    required this.statement,
    required this.current,
    required this.amountDue,
    required this.creditBalance,
    required this.credited,
    required this.bankConfirmed,
  });

  final StatementRow statement;
  final StatementVersionRow current;

  /// 本期应还（当前版本；有贷方余额时为 0）。
  final int amountDue;

  /// 贷方余额（溢缴款）。
  final int creditBalance;

  /// 银行已入账的还款分配（疑似重复只计一次）。
  final int credited;

  /// 银行确认的还款分配。
  final int bankConfirmed;

  /// 剩余应还（不小于 0）。
  int get remaining => amountDue > credited ? amountDue - credited : 0;

  StatementStatus get status => StatementStatus.of(statement.status);

  LocalDate get statementDate => LocalDate.parse(statement.statementDate);

  LocalDate get dueDate => LocalDate.parse(statement.dueDate);
}

// ---------------------------------------------------------------------------
// 交易的账期归属
// ---------------------------------------------------------------------------

/// 一笔交易的账期。
sealed class TxnCycle {
  const TxnCycle();

  /// 可能的账单日（多于一个 = 入账不确定）；没有规则或规则非法时为空。
  List<LocalDate> get statementDates;
}

/// 入账日已知：领域包 `resolveCycle`（已出账单优先，否则预测账期）。
final class TxnCycleKnown extends TxnCycle {
  const TxnCycleKnown(this.cycle);

  final Cycle cycle;

  /// 来自已出账单（而不是预测）。
  bool get fromIssued => cycle.ruleId.startsWith('issued:');

  @override
  List<LocalDate> get statementDates => <LocalDate>[cycle.statementDate];
}

/// 入账日未知：入账延迟区间内的全部可能账期（领域包 `cyclesForTransaction`，F-15）。
final class TxnCyclePossible extends TxnCycle {
  const TxnCyclePossible(this.cycles);

  /// 最早到期在前（保守取第一个）。
  final List<Cycle> cycles;

  @override
  List<LocalDate> get statementDates => <LocalDate>[
    for (final c in cycles) c.statementDate,
  ];
}

/// 没有账期规则。
final class TxnCycleNoRule extends TxnCycle {
  const TxnCycleNoRule();

  @override
  List<LocalDate> get statementDates => const <LocalDate>[];
}

/// 规则给不出账期（不生效、到期不晚于账单日、需要日历）。
final class TxnCycleInvalid extends TxnCycle {
  const TxnCycleInvalid(this.error);

  final String error;

  @override
  List<LocalDate> get statementDates => const <LocalDate>[];
}

/// 交易在账户业务时区里的交易日。
LocalDate txnDateOf(CardTransactionRow txn, BusinessTimeZone zone) =>
    businessDateOf(Timestamp.parse(txn.txnAt), zone);

/// 交易的账期归属：入账日已知 → `resolveCycle`（已出账单 [issued] 优先）；未知 → 交易日在入账延迟区间
/// 内的可能账期（每个可能账期的账单日若已出账，用已出账单的到期日）。
TxnCycle transactionCycle(
  CardTransactionRow txn, {
  required List<BillingRuleVersionRow> versions,
  required List<IssuedStatement> issued,
  required BusinessTimeZone zone,
}) {
  if (versions.isEmpty) {
    return const TxnCycleNoRule();
  }
  final rules = versions.map(billingRuleFromRow).toList();
  try {
    final posted = txn.postedOn;
    if (posted != null) {
      return TxnCycleKnown(
        resolveCycle(rules, issued, LocalDate.parse(posted)),
      );
    }
    final date = txnDateOf(txn, zone);
    final rule = selectRule(rules, date);
    final row = versions.firstWhere((v) => v.id == rule.ruleId);
    final cycles = cyclesForTransaction(
      rule,
      date,
      postingDelayMin: row.postingDelayMinDays,
      postingDelayMax: row.postingDelayMaxDays,
    );
    final resolved = <Cycle>[
      for (final c in cycles) _issuedFor(issued, c.statementDate) ?? c,
    ];
    return resolved.length == 1
        ? TxnCycleKnown(resolved.single)
        : TxnCyclePossible(resolved);
  } on BillingRuleError catch (error) {
    return TxnCycleInvalid(error.message);
  }
}

Cycle? _issuedFor(List<IssuedStatement> issued, LocalDate statementDate) {
  for (final s in issued) {
    if (s.statementDate == statementDate) {
      return Cycle(s.statementDate, s.dueDate, 'issued:${s.source}');
    }
  }
  return null;
}

/// 交易是否已经出账：所有可能账期的账单日都不晚于最近一期已出账单的账单日 [latestIssued]。没有规则时
/// 按入账日（未知时按交易日）与 [latestIssued] 比较（规则缺失时的近似，界面另有"账期规则未设置"）。
bool isBilled(
  CardTransactionRow txn,
  TxnCycle cycle,
  LocalDate? latestIssued, {
  required BusinessTimeZone zone,
}) {
  if (latestIssued == null) {
    return false;
  }
  final dates = cycle.statementDates;
  if (dates.isEmpty) {
    final posted = txn.postedOn;
    final day = posted == null ? txnDateOf(txn, zone) : LocalDate.parse(posted);
    return day <= latestIssued;
  }
  return dates.every((d) => d <= latestIssued);
}

// ---------------------------------------------------------------------------
// 负债四分法（R-STMT-02、F-30）
// ---------------------------------------------------------------------------

/// 一个币种子账户的负债四分法。总负债 = 已出账未还 + 未出账 + 未来分期本金（不含未计提的分期手续费）；
/// 本期应还、未出账、未来分期本金分列，不重复相加。
@immutable
final class LiabilityBreakdown {
  const LiabilityBreakdown({
    required this.currency,
    required this.latest,
    required this.unbilled,
    required this.futureInstallmentPrincipal,
    required this.futureInstallmentFees,
    required this.pendingRefunds,
  });

  final String currency;

  /// 最近一期已出账单（没有时为 null）。
  final StatementBalance? latest;

  /// 未出账：最近一期账单之后的交易（已转分期的原交易、还款入账行、待核对的退款不计）。
  final int unbilled;

  /// 未来分期本金：尚未出账的各期本金（不含费用）。
  final int futureInstallmentPrincipal;

  /// 尚未出账的各期手续费（未计提，不计入总负债；R-STMT-01 的"未来分期还款"用）。
  final int futureInstallmentFees;

  /// 待核对的退款（未计入未出账，F-34）。
  final int pendingRefunds;

  /// 本期应还（最近一期账单的剩余应还；有贷方余额时为 0）。
  int get currentDue => latest?.remaining ?? 0;

  /// 贷方余额（溢缴款）。
  int get creditBalance => latest?.creditBalance ?? 0;

  /// 已出账未还（有贷方余额时为负：负债为负，R-STMT-11）。
  int get billedUnpaid => creditBalance > 0 ? -creditBalance : currentDue;

  /// 总负债。
  int get total => billedUnpaid + unbilled + futureInstallmentPrincipal;
}

/// 负债四分法的计算（一个币种子账户）：[balances] 是该子账户全部账单在某日的余额（按账单日升序），
/// [transactions] 是该子账户未删除的交易及其账期，[coveredByPlans] 是已转分期（计划未作废）的交易，
/// [refundIncluded] 是已确认冲抵应还的退款（其余退款待核对，不计入），[periods] 是该子账户进行中计划的各期。
LiabilityBreakdown liabilityOf({
  required String currency,
  required List<StatementBalance> balances,
  required List<(CardTransactionRow, TxnCycle)> transactions,
  required Set<String> coveredByPlans,
  required Set<String> refundIncluded,
  required List<InstallmentScheduleRow> periods,
  required BusinessTimeZone zone,
}) {
  final latest = balances.isEmpty ? null : balances.last;
  final latestDate = latest?.statementDate;
  var unbilled = 0;
  var pendingRefunds = 0;
  for (final (txn, cycle) in transactions) {
    final type = TxnType.of(txn.txnType);
    if (txn.deletedAt != null ||
        txn.status == TxnStatus.reversed.code ||
        type == TxnType.repayment ||
        type == TxnType.installmentPrincipal ||
        type == TxnType.installmentFee ||
        coveredByPlans.contains(txn.id)) {
      continue;
    }
    if (isBilled(txn, cycle, latestDate, zone: zone)) {
      continue;
    }
    if (type == TxnType.refund && !refundIncluded.contains(txn.id)) {
      pendingRefunds += -txn.amountMinor;
      continue;
    }
    unbilled += txn.amountMinor;
  }
  var principal = 0;
  var fees = 0;
  for (final p in periods) {
    if (p.status == InstallmentPeriodStatus.scheduled.code) {
      principal += p.principalMinor;
      fees += p.feeMinor;
    }
  }
  return LiabilityBreakdown(
    currency: currency,
    latest: latest,
    unbilled: unbilled,
    futureInstallmentPrincipal: principal,
    futureInstallmentFees: fees,
    pendingRefunds: pendingRefunds,
  );
}

// ---------------------------------------------------------------------------
// 分期（F-36/F-37）
// ---------------------------------------------------------------------------

/// 分期计划条款 → 各期本金与费用（领域包 `installment.dart`）。
///
/// 每期收取：`installmentCashFlows`（与 Python `money.py` 同义）。首期一次收取：本金同样按
/// `splitInstallments` 拆分，手续费总额 = `applyRate(本金总额, 每期费率 × 期数, HALF_UP)` 在第 1 期收取
/// （Python 没有这种方式，本地按此约定，见 README 偏离）。
List<InstallmentPeriod> installmentPeriodsOf({
  required int principalMinor,
  required int periods,
  required Rational perPeriodRate,
  required InstallmentFeeMode feeMode,
  required RemainderTo remainderTo,
}) {
  if (feeMode == InstallmentFeeMode.perPeriod) {
    return installmentCashFlows(
      principalMinor,
      periods,
      perPeriodRate,
      remainderTo: remainderTo,
    );
  }
  final parts = splitInstallments(principalMinor, periods, remainderTo);
  final total = applyRate(
    principalMinor,
    perPeriodRate.timesInt(periods),
    RoundingMode.halfUp,
  );
  return <InstallmentPeriod>[
    for (var k = 0; k < parts.length; k++)
      (periodNo: k + 1, principal: parts[k], fee: k == 0 ? total : 0),
  ];
}

/// 分期成本（F-37）：名义 = 每期费率 × 12（不是实际年化）；实际年化 = 各期现金流的月 IRR 按复利折成年。
@immutable
final class InstallmentCost {
  const InstallmentCost({
    required this.perPeriodRate,
    required this.nominal,
    required this.monthlyIrr,
    required this.effective,
  });

  /// 各期（本金 + 费用）的成本。
  factory InstallmentCost.of({
    required int principalMinor,
    required Rational perPeriodRate,
    required List<InstallmentPeriod> periods,
  }) {
    final irr = irrMonthly(installmentIrrFlows(principalMinor, periods));
    return InstallmentCost(
      perPeriodRate: perPeriodRate,
      nominal: annualize(perPeriodRate).nominalX12,
      monthlyIrr: irr,
      effective: annualize(irr).effectiveCompound,
    );
  }

  final Rational perPeriodRate;

  /// 名义年化（每期费率 × 12）。
  final Rational nominal;

  /// 各期现金流的月 IRR（有理数二分）。
  final Rational monthlyIrr;

  /// 实际年化（复利）：(1 + 月 IRR)^12 − 1。
  final Rational effective;
}

/// 比率 → 百分数文本（保留至多 4 位小数，HALF_UP；领域包 `decimalText`）：0.18 → `18%`，
/// 0.367570… → `36.7571%`。
String percentText(Rational rate) {
  final scaled = (rate * Rational(BigInt.from(1000000))).round(
    RoundingMode.halfUp,
  );
  return '${decimalText(Rational(scaled, BigInt.from(10000)))}%';
}

// ---------------------------------------------------------------------------
// 额度释放（F-28）
// ---------------------------------------------------------------------------

/// 还款释放的额度：只有银行入账（`credit_posted`/`bank_confirmed`）且入账日晚于额度快照日 [snapshotDate]
/// （更早的已经反映在快照的可用额里）、并且 `入账日 + 释放时滞 ≤ on` 的还款才释放。释放时滞 [releaseLagDays]
/// 来自账户规则；未知（null）时保守地一律不释放（bank-rules-spec §5、R-CARD-06）。本期账户规则里还没有释放
/// 时滞（LimitRule 未建），所以 App 里总是按"未知"处理。
int releasedRepaymentsOn({
  required Iterable<RepaymentRow> repayments,
  required Map<String, LocalDate?> creditDates,
  required LocalDate snapshotDate,
  required LocalDate on,
  required int? releaseLagDays,
}) {
  if (releaseLagDays == null) {
    return 0;
  }
  var released = 0;
  for (final r in repayments) {
    if (r.deletedAt != null || !RepaymentStatus.of(r.status).isCredited) {
      continue;
    }
    final date = creditDates[r.id];
    if (date == null || date <= snapshotDate) {
      continue;
    }
    if (date.addDays(releaseLagDays) <= on) {
      released += r.amountMinor;
    }
  }
  return released;
}
