/// 分期：每期本金拆分、各期现金流、月 IRR 与年化（Python `engine/money.py` 的
/// `split_installments`、`installment_cash_flows`、`irr_monthly`、`annualize`，逐条同义）。
///
/// 只用 `int`、`BigInt` 与 [Rational]：IRR 用有理数在 [0, 1] 上二分，不用二进制浮点（ADR-008）。
/// 成本两种口径并列（bank-rules-spec §4、F-37）：名义 = 月费率 × 12（单利口径，不是"实际年化"）；
/// 实际年化 = 各期现金流的月 IRR 按复利折成年（`(1 + r)^12 − 1`）。
library;

import 'money.dart';
import 'rational.dart';

/// 尾差（各期按 HALF_UP 取整后与本金的差）加到哪一期（bank-rules-spec §2 InstallmentRule
/// `remainder_to`；建行商户分期 S15 是末期）。
enum RemainderTo {
  /// 末期（建行口径，默认）。
  last('last'),

  /// 首期。
  first('first');

  const RemainderTo(this.code);

  /// 协议与本地库中的写法。
  final String code;

  /// 按写法取值；未知写法抛 [ArgumentError]。
  static RemainderTo parse(String code) => values.firstWhere(
    (v) => v.code == code,
    orElse: () => throw ArgumentError.value(code, 'code', 'unknown remainder'),
  );
}

/// 每期本金（Python `split_installments`）：每期 = `HALF_UP(本金 / 期数)`，尾差加到末期（[RemainderTo.last]）
/// 或首期；Σ 各期 = 本金（守恒）。[periods] ≤ 0 抛 [ArgumentError]（Python：`ValueError("periods must be
/// >= 1")`）。
List<int> splitInstallments(
  int principalMinor,
  int periods, [
  RemainderTo remainderTo = RemainderTo.last,
]) {
  if (periods <= 0) {
    throw ArgumentError('periods must be >= 1');
  }
  final base = Rational.fromInt(
    principalMinor,
    periods,
  ).roundToInt(RoundingMode.halfUp);
  final parts = List<int>.filled(periods, base);
  final diff = principalMinor - base * periods;
  parts[remainderTo == RemainderTo.last ? periods - 1 : 0] += diff;
  var sum = 0;
  for (final p in parts) {
    sum += p;
  }
  if (sum != principalMinor) {
    throw StateError('installment split does not conserve the principal');
  }
  return parts;
}

/// 一期：期号（从 1 起）、本金、费用。
typedef InstallmentPeriod = ({int periodNo, int principal, int fee});

/// 各期现金流（Python `installment_cash_flows`）：本金按 [splitInstallments] 拆分；每期费用 =
/// `applyRate(本金总额, 每期费率, rounding)`（建行口径："每期分期利息 = 分期本金总额 × 每期分期利率"，
/// 每期相同，显式取整）。
List<InstallmentPeriod> installmentCashFlows(
  int principalMinor,
  int periods,
  Rational perPeriodRate, {
  RemainderTo remainderTo = RemainderTo.last,
  RoundingMode rateRounding = RoundingMode.halfUp,
}) {
  final parts = splitInstallments(principalMinor, periods, remainderTo);
  final fee = applyRate(principalMinor, perPeriodRate, rateRounding);
  return <InstallmentPeriod>[
    for (var k = 0; k < parts.length; k++)
      (periodNo: k + 1, principal: parts[k], fee: fee),
  ];
}

/// 现金流的一项：月序（0 = 放款当月）与金额（最小单位）。
typedef MonthlyFlow = ({int month, int amount});

/// [irrMonthly] 的默认精度：10^-12（Python `Decimal("1e-12")`）。
final Rational defaultIrrTolerance = Rational(
  BigInt.one,
  BigInt.from(10).pow(12),
);

/// `(1 + r)^t`（t 可为负）。
Rational _discountBase(Rational r, int t) {
  final base = Rational.one + r;
  var result = Rational.one;
  for (var i = 0; i < t.abs(); i++) {
    result = result * base;
  }
  return t < 0 ? Rational.one.dividedBy(result) : result;
}

/// 净现值 `Σ 金额 / (1 + r)^月序`（精确有理数）。
Rational monthlyNpv(List<MonthlyFlow> flows, Rational r) {
  var sum = Rational.zero;
  for (final f in flows) {
    sum += Rational.fromInt(f.amount).dividedBy(_discountBase(r, f.month));
  }
  return sum;
}

/// 月 IRR（Python `irr_monthly`）：对 [flows] 在 [0, 1] 上用有理数二分。
///
/// **符号约定以 Python 代码的行为为准**：月 0 的放款为**负**、第 1..n 月的各期还款为**正**（Python 的
/// docstring 写反了——按 docstring 的符号传入，代码会抛 `no positive IRR`）。`npv(0) < 0`（还款合计不超过
/// 本金）时抛 [ArgumentError]；至多 200 次，`hi − lo < tol` 时停，返回 `(lo + hi) / 2`。
Rational irrMonthly(List<MonthlyFlow> flows, {Rational? tol}) {
  final tolerance = tol ?? defaultIrrTolerance;
  var lo = Rational.zero;
  var hi = Rational.one;
  if (monthlyNpv(flows, lo).isNegative) {
    throw ArgumentError('no positive IRR: payments do not exceed principal');
  }
  final half = Rational.fromInt(1, 2);
  for (var i = 0; i < 200; i++) {
    final mid = (lo + hi) * half;
    if (monthlyNpv(flows, mid) > Rational.zero) {
      lo = mid;
    } else {
      hi = mid;
    }
    if (hi - lo < tolerance) {
      break;
    }
  }
  return (lo + hi) * half;
}

/// 分期计划的现金流（给 [irrMonthly]）：月 0 放款 `−本金`，第 k 月还 `本金_k + 费用_k`。
List<MonthlyFlow> installmentIrrFlows(
  int principalMinor,
  List<InstallmentPeriod> periods,
) => <MonthlyFlow>[
  (month: 0, amount: -principalMinor),
  for (final p in periods) (month: p.periodNo, amount: p.principal + p.fee),
];

/// 年化的两种口径（Python `annualize`）。
typedef AnnualizedRate = ({Rational nominalX12, Rational effectiveCompound});

/// 月利率 → 名义 `r × 12` 与复利 `(1 + r)^12 − 1`（Python `annualize`）。
AnnualizedRate annualize(Rational monthlyRate) => (
  nominalX12: monthlyRate.timesInt(12),
  effectiveCompound: _discountBase(monthlyRate, 12) - Rational.one,
);
