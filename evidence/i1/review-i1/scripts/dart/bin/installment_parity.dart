// 审查 R-I1：领域包分期模块与 Python money.py 的随机/边界对照（Python 结果在 JSON 里）。
// 用法：dart run bin/installment_parity.dart <cases.json>
import 'dart:convert';
import 'dart:io';

import 'package:cardflow_domain/cardflow_domain.dart';

/// 与 App `ledger_mapping.dart` 的 percentText 同一写法：比率 → 百分数，至多 4 位小数（HALF_UP）。
String percentText(Rational rate) {
  final scaled = (rate * Rational(BigInt.from(1000000))).round(RoundingMode.halfUp);
  return '${decimalText(Rational(scaled, BigInt.from(10000)))}%';
}

void main(List<String> args) {
  final cases = jsonDecode(File(args.single).readAsStringSync()) as List<Object?>;
  var split = 0, fees = 0, irr = 0, eff = 0, nom = 0, pct = 0, worstIrr = Rational.zero;
  final sw = Stopwatch()..start();
  for (final raw in cases) {
    final c = raw! as Map<String, Object?>;
    final principal = c['principal']! as int;
    final periods = c['periods']! as int;
    final rate = Rational.parseDecimal(c['rate']! as String);
    final rem = RemainderTo.parse(c['remainder']! as String);
    final flows = installmentCashFlows(principal, periods, rate, remainderTo: rem);
    if ('${flows.map((f) => f.principal).toList()}' != '${c['split']}') split++;
    if ('${flows.map((f) => f.fee).toList()}' != '${c['fees']}') fees++;
    final r = irrMonthly(installmentIrrFlows(principal, flows));
    final diff = (r - Rational.parseDecimal(c['irr']! as String));
    final absDiff = diff.isNegative ? -diff : diff;
    if (absDiff > worstIrr) worstIrr = absDiff;
    if (absDiff > Rational(BigInt.one, BigInt.from(10).pow(9))) irr++;
    final ann = annualize(r);
    String tenDp(Rational x) => decimalText(
        Rational((x * Rational(BigInt.from(10).pow(10))).round(RoundingMode.halfUp), BigInt.from(10).pow(10)));
    if (tenDp(ann.effectiveCompound) != tenDp(Rational.parseDecimal(c['effective']! as String))) eff++;
    final nominal = annualize(rate).nominalX12;
    if (nominal != Rational.parseDecimal(c['nominal']! as String)) nom++;
    final p1 = '${percentText(ann.effectiveCompound)}|${percentText(nominal)}';
    String py(String k) => decimalText(Rational.parseDecimal(c[k]! as String));
    final p2 = '${py('effective_pct')}%|${py('nominal_pct')}%';
    if (p1 != p2) {
      pct++;
      print('PCT MISMATCH principal=$principal periods=$periods rate=${c['rate']}: dart=$p1 python=$p2');
    }
  }
  print('cases=${cases.length} split_mismatch=$split fee_mismatch=$fees irr_over_1e-9=$irr '
      'max|irr_dart-irr_python|<=1e-${_exp(worstIrr)} effective_10dp_mismatch=$eff nominal_mismatch=$nom '
      'percent_text_mismatch=$pct elapsed_ms=${sw.elapsedMilliseconds}');
}

int _exp(Rational x) {
  var e = 0;
  var t = Rational.one;
  while (x <= t.dividedBy(Rational.fromInt(10)) && e < 40) {
    t = t.dividedBy(Rational.fromInt(10));
    e++;
  }
  return e;
}
