// 测 InstallmentCost 用到的 irrMonthly（有理数二分）在不同期数下的耗时（JIT 与 AOT 各测）。
import 'package:cardflow_domain/cardflow_domain.dart';

void main() {
  for (final periods in <int>[3, 6, 12, 24, 36, 60]) {
    final rate = Rational.parseDecimal('0.006');
    final flows = installmentCashFlows(1234567, periods, rate);
    final sw = Stopwatch()..start();
    final irr = irrMonthly(installmentIrrFlows(1234567, flows));
    final eff = annualize(irr).effectiveCompound;
    sw.stop();
    print('periods=$periods irr+annualize ms=${sw.elapsedMilliseconds} '
        'irr~${decimalText(Rational((irr * Rational(BigInt.from(10).pow(12))).round(RoundingMode.halfUp), BigInt.from(10).pow(12)))} '
        'effective~${decimalText(Rational((eff * Rational(BigInt.from(10).pow(8))).round(RoundingMode.halfUp), BigInt.from(10).pow(8)))}');
  }
}
